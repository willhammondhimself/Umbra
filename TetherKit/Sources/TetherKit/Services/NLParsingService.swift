import Foundation
import NaturalLanguage

public struct ParsedTask: Sendable {
    public var title: String
    public var estimateMinutes: Int?
    public var priority: TetherTask.Priority
    public var projectName: String?
    public var dueDate: Date?

    public init(title: String, estimateMinutes: Int? = nil, priority: TetherTask.Priority = .medium, projectName: String? = nil, dueDate: Date? = nil) {
        self.title = title
        self.estimateMinutes = estimateMinutes
        self.priority = priority
        self.projectName = projectName
        self.dueDate = dueDate
    }
}

// MARK: - LLM Response Types

struct LLMParseResponse: Codable, Sendable {
    let tasks: [LLMParsedTask]
    let usedLlm: Bool

    enum CodingKeys: String, CodingKey {
        case tasks
        case usedLlm = "used_llm"
    }
}

struct LLMParsedTask: Codable, Sendable {
    let title: String
    let estimateMinutes: Int?
    let priority: String?
    let projectName: String?
    let dueDate: String?

    enum CodingKeys: String, CodingKey {
        case title
        case estimateMinutes = "estimate_minutes"
        case priority
        case projectName = "project_name"
        case dueDate = "due_date"
    }
}

// MARK: - Priority String Mapping

extension TetherTask.Priority {
    /// Create a Priority from a lowercase string returned by the LLM API.
    public static func from(string: String) -> TetherTask.Priority {
        switch string.lowercased() {
        case "urgent": .urgent
        case "high": .high
        case "medium": .medium
        case "low": .low
        default: .medium
        }
    }
}

public struct NLParsingService: Sendable {

    public init() {}

    // MARK: - Public API

    public func parse(_ input: String) -> [ParsedTask] {
        let segments = splitIntoSegments(input)
        return segments.compactMap { parseSegment($0) }
    }

    /// Parse natural language into tasks using the backend LLM endpoint,
    /// falling back to local regex-based parsing if the API is unavailable.
    public func parseWithLLM(_ input: String) async -> [ParsedTask] {
        do {
            let body = ["text": input]
            let response: LLMParseResponse = try await APIClient.shared.request(
                .tasksParse, method: "POST", body: body
            )
            if response.usedLlm && !response.tasks.isEmpty {
                return response.tasks.map { llmTask in
                    let priority = TetherTask.Priority.from(string: llmTask.priority ?? "medium")
                    let dueDate: Date? = llmTask.dueDate.flatMap { ISO8601DateFormatter().date(from: $0) }
                    return ParsedTask(
                        title: llmTask.title,
                        estimateMinutes: llmTask.estimateMinutes,
                        priority: priority,
                        projectName: llmTask.projectName,
                        dueDate: dueDate
                    )
                }
            }
        } catch {
            // Fall back to local parsing
        }
        return parse(input)
    }

    // MARK: - Segmentation

    private func splitIntoSegments(_ input: String) -> [String] {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        var segments = trimmed.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }

        if segments.count == 1 {
            let parts = segments[0].components(separatedBy: " then ")
            if parts.count > 1 {
                segments = parts
            }
        }

        if segments.count == 1 {
            let parts = segments[0].components(separatedBy: ";")
            if parts.count > 1 {
                segments = parts
            }
        }

        // Split on " and " conjunction when both sides are substantial
        if segments.count == 1 {
            let parts = segments[0].components(separatedBy: " and ")
            if parts.count > 1 && parts.allSatisfy({ $0.trimmingCharacters(in: .whitespaces).count > 5 }) {
                segments = parts
            }
        }

        if segments.count == 1 {
            let parts = segments[0].components(separatedBy: ",")
            if parts.count > 1 && parts.allSatisfy({ $0.trimmingCharacters(in: .whitespaces).count > 5 }) {
                segments = parts
            }
        }

        return segments.map { segment in
            var s = segment.trimmingCharacters(in: .whitespaces)
            if let range = s.range(of: #"^\d+[\.\)]\s*"#, options: .regularExpression) {
                s.removeSubrange(range)
            }
            return s.trimmingCharacters(in: .whitespaces)
        }.filter { !$0.isEmpty }
    }

    // MARK: - Segment Parsing

    private func parseSegment(_ segment: String) -> ParsedTask? {
        let trimmed = segment.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 3 else { return nil }

        var remaining = trimmed
        let estimate = extractEstimate(from: &remaining)
        let priority = extractPriority(from: &remaining)
        let dueDate = extractDueDate(from: &remaining)
        let projectName = extractProjectName(from: &remaining)

        let title = cleanTitle(remaining)
        guard !title.isEmpty else { return nil }

        return ParsedTask(
            title: title,
            estimateMinutes: estimate,
            priority: priority,
            projectName: projectName,
            dueDate: dueDate
        )
    }

    // MARK: - Time Estimate Extraction

    private func extractEstimate(from text: inout String) -> Int? {
        let patterns: [(pattern: String, groupIndex: Int, toMinutes: (String) -> Int?)] = [
            (#"(?:for|about|around|~|approximately)\s+(\d+\.?\d*)\s*(?:hours?|hrs?|h)\b"#, 1, { s in
                Double(s).map { Int($0 * 60) }
            }),
            (#"(?:for|about|around|~|approximately)\s+(\d+)\s*(?:minutes?|mins?|m)\b"#, 1, { s in
                Int(s)
            }),
            (#"(\d+\.?\d*)\s*(?:hours?|hrs?|h)\b"#, 1, { s in
                Double(s).map { Int($0 * 60) }
            }),
            (#"(\d+)\s*(?:minutes?|mins?|m)\b"#, 1, { s in
                Int(s)
            }),
        ]

        for (pattern, groupIndex, converter) in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else { continue }
            let nsRange = NSRange(text.startIndex..., in: text)
            guard let match = regex.firstMatch(in: text, range: nsRange) else { continue }
            guard let captureRange = Range(match.range(at: groupIndex), in: text) else { continue }

            let value = String(text[captureRange])
            if let minutes = converter(value), minutes > 0 {
                if let fullRange = Range(match.range, in: text) {
                    text.removeSubrange(fullRange)
                }
                return minutes
            }
        }
        return nil
    }

    // MARK: - Priority Extraction

    private func extractPriority(from text: inout String) -> TetherTask.Priority {
        let levels: [(TetherTask.Priority, [String])] = [
            (.urgent, [
                #"\b(?:urgent|urgently|asap|critical|immediately|right away)\b"#,
                #"!!+"#,
            ]),
            (.high, [
                #"\b(?:important|high priority|must do|need to|have to)\b"#,
            ]),
            (.low, [
                #"\b(?:if I have time|low priority|maybe|eventually|someday|when possible|nice to have)\b"#,
            ]),
        ]

        for (priority, patterns) in levels {
            for pattern in patterns {
                guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else { continue }
                let nsRange = NSRange(text.startIndex..., in: text)
                guard let match = regex.firstMatch(in: text, range: nsRange) else { continue }
                if let fullRange = Range(match.range, in: text) {
                    text.removeSubrange(fullRange)
                }
                return priority
            }
        }

        return .medium
    }

    // MARK: - Due Date Extraction

    private func extractDueDate(from text: inout String) -> Date? {
        let calendar = Calendar.current
        let today = Date()

        // "by tomorrow", "due tomorrow"
        if let regex = try? NSRegularExpression(pattern: #"(?:by|due|before)\s+tomorrow\b"#, options: .caseInsensitive) {
            let nsRange = NSRange(text.startIndex..., in: text)
            if let match = regex.firstMatch(in: text, range: nsRange), let fullRange = Range(match.range, in: text) {
                text.removeSubrange(fullRange)
                return calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: today))
            }
        }

        // "by today", "due today"
        if let regex = try? NSRegularExpression(pattern: #"(?:by|due|before)\s+today\b"#, options: .caseInsensitive) {
            let nsRange = NSRange(text.startIndex..., in: text)
            if let match = regex.firstMatch(in: text, range: nsRange), let fullRange = Range(match.range, in: text) {
                text.removeSubrange(fullRange)
                return calendar.startOfDay(for: today)
            }
        }

        // "by [day name]" e.g. "by Friday"
        let dayNames = ["sunday", "monday", "tuesday", "wednesday", "thursday", "friday", "saturday"]
        if let regex = try? NSRegularExpression(
            pattern: #"(?:by|due|before)\s+(sunday|monday|tuesday|wednesday|thursday|friday|saturday)\b"#,
            options: .caseInsensitive
        ) {
            let nsRange = NSRange(text.startIndex..., in: text)
            if let match = regex.firstMatch(in: text, range: nsRange),
               let captureRange = Range(match.range(at: 1), in: text) {
                let dayName = String(text[captureRange]).lowercased()
                if let targetWeekday = dayNames.firstIndex(of: dayName) {
                    // Calendar weekday: Sunday = 1
                    let target = targetWeekday + 1
                    let currentWeekday = calendar.component(.weekday, from: today)
                    var daysAhead = target - currentWeekday
                    if daysAhead <= 0 { daysAhead += 7 }
                    if let fullRange = Range(match.range, in: text) {
                        text.removeSubrange(fullRange)
                    }
                    return calendar.date(byAdding: .day, value: daysAhead, to: calendar.startOfDay(for: today))
                }
            }
        }

        return nil
    }

    // MARK: - Project Name Extraction

    private func extractProjectName(from text: inout String) -> String? {
        let patterns = [
            #"\[([^\]]+)\]"#,
            #"(?:project:\s*)(\S+(?:\s+\S+)?)"#,
            #"(?:for\s+(?:the\s+)?)([\w]+(?:\s+[\w]+)?)\s+project\b"#,
        ]

        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else { continue }
            let nsRange = NSRange(text.startIndex..., in: text)
            guard let match = regex.firstMatch(in: text, range: nsRange) else { continue }
            guard let captureRange = Range(match.range(at: 1), in: text) else { continue }

            let name = String(text[captureRange]).trimmingCharacters(in: .whitespaces)
            if let fullRange = Range(match.range, in: text) {
                text.removeSubrange(fullRange)
            }
            return name.isEmpty ? nil : name
        }
        return nil
    }

    // MARK: - Title Cleanup

    private func cleanTitle(_ text: String) -> String {
        var cleaned = text
            .trimmingCharacters(in: .whitespacesAndNewlines)

        if let range = cleaned.range(of: #"^(?:and|also|plus|then)\s+"#, options: .regularExpression) {
            cleaned.removeSubrange(range)
        }

        if let range = cleaned.range(of: #"\s+(?:for|in|at|about)\s*$"#, options: .regularExpression) {
            cleaned.removeSubrange(range)
        }

        while cleaned.contains("  ") {
            cleaned = cleaned.replacingOccurrences(of: "  ", with: " ")
        }

        cleaned = cleaned.trimmingCharacters(in: .whitespacesAndNewlines)

        if let first = cleaned.first, first.isLowercase {
            cleaned = first.uppercased() + cleaned.dropFirst()
        }

        return cleaned
    }
}
