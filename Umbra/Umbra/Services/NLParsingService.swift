import Foundation
import NaturalLanguage

struct ParsedTask {
    var title: String
    var estimateMinutes: Int?
    var priority: UmbraTask.Priority
    var projectName: String?
}

struct NLParsingService {

    // MARK: - Public API

    func parse(_ input: String) -> [ParsedTask] {
        let segments = splitIntoSegments(input)
        return segments.compactMap { parseSegment($0) }
    }

    // MARK: - Segmentation

    private func splitIntoSegments(_ input: String) -> [String] {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        // Split by newlines first
        var segments = trimmed.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }

        // If single line, try splitting by " then "
        if segments.count == 1 {
            let parts = segments[0].components(separatedBy: " then ")
            if parts.count > 1 {
                segments = parts
            }
        }

        // If still single segment, try semicolons
        if segments.count == 1 {
            let parts = segments[0].components(separatedBy: ";")
            if parts.count > 1 {
                segments = parts
            }
        }

        // If still single segment, try commas (only if both sides are substantial)
        if segments.count == 1 {
            let parts = segments[0].components(separatedBy: ",")
            if parts.count > 1 && parts.allSatisfy({ $0.trimmingCharacters(in: .whitespaces).count > 5 }) {
                segments = parts
            }
        }

        // Strip numbered list prefixes like "1. " or "2) "
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
        let projectName = extractProjectName(from: &remaining)

        let title = cleanTitle(remaining)
        guard !title.isEmpty else { return nil }

        return ParsedTask(
            title: title,
            estimateMinutes: estimate,
            priority: priority,
            projectName: projectName
        )
    }

    // MARK: - Time Estimate Extraction

    private func extractEstimate(from text: inout String) -> Int? {
        // Try each pattern, return first match
        let patterns: [(pattern: String, groupIndex: Int, toMinutes: (String) -> Int?)] = [
            // "for 2 hours", "about 1.5h"
            (#"(?:for|about|around|~|approximately)\s+(\d+\.?\d*)\s*(?:hours?|hrs?|h)\b"#, 1, { s in
                Double(s).map { Int($0 * 60) }
            }),
            (#"(?:for|about|around|~|approximately)\s+(\d+)\s*(?:minutes?|mins?|m)\b"#, 1, { s in
                Int(s)
            }),
            // "2 hours", "1.5h"
            (#"(\d+\.?\d*)\s*(?:hours?|hrs?|h)\b"#, 1, { s in
                Double(s).map { Int($0 * 60) }
            }),
            // "45 minutes", "30m"
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

    private func extractPriority(from text: inout String) -> UmbraTask.Priority {
        let levels: [(UmbraTask.Priority, [String])] = [
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

    // MARK: - Project Name Extraction

    private func extractProjectName(from text: inout String) -> String? {
        let patterns = [
            #"\[([^\]]+)\]"#,
            #"(?:project:\s*)(\S+(?:\s+\S+)?)"#,
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

        // Remove leading conjunctions
        if let range = cleaned.range(of: #"^(?:and|also|plus|then)\s+"#, options: .regularExpression) {
            cleaned.removeSubrange(range)
        }

        // Remove trailing dangling prepositions
        if let range = cleaned.range(of: #"\s+(?:for|in|at|about)\s*$"#, options: .regularExpression) {
            cleaned.removeSubrange(range)
        }

        // Collapse whitespace
        while cleaned.contains("  ") {
            cleaned = cleaned.replacingOccurrences(of: "  ", with: " ")
        }

        cleaned = cleaned.trimmingCharacters(in: .whitespacesAndNewlines)

        // Capitalize first letter
        if let first = cleaned.first, first.isLowercase {
            cleaned = first.uppercased() + cleaned.dropFirst()
        }

        return cleaned
    }
}
