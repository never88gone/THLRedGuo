import 'dart:convert';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

String syntheticOfficialSource() =>
    '${File('assets/sources/hongguo.js').readAsStringSync()}\n'
    'globalThis.__hongguoLocalSign = function() { return {"x-medusa":"synthetic-signature"}; };\n';

void installSyntheticOfficialAsset() {
  rootBundle.evict('assets/sources/hongguo.js');
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMessageHandler('flutter/assets', (message) async {
        final key = utf8.decode(
          message!.buffer.asUint8List(
            message.offsetInBytes,
            message.lengthInBytes,
          ),
        );
        if (key != 'assets/sources/hongguo.js') return null;
        return ByteData.sublistView(
          Uint8List.fromList(utf8.encode(syntheticOfficialSource())),
        );
      });
}
