import XCTest
@testable import Tether
import TetherKit

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

    func testTimeEstimateFractionalHours() {
        let results = parser.parse("study math for 1.5 hours")
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results[0].estimateMinutes, 90)
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

    func testMultipleTasksWithSemicolons() {
        let results = parser.parse("write thesis; prep slides; review notes")
        XCTAssertEqual(results.count, 3)
    }

    func testMultipleTasksWithConjunction() {
        let results = parser.parse("write thesis report and review the slides")
        XCTAssertEqual(results.count, 2)
    }

    func testUrgentPriority() {
        let results = parser.parse("fix the bug urgently")
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results[0].priority, .urgent)
    }

    func testASAPPriority() {
        let results = parser.parse("deploy hotfix asap")
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results[0].priority, .urgent)
    }

    func testExclamationPriority() {
        let results = parser.parse("fix login bug !!")
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

    func testDueDateTomorrow() {
        let results = parser.parse("submit report by tomorrow")
        XCTAssertEqual(results.count, 1)
        XCTAssertNotNil(results[0].dueDate)
        let calendar = Calendar.current
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: Date()))!
        XCTAssertTrue(calendar.isDate(results[0].dueDate!, inSameDayAs: tomorrow))
    }

    func testDueDateToday() {
        let results = parser.parse("finish homework due today")
        XCTAssertEqual(results.count, 1)
        XCTAssertNotNil(results[0].dueDate)
        let today = Calendar.current.startOfDay(for: Date())
        XCTAssertTrue(Calendar.current.isDate(results[0].dueDate!, inSameDayAs: today))
    }

    func testProjectBracketSyntax() {
        let results = parser.parse("write intro [Thesis]")
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results[0].projectName, "Thesis")
    }

    func testProjectKeywordSyntax() {
        let results = parser.parse("write intro for the thesis project")
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results[0].projectName?.lowercased(), "thesis")
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

    func testTitleCapitalization() {
        let results = parser.parse("review pull request")
        XCTAssertEqual(results.count, 1)
        XCTAssertTrue(results[0].title.first?.isUppercase == true)
    }

    func testCombinedEstimateAndPriority() {
        let results = parser.parse("fix auth bug urgently 2h")
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results[0].priority, .urgent)
        XCTAssertEqual(results[0].estimateMinutes, 120)
    }

    func testNicToHaveLowPriority() {
        let results = parser.parse("refactor utils nice to have")
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results[0].priority, .low)
    }
}
