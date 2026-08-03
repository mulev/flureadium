import 'dart:io';

import 'package:flutter/services.dart';

/// Copies a bundled asset to a uniquely named temp file and returns its path.
///
/// `loadPublication` and `openPublication` need a real filesystem path, and the
/// asset bundle is not one. The timestamp keeps repeat calls from colliding, so
/// a suite can extract the same asset more than once.
Future<String> extractAsset(String assetPath) async {
  final bytes = await rootBundle.load(assetPath);
  final filename = assetPath.split('/').last;
  final tmp = File(
    '${Directory.systemTemp.path}/${DateTime.now().millisecondsSinceEpoch}_$filename',
  );
  await tmp.writeAsBytes(bytes.buffer.asUint8List());
  return tmp.path;
}
