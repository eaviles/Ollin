@testable import Ollin
import CoreGraphics
import Foundation
import Metal
import MetalKit
import QuartzCore
import Testing

/// A sketch's own drawing read back: `RenderTarget.snapshot()` answers from
/// the frame before and never waits on the GPU (exactly the frame before in an
/// export, one frame late on the live path, at the cost of one present pass),
/// the GPU slit scan over a `LayerHistory` composes what the CPU `SlitScan`
/// composes from the same frames, the glyph mosaic of a layer chooses what the
/// mosaic of its snapshot chooses, and a web page stops at each by name.
@Suite
@MainActor
struct LayerReadbackTests {

    // MARK: Matching (no GPU)

    /// The n-th request of a frame reads the n-th result of the frame before,
    /// and only one of the same kind at the same size.
    @Test func aRequestReadsItsOwnPositionKindAndSize() throws {
        let sketch = Sketch()
        sketch.setCanvasSize(width: 64, height: 64)
        let picture = Image(width: 64, height: 64, color: .white)
        sketch.drawer.layerReadbackResults = [
            LayerReadbackResult(kind: .pixels, pixelWidth: 64, pixelHeight: 64, image: picture, cells: nil),
            nil,
            LayerReadbackResult(kind: .cells(columns: 4, rows: 4), pixelWidth: 64, pixelHeight: 64,
                                image: nil, cells: Array(repeating: SIMD4<Float>(repeating: 0.5), count: 16)),
        ]
        let layer = sketch.makeRenderTarget()
        #expect(layer.snapshot() === picture, "the first request reads the first result")
        #expect(layer.snapshot() == nil, "the second reads the second, which the frame before did not fill")
        #expect(sketch.drawer.requestLayerReadback(of: layer, .cells(columns: 4, rows: 4))?.cells?.count == 16)
        #expect(sketch.drawer.requestLayerReadback(of: layer, .pixels) == nil, "the fourth has no result yet")
        #expect(sketch.drawer.layerReadbacks.count == 4, "every ask is recorded for the renderer")

        // A result of another kind or size at the position is not an answer.
        sketch.drawer.beginFrame()
        let half = sketch.makeRenderTarget(scale: 0.5)
        #expect(half.snapshot() == nil, "a 32-pixel layer must not read a 64-pixel picture")
        sketch.drawer.beginFrame()
        #expect(sketch.drawer.requestLayerReadback(of: layer, .cells(columns: 4, rows: 4)) == nil,
                "a cell request must not read a pixel result")
        sketch.drawer.beginFrame()
        #expect(sketch.drawer.layerReadbacks.isEmpty, "the requests are per frame")
        #expect(sketch.drawer.layerReadbackResults.count == 3, "the results stay until the next delivery")
    }

    // MARK: The sketches

    /// One white disc a frame, at a column named by the sketch's own frame
    /// count, drawn into a full-canvas layer. The canvas shows the layer's
    /// snapshot, which is the frame before's layer, or nothing on the first
    /// frame; `seen` records which frame's disc each draw was handed.
    final class SnapshotMarker: Sketch {
        var seen: [Int?] = []
        var reads = true
        override var canvasSize: CanvasSize { .square(256) }
        override func draw() {
            background(.black)
            let layer = makeRenderTarget()
            withTarget(layer) {
                background(.black)
                noStroke()
                fill(.white)
                drawCircle(Self.column(of: frameCount), 128, 20)
            }
            guard reads else { return }
            if let picture = layer.snapshot() {
                drawImage(picture, 0, 0)
                seen.append(Self.frameShown(in: picture))
            } else {
                seen.append(nil)
            }
        }
        static func column(of frame: Int) -> Double { 40 + Double((frame - 1) % 3) * 88 }
        /// The frame (1 to 3) whose disc `picture` carries.
        static func frameShown(in picture: Image) -> Int? {
            for frame in 1...3 where picture[Int(column(of: frame)), 128].luminance > 0.5 { return frame }
            return nil
        }
    }

    /// A time-free rosette drawn into a layer and composited whole, so the
    /// snapshot of the layer and the headless image of the canvas are one
    /// picture.
    final class RosetteLayer: Sketch {
        var taken: Image?
        override var canvasSize: CanvasSize { .square(256) }
        override func draw() {
            let layer = makeRenderTarget()
            withTarget(layer) {
                background(Color(white: 0.08))
                noStroke()
                for i in 0..<6 {
                    let a = Double(i) / 6 * .tau
                    fill(Color(hue: Double(i) / 6, saturation: 0.8, brightness: 0.9))
                    drawCircle(center: center + Vector2(angle: a) * 70, radius: 34)
                }
                noFill()
                stroke(.white)
                strokeWeight(3)
                drawCircle(center: center, radius: 110)
            }
            background(.black)
            drawImage(layer.image, 0, 0)
            taken = layer.snapshot()
        }
    }

    /// A disc moving over a field whose hue turns every frame, drawn into a
    /// 64-pixel layer: scanned on the GPU through a `LayerHistory` on the
    /// left, and on the CPU through a `SlitScan` fed by the layer's snapshot
    /// on the right. The CPU side runs one frame behind, so frame N's left
    /// half is frame N + 1's right half.
    final class Scanned: Sketch {
        var delay: SlitScanDelay = .across
        var cpuDelay: (Vector2) -> Double = { $0.x }
        var cpuMap: Image?
        var twice = false
        let cpu = SlitScan(capacity: 8)
        var gpu: LayerHistory!
        override var canvasSize: CanvasSize { .size(128, 64) }
        override func setup() { gpu = makeLayerHistory(capacity: 8) }
        override func draw() {
            background(.black)
            let scene = makeRenderTarget(width: 64, height: 64)
            withTarget(scene) {
                background(Color(hue: Double(frameCount % 8) / 8, saturation: 0.6, brightness: 0.5))
                noStroke()
                fill(.white)
                drawCircle(8 + Double(frameCount * 7 % 48), 32 + 12 * sin(Double(frameCount)), 9)
            }
            drawImage(scene.filtered(.slitScan(gpu, delay: delay)).image, 0, 0)
            if twice {
                drawImage(scene.filtered(.slitScan(gpu, delay: delay)).image, 64, 0)
                return
            }
            if let picture = scene.snapshot() {
                cpu.append(picture)
                let warped = cpuMap.map { cpu.image(delay: $0) } ?? cpu.image(delay: cpuDelay)
                if let warped { drawImage(warped, 64, 0) }
            }
        }
    }

    /// Discs of every brightness, some translucent, in a layer the glyph
    /// mosaic reads two ways in one draw: off the layer (a reduction on the
    /// GPU, a frame late) and off the layer's snapshot (the CPU bytes, the
    /// same frame late).
    final class Mosaicked: Sketch {
        var fromLayer: [GlyphMosaicCell] = []
        var fromSnapshot: [GlyphMosaicCell] = []
        override var canvasSize: CanvasSize { .square(128) }
        override func draw() {
            background(.black)
            textFont(BitmapFont.builtIn)
            let layer = makeRenderTarget()
            withTarget(layer) {
                noStroke()
                for i in 0..<12 {
                    let t = Double(i) / 11
                    fill(Color(hue: t, saturation: 0.5, brightness: 0.2 + 0.8 * t, alpha: i % 3 == 0 ? 0.5 : 1))
                    drawCircle(12 + 104 * t, 20 + 88 * (0.5 + 0.5 * sin(Double(i) * 1.7 + Double(frameCount))), 14)
                }
            }
            fromLayer = glyphMosaic(of: layer.image, columns: 16, characters: GlyphSet.classic)
            if let picture = layer.snapshot() {
                fromSnapshot = glyphMosaic(of: picture, columns: 16, characters: GlyphSet.classic)
            }
            drawImage(layer.image, 0, 0)
        }
    }

    // MARK: Helpers

    private func makeView(_ device: MTLDevice, side: Int, for sketch: Sketch) -> MTKView {
        let view = MTKView(frame: CGRect(x: 0, y: 0, width: side, height: side), device: device)
        view.drawableSize = CGSize(width: side, height: side)
        view.colorPixelFormat = sketch.colorOutput.drawablePixelFormat
        view.isPaused = true
        view.enableSetNeedsDisplay = false
        return view
    }

    /// Turn the main loop until `done`, or ten seconds pass; the probe comes
    /// before the clock, so a late wakeup still finds what it waited for.
    private func spin(until done: () -> Bool) {
        let deadline = CACurrentMediaTime() + 10
        while !done() {
            if CACurrentMediaTime() > deadline { return }
            RunLoop.current.run(until: Date().addingTimeInterval(0.005))
        }
    }

    /// Mean absolute difference over the color bytes of two same-sized images.
    private func meanDifference(_ a: CGImage, _ b: CGImage) throws -> Double {
        let (pa, pb) = (pixels(of: a), pixels(of: b))
        try #require(pa.count == pb.count)
        var sum = 0
        for i in stride(from: 0, to: pa.count, by: 4) {
            sum += abs(Int(pa[i]) - Int(pb[i])) + abs(Int(pa[i + 1]) - Int(pb[i + 1]))
                + abs(Int(pa[i + 2]) - Int(pb[i + 2]))
        }
        return Double(sum) / Double(pa.count / 4 * 3)
    }

    /// Mean absolute difference over the color bytes of two 64-pixel halves of
    /// two 128 by 64 frames: `left` of `a` against `right` of `b`.
    private func halvesDifference(_ a: CGImage, _ b: CGImage) throws -> Double {
        let (pa, pb) = (pixels(of: a), pixels(of: b))
        try #require(a.width == 128 && b.width == 128 && a.height == 64 && b.height == 64)
        var sum = 0
        for y in 0..<64 {
            for x in 0..<64 {
                let i = (y * 128 + x) * 4, j = (y * 128 + x + 64) * 4
                sum += abs(Int(pa[i]) - Int(pb[j])) + abs(Int(pa[i + 1]) - Int(pb[j + 1]))
                    + abs(Int(pa[i + 2]) - Int(pb[j + 2]))
            }
        }
        return Double(sum) / Double(64 * 64 * 3)
    }

    private func brightness(_ image: CGImage, x: Int, y: Int) -> Int {
        let bytes = pixels(of: image)
        let i = (y * image.width + x) * 4
        return (Int(bytes[i]) + Int(bytes[i + 1]) + Int(bytes[i + 2])) / 3
    }

    // MARK: The export

    /// In an export every frame renders and is read in turn, so a snapshot is
    /// exactly the frame before: the first frame shows nothing, and frame N
    /// shows the disc of frame N alone, keyed on the sketch's own frame count.
    @Test(.enabled(if: Snapshot.hasMetal))
    func anExportsSnapshotIsExactlyTheFrameBefore() throws {
        let first = SnapshotMarker()
        let frame0 = try OllinApp.image(of: first, frame: 0)
        #expect(first.seen == [nil], "the first frame has no frame before")
        for frame in 1...3 {
            #expect(brightness(frame0, x: Int(SnapshotMarker.column(of: frame)), y: 128) < 20,
                    "the first frame's canvas must be empty")
        }
        for target in 1...3 {
            let sketch = SnapshotMarker()
            let image = try OllinApp.image(of: sketch, frame: target)
            // The draw of frame `target` has frame count target + 1 and was
            // handed the layer drawn at frame count `target`.
            #expect(sketch.seen.last == target, "frame \(target + 1) saw \(String(describing: sketch.seen.last))")
            for frame in 1...3 {
                let lit = brightness(image, x: Int(SnapshotMarker.column(of: frame)), y: 128) > 128
                #expect(lit == (frame == target),
                        "frame \(target + 1)'s canvas must carry frame \(target)'s disc alone")
            }
        }
    }

    /// The snapshot is the layer as it would be shown: tone-mapped and
    /// encoded by the present pass, so it is the headless image of the same
    /// picture to within a level.
    @Test(.enabled(if: Snapshot.hasMetal))
    func aSnapshotIsTheHeadlessImageWithinALevel() throws {
        let sketch = RosetteLayer()
        _ = try OllinApp.image(of: sketch, frame: 1)
        let taken = try #require(sketch.taken)
        #expect(taken.width == 256 && taken.height == 256)
        let reference = try OllinApp.image(of: RosetteLayer(), frame: 0)
        let mean = try meanDifference(taken.currentCGImage(), reference)
        #expect(mean < 0.5, "the snapshot must be the picture the window shows (mean \(mean))")
        // Its pixels are CPU pixels: what a picture technique reads.
        #expect(taken.premultipliedPixels() != nil)
        #expect(taken[128, 18].luminance > 0.8, "the ring's stroke is in the snapshot")
    }

    // MARK: The live path

    /// On the live path the answer lands once the GPU is done, a frame late,
    /// each the frame it was asked for, and the ask costs one present pass on
    /// that frame, never a second render.
    @Test(.enabled(if: Snapshot.hasMetal))
    func theLivePathAnswersAFrameLateForOnePass() throws {
        let device = try #require(MTLCreateSystemDefaultDevice())
        final class Passes: SketchExtension {
            var passes: [Int] = []
            func afterFrame(_ sketch: Sketch, _ info: FrameInfo) { passes.append(info.profile.passes) }
        }
        // The same sketch without the ask, for the frame's plain pass count.
        let plain = SnapshotMarker()
        plain.reads = false
        let plainView = makeView(device, side: 256, for: plain)
        plain.setCanvasSize(width: 256, height: 256)
        let plainPasses = Passes()
        plain.extend(plainPasses)
        let plainRunner = SketchRunner(sketch: plain, view: plainView, device: device)
        plainRunner.draw(in: plainView)
        plainRunner.draw(in: plainView)
        let floor = try #require(plainPasses.passes.last)

        let sketch = SnapshotMarker()
        let view = makeView(device, side: 256, for: sketch)
        sketch.setCanvasSize(width: 256, height: 256)
        let passes = Passes()
        sketch.extend(passes)
        let runner = SketchRunner(sketch: sketch, view: view, device: device)
        runner.draw(in: view)
        #expect(sketch.seen == [nil], "nothing has come back on the first frame")
        spin { !sketch.drawer.layerReadbackResults.isEmpty }
        runner.draw(in: view)
        spin { sketch.drawer.layerReadbackResults.first??.image.flatMap(SnapshotMarker.frameShown) == 2 }
        runner.draw(in: view)
        #expect(sketch.seen == [nil, 1, 2], "each draw is handed the frame before (\(sketch.seen))")
        #expect(passes.passes.last == floor + 1, "a snapshot adds one present pass (\(passes.passes))")
        // The delivery is the frame it was asked for, at the layer's size.
        let last = try #require(sketch.drawer.layerReadbackResults.first.flatMap { $0 })
        #expect(last.pixelWidth == 256 && last.pixelHeight == 256)
    }

    // MARK: The GPU slit scan

    /// The GPU scan composes what the CPU scan composes from the same frames,
    /// under each delay: across, down, radial, and a picture as the map.
    @Test(.enabled(if: Snapshot.hasMetal),
          arguments: [("across", 0), ("down", 1), ("radial", 2), ("map", 3)])
    func theGPUSlitScanMatchesTheCPUOne(name: String, mode: Int) throws {
        func make() -> Scanned {
            let sketch = Scanned()
            switch mode {
            case 1:
                sketch.delay = .down
                sketch.cpuDelay = { $0.y }
            case 2:
                sketch.delay = .radial
                sketch.cpuDelay = { hypot($0.x - 0.5, $0.y - 0.5) / 0.7071 }
            case 3:
                let map = Image(width: 64, height: 64)
                for y in 0..<64 { for x in 0..<64 { map[x, y] = Color(white: Double(x + y) / 126) } }
                sketch.delay = .map(map)
                sketch.cpuMap = map
            default:
                break
            }
            return sketch
        }
        // Frame 10's GPU scan holds frames 3 to 10; the CPU scan a frame later
        // holds the snapshots of the same frames.
        let gpuFrame = try OllinApp.image(of: make(), frame: 10)
        let cpuFrame = try OllinApp.image(of: make(), frame: 11)
        // Measured 2026-10-25 at 0.23 to 0.25 levels under every delay: the
        // CPU side's frames went through the present's dither twice.
        let mean = try halvesDifference(gpuFrame, cpuFrame)
        #expect(mean < 0.5, "the \(name) scan on the GPU must match the CPU one (mean \(mean))")
        // And it is a scan: pixels across the layer read different frames.
        let left = pixels(of: gpuFrame)
        var distinct = Set<[UInt8]>()
        for x in stride(from: 2, to: 62, by: 4) {
            let i = (32 * 128 + x) * 4
            distinct.insert([left[i], left[i + 1], left[i + 2]])
        }
        #expect(distinct.count > 2, "a scan reads several frames across the layer")
    }

    /// Two scans of one history in a frame append the layer once: the second
    /// reads what the first appended and composes the same picture, apart
    /// from the present pass's dither, which is keyed on the pixel's place on
    /// the canvas. A second append would shift every column's frame by one,
    /// which under the turning hue reads as tens of levels.
    @Test(.enabled(if: Snapshot.hasMetal))
    func aHistoryIsAppendedOnceAFrame() throws {
        let sketch = Scanned()
        sketch.twice = true
        let frame = try OllinApp.image(of: sketch, frame: 6)
        let mean = try halvesDifference(frame, frame)     // 0.46, the dither alone (2026-10-25)
        #expect(mean < 0.6, "the second scan must read the ring the first filled (mean \(mean))")
    }

    // MARK: The glyph mosaic of a layer

    /// The mosaic of a layer, averaged on the GPU, chooses what the mosaic of
    /// the layer's snapshot chooses: the same cells, their tones within a
    /// level, and the same glyph except where a tone sits on a boundary.
    @Test(.enabled(if: Snapshot.hasMetal))
    func theMosaicOfALayerIsTheMosaicOfItsSnapshot() throws {
        let sketch = Mosaicked()
        _ = try OllinApp.image(of: sketch, frame: 2)
        try #require(!sketch.fromLayer.isEmpty, "the layer's cells came back")
        try #require(sketch.fromLayer.count == sketch.fromSnapshot.count,
                     "\(sketch.fromLayer.count) cells off the layer, \(sketch.fromSnapshot.count) off its snapshot")
        var flips = 0
        var worstTone = 0.0, worstColor = 0.0
        for (a, b) in zip(sketch.fromLayer, sketch.fromSnapshot) {
            #expect(a.column == b.column && a.row == b.row)
            worstTone = max(worstTone, abs(a.brightness - b.brightness))
            worstColor = max(worstColor, abs(a.color.red - b.color.red), abs(a.color.green - b.color.green),
                             abs(a.color.blue - b.color.blue), abs(a.color.alpha - b.color.alpha))
            if a.character != b.character { flips += 1 }
        }
        #expect(worstTone * 255 < 1.5, "a cell's tone off the layer is within a level of its snapshot's (\(worstTone * 255))")
        #expect(worstColor * 255 < 2.5, "a cell's color off the layer is within two levels (\(worstColor * 255))")
        #expect(flips * 20 <= sketch.fromLayer.count, "\(flips) of \(sketch.fromLayer.count) cells chose another glyph")
        // The first frame has no frame before to read, and says nothing.
        let first = Mosaicked()
        _ = try OllinApp.image(of: first, frame: 0)
        #expect(first.fromLayer.isEmpty && first.fromSnapshot.isEmpty)
    }

    // MARK: The page

    /// A web page has no frame before to read from, so it stops at each read
    /// and names the call.
    @Test func thePageRefusesALayerReadBackByName() throws {
        final class Snapshotting: Sketch {
            override var canvasSize: CanvasSize { .square(64) }
            override func draw() {
                let layer = makeRenderTarget()
                withTarget(layer) { fill(.white); drawCircle(32, 32, 10) }
                if let picture = layer.snapshot() { drawImage(picture, 0, 0) }
            }
        }
        final class MosaicOfALayer: Sketch {
            override var canvasSize: CanvasSize { .square(64) }
            override func draw() {
                let layer = makeRenderTarget()
                withTarget(layer) { fill(.white); drawCircle(32, 32, 10) }
                drawGlyphMosaic(layer.image, columns: 8)
            }
        }
        final class ScannedOnTheGPU: Sketch {
            var history: LayerHistory!
            override var canvasSize: CanvasSize { .square(64) }
            override func setup() { history = makeLayerHistory(capacity: 4) }
            override func draw() {
                let layer = makeRenderTarget()
                withTarget(layer) { fill(.white); drawCircle(32, 32, 10) }
                drawImage(layer.filtered(.slitScan(history)).image, 0, 0)
            }
        }
        func refusal(_ sketch: Sketch) -> WebExportRefusal? {
            do { _ = try OllinApp.recordWebFrames(of: sketch, frames: 2, fps: 30); return nil }
            catch let refusal as WebExportRefusal { return refusal }
            catch { return nil }
        }
        let snapshotting = try #require(refusal(Snapshotting()))
        #expect(snapshotting.call.contains("RenderTarget.snapshot()"), "\(snapshotting.call)")
        let mosaicked = try #require(refusal(MosaicOfALayer()))
        #expect(mosaicked.call.contains("glyphMosaic of a layer"), "\(mosaicked.call)")
        let scanned = try #require(refusal(ScannedOnTheGPU()))
        #expect(scanned.call == "the slitScan filter", "\(scanned.call)")
    }
}
