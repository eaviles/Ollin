import CoreGraphics
import Foundation
@testable import Ollin
import Testing

/// `toneMap(.neutral)` keeps a bright color's hue. The per-channel curves bend
/// each channel on its own, so a bright saturated orange comes out yellow;
/// the neutral curve compresses all three by one factor and holds it.
@Suite(.serialized)
@MainActor
struct ToneMapTests {

    /// A flat canvas of one bright color, under one tone map.
    final class Flat: Sketch {
        var map: ToneMap = .neutral
        var color = Color(linear: 4, green: 1, blue: 0.2)
        override var canvasSize: CanvasSize { .square(16) }
        override func setup() { toneMap(map) }
        override func draw() { background(color) }
    }

    /// The hue angle of a color in linear light, in degrees: the hue the
    /// present pass was handed, read back out of the 8-bit frame.
    private func hue(under map: ToneMap, color: Color = Color(linear: 4, green: 1, blue: 0.2)) throws -> Double {
        let sketch = Flat()
        sketch.map = map
        sketch.color = color
        let image = try #require(try OllinApp.image(of: sketch, frame: 0))
        let bytes = pixels(of: image)
        let i = (8 * image.width + 8) * 4
        let r = Color.srgbToLinear(Double(bytes[i]) / 255)
        let g = Color.srgbToLinear(Double(bytes[i + 1]) / 255)
        let b = Color.srgbToLinear(Double(bytes[i + 2]) / 255)
        let top = Swift.max(r, g, b), bottom = Swift.min(r, g, b)
        guard top > bottom else { return 0 }
        let h: Double
        if top == r { h = (g - b) / (top - bottom) }
        else if top == g { h = 2 + (b - r) / (top - bottom) }
        else { h = 4 + (r - g) / (top - bottom) }
        return (h * 60 + 360).truncatingRemainder(dividingBy: 360)
    }

    /// Linear (4, 1, 0.2) is an orange at 12.6 degrees. Under `.neutral` it
    /// keeps that hue within two degrees; under `.aces` and `.reinhard` it
    /// drifts past thirty degrees toward yellow, the drift the case exists for.
    @Test(.enabled(if: Snapshot.hasMetal))
    func theNeutralCurveKeepsABrightOrangeOrange() throws {
        let orange = 12.63
        let neutral = try hue(under: .neutral)
        let aces = try hue(under: .aces)
        let reinhard = try hue(under: .reinhard)
        #expect(abs(neutral - orange) <= 2, "neutral: \(neutral)")
        #expect(aces - orange > 25, "aces: \(aces)")
        #expect(reinhard - orange > 15, "reinhard: \(reinhard)")
    }

    /// A color under the curve's knee keeps its hue exactly and loses only the
    /// curve's toe: every channel comes out at most 0.04 of linear light under
    /// what `.clamp` shows, and never over it.
    @Test(.enabled(if: Snapshot.hasMetal))
    func anInRangeColorKeepsItsHueAndLosesOnlyTheToe() throws {
        let dim = Color(linear: 0.5, green: 0.2, blue: 0.1)
        func linear(_ map: ToneMap) throws -> [Double] {
            let sketch = Flat()
            sketch.map = map
            sketch.color = dim
            let bytes = pixels(of: try #require(try OllinApp.image(of: sketch, frame: 0)))
            let i = (8 * 16 + 8) * 4
            return (0 ..< 3).map { Color.srgbToLinear(Double(bytes[i + $0]) / 255) }
        }
        let neutral = try linear(.neutral), clamp = try linear(.clamp)
        for c in 0 ..< 3 {
            #expect(neutral[c] <= clamp[c] + 0.004 && neutral[c] >= clamp[c] - 0.045, "channel \(c): \(neutral[c]) against \(clamp[c])")
        }
        #expect(abs(try hue(under: .neutral, color: dim) - hue(under: .clamp, color: dim)) <= 1)
    }
}
