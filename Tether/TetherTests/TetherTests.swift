import XCTest
@testable import Tether

final class TetherTests: XCTestCase {
    func testAppTabProperties() {
        XCTAssertEqual(AppTab.plan.title, "Plan")
        XCTAssertEqual(AppTab.session.title, "Session")
        XCTAssertEqual(AppTab.stats.title, "Stats")
        XCTAssertEqual(AppTab.settings.title, "Settings")

        XCTAssertEqual(AppTab.plan.icon, "text.badge.plus")
        XCTAssertEqual(AppTab.session.icon, "timer")
        XCTAssertEqual(AppTab.stats.icon, "chart.bar.fill")
        XCTAssertEqual(AppTab.settings.icon, "gearshape")
    }

    func testAllTabsCovered() {
        XCTAssertEqual(AppTab.allCases.count, 6)
    }
}
