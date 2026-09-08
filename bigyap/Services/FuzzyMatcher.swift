import Foundation

/// Pure string-matching used to fix names and jargon the speech model mishears
/// ("swift data" → "SwiftData", "cuber netties" → "Kubernetes"). Combines edit
/// distance with a Soundex phonetic key so both typos and sound-alikes are
/// caught. No dependencies, fully testable.
nonisolated enum FuzzyMatcher {

    /// Classic Levenshtein edit distance between two lowercased strings.
    static func levenshtein(_ a: String, _ b: String) -> Int {
        let lhs = Array(a)
        let rhs = Array(b)
        if lhs.isEmpty { return rhs.count }
        if rhs.isEmpty { return lhs.count }

        var previous = Array(0...rhs.count)
        var current = [Int](repeating: 0, count: rhs.count + 1)

        for i in 1...lhs.count {
            current[0] = i
            for j in 1...rhs.count {
                let cost = lhs[i - 1] == rhs[j - 1] ? 0 : 1
                current[j] = Swift.min(
                    previous[j] + 1,        // deletion
                    current[j - 1] + 1,     // insertion
                    previous[j - 1] + cost  // substitution
                )
            }
            swap(&previous, &current)
        }
        return previous[rhs.count]
    }

    /// Soundex phonetic code (e.g. "Robert" and "Rupert" → "R163"). Letters
    /// that sound alike collapse to the same key, which is what lets us match
    /// mis-transcribed proper nouns.
    static func soundex(_ word: String) -> String {
        let letters = word.uppercased().unicodeScalars.filter { CharacterSet.uppercaseLetters.contains($0) }
        guard let first = letters.first else { return "" }

        func code(_ scalar: Unicode.Scalar) -> Character? {
            switch Character(scalar) {
            case "B", "F", "P", "V": return "1"
            case "C", "G", "J", "K", "Q", "S", "X", "Z": return "2"
            case "D", "T": return "3"
            case "L": return "4"
            case "M", "N": return "5"
            case "R": return "6"
            default: return nil  // vowels, H, W, Y
            }
        }

        var result = String(Character(first))
        var previousCode = code(first)

        for scalar in letters.dropFirst() {
            let current = code(scalar)
            if let current, current != previousCode {
                result.append(current)
                if result.count == 4 { break }
            }
            // H and W don't reset the "previous code" rule; vowels do.
            let char = Character(scalar)
            if char != "H", char != "W" {
                previousCode = current
            }
        }

        return String((result + "000").prefix(4))
    }

    /// The best vocabulary term for `token`, or nil if none is close enough.
    /// Never "corrects" a token that is already an exact (case-insensitive)
    /// member of the vocabulary.
    static func bestMatch(for token: String, in vocabulary: [String]) -> String? {
        let cleaned = token.lowercased()
        guard cleaned.count >= 3 else { return nil }

        var best: (term: String, score: Int)?

        for term in vocabulary {
            let lowerTerm = term.lowercased()
            if lowerTerm == cleaned { return nil }      // already correct
            if abs(lowerTerm.count - cleaned.count) > 3 { continue }

            let distance = levenshtein(cleaned, lowerTerm)
            let allowed = allowedDistance(for: lowerTerm)
            let phoneticMatch = soundex(cleaned) == soundex(lowerTerm) && !soundex(lowerTerm).isEmpty

            // Accept on small edit distance, OR a phonetic match with a
            // forgiving distance ceiling (sound-alikes can differ more).
            let qualifies = distance <= allowed || (phoneticMatch && distance <= allowed + 1)
            guard qualifies else { continue }

            // Lower distance wins; phonetic matches get a tiebreak nudge.
            let score = distance * 2 - (phoneticMatch ? 1 : 0)
            if best == nil || score < best!.score {
                best = (term, score)
            }
        }

        return best?.term
    }

    /// How many edits we tolerate scales with the term's length.
    private static func allowedDistance(for term: String) -> Int {
        switch term.count {
        case 0...4: return 1
        case 5...8: return 2
        default: return 3
        }
    }
}
