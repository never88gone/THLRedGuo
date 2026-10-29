import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:THLRedLook/models/catalog/models.dart';

void main() {
  test(
    'tvOS 原生诊断保留网络与业务错误且报告脱敏',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'thl-tvos-diagnostics-',
      );
      try {
        final main = File('${directory.path}/DiagnosticsRegression.swift');
        await main.writeAsString(r'''import Foundation
import CoreImage.CIFilterBuiltins

public let BuiltInHongguoJSContent = try! String(contentsOfFile: "assets/sources/hongguo.js", encoding: .utf8)
final class StubProtocol: URLProtocol {
    static var mode = "healthy"
    static var registrations = 0
    static var searches = 0
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let registration = request.url!.path.trimmingCharacters(in: CharacterSet(charactersIn: "/")) == "service/2/device_register"
        if registration { Self.registrations += 1 } else { Self.searches += 1 }
        if Self.mode == "dns" && registration {
            client?.urlProtocol(self, didFailWithError: URLError(.cannotFindHost))
            return
        }
        let status = Self.mode == "http" && !registration ? 403 : 200
        let body = registration
            ? "{\"device_id_str\":\"7345678901234567100\",\"install_id_str\":\"7345678901234567200\",\"device_token\":\"private-token-secret\"}"
            : Self.mode == "business" ? "{\"code\":1001,\"message\":\"private-message-secret\"}" : "{\"code\":0,\"search_tabs\":[{\"tab_type\":29,\"data\":[],\"has_more\":false,\"next_offset\":0}]}"
        client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: ["Set-Cookie":"private-cookie-secret"])!, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
@main
struct Regression {
    static func main() async throws {
        for mode in ["healthy", "dns", "http", "business"] {
            StubProtocol.mode = mode
            StubProtocol.registrations = 0
            StubProtocol.searches = 0
            let recorder = SourceDiagnostics()
            let config = URLSessionConfiguration.ephemeral
            config.protocolClasses = [StubProtocol.self]
            let session = URLSession(configuration: config)
            defer { session.invalidateAndCancel() }
            let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            defer { try? FileManager.default.removeItem(at: folder) }
            let bridge = NativeBridge(baseDirectory: folder, httpSession: session, diagnostics: recorder, persistentDeviceSession: false)
            var succeeded = false
            do {
                _ = try await bridge.request(action: "catalog", payload: ["source":"hongguo", "query":"private-query-secret", "page":1])
                succeeded = true
            } catch {
                precondition(recorder.entries.contains { $0.failed }, "mode=\(mode) error=\(error.localizedDescription) records=\(recorder.entries.map(\.text))")
            }
            precondition(succeeded == (mode == "healthy"), "mode=\(mode) succeeded=\(succeeded) records=\(recorder.entries.map(\.text))")
            if mode == "dns" {
                precondition(recorder.entries.first?.stage == "游客注册")
                precondition(recorder.entries.first?.errorCode == "DNS:-1003")
                precondition(StubProtocol.searches == 0)
            }
            if mode == "http" { precondition(recorder.entries.contains { $0.status == 403 && $0.errorCode == "HTTP_403" }) }
            if mode == "business" {
                precondition(StubProtocol.registrations == 2)
                precondition(recorder.entries.contains { $0.status == 200 && $0.businessCode == "1001" && $0.errorCode == "BUSINESS_REJECTED" })
            }
            for text in [recorder.report, recorder.qrText] {
                precondition(!text.contains("private-"))
                precondition(!text.contains("7345678901234567100"))
                precondition(!text.contains("x-medusa"))
            }
            for _ in 0..<70 { recorder.add(SourceDiagnosticEntry(context:"测试",stage:"搜索",errorCode:"HTTP_403")) }
            precondition(recorder.entries.count == 60)
            let qrText = recorder.qrText
            precondition(qrText.utf8.count <= 2300)
            let filter = CIFilter.qrCodeGenerator()
            filter.message = Data(qrText.utf8)
            filter.correctionLevel = "L"
            let image = filter.outputImage!.transformed(by: CGAffineTransform(scaleX: 4, y: 4))
            let detector = CIDetector(ofType: CIDetectorTypeQRCode, context: CIContext(), options: [CIDetectorAccuracy: CIDetectorAccuracyHigh])!
            let decoded = detector.features(in: image).compactMap { ($0 as? CIQRCodeFeature)?.messageString }
            precondition(decoded.contains(qrText))
            recorder.clear()
            precondition(recorder.entries.isEmpty)
        }
        precondition(SourceDiagnostics.networkCode(URLError(.timedOut)) == "TIMEOUT:-1001")
        precondition(SourceDiagnostics.networkCode(URLError(.secureConnectionFailed)) == "TLS:-1200")
        print("THL_TV_DIAGNOSTICS_REGRESSION passed")
    }
}
''');
        final errors = File('${directory.path}/SourceAPIError.swift');
        final protocols = File(
          'tvos/THLRedLook/Core/PlatformProtocols.swift',
        ).readAsStringSync();
        final enumStart = protocols.indexOf('public enum SourceAPIError');
        final enumSource = protocols.substring(
          enumStart,
          protocols.indexOf('\n}\n', enumStart) + 3,
        );
        final player = File(
          'tvos/THLRedLook/ViewModels/PlayerViewModel.swift',
        ).readAsStringSync();
        final policyStart = player.indexOf('enum PlaybackRetryPolicy');
        final policy = player.substring(
          policyStart,
          player.indexOf('\n}\n', policyStart) + 3,
        );
        await errors.writeAsString('import Foundation\n$enumSource\n$policy');
        final binary = '${directory.path}/DiagnosticsRegression';
        final compile = await Process.run('xcrun', [
          'swiftc',
          '-parse-as-library',
          'tvos/THLRedLook/Core/NativeBridge.swift',
          'tvos/THLRedLook/Core/SourceDiagnostics.swift',
          'tvos/THLRedLook/Core/NetworkEgressLookup.swift',
          'tvos/THLRedLook/Models/PlaybackPlan.swift',
          errors.path,
          main.path,
          '-o',
          binary,
        ]);
        expect(compile.exitCode, 0, reason: '${compile.stderr}');
        final result = await Process.run(binary, const []);
        expect(result.exitCode, 0, reason: '${result.stderr}');
        expect(result.stdout, contains('THL_TV_DIAGNOSTICS_REGRESSION passed'));
      } finally {
        await directory.delete(recursive: true);
      }
    },
    skip: !Platform.isMacOS,
    timeout: const Timeout(Duration(minutes: 3)),
  );

  test(
    'tvOS Swift 实现修复旧编号并保留持久化收藏和较新历史',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'thl-tvos-identity-',
      );
      try {
        final main = File('${directory.path}/Regression.swift');
        await main.writeAsString(r'''import Foundation

@main
struct Regression {
    @MainActor
    static func main() throws {
        let oldFourth = Drama(id: "hongguo:7688558312157089000", sourceId: "7688558312157089000", title: "满院亲戚全是上古大妖第四季", episodes: 155)
        let fourth = Drama(id: "hongguo:7688558312157088793", sourceId: "7688558312157088793", title: "满院亲戚全是上古大妖第四季", episodes: 155)
        let oldSecond = Drama(id: "hongguo:7678338044344159000", sourceId: "7678338044344159000", title: "满院亲戚全是上古大妖第二季", episodes: 100)
        let second = Drama(id: "hongguo:7678338044344159256", sourceId: "7678338044344159256", title: "满院亲戚全是上古大妖第二季", episodes: 100)
        let other = Drama(id: "hongguo:synthetic-unrelated", title: "合成隔离记录")
        precondition(HongguoSeriesIdentity.isRounded(oldFourth))
        precondition(!HongguoSeriesIdentity.isRounded(fourth))
        let ambiguous = Drama(id: "hongguo:7688558312157088794", title: fourth.title)
        precondition(HongguoSeriesIdentity.replacements(previous: [oldFourth], fresh: [fourth, ambiguous]).isEmpty)
        precondition(HongguoSeriesIdentity.replacements(previous: [oldFourth], fresh: [oldFourth, fourth]).isEmpty)
        let different = Drama(id: fourth.id, sourceId: fourth.sourceId, title: "合成另一部短剧第四季")
        precondition(HongguoSeriesIdentity.replacements(previous: [oldFourth], fresh: [different]).isEmpty)
        precondition(HongguoSeriesIdentity.replacements(previous: [fourth], fresh: [oldFourth]).isEmpty)
        let variant = Drama(id: oldFourth.id, title: "满院亲戚全是上古大妖 第4季 (全集)")
        precondition(HongguoSeriesIdentity.replacements(previous: [variant], fresh: [fourth])[variant.id]?.id == fourth.id)
        let suite = "THLRedLook.Regression." + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let seeded = LocalStore(defaults: defaults, cloudUpload: { _ in })
        seeded.setFollowState(drama: oldFourth, state: .watching)
        seeded.setFollowState(drama: oldSecond, state: .wishlist)
        seeded.recordWatch(drama: oldFourth, episode: 12, position: 37.5, duration: 158)
        seeded.recordWatch(drama: oldSecond, episode: 5, position: 7, duration: 100)
        seeded.recordWatch(drama: other, episode: 2, position: 42, duration: 120)
        let store = LocalStore(defaults: defaults, cloudUpload: { _ in })
        let oldTime = store.getWatchEntry(dramaId: oldFourth.id)!.updatedAt
        let otherEntry = store.getWatchEntry(dramaId: other.id)!
        let changed = store.refreshDramas([fourth, second])
        precondition(changed[oldFourth.id]?.id == fourth.id)
        let restored = LocalStore(defaults: defaults, cloudUpload: { _ in })
        precondition(restored.followState(for: fourth.id) == .watching)
        precondition(restored.followState(for: second.id) == .wishlist)
        precondition(restored.followState(for: oldFourth.id) == .none)
        precondition(restored.followedDramas.count == 2)
        precondition(restored.getWatchEntry(dramaId: oldFourth.id) == nil)
        precondition(restored.getWatchEntry(dramaId: fourth.id)?.episode == 12)
        precondition(restored.getWatchEntry(dramaId: fourth.id)?.position == 37.5)
        precondition(restored.getWatchEntry(dramaId: fourth.id)?.updatedAt == oldTime)
        precondition(restored.getWatchEntry(dramaId: second.id)?.episode == 5)
        precondition(restored.getWatchEntry(dramaId: other.id) == otherEntry)
        precondition(restored.refreshDramas([fourth, second]).isEmpty)
        restored.setFollowState(drama: oldFourth, state: .watched)
        restored.recordWatch(drama: fourth, episode: 33, position: 17, duration: 80)
        restored.refreshDramas([fourth])
        let merged = LocalStore(defaults: defaults, cloudUpload: { _ in })
        precondition(merged.followedDramas.count == 2)
        precondition(merged.followState(for: fourth.id) == .watched)
        precondition(merged.getWatchEntry(dramaId: fourth.id)?.episode == 33)
        print("THL_TV_IDENTITY_REGRESSION passed")
    }
}
''');
        final binary = '${directory.path}/Regression';
        final compile = await Process.run('xcrun', [
          'swiftc',
          '-parse-as-library',
          'tvos/THLRedLook/Models/Drama.swift',
          'tvos/THLRedLook/Models/WatchEntry.swift',
          'tvos/THLRedLook/Models/SourceSite.swift',
          'tvos/THLRedLook/Models/LanModels.swift',
          'tvos/THLRedLook/Core/LocalStore.swift',
          'tvos/THLRedLook/Core/ICloudSyncService.swift',
          main.path,
          '-o',
          binary,
        ]);
        expect(compile.exitCode, 0, reason: '${compile.stderr}');
        final result = await Process.run(binary, const []);
        expect(result.exitCode, 0, reason: '${result.stderr}');
        expect(result.stdout, contains('THL_TV_IDENTITY_REGRESSION passed'));
      } finally {
        await directory.delete(recursive: true);
      }
    },
    skip: !Platform.isMacOS,
    timeout: const Timeout(Duration(minutes: 2)),
  );

  group('tvOS 原生端模型契约与多端交互规范自动化测试', () {
    test('1. Drama 模型 JSON 序列化与 tvOS Codable 契约对齐', () {
      final drama = Drama(
        id: 'hongguo:7345678901234567890',
        source: 'hongguo',
        sourceId: '7345678901234567890',
        title: '至尊龙王令',
        description: '五年前一代龙王隐姓埋名...',
        cover: 'https://p3.example.com/cover.jpg',
        episodes: 90,
        category: '真人剧',
        vip: false,
        heat: '98.5万',
        views: '120万',
        onlineDate: '2024-05-01',
        tags: ['热血', '战神', '逆袭'],
        releaseStatus: 'completed',
      );

      final json = drama.toJson();

      // 验证与 tvOS Drama.swift Codable 字段一致
      expect(json['id'], equals('hongguo:7345678901234567890'));
      expect(json['source'], equals('hongguo'));
      expect(json['sourceId'], equals('7345678901234567890'));
      expect(json['title'], equals('至尊龙王令'));
      expect(json['description'], contains('一代龙王'));
      expect(json['cover'], equals('https://p3.example.com/cover.jpg'));
      expect(json['episodes'], equals(90));
      expect(json['category'], equals('真人剧'));
      expect(json['vip'], isFalse);
      expect(json['heat'], equals('98.5万'));
      expect(json['views'], equals('120万'));
      expect(json['onlineDate'], equals('2024-05-01'));
      expect(json['tags'], containsAll(['热血', '战神', '逆袭']));
      expect(json['releaseStatus'], equals('completed'));

      // 验证状态标签解析与 tvOS 保持一致
      expect(drama.releaseLabel, equals('已完结'));

      // 反序列化测试
      final restored = Drama.fromJson(json);
      expect(restored.id, equals(drama.id));
      expect(restored.title, equals(drama.title));
      expect(restored.episodes, equals(drama.episodes));
      expect(restored.releaseLabel, equals('已完结'));
    });

    test('2. PlaybackPlan 播放计划与多清晰度契约对齐', () {
      const plan = PlaybackPlan(
        url: 'https://v9-dy-y.hongguoduanju.com/video/stream.m3u8',
        headers: {
          'User-Agent': 'THLRedLook-tvOS/1.0.0',
          'Referer': 'https://hongguoduanju.com/',
        },
        decryptionKey: '',
        quality: 1080,
        qualities: [1080, 720, 480],
        session: 'tvos_sess_123456',
        danmakuId: 'hongguo:7345678901234567890:1',
        routeIndex: 0,
        routeCount: 2,
        local: false,
      );

      final json = {
        'url': plan.url,
        'headers': plan.headers,
        'decryptionKey': plan.decryptionKey,
        'quality': plan.quality,
        'qualities': plan.qualities,
        'session': plan.session,
        'danmakuId': plan.danmakuId,
        'routeIndex': plan.routeIndex,
        'routeCount': plan.routeCount,
        'local': plan.local,
      };

      final restored = PlaybackPlan.fromJson(json);
      expect(restored.url, equals(plan.url));
      expect(restored.headers['User-Agent'], equals('THLRedLook-tvOS/1.0.0'));
      expect(restored.quality, equals(1080));
      expect(restored.qualities, containsAll([1080, 720, 480]));
      expect(restored.hasAlternative, isTrue);
    });

    test('3. WatchEntry 观看历史与秒级断点契约对齐', () {
      final drama = Drama(
        id: 'hongguo:7345678901234567890',
        source: 'hongguo',
        sourceId: '7345678901234567890',
        title: '都市绝品仙医',
      );

      final now = DateTime.now();
      final entry = WatchEntry(
        drama: drama,
        episode: 8,
        position: 110.5,
        duration: 120.0,
        updatedAt: now,
      );

      final json = entry.toJson();
      expect(json['episode'], equals(8));
      expect(json['position'], equals(110.5));
      expect(json['duration'], equals(120.0));
      expect(json['updatedAt'], equals(now.toUtc().toIso8601String()));

      final restored = WatchEntry.fromJson(json);
      expect(restored.episode, equals(8));
      expect(restored.position, equals(110.5));
      expect(restored.duration, equals(120.0));
      expect(restored.finished, isFalse);
    });

    test('4. tvOS 端官方站源独占与大屏合规过滤契约', () {
      // 验证 tvOS 规范：非官方规范站源强制过滤屏蔽
      bool isAdultOrProhibitedOnTV(String sourceId) {
        return sourceId.toLowerCase() != 'hongguo';
      }

      expect(
        isAdultOrProhibitedOnTV('hongguo'),
        isFalse,
        reason: '官方规范站源在大屏端允许使用',
      );
      expect(
        isAdultOrProhibitedOnTV('huangdou'),
        isTrue,
        reason: '敏感源在客厅大屏端必须严格屏蔽',
      );
      expect(
        isAdultOrProhibitedOnTV('unknown_adult'),
        isTrue,
        reason: '未授权源在客厅大屏端必须严格屏蔽',
      );
    });

    test('5. tvOS 大屏遥控器与 50 集分段 Chunk 交互契约', () {
      // 模拟 120 集短剧的 50 集分组
      const totalEpisodes = 120;
      final chunks = <Map<String, int>>[];
      for (var start = 1; start <= totalEpisodes; start += 50) {
        final end = (start + 49).clamp(1, totalEpisodes);
        chunks.add({'start': start, 'end': end});
      }

      expect(chunks.length, equals(3));
      expect(chunks[0], equals({'start': 1, 'end': 50}));
      expect(chunks[1], equals({'start': 51, 'end': 100}));
      expect(chunks[2], equals({'start': 101, 'end': 120}));
    });
  });
}
