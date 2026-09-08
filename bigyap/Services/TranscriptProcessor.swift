import Foundation

/// Post-transcription text pipeline: custom-vocabulary fuzzy correction, then
/// filler-word removal, then tidy-up. Non-destructive by design — callers keep
/// the raw transcript and apply this on top, so every step is reversible by
/// toggling it off. Pure and fully testable.
nonisolated struct TranscriptProcessor: Sendable {
    var vocabulary: [String] = []
    var fillerWords: [String] = []
    var correctVocabulary: Bool = true
    var removeFillers: Bool = true
    /// Put each sentence on its own line, separated by a blank line, so the
    /// transcript pastes into a chat already formatted as readable paragraphs.
    var paragraphPerSentence: Bool = false

    func process(_ text: String) -> String {
        var result = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !result.isEmpty else { return result }

        if correctVocabulary, !vocabulary.isEmpty {
            result = Self.applyVocabulary(result, vocabulary: vocabulary)
        }
        if removeFillers, !fillerWords.isEmpty {
            result = Self.removeFillerWords(result, fillers: fillerWords)
        }
        result = Self.tidy(result)
        if paragraphPerSentence {
            result = Self.splitIntoParagraphs(result)
        }
        return result
    }

    // MARK: - Vocabulary correction

    static func applyVocabulary(_ text: String, vocabulary: [String]) -> String {
        guard !vocabulary.isEmpty else { return text }
        let ns = text as NSString
        guard let regex = try? NSRegularExpression(pattern: "[\\p{L}\\p{N}']+") else { return text }
        let matches = regex.matches(in: text, range: NSRange(location: 0, length: ns.length))
        guard !matches.isEmpty else { return text }

        // Despaced lookup for compound terms like "SwiftData" spoken as "swift data".
        let despaced = vocabulary.filter { $0.contains(where: { !$0.isLetter && !$0.isNumber }) == false }

        struct Replacement { var range: NSRange; var text: String }
        var replacements: [Replacement] = []
        var index = 0

        while index < matches.count {
            let word = ns.substring(with: matches[index].range)

            // Bigram-join pass: "swift data" -> "SwiftData". An exact joined
            // match (same letters, different spacing/casing) must win even
            // though fuzzy matching treats it as "already correct".
            if index + 1 < matches.count {
                let next = ns.substring(with: matches[index + 1].range)
                let joined = (word + next).lowercased()
                let exact = despaced.first { $0.lowercased() == joined }
                if let term = exact ?? FuzzyMatcher.bestMatch(for: joined, in: despaced) {
                    let span = NSRange(location: matches[index].range.location,
                                       length: NSMaxRange(matches[index + 1].range) - matches[index].range.location)
                    replacements.append(Replacement(range: span, text: term))
                    index += 2
                    continue
                }
            }

            // Unigram pass.
            if let term = FuzzyMatcher.bestMatch(for: word, in: vocabulary) {
                replacements.append(Replacement(range: matches[index].range, text: term))
            }
            index += 1
        }

        guard !replacements.isEmpty else { return text }
        let mutable = NSMutableString(string: text)
        for replacement in replacements.reversed() {
            mutable.replaceCharacters(in: replacement.range, with: replacement.text)
        }
        return mutable as String
    }

    // MARK: - Filler removal

    static func removeFillerWords(_ text: String, fillers: [String]) -> String {
        let cleaned = fillers
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .sorted { $0.count > $1.count }  // match multi-word fillers first
        guard !cleaned.isEmpty else { return text }

        let alternation = cleaned.map { NSRegularExpression.escapedPattern(for: $0) }.joined(separator: "|")
        // Word-boundaried, case-insensitive, optionally swallowing a trailing comma/space.
        let pattern = "\\b(?:\(alternation))\\b[ \\t]*,?"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return text }

        let ns = text as NSString
        let stripped = regex.stringByReplacingMatches(in: text, range: NSRange(location: 0, length: ns.length), withTemplate: "")
        return stripped
    }

    // MARK: - Tidy

    static func tidy(_ text: String) -> String {
        var result = text

        let rules: [(String, String)] = [
            ("[ \\t]{2,}", " "),       // collapse runs of spaces
            ("\\s+([,.!?;:])", "$1"),  // no space before punctuation
            ("([,.!?;:]){2,}", "$1"),  // collapse repeated punctuation
            ("^[\\s,.;:]+", ""),       // leading junk
        ]
        for (pattern, template) in rules {
            if let regex = try? NSRegularExpression(pattern: pattern) {
                let ns = result as NSString
                result = regex.stringByReplacingMatches(in: result, range: NSRange(location: 0, length: ns.length), withTemplate: template)
            }
        }

        result = capitalizingSentences(result)
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Paragraph formatting

    /// Puts each sentence on its own line, separated by a blank line, so a
    /// pasted transcript reads as cleanly spaced paragraphs. Uses the system
    /// sentence tokenizer, so abbreviations ("e.g.") and decimals ("3.14")
    /// don't split mid-sentence. A single-sentence transcript is returned
    /// unchanged.
    static func splitIntoParagraphs(_ text: String) -> String {
        let ns = text as NSString
        var sentences: [String] = []
        ns.enumerateSubstrings(in: NSRange(location: 0, length: ns.length), options: .bySentences) { substring, _, _, _ in
            let trimmed = substring?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if !trimmed.isEmpty { sentences.append(trimmed) }
        }
        guard sentences.count > 1 else { return text }
        return sentences.joined(separator: "\n\n")
    }

    /// Uppercases the first letter of the string and the first letter after
    /// each sentence-ending punctuation mark.
    static func capitalizingSentences(_ text: String) -> String {
        var characters = Array(text)
        var capitalizeNext = true
        for i in characters.indices {
            let char = characters[i]
            if capitalizeNext, char.isLetter {
                characters[i] = Character(char.uppercased())
                capitalizeNext = false
            } else if ".!?".contains(char) {
                capitalizeNext = true
            } else if char.isLetter || char.isNumber {
                capitalizeNext = false
            }
        }
        return String(characters)
    }
}
