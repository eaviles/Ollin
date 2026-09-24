@testable import Ollin
import COllinShaders
import CoreGraphics
import Foundation
import Metal
import Testing

/// A pass with more geometry than tile memory alone can bin. The GPU then has
/// to render part of the pass, store its attachments, and load them back, and a
/// memoryless attachment has nowhere to be stored, so the whole frame used to
/// come back empty with nothing said: a line spray past about ten million points
/// a frame drew no light at all. These pin the count the renderer decides by,
/// the storage it picks, the sentence a failed frame writes, and a frame past
/// the measured edge landing its ink, on the canvas and in a layer.
@Suite
@MainActor
struct HeavyPassTests {

    // MARK: The count

    @Test func theCountIsWhatEachDrawRasterizesOnItsOwnPass() {
        let sketch = Plain()
        let drawer = sketch.drawer
        drawer.beginFrame()
        drawer.noStroke()
        drawer.drawCircle(10, 10, 5)
        drawer.drawCircle(20, 20, 5)                                   // two SDF quads: 4
        drawer.drawPolygon([Vector2(0, 0), Vector2(30, 0), Vector2(15, 20)])  // one triangle
        drawer.recordParticles(ComputeBuffer<OllinParticle>(count: 8), count: 1_000)  // 2,000
        let layer = sketch.makeRenderTarget()
        drawer.withTarget(layer) {
            drawer.recordParticles(ComputeBuffer<OllinParticle>(count: 8), count: 700)  // 1,400
            drawer.drawCircle(5, 5, 2)                                 // 2
        }
        #expect(drawer.primitiveCount(on: nil) == 4 + 1 + 2_000)
        #expect(drawer.primitiveCount(on: layer) == 1_400 + 2)
    }

    @Test func aPassPastTheBudgetTakesBackedAttachmentsAndOnlyThatPass() throws {
        let device = try #require(MTLCreateSystemDefaultDevice())
        let renderer = try MetalRenderer(device: device, pixelFormat: ollinColorPixelFormat,
                                         sampleCount: ollinPreferredSampleCount(device))
        let sketch = Plain()
        let drawer = sketch.drawer
        drawer.beginFrame()
        let budget = MetalRenderer.backedAttachmentPrimitives
        drawer.recordParticles(ComputeBuffer<OllinParticle>(count: 8), count: budget / 2)
        let layer = sketch.makeRenderTarget()
        drawer.withTarget(layer) {
            drawer.recordParticles(ComputeBuffer<OllinParticle>(count: 8), count: budget / 2 + 1)
        }
        // Exactly the budget stays memoryless; one quad more does not.
        #expect(drawer.primitiveCount(on: nil) == budget)
        #expect(renderer.attachmentStorage(for: drawer, target: nil) == .memoryless)
        #expect(renderer.attachmentStorage(for: drawer, target: layer) == .private)
    }

    // MARK: The sentence

    @Test func anOverflowSaysSoAndTurnsLaterPassesToBackedOnes() {
        let overflow = NSError(domain: MTLCommandBufferErrorDomain,
                               code: Int(MTLCommandBufferError.Code.memoryless.rawValue),
                               userInfo: [NSLocalizedDescriptionKey: "Too much geometry"])
        let said = GPUFailures.describe(overflow)
        #expect(said.overflow)
        #expect(said.sentence.contains("memoryless") && said.sentence.contains("Too much geometry"))

        let timeout = NSError(domain: MTLCommandBufferErrorDomain,
                              code: Int(MTLCommandBufferError.Code.timeout.rawValue),
                              userInfo: [NSLocalizedDescriptionKey: "Timed out"])
        let other = GPUFailures.describe(timeout)
        #expect(!other.overflow)
        #expect(other.sentence.contains("came back empty") && other.sentence.contains("Timed out"))
        #expect(!GPUFailures.describe(nil).overflow)
    }

    // MARK: A frame past the edge

    /// Ten million one-pixel marks on a 1024-pixel canvas: past the measured
    /// overflow of a memoryless pass there (8.2 million), drawn onto the canvas
    /// or into a layer drawn back over it. Every mark lands on the left half.
    private final class Heavy: Sketch {
        override var canvasSize: CanvasSize { .square(1024) }
        static let count = 10_000_000
        var intoLayer = false
        let marks = ComputeBuffer<OllinParticle>(count: Heavy.count)
        var layer: RenderTarget!

        static let scatter = ComputeKernel(entry: "heavy_pass_scatter", """
            kernel void heavy_pass_scatter(device OllinParticle *out [[buffer(0)]],
                                           constant OllinComputeUniforms &u [[buffer(10)]],
                                           uint id [[thread_position_in_grid]]) {
                if (id >= u.particleCount) { return; }
                uint h = id * 2654435761u;
                h ^= h >> 15; h *= 2246822519u; h ^= h >> 13;
                OllinParticle p;
                p.position = float2(float(h & 511u) + 0.5, float((h >> 9) & 1023u) + 0.5);
                p.velocity = float2(0.0);
                p.color = float4(1.0);
                p.size = 1.0;
                p.life = 1.0;
                p.seedA = 0.0;
                p.seedB = 0.0;
                out[id] = p;
            }
            """)

        override func setup() { layer = makeRenderTarget() }

        override func draw() {
            background(.black)
            compute(Heavy.scatter, buffers: [marks])
            if intoLayer {
                withTarget(layer) { drawParticles(marks) }
                drawImage(layer.image, 0, 0)
            } else {
                drawParticles(marks)
            }
        }
    }

    @Test(.enabled(if: Snapshot.hasMetal))
    func tenMillionMarksLandOnTheCanvasAndInALayer() throws {
        for intoLayer in [false, true] {
            let sketch = Heavy()
            sketch.intoLayer = intoLayer
            let image = try #require(OllinApp.image(of: sketch, frame: 0))
            let (left, right) = try #require(HeavyPassTests.halves(image))
            // Half a million pixels under ten million marks: the left half is
            // covered, the right half never drawn on.
            #expect(left > 200, "the marks landed (\(intoLayer ? "layer" : "canvas")): mean \(left)")
            #expect(right < 1, "nothing reached the right half: mean \(right)")
        }
    }

    // MARK: Support

    private final class Plain: Sketch {
        override var canvasSize: CanvasSize { .square(64) }
        override func draw() {}
    }

    /// The mean of the red channel over the left and the right half.
    private static func halves(_ image: CGImage) -> (Double, Double)? {
        let w = image.width, h = image.height
        guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8,
                                  bytesPerRow: w * 4, space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        guard let data = ctx.data else { return nil }
        let bytes = data.bindMemory(to: UInt8.self, capacity: w * h * 4)
        var left = 0.0, right = 0.0
        for y in 0..<h {
            for x in 0..<w {
                let r = Double(bytes[(y * w + x) * 4])
                if x < w / 2 { left += r } else { right += r }
            }
        }
        let half = Double(w / 2 * h)
        return (left / half, right / half)
    }
}
