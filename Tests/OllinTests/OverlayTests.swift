import CoreGraphics
import Foundation
import Metal
import Testing
@testable import Ollin

/// The overlay (`withOverlay`): drawing held back and drawn over the finished
/// frame after its passes, in a pass of its own.
@Suite
@MainActor
struct OverlayTests {

    static let size = 512

    /// A sketch whose `draw` is handed in, so each test says what it draws.
    final class Overlaid: Sketch {
        var body: (Overlaid) -> Void = { _ in }
        var piles = false
        override var canvasSize: CanvasSize { .square(OverlayTests.size) }
        override func setup() { noStroke(); if piles { noClear() } }
        override func draw() { body(self) }
    }

    /// The frame in linear light, row 0 at the top.
    struct Frame {
        let size: Int
        let rgb: [SIMD3<Float>]
        func at(_ x: Int, _ y: Int) -> SIMD3<Float> { rgb[y * size + x] }
        func lum(_ x: Int, _ y: Int) -> Double {
            let c = at(x, y)
            return Double(0.2126 * c.x + 0.7152 * c.y + 0.0722 * c.z)
        }
    }

    private func render(_ sketch: Overlaid, frame: Int = 0) throws -> (frame: Frame, renderer: MetalRenderer) {
        let renderer = try OllinApp.headlessRenderer(for: sketch)
        OllinApp.isRenderingHeadless = true
        defer { OllinApp.isRenderingHeadless = false }
        renderer.capturesLinearFrame = true
        _ = try OllinApp.renderImage(of: sketch, frame: frame, fps: 60, renderer: renderer)
        let linear = try #require(renderer.lastLinearFrame)
        let n = linear.width * linear.height
        let halfs = linear.color.contents().bindMemory(to: Float16.self, capacity: n * 4)
        var rgb = [SIMD3<Float>](repeating: .zero, count: n)
        for i in 0 ..< n { rgb[i] = SIMD3(Float(halfs[i * 4]), Float(halfs[i * 4 + 1]), Float(halfs[i * 4 + 2])) }
        return (Frame(size: linear.width, rgb: rgb), renderer)
    }

    private func sketch(piles: Bool = false, _ body: @escaping (Overlaid) -> Void) -> Overlaid {
        let s = Overlaid()
        s.piles = piles
        s.body = body
        return s
    }

    /// A thin white bar drawn over a scene whose far plane is well out of focus:
    /// in the frame it takes the blur of the depth under it, in the overlay it
    /// keeps its edge.
    @Test(.enabled(if: Snapshot.hasMetal))
    func theOverlayStaysSharpUnderDepthOfField() throws {
        func scene(overlaid: Bool) -> Overlaid {
            sketch { s in
                s.background(.black)
                var lens = Camera3D.perspective(eye: Vector3(0, 0, 6), target: .zero,
                                                fieldOfView: .pi / 4, near: 1, far: 20)
                lens.aperture = 0.3
                lens.focusDistance = 6
                s.camera(lens)
                s.depthOfField()
                s.noLights()
                // Something in the frame, so it carries a depth, far off to one side.
                s.fill(Color(white: 0.2))
                s.withState { s.translate(-3, 0, -9); s.drawMesh(Mesh.box(width: 1, height: 1, depth: 1)) }
                s.fill(.white)
                let bar = { s.drawRect(255, 100, 2, 300) }
                if overlaid { s.withOverlay(bar) } else { bar() }
            }
        }
        let inFrame = try render(scene(overlaid: false)).frame
        let overlaid = try render(scene(overlaid: true)).frame
        // The bar's own column, and one eight pixels off it.
        #expect(overlaid.lum(256, 250) > 0.9, "the overlay's bar reads \(overlaid.lum(256, 250)) at its center")
        #expect(overlaid.lum(264, 250) < 0.02, "the overlay's bar reads \(overlaid.lum(264, 250)) eight pixels off")
        #expect(inFrame.lum(256, 250) < 0.5, "the bar in the frame reads \(inFrame.lum(256, 250)) at its center: not blurred")
    }

    /// Whatever the call order, the overlay lands over everything else, and a
    /// frame without one draws no overlay pass.
    @Test(.enabled(if: Snapshot.hasMetal))
    func theOverlayLandsOverEverythingWhateverTheCallOrder() throws {
        let first = try render(sketch { s in
            s.background(.black)
            s.withOverlay { s.fill(.red); s.drawRect(200, 200, 100, 100) }
            s.fill(.white)
            s.drawRect(0, 0, 512, 512)
        })
        #expect(first.renderer.overlayDrawnLastFrame)
        let c = first.frame.at(250, 250)
        #expect(c.x > 0.9 && c.y < 0.05, "the overlay's square drawn first reads \(c) under the later fill")
        #expect(first.frame.lum(100, 100) > 0.9, "the canvas fill reads \(first.frame.lum(100, 100)) beside it")

        let plain = try render(sketch { s in s.background(.black); s.fill(.white); s.drawRect(0, 0, 512, 512) })
        #expect(!plain.renderer.overlayDrawnLastFrame, "a frame with no overlay drew the overlay pass")
    }

    /// A blend mode in the overlay composites against the finished frame, not
    /// against an empty layer: a multiply over white is the fill's own value.
    @Test(.enabled(if: Snapshot.hasMetal))
    func aBlendModeInTheOverlayReadsTheFinishedFrame() throws {
        let f = try render(sketch { s in
            s.background(.white)
            s.withOverlay {
                s.blendMode(.multiply)
                s.fill(Color(white: 0.5))
                s.drawRect(100, 100, 200, 200)
            }
        }).frame
        let expected = Color.srgbToLinear(0.5)
        #expect(abs(f.lum(200, 200) - Double(expected)) < 0.02,
                "a half-gray multiplied over white reads \(f.lum(200, 200)), expected \(expected)")
    }

    /// Over an accumulating canvas the overlay is drawn each frame over the pile
    /// and never joins it: a mark drawn in the overlay on the first frame alone
    /// is gone by the second, while the canvas's own mark stays.
    @Test(.enabled(if: Snapshot.hasMetal))
    func theOverlayNeverJoinsAnAccumulatingCanvas() throws {
        let piling = sketch(piles: true) { s in
            // The headless drive settles a frame with its clock held and the frame
            // count moving on, so the first frame is the one at time zero.
            if s.time == 0 {
                s.withOverlay { s.fill(.red); s.drawRect(100, 100, 50, 50) }
            }
            s.fill(.white)
            s.drawCircle(300, 300, 20)
        }
        let first = try render(piling, frame: 0).frame
        #expect(first.at(125, 125).x > 0.9, "the overlay's mark reads \(first.at(125, 125)) on the first frame")
        let second = try render(sketch(piles: true) { s in piling.body(s) }, frame: 1)
        #expect(second.frame.lum(125, 125) < 0.02, "the overlay's first-frame mark reads \(second.frame.lum(125, 125)) on the second frame: it joined the pile")
        #expect(second.frame.lum(300, 300) > 0.9, "the canvas mark reads \(second.frame.lum(300, 300)) on the second frame")
        #expect(!second.renderer.overlayDrawnLastFrame, "the second frame drew an overlay it did not have")
    }

    /// Clipping is per surface: a clip open on the canvas does not clip the
    /// overlay, and a clip inside the overlay clips the overlay alone.
    @Test(.enabled(if: Snapshot.hasMetal))
    func aClipInTheOverlayClipsTheOverlayAlone() throws {
        let f = try render(sketch { s in
            s.background(.black)
            s.withClip(Rectangle(x: 0, y: 0, width: 256, height: 512)) {
                s.fill(.white)
                s.drawRect(0, 0, 512, 512)                       // the canvas: left half only
                s.withOverlay {
                    s.fill(.red)
                    s.drawRect(0, 0, 512, 100)                   // unclipped: the whole top band
                    s.withClip(Rectangle(x: 0, y: 200, width: 100, height: 100)) {
                        s.fill(.blue)
                        s.drawRect(0, 150, 512, 200)             // clipped to its own box
                    }
                }
            }
        }).frame
        #expect(f.lum(400, 300) < 0.02, "the canvas fill reads \(f.lum(400, 300)) outside its clip")
        #expect(f.at(400, 50).x > 0.9, "the overlay's band reads \(f.at(400, 50)) outside the canvas's clip")
        #expect(f.at(50, 250).z > 0.9, "the overlay's clipped fill reads \(f.at(50, 250)) inside its clip")
        #expect(f.at(300, 250).z < 0.05, "the overlay's clipped fill reads \(f.at(300, 250)) outside its clip")
    }

    /// A vector export writes the overlay after everything else, where the pass
    /// puts it, whatever the call order.
    @Test func theOverlayWritesLastInAVectorFile() throws {
        let svg = OllinApp.svg(of: sketch { s in
            s.withOverlay { s.fill(.red); s.drawRect(10, 10, 40, 40) }
            s.fill(.white)
            s.drawCircle(100, 100, 30)
        })
        let rect = try #require(svg.range(of: "<rect x=\"10\""))
        let circle = try #require(svg.range(of: "<circle"))
        #expect(rect.lowerBound > circle.lowerBound, "the overlay's rect is written before the circle drawn after it")
    }
}
