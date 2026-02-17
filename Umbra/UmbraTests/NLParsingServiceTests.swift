import XCTest
@testable import Umbra
import UmbraKit

final class NLParsingServiceTests: XCTestCase {
    let parser = NLParsingService()

    func testBasicTaskExtraction() {
        let results = parser.parse("write thesis intro")
        XCTAssertEqual(results.count, 1)
        XCTAssertTrue(results[0].title.lowercased().contains("thesis"))
    }

    func testTimeEstimateHours() {
        let results = parser.parse("write thesis intro for 2 hours")
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results[0].estimateMinutes, 120)
    }

    func testTimeEstimateMinutes() {
        let results = parser.parse("prep slides 45 minutes")
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results[0].estimateMinutes, 45)
    }

    func testTimeEstimateShorthand() {
        let results = parser.parse("review code 30m")
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results[0].estimateMinutes, 30)
    }

    func testMultipleTasksWithThen() {
        let results = parser.parse("write thesis intro for 2 hours then prep slides 45 minutes")
        XCTAssertEqual(results.count, 2)
    }

    func testMultipleTasksWithNewlines() {
        let input = """
        write thesis intro 2h
        prep slides 45m
        review notes 30m
        """
        let results = parser.parse(input)
        XCTAssertEqual(results.count, 3)
    }

    func testUrgentPriority() {
        let results = parser.parse("fix the bug urgently")
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results[0].priority, .urgent)
    }

    func testHighPriority() {
        let results = parser.parse("important: review the PR")
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results[0].priority, .high)
    }

    func testLowPriority() {
        let results = parser.parse("clean desk if I have time")
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results[0].priority, .low)
    }

    func testDefaultMediumPriority() {
        let results = parser.parse("write documentation")
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results[0].priority, .medium)
    }

    func testEmptyInput() {
        let results = parser.parse("")
        XCTAssertTrue(results.isEmpty)
    }

    func testWhitespaceOnlyInput() {
        let results = parser.parse("   \n\t  ")
        XCTAssertTrue(results.isEmpty)
    }

    func testNumberedList() {
        let input = """
        1. Write thesis intro 2h
        2. Prep slides 45m
        3. Email advisor
        """
        let results = parser.parse(input)
        XCTAssertGreaterThanOrEqual(results.count, 3)
    }
}
