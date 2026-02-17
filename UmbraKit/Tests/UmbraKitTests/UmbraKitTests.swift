import Testing
@testable import UmbraKit

@Test func testTaskPriorityOrder() {
    #expect(UmbraTask.Priority.low < .medium)
    #expect(UmbraTask.Priority.medium < .high)
    #expect(UmbraTask.Priority.high < .urgent)
}

@Test func testTaskStatusLabels() {
    #expect(UmbraTask.Status.todo.label == "To Do")
    #expect(UmbraTask.Status.inProgress.label == "In Progress")
    #expect(UmbraTask.Status.done.label == "Done")
}

@Test func testSessionFormatSeconds() {
    #expect(Session.formatSeconds(0) == "00:00")
    #expect(Session.formatSeconds(65) == "01:05")
    #expect(Session.formatSeconds(3661) == "1:01:01")
}

@Test func testSyncStatusCases() {
    #expect(SyncStatus.allCases.count == 6)
}

@Test func testBlocklistItemTypes() {
    let appBlock = BlocklistItem(bundleId: "com.test", displayName: "Test")
    #expect(appBlock.isAppBlock)
    #expect(!appBlock.isWebBlock)

    let webBlock = BlocklistItem(domain: "example.com", displayName: "Example")
    #expect(!webBlock.isAppBlock)
    #expect(webBlock.isWebBlock)
}

@Test func testNLParsingBasic() {
    let parser = NLParsingService()
    let results = parser.parse("write thesis intro")
    #expect(results.count == 1)
    #expect(results[0].title.lowercased().contains("thesis"))
}

@Test func testNLParsingTimeEstimate() {
    let parser = NLParsingService()
    let results = parser.parse("write thesis intro for 2 hours")
    #expect(results.count == 1)
    #expect(results[0].estimateMinutes == 120)
}

@Test func testNLParsingPriority() {
    let parser = NLParsingService()
    let urgent = parser.parse("fix the bug urgently")
    #expect(urgent[0].priority == .urgent)

    let high = parser.parse("important: review the PR")
    #expect(high[0].priority == .high)
}

@Test func testFormattedEstimate() {
    var task = UmbraTask(title: "Test")
    #expect(task.formattedEstimate == nil)

    task.estimateMinutes = 30
    #expect(task.formattedEstimate == "30m")

    task.estimateMinutes = 120
    #expect(task.formattedEstimate == "2h")

    task.estimateMinutes = 90
    #expect(task.formattedEstimate == "1h 30m")
}
