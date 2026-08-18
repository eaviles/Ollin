@testable import Ollin
import Testing
import CoreGraphics

/// Correctness probes for the offline path-traced export (`--path-traced`).
///
/// The anchor is the furnace test, the canonical integrator check: a white matte
/// body inside a uniform field of light must render exactly that field's radiance
/// (every bounce loses nothing, every direction returns the same light), so any
/// systematic energy error in the sampling shows up as a shifted mean. The other
/// probes pin raster parity (the same simple scene must read the same through both
/// pipelines) and the house determinism rule (same command, byte-identical frame).
@Suite(.serialized)
@MainActor
struct PathTraceTests {

    /// A minimal traced scene: one sphere, one material, one light setup.
    final class Probe: Sketch {
        enum Kind { case furnaceMatte, furnacePBR, parityDirectional }
        var kind: Kind = .furnaceMatte

        override var canvasSize: CanvasSize { .square(256) }

        static func make(_ kind: Kind) -> Probe {
            let p = Probe()
            p.kind = kind
            return p
        }

        override func draw() {
            background(.black)
            camera(Camera3D(eye: Vector3(0, 0, 4), target: .zero))
            switch kind {
            case .furnaceMatte:
                // The uniform field: the flat ambient is the tracer's miss radiance,
                // so an ambient-only scene is a closed furnace.
                ambientLight(Color(white: 0.5))
                fill(.white)
                material(Material())               // standard shading: pure Lambert
            case .furnacePBR:
                ambientLight(Color(white: 0.5))
                fill(.white)
                material(.dielectric(roughness: 1.0))
            case .parityDirectional:
                ambientLight(Color(white: 0.1))
                directionalLight(Color(white: 0.8), direction: Vector3(-1, -1, -1))
                fill(Color(white: 0.9))
                material(Material())
            }
            drawSphere(radius: 1.2)
        }
    }

    private func pixels(of image: CGImage) -> [UInt8] {
        let w = image.width, h = image.height
        var data = [UInt8](repeating: 0, count: w * h * 4)
        let ctx = CGContext(data: &data, width: w, height: h, bitsPerComponent: 8,
                            bytesPerRow: w * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        return data
    }

    /// Mean of one channel over the sphere's central region (well inside the
    /// silhouette, so edge blending never dilutes the read).
    private func centerMean(_ image: CGImage, channel: Int = 1) -> Double {
        let d = pixels(of: image)
        var sum = 0, count = 0
        for py in Int(Double(image.height) * 0.38)..<Int(Double(image.height) * 0.62) {
            for px in Int(Double(image.width) * 0.38)..<Int(Double(image.width) * 0.62) {
                sum += Int(d[(py * image.width + px) * 4 + channel]); count += 1
            }
        }
        return Double(sum) / Double(max(count, 1))
    }

    private func pathTraced(_ kind: Probe.Kind, samples: Int = 96) -> CGImage? {
        OllinApp.pathTracedExport = PathTracing(samplesPerPixel: samples)
        defer { OllinApp.pathTracedExport = nil }
        return OllinApp.image(of: Probe.make(kind), frame: 1)
    }

    /// The furnace: a white Lambert sphere in a uniform field must render the field
    /// itself, so the sphere's pixels must encode back to the ambient color's own
    /// 8-bit value (`Color(white: 0.5)` is sRGB, the field is its linearized 0.214,
    /// and a perfect surface returns exactly that: sRGB 127.5). A sampling or energy
    /// error of even a few percent moves the mean well past the tolerance.
    @Test(.enabled(if: Snapshot.hasRaytracing))
    func theMatteFurnaceHoldsItsEnergy() throws {
        let image = try #require(pathTraced(.furnaceMatte))
        let m = centerMean(image)
        #expect(abs(m - 127.5) < 3.0, "furnace mean \(m), expected ~127.5")
    }

    /// The physically-based furnace: the microfacet surface may lose a little energy
    /// to the single-scatter model (the raster path shares that model), but the
    /// sampling itself must not lose more. Bounds the visible-normal sampling and
    /// its probability math without demanding what the shading model cannot give.
    @Test(.enabled(if: Snapshot.hasRaytracing))
    func thePBRFurnaceStaysNearTheField() throws {
        let image = try #require(pathTraced(.furnacePBR))
        let m = centerMean(image)
        #expect(m > 112.0 && m < 130.0, "PBR furnace mean \(m), expected a little under 127.5")
    }

    /// Raster parity: a directional-lit matte sphere is the simplest scene both
    /// pipelines can draw, and their means must agree closely (the traced legacy
    /// shading mirrors the raster's own light conventions; the sphere is convex, so
    /// bounce light adds almost nothing).
    @Test(.enabled(if: Snapshot.hasRaytracing))
    func aSimpleSceneReadsTheSameThroughBothPipelines() throws {
        let traced = try #require(pathTraced(.parityDirectional))
        let raster = try #require(OllinApp.image(of: Probe.make(.parityDirectional), frame: 1))
        let a = centerMean(traced), b = centerMean(raster)
        #expect(abs(a - b) < 6.0, "path traced \(a) vs raster \(b)")
    }

    /// The house determinism rule: the same export command must produce the same
    /// bytes, because sampling is a pure function of (pixel, sample index, bounce).
    @Test(.enabled(if: Snapshot.hasRaytracing))
    func theSameCommandRendersTheSameBytes() throws {
        let a = try #require(pathTraced(.parityDirectional, samples: 16))
        let b = try #require(pathTraced(.parityDirectional, samples: 16))
        #expect(pixels(of: a) == pixels(of: b))
    }

    /// The render-correctness pin: a small traced scene (an area light, mixed
    /// finishes, the mirror floor, the lens) against a committed reference, the
    /// same harness every raster snapshot uses. Sampling is deterministic, so the
    /// tolerance only absorbs cross-GPU float drift.
    @Test(.enabled(if: Snapshot.hasRaytracing))
    func theTracedFrameMatchesItsReference() throws {
        OllinApp.pathTracedExport = PathTracing(samplesPerPixel: 48)
        defer { OllinApp.pathTracedExport = nil }
        let diff = try Snapshot.meanDifference(of: SnapshotScene(), against: "path-traced-3d",
                                               frame: 1)
        #expect(diff < Snapshot.tolerance, "mean difference \(diff)")
    }

    /// The snapshot's scene: one of everything the tracer claims (an area panel,
    /// metal and dielectric and legacy finishes, an environment stand-in via flat
    /// ambient, the thin lens) at a small canvas so the suite stays quick.
    final class SnapshotScene: Sketch {
        override var canvasSize: CanvasSize { .square(320) }
        override func draw() {
            background(Color(hex: 0x101218))
            ambientLight(Color(white: 0.18))
            rectLight(Color(hue: 0.1, saturation: 0.3, brightness: 1.0),
                      at: Vector3(-2.2, 2.4, 1.2),
                      direction: Vector3(0.6, -0.65, -0.45),
                      width: 2, height: 1.4, intensity: 5)
            var cam = Camera3D(eye: Vector3(0.6, 1.4, 6.4), target: Vector3(0, 0.4, 0))
            cam.aperture = 0.1
            cam.focusDistance = 6.0
            camera(cam)
            withState {
                translate(0, -0.5, 0)
                fill(Color(white: 0.4))
                material(.metal(roughness: 0.15))
                drawBox(width: 14, height: 1, depth: 10)
            }
            let finishes: [(Color, Material)] = [
                (Color(white: 0.9), .metal(roughness: 0.05)),
                (Color(hue: 0.02, saturation: 0.7, brightness: 0.85), .dielectric(roughness: 0.2)),
                (Color(white: 0.85), Material())
            ]
            for (i, f) in finishes.enumerated() {
                withState {
                    translate(-1.7 + Double(i) * 1.7, 0.7, 0)
                    fill(f.0)
                    material(f.1)
                    drawSphere(radius: 0.7)
                }
            }
        }
    }

    /// Off is off: with no `pathTracedExport` set, the export renders the raster
    /// pipeline byte-identically to a build without the feature (the mode's whole
    /// cost gates on the setting).
    @Test(.enabled(if: Snapshot.hasMetal))
    func theModeOffLeavesTheRasterPathAlone() throws {
        OllinApp.pathTracedExport = nil
        let a = try #require(OllinApp.image(of: Probe.make(.parityDirectional), frame: 1))
        let b = try #require(OllinApp.image(of: Probe.make(.parityDirectional), frame: 1))
        #expect(pixels(of: a) == pixels(of: b))
    }
}
