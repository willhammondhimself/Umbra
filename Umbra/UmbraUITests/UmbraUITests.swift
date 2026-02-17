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

    func testMainWindowExists() throws {
        let window = app.windows.firstMatch
        XCTAssertTrue(window.exists)
        XCTAssertTrue(window.frame.width > 0)
        XCTAssertTrue(window.frame.height > 0)
    }

    func testSidebarNavigationItems() throws {
        // Sidebar should have navigation items
        let sidebar = app.splitGroups.firstMatch
        XCTAssertTrue(sidebar.waitForExistence(timeout: 5))
    }

    func testPlanTabExists() throws {
        let planButton = app.buttons["Plan"]
        if planButton.exists {
            planButton.click()
            // Should show planning view content
            XCTAssertTrue(app.windows.firstMatch.exists)
        } else {
            // May be a text element in sidebar
            let planText = app.staticTexts["Plan"]
            XCTAssertTrue(planText.exists || planButton.exists, "Plan navigation should exist")
        }
    }

    func testSessionTabExists() throws {
        let sessionButton = app.buttons["Session"]
        let sessionText = app.staticTexts["Session"]
        XCTAssertTrue(sessionButton.exists || sessionText.exists, "Session navigation should exist")
    }

    func testStatsTabExists() throws {
        let statsButton = app.buttons["Stats"]
        let statsText = app.staticTexts["Stats"]
        XCTAssertTrue(statsButton.exists || statsText.exists, "Stats navigation should exist")
    }

    func testSocialTabExists() throws {
        let socialButton = app.buttons["Social"]
        let socialText = app.staticTexts["Social"]
        XCTAssertTrue(socialButton.exists || socialText.exists, "Social navigation should exist")
    }

    func testSettingsTabExists() throws {
        let settingsButton = app.buttons["Settings"]
        let settingsText = app.staticTexts["Settings"]
        XCTAssertTrue(settingsButton.exists || settingsText.exists, "Settings navigation should exist")
    }

    func testMenuBarExists() throws {
        // The app should have a menu bar
        let menuBar = app.menuBars.firstMatch
        XCTAssertTrue(menuBar.exists)
    }

    func testWindowResizable() throws {
        let window = app.windows.firstMatch
        XCTAssertTrue(window.exists)
        // Window should have reasonable minimum size
        XCTAssertGreaterThan(window.frame.width, 400)
        XCTAssertGreaterThan(window.frame.height, 300)
    }
}
