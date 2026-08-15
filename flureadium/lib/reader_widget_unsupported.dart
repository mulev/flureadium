import 'package:flutter/material.dart';
import 'package:flureadium/flureadium.dart';

import 'reader_channel.dart';

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

class ReadiumReaderWidget extends StatelessWidget {
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

  /// Not invoked on unsupported platforms.
  final void Function(Offset position)? onTap;

  final Function(String)? onExternalLinkActivated;
  final void Function(Locator)? onLocatorChanged;

  /// Not invoked on unsupported platforms.
  final VoidCallback? onReady;

  @override
  Widget build(final BuildContext context) =>
      Center(child: Text('ReaderWidget is not available on this platform.'));
}
