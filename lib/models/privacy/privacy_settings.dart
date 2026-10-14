class PrivacySettings {
  const PrivacySettings({
    this.enabled = false,
    this.hasGesture = false,
    this.autoLockSeconds = 60,
  });

  final bool enabled;
  final bool hasGesture;
  final int autoLockSeconds;

  PrivacySettings copyWith({
    bool? enabled,
    bool? hasGesture,
    int? autoLockSeconds,
  }) {
    return PrivacySettings(
      enabled: enabled ?? this.enabled,
      hasGesture: hasGesture ?? this.hasGesture,
      autoLockSeconds: autoLockSeconds ?? this.autoLockSeconds,
    );
  }

  Map<String, dynamic> toJson() => {
        'enabled': enabled,
        'hasGesture': hasGesture,
        'autoLockSeconds': autoLockSeconds,
      };

  factory PrivacySettings.fromJson(Map<String, dynamic> json) =>
      PrivacySettings(
        enabled: json['enabled'] == true,
        hasGesture: json['hasGesture'] == true,
        autoLockSeconds: (json['autoLockSeconds'] as num?)?.toInt() ?? 0,
      );
}
