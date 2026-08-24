import Foundation
import Ollin
import Testing

/// Laws for the de Bruijn sequence. The whole claim is a counting one, so the
/// tests count: the run is as long as it has to be, and every window turns up in
/// it exactly once.
@Suite
struct DeBruijnTests {
    /// The defining property, asked of every window there is: each appears, and
    /// each appears once. Checked by reading the run around the ring rather than
    /// along it, since the sequence is cyclic.
    @Test func everyWindowAppearsExactlyOnce() {
        for symbols in 2 ... 4 {
            for window in 1 ... 4 {
                let run = deBruijnSequence(symbols: symbols, window: window)
                let expected = Int(pow(Double(symbols), Double(window)))
                #expect(run.count == expected, "\(symbols) symbols, window \(window)")

                var seen: [[Int]: Int] = [:]
                for start in run.indices {
                    let piece = (0 ..< window).map { run[(start + $0) % run.count] }
                    seen[piece, default: 0] += 1
                }
                #expect(seen.count == expected, "\(symbols)/\(window) covered \(seen.count) windows")
                #expect(seen.values.allSatisfy { $0 == 1 }, "\(symbols)/\(window) repeated a window")
                #expect(run.allSatisfy { $0 >= 0 && $0 < symbols })
            }
        }
    }

    /// The known small case, symbol for symbol. The smallest run in dictionary
    /// order is the one that comes back, so it is a fixed answer rather than any
    /// valid one.
    @Test func theSmallestRunInOrderIsTheOneThatComesBack() {
        #expect(deBruijnSequence(symbols: 2, window: 3) == [0, 0, 0, 1, 0, 1, 1, 1])
        #expect(deBruijnSequence(symbols: 2, window: 2) == [0, 0, 1, 1])
        #expect(deBruijnSequence(symbols: 3, window: 2) == [0, 0, 1, 0, 2, 1, 1, 2, 2])
        // Which is why it always opens with a row of zeros.
        for symbols in 2 ... 5 {
            for window in 1 ... 4 {
                let run = deBruijnSequence(symbols: symbols, window: window)
                #expect(run.prefix(window).allSatisfy { $0 == 0 }, "\(symbols)/\(window)")
            }
        }
    }

    /// Nothing to say for an empty alphabet, and one symbol says one thing.
    @Test func theSmallCasesAreAnsweredPlainly() {
        #expect(deBruijnSequence(symbols: 0, window: 3).isEmpty)
        #expect(deBruijnSequence(symbols: 2, window: 0).isEmpty)
        #expect(deBruijnSequence(symbols: 1, window: 4) == [0])
        #expect(deBruijnSequence(symbols: 5, window: 1) == [0, 1, 2, 3, 4])
    }

    /// Lyndon words are the pieces the run is made of, so the two have to agree:
    /// the words whose length divides the window, in order, laid end to end, are
    /// the sequence itself.
    @Test func theSequenceIsItsLyndonWordsLaidEndToEnd() {
        for symbols in 2 ... 4 {
            for window in 1 ... 4 {
                let pieces = lyndonWords(symbols: symbols, maxLength: window)
                    .filter { window % $0.count == 0 }
                #expect(pieces.flatMap { $0 } == deBruijnSequence(symbols: symbols, window: window),
                        "\(symbols) symbols, window \(window)")
            }
        }
    }

    /// A Lyndon word is strictly smaller than every rotation of itself. That is the
    /// definition, and it is cheap to check outright.
    @Test func everyLyndonWordIsSmallerThanItsOwnRotations() {
        for symbols in 2 ... 4 {
            let words = lyndonWords(symbols: symbols, maxLength: 5)
            for word in words {
                for turn in 1 ..< word.count {
                    let rotated = Array(word[turn...] + word[..<turn])
                    #expect(smaller(word, rotated), "\(word) is not below its rotation \(rotated)")
                }
            }
            // And they come back in order, with no repeats.
            for i in 1 ..< words.count {
                #expect(smaller(words[i - 1], words[i]), "\(words[i - 1]) came before \(words[i])")
            }
        }
    }

    /// How many Lyndon words there are of each length is a counting formula, and it
    /// is worked out here from the definition rather than taken from the code.
    @Test func theLyndonWordCountsMatchTheNecklaceFormula() {
        for symbols in 2 ... 4 {
            let words = lyndonWords(symbols: symbols, maxLength: 6)
            for length in 1 ... 6 {
                var total = 0
                for divisor in 1 ... length where length % divisor == 0 {
                    total += mobius(length / divisor) * Int(pow(Double(symbols), Double(divisor)))
                }
                #expect(words.filter { $0.count == length }.count == total / length,
                        "\(symbols) symbols, length \(length)")
            }
        }
    }

    // MARK: - Reading it back

    /// The use the sequence exists for: a few symbols say where you are, and the
    /// answer is right for every position.
    @Test func aWindowSaysWhereItSits() {
        for (symbols, window) in [(2, 4), (3, 3), (4, 3), (5, 2)] {
            let code = DeBruijnCode(symbols: symbols, window: window)
            #expect(code.sequence.count == Int(pow(Double(symbols), Double(window))))
            for position in code.sequence.indices {
                let seen = code.window(at: position)
                #expect(seen.count == window)
                #expect(code.position(of: seen) == position, "\(symbols)/\(window) at \(position)")
            }
            // Reading past the end wraps, since the run is a ring.
            #expect(code.window(at: code.sequence.count) == code.window(at: 0))
            #expect(code.window(at: -1) == code.window(at: code.sequence.count - 1))
        }
    }

    /// A window of the wrong length, or one holding a symbol the alphabet does not
    /// have, is not somewhere in the sequence. It is nowhere.
    @Test func aWindowThatCannotExistIsRefused() {
        let code = DeBruijnCode(symbols: 3, window: 3)
        #expect(code.position(of: [0, 1]) == nil)
        #expect(code.position(of: [0, 1, 2, 0]) == nil)
        #expect(code.position(of: [0, 1, 7]) == nil)
        #expect(code.position(of: [0, 1, -1]) == nil)
        #expect(code.position(of: [0, 0, 0]) == 0)
    }

    // MARK: - Helpers

    private func smaller(_ a: [Int], _ b: [Int]) -> Bool {
        for (x, y) in zip(a, b) {
            if x != y { return x < y }
        }
        return a.count < b.count
    }

    /// The Möbius function, from its own definition.
    private func mobius(_ n: Int) -> Int {
        var n = n, primes = 0
        var factor = 2
        while factor * factor <= n {
            if n % factor == 0 {
                n /= factor
                if n % factor == 0 { return 0 }
                primes += 1
            }
            factor += 1
        }
        if n > 1 { primes += 1 }
        return primes % 2 == 0 ? 1 : -1
    }
}
