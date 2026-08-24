import Foundation

/// The de Bruijn sequence of `symbols` symbols and a window of `window`: a
/// cyclic run in which **every** possible window of that length appears, and
/// each appears exactly once.
///
/// ```swift
/// deBruijnSequence(symbols: 2, window: 3)   // 0,0,0,1,0,1,1,1
/// ```
///
/// Read that run around a circle three at a time and the eight windows it gives
/// are the eight three-bit patterns, in some order, with nothing repeated. It is
/// as short as such a run can be, `symbols` to the power of `window`, since there
/// are that many windows to fit and each takes one place.
///
/// The run that comes back is the smallest one in dictionary order, which is why
/// it always opens with a row of zeros. It is built as the Lyndon words whose
/// length divides `window`, in order, laid end to end.
///
/// This is what to reach for when a pattern has to be *locally unique*: a strip of
/// beads where any few in a row say where you are, a ruler a camera can read from
/// a glimpse, a run of tiles that never repeats itself close up. `DeBruijnCode`
/// wraps the sequence with the reading in the other direction.
public func deBruijnSequence(symbols: Int, window: Int) -> [Int] {
    guard symbols >= 1, window >= 1 else { return [] }
    guard symbols > 1 else { return [0] }

    var word = [Int](repeating: 0, count: symbols * window + 1)
    var sequence: [Int] = []
    sequence.reserveCapacity(Int(pow(Double(symbols), Double(window))))

    // Generate the necklaces in order. A word is written out when its own period
    // divides the window, which is exactly the Lyndon words the run is made of.
    func walk(_ length: Int, _ period: Int) {
        if length > window {
            if window % period == 0 { sequence.append(contentsOf: word[1 ... period]) }
            return
        }
        word[length] = word[length - period]
        walk(length + 1, period)
        var next = word[length - period] + 1
        while next < symbols {
            word[length] = next
            walk(length + 1, length)
            next += 1
        }
    }
    walk(1, 1)
    return sequence
}

/// Every Lyndon word over `symbols` symbols up to `maxLength`, in dictionary
/// order.
///
/// A Lyndon word is a run that is strictly smaller than every rotation of itself,
/// which is another way of saying it is the one representative of a necklace that
/// has no repeat in it. They are the pieces a de Bruijn sequence is made of, and
/// on their own they are a catalog of the patterns of a given length that are
/// genuinely different rather than the same pattern turned round.
///
/// ```swift
/// lyndonWords(symbols: 2, maxLength: 3)   // 0, 001, 011, 1
/// ```
public func lyndonWords(symbols: Int, maxLength: Int) -> [[Int]] {
    guard symbols >= 1, maxLength >= 1 else { return [] }
    var words: [[Int]] = []
    var word = [0]
    // Duval's construction: repeat the current word out to the length, then cut
    // back to the last symbol that can still be raised.
    while !word.isEmpty {
        words.append(word)
        var next: [Int] = []
        next.reserveCapacity(maxLength)
        while next.count < maxLength { next.append(word[next.count % word.count]) }
        while !next.isEmpty, next[next.count - 1] == symbols - 1 { next.removeLast() }
        if next.isEmpty { break }
        next[next.count - 1] += 1
        word = next
    }
    return words
}

/// A de Bruijn sequence with the reading in the other direction: hand it a window
/// and it says where in the run that window sits.
///
/// That is the whole use of the thing. A strip carrying the sequence tells any
/// reader its own position from a glimpse of a few symbols, which is how a rotary
/// encoder finds its angle and how a camera finds its place on a printed ruler.
///
/// ```swift
/// let code = DeBruijnCode(symbols: 4, window: 3)   // 64 beads, every triple once
/// code.position(of: [2, 0, 1])                     // where that triple sits
/// code.window(at: 17)                              // the triple starting there
/// ```
///
/// The table is built once and holds one entry per window, so `symbols` to the
/// power of `window` entries: fine into the thousands, not into the millions.
public struct DeBruijnCode: Sendable {
    /// The alphabet size.
    public let symbols: Int
    /// How many symbols a reader has to see.
    public let window: Int
    /// The sequence itself, `symbols` to the power of `window` long, read as a ring.
    public let sequence: [Int]

    private let places: [Int: Int]

    public init(symbols: Int, window: Int) {
        self.symbols = Swift.max(1, symbols)
        self.window = Swift.max(1, window)
        sequence = deBruijnSequence(symbols: self.symbols, window: self.window)

        var found: [Int: Int] = [:]
        found.reserveCapacity(sequence.count)
        guard !sequence.isEmpty else {
            places = [:]
            return
        }
        for start in sequence.indices {
            var key = 0
            for step in 0 ..< self.window {
                key = key * self.symbols + sequence[(start + step) % sequence.count]
            }
            found[key] = start
        }
        places = found
    }

    /// Where `run` sits in the sequence, or nil if it is the wrong length or holds
    /// a symbol the alphabet does not have.
    public func position(of run: [Int]) -> Int? {
        guard run.count == window else { return nil }
        var key = 0
        for symbol in run {
            guard symbol >= 0, symbol < symbols else { return nil }
            key = key * symbols + symbol
        }
        return places[key]
    }

    /// The window starting at `position`, read around the ring.
    public func window(at position: Int) -> [Int] {
        guard !sequence.isEmpty else { return [] }
        let start = ((position % sequence.count) + sequence.count) % sequence.count
        return (0 ..< window).map { sequence[(start + $0) % sequence.count] }
    }
}
