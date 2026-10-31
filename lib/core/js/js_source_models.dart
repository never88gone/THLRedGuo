class JsSourceMeta {
  static final _versionPattern = RegExp(
    r'^(\d{1,9})\.(\d{1,9})\.(\d{1,9})(?:-([0-9A-Za-z-]+(?:\.[0-9A-Za-z-]+)*))?(?:\+[0-9A-Za-z-]+(?:\.[0-9A-Za-z-]+)*)?$',
  );

  static String scriptVersion(String script) =>
      RegExp(
        r'''\bversion\s*:\s*["']([^"']+)["']''',
      ).firstMatch(script)?.group(1) ??
      '';

  static bool isVersionNewer(String candidate, String baseline) {
    if (candidate.length > 128 || baseline.length > 128) return false;
    final a = _versionPattern.firstMatch(candidate);
    final b = _versionPattern.firstMatch(baseline);
    if (a == null || b == null) return false;
    for (var index = 1; index <= 3; index++) {
      final order = int.parse(
        a.group(index)!,
      ).compareTo(int.parse(b.group(index)!));
      if (order != 0) return order > 0;
    }
    final ap = a.group(4);
    final bp = b.group(4);
    if (ap == null || bp == null) return ap == null && bp != null;
    final ai = ap.split('.');
    final bi = bp.split('.');
    for (var index = 0; index < ai.length && index < bi.length; index++) {
      final left = ai[index];
      final right = bi[index];
      if (left == right) continue;
      final an = RegExp(r'^\d+$').hasMatch(left);
      final bn = RegExp(r'^\d+$').hasMatch(right);
      if (an != bn) return !an;
      if (an) {
        final digitsA = left.replaceFirst(RegExp(r'^0+'), '');
        final digitsB = right.replaceFirst(RegExp(r'^0+'), '');
        final order = digitsA.length == digitsB.length
            ? digitsA.compareTo(digitsB)
            : digitsA.length.compareTo(digitsB.length);
        if (order != 0) return order > 0;
      } else {
        return left.compareTo(right) > 0;
      }
    }
    return ai.length > bi.length;
  }

  final String id;
  final String name;
  final String version;
  final String description;
  final String author;
  final String type;
  final String icon;
  final bool requiresAuth;
  final List<String> features;

  const JsSourceMeta({
    required this.id,
    required this.name,
    this.version = '1.0.0',
    this.description = '',
    this.author = '',
    this.type = 'video',
    this.icon = '',
    this.requiresAuth = false,
    this.features = const [],
  });

  factory JsSourceMeta.fromJson(Map<String, dynamic> json) {
    return JsSourceMeta(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? '',
      version: json['version'] as String? ?? '1.0.0',
      description: json['description'] as String? ?? '',
      author: json['author'] as String? ?? '',
      type: json['type'] as String? ?? 'video',
      icon: json['icon'] as String? ?? '',
      requiresAuth: json['requiresAuth'] as bool? ?? false,
      features:
          (json['features'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          const [],
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'version': version,
    'description': description,
    'author': author,
    'type': type,
    'icon': icon,
    'requiresAuth': requiresAuth,
    'features': features,
  };

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is JsSourceMeta &&
          runtimeType == other.runtimeType &&
          id == other.id;

  @override
  int get hashCode => id.hashCode;
}
