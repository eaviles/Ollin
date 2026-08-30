import Foundation

/// Turns a phrase into the fixed-length token sequence a contrastive
/// image-text model's text encoder expects: lowercased words split by a
/// byte-pair-encoding vocabulary, wrapped in start/end markers, padded to the
/// model's context length.
///
/// The vocabulary is the published merges file the model was trained with
/// (fetched beside the model weights, never bundled). Byte-pair encoding
/// starts from a word's UTF-8 bytes (each byte mapped to a printable stand-in
/// character) and greedily joins the pair with the lowest merge rank until no
/// listed pair remains; the surviving pieces are the tokens.
struct PhraseTokenizer: Sendable {

    /// A candidate pair of adjacent pieces, looked up in the merge ranks.
    private struct Pair: Hashable {
        let first: String
        let second: String
    }

    /// How long every encoded sequence is, start/end markers included.
    let contextLength = 77

    let startToken: Int32
    let endToken: Int32

    /// Merge rank by pair; lower merges first.
    private let ranks: [Pair: Int]
    /// Token id by piece text.
    private let ids: [String: Int32]
    /// The stand-in character for each of the 256 byte values.
    private let byteStandIns: [String]

    /// How many pieces the vocabulary knows (the text model's input range).
    var vocabularySize: Int { ids.count }

    /// Reads the merges file (the first line is a header; the model's
    /// vocabulary uses the first 48,894 merge lines).
    init(vocabularyAt url: URL) throws {
        let text = try String(contentsOf: url, encoding: .utf8)
        var lines = text.split(separator: "\n", omittingEmptySubsequences: false)
        // Header line, then exactly the merges the model's vocabulary covers.
        lines = Array(lines.dropFirst().prefix(48894))

        // The 256 byte stand-ins, in vocabulary order: the printable Latin-1
        // ranges keep their own character; every other byte value gets a
        // stand-in from U+0100 up, appended after the printable ones.
        var mappedBytes: [Int] = []
        mappedBytes.append(contentsOf: 33...126)
        mappedBytes.append(contentsOf: 161...172)
        mappedBytes.append(contentsOf: 174...255)
        var standInsInOrder = mappedBytes.map { String(UnicodeScalar($0)!) }
        var byByte = [String](repeating: "", count: 256)
        for (value, standIn) in zip(mappedBytes, standInsInOrder) {
            byByte[value] = standIn
        }
        var next = 256
        for value in 0..<256 where byByte[value].isEmpty {
            let standIn = String(UnicodeScalar(next)!)
            byByte[value] = standIn
            standInsInOrder.append(standIn)
            next += 1
        }
        self.byteStandIns = byByte

        // Token ids, in the published order: the 256 stand-ins, the same 256
        // as word endings, one joined token per merge, then the two markers.
        var ids: [String: Int32] = [:]
        ids.reserveCapacity(256 * 2 + lines.count + 2)
        var ranks: [Pair: Int] = [:]
        ranks.reserveCapacity(lines.count)
        var id: Int32 = 0
        for standIn in standInsInOrder {
            ids[standIn] = id
            id += 1
        }
        for standIn in standInsInOrder {
            ids[standIn + "</w>"] = id
            id += 1
        }
        for (rank, line) in lines.enumerated() {
            let halves = line.split(separator: " ")
            guard halves.count == 2 else {
                throw Error.badVocabulary("line \(rank + 2) isn't a pair: \(line)")
            }
            ranks[Pair(first: String(halves[0]), second: String(halves[1]))] = rank
            ids[String(halves[0] + halves[1])] = id
            id += 1
        }
        ids["<|startoftext|>"] = id
        self.startToken = id
        id += 1
        ids["<|endoftext|>"] = id
        self.endToken = id
        self.ids = ids
        self.ranks = ranks
    }

    enum Error: Swift.Error, CustomStringConvertible {
        case badVocabulary(String)
        var description: String {
            switch self {
            case .badVocabulary(let reason): return "Bad tokenizer vocabulary: \(reason)"
            }
        }
    }

    /// The phrase as the model's input: start marker, the phrase's tokens, end
    /// marker, zero-padded to `contextLength`. A phrase too long to fit is
    /// truncated and still ends on the end marker.
    func encode(_ phrase: String) -> [Int32] {
        var tokens: [Int32] = [startToken]
        for word in Self.words(of: phrase) {
            tokens.append(contentsOf: pieces(of: word))
        }
        tokens.append(endToken)
        if tokens.count > contextLength {
            tokens = Array(tokens.prefix(contextLength))
            tokens[contextLength - 1] = endToken
        }
        tokens.append(contentsOf: [Int32](repeating: 0, count: contextLength - tokens.count))
        return tokens
    }

    /// The splitter the vocabulary was built around: contraction endings on
    /// their own, letter runs, single digits, and punctuation runs. Spaces
    /// only separate.
    private static let splitter = try! NSRegularExpression(
        pattern: "'s|'t|'re|'ve|'m|'ll|'d|[\\p{L}]+|[\\p{N}]|[^\\s\\p{L}\\p{N}]+")

    /// Lowercased, whitespace-collapsed, split into the units byte-pair
    /// encoding runs over.
    static func words(of phrase: String) -> [String] {
        let cleaned = phrase
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
            .lowercased()
        let range = NSRange(cleaned.startIndex..., in: cleaned)
        return splitter.matches(in: cleaned, range: range).compactMap {
            Range($0.range, in: cleaned).map { String(cleaned[$0]) }
        }
    }

    /// One word through byte-pair encoding: UTF-8 bytes as stand-ins, the last
    /// carrying the word-end marker, then the lowest-ranked adjacent pair joins
    /// until none is listed.
    private func pieces(of word: String) -> [Int32] {
        let bytes = Array(word.utf8)
        guard !bytes.isEmpty else { return [] }
        var parts = bytes.map { byteStandIns[Int($0)] }
        parts[parts.count - 1] += "</w>"

        while parts.count > 1 {
            var best: (rank: Int, index: Int)?
            for index in 0..<(parts.count - 1) {
                let pair = Pair(first: parts[index], second: parts[index + 1])
                if let rank = ranks[pair], rank < best?.rank ?? .max {
                    best = (rank, index)
                }
            }
            guard let found = best else { break }
            // Join every adjacent occurrence of that pair in one pass, the way
            // the published algorithm does.
            let first = parts[found.index]
            let second = parts[found.index + 1]
            var joined: [String] = []
            joined.reserveCapacity(parts.count)
            var index = 0
            while index < parts.count {
                if index < parts.count - 1, parts[index] == first, parts[index + 1] == second {
                    joined.append(first + second)
                    index += 2
                } else {
                    joined.append(parts[index])
                    index += 1
                }
            }
            parts = joined
        }
        return parts.map { ids[$0] ?? 0 }
    }
}
