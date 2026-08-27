@testable import Ollin
import CoreGraphics
import ImageIO
import Metal
import simd
import Testing

/// The live caustics temporal resolve, pinned headlessly. The export path is a
/// pure function of the frame and every snapshot goes through it, which is how
/// a live-only defect (the pattern flickering and never settling under a still
/// camera) shipped invisibly. These probes drive the live encode
/// (`encodeCausticsPass(supersample: false)`) frame after frame on one
/// renderer, no drawable, and measure what the window would show: with a
/// static camera the resolved layer must stay fed, carry energy, and settle,
/// its distance to the settled reference falling as the history accumulates.
@Suite
@MainActor
struct CausticsLiveTemporalProbes {

    /// One live frame's resolved caustics layer as luminance floats plus its
    /// deposited photon count, for `frames` consecutive frames of the static
    /// probe scene.
    private func liveLuminancePlanes(frames: Int) throws -> (planes: [[Float]], photons: [UInt32]) {
        let sketch = LiveCausticProbe()
        let size = sketch.canvasSize
        let width = size.width, height = size.height
        guard let device = MTLCreateSystemDefaultDevice() else { throw ProbeFailure.noDevice }
        let renderer = try MetalRenderer(device: device,
                                         pixelFormat: sketch.colorOutput.drawablePixelFormat,
                                         sampleCount: ollinPreferredSampleCount(device),
                                         encoding: sketch.colorOutput.presentEncoding)
        sketch.setCanvasSize(width: Double(width), height: Double(height))
        sketch.setup()

        var planes: [[Float]] = []
        var photons: [UInt32] = []
        for k in 0..<frames {
            sketch.advance(time: Double(k) / 60, deltaTime: 1.0 / 60, frameRate: 60)
            sketch.performDraw()
            let drawer = sketch.drawer
            renderer.beginStatefulEncode(drawer)
            guard let cb = renderer.commandQueue.makeCommandBuffer() else { throw ProbeFailure.noEncode }
            let meshBuf = renderer.exportMeshBuffer(for: renderer.tracedMeshVertexCount(drawer))
            // The export buffer is allocated on demand and filled by the caller
            // (the upload step of the full render drives); this drive is the
            // caustics slice alone, so it copies the frame's mesh vertices in
            // itself before the commit the G-buffer and accel build read them.
            if let meshBuf, !drawer.meshVertices.isEmpty {
                drawer.meshVertices.withUnsafeBytes { raw in
                    meshBuf.contents().copyMemory(from: raw.baseAddress!, byteCount: raw.count)
                }
            }
            let shadow = renderer.encodeShadowPass(drawer, into: cb, meshBuffer: meshBuf)
            let resolved = renderer.encodeCausticsPass(
                drawer, into: cb, meshBuffer: meshBuf,
                causticAccel: shadow.causticAccel,
                causticGeoOffsets: shadow.causticGeoOffsets,
                causticGeoMats: shadow.causticGeoMats,
                width: width, height: height,
                supersample: false, pooled: false)
            guard let resolved else { throw ProbeFailure.noLayer }
            #expect(resolved.pixelFormat == .rgba16Float,
                    "the readback below decodes rgba16Float, got \(resolved.pixelFormat.rawValue)")
            // The splat pass's indirect arguments carry the deposited photon
            // count in slot 1: the emission plan's health, read back per frame
            // (the starvation defects showed here first, 13592 -> 3 in a
            // second, before any pixel could say why).
            var argsReadback: MTLBuffer?
            if let args = renderer.causticsArgs,
               let shared = device.makeBuffer(length: 16, options: .storageModeShared),
               let argBlit = cb.makeBlitCommandEncoder() {
                argBlit.copy(from: args, sourceOffset: 0, to: shared,
                             destinationOffset: 0, size: 16)
                argBlit.endEncoding()
                argsReadback = shared
            }
            let bytesPerRow = width * 8
            guard let readback = device.makeBuffer(length: bytesPerRow * height,
                                                   options: .storageModeShared),
                  let blit = cb.makeBlitCommandEncoder() else { throw ProbeFailure.noEncode }
            blit.copy(from: resolved, sourceSlice: 0, sourceLevel: 0,
                      sourceOrigin: MTLOrigin(x: 0, y: 0, z: 0),
                      sourceSize: MTLSize(width: width, height: height, depth: 1),
                      to: readback, destinationOffset: 0,
                      destinationBytesPerRow: bytesPerRow,
                      destinationBytesPerImage: bytesPerRow * height)
            blit.endEncoding()
            cb.commit()
            cb.waitUntilCompleted()
            if let argsReadback {
                let counts = argsReadback.contents().bindMemory(to: UInt32.self, capacity: 4)
                photons.append(counts[1])
            } else {
                photons.append(0)
            }

            var plane = [Float](repeating: 0, count: width * height)
            let halves = readback.contents().bindMemory(to: Float16.self,
                                                        capacity: width * height * 4)
            for i in 0..<(width * height) {
                let r = Float(halves[i * 4 + 0])
                let g = Float(halves[i * 4 + 1])
                let b = Float(halves[i * 4 + 2])
                plane[i] = 0.2126 * r + 0.7152 * g + 0.0722 * b
            }
            planes.append(plane)
            // Debug dump for eyes-on comparison: set the env var to a directory
            // and the probe writes each tenth frame's resolved layer as a PNG.
            if let dir = ProcessInfo.processInfo.environment["OLLIN_CAUSTICS_PROBE_DUMP"],
               k % 10 == 9 || k == 0 {
                dumpPlane(plane, width: width, height: height,
                          to: "\(dir)/caustics-live-frame\(String(format: "%02d", k)).png")
            }
        }
        return (planes, photons)
    }

    private func meanAbsDiff(_ a: [Float], _ b: [Float]) -> Float {
        var total: Float = 0
        for i in a.indices { total += abs(a[i] - b[i]) }
        return total / Float(a.count)
    }

    @Test(.enabled(if: Snapshot.hasMetal && Snapshot.hasRaytracing))
    func aStillCameraSettlesInsteadOfFlickering() throws {
        let (planes, photons) = try liveLuminancePlanes(frames: 40)
        // The layer must carry real energy (a probe of an empty texture would
        // pass any stability bar).
        let peak = planes[39].max() ?? 0
        #expect(peak > 0.05, "the resolved caustics layer is empty: peak \(peak)")
        // Convergence: the distance from each frame to the settled picture (the
        // mean of the last ten planes) must fall as the history accumulates. A
        // resolve that rejects its history holds every frame at the raw splat
        // churn, so early and late read the same distance.
        var reference = [Float](repeating: 0, count: planes[0].count)
        for k in 30...39 {
            for i in reference.indices { reference[i] += planes[k][i] }
        }
        for i in reference.indices { reference[i] /= 10 }
        let earlyErr = (2...5).map { meanAbsDiff(planes[$0], reference) }.reduce(0, +) / 4
        let lateErr = (34...37).map { meanAbsDiff(planes[$0], reference) }.reduce(0, +) / 4
        // And the emission plan must stay alive: a starving adaptive loop fades
        // the whole layer instead of converging it (the totals-reset and
        // floor-truncation defects both read as exactly that).
        let lateChurn = (35...39).map { meanAbsDiff(planes[$0], planes[$0 - 1]) }.reduce(0, +) / 5
        print("caustics live probe: peak \(peak), early err \(earlyErr), late err \(lateErr), "
              + "late churn \(lateChurn), photons \(photons[0]) -> \(photons[39])")
        #expect(lateErr < earlyErr * 0.6,
                "static caustics never converge: early \(earlyErr), late \(lateErr)")
        // The emission plan must stay fed: the adaptive loop once starved the
        // map within a second (an unreset budget total plus floor truncation),
        // which no export-path test could see.
        #expect(photons[39] > photons[0] / 2,
                "the adaptive plan starves: photons \(photons[0]) -> \(photons[39])")
    }

    /// The headline of the live scene: the bright point a clear ball lens throws
    /// into its own shadow, watched for long enough that the adaptive emission
    /// loop has run over a hundred times. Three things are measured, because the
    /// loop found three ways to put that spot out and each one hid the next.
    ///
    /// - The spot's own energy, in a window that follows it (its floor point is
    ///   projected with each frame's camera, so the measurement holds while the
    ///   view sways). It fell to nothing within 30 frames and never came back.
    /// - The whole layer's energy, because the spot went out as part of the
    ///   layer losing six sevenths of its light while depositing nine times the
    ///   photons: the plan was spending the budget on photons carrying almost
    ///   nothing each.
    /// - The plan against the ray budget, which is the mechanism. The trace
    ///   dispatches exactly `budget` threads, so a plan that asks for more than
    ///   that loses the rest, and the quadtree hands out tasks in traversal
    ///   order, so what is lost is always the same corner of the map. Whatever
    ///   caustic sits in that corner goes out and stays out.
    ///
    /// The camera's motion was never part of it: a still camera on this same
    /// scene collapsed on the same schedule, so the temporal resolve is not
    /// where this lived.
    @Test(.enabled(if: Snapshot.hasMetal && Snapshot.hasRaytracing))
    func theFocusedSpotSurvivesTheAdaptiveLoop() throws {
        let run = try spotEnergyRun(frames: 150)
        let early = run.spotPeaks[10...25].reduce(0, +) / 16
        let late = run.spotPeaks[130...145].reduce(0, +) / 16
        let earlyLayer = run.layerEnergy[10...25].reduce(0, +) / 16
        let lateLayer = run.layerEnergy[130...145].reduce(0, +) / 16
        let worstPlan = run.plannedRays.max() ?? 0
        print("caustics spot probe: peak by frame "
              + stride(from: 0, to: run.spotPeaks.count, by: 10)
                  .map { String(format: "%d:%.1f", $0, run.spotPeaks[$0]) }
                  .joined(separator: " "))
        print(String(format: "caustics spot probe: spot %.1f -> %.1f, layer %.0f -> %.0f, "
                     + "plan at most %d of %d rays",
                     early, late, earlyLayer, lateLayer, worstPlan, run.budget))
        #expect(early > 0.05, "the probe scene never focused a spot at all: \(early)")
        #expect(late > early * 0.5,
                "the focused spot starves: early \(early), late \(late)")
        #expect(lateLayer > earlyLayer * 0.5,
                "the caustics layer loses its light: early \(earlyLayer), late \(lateLayer)")
        #expect(worstPlan <= Int(Double(run.budget) * 1.05),
                "the emission plan asks for more rays than the trace runs, so the map's last texels in traversal order are dropped: \(worstPlan) of \(run.budget)")
    }

    /// Per live frame of the moving scene: the peak luminance inside the clear
    /// sphere's focused spot, the whole resolved layer's energy, and the ray
    /// count the emission plan asked for (the leaf counts' own sum).
    private func spotEnergyRun(frames: Int, moving: Bool = true)
        throws -> (spotPeaks: [Float], layerEnergy: [Double],
                   plannedRays: [Int], budget: Int) {
        let sketch = MovingCausticProbe()
        sketch.moves = moving
        let size = sketch.canvasSize
        let width = size.width, height = size.height
        guard let device = MTLCreateSystemDefaultDevice() else { throw ProbeFailure.noDevice }
        let renderer = try MetalRenderer(device: device,
                                         pixelFormat: sketch.colorOutput.drawablePixelFormat,
                                         sampleCount: ollinPreferredSampleCount(device),
                                         encoding: sketch.colorOutput.presentEncoding)
        sketch.setCanvasSize(width: Double(width), height: Double(height))
        sketch.setup()

        var peaks: [Float] = []
        var energies: [Double] = []
        var planned: [Int] = []
        for k in 0..<frames {
            sketch.advance(time: Double(k) / 60, deltaTime: 1.0 / 60, frameRate: 60)
            sketch.performDraw()
            let drawer = sketch.drawer
            renderer.beginStatefulEncode(drawer)
            guard let cb = renderer.commandQueue.makeCommandBuffer() else { throw ProbeFailure.noEncode }
            let meshBuf = renderer.exportMeshBuffer(for: renderer.tracedMeshVertexCount(drawer))
            if let meshBuf, !drawer.meshVertices.isEmpty {
                drawer.meshVertices.withUnsafeBytes { raw in
                    meshBuf.contents().copyMemory(from: raw.baseAddress!, byteCount: raw.count)
                }
            }
            let shadow = renderer.encodeShadowPass(drawer, into: cb, meshBuffer: meshBuf)
            let resolved = renderer.encodeCausticsPass(
                drawer, into: cb, meshBuffer: meshBuf,
                causticAccel: shadow.causticAccel,
                causticGeoOffsets: shadow.causticGeoOffsets,
                causticGeoMats: shadow.causticGeoMats,
                width: width, height: height,
                supersample: false, pooled: false)
            guard let resolved else { throw ProbeFailure.noLayer }
            // The plan's own ray count: the leaf counts summed, which is what the
            // quadtree's root holds and what the trace's thread count must cover.
            var leafReadback: MTLBuffer?
            let edge = renderer.causticsMapEdge
            if let leaves = renderer.causticsLeafCounts, edge > 0,
               let shared = device.makeBuffer(length: edge * edge * 4, options: .storageModeShared),
               let lBlit = cb.makeBlitCommandEncoder() {
                lBlit.copy(from: leaves, sourceOffset: 0, to: shared,
                           destinationOffset: 0, size: edge * edge * 4)
                lBlit.endEncoding()
                leafReadback = shared
            }
            let bytesPerRow = width * 8
            guard let readback = device.makeBuffer(length: bytesPerRow * height,
                                                   options: .storageModeShared),
                  let blit = cb.makeBlitCommandEncoder() else { throw ProbeFailure.noEncode }
            blit.copy(from: resolved, sourceSlice: 0, sourceLevel: 0,
                      sourceOrigin: MTLOrigin(x: 0, y: 0, z: 0),
                      sourceSize: MTLSize(width: width, height: height, depth: 1),
                      to: readback, destinationOffset: 0,
                      destinationBytesPerRow: bytesPerRow,
                      destinationBytesPerImage: bytesPerRow * height)
            blit.endEncoding()
            cb.commit()
            cb.waitUntilCompleted()
            if let leafReadback, edge > 0 {
                let l = leafReadback.contents().bindMemory(to: UInt32.self, capacity: edge * edge)
                var rays = 0
                for i in 0..<(edge * edge) { rays += Int(l[i]) }
                planned.append(rays)
            } else {
                planned.append(0)
            }

            let halves = readback.contents().bindMemory(to: Float16.self,
                                                        capacity: width * height * 4)
            func luminance(_ i: Int) -> Float {
                0.2126 * Float(halves[i * 4 + 0]) + 0.7152 * Float(halves[i * 4 + 1])
                    + 0.0722 * Float(halves[i * 4 + 2])
            }
            // Every fourth pixel: this is a sum compared against itself over
            // time, so a strided sample carries the same signal for a quarter of
            // the work (the readback dominates a debug build otherwise).
            var total: Double = 0
            for i in stride(from: 0, to: width * height, by: 4) { total += Double(luminance(i)) }
            energies.append(total)
            // Debug dump for eyes-on comparison: set the env var to a directory
            // and the probe writes the resolved layer at the frames that matter.
            if let dir = ProcessInfo.processInfo.environment["OLLIN_CAUSTICS_PROBE_DUMP"],
               k == 0 || k == 20 || k == frames - 1 {
                var plane = [Float](repeating: 0, count: width * height)
                for i in plane.indices { plane[i] = luminance(i) }
                dumpPlane(plane, width: width, height: height, gain: 0.02,
                          to: "\(dir)/caustics-layer-frame\(String(format: "%03d", k)).png")
            }

            // Where the spot is on screen this frame: the floor point the clear
            // sphere focuses onto, put through the frame's own camera.
            guard let camera = drawer.camera3D else { throw ProbeFailure.noLayer }
            let aspect = Double(width) / Double(height)
            let vp = camera.projectionMatrix(aspect: aspect) * camera.viewMatrix
            let clip = vp * SIMD4<Float>(MovingCausticProbe.spotOnFloor, 1)
            var peak: Float = 0
            if clip.w > 0 {
                let ndc = SIMD2(clip.x / clip.w, clip.y / clip.w)
                let cx = Int((ndc.x * 0.5 + 0.5) * Float(width))
                let cy = Int((0.5 - ndc.y * 0.5) * Float(height))
                let radius = 10
                for y in max(0, cy - radius)...min(height - 1, cy + radius) {
                    for x in max(0, cx - radius)...min(width - 1, cx + radius) {
                        peak = max(peak, luminance(y * width + x))
                    }
                }
            }
            peaks.append(peak)
        }
        return (peaks, energies, planned, renderer.causticsPhotonCapacity)
    }

    private enum ProbeFailure: Error { case noDevice, noEncode, noLayer }

    /// Write a luminance plane as an 8-bit PNG (x6 gain so the dim caustic
    /// layer reads), for the debug dump alone; never part of an assertion.
    private func dumpPlane(_ plane: [Float], width: Int, height: Int,
                           gain: Float = 6, to path: String) {
        var bytes = [UInt8](repeating: 0, count: width * height)
        for i in plane.indices { bytes[i] = UInt8(min(255, max(0, plane[i] * gain * 255))) }
        let cs = CGColorSpaceCreateDeviceGray()
        guard let provider = CGDataProvider(data: Data(bytes) as CFData),
              let image = CGImage(width: width, height: height, bitsPerComponent: 8,
                                  bitsPerPixel: 8, bytesPerRow: width, space: cs,
                                  bitmapInfo: CGBitmapInfo(rawValue: 0), provider: provider,
                                  decode: nil, shouldInterpolate: false, intent: .defaultIntent),
              let dest = CGImageDestinationCreateWithURL(
                  URL(fileURLWithPath: path) as CFURL, "public.png" as CFString, 1, nil)
        else { return }
        CGImageDestinationAddImage(dest, image, nil)
        CGImageDestinationFinalize(dest)
    }
}

/// A static-camera caustic scene: a glass ball lens over a matte floor under a
/// steep sun, nothing animated, so every frame's only variation is the photon
/// jitter the temporal resolve exists to absorb.
private final class LiveCausticProbe: Sketch {
    override var canvasSize: CanvasSize { .square(256) }

    override func draw() {
        background(Color(white: 0.05))
        perspective(eye: Vector3(0, 5.2, 3.4), target: Vector3(0, 0, 0.3),
                    fieldOfView: .pi / 3.4, near: 1, far: 30)
        directionalLight(.white, direction: Vector3(-0.05, -1, -0.02), intensity: 2)
        castShadows()
        caustics()
        withState {
            material(.glass(thickness: 2.0))
            fill(.white)
            translate(0, 1.45, 0.3)
            drawSphere(radius: 1.0)
        }
        withState {
            material(.dielectric(roughness: 0.85))
            fill(Color(white: 0.55))
            translate(0, -0.5, 0)
            drawBox(width: 18, height: 1.0, depth: 14)
        }
    }
}

/// The live scene at full size: the example's own cast (a clear ball lens, a
/// tinted one, a chrome ring, a matte floor) under its own swaying camera, which
/// is the shape the adaptive emission loop must hold up under. The canvas is the
/// default 1080 square because the loop's target and its cull cap are both
/// measured in screen pixels, so a small probe canvas is a different scene.
private final class MovingCausticProbe: Sketch {
    /// The floor point the clear sphere focuses onto: its center carried down the
    /// light's travel direction until it meets the floor's top face.
    static let spotOnFloor = SIMD3<Float>(-3.0, 0.0, -0.34)

    var moves = true

    override func draw() {
        background(Color(hex: 0x101318))
        if moves {
            cameraShowcase(.sway(amplitude: 0.2, period: .tau / 0.08),
                           target: Vector3(0, 0.6, 0), radius: 10.5, elevation: 0.42,
                           fieldOfView: .pi / 4, near: 1, far: 40)
        } else {
            perspective(eye: Vector3(0, 4.4, 9.5), target: Vector3(0, 0.6, 0),
                        fieldOfView: .pi / 4, near: 1, far: 40)
        }
        directionalLight(.white, direction: Vector3(-0.35, -1, -0.2), intensity: 2.2)
        castShadows()
        caustics()
        withState {
            material(.dielectric(roughness: 0.85))
            fill(Color(hex: 0x878c99))
            translate(0, -0.5, 0)
            drawBox(width: 26, height: 1.0, depth: 16)
        }
        withState {
            material(.glass(thickness: 2.4))
            fill(.white)
            translate(-2.4, 1.7, 0)
            drawSphere(radius: 1.2)
        }
        withState {
            material(.glass(thickness: 2.0,
                            attenuationColor: Color(hex: 0x2e8f5b),
                            attenuationDistance: 1.6))
            fill(.white)
            translate(2.5, 1.15, -0.4)
            drawSphere(radius: 1.0)
        }
        withState {
            material(.metal(roughness: 0.06))
            fill(Color(hex: 0xf2f4f8))
            translate(0.3, 0.42, 2.6)
            rotateX(.pi / 2 * 0.92)
            drawTorus(radius: 1.15, tube: 0.16)
        }
    }
}
