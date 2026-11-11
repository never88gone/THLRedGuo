import 'dart:async';
import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';
import 'package:flutter_js/javascript_runtime.dart';
import 'package:flutter_js/javascriptcore/binding/js_object_ref.dart'
    as js_object;
import 'package:flutter_js/javascriptcore/flutter_jscore.dart';
import 'package:flutter_js/javascriptcore/jscore_bindings.dart';
import 'package:flutter_js/js_eval_result.dart';

class SafeJavascriptCoreRuntime extends JavascriptRuntime {
  static final Map<int, SafeJavascriptCoreRuntime> _instances = {};

  late final Pointer _contextGroup;
  late final Pointer _globalContext;
  late final Pointer _globalObject;
  late final JSContext context;

  final Set<Timer> _timers = {};
  bool _isDisposed = false;
  int _promiseSequence = 0;

  bool get isDisposed => _isDisposed;

  SafeJavascriptCoreRuntime() {
    _contextGroup = jSContextGroupCreate();
    _globalContext = jSGlobalContextCreateInGroup(_contextGroup, nullptr);
    _globalObject = jSContextGetGlobalObject(_globalContext);
    context = JSContext(_globalContext);
    _instances[_globalContext.address] = this;

    final funcNameCString = 'sendMessage'.toNativeUtf8();
    final funcNameJs = jSStringCreateWithUTF8CString(funcNameCString);
    try {
      final functionObject = jSObjectMakeFunctionWithCallback(
        _globalContext,
        funcNameJs,
        Pointer.fromFunction(sendMessageBridgeFunction),
      );
      jSObjectSetProperty(
        _globalContext,
        _globalObject,
        funcNameJs,
        functionObject,
        js_object.JSPropertyAttributes.kJSPropertyAttributeNone,
        nullptr,
      );
    } finally {
      jSStringRelease(funcNameJs);
      calloc.free(funcNameCString);
    }

    init();
    _installSafeSetTimeoutHandler();
  }

  void _installSafeSetTimeoutHandler() {
    final channels =
        JavascriptRuntime.channelFunctionsRegistered[getEngineInstanceId()];
    if (channels == null) return;
    channels['SetTimeout'] = (dynamic args) {
      if (_isDisposed || args is! Map) return;
      final duration = args['timeout'] is int ? args['timeout'] as int : 0;
      final idx = args['timeoutIndex']?.toString();
      if (idx == null || idx.isEmpty) return;
      late final Timer timer;
      timer = Timer(Duration(milliseconds: duration < 0 ? 0 : duration), () {
        _timers.remove(timer);
        if (_isDisposed) return;
        evaluate('''
          (function() {
            var fn = __NATIVE_FLUTTER_JS__setTimeoutCallbacks[${jsonEncode(idx)}];
            if (typeof fn === 'function') { fn.call(); }
            delete __NATIVE_FLUTTER_JS__setTimeoutCallbacks[${jsonEncode(idx)}];
          })();
        ''');
      });
      _timers.add(timer);
    };
  }

  @override
  void initChannelFunctions() {
    if (_isDisposed) return;
    JavascriptRuntime.channelFunctionsRegistered[getEngineInstanceId()] = {};
  }

  @override
  int executePendingJob() {
    if (_isDisposed) return 0;
    evaluate('(function(){})();');
    return 0;
  }

  @override
  JsEvalResult evaluate(String js, {String? sourceUrl}) {
    if (_isDisposed) {
      return JsEvalResult(
        'ERROR: runtime disposed',
        nullptr,
        isError: true,
      );
    }

    final scriptCString = js.toNativeUtf8();
    final sourceUrlCString = sourceUrl?.toNativeUtf8();
    final scriptJs = jSStringCreateWithUTF8CString(scriptCString);
    final sourceUrlJs = sourceUrlCString != null
        ? jSStringCreateWithUTF8CString(sourceUrlCString)
        : nullptr;
    final exceptionPtr = calloc<Pointer>()..value = nullptr;

    try {
      final jsValueRef = jSEvaluateScript(
        _globalContext,
        scriptJs,
        nullptr,
        sourceUrlJs,
        1,
        exceptionPtr,
      );

      final exceptionRef = exceptionPtr.value;
      if (exceptionRef != nullptr &&
          jSValueIsObject(_globalContext, exceptionRef) == 1) {
        final exObj = jSValueToObject(_globalContext, exceptionRef, nullptr);
        final message = _readObjectStringProperty(exObj, 'message');
        final stack = _readObjectStringProperty(exObj, 'stack');
        return JsEvalResult(
          'ERROR: $message \n  at $stack',
          exceptionRef,
          isError: true,
        );
      }

      final result = _getJsValue(jsValueRef);
      final isPromise = _isPromiseValue(jsValueRef);
      return JsEvalResult(
        result,
        jsValueRef,
        isError: result.startsWith('ERROR:'),
        isPromise: isPromise,
      );
    } finally {
      jSStringRelease(scriptJs);
      if (sourceUrlJs != nullptr) {
        jSStringRelease(sourceUrlJs);
      }
      calloc.free(scriptCString);
      if (sourceUrlCString != null) {
        calloc.free(sourceUrlCString);
      }
      calloc.free(exceptionPtr);
    }
  }

  @override
  Future<JsEvalResult> evaluateAsync(String code, {String? sourceUrl}) {
    if (_isDisposed) {
      return Future.value(
        JsEvalResult('ERROR: runtime disposed', nullptr, isError: true),
      );
    }
    return Future.value(evaluate(code, sourceUrl: sourceUrl));
  }

  @override
  void dispose() {
    if (_isDisposed) return;
    _isDisposed = true;
    for (final timer in _timers.toList()) {
      timer.cancel();
    }
    _timers.clear();
    _instances.remove(_globalContext.address);
    JavascriptRuntime.channelFunctionsRegistered.remove(getEngineInstanceId());
    jSGlobalContextRelease(_globalContext);
    jSContextGroupRelease(_contextGroup);
  }

  @override
  String getEngineInstanceId() => identityHashCode(this).toString();

  @override
  void setInspectable(bool inspectable) {
    if (_isDisposed) return;
    if (Platform.isIOS || Platform.isMacOS) {
      try {
        context.setInspectable(inspectable);
      } on Error {
        // Ignore on unsupported OS builds.
      }
    }
  }

  @override
  bool setupBridge(String channelName, void Function(dynamic args) fn) {
    if (_isDisposed) return false;
    final channelFunctionCallbacks =
        JavascriptRuntime.channelFunctionsRegistered[getEngineInstanceId()];
    if (channelFunctionCallbacks == null) return false;
    if (channelFunctionCallbacks.containsKey(channelName)) return false;
    channelFunctionCallbacks[channelName] = fn;
    return true;
  }

  static Pointer sendMessageBridgeFunction(
    Pointer ctx,
    Pointer function,
    Pointer thisObject,
    int argumentCount,
    Pointer<Pointer> arguments,
    Pointer<Pointer> exception,
  ) {
    try {
      if (ctx == nullptr) return nullptr;
      final globalCtx = jSContextGetGlobalContext(ctx);
      if (globalCtx == nullptr) return nullptr;
      final runtime = _instances[globalCtx.address];
      if (runtime == null || runtime._isDisposed) {
        return nullptr;
      }
      return runtime._sendMessage(
        ctx,
        function,
        thisObject,
        argumentCount,
        arguments,
        exception,
      );
    } catch (_) {
      return nullptr;
    }
  }

  Pointer _sendMessage(
    Pointer ctx,
    Pointer function,
    Pointer thisObject,
    int argumentCount,
    Pointer<Pointer> arguments,
    Pointer<Pointer> exception,
  ) {
    if (_isDisposed || argumentCount < 2 || arguments == nullptr) {
      return nullptr;
    }
    final channelFunctions =
        JavascriptRuntime.channelFunctionsRegistered[getEngineInstanceId()];
    if (channelFunctions == null) return nullptr;

    final channelName = _getJsValue(arguments[0]);
    final message = _getJsValue(arguments[1]);
    final callback = channelFunctions[channelName];
    if (callback == null) {
      return nullptr;
    }

    dynamic decoded;
    try {
      decoded = jsonDecode(message);
    } catch (_) {
      return nullptr;
    }

    try {
      final result = callback.call(decoded);
      if (_isDisposed) return nullptr;
      if (result is Future) {
        return _constructPromiseFor(result);
      }
      final encoded = json.encode(result);
      final jsonStrC = encoded.toNativeUtf8();
      final jsonJsStr = jSStringCreateWithUTF8CString(jsonStrC);
      try {
        final value = jSValueMakeFromJSONString(_globalContext, jsonJsStr);
        return value;
      } finally {
        jSStringRelease(jsonJsStr);
        calloc.free(jsonStrC);
      }
    } catch (_) {
      return nullptr;
    }
  }

  Pointer<NativeType> _constructPromiseFor(Future future) {
    if (_isDisposed) return nullptr;
    final id = ++_promiseSequence;
    final scriptCString = (
      'var __JSC_promise_result$id = {};'
      'new Promise(function(resolve, reject) { '
      '__JSC_promise_result$id.resolve = resolve; '
      '__JSC_promise_result$id.reject = reject; '
      '});'
    ).toNativeUtf8();
    final scriptJs = jSStringCreateWithUTF8CString(scriptCString);

    Pointer<NativeType> jsValueRef = nullptr;
    try {
      jsValueRef = jSEvaluateScript(
        _globalContext,
        scriptJs,
        nullptr,
        nullptr,
        1,
        nullptr,
      );
    } finally {
      jSStringRelease(scriptJs);
      calloc.free(scriptCString);
    }

    future.then((value) {
      if (_isDisposed) return;
      final encoded = json.encode(value);
      evaluate(
        'if (typeof __JSC_promise_result$id === "object" && __JSC_promise_result$id) { '
        '__JSC_promise_result$id.resolve($encoded); '
        'delete __JSC_promise_result$id; }',
      );
    }).catchError((Object error) {
      if (_isDisposed) return;
      final encodedError = json.encode(error.toString());
      evaluate(
        'if (typeof __JSC_promise_result$id === "object" && __JSC_promise_result$id) { '
        '__JSC_promise_result$id.reject($encodedError); '
        'delete __JSC_promise_result$id; }',
      );
    });
    return jsValueRef;
  }

  @override
  JsEvalResult callFunction(Pointer<NativeType>? fn, Pointer<NativeType>? obj) {
    if (_isDisposed || fn == nullptr) {
      return JsEvalResult(
        'ERROR: runtime disposed',
        nullptr,
        isError: true,
      );
    }
    final fnObj = jSValueToObject(_globalContext, fn!, nullptr);
    if (fnObj == nullptr) {
      return JsEvalResult(
        'ERROR: invalid function object',
        nullptr,
        isError: true,
      );
    }
    final exceptionPtr = calloc<Pointer>()..value = nullptr;
    final thisArg = obj ?? nullptr;
    try {
      final resultPtr = jSObjectCallAsFunction(
        _globalContext,
        fnObj,
        thisArg,
        0,
        nullptr,
        exceptionPtr,
      );
      final exceptionRef = exceptionPtr.value;
      if (exceptionRef != nullptr &&
          jSValueIsObject(_globalContext, exceptionRef) == 1) {
        final exObj = jSValueToObject(_globalContext, exceptionRef, nullptr);
        final message = _readObjectStringProperty(exObj, 'message');
        throw Exception('ERROR: $message');
      }
      final isPromise = _isPromiseValue(resultPtr);
      return JsEvalResult(
        _getJsValue(resultPtr),
        resultPtr,
        isPromise: isPromise,
      );
    } finally {
      calloc.free(exceptionPtr);
    }
  }

  @override
  T? convertValue<T>(JsEvalResult jsValue) {
    if (_isDisposed) return null;
    final dynamic raw = jsValue.rawResult;
    if (raw is! Pointer || raw == nullptr) return null;
    if (jSValueIsNull(_globalContext, raw) == 1 ||
        jSValueIsUndefined(_globalContext, raw) == 1) {
      return null;
    }
    if (jSValueIsString(_globalContext, raw) == 1) {
      return _getJsValue(raw) as T;
    }
    if (jSValueIsBoolean(_globalContext, raw) == 1) {
      return (_getJsValue(raw) == 'true') as T;
    }
    if (jSValueIsNumber(_globalContext, raw) == 1) {
      final valueString = _getJsValue(raw);
      if (valueString.contains('.')) {
        try {
          return double.parse(valueString) as T;
        } on TypeError {
          return null;
        }
      }
      try {
        return int.parse(valueString) as T;
      } on TypeError {
        return null;
      }
    }
    if (jSValueIsObject(_globalContext, raw) == 1 ||
        jSValueIsArray(_globalContext, raw) == 1) {
      final serialized = _toJsonString(raw);
      if (serialized == null) return null;
      return jsonDecode(serialized) as T?;
    }
    return null;
  }

  @override
  String jsonStringify(JsEvalResult jsValue) {
    if (_isDisposed) return 'null';
    final dynamic raw = jsValue.rawResult;
    if (raw is! Pointer || raw == nullptr) return 'null';
    return _toJsonString(raw) ?? 'null';
  }

  bool _isPromiseValue(Pointer jsValueRef) {
    if (jsValueRef == nullptr ||
        jSValueIsObject(_globalContext, jsValueRef) != 1) {
      return false;
    }
    final objPtr = jSValueToObject(_globalContext, jsValueRef, nullptr);
    if (objPtr == nullptr) return false;
    return _hasObjectProperty(objPtr, 'then') &&
        _hasObjectProperty(objPtr, 'catch');
  }

  bool _hasObjectProperty(Pointer objPtr, String name) {
    final nameC = name.toNativeUtf8();
    final nameJs = jSStringCreateWithUTF8CString(nameC);
    try {
      final propPtr =
          jSObjectGetProperty(_globalContext, objPtr, nameJs, nullptr);
      return propPtr != nullptr && jSValueIsObject(_globalContext, propPtr) == 1;
    } finally {
      jSStringRelease(nameJs);
      calloc.free(nameC);
    }
  }

  String _readObjectStringProperty(Pointer objPtr, String name) {
    if (objPtr == nullptr) return '';
    final nameC = name.toNativeUtf8();
    final nameJs = jSStringCreateWithUTF8CString(nameC);
    try {
      final propPtr =
          jSObjectGetProperty(_globalContext, objPtr, nameJs, nullptr);
      return _getJsValue(propPtr);
    } finally {
      jSStringRelease(nameJs);
      calloc.free(nameC);
    }
  }

  String? _toJsonString(Pointer valueRef) {
    if (valueRef == nullptr) return null;
    final jsonJs = jSValueCreateJSONString(_globalContext, valueRef, 0, nullptr);
    if (jsonJs == nullptr) return null;
    try {
      return _jsStringRefToDart(jsonJs);
    } finally {
      jSStringRelease(jsonJs);
    }
  }

  String _getJsValue(Pointer jsValueRef) {
    if (jsValueRef == nullptr ||
        jSValueIsNull(_globalContext, jsValueRef) == 1) {
      return 'null';
    }
    if (jSValueIsUndefined(_globalContext, jsValueRef) == 1) {
      return 'undefined';
    }
    final resultJsString =
        jSValueToStringCopy(_globalContext, jsValueRef, nullptr);
    if (resultJsString == nullptr) {
      return 'null';
    }
    try {
      return _jsStringRefToDart(resultJsString) ?? 'null';
    } finally {
      jSStringRelease(resultJsString);
    }
  }

  String? _jsStringRefToDart(Pointer jsStringRef) {
    final cStr = jSStringGetCharactersPtr(jsStringRef);
    final length = jSStringGetLength(jsStringRef);
    if (cStr == nullptr) return null;
    if (length <= 0) return '';
    return String.fromCharCodes(
      Uint16List.view(
        cStr.cast<Uint16>().asTypedList(length).buffer,
        0,
        length,
      ),
    );
  }
}
