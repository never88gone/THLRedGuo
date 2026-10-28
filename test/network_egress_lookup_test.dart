import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:THLRedLook/core/diagnostics/network_egress_lookup.dart';
import 'package:THLRedLook/core/diagnostics/source_diagnostics.dart';
import 'package:THLRedLook/pages/settings/source_diagnostics_page.dart';

void main() {
  const fixture =
      '{"ip":"203.0.113.23","country":"Synthetic Region","country_code":"TW","region":"Synthetic State","city":"Synthetic City","latitude":1,"longitude":2,"cookie":"private-cookie"}';
  test(
    'IPv4 and IPv6 retain location provenance without unrelated response fields',
    () {
      for (final ip in ['203.0.113.23', '2001:db8::23']) {
        final result = NetworkEgressLookup.parse(
          fixture.replaceFirst('203.0.113.23', ip),
          provider: 'IP.SB',
        )!;
        expect(result.ip, ip);
        expect(result.countryCode, 'TW');
        expect(result.location, contains('Synthetic Region'));
        expect(result.reportLines.join('\n'), contains('IP.SB'));
        expect(result.reportLines.join('\n'), contains('分流'));
        expect(
          result.reportLines.join('\n'),
          isNot(contains('private-cookie')),
        );
        expect(result.reportLines.join('\n'), isNot(contains('latitude')));
      }
    },
  );
  test(
    'invalid, oversized or refused responses cannot become an IP address',
    () {
      for (final value in [
        '<html>denied</html>',
        '{"ip":"not-an-ip"}',
        '{"ip":"203.0.113.23","success":false}',
        jsonEncode({'ip': '203.0.113.23', 'country': 'x' * 40000}),
      ]) {
        expect(NetworkEgressLookup.parse(value, provider: 'Synthetic'), isNull);
      }
    },
  );
  test(
    'provider failure falls back and keeps the successful provider snapshot intact',
    () async {
      final hosts = <String>[];
      final client = MockClient((request) async {
        hosts.add(request.url.host);
        expect(request.url.query, isEmpty);
        expect(request.headers.containsKey('cookie'), isFalse);
        return hosts.length == 1
            ? http.Response('', 403)
            : http.Response(fixture, 200);
      });
      addTearDown(client.close);
      final result = await NetworkEgressLookup(client: client).lookup();
      expect(result.ip, '203.0.113.23');
      expect(result.provider, 'IPWho.is');
      expect(hosts, ['api.ip.sb', 'ipwho.is']);
    },
  );
  test(
    'diagnostic refresh coalesces requests, caches and includes full requested IP in export',
    () async {
      var calls = 0;
      final client = MockClient((request) async {
        calls++;
        return http.Response(fixture, 200);
      });
      addTearDown(client.close);
      final recorder = SourceDiagnostics(
        networkLookup: NetworkEgressLookup(client: client),
      );
      addTearDown(recorder.dispose);
      await Future.wait([
        recorder.refreshNetworkEgress(),
        recorder.refreshNetworkEgress(),
      ]);
      await recorder.refreshNetworkEgress();
      expect(calls, 1);
      await recorder.refreshNetworkEgress(force: true);
      expect(calls, 2);
      final report = recorder.report(version: '1.0.0', sourceHash: 'synthetic');
      expect(report, contains('203.0.113.23'));
      expect(report, contains('[TW]'));
      expect(report, contains('IP 检测时间'));
      expect(report, isNot(contains('private-cookie')));
      expect(recorder.entries, isEmpty);
    },
  );
  test(
    'both providers failing cannot block diagnostics or invent a region',
    () async {
      final client = MockClient((request) async => http.Response('', 503));
      addTearDown(client.close);
      final recorder = SourceDiagnostics(
        networkLookup: NetworkEgressLookup(client: client),
      );
      addTearDown(recorder.dispose);
      await recorder.refreshNetworkEgress();
      expect(recorder.networkEgress!.ip, isEmpty);
      expect(recorder.networkEgress!.location, '归属地未知');
      expect(
        recorder.report(version: '1.0.0', sourceHash: 'synthetic'),
        contains('HTTP_503'),
      );
      expect(recorder.entries, isEmpty);
    },
  );
  testWidgets(
    'phone diagnostic page displays IP and region without a narrow-screen overflow',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      PackageInfo.setMockInitialValues(
        appName: 'THL',
        packageName: 'synthetic',
        version: '1.0.0',
        buildNumber: '262901343',
        buildSignature: '',
      );
      final client = MockClient((request) async => http.Response(fixture, 200));
      addTearDown(client.close);
      final recorder = SourceDiagnostics(
        networkLookup: NetworkEgressLookup(client: client),
      );
      addTearDown(recorder.dispose);
      await tester.runAsync(() => recorder.refreshNetworkEgress());
      await tester.pumpWidget(
        MaterialApp(home: SourceDiagnosticsPage(diagnostics: recorder)),
      );
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('source-diagnostics-egress')),
        findsOneWidget,
      );
      expect(find.textContaining('203.0.113.23'), findsOneWidget);
      expect(find.textContaining('Synthetic Region'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
