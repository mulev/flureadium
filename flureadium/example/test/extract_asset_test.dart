import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../integration_test/helpers/extract_asset.dart';

void main() {
  // extractAsset does real file I/O, which only completes on the real event
  // loop — so these are plain tests rather than testWidgets bodies, whose fake
  // async never lets the write finish.
  TestWidgetsFlutterBinding.ensureInitialized();

  const asset = 'assets/pubs/sample_comic.cbz';

  test('writes the asset bytes to a readable file', () async {
    final path = await extractAsset(asset);
    final file = File(path);

    expect(file.existsSync(), isTrue);
    expect(
      file.readAsBytesSync(),
      (await rootBundle.load(asset)).buffer.asUint8List(),
    );
    expect(path, endsWith('sample_comic.cbz'));
  });

  test('repeat extractions of one asset cannot overwrite each other', () async {
    // Two calls in the same millisecond used to resolve to the same path, so
    // the second write truncated the file the first caller had already handed
    // to loadPublication. Each extraction gets its own directory instead.
    final first = await extractAsset(asset);
    final second = await extractAsset(asset);

    expect(File(first).parent.path, isNot(File(second).parent.path));
    expect(File(first).existsSync(), isTrue);
    expect(File(second).existsSync(), isTrue);
  });
}
