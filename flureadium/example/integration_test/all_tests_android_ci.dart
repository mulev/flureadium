// Android CI test bundle — excludes TTS, audiobook, and WebPub tests which
// require hardware audio engines or external network access unavailable on
// GitHub-hosted emulators.
import 'package:integration_test/integration_test.dart';

import 'launch_test.dart' as launch;
import 'cbz_test.dart' as cbz;
import 'divina_test.dart' as divina;
import 'epub_test.dart' as epub;
import 'error_handling_test.dart' as error_handling;
import 'car_transport_test.dart' as car_transport;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  launch.main();
  cbz.main();
  divina.main();
  epub.main();
  error_handling.main();
  car_transport.main();
}
