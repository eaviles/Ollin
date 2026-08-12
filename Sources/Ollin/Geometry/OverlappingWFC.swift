import Foundation
import os

/// Which turned and mirrored copies of the sample a model learns from.
///
/// A sample is a small picture, and most of what it teaches applies just as well
/// sideways or in a mirror. Learning those copies too multiplies what the solver
/// has to work with without asking for a bigger sample, at the cost of a texture
/// that no longer remembers which way up it was drawn.
public enum WFCSymmetry: Sendable, CaseIterable {
    /// The sample exactly as given. Keeps a directional sample (a skyline, a
    /// waterline, anything with an up) the way round it was drawn.
    case none
    /// The sample and its four quarter turns.
    case rotations
    /// The sample, its four quarter turns, and the mirror of each. The default,
    /// and the right answer for a texture with no particular orientation.
    case all

    /// Which of the eight copies of a patch this keeps, as indices into the
    /// mirror-and-turn sequence: 0 is the patch itself, the even ones are its
    /// four quarter turns, and each odd one mirrors the turn before it. So the
    /// turns alone are the even indices, and everything is all eight.
    var keptVariants: [Int] {
        switch self {
        case .none: return [0]
        case .rotations: return [0, 2, 4, 6]
        case .all: return Array(0 ..< 8)
        }
    }
}

/// Wave Function Collapse, the *overlapping* model: learn from an example
/// picture instead of hand-declaring tiles. The model cuts the sample into every
/// `patternSize × patternSize` patch it contains, counts how often each one
/// occurs, and works out which patches may overlap each other. Solving then
/// fills a fresh grid with those patches so that every overlap agrees, and the
/// result is a new picture that is locally indistinguishable from the sample and
/// globally nothing like it.
///
/// It's the complement of the tiled model in
/// [`WaveFunctionCollapse`](x-source-tag://WaveFunctionCollapse): that one takes
/// tiles you designed and edge sockets you declared, this one takes a picture and
/// works the vocabulary out for itself.
///
/// ```swift
/// // A 16x16 doodle in, a 64x64 texture out.
/// if let model = OverlappingWFC(learningFrom: sample, patternSize: 3),
///    let texture = model.solve(width: 64, height: 64, using: &rng) {
///     drawImage(texture, in: bounds)
/// }
/// ```
///
/// Learning is the expensive half and doesn't depend on the output, so a model
/// built once solves as many textures as you like. Both halves are pure
/// functions of the sample and the seed, so a run reproduces.
///
/// The sample wants to be *small and few-colored*: this is a technique for pixel
/// art and hand-drawn motifs, tens of pixels on a side, not a photograph. A
/// photo has a distinct color in nearly every patch, so nearly every patch is
/// unique, nothing overlaps anything else, and the solve has nothing to choose
/// between.
///
/// - Tag: OverlappingWFC
public struct OverlappingWFC: Sendable {

    // MARK: - What the model was asked for

    /// The side of the square patches the sample was cut into.
    public let patternSize: Int
    /// Which turned and mirrored copies of the sample were learned from.
    public let symmetry: WFCSymmetry
    /// Whether the sample was read as wrapping at its edges when patches were cut.
    public let wrapsSample: Bool

    // MARK: - What it learned

    /// The distinct colors of the sample, as premultiplied RGBA8 words, in the
    /// order they were first met scanning the sample. Patterns index into this.
    private let palette: [UInt32]
    /// Every distinct patch, back to back: pattern `p`'s cell `(x, y)` lives at
    /// `patterns[p * area + y * patternSize + x]` and holds a palette index.
    private let patterns: [Int32]
    /// How often each pattern occurred in the sample (and its learned copies).
    private let weights: [Double]
    /// `weights[p] * log(weights[p])`, the running term of the entropy.
    private let weightLogWeights: [Double]

    /// For each direction and pattern, the patterns that may sit in the neighbor
    /// that way: `propagator[d]` is a flat run of pattern lists, `p`'s starting
    /// at `propagatorStart[d][p]` and running `propagatorCount[d][p]` long.
    private let propagator: [[Int32]]
    private let propagatorStart: [[Int32]]
    private let propagatorCount: [[Int32]]

    /// How many distinct patterns the sample taught.
    public var patternCount: Int { weights.count }

    /// The most patterns a sample may teach before the model refuses it. A
    /// pattern set past this means the sample isn't the small, few-colored kind
    /// of picture the technique works on, and building the overlap table would
    /// cost more than the solve is worth.
    public static let maxPatterns = 1024

    /// The most distinct colors a sample may hold. Same reasoning: a picture with
    /// more colors than this is a photograph, not a motif.
    public static let maxColors = 256

    // MARK: - Directions

    // Neighbor offsets for directions 0…3, and which direction points back.
    private static let dx: [Int] = [-1, 0, 1, 0]
    private static let dy: [Int] = [0, 1, 0, -1]
    private static let opposite: [Int] = [2, 3, 0, 1]
    private static let directions = 0 ..< 4

    // MARK: - Learning

    /// Learn a model from `sample`.
    ///
    /// Returns `nil` when the sample can't be read (a GPU-backed image has no CPU
    /// pixels), when it's smaller than one patch, or when it's too large and
    /// varied to be a sample at all (see `maxPatterns` and `maxColors`); each case
    /// prints a note saying which.
    ///
    /// - Parameters:
    ///   - sample: The example picture. Small and few-colored: tens of pixels a
    ///     side, a handful of colors.
    ///   - patternSize: The side of the patches the sample is cut into. `2` keeps
    ///     only the loosest sense of the sample, `3` is the usual choice, and
    ///     larger reproduces bigger motifs at the cost of variety.
    ///   - symmetry: Which turned and mirrored copies to learn from as well.
    ///   - wrapsSample: Read the sample as wrapping at its edges, so patches are
    ///     cut from every position rather than stopping a patch short of the
    ///     right and bottom edges. True suits a sample that tiles; false keeps a
    ///     sample's own border out of the vocabulary.
    public init?(learningFrom sample: Image, patternSize: Int = 3,
                 symmetry: WFCSymmetry = .all, wrapsSample: Bool = true) {
        let n = max(2, patternSize)
        self.patternSize = n
        self.symmetry = symmetry
        self.wrapsSample = wrapsSample

        guard let bytes = sample.premultipliedPixels() else {
            OverlappingWFCNotes.note("OverlappingWFC needs CPU pixels; a texture-backed image has none. Read a video frame through its snapshot first.")
            return nil
        }
        let sw = sample.width, sh = sample.height
        guard sw > 0, sh > 0 else { return nil }
        guard wrapsSample || (sw >= n && sh >= n) else {
            OverlappingWFCNotes.note("OverlappingWFC: the sample is \(sw)x\(sh), smaller than one \(n)x\(n) patch. Use a larger sample, a smaller patternSize, or wrapsSample: true.")
            return nil
        }

        // Index the sample's colors. First-met order scanning the sample, so the
        // palette (and everything keyed on it) is a pure function of the pixels.
        var palette: [UInt32] = []
        var colorIndex: [UInt32: Int32] = [:]
        var indexed = [Int32](repeating: 0, count: sw * sh)
        for i in 0 ..< (sw * sh) {
            let word = UInt32(bytes[i * 4]) << 24 | UInt32(bytes[i * 4 + 1]) << 16
                     | UInt32(bytes[i * 4 + 2]) << 8 | UInt32(bytes[i * 4 + 3])
            if let known = colorIndex[word] {
                indexed[i] = known
            } else {
                guard palette.count < OverlappingWFC.maxColors else {
                    OverlappingWFCNotes.note("OverlappingWFC: the sample holds more than \(OverlappingWFC.maxColors) distinct colors, so it is a photograph rather than a motif. Posterize it (try dithered(_:levels:)) or use a smaller, flatter sample.")
                    return nil
                }
                let next = Int32(palette.count)
                colorIndex[word] = next
                palette.append(word)
                indexed[i] = next
            }
        }
        self.palette = palette

        // Cut every patch the sample holds, in each learned variant, counting how
        // often each distinct one turns up. Patches are gathered in scan order and
        // distinct ones appended as first met, so the pattern list is ordered by
        // the sample rather than by hash order.
        let area = n * n
        var distinct: [[Int32]: Int] = [:]
        var flat: [Int32] = []
        var counts: [Double] = []

        // A patch read out of the sample at (px, py), wrapping if asked.
        func patch(_ px: Int, _ py: Int) -> [Int32] {
            var out = [Int32](repeating: 0, count: area)
            for y in 0 ..< n {
                let sy = wrapsSample ? (py + y) % sh : py + y
                for x in 0 ..< n {
                    let sx = wrapsSample ? (px + x) % sw : px + x
                    out[y * n + x] = indexed[sy * sw + sx]
                }
            }
            return out
        }

        let lastX = wrapsSample ? sw - 1 : sw - n
        let lastY = wrapsSample ? sh - 1 : sh - n
        let kept = symmetry.keptVariants
        for py in 0 ... max(lastY, 0) {
            for px in 0 ... max(lastX, 0) {
                // The eight copies of the patch, built by alternately mirroring
                // and turning: 0 is the patch itself, the even ones are its four
                // quarter turns, and each odd one mirrors the turn before it.
                var dihedral = [[Int32]]()
                dihedral.reserveCapacity(8)
                dihedral.append(patch(px, py))
                for v in 1 ..< 8 {
                    dihedral.append(v % 2 == 1
                        ? OverlappingWFC.mirrored(dihedral[v - 1], n)
                        : OverlappingWFC.rotated(dihedral[v - 2], n))
                }
                for v in kept {
                    let variant = dihedral[v]
                    if let known = distinct[variant] {
                        counts[known] += 1
                    } else {
                        guard counts.count < OverlappingWFC.maxPatterns else {
                            OverlappingWFCNotes.note("OverlappingWFC: the sample teaches more than \(OverlappingWFC.maxPatterns) distinct \(n)x\(n) patterns, which is past what the technique is for. Use a smaller or flatter sample, a smaller patternSize, or symmetry: .none.")
                            return nil
                        }
                        distinct[variant] = counts.count
                        counts.append(1)
                        flat.append(contentsOf: variant)
                    }
                }
            }
        }
        guard !counts.isEmpty else { return nil }

        self.patterns = flat
        self.weights = counts
        self.weightLogWeights = counts.map { $0 * Foundation.log($0) }

        // Which patterns may overlap which, in each direction. Two patterns agree
        // in direction d when the part they share once the neighbor is offset by
        // (dx, dy) holds the same colors in both.
        let count = counts.count
        var propagator = [[Int32]](repeating: [], count: 4)
        var starts = [[Int32]](repeating: [Int32](repeating: 0, count: count), count: 4)
        var lengths = [[Int32]](repeating: [Int32](repeating: 0, count: count), count: 4)
        flat.withUnsafeBufferPointer { pats in
            for d in 0 ..< 4 {
                var list: [Int32] = []
                list.reserveCapacity(count * 4)
                for p in 0 ..< count {
                    starts[d][p] = Int32(list.count)
                    for q in 0 ..< count where OverlappingWFC.agree(pats, p, q,
                                                                   OverlappingWFC.dx[d],
                                                                   OverlappingWFC.dy[d], n) {
                        list.append(Int32(q))
                    }
                    lengths[d][p] = Int32(list.count) - starts[d][p]
                }
                propagator[d] = list
            }
        }
        self.propagator = propagator
        self.propagatorStart = starts
        self.propagatorCount = lengths
    }

    /// A patch turned a quarter turn.
    private static func rotated(_ p: [Int32], _ n: Int) -> [Int32] {
        var out = [Int32](repeating: 0, count: n * n)
        for y in 0 ..< n {
            for x in 0 ..< n {
                out[y * n + x] = p[x * n + (n - 1 - y)]
            }
        }
        return out
    }

    /// A patch mirrored left to right.
    private static func mirrored(_ p: [Int32], _ n: Int) -> [Int32] {
        var out = [Int32](repeating: 0, count: n * n)
        for y in 0 ..< n {
            for x in 0 ..< n {
                out[y * n + x] = p[y * n + (n - 1 - x)]
            }
        }
        return out
    }

    /// Whether pattern `q` may sit at offset `(ox, oy)` from pattern `p`: the
    /// region the two cover in common must read the same in both.
    private static func agree(_ pats: UnsafeBufferPointer<Int32>,
                              _ p: Int, _ q: Int, _ ox: Int, _ oy: Int, _ n: Int) -> Bool {
        let area = n * n
        let pBase = p * area, qBase = q * area
        // The overlap in p's coordinates: x from max(0, ox) up to min(n, n + ox).
        let xMin = max(0, ox), xMax = min(n, n + ox)
        let yMin = max(0, oy), yMax = min(n, n + oy)
        for y in yMin ..< yMax {
            for x in xMin ..< xMax {
                if pats[pBase + y * n + x] != pats[qBase + (y - oy) * n + (x - ox)] {
                    return false
                }
            }
        }
        return true
    }

    // MARK: - Inspecting what was learned

    /// Pattern `index` as its own little image, for drawing the vocabulary the
    /// sample taught. Clamped to the patterns that exist.
    public func pattern(_ index: Int) -> Image {
        let n = patternSize
        let p = max(0, min(index, patternCount - 1))
        var bytes = [UInt8](repeating: 0, count: n * n * 4)
        for i in 0 ..< (n * n) {
            let word = palette[Int(patterns[p * n * n + i])]
            bytes[i * 4] = UInt8((word >> 24) & 0xFF)
            bytes[i * 4 + 1] = UInt8((word >> 16) & 0xFF)
            bytes[i * 4 + 2] = UInt8((word >> 8) & 0xFF)
            bytes[i * 4 + 3] = UInt8(word & 0xFF)
        }
        return Image(width: n, height: n, premultipliedRGBA: bytes) ?? Image(width: n, height: n)
    }

    /// How often pattern `index` occurred in the sample, which is how likely it
    /// is when a cell settles. Clamped to the patterns that exist.
    public func weight(_ index: Int) -> Double {
        weights[max(0, min(index, patternCount - 1))]
    }

    // MARK: - Solving

    /// Synthesize a `width × height` picture from what the sample taught, or
    /// `nil` if no consistent filling was found within `attempts` restarts.
    ///
    /// - Parameters:
    ///   - width: The output width in pixels.
    ///   - height: The output height in pixels.
    ///   - tileable: Solve the output as a torus, so the result tiles seamlessly
    ///     with itself. Off by default, which lets the edges do as they like.
    ///   - attempts: How many times to restart after a contradiction (a cell left
    ///     with no pattern that fits).
    ///   - rng: The generator every choice is drawn from.
    public func solve<R: RandomNumberGenerator>(width: Int, height: Int,
                                                tileable: Bool = false,
                                                attempts: Int = 10,
                                                using rng: inout R) -> Image? {
        guard width > 0, height > 0, patternCount > 0 else { return nil }
        // A bounded output reads its last patch-width of pixels back out of the
        // last cell that covers them, so it needs room for two patches side by
        // side less their overlap; anything smaller has nowhere to read from.
        let smallest = 2 * patternSize - 2
        guard tileable || (width >= smallest && height >= smallest) else {
            OverlappingWFCNotes.note("OverlappingWFC: a \(width)x\(height) output is too small to solve with \(patternSize)x\(patternSize) patches; it needs to be at least \(smallest) each way, or tileable.")
            return nil
        }
        for _ in 0 ..< max(attempts, 1) {
            if let observed = attempt(width: width, height: height, tileable: tileable, using: &rng) {
                return render(observed, width: width, height: height, tileable: tileable)
            }
        }
        return nil
    }

    /// One run of observe-and-propagate. Returns the settled pattern per cell, or
    /// `nil` on a contradiction.
    private func attempt<R: RandomNumberGenerator>(width: Int, height: Int, tileable: Bool,
                                                   using rng: inout R) -> [Int32]? {
        var solver = Solver(model: self, width: width, height: height, tileable: tileable)
        return solver.run(using: &rng)
    }

    /// Turn the settled patterns back into pixels.
    ///
    /// A cell holds the pattern whose *top-left* corner sits there, so ordinarily
    /// a pixel is just its own cell's first color. The cells within one patch of
    /// the right or bottom edge are never settled when the output doesn't wrap
    /// (a patch placed there would hang over the edge), so those pixels are read
    /// out of the last settled cell instead, at the offset they sit at inside it.
    private func render(_ observed: [Int32], width: Int, height: Int, tileable: Bool) -> Image? {
        let n = patternSize, area = n * n
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        for y in 0 ..< height {
            let oy = tileable ? 0 : (y < height - n + 1 ? 0 : n - 1)
            for x in 0 ..< width {
                let ox = tileable ? 0 : (x < width - n + 1 ? 0 : n - 1)
                let cell = (y - oy) * width + (x - ox)
                let word = palette[Int(patterns[Int(observed[cell]) * area + oy * n + ox])]
                let i = (y * width + x) * 4
                bytes[i] = UInt8((word >> 24) & 0xFF)
                bytes[i + 1] = UInt8((word >> 16) & 0xFF)
                bytes[i + 2] = UInt8((word >> 8) & 0xFF)
                bytes[i + 3] = UInt8(word & 0xFF)
            }
        }
        return Image(width: width, height: height, premultipliedRGBA: bytes)
    }

    // MARK: - The solver

    /// One solve in progress. Flat storage throughout: the inner loops run
    /// millions of times and examples run unoptimized, so this stays scalar
    /// indexing into contiguous arrays rather than nested arrays of structs.
    private struct Solver {
        let model: OverlappingWFC
        let width: Int
        let height: Int
        let tileable: Bool
        let count: Int          // patterns
        let cells: Int

        /// `wave[cell * count + p]`: may cell still hold pattern p?
        var wave: [Bool]
        /// `compatible[(cell * count + p) * 4 + d]`: how many patterns are still
        /// standing in the neighbor **opposite** `d` that would allow `p` to sit
        /// here. Mind that inversion; it is the one place this algorithm is
        /// quietly wrong if you read `d` for `opposite[d]`, since the code still
        /// compiles and still produces a picture.
        ///
        /// When one of these reaches zero, nothing over there can sit beside `p`
        /// any more, so `p` is unplaceable and gets banned. Keeping the count is
        /// what makes propagation cheap: the alternative is rebuilding each
        /// cell's allowed set from scratch every time a neighbor changes.
        var compatible: [Int32]
        var remaining: [Int32]              // patterns left per cell
        var sumWeights: [Double]
        var sumWeightLogWeights: [Double]
        var entropies: [Double]
        /// The (cell, pattern) bans still to spread.
        var stack: [(cell: Int32, pattern: Int32)] = []

        init(model: OverlappingWFC, width: Int, height: Int, tileable: Bool) {
            self.model = model
            self.width = width
            self.height = height
            self.tileable = tileable
            self.count = model.patternCount
            self.cells = width * height

            wave = [Bool](repeating: true, count: cells * count)
            compatible = [Int32](repeating: 0, count: cells * count * 4)
            remaining = [Int32](repeating: Int32(count), count: cells)

            let totalWeight = model.weights.reduce(0, +)
            let totalWLW = model.weightLogWeights.reduce(0, +)
            sumWeights = [Double](repeating: totalWeight, count: cells)
            sumWeightLogWeights = [Double](repeating: totalWLW, count: cells)
            let startingEntropy = Foundation.log(totalWeight) - totalWLW / totalWeight
            entropies = [Double](repeating: startingEntropy, count: cells)

            // A pattern's count in direction d starts as the number of patterns
            // that support it from the other side, which is exactly the size of
            // the opposite direction's list.
            for cell in 0 ..< cells {
                for p in 0 ..< count {
                    for d in 0 ..< 4 {
                        compatible[(cell * count + p) * 4 + d] =
                            model.propagatorCount[OverlappingWFC.opposite[d]][p]
                    }
                }
            }
        }

        mutating func run<R: RandomNumberGenerator>(using rng: inout R) -> [Int32]? {
            if !banPatternsWithNowhereToGo() { return nil }
            while true {
                switch observe(using: &rng) {
                case .contradiction: return nil
                case .finished:
                    var out = [Int32](repeating: 0, count: cells)
                    for cell in 0 ..< cells {
                        var chosen: Int32 = -1
                        for p in 0 ..< count where wave[cell * count + p] { chosen = Int32(p); break }
                        // An unsettled edge cell is never read by `render`, but it
                        // must still name something; its first survivor will do.
                        out[cell] = chosen < 0 ? 0 : chosen
                    }
                    return out
                case .ok:
                    if !propagate() { return nil }
                }
            }
        }

        enum Step { case ok, finished, contradiction }

        /// Rule out, before anything is settled, any pattern that has *no* legal
        /// neighbor in some direction where a neighbor actually exists.
        ///
        /// The propagation loop assumes every pattern still standing has
        /// somewhere to pass its support along; one that doesn't can never be
        /// eliminated by a counter reaching zero, because no counter is ever
        /// decremented on its behalf. Left in, it survives to be chosen and the
        /// output is quietly illegal rather than contradictory. Patterns like
        /// this show up when the sample is read as bounded, where the patches
        /// along its edges may have nothing that can follow them.
        mutating func banPatternsWithNowhereToGo() -> Bool {
            var stranded = false
            for p in 0 ..< count where OverlappingWFC.directions.contains(where: {
                model.propagatorCount[$0][p] == 0
            }) {
                stranded = true
                for cell in 0 ..< cells where wave[cell * count + p] {
                    guard tileable || canHoldPatch(cell) else { continue }
                    // Only a direction with a real neighbor can strand a pattern:
                    // at the edge of a bounded output there is nothing that way to
                    // disagree with.
                    let x = cell % width, y = cell / width
                    let strandedHere = OverlappingWFC.directions.contains { d in
                        guard model.propagatorCount[d][p] == 0 else { return false }
                        let nx = x + OverlappingWFC.dx[d], ny = y + OverlappingWFC.dy[d]
                        return tileable || holdsPatch(nx, ny)
                    }
                    if strandedHere {
                        ban(cell, p)
                        if remaining[cell] == 0 { return false }
                    }
                }
            }
            return stranded ? propagate() : true
        }

        /// Settle the most-constrained cell: the one whose remaining patterns carry
        /// the least entropy, which is where a contradiction would surface soonest.
        mutating func observe<R: RandomNumberGenerator>(using rng: inout R) -> Step {
            var best = -1
            var bestEntropy = Double.infinity
            for cell in 0 ..< cells {
                if !tileable && !canHoldPatch(cell) { continue }
                let left = remaining[cell]
                if left == 0 { return .contradiction }
                if left == 1 { continue }
                // A hair of noise breaks ties, drawn in a fixed cell order so the
                // choice is a pure function of the seed.
                let key = entropies[cell] + Double.random(in: 0 ..< 1e-6, using: &rng)
                if key < bestEntropy { bestEntropy = key; best = cell }
            }
            guard best >= 0 else { return .finished }

            // Pick one of the survivors, weighted by how common it was in the
            // sample, then ban the rest.
            var total = 0.0
            for p in 0 ..< count where wave[best * count + p] { total += model.weights[p] }
            var pick = Double.random(in: 0 ..< Swift.max(total, .leastNonzeroMagnitude), using: &rng)
            var chosen = -1
            for p in 0 ..< count where wave[best * count + p] {
                pick -= model.weights[p]
                if pick < 0 { chosen = p; break }
                chosen = p
            }
            for p in 0 ..< count where p != chosen && wave[best * count + p] {
                ban(best, p)
            }
            return .ok
        }

        /// Whether a patch placed with its corner at this cell fits inside the
        /// output. When the output doesn't wrap, the cells within one patch of the
        /// right or bottom edge don't take part in the solve at all.
        func canHoldPatch(_ cell: Int) -> Bool {
            holdsPatch(cell % width, cell / width)
        }

        func holdsPatch(_ x: Int, _ y: Int) -> Bool {
            let n = model.patternSize
            return x >= 0 && y >= 0 && x + n <= width && y + n <= height
        }

        /// Spread every ban outward until nothing changes. Each banned pattern
        /// withdraws its support from its neighbors; a neighbor's pattern that
        /// runs out of support is banned in turn.
        mutating func propagate() -> Bool {
            while let (cell, pattern) = stack.popLast() {
                let x = Int(cell) % width, y = Int(cell) / width
                for d in 0 ..< 4 {
                    var nx = x + OverlappingWFC.dx[d]
                    var ny = y + OverlappingWFC.dy[d]
                    if tileable {
                        nx = (nx + width) % width
                        ny = (ny + height) % height
                    } else if !holdsPatch(nx, ny) {
                        // Off the edge, or too near the right or bottom edge for a
                        // patch to fit. Those cells are outside the solve
                        // altogether: nothing is ever settled there and nothing is
                        // read from there, so a ban must not spread into one (it
                        // would empty a cell nobody asked about and read as a
                        // contradiction).
                        continue
                    }
                    let neighbor = ny * width + nx
                    let start = Int(model.propagatorStart[d][Int(pattern)])
                    let length = Int(model.propagatorCount[d][Int(pattern)])
                    for i in start ..< (start + length) {
                        let q = Int(model.propagator[d][i])
                        let slot = (neighbor * count + q) * 4 + d
                        compatible[slot] -= 1
                        if compatible[slot] == 0 && wave[neighbor * count + q] {
                            ban(neighbor, q)
                            if remaining[neighbor] == 0 { return false }
                        }
                    }
                }
            }
            return true
        }

        /// Rule pattern `p` out of `cell`, and note the ban for propagation.
        mutating func ban(_ cell: Int, _ p: Int) {
            wave[cell * count + p] = false
            for d in 0 ..< 4 { compatible[(cell * count + p) * 4 + d] = 0 }
            remaining[cell] -= 1
            sumWeights[cell] -= model.weights[p]
            sumWeightLogWeights[cell] -= model.weightLogWeights[p]
            let sw = sumWeights[cell]
            entropies[cell] = sw > 0 ? Foundation.log(sw) - sumWeightLogWeights[cell] / sw : 0
            stack.append((Int32(cell), Int32(p)))
        }
    }
}

// MARK: - Notes

/// One-time notes for a sample the model can't learn from, keyed by message so a
/// sketch that asks every frame says it once. Lock-guarded rather than
/// main-actor-bound: a model is `Sendable`, so learning may run off the main
/// thread.
private enum OverlappingWFCNotes {
    private static let printed = OSAllocatedUnfairLock(initialState: Set<String>())
    static func note(_ message: String) {
        let isNew = printed.withLock { $0.insert(message).inserted }
        if isNew { print("Ollin: \(message)") }
    }
}

// MARK: - Sketch sugar

public extension Sketch {
    /// Synthesize a `width × height` texture from an example picture: Wave
    /// Function Collapse's overlapping model learns the sample's
    /// `patternSize × patternSize` patches and how they may overlap, then fills a
    /// fresh grid so every overlap agrees.
    ///
    /// Driven by the seeded `random`, so `seed(_:)` makes the result
    /// reproducible. Learning and solving are both real work, so do this once (in
    /// `setup`, or guarded so it runs on the first frame) rather than every frame.
    ///
    /// ```swift
    /// let texture = wfc(from: sample, width: 64, height: 64)
    /// ```
    ///
    /// The sample wants to be small and few-colored (pixel art, a hand-drawn
    /// motif), not a photograph. Returns `nil` if the sample can't be learned from
    /// or no consistent filling was found; both print a note saying which.
    func wfc(from sample: Image, width: Int, height: Int,
             patternSize: Int = 3, symmetry: WFCSymmetry = .all,
             wrapsSample: Bool = true, tileable: Bool = false,
             attempts: Int = 10) -> Image? {
        guard let model = OverlappingWFC(learningFrom: sample, patternSize: patternSize,
                                         symmetry: symmetry, wrapsSample: wrapsSample) else {
            return nil
        }
        return model.solve(width: width, height: height, tileable: tileable,
                           attempts: attempts, using: &rng)
    }

    /// Synthesize from a model you already learned, driven by the seeded
    /// `random`. Learning is the expensive half and doesn't depend on the output,
    /// so a sketch that solves more than once (or wants to show what the sample
    /// taught) builds the model itself and keeps it:
    ///
    /// ```swift
    /// let model = OverlappingWFC(learningFrom: sample, patternSize: 3)
    /// // ... later, as often as you like
    /// let texture = wfc(model, width: 64, height: 64)
    /// ```
    func wfc(_ model: OverlappingWFC, width: Int, height: Int,
             tileable: Bool = false, attempts: Int = 10) -> Image? {
        model.solve(width: width, height: height, tileable: tileable,
                    attempts: attempts, using: &rng)
    }
}
