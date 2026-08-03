import 'dart:io';

import 'package:flutter/services.dart';

/// Copies a bundled asset to a temp file and returns its path.
///
/// `loadPublication` and `openPublication` need a real filesystem path, and the
/// asset bundle is not one. Each call gets its own temp directory, so a suite
/// can extract the same asset more than once without one copy overwriting the
/// file another caller is still reading.
Future<String> extractAsset(String assetPath) async {
  final bytes = await rootBundle.load(assetPath);
  final dir = Directory.systemTemp.createTempSync('flureadium_asset_');
  final tmp = File('${dir.path}/${assetPath.split('/').last}');
  await tmp.writeAsBytes(bytes.buffer.asUint8List());
  return tmp.path;
}
