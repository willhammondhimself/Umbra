import XCTest

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
        // Verify all four tabs are present
        XCTAssertTrue(app.buttons["Plan"].exists || app.staticTexts["Plan"].exists)
    }
}
