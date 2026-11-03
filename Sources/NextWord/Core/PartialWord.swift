import AppKit
import NaturalLanguage

enum PartialWord {
    private static let joiners: Set<Character> = ["'", "’", "-"]

    static func trailing(in text: String) -> String? {
        guard let last = text.last else { return nil }
        let endsInApostrophe = (last == "'" || last == "’") && text.dropLast().last?.isLetter == true
        guard last.isLetter || last.isNumber || endsInApostrophe else { return nil }
        let token = String(text.reversed().prefix { $0.isLetter || $0.isNumber || joiners.contains($0) }.reversed())
        if endsInApostrophe, let first = token.first, first == "'" || first == "‘" || first == "’" { return nil }
        let trimmed = token.drop { joiners.contains($0) }
        return trimmed.isEmpty ? nil : String(trimmed)
    }

    static func isUnfinished(_ token: String, context text: String) -> Bool {
        guard token.count > 1 else { return true }
        let recognizer = NLLanguageRecognizer()
        recognizer.processString(String(text.suffix(400)))
        let language = recognizer.dominantLanguage?.rawValue
        let check: () -> Bool = {
            let checker = NSSpellChecker.shared
            let code = language.flatMap { checker.availableLanguages.contains($0) ? $0 : nil }
            let misspelled = checker.checkSpelling(of: token, startingAt: 0, language: code, wrap: false, inSpellDocumentWithTag: 0, wordCount: nil)
            return misspelled.location != NSNotFound
        }
        return Thread.isMainThread ? check() : DispatchQueue.main.sync(execute: check)
    }
}
