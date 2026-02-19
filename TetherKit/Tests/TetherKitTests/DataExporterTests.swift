import Testing
import Foundation
import GRDB
@testable import TetherKit

// MARK: - Data Exporter Tests

/// Tests for DataExporter functionality.
/// Note: DataExporter.exportSessions/exportTasks use DatabaseManager.shared internally,
/// so we test the CSV/JSON format by exercising the Session and TetherTask Codable conformance
/// and validating the export pipeline with in-memory database where possible.

@MainActor
struct DataExporterSessionCRUDTests {

    // MARK: - Session CSV Export Format Validation

    @Test func sessionCSVHeaderContainsExpectedColumns() throws {
        let db = DatabaseManager(inMemory: true)

        // Insert a completed session
        var session = Session(
            startTime: Date(),
            durationSeconds: 3600,
            focusedSeconds: 3000,
            distractionCount: 2,
            isComplete: true
        )
        try db.dbQueue.write { d in try session.save(d) }

        // Fetch sessions using the same pattern DataExporter uses
        let sessions = try db.dbQueue.read { d in
            try Session.filter(Column("isComplete") == true).fetchAll(d)
        }
        #expect(sessions.count == 1)

        // Build CSV manually the same way DataExporter.sessionsToCSV does
        let csv = buildSessionCSV(sessions)
        #expect(csv.contains("Date"))
        #expect(csv.contains("Start Time"))
        #expect(csv.contains("Duration (min)"))
        #expect(csv.contains("Focus %"))
        #expect(csv.contains("Distractions"))
    }

    @Test func sessionCSVContainsSessionData() throws {
        let db = DatabaseManager(inMemory: true)

        var session = Session(
            startTime: Date(),
            durationSeconds: 3600,
            focusedSeconds: 3000,
            distractionCount: 2,
            isComplete: true
        )
        try db.dbQueue.write { d in try session.save(d) }

        let sessions = try db.dbQueue.read { d in
            try Session.filter(Column("isComplete") == true).fetchAll(d)
        }

        let csv = buildSessionCSV(sessions)
        // Duration in minutes: 3600 / 60 = 60
        #expect(csv.contains("60"))
        // Focus in minutes: 3000 / 60 = 50
        #expect(csv.contains("50"))
        // Distraction count
        #expect(csv.contains("2"))
    }

    @Test func emptySessionCSVHasHeaderOnly() {
        let csv = buildSessionCSV([])
        let lines = csv.components(separatedBy: "\n").filter { !$0.isEmpty }
        #expect(lines.count == 1) // Header only
        #expect(lines[0].contains("Date"))
    }

    @Test func multipleSessionsInCSV() throws {
        let db = DatabaseManager(inMemory: true)

        for i in 1...3 {
            var session = Session(
                startTime: Date().addingTimeInterval(Double(-i * 3600)),
                durationSeconds: i * 1800,
                focusedSeconds: i * 1500,
                distractionCount: i,
                isComplete: true
            )
            try db.dbQueue.write { d in try session.save(d) }
        }

        let sessions = try db.dbQueue.read { d in
            try Session.filter(Column("isComplete") == true).fetchAll(d)
        }

        let csv = buildSessionCSV(sessions)
        let lines = csv.components(separatedBy: "\n").filter { !$0.isEmpty }
        // 1 header + 3 data rows
        #expect(lines.count == 4)
    }

    // MARK: - Task CSV Export Format Validation

    @Test func taskCSVHeaderContainsExpectedColumns() throws {
        let db = DatabaseManager(inMemory: true)

        var task = TetherTask(title: "Write tests", estimateMinutes: 30, priority: .high)
        try db.dbQueue.write { d in try task.save(d) }

        let tasks = try db.dbQueue.read { d in try TetherTask.fetchAll(d) }
        let csv = buildTaskCSV(tasks)

        #expect(csv.contains("Title"))
        #expect(csv.contains("Priority"))
        #expect(csv.contains("Status"))
        #expect(csv.contains("Estimate (min)"))
        #expect(csv.contains("Created"))
    }

    @Test func taskCSVContainsTaskData() throws {
        let db = DatabaseManager(inMemory: true)

        var task = TetherTask(title: "Write tests", estimateMinutes: 30, priority: .high)
        try db.dbQueue.write { d in try task.save(d) }

        let tasks = try db.dbQueue.read { d in try TetherTask.fetchAll(d) }
        let csv = buildTaskCSV(tasks)

        #expect(csv.contains("Write tests"))
        #expect(csv.contains("High"))
        #expect(csv.contains("To Do"))
        #expect(csv.contains("30"))
    }

    @Test func emptyTaskCSVHasHeaderOnly() {
        let csv = buildTaskCSV([])
        let lines = csv.components(separatedBy: "\n").filter { !$0.isEmpty }
        #expect(lines.count == 1)
        #expect(lines[0].contains("Title"))
    }

    // MARK: - JSON Export Format Validation

    @Test func sessionJSONExportIsValidJSON() throws {
        let session = Session(
            startTime: Date(),
            durationSeconds: 3600,
            focusedSeconds: 3000,
            distractionCount: 2,
            isComplete: true
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode([session])

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        _ = try decoder.decode([Session].self, from: data)
        #expect(!data.isEmpty)
        // Verify JSON string contains expected keys
        let jsonString = String(data: data, encoding: .utf8)!
        #expect(jsonString.contains("durationSeconds"))
        #expect(jsonString.contains("focusedSeconds"))
        #expect(jsonString.contains("isComplete"))
    }

    @Test func taskJSONExportIsValidJSON() throws {
        let task = TetherTask(title: "Test task", estimateMinutes: 60, priority: .high)

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode([task])

        let jsonString = String(data: data, encoding: .utf8)!
        #expect(jsonString.contains("title"))
        #expect(jsonString.contains("Test task"))
        #expect(jsonString.contains("estimateMinutes"))
        #expect(jsonString.contains("priority"))
    }

    @Test func emptySessionJSONExport() throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode([Session]())

        let jsonString = String(data: data, encoding: .utf8)!
        #expect(jsonString == "[\n\n]" || jsonString == "[]")
    }

    @Test func emptyTaskJSONExport() throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode([TetherTask]())

        let jsonString = String(data: data, encoding: .utf8)!
        #expect(jsonString == "[\n\n]" || jsonString == "[]")
    }

    // MARK: - Export Format Enum

    @Test func exportFormatCases() {
        // Verify the enum has both cases
        let csv = DataExporter.ExportFormat.csv
        let json = DataExporter.ExportFormat.json
        // Compile-time check that both exist
        _ = csv
        _ = json
    }

    // MARK: - Helpers

    /// Mirrors the CSV generation logic from DataExporter.sessionsToCSV
    private func buildSessionCSV(_ sessions: [Session]) -> String {
        var csv = "Date,Start Time,End Time,Duration (min),Focused (min),Focus %,Distractions\n"
        let df = DateFormatter()
        df.dateStyle = .short
        df.timeStyle = .short

        for session in sessions {
            let endStr = session.endTime.map { df.string(from: $0) } ?? ""
            csv += "\(df.string(from: session.startTime)),\(df.string(from: session.startTime)),\(endStr),"
            csv += "\(session.durationSeconds / 60),\(session.focusedSeconds / 60),"
            csv += String(format: "%.1f", session.focusPercentage)
            csv += ",\(session.distractionCount)\n"
        }
        return csv
    }

    /// Mirrors the CSV generation logic from DataExporter.tasksToCSV
    private func buildTaskCSV(_ tasks: [TetherTask]) -> String {
        var csv = "Title,Priority,Status,Estimate (min),Created\n"
        let df = DateFormatter()
        df.dateStyle = .short

        for task in tasks {
            let estimate = task.estimateMinutes.map(String.init) ?? ""
            csv += "\"\(task.title)\",\(task.priority.label),\(task.status.label),\(estimate),\(df.string(from: task.createdAt))\n"
        }
        return csv
    }
}
