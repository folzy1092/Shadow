import Foundation

/// Shadow: «Сравнить правки» — what changed between two versions of a message's text, word by word, so a long post
/// shows only its changed words marked instead of both versions in full. Foundation only (tested by
/// `Tests/ShadowSettings/TextDiffTests.swift`).
public enum ShadowTextDiff {
    public enum Kind: Equatable {
        case same
        case deleted
        case inserted
    }

    public struct Segment: Equatable {
        public let kind: Kind
        public let text: String

        public init(kind: Kind, text: String) {
            self.kind = kind
            self.text = text
        }
    }

    /// Above this many compared token pairs the part that differs is shown as one deletion and one insertion: the
    /// comparison table would take too long and too much memory (a 1 000-word change on each side is a million).
    public static let maxComparedPairs = 1_000_000

    /// Words (letters and digits), runs of whitespace, and every other character on its own (punctuation, emoji).
    public static func tokens(_ text: String) -> [String] {
        enum Class {
            case word
            case space
            case other
        }
        func classify(_ character: Character) -> Class {
            if character.isWhitespace {
                return .space
            }
            if character.isLetter || character.isNumber || character == "_" {
                return .word
            }
            return .other
        }

        var result: [String] = []
        var current = ""
        var currentClass: Class?
        for character in text {
            let characterClass = classify(character)
            if let previous = currentClass, previous == characterClass, characterClass != .other {
                current.append(character)
            } else {
                if !current.isEmpty {
                    result.append(current)
                }
                current = String(character)
                currentClass = characterClass
            }
        }
        if !current.isEmpty {
            result.append(current)
        }
        return result
    }

    /// The segments that turn `old` into `new`: unchanged text, deleted text and inserted text, in reading order, with
    /// a deletion before the insertion that replaces it. Joining the `.same` and `.deleted` texts gives `old`; joining
    /// the `.same` and `.inserted` texts gives `new`.
    public static func segments(old: String, new: String) -> [Segment] {
        let oldTokens = tokens(old)
        let newTokens = tokens(new)

        var prefix = 0
        while prefix < oldTokens.count && prefix < newTokens.count && oldTokens[prefix] == newTokens[prefix] {
            prefix += 1
        }
        var suffix = 0
        while suffix < oldTokens.count - prefix && suffix < newTokens.count - prefix && oldTokens[oldTokens.count - 1 - suffix] == newTokens[newTokens.count - 1 - suffix] {
            suffix += 1
        }

        let oldMiddle = Array(oldTokens[prefix ..< oldTokens.count - suffix])
        let newMiddle = Array(newTokens[prefix ..< newTokens.count - suffix])

        var operations: [(Kind, String)] = []
        for token in oldTokens[0 ..< prefix] {
            operations.append((.same, token))
        }
        operations.append(contentsOf: middleOperations(old: oldMiddle, new: newMiddle))
        for token in oldTokens[oldTokens.count - suffix ..< oldTokens.count] {
            operations.append((.same, token))
        }

        return merged(absorbingSpaces(in: operations))
    }

    /// The longest common subsequence of the two token lists, as operations; a table too large is one replacement.
    private static func middleOperations(old: [String], new: [String]) -> [(Kind, String)] {
        let n = old.count
        let m = new.count
        if n == 0 || m == 0 || n * m > maxComparedPairs {
            return old.map { (.deleted, $0) } + new.map { (.inserted, $0) }
        }

        // lengths[i][j]: the common subsequence of old[i...] and new[j...], in one flat array.
        let width = m + 1
        var lengths = [Int32](repeating: 0, count: (n + 1) * width)
        var i = n - 1
        while i >= 0 {
            var j = m - 1
            while j >= 0 {
                if old[i] == new[j] {
                    lengths[i * width + j] = lengths[(i + 1) * width + j + 1] + 1
                } else {
                    lengths[i * width + j] = max(lengths[(i + 1) * width + j], lengths[i * width + j + 1])
                }
                j -= 1
            }
            i -= 1
        }

        var result: [(Kind, String)] = []
        var pendingDeleted: [String] = []
        var pendingInserted: [String] = []
        func flush() {
            for token in pendingDeleted {
                result.append((.deleted, token))
            }
            for token in pendingInserted {
                result.append((.inserted, token))
            }
            pendingDeleted.removeAll()
            pendingInserted.removeAll()
        }
        i = 0
        var j = 0
        while i < n && j < m {
            if old[i] == new[j] {
                flush()
                result.append((.same, old[i]))
                i += 1
                j += 1
            } else if lengths[(i + 1) * width + j] >= lengths[i * width + j + 1] {
                pendingDeleted.append(old[i])
                i += 1
            } else {
                pendingInserted.append(new[j])
                j += 1
            }
        }
        while i < n {
            pendingDeleted.append(old[i])
            i += 1
        }
        while j < m {
            pendingInserted.append(new[j])
            j += 1
        }
        flush()
        return result
    }

    /// A lone space kept between two changes splits one changed phrase into word-by-word pieces ("−a +x −b +y"):
    /// such a space joins both sides of the change ("−a b +x y").
    private static func absorbingSpaces(in operations: [(Kind, String)]) -> [(Kind, String)] {
        var result = operations
        var index = 1
        while index < result.count - 1 {
            let (kind, text) = result[index]
            if kind == .same, text.allSatisfy({ $0.isWhitespace }), !text.contains(where: { $0.isNewline }), result[index - 1].0 != .same, result[index + 1].0 != .same {
                result[index] = (.deleted, text)
                result.insert((.inserted, text), at: index + 1)
                index += 2
            } else {
                index += 1
            }
        }
        // Within each run of changes, every deletion goes before every insertion.
        var ordered: [(Kind, String)] = []
        var deleted: [(Kind, String)] = []
        var inserted: [(Kind, String)] = []
        for operation in result {
            switch operation.0 {
            case .same:
                ordered.append(contentsOf: deleted)
                ordered.append(contentsOf: inserted)
                deleted.removeAll()
                inserted.removeAll()
                ordered.append(operation)
            case .deleted:
                deleted.append(operation)
            case .inserted:
                inserted.append(operation)
            }
        }
        ordered.append(contentsOf: deleted)
        ordered.append(contentsOf: inserted)
        return ordered
    }

    private static func merged(_ operations: [(Kind, String)]) -> [Segment] {
        var result: [Segment] = []
        for (kind, text) in operations where !text.isEmpty {
            if let last = result.last, last.kind == kind {
                result[result.count - 1] = Segment(kind: kind, text: last.text + text)
            } else {
                result.append(Segment(kind: kind, text: text))
            }
        }
        return result
    }

    /// How much of the text changed: (deleted words, inserted words), counting word tokens only.
    public static func changedWordCounts(_ segments: [Segment]) -> (deleted: Int, inserted: Int) {
        var deleted = 0
        var inserted = 0
        for segment in segments {
            let words = tokens(segment.text).filter { token in token.contains(where: { $0.isLetter || $0.isNumber }) }.count
            switch segment.kind {
            case .same:
                break
            case .deleted:
                deleted += words
            case .inserted:
                inserted += words
            }
        }
        return (deleted, inserted)
    }
}
