import CoreGraphics
import Ollin
import Testing

/// Behavioral probes for the `.ripples` wave-equation sim, run headless on a
/// small field and read back per frame: a still pool stays still, a single
/// soft drop becomes a ring that expands and dies away, and neither channel
/// (height in red, velocity in green) blows up or pins into sustained blobs
/// (the failure mode that parked the first attempt). Metal-gated.
@Suite
@MainActor
struct RipplesTests {

    @Test(.enabled(if: Snapshot.hasMetal))
    func stillPoolStaysStill() throws {
        let sketch = RipplesProbeSketch()
        sketch.dropFrame = -1   // never drop
        let image = try #require(OllinApp.image(of: sketch, frame: 40))
        let stats = channelStats(of: image)
        // Within the present pass's output dither (±1 LSB), the pool is flat.
        #expect(stats.peakRed < 0.02)
        #expect(stats.peakGreen < 0.02)
    }

    @Test(.enabled(if: Snapshot.hasMetal))
    func dropBecomesAnExpandingRing() throws {
        let sketch = RipplesProbeSketch()
        let early = ringRadius(of: try #require(OllinApp.image(of: sketch, frame: 10)))
        let late = ringRadius(of: try #require(OllinApp.image(of: RipplesProbeSketch(), frame: 26)))
        #expect(early > 0)
        #expect(late > early + 4)   // the front moved outward, meaningfully
    }

    @Test(.enabled(if: Snapshot.hasMetal))
    func ringsDecayInsteadOfPinning() throws {
        // Just after the drop the surface is strongly disturbed; long after,
        // both channels must have died far down (the parked attempt's blobs
        // stayed saturated and *grew* over frames).
        let fresh = channelStats(of: try #require(OllinApp.image(of: RipplesProbeSketch(), frame: 6)))
        let settled = channelStats(of: try #require(OllinApp.image(of: RipplesProbeSketch(), frame: 220)))
        #expect(fresh.peakRed > 0.15)
        #expect(settled.peakRed < fresh.peakRed * 0.5)
        #expect(settled.peakGreen < 0.1)
        // And the drop site itself is quiet, not a standing plateau.
        #expect(settled.centerRed < 0.1)
    }

    // MARK: Readback helpers

    private struct Stats {
        var peakRed = 0.0     // height channel
        var peakGreen = 0.0   // velocity channel
        var centerRed = 0.0
    }

    private func bytes(of image: CGImage) -> (bytes: [UInt8], width: Int, height: Int) {
        let w = image.width, h = image.height
        var data = [UInt8](repeating: 0, count: w * h * 4)
        let space = CGColorSpaceCreateDeviceRGB()
        let info = CGImageAlphaInfo.premultipliedLast.rawValue
        if let ctx = CGContext(data: &data, width: w, height: h, bitsPerComponent: 8,
                               bytesPerRow: w * 4, space: space, bitmapInfo: info) {
            ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        }
        return (data, w, h)
    }

    private func channelStats(of image: CGImage) -> Stats {
        let (data, w, h) = bytes(of: image)
        var stats = Stats()
        for i in stride(from: 0, to: data.count, by: 4) {
            stats.peakRed = max(stats.peakRed, Double(data[i]) / 255)
            stats.peakGreen = max(stats.peakGreen, Double(data[i + 1]) / 255)
        }
        let center = ((h / 2) * w + w / 2) * 4
        stats.centerRed = Double(data[center]) / 255
        return stats
    }

    /// The farthest lit height pixel from the drop point: the ring front.
    private func ringRadius(of image: CGImage) -> Double {
        let (data, w, h) = bytes(of: image)
        var radius = 0.0
        for y in 0 ..< h {
            for x in 0 ..< w where data[(y * w + x) * 4] > 24 {
                let dx = Double(x - w / 2), dy = Double(y - h / 2)
                radius = max(radius, (dx * dx + dy * dy).squareRoot())
            }
        }
        return radius
    }
}

/// A tiny pool: a 64² ripples field under a 128² canvas. One soft drop lands
/// at `dropFrame` (a radial-gradient dab fading to clear, the recommended drop
/// shape) and the raw state draws full-canvas for readback.
@MainActor
private final class RipplesProbeSketch: Sketch {
    override var canvasSize: CanvasSize { .square(128) }
    var dropFrame = 1

    private var pool: SimField!

    override func setup() {
        pool = simField(.ripples(), scale: 0.5)
    }

    override func draw() {
        background(.black)
        withField(pool) {
            if frameCount == dropFrame {
                fill(.radial(center: center, radius: 12,
                             [Color(white: 1, alpha: 0.9), Color(white: 1, alpha: 0)]))
                drawCircle(center.x, center.y, 12)
            }
        }
        drawImage(pool.image, 0, 0)
    }
}
