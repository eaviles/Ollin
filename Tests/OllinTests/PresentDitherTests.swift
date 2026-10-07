import CoreGraphics
import Testing
@testable import Ollin

/// The present pass adds up to a level of noise before the 8-bit encode, to
/// break up the bands a smooth gradient otherwise shows. Within a level of
/// black or white the noise reaches only as far as that end allows. These
/// probes read the exported bytes: an exact end stays exact, the noise still
/// runs everywhere else, and a value near an end averages back to itself.
@Suite
@MainActor
struct PresentDitherTests {

    /// Black on the left, white on the right, nothing between.
    private final class TwoLevels: Sketch {
        override var canvasSize: CanvasSize { .size(256, 128) }

        override func draw() {
            background(.black)
            noStroke()
            fill(.white)
            drawRect(128, 0, 128, 128)
        }
    }

    /// One flat gray, half way up the encoded range.
    private final class MidGray: Sketch {
        override var canvasSize: CanvasSize { .square(128) }

        override func draw() {
            background(Color(white: 0.5))
        }
    }

    /// Columns a tenth of a level apart, from black up and from white down:
    /// `steps` of them from 0, each `columnWidth` wide, black's in the top half.
    private final class EndRamps: Sketch {
        static let steps = 5
        static let columnWidth = 16
        override var canvasSize: CanvasSize { .size(Self.steps * Self.columnWidth, 160) }

        override func draw() {
            background(.black)
            noStroke()
            for i in 0 ..< Self.steps {
                let level = Double(i) / 10
                let x = Double(i * Self.columnWidth)
                fill(Color(white: level / 255))
                drawRect(x, 0, Double(Self.columnWidth), 80)
                fill(Color(white: 1 - level / 255))
                drawRect(x, 80, Double(Self.columnWidth), 80)
            }
        }
    }

    @Test("exact black and exact white come out exactly 0 and 255")
    func exactEndsStayExact() throws {
        let frame = Pixels(try OllinApp.image(of: TwoLevels()))
        var moved = 0
        for y in 0 ..< frame.height {
            for x in 0 ..< frame.width where abs(x - 128) > 2 {
                let want: UInt8 = x < 128 ? 0 : 255
                let at = (y * frame.width + x) * 4
                for c in 0 ..< 3 where frame.bytes[at + c] != want { moved += 1 }
            }
        }
        // Before the reach was limited, about one black value in six read 1 and
        // one white value in eight read 254.
        #expect(moved == 0)
    }

    @Test("a mid gray is still dithered")
    func theMiddleIsStillDithered() throws {
        let frame = Pixels(try OllinApp.image(of: MidGray()))
        let reds = stride(from: 0, to: frame.bytes.count, by: 4).map { Int(frame.bytes[$0]) }
        #expect(Set(reds).count >= 2)
        let mean = Double(reds.reduce(0, +)) / Double(reds.count)
        #expect(abs(mean - 127.5) < 0.1)
    }

    @Test("a value within 0.4 of a level of either end averages back to itself")
    func nearTheEndsTheMeanHolds() throws {
        let frame = Pixels(try OllinApp.image(of: EndRamps()))
        let width = EndRamps.columnWidth
        var worst = 0.0
        for i in 0 ..< EndRamps.steps {
            let level = Double(i) / 10
            var dark = 0.0, light = 0.0, count = 0.0
            for y in 4 ..< 76 {
                for x in (i * width + 2) ..< ((i + 1) * width - 2) {
                    dark += Double(frame.bytes[(y * frame.width + x) * 4])
                    light += 255 - Double(frame.bytes[((y + 80) * frame.width + x) * 4])
                    count += 1
                }
            }
            worst = max(worst, abs(dark / count - level), abs(light / count - level))
        }
        // The clamp that let the noise reach past an end pushed these up by as
        // much as 0.18 of a level; limited, they land within 0.11. From about
        // half a level up, black's mean reads up to a quarter of a level high
        // with or without the limit, which is the 8-bit sRGB encode rounding in
        // its straight segment, not the dither, so the columns stop at 0.4.
        #expect(worst < 0.15)
    }
}
