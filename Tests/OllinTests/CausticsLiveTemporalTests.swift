@testable import Ollin
import CoreGraphics
import ImageIO
import Metal
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

    private enum ProbeFailure: Error { case noDevice, noEncode, noLayer }

    /// Write a luminance plane as an 8-bit PNG (x6 gain so the dim caustic
    /// layer reads), for the debug dump alone; never part of an assertion.
    private func dumpPlane(_ plane: [Float], width: Int, height: Int, to path: String) {
        var bytes = [UInt8](repeating: 0, count: width * height)
        for i in plane.indices { bytes[i] = UInt8(min(255, max(0, plane[i] * 6 * 255))) }
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
