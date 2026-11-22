import 'dart:ffi';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';
import 'package:flutter_js/javascriptcore/jscore_bindings.dart';

/// JavaScriptCore 底层 FFI 字符串与对象解析辅助工具类
abstract final class SafeJscoreHelper {
  static String readObjectStringProperty(
    Pointer globalContext,
    Pointer objPtr,
    String name,
  ) {
    if (objPtr == nullptr) return '';
    final nameC = name.toNativeUtf8();
    final nameJs = jSStringCreateWithUTF8CString(nameC);
    try {
      final propPtr =
          jSObjectGetProperty(globalContext, objPtr, nameJs, nullptr);
      return getJsValue(globalContext, propPtr);
    } finally {
      jSStringRelease(nameJs);
      calloc.free(nameC);
    }
  }

  static String? toJsonString(Pointer globalContext, Pointer valueRef) {
    if (valueRef == nullptr) return null;
    final jsonJs = jSValueCreateJSONString(globalContext, valueRef, 0, nullptr);
    if (jsonJs == nullptr) return null;
    try {
      return jsStringRefToDart(jsonJs);
    } finally {
      jSStringRelease(jsonJs);
    }
  }

  static String getJsValue(Pointer globalContext, Pointer jsValueRef) {
    if (jsValueRef == nullptr ||
        jSValueIsNull(globalContext, jsValueRef) == 1) {
      return 'null';
    }
    if (jSValueIsUndefined(globalContext, jsValueRef) == 1) {
      return 'undefined';
    }
    final resultJsString =
        jSValueToStringCopy(globalContext, jsValueRef, nullptr);
    if (resultJsString == nullptr) {
      return 'null';
    }
    try {
      return jsStringRefToDart(resultJsString) ?? 'null';
    } finally {
      jSStringRelease(resultJsString);
    }
  }

  static String? jsStringRefToDart(Pointer jsStringRef) {
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
