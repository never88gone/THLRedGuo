import '../../models.dart';

class PrivacyVaultEntry {
  const PrivacyVaultEntry({
    required this.drama,
    required this.addedAt,
  });

  final Drama drama;
  final DateTime addedAt;

  Map<String, dynamic> toJson() => {
        'drama': drama.toJson(),
        'addedAt': addedAt.toIso8601String(),
      };

  factory PrivacyVaultEntry.fromJson(Map<String, dynamic> json) =>
      PrivacyVaultEntry(
        drama: Drama.fromJson(Map<String, dynamic>.from(json['drama'] as Map)),
        addedAt: DateTime.tryParse(json['addedAt']?.toString() ?? '') ??
            DateTime.now(),
      );
}
