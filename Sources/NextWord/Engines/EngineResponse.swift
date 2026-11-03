import Foundation

enum EngineResponse {
    static let authFailureMarkers = [
        "not logged in", "please run /login", "/login", "log in", "login", "authentication",
        "unauthorized", "invalid api key", "oauth token", "token has expired", "401",
    ]

    static func clean(_ words: [String], count: Int) -> [String] {
        var seen = Set<String>()
        var cleaned: [String] = []
        for raw in words {
            let word = cleanWord(raw)
            guard !word.isEmpty, seen.insert(word.lowercased()).inserted else { continue }
            cleaned.append(word)
            if cleaned.count >= max(1, count) { break }
        }
        return cleaned
    }

    static func cleanWord(_ raw: String) -> String {
        let quotes = CharacterSet(charactersIn: "\"'`“”‘’«»„")
        let trailing = CharacterSet(charactersIn: ".,;:!?…)]}")
        var word = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if let range = word.range(of: #"^(\d+\s*[.):\-]|[-*•–—])\s*"#, options: .regularExpression) {
            word.removeSubrange(range)
        }
        var previous = ""
        while word != previous {
            previous = word
            word = word
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .trimmingCharacters(in: quotes)
                .trimmingCharacters(in: trailing)
            if word.hasPrefix("(") || word.hasPrefix("[") { word.removeFirst() }
        }
        return word.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    static func jsonObject(in text: String) -> [String: Any]? {
        if let object = decodeObject(text) { return object }
        if let line = text.split(whereSeparator: \.isNewline).last(where: { $0.hasPrefix("{") }),
           let object = decodeObject(String(line)) {
            return object
        }
        guard let start = text.firstIndex(of: "{"), let end = text.lastIndex(of: "}"), start < end else { return nil }
        return decodeObject(String(text[start...end]))
    }

    private static func decodeObject(_ text: String) -> [String: Any]? {
        guard let data = text.data(using: .utf8) else { return nil }
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }

    static func snippet(_ text: String, limit: Int = 300) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.count > limit ? String(trimmed.prefix(limit)) + "…" : trimmed
    }

    static func makeMeaning(from fields: [String: Any], word: String, request: SuggestionRequest) -> WordMeaning? {
        func field(_ key: String) -> String? {
            guard let value = (fields[key] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !value.isEmpty else { return nil }
            return value
        }
        guard let definition = field("definition") else { return nil }
        let translation = field("nativeTranslation").map(cleanWord).flatMap { $0.isEmpty ? nil : $0 } ?? word
        return WordMeaning(
            word: word,
            partOfSpeech: field("partOfSpeech"),
            definition: definition,
            example: request.includeExample ? field("example") : nil,
            nativeLanguage: request.nativeLanguage,
            nativeTranslation: translation,
            nativeDefinition: field("nativeDefinition") ?? definition
        )
    }

    static func looksLikeAuthFailure(_ text: String, extraMarkers: [String] = []) -> Bool {
        (authFailureMarkers + extraMarkers).contains { containsPhrase($0, in: text) }
    }

    static func containsPhrase(_ phrase: String, in text: String) -> Bool {
        let pattern = "(?<![\\p{L}\\p{N}_])" + NSRegularExpression.escapedPattern(for: phrase) + "(?![\\p{L}\\p{N}_])"
        return text.range(of: pattern, options: [.regularExpression, .caseInsensitive]) != nil
    }
}
