import CoreGraphics
import Metal
import MetalKit
import Testing
@testable import Ollin

/// Parameter values carried into a run from the command line (`--param name=value`):
/// how a flag is read, how a value is read against its parameter's own kind, that it
/// wins over the sketch's own `setup()`, and that the export recipe then names
/// the value the frame was really drawn with. The render check needs a GPU, so
/// it is Metal-gated the way the snapshot suite is; the rest is CPU-only.
@Suite
@MainActor
struct ParamOverrideTests {

    enum Mood: String, CaseIterable, ParamOption { case calm, easeOut, deepBlue }

    /// One parameter of every kind the flag can set.
    final class ParamSketch: Sketch {
        override var canvasSize: CanvasSize { .square(64) }
        @Param(0...200) var radius = 120.0
        @Param(1...12) var rings = 5
        @Param var filled = true
        @Param var tint: Color = .purple
        @Param(x: 0...1080, y: 0...1080) var anchor = Vector2(540, 540)
        @Param(x: -10...10, y: -10...10, z: -10...10) var pull = Vector3(0, 0, 0)
        @Param(x: 0...1080, y: 0...1080, width: 0...1080, height: 0...1080)
        var plate = Rectangle(x: 0, y: 0, width: 100, height: 100)
        @Param(0...200) var margin = Insets(top: 10, right: 10, bottom: 10, left: 10)
        @Param(in: 0...1) var band = 0.2...0.8
        @Param var caption = "hello"
        @Param var mood: Mood = .calm
        @Param var palette = Palette([.red, .blue])
        @Param var ramp = Ramp([.black, .white], in: .oklab)

        override func draw() {
            background(.white)
            fill(tint)
            drawCircle(32, 32, radius)
        }
    }

    /// A sketch that sets its own parameter in `setup()`, to prove which one wins.
    final class Opinionated: Sketch {
        override var canvasSize: CanvasSize { .square(64) }
        @Param(0...200) var radius = 120.0
        override func setup() { radius = 77 }
        override func draw() { background(.white) }
    }

    /// Run `body` with `overrides` standing in for this run's command line.
    private func withOverrides(_ overrides: [ParamOverride], _ body: () -> Void) {
        let previous = OllinApp.paramOverrides
        OllinApp.paramOverrides = overrides
        defer { OllinApp.paramOverrides = previous }
        body()
    }

    private func read(_ args: [String]) -> [ParamOverride] {
        guard case .value(let found) = ParamOverride.parse(args) else { return [] }
        return found
    }

    // MARK: - Reading the flags

    @Test func theFlagRepeatsAndKeepsItsOrder() {
        let found = read(["sketch", "--param", "radius=40", "--seed", "7", "--param", "rings=3"])
        #expect(found == [ParamOverride(name: "radius", text: "40"),
                          ParamOverride(name: "rings", text: "3")])
    }

    @Test func onlyTheFirstEqualsSignSplitsTheValue() {
        let found = read(["--param", "caption=a=b"])
        #expect(found == [ParamOverride(name: "caption", text: "a=b")])
    }

    @Test func aFlagWithNoValueIsRefused() {
        guard case .problem(let message) = ParamOverride.parse(["--param", "radius"]) else {
            Issue.record("a bare name should not read as a value")
            return
        }
        #expect(message.contains("--param <name>=<value>"))
        // The sweep's own parameter name is the bare form somebody would try here,
        // so the message says where it went.
        #expect(!message.contains("--sweep-param"))
        guard case .problem(let swept) = ParamOverride.parse(
            ["--export-sweep", "sheet.png", "--param", "radius"]) else {
            Issue.record("a bare name should not read as a value")
            return
        }
        #expect(swept.contains("--sweep-param"))
    }

    // MARK: - Reading a value against its parameter

    @Test func everyKindReadsItsOwnValue() {
        let sketch = ParamSketch()
        let problems = ParamOverride.apply([
            ParamOverride(name: "radius", text: "40"),
            ParamOverride(name: "rings", text: "3"),
            ParamOverride(name: "filled", text: "no"),
            ParamOverride(name: "tint", text: "#FF0066"),
            ParamOverride(name: "anchor", text: "100,900"),
            ParamOverride(name: "pull", text: "1,-2,3"),
            ParamOverride(name: "plate", text: "10,20,30,40"),
            ParamOverride(name: "margin", text: "12"),
            ParamOverride(name: "band", text: "0.25...0.75"),
            ParamOverride(name: "caption", text: "a longer line"),
            ParamOverride(name: "mood", text: "deepBlue"),
            ParamOverride(name: "palette", text: "#000,#FFF,#F06"),
        ], to: sketch)
        #expect(problems.isEmpty)
        #expect(sketch.radius == 40)
        #expect(sketch.rings == 3)
        #expect(sketch.filled == false)
        #expect(sketch.tint == Color(hex: 0xFF0066))
        #expect(sketch.anchor == Vector2(100, 900))
        #expect(sketch.pull == Vector3(1, -2, 3))
        #expect(sketch.plate == Rectangle(x: 10, y: 20, width: 30, height: 40))
        #expect(sketch.margin.top == 12 && sketch.margin.left == 12)
        #expect(sketch.band == 0.25...0.75)
        #expect(sketch.caption == "a longer line")
        #expect(sketch.mood == .deepBlue)
        #expect(sketch.palette.colors == [Color(hex: 0x000000), Color(hex: 0xFFFFFF),
                                          Color(hex: 0xFF0066)])
    }

    @Test func aRangeReadsBothSpellingsAndEitherWayRound() {
        let sketch = ParamSketch()
        #expect(ParamOverride.apply([.init(name: "band", text: "0.1,0.9")], to: sketch).isEmpty)
        #expect(sketch.band == 0.1...0.9)
        #expect(ParamOverride.apply([.init(name: "band", text: "0.8...0.3")], to: sketch).isEmpty)
        #expect(sketch.band == 0.3...0.8)
    }

    @Test func aColorReadsHexOrPlainNumbers() {
        let sketch = ParamSketch()
        #expect(ParamOverride.apply([.init(name: "tint", text: "0,0.5,1")], to: sketch).isEmpty)
        #expect(sketch.tint.red == 0 && sketch.tint.green == 0.5 && sketch.tint.blue == 1)
        #expect(sketch.tint.alpha == 1)
        #expect(ParamOverride.apply([.init(name: "tint", text: "#0000FF80")], to: sketch).isEmpty)
        #expect(abs(sketch.tint.alpha - 128.0 / 255) < 0.001)
    }

    @Test func swatchesSpreadEvenlyUnlessTheyNameTheirPlace() {
        let sketch = ParamSketch()
        #expect(ParamOverride.apply([.init(name: "ramp", text: "#000,#FFF,#F06")],
                                    to: sketch).isEmpty)
        #expect(sketch.ramp.stops.map(\.position) == [0, 0.5, 1])
        #expect(ParamOverride.apply([.init(name: "ramp", text: "#000@0,#FFF@0.75")],
                                    to: sketch).isEmpty)
        #expect(sketch.ramp.stops.map(\.position) == [0, 0.75])
        // The parameter keeps the space it mixes in: only the colors moved.
        #expect(sketch.ramp.space == .oklab)
    }

    @Test func aValueOutsideTheRangeClampsTheWayTheRowDoes() {
        let sketch = ParamSketch()
        #expect(ParamOverride.apply([.init(name: "radius", text: "9999")], to: sketch).isEmpty)
        #expect(sketch.radius == 200)
    }

    @Test func aChoiceMatchesItsNameLoosely() {
        for spelling in ["easeOut", "ease-out", "Ease Out", "EASEOUT"] {
            let sketch = ParamSketch()
            #expect(ParamOverride.apply([.init(name: "mood", text: spelling)], to: sketch).isEmpty)
            #expect(sketch.mood == .easeOut, "\(spelling) should find the same choice")
        }
    }

    // MARK: - What it says when it cannot

    @Test func anUnknownParameterNamesWhatTheSketchHas() {
        let problems = ParamOverride.apply([.init(name: "radiuz", text: "40")], to: ParamSketch())
        #expect(problems.count == 1)
        #expect(problems[0].contains("no @Param named 'radiuz'"))
        #expect(problems[0].contains("radius"))
    }

    @Test func aValueTheKindCannotReadSaysWhatItWanted() {
        let sketch = ParamSketch()
        let problems = ParamOverride.apply([
            .init(name: "radius", text: "wide"),
            .init(name: "anchor", text: "100"),
            .init(name: "mood", text: "stormy"),
        ], to: sketch)
        #expect(problems.count == 3)
        #expect(problems[0].contains("expected a number"))
        #expect(problems[1].contains("expected two numbers"))
        #expect(problems[2].contains("Calm"))          // the choices it does have
        // Nothing landed halfway: a parameter it could not read keeps its value.
        #expect(sketch.radius == 120)
        #expect(sketch.anchor == Vector2(540, 540))
        #expect(sketch.mood == .calm)
    }

    @Test func aParameterNamedTwiceEndsOnTheLastValue() {
        let sketch = ParamSketch()
        #expect(ParamOverride.apply([.init(name: "radius", text: "40"),
                                     .init(name: "radius", text: "60")], to: sketch).isEmpty)
        #expect(sketch.radius == 60)
    }

    // MARK: - Where it lands

    @Test func theFlagWinsOverTheSketchsOwnSetup() {
        let sketch = Opinionated()
        withOverrides([.init(name: "radius", text: "40")]) {
            sketch.runSetup()
        }
        #expect(sketch.radius == 40)
        // And with no flag, the sketch's own line still stands.
        let plain = Opinionated()
        withOverrides([]) { plain.runSetup() }
        #expect(plain.radius == 77)
    }

    @Test func theRecipeNamesTheValueTheFrameWasDrawnWith() {
        let sketch = ParamSketch()
        withOverrides([.init(name: "radius", text: "40")]) {
            sketch.runSetup()
            let recipe = ExportMetadata.capture(from: sketch, frame: 0, fps: 60).recipe
            #expect(recipe.contains("\"radius\":40"))
        }
    }

    @Test func theFrameIsDrawnWithTheFlaggedValue() throws {
        try #require(MTLCreateSystemDefaultDevice() != nil)
        func ink(_ overrides: [ParamOverride]) -> Int {
            var covered = 0
            withOverrides(overrides) {
                guard let image = OllinApp.image(of: ParamSketch(), frame: 0, fps: 60) else { return }
                covered = inkedPixels(of: image)
            }
            return covered
        }
        let wide = ink([])
        let small = ink([.init(name: "radius", text: "20")])
        #expect(wide > 0 && small > 0)
        // A smaller radius covers less of the canvas, and by a lot: the flag
        // reached the frame rather than only the value.
        #expect(small < wide / 2)
    }

    @Test func aWindowTakesTheValueAtLaunchAndKeepsWhatIsTurnedAfter() throws {
        let device = try #require(MTLCreateSystemDefaultDevice())
        let view = MTKView(frame: CGRect(x: 0, y: 0, width: 64, height: 64), device: device)
        view.drawableSize = CGSize(width: 64, height: 64)
        view.isPaused = true
        view.enableSetNeedsDisplay = false
        let sketch = Opinionated()
        withOverrides([.init(name: "radius", text: "40")]) {
            let runner = SketchRunner(sketch: sketch, view: view, device: device)
            runner.draw(in: view)
            #expect(sketch.radius == 40, "the launch value must beat the sketch's own setup()")

            // A live reload is a fresh instance, and the flag is a launch
            // instruction rather than a standing one: the host carries the
            // turned value across the swap, so re-applying here would undo it.
            let edited = Opinionated()
            runner.reload(to: edited)
            runner.draw(in: view)
            #expect(edited.radius == 77, "a reload keeps what the run has since become")
        }
    }

    /// Pixels that are not the white background, counted off the rendered frame.
    private func inkedPixels(of image: CGImage) -> Int {
        let width = image.width, height = image.height
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(data: &bytes, width: width, height: height,
                                      bitsPerComponent: 8, bytesPerRow: width * 4, space: space,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
            return 0
        }
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        var count = 0
        for pixel in stride(from: 0, to: bytes.count, by: 4) where bytes[pixel + 2] < 200 {
            count += 1          // the fill is purple or pink, so its blue-vs-white gap reads
        }
        return count
    }
}
