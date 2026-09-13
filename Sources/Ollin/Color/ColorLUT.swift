import Foundation
import simd

/// A color lookup table: the look a grading tool exports as a `.cube` file,
/// read into a value a sketch applies with `Filter.lut(_:amount:)` or asks
/// directly with `color(for:)`.
///
/// A `.cube` file is the plain-text table Adobe published and every color
/// tool writes: DaVinci Resolve, Premiere, Photoshop, and the camera makers'
/// own looks. It comes in two forms. A **cube** (`LUT_3D_SIZE`) holds an
/// output color for every node of a lattice over the input's red, green, and
/// blue, so it can move any color anywhere: a film look, a grade, a print
/// emulation. **Curves** (`LUT_1D_SIZE`) hold one curve per channel, so each
/// channel bends on its own and none can see the others: a tone curve, a
/// transfer function.
///
/// ```swift
/// var look = ColorLUT.warmPrint                      // the bundled look
///
/// override func setup() {
///     look = try! ColorLUT(resource: "teal-orange", withExtension: "cube", in: .module)
/// }
///
/// override func draw() {
///     drawImage(photo, 0, 0)
///     postProcess(.lut(look, amount: 0.8))
/// }
/// ```
///
/// A table is authored on the picture a display shows, so the filter encodes
/// the layer's linear light before the read and decodes the answer after it,
/// and a value above white reads as white, since a table has no node past its
/// last. A cube is read by tetrahedral interpolation, the way a grading tool
/// reads it, so a gray input stays gray between the nodes of a table that
/// leaves gray alone. A file that is not a `.cube` is refused with the line
/// that stopped it. Read a file once, in `setup()`: the renderer keeps the
/// table on the GPU by its contents, so a table built every frame is
/// uploaded every frame. See `Docs/Drawing/Looks.md`.
public struct ColorLUT: Sendable, Equatable {

    /// Which of the two tables a file holds.
    public enum Form: Sendable {
        /// One curve per channel (`LUT_1D_SIZE`): each channel bends on its own.
        case curves
        /// A lattice over all three channels (`LUT_3D_SIZE`): any color can go anywhere.
        case cube
    }

    /// What stopped a file from reading, and the line it happened on.
    public struct ReadError: Error, Equatable, Sendable, CustomStringConvertible {
        /// The line the problem is on, counted from 1, or `nil` when the
        /// whole file is the problem (a size that was never declared, a
        /// count that does not add up).
        public let line: Int?
        /// What was wrong, in a sentence.
        public let problem: String

        public var description: String {
            if let line { return "line \(line): \(problem)" }
            return problem
        }
    }

    /// The `TITLE` the file carries, or an empty string.
    public let title: String
    /// Curves or a cube.
    public let form: Form
    /// Nodes along each axis: the curve's length, or the cube's edge.
    public let size: Int

    /// The input each axis runs over, from the file's `DOMAIN_MIN` and
    /// `DOMAIN_MAX` (0 to 1 unless the file says otherwise).
    let domainMin: SIMD3<Float>
    let domainMax: SIMD3<Float>
    /// `size` entries (curves) or `size` cubed (cube), red fastest then green
    /// then blue, which is the file's own order and the memory order of a 3D
    /// texture. `rgb` is the table's value, `a` is 1, so the array uploads
    /// verbatim as an `rgba32Float` texture.
    let samples: [SIMD4<Float>]
    /// FNV-1a over the samples, size, and form: what keys the renderer's
    /// texture cache, so two reads of one file share one upload.
    let fingerprint: UInt64

    init(title: String, form: Form, size: Int, domainMin: SIMD3<Float>, domainMax: SIMD3<Float>,
         samples: [SIMD4<Float>]) {
        self.title = title
        self.form = form
        self.size = size
        self.domainMin = domainMin
        self.domainMax = domainMax
        self.samples = samples
        self.fingerprint = Self.digest(samples, size: size, form: form)
    }

    public static func == (lhs: ColorLUT, rhs: ColorLUT) -> Bool {
        lhs.fingerprint == rhs.fingerprint && lhs.size == rhs.size && lhs.form == rhs.form
    }

    // MARK: Reading a file

    /// The table in a `.cube` file on disk. Throws a `ReadError` naming the
    /// line that stopped it.
    public init(contentsOf path: String) throws {
        guard let data = FileManager.default.contents(atPath: path) else {
            throw ReadError(line: nil, problem: "no file at \(path)")
        }
        try self.init(data: data)
    }

    /// The table in a bundled `.cube` file.
    ///
    /// `in:` has no default on purpose: a default would resolve to Ollin's
    /// own bundle rather than the caller's. Pass `.module` from your sketch.
    public init(resource: String, withExtension ext: String? = "cube", in bundle: Bundle) throws {
        guard let url = bundle.url(forResource: resource, withExtension: ext) else {
            throw ReadError(line: nil, problem: "no resource named \(resource) in the bundle")
        }
        try self.init(contentsOf: url.path)
    }

    /// The table in the bytes of a `.cube` file.
    public init(data: Data) throws {
        guard let text = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) else {
            throw ReadError(line: nil, problem: "the file is not text")
        }
        try self.init(text: text)
    }

    /// The table in the text of a `.cube` file.
    ///
    /// The format is line-based: `#` opens a comment, `TITLE "…"` names the
    /// table, `LUT_1D_SIZE n` or `LUT_3D_SIZE n` declares its form and size,
    /// `DOMAIN_MIN r g b` and `DOMAIN_MAX r g b` (or Resolve's
    /// `LUT_1D_INPUT_RANGE lo hi` / `LUT_3D_INPUT_RANGE lo hi`) set the input
    /// range, and every other line is one entry of three numbers, red running
    /// fastest. A keyword the format does not have, an entry before the size,
    /// a second size, or an entry that is not three numbers is refused with
    /// its line; a count that does not match the size is refused at the end.
    public init(text: String) throws {
        var title = ""
        var form: Form?
        var size = 0
        var domainMin = SIMD3<Float>(0, 0, 0)
        var domainMax = SIMD3<Float>(1, 1, 1)
        var samples: [SIMD4<Float>] = []
        var expected = 0
        var lineNumber = 0

        func numbers(_ fields: ArraySlice<Substring>, _ line: Int, _ what: String) throws -> [Float] {
            var out: [Float] = []
            for field in fields {
                guard let value = Float(field), value.isFinite else {
                    throw ReadError(line: line, problem: "\(what): '\(field)' is not a number")
                }
                out.append(value)
            }
            return out
        }

        for rawLine in text.split(omittingEmptySubsequences: false, whereSeparator: { $0.isNewline }) {
            lineNumber += 1
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.isEmpty || line.hasPrefix("#") { continue }
            let fields = line.split(whereSeparator: { $0 == " " || $0 == "\t" })
            guard let first = fields.first else { continue }

            // A line that opens with a letter is a keyword; anything else is an entry.
            if first.first!.isLetter {
                let keyword = first.uppercased()
                let rest = fields.dropFirst()
                switch keyword {
                case "TITLE":
                    var name = line.dropFirst(first.count).trimmingCharacters(in: .whitespaces)
                    if name.hasPrefix("\""), name.hasSuffix("\""), name.count >= 2 {
                        name = String(name.dropFirst().dropLast())
                    }
                    title = name
                case "LUT_1D_SIZE", "LUT_3D_SIZE":
                    if form != nil {
                        throw ReadError(line: lineNumber,
                                        problem: "a second table size (\(keyword)); a file holds one table")
                    }
                    guard rest.count == 1, let n = Int(rest.first!) else {
                        throw ReadError(line: lineNumber, problem: "\(keyword) wants one whole number")
                    }
                    if keyword == "LUT_1D_SIZE" {
                        guard n >= 2 && n <= 16384 else {
                            throw ReadError(line: lineNumber,
                                            problem: "LUT_1D_SIZE \(n): the curves want 2 to 16384 nodes")
                        }
                        form = .curves
                        expected = n
                    } else {
                        guard n >= 2 && n <= 256 else {
                            throw ReadError(line: lineNumber,
                                            problem: "LUT_3D_SIZE \(n): a cube wants 2 to 256 nodes on a side")
                        }
                        form = .cube
                        expected = n * n * n
                    }
                    size = n
                    samples.reserveCapacity(expected)
                case "DOMAIN_MIN", "DOMAIN_MAX":
                    let v = try numbers(rest, lineNumber, keyword)
                    guard v.count == 3 else {
                        throw ReadError(line: lineNumber, problem: "\(keyword) wants three numbers")
                    }
                    if keyword == "DOMAIN_MIN" { domainMin = SIMD3(v[0], v[1], v[2]) }
                    else { domainMax = SIMD3(v[0], v[1], v[2]) }
                case "LUT_1D_INPUT_RANGE", "LUT_3D_INPUT_RANGE":
                    let v = try numbers(rest, lineNumber, keyword)
                    guard v.count == 2 else {
                        throw ReadError(line: lineNumber, problem: "\(keyword) wants two numbers")
                    }
                    domainMin = SIMD3(repeating: v[0])
                    domainMax = SIMD3(repeating: v[1])
                default:
                    throw ReadError(line: lineNumber, problem: "unknown keyword '\(first)'")
                }
                continue
            }

            guard form != nil else {
                throw ReadError(line: lineNumber,
                                problem: "a table entry before the LUT_1D_SIZE or LUT_3D_SIZE keyword")
            }
            guard fields.count == 3 else {
                throw ReadError(line: lineNumber,
                                problem: "an entry is three numbers; this line has \(fields.count) fields")
            }
            let v = try numbers(fields[...], lineNumber, "entry")
            guard samples.count < expected else {
                throw ReadError(line: lineNumber, problem: "more entries than the size allows (\(expected))")
            }
            samples.append(SIMD4(v[0], v[1], v[2], 1))
        }

        guard let form else {
            throw ReadError(line: nil, problem: "no LUT_1D_SIZE or LUT_3D_SIZE keyword")
        }
        guard samples.count == expected else {
            throw ReadError(line: nil, problem: "the size declares \(expected) entries and the table holds \(samples.count)")
        }
        guard all(domainMax .> domainMin) else {
            throw ReadError(line: nil, problem: "DOMAIN_MAX must be above DOMAIN_MIN on every channel")
        }
        self.init(title: title, form: form, size: size, domainMin: domainMin, domainMax: domainMax,
                  samples: samples)
    }

    // MARK: Building one in code

    /// A cube built from a function of color: every node of a `size`-sided
    /// lattice over red, green, and blue holds what `transform` returns for
    /// it. Build one in `setup()`, and `write(to:)` hands it to any other
    /// tool as a `.cube` file.
    ///
    /// ```swift
    /// let cooler = ColorLUT(size: 17, title: "Cooler") { c in
    ///     Color(red: c.red * 0.92, green: c.green, blue: min(1, c.blue * 1.08))
    /// }
    /// ```
    public init(size: Int = 33, title: String = "", _ transform: (Color) -> Color) {
        let n = max(2, min(size, 256))
        var samples: [SIMD4<Float>] = []
        samples.reserveCapacity(n * n * n)
        let step = 1 / Double(n - 1)
        for b in 0 ..< n {
            for g in 0 ..< n {
                for r in 0 ..< n {
                    let out = transform(Color(red: Double(r) * step, green: Double(g) * step,
                                              blue: Double(b) * step))
                    samples.append(SIMD4(Float(out.red), Float(out.green), Float(out.blue), 1))
                }
            }
        }
        self.init(title: title, form: .cube, size: n, domainMin: SIMD3(0, 0, 0), domainMax: SIMD3(1, 1, 1),
                  samples: samples)
    }

    /// A cube that changes nothing: every node holds its own position. The
    /// control for a comparison, and the starting point for a look written by
    /// hand.
    public static func identity(size: Int = 17) -> ColorLUT {
        ColorLUT(size: size, title: "Identity") { $0 }
    }

    /// The bundled look, a warm print: blacks lifted a little, a gentle S
    /// through the midtones, the highlights warmed toward amber and the
    /// shadows cooled toward slate, and the whites held just short of paper.
    /// Written by Ollin from those four rules (`Resources/Looks/WarmPrint.cube`
    /// carries them in its header), so it is a look to try the filter on and a
    /// file to read as a template for one of your own.
    public static let warmPrint: ColorLUT = {
        if let url = Bundle.module.url(forResource: "WarmPrint", withExtension: "cube", subdirectory: "Looks"),
           let look = try? ColorLUT(contentsOf: url.path) {
            return look
        }
        FileHandle.standardError.write(Data("Ollin: the bundled WarmPrint look could not be read; using an identity table\n".utf8))
        return .identity(size: 2)
    }()

    // MARK: Reading a color

    /// The table's answer for one color, read the way the GPU filter reads it:
    /// `input`'s red, green, and blue (the values a display shows) are scaled
    /// into the table's domain and clamped to it, a cube is read by
    /// tetrahedral interpolation and curves linearly, and the answer comes
    /// back with `input`'s alpha. A table value below black reads as black.
    public func color(for input: Color) -> Color {
        let lo = SIMD3<Double>(domainMin), hi = SIMD3<Double>(domainMax)
        var t = (SIMD3(input.red, input.green, input.blue) - lo) / (hi - lo)
        t = simd_clamp(t, SIMD3(repeating: 0), SIMD3(repeating: 1))
        let p = t * Double(size - 1)
        let base = simd_min(p.rounded(.down), SIMD3(repeating: Double(size - 2)))
        let f = p - base
        let i0 = SIMD3<Int>(Int(base.x), Int(base.y), Int(base.z))
        let mapped: SIMD3<Double>
        switch form {
        case .curves:
            func at(_ i: Int) -> SIMD3<Double> {
                SIMD3<Double>(Double(samples[i].x), Double(samples[i].y), Double(samples[i].z))
            }
            mapped = SIMD3(at(i0.x).x + (at(i0.x + 1).x - at(i0.x).x) * f.x,
                           at(i0.y).y + (at(i0.y + 1).y - at(i0.y).y) * f.y,
                           at(i0.z).z + (at(i0.z + 1).z - at(i0.z).z) * f.z)
        case .cube:
            mapped = tetrahedral(i0, f)
        }
        let out = simd_max(mapped, SIMD3(repeating: 0))
        return Color(red: out.x, green: out.y, blue: out.z, alpha: input.alpha)
    }

    /// The cube read at cell `i0` and fraction `f` through the four corners of
    /// the tetrahedron that holds the point. The cell is cut into six
    /// tetrahedra along its gray diagonal, and the order of the three
    /// fractions says which one; every tetrahedron has the cell's black and
    /// white corners, so a point on the diagonal reads through those two
    /// alone, which is what keeps a gray input gray between the nodes.
    private func tetrahedral(_ i0: SIMD3<Int>, _ f: SIMD3<Double>) -> SIMD3<Double> {
        func node(_ r: Int, _ g: Int, _ b: Int) -> SIMD3<Double> {
            let s = samples[r + size * (g + size * b)]
            return SIMD3<Double>(Double(s.x), Double(s.y), Double(s.z))
        }
        let r0 = i0.x, g0 = i0.y, b0 = i0.z
        let r1 = r0 + 1, g1 = g0 + 1, b1 = b0 + 1
        let c000 = node(r0, g0, b0), c111 = node(r1, g1, b1)
        if f.x > f.y {
            if f.y > f.z {          // r > g > b
                return (1 - f.x) * c000 + (f.x - f.y) * node(r1, g0, b0) + (f.y - f.z) * node(r1, g1, b0) + f.z * c111
            } else if f.x > f.z {   // r > b > g
                return (1 - f.x) * c000 + (f.x - f.z) * node(r1, g0, b0) + (f.z - f.y) * node(r1, g0, b1) + f.y * c111
            } else {                // b > r > g
                return (1 - f.z) * c000 + (f.z - f.x) * node(r0, g0, b1) + (f.x - f.y) * node(r1, g0, b1) + f.y * c111
            }
        } else {
            if f.z > f.y {          // b > g > r
                return (1 - f.z) * c000 + (f.z - f.y) * node(r0, g0, b1) + (f.y - f.x) * node(r0, g1, b1) + f.x * c111
            } else if f.z > f.x {   // g > b > r
                return (1 - f.y) * c000 + (f.y - f.z) * node(r0, g1, b0) + (f.z - f.x) * node(r0, g1, b1) + f.x * c111
            } else {                // g > r > b
                return (1 - f.y) * c000 + (f.y - f.x) * node(r0, g1, b0) + (f.x - f.z) * node(r1, g1, b0) + f.z * c111
            }
        }
    }

    // MARK: Writing a file

    /// The table as the text of a `.cube` file, the form every grading tool
    /// reads: the title, the size, the domain, and one entry per line.
    public var cubeText: String {
        var out = "# Written by Ollin\n"
        if !title.isEmpty {
            out += "TITLE \"\(title.replacingOccurrences(of: "\"", with: "'"))\"\n"
        }
        out += form == .curves ? "LUT_1D_SIZE \(size)\n" : "LUT_3D_SIZE \(size)\n"
        out += "DOMAIN_MIN \(number(domainMin.x)) \(number(domainMin.y)) \(number(domainMin.z))\n"
        out += "DOMAIN_MAX \(number(domainMax.x)) \(number(domainMax.y)) \(number(domainMax.z))\n\n"
        out.reserveCapacity(out.count + samples.count * 27)
        for s in samples {
            out += "\(number(s.x)) \(number(s.y)) \(number(s.z))\n"
        }
        return out
    }

    /// Write the table to `path` as a `.cube` file.
    public func write(to path: String) throws {
        try cubeText.write(toFile: path, atomically: true, encoding: .utf8)
    }

    private func number(_ v: Float) -> String {
        String(format: "%.6f", v)
    }

    // MARK: What the renderer reads

    /// The scale and offset that carry an encoded value into the table's
    /// domain, as two parameter rows: `value * scale + offset`.
    var domainScale: SIMD4<Float> {
        let s = 1 / (domainMax - domainMin)
        return SIMD4(s.x, s.y, s.z, 0)
    }

    var domainOffset: SIMD4<Float> {
        let s = 1 / (domainMax - domainMin)
        let o = -domainMin * s
        return SIMD4(o.x, o.y, o.z, 0)
    }

    private static func digest(_ samples: [SIMD4<Float>], size: Int, form: Form) -> UInt64 {
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        func feed(_ byte: UInt8) {
            hash ^= UInt64(byte)
            hash = hash &* 0x0000_0100_0000_01b3
        }
        feed(form == .cube ? 3 : 1)
        for shift in stride(from: 0, to: 64, by: 8) { feed(UInt8(truncatingIfNeeded: size >> shift)) }
        samples.withUnsafeBytes { bytes in
            for byte in bytes { feed(byte) }
        }
        return hash
    }
}
