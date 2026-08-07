import Flutter
import Foundation
import UIKit
import ReadiumShared

class ReadiumReaderViewFactory: NSObject, @preconcurrency FlutterPlatformViewFactory {
    private weak var registrar: FlutterPluginRegistrar?

  init(registrar: FlutterPluginRegistrar?) {
    self.registrar = registrar
    super.init()
  }

  @MainActor func create(
        withFrame frame: CGRect,
        viewIdentifier viewId: Int64,
        arguments args: Any?
    ) -> FlutterPlatformView {
        if let publication = getCurrentPublication() {
            switch readerViewKind(for: publication) {
            case .pdf:
                return PdfReaderView(
                    frame: frame,
                    viewIdentifier: viewId,
                    arguments: args,
                    registrar: registrar!)
            case .image:
                return ImageReaderView(
                    frame: frame,
                    viewIdentifier: viewId,
                    arguments: args,
                    registrar: registrar!)
            case .audio:
                // No frame or arguments: the host renders nothing, and
                // preferences and initialLocator only mean something to a
                // navigator.
                return AudioReaderView(
                    viewIdentifier: viewId,
                    messenger: registrar!.messenger())
            case .epub:
                break
            }
        }

        // Default to EPUB reader
        return ReadiumReaderView(
            frame: frame,
            viewIdentifier: viewId,
            arguments: args,
            registrar: registrar!)
    }

  // Undocumented, but boilerplate function required for creationParams to not silently become nil!
  // https://github.com/flutter/flutter/issues/28124
  func createArgsCodec() -> FlutterMessageCodec & NSObjectProtocol {
    return FlutterStandardMessageCodec.sharedInstance()
  }
}
