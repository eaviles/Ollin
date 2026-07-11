import Foundation

/// One-dimensional **elementary cellular automaton** (rules 0...255): every cell reads
/// its three-cell neighborhood (left, self, right) and looks the next value up in the
/// rule's 8-bit table, so a single number names the whole system. Rule 30 boils into
/// chaos, rule 90 draws the Sierpinski triangle, rule 110 grows structured machinery;
/// stacking the generations as rows is the classic picture.
///
/// Returns `generations` rows (the first is the start row), each `width` cells wide,
/// ready to draw over a `Grid` or as rects. Deterministic: the same inputs always
/// produce the same rows. Setup-time work, not per-frame (though a small automaton is
/// cheap enough to rebuild live under a rule knob).
///
/// - Parameters:
///   - rule: The rule number, wrapped into 0...255. Bit `(left<<2 | self<<1 | right)`
///     of the rule byte is the neighborhood's next value.
///   - width: Cells per row (at least 1).
///   - generations: Rows returned, including the start row (at least 1).
///   - start: The first row, padded or trimmed to `width`. `nil` starts from a single
///     live cell at the center, the classic seed.
///   - wrap: Whether the row's two ends neighbor each other (a ring). `false` reads
///     past the edge as dead.
public func elementaryCA(rule: Int, width: Int, generations: Int,
                         from start: [Bool]? = nil, wrap: Bool = true) -> [[Bool]] {
    let width = max(1, width)
    let rule = ((rule % 256) + 256) % 256
    var row = normalizedStartRow(start, width: width, off: false) { $0[width / 2] = true }
    var rows: [[Bool]] = []
    rows.reserveCapacity(max(1, generations))
    rows.append(row)
    var next = [Bool](repeating: false, count: width)
    for _ in 1 ..< max(1, generations) {
        for i in 0 ..< width {
            let l = i > 0 ? row[i - 1] : (wrap ? row[width - 1] : false)
            let r = i < width - 1 ? row[i + 1] : (wrap ? row[0] : false)
            let pattern = (l ? 4 : 0) | (row[i] ? 2 : 0) | (r ? 1 : 0)
            next[i] = (rule >> pattern) & 1 == 1
        }
        swap(&row, &next)
        rows.append(row)
    }
    return rows
}

/// One-dimensional **totalistic cellular automaton**: a cell's next value depends only
/// on the *sum* of its three-cell neighborhood, looked up as digit `sum` of `code`
/// written in base `colors`. With more than two colors the family draws patterns the
/// elementary rules can't reach (code 777 over 3 colors is a classic irregular grower).
///
/// Returns `generations` rows of color indices `0 ..< colors` (the first is the start
/// row). Deterministic, like `elementaryCA`.
///
/// - Parameters:
///   - code: The totalistic code. Digit `i` (base `colors`, least significant first)
///     is the next value for a neighborhood summing to `i`; digits past the table's
///     `3 * (colors - 1) + 1` entries are ignored.
///   - colors: How many cell values, clamped to 2...8.
///   - width: Cells per row (at least 1).
///   - generations: Rows returned, including the start row (at least 1).
///   - start: The first row, values clamped into range, padded or trimmed to `width`.
///     `nil` starts from a single center cell of color 1.
///   - wrap: Whether the row's two ends neighbor each other (a ring).
public func totalisticCA(code: Int, colors: Int = 3, width: Int, generations: Int,
                         from start: [Int]? = nil, wrap: Bool = true) -> [[Int]] {
    let width = max(1, width)
    let k = min(8, max(2, colors))
    // The lookup table: digit `sum` of the code in base k, sums 0 through 3(k - 1).
    var table = [Int](repeating: 0, count: 3 * (k - 1) + 1)
    var c = max(0, code)
    for i in table.indices { table[i] = c % k; c /= k }
    var row = normalizedStartRow(start.map { $0.map { min(k - 1, max(0, $0)) } },
                                 width: width, off: 0) { $0[width / 2] = 1 }
    var rows: [[Int]] = []
    rows.reserveCapacity(max(1, generations))
    rows.append(row)
    var next = [Int](repeating: 0, count: width)
    for _ in 1 ..< max(1, generations) {
        for i in 0 ..< width {
            let l = i > 0 ? row[i - 1] : (wrap ? row[width - 1] : 0)
            let r = i < width - 1 ? row[i + 1] : (wrap ? row[0] : 0)
            next[i] = table[l + row[i] + r]
        }
        swap(&row, &next)
        rows.append(row)
    }
    return rows
}

/// Pad or trim a caller's start row to `width`, or build the default single-seed row.
private func normalizedStartRow<Value>(_ start: [Value]?, width: Int, off: Value,
                                       seed: (inout [Value]) -> Void) -> [Value] {
    guard let start, !start.isEmpty else {
        var row = [Value](repeating: off, count: width)
        seed(&row)
        return row
    }
    if start.count == width { return start }
    if start.count > width { return Array(start.prefix(width)) }
    return start + [Value](repeating: off, count: width - start.count)
}

public extension Sketch {

    /// An elementary cellular automaton; see the free function of the same name. The
    /// facade mirrors it so bare calls inside a sketch resolve.
    func elementaryCA(rule: Int, width: Int, generations: Int,
                      from start: [Bool]? = nil, wrap: Bool = true) -> [[Bool]] {
        Ollin.elementaryCA(rule: rule, width: width, generations: generations,
                           from: start, wrap: wrap)
    }

    /// A totalistic cellular automaton; see the free function of the same name. The
    /// facade mirrors it so bare calls inside a sketch resolve.
    func totalisticCA(code: Int, colors: Int = 3, width: Int, generations: Int,
                      from start: [Int]? = nil, wrap: Bool = true) -> [[Int]] {
        Ollin.totalisticCA(code: code, colors: colors, width: width,
                           generations: generations, from: start, wrap: wrap)
    }

    /// An elementary cellular automaton grown from a *random* start row (each cell live
    /// with probability `startDensity`), rolled on the sketch's seeded `random` so a
    /// `variation` brings the same field back.
    func elementaryCA(rule: Int, width: Int, generations: Int, startDensity: Double,
                      wrap: Bool = true) -> [[Bool]] {
        var row = [Bool](repeating: false, count: max(1, width))
        for i in row.indices { row[i] = random(1) < startDensity }
        return Ollin.elementaryCA(rule: rule, width: width, generations: generations,
                                  from: row, wrap: wrap)
    }

    /// A totalistic cellular automaton grown from a *random* start row: each cell takes
    /// a uniform non-zero color with probability `startDensity`, else 0. Rolled on the
    /// sketch's seeded `random` so a `variation` brings the same field back.
    func totalisticCA(code: Int, colors: Int = 3, width: Int, generations: Int,
                      startDensity: Double, wrap: Bool = true) -> [[Int]] {
        let k = min(8, max(2, colors))
        var row = [Int](repeating: 0, count: max(1, width))
        for i in row.indices where random(1) < startDensity {
            row[i] = 1 + Int(random(Double(k - 1)))
        }
        return Ollin.totalisticCA(code: code, colors: k, width: width,
                                  generations: generations, from: row, wrap: wrap)
    }
}
