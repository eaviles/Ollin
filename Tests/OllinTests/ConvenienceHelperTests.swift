import CoreGraphics
import Testing
@testable import Ollin

/// Laws for the small convenience helpers: the shaping additions (`wrap`, the
/// generic `clamp`, `unipolar`/`bipolar`), the sequence builders (`fractions`,
/// `angles`), the point helpers (`polar`, the angle units), the sketch
/// properties (`mouse`, `previousMouse`, `shortSide`), and the one-call sugar
/// (`drawText` styled, `withState(at:)`, `drawArrow`). The sugar is checked by
/// rendering: the one-call form must be byte-identical to the block it
/// replaces, which also proves it restores every piece of state it touches.
@Suite
@MainActor
struct ConvenienceHelperTests {

    // MARK: Shaping scalars

    @Test func wrapCarriesAValueAroundTheRange() {
        #expect(wrap(5, 0, 10) == 5)
        #expect(wrap(12, 0, 10) == 2)
        #expect(abs(wrap(-1, 0, 10) - 9) < 1e-12)
        #expect(abs(wrap(-11, 0, 10) - 9) < 1e-12, "any number of laps back")
        #expect(wrap(10, 0, 10) == 0, "the high edge is the far side of the low one")
        #expect(abs(wrap(7.5, 2, 4) - 3.5) < 1e-12, "offset ranges wrap in place")
    }

    @Test func wrapAgreesWithItselfAcrossWholeLaps() {
        for x in stride(from: -25.0, through: 25.0, by: 0.7) {
            let once = wrap(x, -3, 8)
            #expect(abs(wrap(x + 11 * 4, -3, 8) - once) < 1e-9)
            #expect(once >= -3 && once < 8)
        }
    }

    @Test func wrapDegenerateRangeReturnsTheFloor() {
        #expect(wrap(7, 2, 2) == 2)
        #expect(wrap(7, 10, 0) == 10)
    }

    @Test func clampWorksOnAnyComparable() {
        #expect(clamp(12, 0, 9) == 9)
        #expect(clamp(-3, 0, 9) == 0)
        #expect(clamp(4, 0, 9) == 4)
        #expect(clamp(1.5, to: 0.0...1.0) == 1.0)
        #expect(clamp(7, to: 0...9) == 7)
        #expect(clamp("m", "a", "f") == "f")
    }

    @Test func unipolarAndBipolarAreInverses() {
        #expect(unipolar(-1) == 0)
        #expect(unipolar(0) == 0.5)
        #expect(unipolar(1) == 1)
        #expect(bipolar(0) == -1)
        #expect(bipolar(0.5) == 0)
        #expect(bipolar(1) == 1)
        for x in stride(from: -1.0, through: 1.0, by: 0.25) {
            #expect(abs(bipolar(unipolar(x)) - x) < 1e-12)
        }
    }

    // MARK: Dividing a whole

    @Test func fractionsTileWithoutADoubledSeam() {
        #expect(fractions(4) == [0, 0.25, 0.5, 0.75])
        #expect(fractions(1) == [0])
        #expect(fractions(0).isEmpty)
        #expect(fractions(-2).isEmpty)
    }

    @Test func inclusiveFractionsRunThroughOne() {
        #expect(fractions(5, inclusive: true) == [0, 0.25, 0.5, 0.75, 1])
        #expect(fractions(2, inclusive: true) == [0, 1])
        #expect(fractions(1, inclusive: true) == [0])
    }

    @Test func anglesFanTheCircle() {
        let quarter = angles(4)
        #expect(quarter.count == 4)
        for (i, a) in quarter.enumerated() {
            #expect(abs(a - Double(i) * .tau / 4) < 1e-12)
        }
        let shifted = angles(3, from: 1.5)
        #expect(abs(shifted[0] - 1.5) < 1e-12)
        let fan = angles(2, turns: 0.5)
        #expect(abs(fan[1] - .tau / 4) < 1e-12, "half a turn split in two panels")
    }

    // MARK: Points and angle units

    @Test func polarMatchesTheSpelledOutForm() {
        let c = Vector2(37, -12)
        for a in stride(from: 0.0, through: 6.4, by: 0.4) {
            let direct = c + Vector2(cos(a), sin(a)) * 5.5
            let helper = polar(a, 5.5, around: c)
            #expect(abs(helper.x - direct.x) < 1e-12)
            #expect(abs(helper.y - direct.y) < 1e-12)
        }
        #expect(polar(0, 3) == Vector2(3, 0), "no center means the origin")
    }

    @Test func angleUnitsReadIntoRadians() {
        #expect(abs(Double.degrees(180) - .pi) < 1e-12)
        #expect(abs(Double.degrees(45) - .pi / 4) < 1e-12)
        #expect(abs(Double.turns(1) - .tau) < 1e-12)
        #expect(abs(Double.turns(0.25) - .pi / 2) < 1e-12)
    }

    // MARK: Sketch properties

    @Test func shortAndLongSideAreTheTwoEdges() {
        let sketch = Sketch()
        sketch.width = 300
        sketch.height = 200
        #expect(sketch.shortSide == 200)
        #expect(sketch.longSide == 300)
    }

    @Test func mouseIsThePointerAsOnePoint() {
        let sketch = Sketch()
        sketch.mouseX = 41
        sketch.mouseY = 8.5
        #expect(sketch.mouse == Vector2(41, 8.5))
    }

    @Test func previousMouseLagsExactlyOneFrame() {
        let sketch = Sketch()
        sketch.mouseX = 10; sketch.mouseY = 20
        sketch.advance(time: 0, deltaTime: 1 / 60, frameRate: 60)
        #expect(sketch.previousMouse == Vector2(10, 20),
                "the first frame has no earlier pointer, so the delta starts at zero")
        sketch.mouseX = 30; sketch.mouseY = 40
        sketch.advance(time: 1 / 60, deltaTime: 1 / 60, frameRate: 60)
        #expect(sketch.previousMouse == Vector2(10, 20))
        sketch.advance(time: 2 / 60, deltaTime: 1 / 60, frameRate: 60)
        #expect(sketch.previousMouse == Vector2(30, 40),
                "a still pointer catches up after one frame")
    }

    @Test func waveIsTheSpelledOutSine() {
        let sketch = Sketch()
        sketch.time = 1.7
        let expected = 150 + sin(1.7 * 0.8 + 0.3) * 40
        #expect(abs(sketch.wave(0.8, amplitude: 40, around: 150, phase: 0.3) - expected) < 1e-12)
        #expect(abs(sketch.wave() - sin(1.7)) < 1e-12, "no arguments is plain sin(time)")
    }

    // MARK: Color read-back and mixing

    @Test func hsbReadBackRoundTrips() {
        for (h, s, v) in [(0.1, 0.8, 0.9), (0.55, 0.3, 0.4), (0.9, 1.0, 1.0)] {
            let c = Color(hue: h, saturation: s, brightness: v)
            #expect(abs(c.hue - h) < 1e-9)
            #expect(abs(c.saturation - s) < 1e-9)
            #expect(abs(c.brightness - v) < 1e-9)
        }
        let gray = Color(white: 0.4)
        #expect(gray.saturation == 0)
        #expect(abs(gray.brightness - 0.4) < 1e-9)
    }

    @Test func mixedIsTheInstanceFormOfMix() {
        let a = Color(hex: 0x1F6FEB), b = Color(hex: 0xE4572E)
        for t in stride(from: 0.0, through: 1.0, by: 0.25) {
            let byStatic = Color.mix(a, b, t: t)
            let byInstance = a.mixed(with: b, t)
            #expect(byStatic.red == byInstance.red)
            #expect(byStatic.green == byInstance.green)
            #expect(byStatic.blue == byInstance.blue)
        }
    }

    @Test func colormapCyclingWrapsWhereAtClamps() {
        let map = Colormap.viridis
        let wrapped = map.color(cycling: 1.25)
        let direct = map.color(at: 0.25)
        #expect(wrapped.red == direct.red && wrapped.green == direct.green && wrapped.blue == direct.blue)
        let back = map.color(cycling: -0.25)
        let expected = map.color(at: 0.75)
        #expect(back.red == expected.red && back.green == expected.green && back.blue == expected.blue)
        let clamped = map.color(at: 1.25)
        let end = map.color(at: 1)
        #expect(clamped.red == end.red, "the clamped form still clamps")
    }

    // MARK: Rendered A/B: the sugar must equal the block it replaces

    /// The raw RGBA bytes of a rendered frame, for byte-identical comparison.
    private func bytes(of image: CGImage) -> [UInt8] {
        let w = image.width, h = image.height
        var out = [UInt8](repeating: 0, count: w * h * 4)
        out.withUnsafeMutableBytes { raw in
            let ctx = CGContext(data: raw.baseAddress, width: w, height: h,
                                bitsPerComponent: 8, bytesPerRow: w * 4,
                                space: CGColorSpaceCreateDeviceRGB(),
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
            ctx?.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        }
        return out
    }

    private final class StyledLabel: Sketch {
        var oneCall = true
        override var canvasSize: CanvasSize { .square(256) }
        override func setup() { noLoop() }
        override func draw() {
            background(.white)
            stroke(.crimson)          // a standing stroke the label must suppress
            strokeWeight(3)
            fill(.black)
            textSize(30)
            if oneCall {
                drawText("area", at: Vector2(128, 40), size: 17, color: .navy, align: .center, .top)
            } else {
                withState {
                    noStroke()
                    fill(.navy)
                    textSize(17)
                    textAlign(.center, .top)
                    drawText("area", at: Vector2(128, 40))
                }
            }
            // Drawn with the standing state: any leak from the label shows here.
            drawText("after", 40, 200)
            drawLine(20, 230, 236, 230)
        }
    }

    @Test func styledTextEqualsThePreambleItReplaces() throws {
        let one = StyledLabel()
        let block = StyledLabel(); block.oneCall = false
        let a = bytes(of: try #require(OllinApp.image(of: one)))
        let b = bytes(of: try #require(OllinApp.image(of: block)))
        #expect(a == b)
    }

    @Test func styledTextPutsEveryStateFieldBack() {
        let sketch = Sketch()
        sketch.textSize(30)
        sketch.textAlign(.right, .bottom)
        sketch.fill(.red)
        sketch.stroke(.blue)
        sketch.drawText("x", 10, 10, size: 12, color: .white, align: .center, .middle)
        #expect(sketch.drawer.textPixelSize == 30)
        #expect(sketch.drawer.textAlignH == .right)
        #expect(sketch.drawer.textAlignV == .bottom)
        guard case .color(let f)? = sketch.drawer.fillPaint else { Issue.record("fill lost"); return }
        guard case .color(let s)? = sketch.drawer.strokePaint else { Issue.record("stroke lost"); return }
        #expect(f.red == 1 && f.green == 0 && f.blue == 0)
        #expect(s.blue == 1 && s.red == 0)
    }

    private final class Placed: Sketch {
        var oneCall = true
        override var canvasSize: CanvasSize { .square(256) }
        override func setup() { noLoop() }
        override func draw() {
            background(.white)
            fill(.teal)
            if oneCall {
                withState(at: Vector2(90, 110), rotation: 0.6, scale: 1.4) {
                    drawRect(center: .zero, width: 60, height: 24)
                }
            } else {
                withState {
                    translate(90, 110)
                    rotate(0.6)
                    scale(1.4)
                    drawRect(center: .zero, width: 60, height: 24)
                }
            }
            drawCircle(200, 200, 20)   // standing state must be untouched
        }
    }

    @Test func withStateAtEqualsTheSpelledOutBlock() throws {
        let one = Placed()
        let block = Placed(); block.oneCall = false
        #expect(bytes(of: try #require(OllinApp.image(of: one)))
             == bytes(of: try #require(OllinApp.image(of: block))))
    }

    private final class Arrow: Sketch {
        var oneCall = true
        let a = Vector2(40, 200), b = Vector2(210, 60)
        override var canvasSize: CanvasSize { .square(256) }
        override func setup() { noLoop() }
        override func draw() {
            background(.white)
            stroke(.black)
            strokeWeight(6)
            fill(.orange)              // must survive, and must not paint the head
            if oneCall {
                drawArrow(from: a, to: b, headLength: 24, headWidth: 18)
            } else {
                let dir = (b - a).normalized
                let base = b - dir * 24
                drawLine(a, base)
                withState {
                    fill(.black)
                    noStroke()
                    let perp = dir.perpendicular * 9
                    drawTriangle(b, base + perp, base - perp)
                }
            }
            drawCircle(60, 60, 18)     // painted with the standing orange fill
        }
    }

    @Test func arrowEqualsItsSpelledOutParts() throws {
        let one = Arrow()
        let parts = Arrow(); parts.oneCall = false
        #expect(bytes(of: try #require(OllinApp.image(of: one)))
             == bytes(of: try #require(OllinApp.image(of: parts))))
    }

    private final class NoStrokeArrow: Sketch {
        var drawsArrow = true
        override var canvasSize: CanvasSize { .square(64) }
        override func setup() { noLoop() }
        override func draw() {
            background(.white)
            noStroke()
            if drawsArrow { drawArrow(from: Vector2(8, 8), to: Vector2(56, 56)) }
        }
    }

    @Test func arrowWithNoStrokeDrawsNothing() throws {
        let with = NoStrokeArrow()
        let without = NoStrokeArrow(); without.drawsArrow = false
        #expect(bytes(of: try #require(OllinApp.image(of: with)))
             == bytes(of: try #require(OllinApp.image(of: without))))
    }
}
