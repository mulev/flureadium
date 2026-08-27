import Foundation
import os

/// Subsystem the integration runner filters its `simctl log stream` predicate on.
///
/// `scripts/run_integration_tests.sh` streams `subsystem == "dev.mulev.flureadium"` into
/// `ios_native.log`. Renaming this without changing that predicate silently empties the file,
/// which is why `ReaderLogTests` pins the string.
let readerLogSubsystem = "dev.mulev.flureadium"

private let readerLogHandle = OSLog(subsystem: readerLogSubsystem, category: "reader")

/// Formatting for a reader diagnostic, kept apart from the emit so it can be tested
/// without a log sink.
enum ReaderLog {

  /// The single line a diagnostic becomes: tag, one space, message — byte-identical to what
  /// `print(TAG, message)` used to produce, so existing greps over the logs keep working.
  static func format(tag: String, message: String) -> String {
    "\(tag) \(message)"
  }
}

/// Emits a reader diagnostic to the unified log, where `simctl log stream` can capture it.
///
/// `%{public}@` is not decoration. `os_log` redacts `%@` arguments to `<private>` by default, so
/// the plain form would fill `ios_native.log` with `<private>` and defeat the point of capturing it.
func readerLog(_ tag: String, _ message: String) {
  os_log(
    "%{public}@", log: readerLogHandle, type: .default,
    ReaderLog.format(tag: tag, message: message))
}
