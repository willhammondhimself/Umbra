import XCTest

@MainActor
final class UmbraUITests: XCTestCase {
    let app = XCUIApplication()

    override func setUpWithError() throws {
        continueAfterFailure = false
        app.launch()
    }

    func testAppLaunches() throws {
        XCTAssertTrue(app.windows.count > 0)
    }

    func testTabsExist() throws {
        XCTAssertTrue(app.buttons["Plan"].exists || app.staticTexts["Plan"].exists)
    }
}
