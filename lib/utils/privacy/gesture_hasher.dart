import 'dart:convert';
import 'dart:math';
import 'package:crypto/crypto.dart';

class GestureHasher {
  const GestureHasher();

  static String generateSalt() {
    final random = Random.secure();
    final bytes = List<int>.generate(16, (_) => random.nextInt(256));
    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }

  static String hashPattern(List<int> pattern, String salt) {
    final patternString = pattern.join('-');
    final bytes = utf8.encode('$salt:$patternString:$salt');
    return sha256.convert(bytes).toString();
  }

  static bool constantTimeCompare(String a, String b) {
    if (a.length != b.length) return false;
    var result = 0;
    for (var i = 0; i < a.length; i++) {
      result |= a.codeUnitAt(i) ^ b.codeUnitAt(i);
    }
    return result == 0;
  }
}
