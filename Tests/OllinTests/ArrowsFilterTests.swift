import CoreGraphics
import Ollin
import Testing

/// `Filter.arrows`: a two-channel layer read as arrows. Probed on a field whose
/// kernel holds one vector everywhere, so every arrow is known: where the ink sits
/// relative to each cell's center says the direction, the count says the spacing,
/// and a zero field draws nothing at all.
@Suite
@MainActor
struct ArrowsFilterTests {

    @Test(.enabled(if: Snapshot.hasMetal))
    func arrowsPointTheWayTheFieldSays() throws {
        let right = try ink(vector: SIMD4(1, 0, 0, 1))
        #expect(right.total > 0)
        #expect(right.rightOfCenter > right.leftOfCenter * 4)
        #expect(abs(right.belowCenter - right.aboveCenter) < right.total / 4)
        let down = try ink(vector: SIMD4(0, 1, 0, 1))
        #expect(down.belowCenter > down.aboveCenter * 4)
        #expect(abs(down.rightOfCenter - down.leftOfCenter) < down.total / 4)
    }

    @Test(.enabled(if: Snapshot.hasMetal))
    func aStillFieldDrawsNoArrows() throws {
        let none = try ink(vector: SIMD4(0, 0, 0, 1))
        #expect(none.total == 0)
    }

    @Test(.enabled(if: Snapshot.hasMetal))
    func everyCellGetsOneArrow() throws {
        // Eight cells of twelve pixels across a 96-pixel canvas: eight shafts on the
        // row through the cell centers, each a run of ink with a gap between.
        let right = try ink(vector: SIMD4(1, 0, 0, 1))
        #expect(right.runsOnCenterRow == 8)
    }

    // MARK: The probe

    private struct Ink {
        var total = 0, leftOfCenter = 0, rightOfCenter = 0, aboveCenter = 0, belowCenter = 0
        var runsOnCenterRow = 0
    }

    /// The arrows of a field that is `vector` everywhere, 12 pixels apart at 4 pixels
    /// per unit (short enough that no arrow leaves its own cell), as ink counts about
    /// each cell's center, sides told apart at pixel centers.
    private func ink(vector: SIMD4<Float>) throws -> Ink {
        let sketch = ArrowProbe()
        sketch.vector = vector
        let image = try #require(OllinApp.image(of: sketch, frame: 1))
        let w = image.width, h = image.height
        var data = [UInt8](repeating: 0, count: w * h * 4)
        let info = CGImageAlphaInfo.premultipliedLast.rawValue
        if let ctx = CGContext(data: &data, width: w, height: h, bitsPerComponent: 8,
                               bytesPerRow: w * 4, space: CGColorSpaceCreateDeviceRGB(),
                               bitmapInfo: info) {
            ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        }
        var ink = Ink()
        let spacing = 12
        for y in 0 ..< h {
            for x in 0 ..< w where data[(y * w + x) * 4] > 64 {
                ink.total += 1
                let cx = Double((x / spacing) * spacing + spacing / 2)
                let cy = Double((y / spacing) * spacing + spacing / 2)
                if Double(x) + 0.5 > cx { ink.rightOfCenter += 1 } else { ink.leftOfCenter += 1 }
                if Double(y) + 0.5 > cy { ink.belowCenter += 1 } else { ink.aboveCenter += 1 }
            }
        }
        // Runs of ink along the row through the first cell centers (y = 6).
        var inRun = false
        for x in 0 ..< w {
            let lit = data[(6 * w + x) * 4] > 64
            if lit && !inRun { ink.runsOnCenterRow += 1 }
            inRun = lit
        }
        return ink
    }
}

/// A 96-pixel field holding one vector in every cell (its rest state under an
/// identity kernel), drawn as arrows twelve pixels apart over black.
@MainActor
private final class ArrowProbe: Sketch {
    override var canvasSize: CanvasSize { .square(96) }
    var vector = SIMD4<Float>(1, 0, 0, 1)
    private var field: SimField!

    override func setup() {
        let identity = Shader("float4 shade(float2 uv, ShaderInfo info) { return cell(info); }")
        field = makeSimField(.shader(identity, rest: vector), scale: 1)
    }

    override func draw() {
        background(.black)
        drawImage(field.filtered(.arrows(spacing: 12, scale: 4, color: .white, width: 1.5)).image, 0, 0)
    }
}
