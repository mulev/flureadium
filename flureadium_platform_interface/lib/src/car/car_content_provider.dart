import 'car_browse_node.dart';
import 'car_tab.dart';

/// The contract a host app implements to answer a car head unit's browse,
/// search, and playback requests.
///
/// flureadium never constructs a provider; the host registers one via
/// `Flureadium.registerCarContentProvider`. Every method is async because the
/// car callbacks may run before any UI is alive (cold launch) and the host
/// answers from its own library store.
abstract class CarContentProvider {
  /// The root tabs, e.g. Continue · Library · Search.
  Future<List<CarTab>> rootTabs();

  /// The rows nested under [nodeId] (a tab id or a container node id).
  Future<List<CarBrowseNode>> children(String nodeId);

  /// The rows matching [query] across the host's library.
  Future<List<CarBrowseNode>> search(String query);

  /// Starts playback for [nodeId]; the host decides audiobook vs read-aloud.
  Future<void> play(String nodeId);

  /// The chapters of the currently playing publication, if any.
  Future<List<CarBrowseNode>> nowPlayingChapters();
}
