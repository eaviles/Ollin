import Testing
import CoreGraphics
import Foundation
@testable import Ollin

/// The small public values the coverage read found unheld, each against an
/// analytic oracle: a variable font's axes, a single-stroke font read from its
/// file format, the `@Smoothed` and `@Sprung` wrappers as a sketch holds them,
/// `LSystem.isStochastic`, and the envelope and caustic drawn through the
/// sketch's own calls.
@Suite
@MainActor
struct SmallValueTests {

    // MARK: Variable fonts

    /// The first font on this machine that exposes variation axes.
    private func variableFont() throws -> OutlineFont {
        let candidates: [OutlineFont?] = [
            .system, OutlineFont(name: "Skia"), OutlineFont(name: "SF Pro"),
            OutlineFont(name: "Avenir Next Variable"),
        ]
        return try #require(candidates.compactMap { $0 }.first { !$0.variationAxes.isEmpty },
                            "no variable font on this machine")
    }

    private func width(_ font: OutlineFont, _ text: String = "Ollin") -> Double {
        let sketch = Sketch()
        sketch.textFont(font)
        sketch.textSize(120)
        return sketch.textWidth(text)
    }

    private func glyphs(_ font: OutlineFont) throws -> [UInt8] {
        pixels(of: try OllinApp.image(of: OneText(font), frame: 1))
    }

    @Test func eachAxisMovesTheOutlinesAndItsDefaultLeavesThem() throws {
        let font = try variableFont()
        let plain = try glyphs(font)
        for axis in font.variationAxes {
            let low = font.variation([axis.tag: axis.min])
            let high = font.variation([axis.tag: axis.max])
            #expect(try glyphs(low) != glyphs(high), "the \(axis.tag) axis moved nothing")
            // Pinning an axis at its default is the font as it stands, except
            // the optical size: left alone, the system picks it from the point
            // size, so naming the axis's own default is a different choice.
            if axis.tag != "opsz" {
                #expect(try glyphs(font.variation([axis.tag: axis.default])) == plain,
                        "the \(axis.tag) axis at its default changed the font")
            }
            switch axis.tag {
            case "wght": #expect(width(high) > width(low), "heavier is wider")
            case "wdth": #expect(width(high) > width(low), "wider is wider")
            default: break
            }
        }
    }

    @Test func theOneAxisSpellingsAreTheTagsTheyStandFor() throws {
        let font = try variableFont()
        for axis in font.variationAxes {
            let mid = (axis.min + axis.max) / 2
            let byTag = font.variation([axis.tag: mid])
            let short: OutlineFont?
            switch axis.tag {
            case "wght": short = font.weight(mid)
            case "wdth": short = font.width(mid)
            case "opsz": short = font.opticalSize(mid)
            case "slnt": short = font.slant(mid)
            default: short = nil
            }
            if let short {
                #expect(try glyphs(short) == glyphs(byTag), "\(axis.tag)")
            }
        }
    }

    @Test func anAxisTheFontLacksIsIgnored() throws {
        let font = try variableFont()
        let tags = Set(font.variationAxes.map(\.tag))
        let plain = try glyphs(font)
        if !tags.contains("slnt") { #expect(try glyphs(font.slant(-10)) == plain) }
        if !tags.contains("wdth") { #expect(try glyphs(font.width(150)) == plain) }
        #expect(try glyphs(font.variation([:])) == plain, "no axes at all is the font itself")
        // A font with no axes ignores every axis.
        let fixed = try #require(OutlineFont(name: "Helvetica"))
        #expect(fixed.variationAxes.isEmpty)
        #expect(try glyphs(fixed.weight(900)) == glyphs(fixed))
    }

    // MARK: Single-stroke fonts

    /// Two records in the Hershey file format: the space, whose only pair is its
    /// pen bounds, and a glyph of two strokes with a pen-up between them. Each
    /// coordinate is a character's distance from `R`.
    private static let twoGlyphs = "    1  1JZ\n    2  6JZRJRR RLRXR\n"

    @Test func theFileFormatReadsAsItsOwnDescriptionSays() throws {
        let font = try StrokeFont(jhf: Self.twoGlyphs)
        #expect(font.glyphs.count == 2)
        // The bounds pair J...Z is -8...8 about the pen, so each advance is 16.
        #expect(font.spaceAdvanceUnits == 16)
        let bang = try #require(font.glyph(for: "!"))
        #expect(bang.advance == 16)
        // Pen origin to x = 0 (so J, the left bound, is 0), baseline to y = 0
        // (so R, Hershey's +9 line, is -9).
        #expect(bang.polylines == [[Vector2(8, -17), Vector2(8, -9)], [Vector2(2, -9), Vector2(14, -9)]])
        #expect(font.advanceUnits(for: "!") == 16)
        #expect(font.advanceUnits(for: " ") == 16)
        #expect(font.advanceUnits(for: "?") == 0, "a glyph the font lacks advances nothing")
        // The layout metrics are Hershey's 28-unit em: caps 21 up, descenders 7 down.
        #expect(font.ascent == 21.0 / 28)
        #expect(font.descent == 7.0 / 28)
        #expect(font.leading == 8.0 / 28)
    }

    @Test func aStringsWidthIsItsAdvancesScaledToTheSize() throws {
        let font = try StrokeFont(jhf: Self.twoGlyphs)
        #expect(font.width(of: "!", size: 28) == 16)
        #expect(font.width(of: "!!", size: 56) == 64)
        #expect(font.width(of: "! !", size: 28) == 48)
        #expect(font.width(of: "!\n!!", size: 28) == 32, "a multi-line string is as wide as its widest line")
        #expect(font.width(of: "", size: 28) == 0)
        let empty = StrokeFont(glyphs: [:], unitsPerEm: 0, ascentUnits: 0, descentUnits: 0, lineGapUnits: 0)
        #expect(empty.width(of: "!", size: 28) == 0, "a font with no em has no width")
        #expect(empty.ascent == 0)
    }

    @Test func theBuiltInFontHoldsPrintableASCII() throws {
        let font = StrokeFont.builtIn
        #expect(font.glyphs.count >= 95)
        for scalar in 32 ... 126 {
            #expect(font.glyph(for: Character(UnicodeScalar(UInt8(scalar)))) != nil, "\(scalar)")
        }
        let h = try #require(font.glyph(for: "H"))
        #expect(font.width(of: "H", size: 28) == h.advance)
        #expect(!h.polylines.isEmpty)
    }

    @Test func aFileWithNoGlyphIsRefused() {
        #expect(throws: FileError.self) { try StrokeFont(jhf: "nothing here\n") }
        #expect(throws: FileError.self) { try StrokeFont(jhf: "") }
    }

    // MARK: @Smoothed and @Sprung

    /// A sketch whose wrappers are set to 100 in `setup()`, then told to go
    /// back to 0 on their second frame, writing down what each reads back.
    @MainActor
    private final class Follower: Sketch {
        @Smoothed var smooth = 0.0
        @Sprung(duration: 0.3) var sprung = 0.0
        nonisolated(unsafe) static var smoothRead: [Double] = []
        nonisolated(unsafe) static var sprungRead: [Double] = []
        nonisolated(unsafe) static var rawRead: [Double] = []
        override var canvasSize: CanvasSize { .square(8) }
        override func setup() throws {
            smooth = 100
            sprung = 100
        }
        override func draw() {
            Self.smoothRead.append(smooth)
            Self.sprungRead.append(sprung)
            Self.rawRead.append($smooth.rawValue)
            if Self.smoothRead.count == 2 {
                smooth = 0
                sprung = 0
            }
        }
    }

    @Test func aSketchAdvancesItsWrappersTowardTheirInputs() throws {
        Follower.smoothRead = []; Follower.sprungRead = []; Follower.rawRead = []
        _ = try OllinApp.image(of: Follower(), frame: 90)
        let smooth = Follower.smoothRead, sprung = Follower.sprungRead, raw = Follower.rawRead
        #expect(smooth.count == 91)
        #expect(raw[0] == 100 && raw[1] == 100 && raw[2] == 0, "the raw value is the input, at once")
        // The filter's first sample passes through, so the value set in
        // setup() is read back whole within the first two frames.
        #expect(smooth[1] == 100, "the first sample passes through untouched")
        // From the second frame's assignment on, both glide toward 0.
        #expect(smooth[3] > 0 && smooth[3] < 100, "a frame after the change it is on its way")
        #expect(zip(smooth.dropFirst(2), smooth.dropFirst(3)).allSatisfy { $0 >= $1 }, "it never turns back")
        #expect(smooth.allSatisfy { $0 >= 0 }, "it never overshoots")
        #expect(smooth[90] < 1, "a second and a half in it has arrived")
        #expect(sprung[1] > 0 && sprung[1] < 100, "a spring starts where it was declared and glides to what setup() set")
        #expect(sprung[5] > 0 && sprung[5] < 100)
        #expect(sprung[90] < 1)
        #expect(sprung.min()! > -1, "a spring with no bounce never overshoots by a whole unit")
    }

    @Test func theSmoothedWrapperFiltersItsInputByTime() {
        let value = Smoothed(wrappedValue: 0.0)
        value.wrappedValue = 10
        #expect(value.wrappedValue == 0, "nothing moves until a frame advances")
        #expect(value.rawValue == 10)
        value.advance(by: 1.0 / 60)
        #expect(value.wrappedValue == 10, "the filter's first sample passes through, as its page says")
        value.wrappedValue = 0
        var last = 10.0
        for _ in 0 ..< 60 {
            value.advance(by: 1.0 / 60)
            #expect(value.wrappedValue <= last && value.wrappedValue >= 0)
            last = value.wrappedValue
        }
        #expect(last < 0.5, "a second at the default cutoff is nearly there")
        value.jump(to: 3)
        #expect(value.wrappedValue == 3 && value.rawValue == 3, "a jump lands at once")
        value.advance(by: 1.0 / 60)
        #expect(value.wrappedValue == 3, "and stays")
        // A lower cutoff is a slower follow.
        let slow = Smoothed(wrappedValue: 0.0, minCutoff: 0.1)
        let quick = Smoothed(wrappedValue: 0.0, minCutoff: 5)
        for filter in [slow, quick] {
            filter.jump(to: 10)
            filter.wrappedValue = 0
            for _ in 0 ..< 10 { filter.advance(by: 1.0 / 60) }
        }
        #expect(slow.wrappedValue > quick.wrappedValue, "the slow one is still high")
        #expect(slow.minCutoff == 0.1 && quick.minCutoff == 5)
    }

    @Test func theSprungWrapperSettlesInItsDurationAndTakesAKick() {
        let value = Sprung(wrappedValue: 0.0, duration: 0.5)
        value.wrappedValue = 10
        #expect(value.target == 10 && value.wrappedValue == 0)
        for _ in 0 ..< 60 { value.advance(by: 1.0 / 60) }
        #expect(abs(value.wrappedValue - 10) < 0.5, "two durations in, within 5%")
        #expect(value.duration == 0.5 && value.bounce == 0)
        value.jump(to: 2)
        #expect(value.wrappedValue == 2 && value.target == 2 && value.velocity == 0)
        value.kick(30)
        #expect(value.velocity == 30)
        value.advance(by: 1.0 / 60)
        #expect(value.wrappedValue > 2, "a kick moves it off its rest")
        // A bouncy spring overshoots; a critically damped one does not.
        let bouncy = Sprung(wrappedValue: 0.0, duration: 0.3, bounce: 0.6)
        bouncy.wrappedValue = 10
        var peak = 0.0
        for _ in 0 ..< 60 { bouncy.advance(by: 1.0 / 60); peak = max(peak, bouncy.wrappedValue) }
        #expect(peak > 10.5)
    }

    // MARK: L-systems

    @Test func anLSystemIsStochasticWhenASymbolHasAChoice() {
        #expect(!LSystem(axiom: "F", rules: ["F": "F+F"], angle: 90).isStochastic)
        #expect(!LSystem(axiom: "F", choices: ["F": ["F+F"], "X": ["XX"]], angle: 90).isStochastic,
                "one production each is deterministic")
        #expect(LSystem(axiom: "F", choices: ["F": ["F+F", "F-F"]], angle: 90).isStochastic)
        #expect(!LSystem(axiom: "F", choices: ["F": []], angle: 90).isStochastic,
                "an empty choice list is dropped, not counted")
    }

    // MARK: Envelopes and caustics, drawn

    nonisolated static let rays: [Ray2] = (0 ..< 24).map {
        let a = Double($0) / 24 * .pi
        return Ray2(origin: Vector2(32 + cos(a) * 20, 32 + sin(a) * 20), direction: Vector2(-sin(a * 2), cos(a * 2)))
    }
    nonisolated static let mirror: [Vector2] = (0 ..< 180).map {
        Vector2(angle: Double($0) / 180 * .tau, length: 24) + Vector2(32, 32)
    }

    @Test func drawEnvelopeDrawsThePolylinesOfTheEnvelope() throws {
        let bare = pixels(of: try OllinApp.image(of: OneMark { $0.drawEnvelope(of: Self.rays) }, frame: 1))
        let twin = pixels(of: try OllinApp.image(of: OneMark {
            for run in envelope(of: Self.rays) { $0.drawPolyline(run.points) }
        }, frame: 1))
        let blank = pixels(of: try OllinApp.image(of: OneMark { _ in }, frame: 1))
        #expect(bare != blank)
        #expect(bare == twin)
    }

    @Test func drawCausticDrawsThePolylinesOfTheCaustic() throws {
        let bare = pixels(of: try OllinApp.image(of: OneMark {
            $0.drawCaustic(off: Self.mirror, from: .parallel(0.3), closed: true)
        }, frame: 1))
        let twin = pixels(of: try OllinApp.image(of: OneMark {
            for run in caustic(off: Self.mirror, from: .parallel(0.3), closed: true) { $0.drawPolyline(run.points) }
        }, frame: 1))
        let blank = pixels(of: try OllinApp.image(of: OneMark { _ in }, frame: 1))
        #expect(bare != blank)
        #expect(bare == twin)
    }
}

/// A 64-point canvas with one stroked mark on it.
@MainActor
private final class OneMark: Sketch {
    var paint: (Sketch) -> Void = { _ in }

    convenience init(_ paint: @escaping (Sketch) -> Void) {
        self.init()
        self.paint = paint
    }

    override var canvasSize: CanvasSize { .square(64) }

    override func draw() {
        background(.black)
        noFill()
        stroke(Color(red: 0.2, green: 0.6, blue: 1))
        strokeWeight(1.5)
        paint(self)
    }
}

/// A 96-point canvas with two letters set in one font, for telling one
/// variation of a font from another.
@MainActor
private final class OneText: Sketch {
    let font: OutlineFont

    init(_ font: OutlineFont) {
        self.font = font
        super.init()
    }

    required init() {
        self.font = .system
        super.init()
    }

    override var canvasSize: CanvasSize { .square(96) }

    override func draw() {
        background(.black)
        fill(.white)
        textFont(font)
        textSize(60)
        textAlign(.center, .center)
        drawText("Og", 48, 48)
    }
}
