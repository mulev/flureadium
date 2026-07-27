import 'package:integration_test/integration_test.dart';

import 'launch_test.dart' as launch;
import 'audiobook_test.dart' as audiobook;
import 'cbz_test.dart' as cbz;
import 'divina_test.dart' as divina;
import 'epub_test.dart' as epub;
import 'epub_tts_test.dart' as epub_tts;
import 'error_handling_test.dart' as error_handling;
import 'webpub_test.dart' as webpub;
import 'car_transport_test.dart' as car_transport;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  launch.main();
  audiobook.main();
  cbz.main();
  divina.main();
  epub.main();
  epub_tts.main();
  error_handling.main();
  webpub.main();
  car_transport.main();
}
