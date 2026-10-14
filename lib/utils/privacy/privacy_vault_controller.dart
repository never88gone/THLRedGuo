import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../models.dart';
import '../../models/privacy/privacy_vault_entry.dart';
import 'gesture_hasher.dart';

class PrivacyVaultController extends ChangeNotifier {
  PrivacyVaultController(this.preferences) {
    _load();
  }

  static const _keyVaultSalt = 'privacy_vault_salt';
  static const _keyVaultHash = 'privacy_vault_hash';
  static const _keyVaultEntries = 'privacy_vault_entries';

  final SharedPreferences preferences;
  final Map<String, PrivacyVaultEntry> _entries = {};
  bool _isUnlocked = false;

  bool get hasPassword {
    final salt = preferences.getString(_keyVaultSalt) ?? '';
    final hash = preferences.getString(_keyVaultHash) ?? '';
    return salt.isNotEmpty && hash.isNotEmpty;
  }

  bool get isUnlocked => _isUnlocked;
  int get vaultCount => _entries.length;
  List<Drama> get vaultDramas =>
      _entries.values.map((entry) => entry.drama).toList();

  void _load() {
    _entries.clear();
    final raw = preferences.getString(_keyVaultEntries);
    if (raw != null && raw.isNotEmpty) {
      try {
        final list = jsonDecode(raw) as List;
        for (final item in list) {
          final entry =
              PrivacyVaultEntry.fromJson(Map<String, dynamic>.from(item as Map));
          _entries[entry.drama.id] = entry;
        }
      } catch (_) {}
    }
  }

  bool isInVault(String dramaId) => _entries.containsKey(dramaId);

  Future<void> setPassword(String password) async {
    final trimmed = password.trim();
    if (trimmed.length < 4) {
      throw ArgumentError('密码至少需要 4 位字符');
    }
    final salt = GestureHasher.generateSalt();
    final hash = GestureHasher.hashPattern(
      trimmed.codeUnits,
      salt,
    );
    await preferences.setString(_keyVaultSalt, salt);
    await preferences.setString(_keyVaultHash, hash);
    _isUnlocked = true;
    notifyListeners();
  }

  bool verifyPassword(String password) {
    if (!hasPassword) return false;
    final salt = preferences.getString(_keyVaultSalt) ?? '';
    final hash = preferences.getString(_keyVaultHash) ?? '';
    if (salt.isEmpty || hash.isEmpty) return false;

    final target = GestureHasher.hashPattern(
      password.trim().codeUnits,
      salt,
    );
    final match = GestureHasher.constantTimeCompare(target, hash);
    if (match) {
      _isUnlocked = true;
      notifyListeners();
    }
    return match;
  }

  void lock() {
    if (_isUnlocked) {
      _isUnlocked = false;
      notifyListeners();
    }
  }

  Future<void> addToVault(Drama drama) async {
    _entries[drama.id] = PrivacyVaultEntry(
      drama: drama,
      addedAt: DateTime.now(),
    );
    await _saveEntries();
    notifyListeners();
  }

  Future<void> removeFromVault(String dramaId) async {
    if (_entries.remove(dramaId) != null) {
      await _saveEntries();
      notifyListeners();
    }
  }

  Future<void> _saveEntries() async {
    final list = _entries.values.map((e) => e.toJson()).toList();
    await preferences.setString(_keyVaultEntries, jsonEncode(list));
  }

  Future<void> clearVault() async {
    _entries.clear();
    await preferences.remove(_keyVaultEntries);
    notifyListeners();
  }
}
