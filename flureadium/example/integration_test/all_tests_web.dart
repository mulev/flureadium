import 'package:integration_test/integration_test.dart';

import 'launch_test.dart' as launch;
import 'epub_tts_web_test.dart' as epub_tts_web;

// Web reader support is work in progress. The launch smoke test runs live;
// epub_tts_web_test is bundled but its tests are skipped in-file until the
// web-reader TTS plumbing (onErrorEvent, applyDecorations, navigator init)
// lands — so the web suite still references every web integration test.
//
// Not bundled here (they run on mobile via all_tests.dart, not on web):
// - epub_test, epub_navigation_test: packed EPUB files cannot be served via
//   HTTP URL on web
// - webpub_test: requires container div init inside ReadiumWebView on web

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  launch.main();
  epub_tts_web.main(); // tests skipped in-file until web-reader TTS lands
}
