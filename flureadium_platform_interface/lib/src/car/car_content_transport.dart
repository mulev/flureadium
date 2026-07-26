import 'package:flutter/services.dart';

import 'car_browse_node.dart';
import 'car_content_provider.dart';
import 'car_content_strings.dart';

/// Routes native car head-unit requests to the registered [CarContentProvider]
/// over a [MethodChannel] (the ADR's variant (a): headless engine + channel).
///
/// The handler is installed at construction so a cold-launched car process can
/// call in before the host registers a provider; until then every request
/// resolves to a typed empty result rather than throwing, matching the
/// "app not ready" case. The channel is injectable for tests.
class CarContentTransport {
  CarContentTransport({MethodChannel? channel})
    : _channel = channel ?? const MethodChannel(_channelName) {
    _channel.setMethodCallHandler(_handle);
  }

  static const String _channelName = 'dev.mulev.flureadium/car';

  final MethodChannel _channel;
  CarContentProvider? _provider;
  CarContentStrings? _strings;

  /// Stores the host's provider and localized strings so incoming native
  /// requests can be answered.
  void register(
    CarContentProvider provider, {
    required CarContentStrings strings,
  }) {
    _provider = provider;
    _strings = strings;
  }

  /// Clears the provider and strings; the channel handler stays installed and
  /// resolves subsequent requests to empty results.
  void unregister() {
    _provider = null;
    _strings = null;
  }

  Future<Object?> _handle(MethodCall call) async {
    final provider = _provider;
    switch (call.method) {
      case 'rootTabs':
        if (provider == null) return const <Object?>[];
        return [for (final tab in await provider.rootTabs()) tab.toMap()];
      case 'children':
        if (provider == null) return const <Object?>[];
        return _encodeNodes(
          await provider.children(_stringArg(call, 'nodeId')),
        );
      case 'search':
        if (provider == null) return const <Object?>[];
        return _encodeNodes(await provider.search(_stringArg(call, 'query')));
      case 'nowPlayingChapters':
        if (provider == null) return const <Object?>[];
        return _encodeNodes(await provider.nowPlayingChapters());
      case 'play':
        if (provider == null) return null;
        await provider.play(_stringArg(call, 'nodeId'));
        return null;
      case 'strings':
        return _strings?.toMap();
      default:
        return null;
    }
  }

  List<Map<String, Object?>> _encodeNodes(List<CarBrowseNode> nodes) => [
    for (final node in nodes) node.toMap(),
  ];

  String _stringArg(MethodCall call, String key) =>
      (call.arguments as Map)[key] as String;
}
