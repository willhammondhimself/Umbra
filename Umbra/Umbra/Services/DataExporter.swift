import Foundation

@MainActor
struct DataExporter {
    enum ExportFormat {
        case csv
        case json
    }

    func exportSessions(format: ExportFormat, from startDate: Date, to endDate: Date) throws -> Data {
        let sessions = try DatabaseManager.shared.fetchSessions(limit: 10000)
            .filter { $0.isComplete && $0.startTime >= startDate && $0.startTime <= endDate }

        switch format {
        case .csv:
            return sessionsToCSV(sessions)
        case .json:
            return try sessionsToJSON(sessions)
        }
    }

    func exportTasks(format: ExportFormat) throws -> Data {
        let tasks = try DatabaseManager.shared.fetchTasks()

        switch format {
        case .csv:
            return tasksToCSV(tasks)
        case .json:
            return try tasksToJSON(tasks)
        }
    }

    // MARK: - CSV

    private func sessionsToCSV(_ sessions: [Session]) -> Data {
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
        return csv.data(using: .utf8) ?? Data()
    }

    private func tasksToCSV(_ tasks: [UmbraTask]) -> Data {
        var csv = "Title,Priority,Status,Estimate (min),Created\n"
        let df = DateFormatter()
        df.dateStyle = .short

        for task in tasks {
            let estimate = task.estimateMinutes.map(String.init) ?? ""
            csv += "\"\(task.title)\",\(task.priority.label),\(task.status.label),\(estimate),\(df.string(from: task.createdAt))\n"
        }
        return csv.data(using: .utf8) ?? Data()
    }

    // MARK: - JSON

    private func sessionsToJSON(_ sessions: [Session]) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(sessions)
    }

    private func tasksToJSON(_ tasks: [UmbraTask]) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(tasks)
    }
}
