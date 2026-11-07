import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

/// 对应平台的安装包产物信息
class UpdateAsset {
  const UpdateAsset({
    required this.name,
    required this.downloadUrl,
    required this.sizeBytes,
    this.description = '',
  });

  final String name;
  final String downloadUrl;
  final int sizeBytes;
  final String description;

  String get formattedSize {
    if (sizeBytes <= 0) return '';
    if (sizeBytes < 1024 * 1024) {
      return '${(sizeBytes / 1024).toStringAsFixed(1)} KB';
    }
    return '${(sizeBytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
}

/// 检查更新结果数据模型
class AppUpdateInfo {
  const AppUpdateInfo({
    required this.currentVersion,
    required this.currentBuildNumber,
    required this.remoteVersion,
    required this.remoteBuildNumber,
    required this.remoteTagName,
    required this.title,
    required this.releaseNotes,
    required this.htmlUrl,
    required this.hasUpdate,
    this.primaryAsset,
    this.availableAssets = const [],
    this.publishedAt,
  });

  final String currentVersion;
  final String currentBuildNumber;
  final String remoteVersion;
  final String remoteBuildNumber;
  final String remoteTagName;
  final String title;
  final String releaseNotes;
  final String htmlUrl;
  final bool hasUpdate;
  final UpdateAsset? primaryAsset;
  final List<UpdateAsset> availableAssets;
  final DateTime? publishedAt;

  String get displayRemoteVersion {
    final v = remoteVersion.isNotEmpty ? 'v$remoteVersion' : remoteTagName;
    if (remoteBuildNumber.isNotEmpty) {
      return '$v (Build $remoteBuildNumber)';
    }
    return v;
  }

  String get displayCurrentVersion {
    final v = 'v$currentVersion';
    if (currentBuildNumber.isNotEmpty) {
      return '$v (Build $currentBuildNumber)';
    }
    return v;
  }
}

/// 跨平台应用更新检查服务
class AppUpdateService {
  AppUpdateService._();
  static final AppUpdateService instance = AppUpdateService._();

  static const String repoOwner = 'never88gone';
  static const String repoName = 'THLRedGuo';
  static const String githubReleasesApi =
      'https://api.github.com/repos/$repoOwner/$repoName/releases/latest';

  /// 判断当前平台是否支持客户端内独立检查更新
  /// iOS 与 Apple tvOS 统一通过 TestFlight 分发与自动更新，不在此进行更新检测
  static bool get isSupportedPlatform {
    if (kIsWeb) return false;
    return defaultTargetPlatform == TargetPlatform.android ||
        defaultTargetPlatform == TargetPlatform.windows ||
        defaultTargetPlatform == TargetPlatform.macOS ||
        defaultTargetPlatform == TargetPlatform.linux;
  }

  /// 检查 GitHub Releases 是否有新版本
  Future<AppUpdateInfo> checkUpdate({
    http.Client? client,
    String? overrideCurrentVersion,
    String? overrideCurrentBuild,
    TargetPlatform? targetPlatform,
  }) async {
    String currentVersion = overrideCurrentVersion ?? '';
    String currentBuild = overrideCurrentBuild ?? '';

    if (currentVersion.isEmpty || currentBuild.isEmpty) {
      try {
        final info = await PackageInfo.fromPlatform();
        if (currentVersion.isEmpty) {
          currentVersion = info.version.isNotEmpty ? info.version : '1.0.0';
        }
        if (currentBuild.isEmpty) {
          currentBuild = info.buildNumber;
        }
      } catch (_) {
        if (currentVersion.isEmpty) currentVersion = '1.0.0';
      }
    }

    final httpClient = client ?? http.Client();
    final bool shouldCloseClient = client == null;

    try {
      final response = await httpClient.get(
        Uri.parse(githubReleasesApi),
        headers: {
          'Accept': 'application/vnd.github.v3+json',
          'User-Agent': 'THLRedGuo-UpdateChecker/$currentVersion',
        },
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode != 200) {
        throw HttpException(
          'GitHub API 请求失败 (HTTP ${response.statusCode})',
          uri: Uri.parse(githubReleasesApi),
        );
      }

      final Map<String, dynamic> json =
          jsonDecode(response.body) as Map<String, dynamic>;

      return parseReleaseJson(
        json: json,
        currentVersion: currentVersion,
        currentBuild: currentBuild,
        platform: targetPlatform ?? defaultTargetPlatform,
      );
    } finally {
      if (shouldCloseClient) {
        httpClient.close();
      }
    }
  }

  /// 解析 GitHub Release JSON 数据
  static AppUpdateInfo parseReleaseJson({
    required Map<String, dynamic> json,
    required String currentVersion,
    required String currentBuild,
    required TargetPlatform platform,
  }) {
    final tagName = (json['tag_name'] as String?)?.trim() ?? '';
    final title = (json['name'] as String?)?.trim() ?? tagName;
    final body = (json['body'] as String?)?.trim() ?? '';
    final htmlUrl = (json['html_url'] as String?)?.trim() ??
        'https://github.com/$repoOwner/$repoName/releases';

    DateTime? publishedAt;
    if (json['published_at'] != null) {
      publishedAt = DateTime.tryParse(json['published_at'] as String);
    }

    final remoteVersion = cleanVersion(tagName);
    final remoteBuild = extractBuildNumber(title, tagName, body);

    final bool hasUpdate = isNewerVersion(
      currentVersion: currentVersion,
      currentBuild: currentBuild,
      remoteVersion: remoteVersion,
      remoteBuild: remoteBuild,
    );

    // 解析 assets
    final rawAssets = json['assets'] as List<dynamic>? ?? [];
    final List<UpdateAsset> platformAssets = [];

    for (final item in rawAssets) {
      if (item is! Map<String, dynamic>) continue;
      final name = (item['name'] as String?) ?? '';
      final downloadUrl = (item['browser_download_url'] as String?) ?? '';
      final size = (item['size'] as num?)?.toInt() ?? 0;

      if (downloadUrl.isEmpty || name.isEmpty) continue;

      if (_matchesPlatform(name, platform)) {
        final description = _describeAsset(name, platform);
        platformAssets.add(
          UpdateAsset(
            name: name,
            downloadUrl: downloadUrl,
            sizeBytes: size,
            description: description,
          ),
        );
      }
    }

    // 确定主推荐包
    UpdateAsset? primaryAsset;
    if (platformAssets.isNotEmpty) {
      if (platform == TargetPlatform.android) {
        // Android 首选 arm64-v8a
        primaryAsset = platformAssets.firstWhere(
          (a) => a.name.contains('arm64-v8a'),
          orElse: () => platformAssets.first,
        );
      } else {
        primaryAsset = platformAssets.first;
      }
    }

    return AppUpdateInfo(
      currentVersion: currentVersion,
      currentBuildNumber: currentBuild,
      remoteVersion: remoteVersion,
      remoteBuildNumber: remoteBuild,
      remoteTagName: tagName,
      title: title,
      releaseNotes: body,
      htmlUrl: htmlUrl,
      hasUpdate: hasUpdate,
      primaryAsset: primaryAsset,
      availableAssets: platformAssets,
      publishedAt: publishedAt,
    );
  }

  /// 过滤符合当前平台的安装包
  static bool _matchesPlatform(String name, TargetPlatform platform) {
    final lower = name.toLowerCase();
    switch (platform) {
      case TargetPlatform.android:
        return lower.endsWith('.apk');
      case TargetPlatform.windows:
        return lower.endsWith('.exe') ||
            (lower.contains('win') && lower.endsWith('.zip'));
      case TargetPlatform.macOS:
        return lower.endsWith('.dmg') ||
            (lower.contains('mac') && lower.endsWith('.zip'));
      default:
        return false;
    }
  }

  /// 生成安装包描述
  static String _describeAsset(String name, TargetPlatform platform) {
    final lower = name.toLowerCase();
    if (platform == TargetPlatform.android) {
      if (lower.contains('arm64-v8a')) return '64位主流手机与平板（推荐）';
      if (lower.contains('armeabi-v7a')) return '32位老设备或部分电视盒子';
      if (lower.contains('x86_64')) return 'PC 安卓模拟器';
      return 'Android 安装包';
    }
    if (platform == TargetPlatform.windows) {
      return 'Windows 64位绿色便携包';
    }
    if (platform == TargetPlatform.macOS) {
      return 'macOS 原生磁盘映像安装包 (DMG)';
    }
    if (platform == TargetPlatform.iOS) {
      return 'iOS 原生安装包 (IPA)';
    }
    return '';
  }

  /// 清洗版本字符串，去除前导 v / V
  static String cleanVersion(String raw) {
    var v = raw.trim();
    if (v.startsWith('v') || v.startsWith('V')) {
      v = v.substring(1).trim();
    }
    // 去除 +build 或 -suffix
    if (v.contains('+')) {
      v = v.split('+').first;
    }
    if (v.contains('-')) {
      v = v.split('-').first;
    }
    return v;
  }

  /// 从标题、Tag 或正文中提取构建号
  static String extractBuildNumber(String title, String tag, String body) {
    // 匹配如: Build 263051655 或 (Build 263051655)
    final buildRegex = RegExp(r'Build\s*(\d+)', caseSensitive: false);
    final matchInTitle = buildRegex.firstMatch(title);
    if (matchInTitle != null) {
      return matchInTitle.group(1) ?? '';
    }

    // 匹配如: +263051654
    final plusRegex = RegExp(r'\+(\d+)');
    final matchInTag = plusRegex.firstMatch(tag);
    if (matchInTag != null) {
      return matchInTag.group(1) ?? '';
    }

    // 匹配如: -263051654
    final dashRegex = RegExp(r'-(\d{6,})');
    final matchDash = dashRegex.firstMatch(tag);
    if (matchDash != null) {
      return matchDash.group(1) ?? '';
    }

    final matchInBody = buildRegex.firstMatch(body);
    if (matchInBody != null) {
      return matchInBody.group(1) ?? '';
    }

    return '';
  }

  /// 对比版本号与构建号
  static bool isNewerVersion({
    required String currentVersion,
    required String currentBuild,
    required String remoteVersion,
    required String remoteBuild,
  }) {
    final curParts = _parseVersionParts(currentVersion);
    final remParts = _parseVersionParts(remoteVersion);

    final maxLen = curParts.length > remParts.length ? curParts.length : remParts.length;

    for (int i = 0; i < maxLen; i++) {
      final c = i < curParts.length ? curParts[i] : 0;
      final r = i < remParts.length ? remParts[i] : 0;
      if (r > c) return true;
      if (r < c) return false;
    }

    // 语义化版本相同时，对比 Build Number
    final cBuild = int.tryParse(currentBuild);
    final rBuild = int.tryParse(remoteBuild);

    if (cBuild != null && rBuild != null) {
      return rBuild > cBuild;
    }

    return false;
  }

  static List<int> _parseVersionParts(String version) {
    final clean = cleanVersion(version);
    if (clean.isEmpty) return [0];
    return clean
        .split('.')
        .map((part) => int.tryParse(part) ?? 0)
        .toList();
  }

  /// 打开安装包下载链接或 Release 页面
  static Future<bool> openDownloadUrl(
    BuildContext context,
    String url, {
    String? fallbackLabel,
  }) async {
    final uri = Uri.parse(url);
    try {
      final launched = await launchUrl(
        uri,
        mode: LaunchMode.externalApplication,
      );
      if (launched) return true;

      final fallback = await launchUrl(uri);
      if (fallback) return true;

      if (context.mounted) {
        _copyAndNotify(context, url, fallbackLabel ?? '下载链接');
      }
      return false;
    } catch (_) {
      if (context.mounted) {
        _copyAndNotify(context, url, fallbackLabel ?? '下载链接');
      }
      return false;
    }
  }

  static void _copyAndNotify(BuildContext context, String text, String label) {
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('已复制 $label 到剪贴板，可在浏览器中打开'),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 3),
      ),
    );
  }
}
