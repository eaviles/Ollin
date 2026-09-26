import Foundation
@testable import Ollin
import Testing

/// A look from a `.cube` file: the reader and what it refuses (with the line),
/// the table read on the CPU (tetrahedral for a cube, linear for curves), the
/// writer's round trip, the bundled look, and the GPU filter against the CPU
/// read. Everything but the last runs without Metal.
@Suite
struct ColorLUTTests {

    /// A small seeded generator of its own, so the probes here never move.
    private struct Coin {
        var state: UInt64
        init(seed: UInt64) { state = seed &* 0x9E37_79B9_7F4A_7C15 | 1 }
        mutating func next() -> Double {
            state ^= state << 13; state ^= state >> 7; state ^= state << 17
            return Double(state >> 11) / Double(1 << 53)
        }
    }

    /// A two-node cube written by hand: the eight corners, red fastest.
    static let tinyCube = """
    TITLE "Tiny"
    LUT_3D_SIZE 2
    0 0 0
    1 0 0
    0 1 0
    1 1 0
    0 0 1
    1 0 1
    0 1 1
    1 1 1
    """

    /// Three curves of three nodes: red bends up, green is straight, blue is
    /// turned over.
    static let curves = """
    LUT_1D_SIZE 3
    0.0 0.0 1.0
    0.7 0.5 0.5
    1.0 1.0 0.0
    """

    // MARK: Reading

    @Test func readsACubeInTheFilesOwnOrder() throws {
        let lut = try ColorLUT(text: Self.tinyCube)
        #expect(lut.title == "Tiny")
        #expect(lut.form == .cube)
        #expect(lut.size == 2)
        #expect(lut.samples.count == 8)
        // The second entry is one step of red, not one of blue.
        #expect(lut.samples[1] == SIMD4(1, 0, 0, 1))
        #expect(lut.samples[4] == SIMD4(0, 0, 1, 1))
        #expect(lut.domainMin == SIMD3(0, 0, 0))
        #expect(lut.domainMax == SIMD3(1, 1, 1))
    }

    @Test func readsCurvesCommentsBlankLinesTabsAndWindowsLineEnds() throws {
        let text = "# a comment\r\n\r\nTITLE \"Bent\"\r\nlut_1d_size 3\r\n0.0\t0.0\t1.0\r\n  0.7 0.5 0.5  \r\n1 1 0\r\n"
        let lut = try ColorLUT(text: text)
        #expect(lut.form == .curves)
        #expect(lut.size == 3)
        #expect(lut.title == "Bent")
        #expect(lut.samples.count == 3)
        #expect(lut.samples[1] == SIMD4(0.7, 0.5, 0.5, 1))
    }

    @Test func readsTheDomainInBothSpellings() throws {
        let adobe = try ColorLUT(text: "LUT_3D_SIZE 2\nDOMAIN_MIN 0.1 0.2 0.3\nDOMAIN_MAX 0.9 0.8 0.7\n"
                                 + Self.tinyCube.split(separator: "\n").dropFirst(2).joined(separator: "\n"))
        #expect(adobe.domainMin == SIMD3(0.1, 0.2, 0.3))
        #expect(adobe.domainMax == SIMD3(0.9, 0.8, 0.7))
        let resolve = try ColorLUT(text: "LUT_3D_INPUT_RANGE 0.25 0.75\nLUT_3D_SIZE 2\n"
                                   + Self.tinyCube.split(separator: "\n").dropFirst(2).joined(separator: "\n"))
        #expect(resolve.domainMin == SIMD3(repeating: 0.25))
        #expect(resolve.domainMax == SIMD3(repeating: 0.75))
    }

    @Test func refusesWithTheLineThatStoppedIt() {
        func refusal(_ text: String) -> ColorLUT.ReadError? {
            do { _ = try ColorLUT(text: text); return nil } catch { return error as? ColorLUT.ReadError }
        }
        // An unknown keyword, on its line.
        let unknown = refusal("TITLE \"x\"\nLUT_3D_SIZE 2\nCOLOR_SPACE rec709\n")
        #expect(unknown?.line == 3)
        #expect(unknown?.problem.contains("COLOR_SPACE") == true)
        // An entry before the size.
        let early = refusal("# look\n0 0 0\nLUT_3D_SIZE 2\n")
        #expect(early?.line == 2)
        // A second size.
        let twice = refusal("LUT_1D_SIZE 2\nLUT_3D_SIZE 2\n")
        #expect(twice?.line == 2)
        #expect(twice?.problem.contains("second") == true)
        // An entry that is not three numbers, and one with a word in it.
        let four = refusal("LUT_3D_SIZE 2\n0 0 0 0\n")
        #expect(four?.line == 2)
        let word = refusal("LUT_3D_SIZE 2\n0 0 0\n0.1 abc 0.3\n")
        #expect(word?.line == 3)
        #expect(word?.problem.contains("abc") == true)
        // A count that does not add up has no one line; both numbers are named.
        let short = refusal("LUT_3D_SIZE 2\n0 0 0\n1 0 0\n")
        #expect(short?.line == nil)
        #expect(short?.problem.contains("8") == true && short?.problem.contains("2") == true)
        // More entries than the size allows stops on the first extra one.
        let long = refusal(Self.tinyCube + "\n0.5 0.5 0.5\n")
        #expect(long?.line == 11)
        // No size at all, and sizes off the format's range.
        #expect(refusal("TITLE \"none\"\n")?.line == nil)
        #expect(refusal("LUT_3D_SIZE 1\n")?.line == 1)
        #expect(refusal("LUT_3D_SIZE 300\n")?.line == 1)
        #expect(refusal("LUT_1D_SIZE 20000\n")?.line == 1)
        #expect(refusal("LUT_3D_SIZE two\n")?.line == 1)
        // A domain that runs backwards.
        let backwards = refusal("DOMAIN_MIN 1 1 1\nDOMAIN_MAX 0 0 0\n"
                                + Self.tinyCube.split(separator: "\n").dropFirst(1).joined(separator: "\n"))
        #expect(backwards?.line == nil)
        #expect(backwards?.problem.contains("DOMAIN_MAX") == true)
        // The description carries the line for a reader.
        #expect("\(unknown!)".hasPrefix("line 3: "))
        // A missing file is refused rather than trapped on.
        #expect(throws: ColorLUT.ReadError.self) { try ColorLUT(contentsOf: "/nowhere/look.cube") }
    }

    // MARK: The read

    @Test func theCornersAreExact() {
        func look(_ c: Color) -> Color {
            Color(red: 0.1 + 0.8 * c.green * c.green, green: 0.9 - 0.7 * c.blue, blue: c.red * 0.5 + 0.2 * c.green)
        }
        let lut = ColorLUT(size: 3, title: "corners", look)
        for r in [0.0, 1.0] {
            for g in [0.0, 1.0] {
                for b in [0.0, 1.0] {
                    let input = Color(red: r, green: g, blue: b)
                    let expected = look(input), got = lut.color(for: input)
                    #expect(abs(got.red - expected.red) < 1e-6)
                    #expect(abs(got.green - expected.green) < 1e-6)
                    #expect(abs(got.blue - expected.blue) < 1e-6)
                }
            }
        }
    }

    /// The reason for the tetrahedral read: the cell is cut along its gray
    /// diagonal, so a gray input meets only the two gray corners, whatever the
    /// six colored corners around it hold. A trilinear read would pull them in.
    @Test func grayStaysGrayThroughWildOffDiagonalNodes() throws {
        var lines = ["LUT_3D_SIZE 3"]
        var rng = Coin(seed: 3)
        for b in 0 ..< 3 {
            for g in 0 ..< 3 {
                for r in 0 ..< 3 {
                    if r == g && g == b {
                        let v = Double(r) / 2
                        lines.append("\(v) \(v) \(v)")
                    } else {
                        lines.append("\(rng.next()) \(rng.next()) \(rng.next())")
                    }
                }
            }
        }
        let lut = try ColorLUT(text: lines.joined(separator: "\n"))
        for v in stride(from: 0.0, through: 1.0, by: 0.05) {
            let out = lut.color(for: Color(white: v))
            #expect(abs(out.red - v) < 1e-9)
            #expect(abs(out.green - v) < 1e-9)
            #expect(abs(out.blue - v) < 1e-9)
        }
    }

    /// Four corners with weights that sum to one reproduce any affine map
    /// exactly, everywhere in the cell, not only at the nodes. The identity
    /// (`ColorLUT.identity`, which returns what it is given) is the plainest such
    /// map and reads through the same table. Alpha rides through the read
    /// untouched.
    @Test func anAffineTableIsReproducedBetweenTheNodes() {
        func affine(_ c: Color) -> Color {
            Color(red: 0.2 + 0.5 * c.red - 0.1 * c.blue, green: 0.1 + 0.8 * c.green + 0.05 * c.red,
                  blue: 0.7 * c.blue + 0.1 * c.red + 0.1 * c.green)
        }
        let lut = ColorLUT(size: 5, affine)
        var rng = Coin(seed: 11)
        for _ in 0 ..< 200 {
            let c = Color(red: rng.next(), green: rng.next(), blue: rng.next(), alpha: 0.5)
            let expected = affine(c), got = lut.color(for: c)
            #expect(abs(got.red - expected.red) < 1e-6)
            #expect(abs(got.green - expected.green) < 1e-6)
            #expect(abs(got.blue - expected.blue) < 1e-6)
            #expect(got.alpha == 0.5)
        }
    }

    @Test func curvesBendEachChannelAlone() throws {
        let lut = try ColorLUT(text: Self.curves)
        // Halfway up the first segment of each curve, and the channels do not mix.
        let out = lut.color(for: Color(red: 0.25, green: 0.25, blue: 0.25))
        #expect(abs(out.red - 0.35) < 1e-6)
        #expect(abs(out.green - 0.25) < 1e-6)
        #expect(abs(out.blue - 0.75) < 1e-6)
        let mixed = lut.color(for: Color(red: 1, green: 0, blue: 0.5))
        #expect(abs(mixed.red - 1) < 1e-6 && abs(mixed.green - 0) < 1e-6 && abs(mixed.blue - 0.5) < 1e-6)
    }

    @Test func theDomainScalesTheInputAndClampsOutsideIt() throws {
        let text = "LUT_3D_INPUT_RANGE 0.25 0.75\n" + Self.tinyCube.split(separator: "\n").dropFirst(1).joined(separator: "\n")
        let lut = try ColorLUT(text: text)
        let low = lut.color(for: Color(white: 0.25)), high = lut.color(for: Color(white: 0.75))
        #expect(low.red == 0 && low.green == 0 && low.blue == 0)
        #expect(high.red == 1 && high.green == 1 && high.blue == 1)
        let mid = lut.color(for: Color(white: 0.5))
        #expect(abs(mid.red - 0.5) < 1e-9 && abs(mid.green - 0.5) < 1e-9 && abs(mid.blue - 0.5) < 1e-9)
        // Past the domain, the table's last node holds.
        let beyond = lut.color(for: Color(white: 0.9))
        #expect(beyond.red == 1 && beyond.blue == 1)
        #expect(lut.color(for: .black).red == 0)
    }

    @Test func aValueBelowBlackReadsAsBlack() throws {
        let lut = try ColorLUT(text: "LUT_1D_SIZE 2\n-0.5 0 0\n1 1 1\n")
        #expect(lut.color(for: .black).red == 0)
    }

    // MARK: Writing

    @Test func aWrittenTableReadsBackAsItself() throws {
        let look = ColorLUT(size: 5, title: "Round \"trip\"") { c in
            Color(red: c.red * 0.9, green: c.green, blue: min(1, c.blue * 1.1 + 0.02))
        }
        let path = ollinTempPath("look-\(UUID().uuidString).cube")
        defer { try? FileManager.default.removeItem(atPath: path) }
        try look.write(to: path)
        let back = try ColorLUT(contentsOf: path)
        #expect(back.title == "Round 'trip'")
        #expect(back.form == .cube && back.size == 5)
        // Six decimals hold a float to well under a level of eight bits, so
        // the read table agrees with the written one at every node.
        for (a, b) in zip(look.samples, back.samples) {
            #expect(abs(a.x - b.x) < 1e-6 && abs(a.y - b.y) < 1e-6 && abs(a.z - b.z) < 1e-6)
        }
        // The text is the format every tool reads: the keywords first, then
        // one entry per line.
        let text = look.cubeText
        #expect(text.contains("TITLE \"Round 'trip'\"\nLUT_3D_SIZE 5\nDOMAIN_MIN 0.000000 0.000000 0.000000\n"))
        #expect(text.split(separator: "\n").filter { !$0.hasPrefix("#") && $0.first?.isLetter == false }.count == 125)
    }

    @Test func twoReadsOfOneFileAreOneTable() throws {
        let a = try ColorLUT(text: Self.tinyCube), b = try ColorLUT(text: Self.tinyCube)
        #expect(a == b && a.fingerprint == b.fingerprint)
        // The two-node cube is the identity at that size, and no other.
        #expect(a == ColorLUT.identity(size: 2))
        #expect(a != ColorLUT.identity(size: 3))
        #expect(try ColorLUT(text: Self.curves) != a)
    }

    // MARK: The bundled look

    @Test func theBundledLookIsAWarmPrint() {
        let look = ColorLUT.warmPrint
        #expect(look.form == .cube)
        #expect(look.size == 17)
        #expect(look.title == "Warm Print")
        // Blacks lifted, whites held short of paper.
        let black = look.color(for: .black), white = look.color(for: .white)
        #expect(black.red > 0.02 && black.red < 0.06)
        #expect(white.green < 0.99 && white.green > 0.85)
        // Slate in the shadows, amber in the highlights.
        let shadow = look.color(for: Color(white: 0.15)), highlight = look.color(for: Color(white: 0.9))
        #expect(shadow.blue > shadow.red)
        #expect(highlight.red > highlight.blue)
        // The gray axis only ever climbs.
        var last = -1.0
        for v in stride(from: 0.0, through: 1.0, by: 0.02) {
            let c = look.color(for: Color(white: v))
            let luminance = 0.2126 * c.red + 0.7152 * c.green + 0.0722 * c.blue
            #expect(luminance > last)
            last = luminance
        }
    }

    // MARK: The GPU filter, rendered

    /// Eight flat patches, the colors of a cube's corners, through the filter.
    private final class PatchSketch: Sketch {
        var filter: Filter?
        static let patches: [Color] = [.black, .red, .green, Color(red: 1, green: 1, blue: 0),
                                       .blue, Color(red: 1, green: 0, blue: 1), Color(red: 0, green: 1, blue: 1), .white]
        override var canvasSize: CanvasSize { .square(64) }
        override func draw() {
            noStroke()
            background(.black)
            for (index, color) in Self.patches.enumerated() {
                fill(color)
                drawRect(Double(index % 4) * 16, Double(index / 4) * 32, 16, 32)
            }
            if let filter { postProcess(filter) }
        }
    }

    /// A picture with every kind of color in range: a sweep, a ramp, and a few
    /// disks, all opaque, nothing above white.
    private final class SceneSketch: Sketch {
        var filter: Filter?
        override var canvasSize: CanvasSize { .square(96) }
        override func draw() {
            noStroke()
            for x in 0 ..< 96 {
                fill(Color(hue: Double(x) / 96, saturation: 0.8, brightness: 0.9))
                drawRect(Double(x), 0, 1, 48)
                fill(Color(white: Double(x) / 95))
                drawRect(Double(x), 48, 1, 48)
            }
            fill(Color(red: 0.31, green: 0.62, blue: 0.17)); drawCircle(30, 48, 14)
            fill(Color(red: 0.05, green: 0.11, blue: 0.29)); drawCircle(66, 48, 14)
            if let filter { postProcess(filter) }
        }
    }

    @MainActor
    private func pixels(_ sketch: Sketch) throws -> [UInt8] {
        let rendered = Image(cgImage: try #require(OllinApp.image(of: sketch, frame: 0)))
        return try #require(rendered.premultipliedPixels())
    }

    @MainActor
    private func patchColors(_ sketch: PatchSketch) throws -> [Color] {
        let rendered = Image(cgImage: try #require(OllinApp.image(of: sketch, frame: 0)))
        return (0 ..< PatchSketch.patches.count).map { rendered[($0 % 4) * 16 + 8, ($0 / 4) * 32 + 16] }
    }

    @MainActor @Test(.enabled(if: Snapshot.hasMetal))
    func anIdentityTableChangesNoByte() throws {
        let plain = SceneSketch()
        let reference = try pixels(plain)
        let cube = SceneSketch()
        cube.filter = .lut(.identity(size: 17))
        #expect(try pixels(cube) == reference)
        let curves = SceneSketch()
        curves.filter = .lut(try ColorLUT(text: "LUT_1D_SIZE 2\n0 0 0\n1 1 1\n"))
        #expect(try pixels(curves) == reference)
        // And a look at amount zero is the picture untouched.
        let held = SceneSketch()
        held.filter = .lut(.warmPrint, amount: 0)
        #expect(try pixels(held) == reference)
        // The gate: the look itself does change the picture.
        let looked = SceneSketch()
        looked.filter = .lut(.warmPrint)
        #expect(try pixels(looked) != reference)
    }

    @MainActor @Test(.enabled(if: Snapshot.hasMetal))
    func theCornersLandWhereTheTableSays() throws {
        // A cube whose corners are turned: red to green, green to blue, blue
        // to red, black to a deep gray, white to cream.
        let lut = ColorLUT(size: 2, title: "turned") { c in
            Color(red: 0.95 * c.blue + 0.08 * (1 - c.red) * (1 - c.green) * (1 - c.blue),
                  green: 0.9 * c.red + 0.08 * (1 - c.red) * (1 - c.green) * (1 - c.blue),
                  blue: 0.85 * c.green + 0.1 * (1 - c.red) * (1 - c.green) * (1 - c.blue))
        }
        let sketch = PatchSketch()
        sketch.filter = .lut(lut)
        let rendered = try patchColors(sketch)
        for (index, input) in PatchSketch.patches.enumerated() {
            let expected = lut.color(for: input)
            // The present pass dithers, so one value straddles two levels.
            #expect(abs(rendered[index].red - expected.red) <= 2.0 / 255)
            #expect(abs(rendered[index].green - expected.green) <= 2.0 / 255)
            #expect(abs(rendered[index].blue - expected.blue) <= 2.0 / 255)
        }
    }

    @MainActor @Test(.enabled(if: Snapshot.hasMetal))
    func theFilterAgreesWithTheReadBetweenTheNodes() throws {
        // Off-node colors through the bundled look and through a set of
        // curves: the GPU's tetrahedral and linear reads against the CPU's.
        final class BandSketch: Sketch {
            var filter: Filter?
            static let bands: [Color] = [Color(red: 0.31, green: 0.62, blue: 0.17), Color(white: 0.43),
                                         Color(red: 0.05, green: 0.11, blue: 0.29), Color(red: 0.9, green: 0.55, blue: 0.2)]
            override var canvasSize: CanvasSize { .square(64) }
            override func draw() {
                noStroke()
                background(.white)
                for (index, color) in Self.bands.enumerated() {
                    fill(color)
                    drawRect(0, Double(index) * 16, 64, 16)
                }
                if let filter { postProcess(filter) }
            }
        }
        for table in [ColorLUT.warmPrint, try ColorLUT(text: Self.curves)] {
            let sketch = BandSketch()
            sketch.filter = .lut(table, amount: 0.7)
            let rendered = Image(cgImage: try #require(OllinApp.image(of: sketch, frame: 0)))
            for (index, source) in BandSketch.bands.enumerated() {
                let looked = table.color(for: source)
                let got = rendered[32, index * 16 + 8]
                // `amount` mixes in linear light, as the filter does.
                func mix(_ a: Double, _ b: Double) -> Double {
                    Color.linearToSrgb(Color.srgbToLinear(a) * 0.3 + Color.srgbToLinear(b) * 0.7)
                }
                #expect(abs(got.red - mix(source.red, looked.red)) < 0.02)
                #expect(abs(got.green - mix(source.green, looked.green)) < 0.02)
                #expect(abs(got.blue - mix(source.blue, looked.blue)) < 0.02)
            }
        }
    }
}
