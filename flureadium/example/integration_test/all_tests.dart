// Every integration suite. The only aggregator for a device run: what an
// environment cannot support is excluded with `--exclude-tags`, not by
// leaving an import out.
//
// A file omitted from a list is invisible — nothing fails, the tests just
// never run. That is how the whole audiobook group went unrun in Android CI
// (flureadium-29l). Tags put the requirement in the test that has it, so a
// new file is included by default and can only be skipped by saying why.
//
// Tags in use, both applied to groups rather than as library-level `@Tags`,
// which the runner ignores once a file is imported rather than executed:
//   native  — needs a real audio or TTS engine
//   network — needs the public internet
//
import 'package:integration_test/integration_test.dart';

import 'launch_test.dart' as launch;
import 'audiobook_test.dart' as audiobook;
import 'audiobook_host_test.dart' as audiobook_host;
import 'cbz_test.dart' as cbz;
import 'divina_test.dart' as divina;
import 'epub_test.dart' as epub;
import 'epub_tts_test.dart' as epub_tts;
import 'error_handling_test.dart' as error_handling;
import 'webpub_test.dart' as webpub;
import 'car_transport_test.dart' as car_transport;
import 'text_locator_test.dart' as text_locator;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  launch.main();
  cbz.main();
  divina.main();
  audiobook_host.main();
  audiobook.main();
  epub.main();
  epub_tts.main();
  error_handling.main();
  webpub.main();
  car_transport.main();
  text_locator.main();
}
