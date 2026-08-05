import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flureadium_platform_interface/flureadium_platform_interface.dart';
import 'package:rxdart/rxdart.dart';

import 'reader_channel.dart';
import 'src/reader/orientation_handler_mixin.dart';
import 'src/reader/reader_lifecycle_mixin.dart';
import 'src/reader/toc_skip_navigation_mixin.dart';
import 'src/reader/wakelock_manager_mixin.dart';

const _viewType = 'dev.mulev.flureadium/ReadiumReaderWidget';

@visibleForTesting
ReadiumReaderChannel createReadiumReaderChannel(
  int id, {
  required ValueChanged<Locator> onPageChanged,
  ValueChanged<String>? onExternalLinkActivated,
}) {
  return ReadiumReaderChannel(
    '$_viewType:$id',
    onPageChanged: onPageChanged,
    onExternalLinkActivated: onExternalLinkActivated,
  );
}

/// A ReadiumReaderWidget wraps a native Kotlin/Swift Readium navigator widget.
class ReadiumReaderWidget extends StatefulWidget {
  const ReadiumReaderWidget({
    required this.publication,
    this.loadingWidget = const Center(child: CircularProgressIndicator()),
    this.initialLocator,
    this.onTap,
    this.onGoLeft,
    this.onGoRight,
    this.onSwipe,
    this.onExternalLinkActivated,
    this.onLocatorChanged,
    this.onReady,
    super.key,
  });

  final Publication publication;
  final Widget loadingWidget;
  final Locator? initialLocator;
  final VoidCallback? onTap;
  final VoidCallback? onGoLeft;
  final VoidCallback? onGoRight;
  final VoidCallback? onSwipe;
  final Function(String)? onExternalLinkActivated;
  final void Function(Locator)? onLocatorChanged;

  /// Called once when the native platform view has been created and all
  /// EventChannel handlers are registered. Safe to subscribe to
  /// [Flureadium.onReaderStatusChanged], [Flureadium.onTextLocatorChanged],
  /// and [Flureadium.onErrorEvent] from within this callback on all platforms.
  final VoidCallback? onReady;

  @override
  State<StatefulWidget> createState() => _ReadiumReaderWidgetState();
}

class _ReadiumReaderWidgetState extends State<ReadiumReaderWidget>
    with
        WakelockManagerMixin,
        ReaderLifecycleMixin,
        OrientationHandlerMixin,
        TocSkipNavigationMixin
    implements ReadiumReaderWidgetInterface {
  ReadiumReaderChannel? _channel;
  Locator? _currentLocator;
  StreamSubscription<Locator>? _locatorDebugSub;
  bool isReady = false;

  final _isReadyCompleter = Completer<Locator>();

  late Widget _readerWidget;

  EPUBPreferences? get _defaultPreferences {
    return readium.defaultPreferences;
  }

  PDFPreferences? get _defaultPdfPreferences {
    return readium.defaultPdfPreferences;
  }

  @override
  void initState() {
    super.initState();
    R2Log.d('ReadiumReaderWidget initiated');

    _readerWidget = _buildNativeReader();
    enableWakelock();
    // setCurrentWidgetInterface is called in _onPlatformViewCreated after
    // _channel is assigned, so that callers receive a widget whose channel
    // is ready to send method calls.
  }

  @override
  void dispose() {
    R2Log.d('ReadiumReaderWidget disposed');
    _locatorDebugSub?.cancel();
    _locatorDebugSub = null;
    cleanupWidgetInterface(_channel?.name);
    _channel?.dispose();
    _channel = null;
    lastOrientation = null;

    disableWakelock();

    super.dispose();
  }

  @override
  Widget build(final BuildContext context) {
    handleOrientationChange(
      currentOrientation: MediaQuery.orientationOf(context),
      isReady: isReady,
      currentLocator: _currentLocator,
      channel: _channel,
    );

    return Listener(
      onPointerDown: (final event) {
        R2Log.d('[TAP-DEBUG] Listener onPointerDown at ${event.position}');
        enableWakelock();
      },
      onPointerUp: (final event) {
        R2Log.d('[TAP-DEBUG] Listener onPointerUp at ${event.position}');
      },
      child: _readerWidget,
    );
  }

  @override
  Future<void> go(
    final Locator locator, {
    required final bool isAudioBookWithText,
    final bool animated = false,
  }) async {
    R2Log.d(() => 'Go to $locator');

    await _channel?.go(
      locator,
      animated: animated,
      isAudioBookWithText: isAudioBookWithText,
    );

    R2Log.d('Done');
  }

  @override
  Future<void> goLeft({final bool animated = true}) async =>
      _channel?.goLeft(animated: animated);

  @override
  Future<void> goRight({final bool animated = true}) async =>
      _channel?.goRight(animated: animated);

  @override
  Future<void> skipToNext({final bool animated = true}) => skipToNextChapter(
    publication: widget.publication,
    currentLocator: _currentLocator,
    channel: _channel,
  );

  @override
  Future<void> skipToPrevious({final bool animated = true}) =>
      skipToPreviousChapter(
        publication: widget.publication,
        currentLocator: _currentLocator,
        channel: _channel,
      );

  @override
  Future<Locator?> getLocatorFragments(final Locator locator) async {
    R2Log.d('getLocatorFragments: $locator');

    await _awaitNativeViewReady();

    return await _channel?.getLocatorFragments(locator);
  }

  @override
  Future<Locator?> getCurrentLocator() async {
    R2Log.d('GetCurrentLocator()');
    return _channel?.getCurrentLocator();
  }

  @override
  Future<void> setEPUBPreferences(EPUBPreferences preferences) async {
    _channel?.setEPUBPreferences(preferences);
  }

  @override
  Future<void> setPDFPreferences(PDFPreferences preferences) async {
    _channel?.setPDFPreferences(preferences);
  }

  @override
  Future<void> setNavigationConfig(ReaderNavigationConfig config) async {
    _channel?.setNavigationConfig(config);
  }

  @override
  Future<void> applyDecorations(
    String id,
    List<ReaderDecoration> decorations,
  ) async {
    await _channel?.applyDecorations(id, decorations);
  }

  Widget _buildNativeReader() {
    final publication = widget.publication;

    R2Log.d(publication.identifier);

    // Check if this is a PDF publication by looking at reading order media types
    final isPdf = publication.readingOrder.any(
      (link) => link.type?.contains('pdf') ?? false,
    );

    // Use PDF preferences for PDF publications, EPUB preferences for others
    final defaultPreferences = isPdf
        ? _defaultPdfPreferences?.toJson()
        : _defaultPreferences?.toJson();

    final creationParams = <String, dynamic>{
      'pubIdentifier': publication.identifier,
      'preferences': defaultPreferences,
      'initialLocator': widget.initialLocator == null
          ? null
          : json.encode(widget.initialLocator),
    };

    R2Log.d('creationParams=$creationParams');

    if (Platform.isAndroid) {
      return PlatformViewLink(
        viewType: _viewType,
        surfaceFactory: (final context, final controller) => AndroidViewSurface(
          controller: controller as AndroidViewController,
          gestureRecognizers: const {},
          hitTestBehavior: PlatformViewHitTestBehavior.opaque,
        ),
        onCreatePlatformView: (final params) =>
            PlatformViewsService.initSurfaceAndroidView(
                id: params.id,
                viewType: _viewType,
                layoutDirection: TextDirection.ltr,
                creationParams: creationParams,
                creationParamsCodec: const StandardMessageCodec(),
              )
              ..addOnPlatformViewCreatedListener(params.onPlatformViewCreated)
              ..addOnPlatformViewCreatedListener(_onPlatformViewCreated)
              ..create(),
      );
    } else if (Platform.isIOS) {
      return UiKitView(
        viewType: _viewType,
        layoutDirection: TextDirection.ltr,
        creationParams: creationParams,
        creationParamsCodec: const StandardMessageCodec(),
        onPlatformViewCreated: _onPlatformViewCreated,
      );
    }
    return ColoredBox(
      color: const Color(0xffff00ff),
      child: Center(
        child: Text(
          'TODO — Implement ReadiumReaderWidget on ${Platform.operatingSystem}.',
        ),
      ),
    );
  }

  void _onPlatformViewCreated(final int id) {
    _channel = createReadiumReaderChannel(
      id,
      onPageChanged: (final locator) {
        debugPrint('onPageChanged: ${locator.toJson()}');
        _currentLocator = locator;
        widget.onLocatorChanged?.call(locator);

        if (isReady == false) {
          if (mounted) {
            setState(() {
              isReady = true;
            });
          }
          if (!_isReadyCompleter.isCompleted) {
            _isReadyCompleter.complete(locator);
          }
        }
      },
      onExternalLinkActivated: widget.onExternalLinkActivated,
    );

    // Register as current widget only after _channel is assigned.
    // This ensures waitForCurrentReaderWidget() callers receive a widget
    // whose channel is ready, so method calls aren't silently dropped.
    setCurrentWidgetInterface(this);

    // Notify the host widget that the platform view (and all native
    // EventChannel handlers) are ready. Safe to call listen() on
    // onReaderStatusChanged / onTextLocatorChanged / onErrorEvent from here.
    widget.onReady?.call();

    R2Log.d('New widget is: ${_channel?.name}');

    // TODO: This is just to demo how to use and debounce the Stream, remove when appropriate.
    final nativeLocatorStream = readium.onTextLocatorChanged
        .debounceTime(const Duration(milliseconds: 50))
        .asBroadcastStream()
        .distinct();

    _locatorDebugSub?.cancel();
    _locatorDebugSub = nativeLocatorStream.listen((locator) {
      R2Log.d('ReaderWidget.LocatorChanged - $locator');
    });
  }

  Future _awaitNativeViewReady() {
    return _isReadyCompleter.future;
  }
}
