import Foundation

/// How a palette file is laid out. `.auto` reads the bytes and decides, which
/// is right almost always; name a format when a file is unusual enough that
/// the guess goes wrong.
public enum PaletteFormat: Sendable {
    /// Sniff the format from the file's contents.
    case auto
    /// One color per line; the whole file is a single palette.
    case hexLines
    /// One palette per line, colors separated by commas.
    case csv
    /// One palette per line, colors separated by tabs.
    case tsv
    /// A JSON array of hex strings (one palette), or an array of those arrays
    /// (many). An array of `{"colors": [...]}` objects reads too.
    case json
    /// Adobe Swatch Exchange. Each swatch group becomes a palette.
    case ase
}

// MARK: - Loading

public extension Palette {
    /// The first palette in a file, or `nil` if it holds none.
    ///
    /// ```swift
    /// let p = Palette(contentsOf: "sunset.hex")
    /// ```
    init?(contentsOf path: String, format: PaletteFormat = .auto) {
        self.init(url: URL(fileURLWithPath: path), format: format)
    }

    /// The first palette at `url`, or `nil` if it holds none.
    init?(url: URL, format: PaletteFormat = .auto) {
        guard let data = try? Data(contentsOf: url) else { return nil }
        self.init(data: data, format: format)
    }

    /// The first palette in `data`, or `nil` if it holds none.
    init?(data: Data, format: PaletteFormat = .auto) {
        guard let first = Palette.palettes(data: data, format: format).first else { return nil }
        self = first
    }

    /// The first palette in a bundled resource.
    ///
    /// `in:` has no default on purpose: a default would resolve to Ollin's own
    /// bundle rather than the caller's. Pass `.module` from your sketch.
    init?(resource: String, withExtension ext: String? = nil, in bundle: Bundle) {
        guard let url = bundle.url(forResource: resource, withExtension: ext) else { return nil }
        self.init(url: url, format: .auto)
    }

    /// Every palette in a file, in the order the file lists them.
    ///
    /// A file that holds one palette reads as a single-element array, so this
    /// is the form to reach for when you don't know which you have.
    ///
    /// ```swift
    /// let sets = Palette.palettes(contentsOf: "1000.json")
    /// fill(sets[variation % sets.count][0])
    /// ```
    static func palettes(contentsOf path: String, format: PaletteFormat = .auto) -> [Palette] {
        palettes(url: URL(fileURLWithPath: path), format: format)
    }

    /// Every palette at `url`, in file order.
    static func palettes(url: URL, format: PaletteFormat = .auto) -> [Palette] {
        guard let data = try? Data(contentsOf: url) else { return [] }
        return palettes(data: data, format: format)
    }

    /// Every palette in a bundled resource, in file order.
    static func palettes(resource: String, withExtension ext: String? = nil,
                         in bundle: Bundle) -> [Palette] {
        guard let url = bundle.url(forResource: resource, withExtension: ext) else { return [] }
        return palettes(url: url, format: .auto)
    }

    /// Every palette in `data`, in file order. Unreadable bytes yield `[]`
    /// rather than trapping, so a file from the network fails quietly.
    static func palettes(data: Data, format: PaletteFormat = .auto) -> [Palette] {
        switch format {
        case .auto:
            // Swatch Exchange announces itself and JSON opens with a bracket.
            // Everything else is text, and passing no palette-per-line answer
            // leaves that decision to the file's own shape.
            if data.count >= 4, data.prefix(4).elementsEqual("ASEF".utf8) { return parseASE(data) }
            if looksLikeJSON(data) { return parseJSON(data) }
            return parseText(data, separator: nil, palettePerLine: nil)
        case .ase:      return parseASE(data)
        case .json:     return parseJSON(data)
        case .hexLines: return parseText(data, separator: nil, palettePerLine: false)
        case .csv:      return parseText(data, separator: ",", palettePerLine: true)
        case .tsv:      return parseText(data, separator: "\t", palettePerLine: true)
        }
    }

    private static func looksLikeJSON(_ data: Data) -> Bool {
        for byte in data.prefix(64) {
            if byte == UInt8(ascii: "[") || byte == UInt8(ascii: "{") { return true }
            // Skip leading whitespace; the first real character decides.
            if byte != 0x20, byte != 0x09, byte != 0x0A, byte != 0x0D { return false }
        }
        return false
    }
}

// MARK: - Text (hex-per-line, CSV, TSV)

private extension Palette {
    /// One text parser serves three formats, because they differ only in what
    /// separates the colors on a line.
    ///
    /// When `separator` is nil each line splits on commas, tabs, semicolons,
    /// and runs of spaces alike. A nil `palettePerLine` lets the file decide:
    /// if every line yields exactly one color the whole file is one palette,
    /// otherwise each line is its own. A line that parses to no colors at all
    /// is skipped, which is how a CSV header or a line of stray text falls
    /// away without a comment syntax to define.
    static func parseText(_ data: Data, separator: Character?, palettePerLine: Bool?) -> [Palette] {
        guard let text = String(data: data, encoding: .utf8)
                ?? String(data: data, encoding: .isoLatin1) else { return [] }

        var rows: [[Color]] = []
        for line in text.split(whereSeparator: \.isNewline) {
            let fields: [Substring]
            if let separator {
                fields = line.split(separator: separator, omittingEmptySubsequences: true)
            } else {
                fields = line.split(whereSeparator: { $0 == "," || $0 == ";" || $0.isWhitespace })
            }
            let colors = fields.compactMap { color(fromToken: $0) }
            if !colors.isEmpty { rows.append(colors) }
        }
        guard !rows.isEmpty else { return [] }

        // A file of single-color lines is one palette, not a stack of one-color
        // palettes; anything wider is a palette per line.
        let perLine = palettePerLine ?? rows.contains { $0.count > 1 }
        return perLine ? rows.map(Palette.init) : [Palette(rows.flatMap { $0 })]
    }

    /// Strip the punctuation a hex color picks up in the wild (quotes from a
    /// CSV cell, a `0x` prefix, stray whitespace) and hand the rest to `Color`.
    static func color(fromToken token: Substring) -> Color? {
        var t = token.trimmingCharacters(in: .whitespaces)
        t = t.trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
        if t.hasPrefix("0x") || t.hasPrefix("0X") { t = String(t.dropFirst(2)) }
        guard !t.isEmpty else { return nil }
        return Color(hex: t)
    }
}

// MARK: - JSON

private extension Palette {
    /// Three shapes, because palette JSON in the wild is one of three things:
    /// an array of hex strings, an array of those arrays, or an array of
    /// objects each carrying a `colors` array.
    static func parseJSON(_ data: Data) -> [Palette] {
        guard let object = try? JSONSerialization.jsonObject(with: data) else { return [] }

        func palette(from any: Any) -> Palette? {
            guard let strings = any as? [String] else { return nil }
            let colors = strings.compactMap { color(fromToken: Substring($0)) }
            return colors.isEmpty ? nil : Palette(colors)
        }

        if let rows = object as? [Any] {
            // An array of hex strings is a single palette.
            if let single = palette(from: rows) { return [single] }
            let many = rows.compactMap { row -> Palette? in
                if let p = palette(from: row) { return p }
                if let dict = row as? [String: Any], let colors = dict["colors"] {
                    return palette(from: colors)
                }
                return nil
            }
            return many
        }
        if let dict = object as? [String: Any], let colors = dict["colors"],
           let single = palette(from: colors) {
            return [single]
        }
        return []
    }
}

// MARK: - Adobe Swatch Exchange

private extension Palette {
    /// Written from the published description of the format: a `ASEF` magic,
    /// a version pair, a block count, then that many length-prefixed blocks.
    /// A block opens a group, closes one, or carries a color.
    ///
    /// Groups map onto palettes. Colors outside any group collect into a
    /// palette of their own, flushed where they appear so the result keeps
    /// the file's order.
    static func parseASE(_ data: Data) -> [Palette] {
        var reader = ByteReader(data)
        guard let magic = reader.ascii(4), magic == "ASEF",
              reader.u16() != nil, reader.u16() != nil,
              let blockCount = reader.u32() else { return [] }

        var palettes: [Palette] = []
        var loose: [Color] = []
        var group: [Color]?

        for _ in 0..<blockCount {
            guard let type = reader.u16(), let length = reader.u32() else { break }
            let blockEnd = reader.offset + Int(length)

            switch type {
            case 0xC001:  // group start
                if !loose.isEmpty { palettes.append(Palette(loose)); loose = [] }
                _ = reader.name()
                group = []
            case 0xC002:  // group end
                if let g = group, !g.isEmpty { palettes.append(Palette(g)) }
                group = nil
            case 0x0001:  // color entry
                _ = reader.name()
                if let color = reader.color() {
                    if group != nil { group?.append(color) } else { loose.append(color) }
                }
            default:
                break  // Unknown block: its length tells us how far to skip.
            }
            // The block length is authoritative, so a block we half-read (or
            // skipped entirely) can't desynchronize the ones after it.
            guard blockEnd <= data.count, blockEnd >= reader.offset else { break }
            reader.offset = blockEnd
        }

        if let g = group, !g.isEmpty { palettes.append(Palette(g)) }
        if !loose.isEmpty { palettes.append(Palette(loose)) }
        return palettes
    }
}

/// A cursor over big-endian bytes. Every read is bounds-checked and returns
/// nil past the end, so a truncated file stops the parse instead of trapping.
private struct ByteReader {
    private let bytes: [UInt8]
    var offset = 0

    init(_ data: Data) { bytes = [UInt8](data) }

    mutating func u16() -> UInt16? {
        guard offset + 2 <= bytes.count else { return nil }
        defer { offset += 2 }
        return UInt16(bytes[offset]) << 8 | UInt16(bytes[offset + 1])
    }

    mutating func u32() -> UInt32? {
        guard offset + 4 <= bytes.count else { return nil }
        defer { offset += 4 }
        return (0..<4).reduce(UInt32(0)) { $0 << 8 | UInt32(bytes[offset + $1]) }
    }

    mutating func f32() -> Float? {
        guard let bits = u32() else { return nil }
        return Float(bitPattern: bits)
    }

    mutating func ascii(_ count: Int) -> String? {
        guard offset + count <= bytes.count else { return nil }
        defer { offset += count }
        return String(decoding: bytes[offset..<offset + count], as: UTF8.self)
    }

    /// A UTF-16 big-endian string, prefixed by its length in code units and
    /// terminated by a null unit the count includes.
    mutating func name() -> String? {
        guard let units = u16() else { return nil }
        let byteCount = Int(units) * 2
        guard offset + byteCount <= bytes.count else { return nil }
        defer { offset += byteCount }
        var scalars: [UInt16] = []
        for i in stride(from: offset, to: offset + byteCount, by: 2) {
            let unit = UInt16(bytes[i]) << 8 | UInt16(bytes[i + 1])
            if unit == 0 { break }
            scalars.append(unit)
        }
        return String(decoding: scalars, as: UTF16.self)
    }

    /// A four-character model tag, its floats, and the swatch's color type.
    mutating func color() -> Color? {
        guard let model = ascii(4) else { return nil }
        var color: Color?
        switch model.trimmingCharacters(in: .whitespaces).uppercased() {
        case "RGB":
            if let r = f32(), let g = f32(), let b = f32() {
                color = Color(red: clamped(r), green: clamped(g), blue: clamped(b))
            }
        case "GRAY":
            if let v = f32() {
                let g = clamped(v)
                color = Color(red: g, green: g, blue: g)
            }
        case "CMYK":
            if let c = f32(), let m = f32(), let y = f32(), let k = f32() {
                color = Color(red: clamped((1 - c) * (1 - k)),
                              green: clamped((1 - m) * (1 - k)),
                              blue: clamped((1 - y) * (1 - k)))
            }
        case "LAB":
            // Lightness arrives as 0...1 here, not the 0...100 of CIELAB proper.
            if let l = f32(), let a = f32(), let b = f32() {
                color = colorFromCIELAB(lightness: Double(l) * 100, a: Double(a), b: Double(b))
            }
        default:
            return nil
        }
        _ = u16()  // color type: global, spot, or normal
        return color
    }

    private func clamped(_ v: Float) -> Double { min(max(Double(v), 0), 1) }
}

/// CIELAB to sRGB through XYZ, on the D50 white point swatch files are written
/// against. The matrix folds the D50-to-D65 adaptation into the XYZ-to-linear
/// step, so it's one multiply rather than two.
private func colorFromCIELAB(lightness l: Double, a: Double, b: Double) -> Color {
    let fy = (l + 16) / 116
    let fx = fy + a / 500
    let fz = fy - b / 200

    let epsilon = 216.0 / 24389
    let kappa = 24389.0 / 27
    func inverse(_ t: Double) -> Double {
        let cubed = t * t * t
        return cubed > epsilon ? cubed : (116 * t - 16) / kappa
    }

    // D50 reference white.
    let x = 0.9642956764 * inverse(fx)
    let y = 1.0 * inverse(fy)
    let z = 0.8251046025 * inverse(fz)

    let r =  3.1338561 * x - 1.6168667 * y - 0.4906146 * z
    let g = -0.9787684 * x + 1.9161415 * y + 0.0334540 * z
    let bl = 0.0719453 * x - 0.2289914 * y + 1.4052427 * z

    func encode(_ c: Double) -> Double { min(max(Color.linearToSrgb(min(max(c, 0), 1)), 0), 1) }
    return Color(red: encode(r), green: encode(g), blue: encode(bl))
}

// MARK: - Sketch sugar

public extension Sketch {
    /// The first palette in a file: `loadPalette("sunset.hex")`.
    func loadPalette(_ path: String, format: PaletteFormat = .auto) -> Palette? {
        Palette(contentsOf: path, format: format)
    }

    /// The first palette at a URL.
    func loadPalette(_ url: URL, format: PaletteFormat = .auto) -> Palette? {
        Palette(url: url, format: format)
    }

    /// Every palette in a file, in file order: `loadPalettes("100.json")`.
    func loadPalettes(_ path: String, format: PaletteFormat = .auto) -> [Palette] {
        Palette.palettes(contentsOf: path, format: format)
    }

    /// Every palette at a URL, in file order.
    func loadPalettes(_ url: URL, format: PaletteFormat = .auto) -> [Palette] {
        Palette.palettes(url: url, format: format)
    }

    /// The first palette in a bundled resource. Pass `.module` for the
    /// sketch's own bundle; a default here would resolve to Ollin's.
    func loadPalette(resource: String, withExtension ext: String? = nil,
                     in bundle: Bundle) -> Palette? {
        Palette(resource: resource, withExtension: ext, in: bundle)
    }

    /// Every palette in a bundled resource, in file order.
    func loadPalettes(resource: String, withExtension ext: String? = nil,
                      in bundle: Bundle) -> [Palette] {
        Palette.palettes(resource: resource, withExtension: ext, in: bundle)
    }
}
