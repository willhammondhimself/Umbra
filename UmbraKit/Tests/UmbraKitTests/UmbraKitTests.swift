import Testing
import Foundation
import GRDB
@testable import UmbraKit

// MARK: - Task Model Tests

@Test func testTaskPriorityOrder() {
    #expect(UmbraTask.Priority.low < .medium)
    #expect(UmbraTask.Priority.medium < .high)
    #expect(UmbraTask.Priority.high < .urgent)
}

@Test func testTaskPriorityLabels() {
    #expect(UmbraTask.Priority.low.label == "Low")
    #expect(UmbraTask.Priority.medium.label == "Medium")
    #expect(UmbraTask.Priority.high.label == "High")
    #expect(UmbraTask.Priority.urgent.label == "Urgent")
}

@Test func testTaskPriorityIcons() {
    #expect(UmbraTask.Priority.low.iconName == "arrow.down")
    #expect(UmbraTask.Priority.urgent.iconName == "exclamationmark.2")
}

@Test func testTaskStatusLabels() {
    #expect(UmbraTask.Status.todo.label == "To Do")
    #expect(UmbraTask.Status.inProgress.label == "In Progress")
    #expect(UmbraTask.Status.done.label == "Done")
}

@Test func testTaskStatusAllCases() {
    #expect(UmbraTask.Status.allCases.count == 3)
}

@Test func testTaskDefaultValues() {
    let task = UmbraTask(title: "Test")
    #expect(task.id == nil)
    #expect(task.projectId == nil)
    #expect(task.priority == .medium)
    #expect(task.status == .todo)
    #expect(task.estimateMinutes == nil)
    #expect(task.dueDate == nil)
    #expect(task.sortOrder == 0)
    #expect(task.syncStatus == .local)
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

    task.estimateMinutes = 1
    #expect(task.formattedEstimate == "1m")
}

// MARK: - Session Model Tests

@Test func testSessionFormatSeconds() {
    #expect(Session.formatSeconds(0) == "00:00")
    #expect(Session.formatSeconds(65) == "01:05")
    #expect(Session.formatSeconds(3661) == "1:01:01")
    #expect(Session.formatSeconds(7200) == "2:00:00")
}

@Test func testSessionFocusPercentage() {
    var session = Session()
    #expect(session.focusPercentage == 0)

    session.durationSeconds = 100
    session.focusedSeconds = 80
    #expect(session.focusPercentage == 80.0)

    session.focusedSeconds = 100
    #expect(session.focusPercentage == 100.0)
}

@Test func testSessionDefaultValues() {
    let session = Session()
    #expect(session.id == nil)
    #expect(session.endTime == nil)
    #expect(session.durationSeconds == 0)
    #expect(session.focusedSeconds == 0)
    #expect(session.distractionCount == 0)
    #expect(session.isComplete == false)
    #expect(session.syncStatus == .local)
}

// MARK: - SessionEvent Tests

@Test func testSessionEventTypes() {
    #expect(SessionEvent.EventType.allCases.count == 7)
    #expect(SessionEvent.EventType.start.rawValue == "START")
    #expect(SessionEvent.EventType.distraction.rawValue == "DISTRACTION")
    #expect(SessionEvent.EventType.idle.rawValue == "IDLE")
}

// MARK: - SyncStatus Tests

@Test func testSyncStatusCases() {
    #expect(SyncStatus.allCases.count == 6)
    #expect(SyncStatus.local.rawValue == 0)
    #expect(SyncStatus.synced.rawValue == 1)
    #expect(SyncStatus.conflicted.rawValue == 5)
}

// MARK: - BlocklistItem Tests

@Test func testBlocklistItemTypes() {
    let appBlock = BlocklistItem(bundleId: "com.test", displayName: "Test")
    #expect(appBlock.isAppBlock)
    #expect(!appBlock.isWebBlock)

    let webBlock = BlocklistItem(domain: "example.com", displayName: "Example")
    #expect(!webBlock.isAppBlock)
    #expect(webBlock.isWebBlock)
}

@Test func testBlocklistBlockModes() {
    #expect(BlocklistItem.BlockMode.allCases.count == 3)
    #expect(BlocklistItem.BlockMode.softWarn.label == "Soft Warn")
    #expect(BlocklistItem.BlockMode.hardBlock.label == "Hard Block")
    #expect(BlocklistItem.BlockMode.timedLock.label == "Timed Lock")
}

@Test func testBlocklistDefaults() {
    let item = BlocklistItem(bundleId: "com.test", displayName: "Test")
    #expect(item.blockMode == .softWarn)
    #expect(item.isEnabled == true)
}

// MARK: - Project Tests

@Test func testProjectDefaults() {
    let project = Project(name: "My Project")
    #expect(project.id == nil)
    #expect(project.name == "My Project")
    #expect(project.syncStatus == .local)
    #expect(project.remoteId == nil)
}

// MARK: - Social Types Tests

@Test func testFriendItemCodable() throws {
    let json = """
    {
        "id": "550e8400-e29b-41d4-a716-446655440000",
        "user_id": "660e8400-e29b-41d4-a716-446655440000",
        "display_name": "Alice",
        "email": "alice@test.com",
        "status": "accepted",
        "since": "2025-01-01T00:00:00Z"
    }
    """.data(using: .utf8)!

    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    let friend = try decoder.decode(FriendItem.self, from: json)
    #expect(friend.displayName == "Alice")
    #expect(friend.email == "alice@test.com")
    #expect(friend.status == "accepted")
}

@Test func testGroupItemCodable() throws {
    let json = """
    {
        "id": "550e8400-e29b-41d4-a716-446655440000",
        "name": "Study Group",
        "created_by": "660e8400-e29b-41d4-a716-446655440000",
        "created_at": "2025-01-01T00:00:00Z",
        "member_count": 5
    }
    """.data(using: .utf8)!

    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    let group = try decoder.decode(GroupItem.self, from: json)
    #expect(group.name == "Study Group")
    #expect(group.memberCount == 5)
}

@Test func testLeaderboardEntryCodable() throws {
    let json = """
    {
        "user_id": "550e8400-e29b-41d4-a716-446655440000",
        "display_name": "Bob",
        "focused_seconds": 7200,
        "session_count": 3,
        "rank": 1
    }
    """.data(using: .utf8)!

    let decoder = JSONDecoder()
    let entry = try decoder.decode(LeaderboardEntryItem.self, from: json)
    #expect(entry.displayName == "Bob")
    #expect(entry.focusedSeconds == 7200)
    #expect(entry.rank == 1)
    #expect(entry.id == entry.userId)
}

@Test func testInviteResponseCodable() throws {
    let json = """
    {"id": "550e8400-e29b-41d4-a716-446655440000", "status": "pending"}
    """.data(using: .utf8)!

    let response = try JSONDecoder().decode(InviteResponse.self, from: json)
    #expect(response.status == "pending")
}

// MARK: - NL Parsing Tests

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

@Test func testNLParsingMinutes() {
    let parser = NLParsingService()
    let results = parser.parse("review code 30m")
    #expect(results.count == 1)
    #expect(results[0].estimateMinutes == 30)
}

@Test func testNLParsingPriority() {
    let parser = NLParsingService()
    let urgent = parser.parse("fix the bug urgently")
    #expect(urgent[0].priority == .urgent)

    let high = parser.parse("important: review the PR")
    #expect(high[0].priority == .high)

    let low = parser.parse("clean desk if I have time")
    #expect(low[0].priority == .low)

    let medium = parser.parse("write documentation")
    #expect(medium[0].priority == .medium)
}

@Test func testNLParsingEmptyInput() {
    let parser = NLParsingService()
    #expect(parser.parse("").isEmpty)
    #expect(parser.parse("   \n\t  ").isEmpty)
    #expect(parser.parse("ab").isEmpty) // too short
}

@Test func testNLParsingMultipleWithThen() {
    let parser = NLParsingService()
    let results = parser.parse("write thesis then prep slides")
    #expect(results.count == 2)
}

@Test func testNLParsingMultipleWithNewlines() {
    let parser = NLParsingService()
    let results = parser.parse("write thesis 2h\nprep slides 45m\nreview notes")
    #expect(results.count == 3)
}

@Test func testNLParsingMultipleWithSemicolon() {
    let parser = NLParsingService()
    let results = parser.parse("write thesis; prep slides; review notes")
    #expect(results.count == 3)
}

@Test func testNLParsingNumberedList() {
    let parser = NLParsingService()
    let results = parser.parse("1. Write thesis 2h\n2. Prep slides 45m\n3. Email advisor")
    #expect(results.count >= 3)
}

@Test func testNLParsingConjunctionSplitting() {
    let parser = NLParsingService()
    let results = parser.parse("write thesis report and review the slides")
    #expect(results.count == 2)
}

@Test func testNLParsingDueDateTomorrow() {
    let parser = NLParsingService()
    let results = parser.parse("submit report by tomorrow")
    #expect(results.count == 1)
    #expect(results[0].dueDate != nil)
    let calendar = Calendar.current
    let tomorrow = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: Date()))!
    #expect(calendar.isDate(results[0].dueDate!, inSameDayAs: tomorrow))
}

@Test func testNLParsingDueDateToday() {
    let parser = NLParsingService()
    let results = parser.parse("finish homework due today")
    #expect(results.count == 1)
    #expect(results[0].dueDate != nil)
    let today = Calendar.current.startOfDay(for: Date())
    #expect(Calendar.current.isDate(results[0].dueDate!, inSameDayAs: today))
}

@Test func testNLParsingProjectBracket() {
    let parser = NLParsingService()
    let results = parser.parse("write intro [Thesis]")
    #expect(results.count == 1)
    #expect(results[0].projectName == "Thesis")
}

@Test func testNLParsingProjectKeyword() {
    let parser = NLParsingService()
    let results = parser.parse("write intro for the thesis project")
    #expect(results.count == 1)
    #expect(results[0].projectName?.lowercased() == "thesis")
}

@Test func testNLParsingExclamationPriority() {
    let parser = NLParsingService()
    let results = parser.parse("fix login bug !!")
    #expect(results.count == 1)
    #expect(results[0].priority == .urgent)
}

@Test func testNLParsingASAPPriority() {
    let parser = NLParsingService()
    let results = parser.parse("deploy hotfix asap")
    #expect(results.count == 1)
    #expect(results[0].priority == .urgent)
}

@Test func testNLParsingFractionalHours() {
    let parser = NLParsingService()
    let results = parser.parse("study math for 1.5 hours")
    #expect(results.count == 1)
    #expect(results[0].estimateMinutes == 90)
}

@Test func testNLParsingTitleCapitalization() {
    let parser = NLParsingService()
    let results = parser.parse("review pull request")
    #expect(results.count == 1)
    #expect(results[0].title.first?.isUppercase == true)
}

// MARK: - PeriodStats Tests

@Test func testPeriodStatsDefaults() {
    let stats = PeriodStats()
    #expect(stats.focusedSeconds == 0)
    #expect(stats.totalSeconds == 0)
    #expect(stats.sessionCount == 0)
    #expect(stats.averageSessionLength == 0)
    #expect(stats.distractionRate == 0)
    #expect(stats.focusPercentage == 0)
}

@Test func testPeriodStatsComputedProperties() {
    var stats = PeriodStats()
    stats.totalSeconds = 3600
    stats.focusedSeconds = 2700
    stats.sessionCount = 2
    stats.distractionCount = 3

    #expect(stats.averageSessionLength == 1800)
    #expect(stats.focusPercentage == 75.0)
    #expect(stats.distractionRate == 3.0) // 3 distractions per hour
}

// MARK: - Database CRUD Tests

@MainActor
@Test func testDatabaseProjectCRUD() throws {
    let db = DatabaseManager(inMemory: true)

    // Create
    var project = Project(name: "Test Project")
    try db.dbQueue.write { d in try project.save(d) }
    #expect(project.id != nil)

    // Read
    let projects = try db.dbQueue.read { d in try Project.fetchAll(d) }
    #expect(projects.count == 1)
    #expect(projects[0].name == "Test Project")
}

@MainActor
@Test func testDatabaseTaskCRUD() throws {
    let db = DatabaseManager(inMemory: true)

    var task = UmbraTask(title: "Write tests")
    try db.dbQueue.write { d in try task.save(d) }
    #expect(task.id != nil)

    let tasks = try db.dbQueue.read { d in try UmbraTask.fetchAll(d) }
    #expect(tasks.count == 1)
    #expect(tasks[0].title == "Write tests")
    #expect(tasks[0].priority == .medium)
}

@MainActor
@Test func testDatabaseSessionCRUD() throws {
    let db = DatabaseManager(inMemory: true)

    var session = Session(startTime: Date(), durationSeconds: 600, focusedSeconds: 500, isComplete: true)
    try db.dbQueue.write { d in try session.save(d) }
    #expect(session.id != nil)

    let sessions = try db.dbQueue.read { d in try Session.fetchAll(d) }
    #expect(sessions.count == 1)
    #expect(sessions[0].durationSeconds == 600)
    #expect(sessions[0].isComplete == true)
}

@MainActor
@Test func testDatabaseSessionEventCRUD() throws {
    let db = DatabaseManager(inMemory: true)

    var session = Session()
    try db.dbQueue.write { d in try session.save(d) }

    var event = SessionEvent(sessionId: session.id!, eventType: .start)
    try db.dbQueue.write { d in try event.save(d) }
    #expect(event.id != nil)

    let events = try db.dbQueue.read { d in
        try SessionEvent.filter(GRDB.Column("sessionId") == session.id!).fetchAll(d)
    }
    #expect(events.count == 1)
    #expect(events[0].eventType == SessionEvent.EventType.start)
}

@MainActor
@Test func testDatabaseBlocklistCRUD() throws {
    let db = DatabaseManager(inMemory: true)

    var item = BlocklistItem(bundleId: "com.twitter", displayName: "Twitter", blockMode: .hardBlock)
    try db.dbQueue.write { d in try item.save(d) }
    #expect(item.id != nil)

    let items = try db.dbQueue.read { d in try BlocklistItem.fetchAll(d) }
    #expect(items.count == 1)
    #expect(items[0].blockMode == .hardBlock)
    #expect(items[0].isAppBlock)
}

// MARK: - Model Codable Conformance

@Test func testTaskCodableRoundtrip() throws {
    let original = UmbraTask(title: "Test", estimateMinutes: 60, priority: .high, status: .inProgress)
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    let data = try encoder.encode(original)

    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    let decoded = try decoder.decode(UmbraTask.self, from: data)

    #expect(decoded.title == original.title)
    #expect(decoded.estimateMinutes == 60)
    #expect(decoded.priority == .high)
    #expect(decoded.status == .inProgress)
}

@Test func testSessionCodableRoundtrip() throws {
    let original = Session(durationSeconds: 3600, focusedSeconds: 3000, distractionCount: 2, isComplete: true)
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    let data = try encoder.encode(original)

    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    let decoded = try decoder.decode(Session.self, from: data)

    #expect(decoded.durationSeconds == 3600)
    #expect(decoded.focusedSeconds == 3000)
    #expect(decoded.isComplete == true)
}
