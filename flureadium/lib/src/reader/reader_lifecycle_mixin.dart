import 'package:flureadium_platform_interface/flureadium_platform_interface.dart';

/// Mixin for managing reader widget lifecycle.
///
/// Handles registration and cleanup of the reader widget with the platform instance.
mixin ReaderLifecycleMixin {
  /// Gets the platform instance.
  FlureadiumPlatform get readium => FlureadiumPlatform.instance;

  /// Sets this widget as the current reader in the platform instance.
  ///
  /// Should be called during widget initialization.
  void setCurrentWidgetInterface(ReadiumReaderWidgetInterface widget) {
    R2Log.d('Set current reader in plugin');
    readium.currentReaderWidget = widget;

    // A navigation config set before any reader existed was stored on the
    // platform and forwarded to a null currentReaderWidget, which dropped it
    // in silence. Registration is the first moment it can land: reader_widget
    // calls this from _onPlatformViewCreated only after assigning _channel, so
    // the widget has a channel to send on.
    //
    // The stored config is deliberately left in place. It is the platform's
    // last known config, and a publication swap unregisters this widget and
    // registers a fresh one over a new native view that needs it again.
    final config = readium.defaultNavigationConfig;
    if (config != null) {
      widget.setNavigationConfig(config);
    }
  }

  /// Cleans up reader widget registration.
  ///
  /// Should be called during widget disposal.
  void cleanupWidgetInterface(String? channelName) {
    R2Log.d('cleanup $channelName!');
    readium.currentReaderWidget = null;
  }
}
