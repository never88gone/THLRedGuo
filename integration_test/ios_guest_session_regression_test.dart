import 'package:integration_test/integration_test.dart';

import '../test/hongguo_guest_session_test.dart' as regression;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  regression.main();
}
