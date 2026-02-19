import Testing
import Foundation
@testable import TetherKit

// MARK: - NL Parsing Service Tests

struct NLParsingServiceTests {
    let parser = NLParsingService()

    // MARK: - Basic Single Task Parsing

    @Test func parseSingleTask() {
        let results = parser.parse("Write the report")
        #expect(results.count == 1)
        #expect(results[0].title == "Write the report")
    }

    @Test func parseSingleTaskPreservesContent() {
        let results = parser.parse("Review the pull request")
        #expect(results.count == 1)
        #expect(results[0].title.lowercased().contains("review"))
        #expect(results[0].title.lowercased().contains("pull request"))
    }

    @Test func parseTitleCapitalization() {
        let results = parser.parse("review pull request")
        #expect(results.count == 1)
        #expect(results[0].title.first?.isUppercase == true)
    }

    // MARK: - Multi-Task with Newlines

    @Test func parseMultipleTasksWithNewlines() {
        let input = "Task one\nTask two\nTask three"
        let results = parser.parse(input)
        #expect(results.count == 3)
    }

    @Test func parseMultipleTasksWithNewlinesAndWhitespace() {
        let input = """
        Write thesis intro 2h
        Prep slides 45m
        Review notes
        """
        let results = parser.parse(input)
        #expect(results.count == 3)
    }

    // MARK: - Multi-Task with Commas

    @Test func parseMultipleTasksWithCommas() {
        let results = parser.parse("do laundry, write code, review PR")
        #expect(results.count == 3)
    }

    @Test func parseCommasSplitOnlyWhenSubstantial() {
        // Short segments (<=5 chars) should NOT cause comma splitting
        let results = parser.parse("fix a, b")
        // "a" and "b" are too short, so no comma split
        #expect(results.count == 1)
    }

    // MARK: - Multi-Task with Semicolons

    @Test func parseMultipleTasksWithSemicolons() {
        let results = parser.parse("Task A; Task B")
        #expect(results.count == 2)
    }

    @Test func parseThreeTasksWithSemicolons() {
        let results = parser.parse("write thesis; prep slides; review notes")
        #expect(results.count == 3)
    }

    // MARK: - Numbered Lists

    @Test func parseNumberedList() {
        let input = "1. First task\n2. Second task"
        let results = parser.parse(input)
        #expect(results.count == 2)
        // Numbered prefix should be stripped from titles
        #expect(!results[0].title.hasPrefix("1"))
        #expect(!results[1].title.hasPrefix("2"))
    }

    @Test func parseNumberedListWithEstimates() {
        let input = "1. Write thesis 2h\n2. Prep slides 45m\n3. Email advisor"
        let results = parser.parse(input)
        #expect(results.count >= 3)
    }

    @Test func parseNumberedListWithDotFormat() {
        let input = "1. First\n2. Second\n3. Third"
        let results = parser.parse(input)
        #expect(results.count == 3)
    }

    // MARK: - Multi-Task with "then"

    @Test func parseMultipleTasksWithThen() {
        let results = parser.parse("write thesis then prep slides")
        #expect(results.count == 2)
    }

    // MARK: - Multi-Task with "and" Conjunction

    @Test func parseMultipleTasksWithAndConjunction() {
        let results = parser.parse("write thesis report and review the slides")
        #expect(results.count == 2)
    }

    @Test func parseAndConjunctionOnlyWhenBothSubstantial() {
        // Short segments should not split on "and"
        let results = parser.parse("read and write")
        // "read" is 4 chars, "write" is 5 chars - both need >5
        #expect(results.count == 1)
    }

    // MARK: - Time Estimate Extraction (Minutes)

    @Test func parseTimeEstimateMinutes() {
        let results = parser.parse("Write report for 30 minutes")
        #expect(results.count == 1)
        #expect(results[0].estimateMinutes == 30)
    }

    @Test func parseTimeEstimateMinutesShorthand() {
        let results = parser.parse("review code 30m")
        #expect(results.count == 1)
        #expect(results[0].estimateMinutes == 30)
    }

    @Test func parseTimeEstimate45Minutes() {
        let results = parser.parse("prep slides 45 minutes")
        #expect(results.count == 1)
        #expect(results[0].estimateMinutes == 45)
    }

    // MARK: - Time Estimate Extraction (Hours)

    @Test func parseTimeEstimateHours() {
        let results = parser.parse("Study for 2 hours")
        #expect(results.count == 1)
        #expect(results[0].estimateMinutes == 120)
    }

    @Test func parseTimeEstimateHoursShorthand() {
        let results = parser.parse("write thesis intro 2h")
        #expect(results.count == 1)
        #expect(results[0].estimateMinutes == 120)
    }

    @Test func parseTimeEstimateFractionalHours() {
        let results = parser.parse("study math for 1.5 hours")
        #expect(results.count == 1)
        #expect(results[0].estimateMinutes == 90)
    }

    @Test func parseTimeEstimateOneHour() {
        let results = parser.parse("meeting prep for 1 hour")
        #expect(results.count == 1)
        #expect(results[0].estimateMinutes == 60)
    }

    @Test func parseNoTimeEstimate() {
        let results = parser.parse("write documentation")
        #expect(results.count == 1)
        #expect(results[0].estimateMinutes == nil)
    }

    // MARK: - Priority Extraction: Urgent

    @Test func parseUrgentPriority() {
        let results = parser.parse("urgent fix the bug")
        #expect(results.count == 1)
        #expect(results[0].priority == .urgent)
    }

    @Test func parseUrgentlyKeyword() {
        let results = parser.parse("fix the bug urgently")
        #expect(results.count == 1)
        #expect(results[0].priority == .urgent)
    }

    @Test func parseASAPPriority() {
        let results = parser.parse("deploy hotfix asap")
        #expect(results.count == 1)
        #expect(results[0].priority == .urgent)
    }

    @Test func parseCriticalPriority() {
        let results = parser.parse("critical security patch needed")
        #expect(results.count == 1)
        #expect(results[0].priority == .urgent)
    }

    @Test func parseExclamationMarkPriority() {
        let results = parser.parse("fix login bug !!")
        #expect(results.count == 1)
        #expect(results[0].priority == .urgent)
    }

    // MARK: - Priority Extraction: High

    @Test func parseHighPriorityImportant() {
        let results = parser.parse("important meeting prep")
        #expect(results.count == 1)
        #expect(results[0].priority == .high)
    }

    @Test func parseHighPriorityMustDo() {
        let results = parser.parse("must do the code review")
        #expect(results.count == 1)
        #expect(results[0].priority == .high)
    }

    // MARK: - Priority Extraction: Low

    @Test func parseLowPrioritySomeday() {
        let results = parser.parse("someday clean garage")
        #expect(results.count == 1)
        #expect(results[0].priority == .low)
    }

    @Test func parseLowPriorityIfTime() {
        let results = parser.parse("clean desk if I have time")
        #expect(results.count == 1)
        #expect(results[0].priority == .low)
    }

    @Test func parseLowPriorityNiceToHave() {
        let results = parser.parse("refactor utils nice to have")
        #expect(results.count == 1)
        #expect(results[0].priority == .low)
    }

    @Test func parseLowPriorityEventually() {
        let results = parser.parse("eventually reorganize files")
        #expect(results.count == 1)
        #expect(results[0].priority == .low)
    }

    // MARK: - Priority Extraction: Default Medium

    @Test func parseDefaultMediumPriority() {
        let results = parser.parse("write tests")
        #expect(results.count == 1)
        #expect(results[0].priority == .medium)
    }

    @Test func parseDefaultMediumForPlainInput() {
        let results = parser.parse("write documentation")
        #expect(results.count == 1)
        #expect(results[0].priority == .medium)
    }

    // MARK: - Project Extraction

    @Test func parseProjectBracketSyntax() {
        let results = parser.parse("[Marketing] create presentation")
        #expect(results.count == 1)
        #expect(results[0].projectName == "Marketing")
    }

    @Test func parseProjectBracketAtEnd() {
        let results = parser.parse("write intro [Thesis]")
        #expect(results.count == 1)
        #expect(results[0].projectName == "Thesis")
    }

    @Test func parseProjectKeywordSyntax() {
        let results = parser.parse("write intro for the thesis project")
        #expect(results.count == 1)
        #expect(results[0].projectName?.lowercased() == "thesis")
    }

    @Test func parseNoProject() {
        let results = parser.parse("write documentation")
        #expect(results.count == 1)
        #expect(results[0].projectName == nil)
    }

    // MARK: - Due Date Extraction

    @Test func parseDueDateTomorrow() {
        let results = parser.parse("finish report by tomorrow")
        #expect(results.count == 1)
        #expect(results[0].dueDate != nil)
        let calendar = Calendar.current
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: Date()))!
        #expect(calendar.isDate(results[0].dueDate!, inSameDayAs: tomorrow))
    }

    @Test func parseDueDateToday() {
        let results = parser.parse("finish homework due today")
        #expect(results.count == 1)
        #expect(results[0].dueDate != nil)
        let today = Calendar.current.startOfDay(for: Date())
        #expect(Calendar.current.isDate(results[0].dueDate!, inSameDayAs: today))
    }

    @Test func parseDueDateBeforeTomorrow() {
        let results = parser.parse("submit report before tomorrow")
        #expect(results.count == 1)
        #expect(results[0].dueDate != nil)
    }

    @Test func parseNoDueDate() {
        let results = parser.parse("write documentation")
        #expect(results.count == 1)
        #expect(results[0].dueDate == nil)
    }

    // MARK: - Empty and Invalid Input

    @Test func parseEmptyInputReturnsEmpty() {
        let results = parser.parse("")
        #expect(results.isEmpty)
    }

    @Test func parseWhitespaceOnlyReturnsEmpty() {
        let results = parser.parse("   \n\t  ")
        #expect(results.isEmpty)
    }

    @Test func parseVeryShortInputReturnsEmpty() {
        // Segments shorter than 3 characters are filtered out
        let results = parser.parse("ab")
        #expect(results.isEmpty)
    }

    @Test func parseSingleCharReturnsEmpty() {
        let results = parser.parse("x")
        #expect(results.isEmpty)
    }

    // MARK: - Combined Extraction

    @Test func parseCombinedEstimateAndPriority() {
        let results = parser.parse("fix auth bug urgently 2h")
        #expect(results.count == 1)
        #expect(results[0].priority == .urgent)
        #expect(results[0].estimateMinutes == 120)
    }

    @Test func parseCombinedEstimateAndProject() {
        let results = parser.parse("write introduction [Thesis] 2h")
        #expect(results.count == 1)
        #expect(results[0].projectName == "Thesis")
        #expect(results[0].estimateMinutes == 120)
    }

    @Test func parseCombinedDueDateAndPriority() {
        let results = parser.parse("urgent: submit report by tomorrow")
        #expect(results.count == 1)
        #expect(results[0].priority == .urgent)
        #expect(results[0].dueDate != nil)
    }

    // MARK: - Priority.from(string:) Tests

    @Test func priorityFromStringUrgent() {
        #expect(TetherTask.Priority.from(string: "urgent") == .urgent)
        #expect(TetherTask.Priority.from(string: "URGENT") == .urgent)
    }

    @Test func priorityFromStringHigh() {
        #expect(TetherTask.Priority.from(string: "high") == .high)
        #expect(TetherTask.Priority.from(string: "High") == .high)
    }

    @Test func priorityFromStringMedium() {
        #expect(TetherTask.Priority.from(string: "medium") == .medium)
    }

    @Test func priorityFromStringLow() {
        #expect(TetherTask.Priority.from(string: "low") == .low)
    }

    @Test func priorityFromStringUnknownDefaultsMedium() {
        #expect(TetherTask.Priority.from(string: "unknown") == .medium)
        #expect(TetherTask.Priority.from(string: "") == .medium)
    }

    // MARK: - ParsedTask Model Tests

    @Test func parsedTaskDefaultValues() {
        let task = ParsedTask(title: "Test task")
        #expect(task.title == "Test task")
        #expect(task.estimateMinutes == nil)
        #expect(task.priority == .medium)
        #expect(task.projectName == nil)
        #expect(task.dueDate == nil)
    }

    @Test func parsedTaskFullInit() {
        let dueDate = Date()
        let task = ParsedTask(
            title: "Full task",
            estimateMinutes: 45,
            priority: .high,
            projectName: "Project X",
            dueDate: dueDate
        )
        #expect(task.title == "Full task")
        #expect(task.estimateMinutes == 45)
        #expect(task.priority == .high)
        #expect(task.projectName == "Project X")
        #expect(task.dueDate == dueDate)
    }
}
