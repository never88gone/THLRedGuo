import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import '../test/icloud_sync_regression_test.dart' as regression;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  regression.runICloudRegressionTests(
    fixtureJson: r'''{
  "history": [
    {
      "drama": {
        "metadataSchema": 1,
        "id": "hongguo:7688558312157088793",
        "source": "hongguo",
        "sourceId": "7688558312157088793",
        "title": "同步合成短剧",
        "description": "合成同步数据",
        "cover": "",
        "episodes": 24,
        "category": "真人剧",
        "vip": false,
        "heat": "",
        "views": "",
        "onlineDate": "",
        "tags": [],
        "releaseStatus": "finished"
      },
      "episode": 3,
      "position": 45.25,
      "duration": 120,
      "updatedAt": "2026-10-24T08:05:01.123456Z"
    }
  ],
  "follows": {
    "follows": {
      "hongguo:7688558312157088793": "watching"
    },
    "dramas": [
      {
        "metadataSchema": 1,
        "id": "hongguo:7688558312157088793",
        "source": "hongguo",
        "sourceId": "7688558312157088793",
        "title": "同步合成短剧",
        "description": "合成同步数据",
        "cover": "",
        "episodes": 24,
        "category": "真人剧",
        "vip": false,
        "heat": "",
        "views": "",
        "onlineDate": "",
        "tags": [],
        "releaseStatus": "finished"
      }
    ],
    "updatedAt": "2026-10-24T08:05:01.123456Z"
  },
  "settings": {
    "source": "hongguo",
    "danmaku": false,
    "speed": 1,
    "quality": 720,
    "updatedAt": "2026-10-24T08:05:01.123456Z"
  }
}
''',
  );
  testWidgets(
    'native iCloud channel returns a synchronize result without writing records',
    (tester) async {
      debugDefaultTargetPlatformOverride = null;
      final value = await const MethodChannel(
        'duanju/icloud',
      ).invokeMethod<bool>('synchronize');
      expect(value, isA<bool>());
      debugPrint(
        'THL_ICLOUD_NATIVE_IOS synchronize=$value cloudTransportVerified=false',
      );
    },
  );
}
