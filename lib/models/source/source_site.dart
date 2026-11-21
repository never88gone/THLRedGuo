import 'package:THLRedLook/core/js/js_source_service.dart';
import 'package:THLRedLook/utils/build/app_build.dart';

class SourceSite {
  const SourceSite(this.id, this.name, this.description);
  final String id;
  final String name;
  final String description;
  bool get onlineSearch => id == 'hongguo';
  bool get pagedSearch => id == 'hongguo';
  bool get searchSuggestions => id == 'hongguo';
  String get groupId => id;
  String get groupName => name;
  String get entryName => name;

  static const hongguo = SourceSite('hongguo', '精选短剧', '短剧 · 漫剧 · AI 剧');

  /// 默认可见站源：开源版本仅包含官方规范短剧
  static const primaryValues = [hongguo];

  /// 敏感站源：开源版本已全部移除
  static const restrictedValues = <SourceSite>[];
  static const knownValues = [hongguo];
  static const allValues = [hongguo];

  static bool _runtimeActivated = false;

  /// 是否已激活全功能模式（编译开关打开或运行时用户激活）。
  static bool get isZhenguojianActivated =>
      allSourcesEnabled || _runtimeActivated;

  /// 运行时激活全功能模式，解锁全部数据源。
  static void activateAllSources() => _runtimeActivated = true;

  /// 重置运行时激活状态（主要供测试使用）。
  static void resetRuntimeActivation() => _runtimeActivated = false;

  static List<SourceSite> get values {
    final jsService = JsSourceService.current;
    if (jsService != null) {
      return [
        for (final meta in jsService.sources)
          SourceSite(meta.id, meta.name, meta.description),
      ];
    }
    final baseSites = isZhenguojianActivated ? knownValues : const [hongguo];
    return baseSites;
  }

  static bool isAvailable(String id) {
    final jsService = JsSourceService.current;
    if (jsService != null) {
      return jsService.sources.any((s) => s.id == id);
    }
    return values.any((site) => site.id == id) ||
        allValues.any((site) => site.id == id);
  }

  static bool isKnown(String id) {
    final jsService = JsSourceService.current;
    if (jsService != null) {
      return jsService.sources.any((s) => s.id == id);
    }
    return values.any((site) => site.id == id) ||
        allValues.any((site) => site.id == id);
  }

  static bool isPrimary(String id) {
    final jsService = JsSourceService.current;
    if (jsService != null) {
      return jsService.sources.any((s) => s.id == id);
    }
    return primaryValues.any((site) => site.id == id);
  }

  static bool isRestricted(String id) =>
      restrictedValues.any((site) => site.id == id);

  /// 运行时可见站源：当启用 JS 服务时完全取决于已导入的 JS 插件；无插件时返回空列表
  static List<SourceSite> visibleValues({required bool unlocked}) {
    final jsService = JsSourceService.current;
    if (jsService != null) {
      return [
        for (final meta in jsService.sources)
          SourceSite(meta.id, meta.name, meta.description),
      ];
    }
    return [
      for (final site
          in (unlocked || isZhenguojianActivated ? knownValues : primaryValues))
        site,
    ];
  }

  static SourceSite byId(String id) {
    final jsSources = JsSourceService.current?.sources;
    if (jsSources != null) {
      for (final meta in jsSources) {
        if (meta.id == id) {
          return SourceSite(meta.id, meta.name, meta.description);
        }
      }
    }
    for (final site in allValues) {
      if (site.id == id) return site;
    }
    return SourceSite(id, id, '自定义数据源');
  }
}

class SourceGroup {
  const SourceGroup(this.id, this.name, this.sources);
  final String id;
  final String name;
  final List<SourceSite> sources;

  static List<SourceGroup> fromSources(Iterable<SourceSite> sources) {
    final groups = <String, List<SourceSite>>{};
    for (final source in sources) {
      (groups[source.groupId] ??= []).add(source);
    }
    return [
      for (final group in groups.entries)
        SourceGroup(group.key, group.value.first.groupName, group.value),
    ];
  }
}
