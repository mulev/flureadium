import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flureadium/flureadium.dart';

import 'reader_channel.dart';
import 'src/index.dart';

const _viewType = 'dev.mulev.flureadium/ReadiumReaderWidget';

@visibleForTesting
ReadiumReaderChannel createReadiumReaderChannel(
  int id, {
  required ValueChanged<Locator> onPageChanged,
  ValueChanged<String>? onExternalLinkActivated,
  void Function(Offset)? onTap,
}) {
  return ReadiumReaderChannel(
    '$_viewType:$id',
    onPageChanged: onPageChanged,
    onExternalLinkActivated: onExternalLinkActivated,
    onTap: onTap,
  );
}

class ReadiumReaderWidget extends StatefulWidget {
  const ReadiumReaderWidget({
    required this.publication,
    this.loadingWidget = const Center(child: CircularProgressIndicator()),
    this.initialLocator,
    this.onTap,
    this.onExternalLinkActivated,
    this.onLocatorChanged,
    this.onReady,
    super.key,
  });

  final Publication publication;
  final Widget loadingWidget;
  final Locator? initialLocator;

  /// Never invoked on web: there is no native tap source.
  final void Function(Offset position)? onTap;

  final Function(String)? onExternalLinkActivated;
  final void Function(Locator)? onLocatorChanged;

  /// Called once when the widget is ready to accept stream subscriptions.
  /// On web, event channels are registered eagerly, so this fires from initState.
  final VoidCallback? onReady;

  @override
  State<ReadiumReaderWidget> createState() => _ReadiumReaderWidgetState();
}

class _ReadiumReaderWidgetState extends State<ReadiumReaderWidget>
    implements ReadiumReaderWidgetInterface {
  @override
  void initState() {
    super.initState();
    R2Log.d('Widget initiated');
    // Web event channels are registered eagerly; fire onReady immediately.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) widget.onReady?.call();
    });
  }

  @override
  void dispose() {
    R2Log.d('Widget disposed');
    super.dispose();

    // Close the publication when the widget is disposed
    Flureadium().closePublication();
  }

  @override
  Widget build(final BuildContext context) {
    return SizedBox.expand(
      child: ReadiumWebView(
        publication: widget.publication,
        currentLocator: widget.initialLocator,
      ),
    );
  }

  @override
  Future<void> go(
    final Locator locator, {
    required final bool isAudioBookWithText,
    final bool animated = false,
  }) async {
    try {
      await JsPublicationChannel.goToLocation(locator.hrefPath);
    } on PlatformException catch (e, stackTrace) {
      final pubID = widget.publication.metadata.identifier;
      throw ReadiumError(
        'Error when navigating to locator: ${e.message}',
        code: e.code,
        data: 'publication id: $pubID. locator: $locator',
        stackTrace: stackTrace,
      );
    }
  }

  @override
  Future<void> goLeft({final bool animated = true}) async {
    JsPublicationChannel.goLeft();
  }

  @override
  Future<void> goRight({final bool animated = true}) async {
    JsPublicationChannel.goRight();
  }

  @override
  // ignore: prefer_expression_function_bodies
  Future<Locator?> getLocatorFragments(final Locator locator) async {
    // Implement this method if needed
    return null;
  }

  @override
  Future<void> skipToPrevious({final bool animated = true}) async {
    R2Log.d('skipToPrevious not implemented in web version');
  }

  @override
  Future<void> skipToNext({final bool animated = true}) async {
    R2Log.d('skipToNext not implemented in web version');
  }

  @override
  Future<Locator?> getCurrentLocator() async {
    R2Log.d('getCurrentLocator not implemented in web version');
    return null;
  }

  @override
  Future<void> setEPUBPreferences(EPUBPreferences preferences) async {
    R2Log.d('setEPUBPreferences not implemented in web version');
  }

  @override
  Future<void> setPDFPreferences(PDFPreferences preferences) async {
    R2Log.d('setPDFPreferences not implemented in web version');
  }

  @override
  Future<void> setNavigationConfig(ReaderNavigationConfig config) async {
    R2Log.d('setNavigationConfig not implemented in web version');
  }

  @override
  Future<void> applyDecorations(
    String id,
    List<ReaderDecoration> decorations,
  ) async {
    R2Log.d('applyDecorations not implemented in web version');
  }
}
