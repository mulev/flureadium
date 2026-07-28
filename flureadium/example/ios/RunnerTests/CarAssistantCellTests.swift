import CarPlay
import XCTest

@testable import flureadium

/// Covers the Search tab's Siri assistant-cell configuration: it sits at the top,
/// stays always visible, and declares the `.playMedia` Siri action — the only
/// action audio apps may use, which routes the tap to `INPlayMediaIntent`.
@available(iOS 15.0, *)
final class CarAssistantCellTests: XCTestCase {

  func testConfigurationIsTopAlwaysVisibleAndPlayMedia() {
    let config = CarAssistantCell.configuration()

    XCTAssertEqual(config.position, .top)
    XCTAssertEqual(config.visibility, .always)
    XCTAssertEqual(config.assistantAction, .playMedia)
  }
}
