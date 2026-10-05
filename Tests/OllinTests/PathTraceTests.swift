@testable import Ollin
import Testing
import CoreGraphics
import Foundation
import ImageIO

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
        enum Kind { case furnaceMatte, furnacePBR, furnaceMetal, parityDirectional,
                         prismClear, prismDispersive }
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
            case .furnaceMetal:
                // The hard case for a microfacet lobe: at roughness 1 the
                // single-scatter model alone keeps ~40% of the field, and the
                // multiple-scattering energy compensation must put the rest back.
                ambientLight(Color(white: 0.5))
                fill(.white)
                material(.metal(roughness: 1.0))
            case .parityDirectional:
                ambientLight(Color(white: 0.1))
                directionalLight(Color(white: 0.8), direction: Vector3(-1, -1, -1))
                fill(Color(white: 0.9))
                material(Material())
            case .prismClear, .prismDispersive:
                // A black bar in the furnace field behind a solid glass ball: the
                // ball's lens image of the bar is the only structure in the frame.
                ambientLight(Color(white: 0.5))
                withState {
                    fill(.black)
                    material(Material())
                    translate(0, 0, -3)
                    drawBox(width: 0.9, height: 8, depth: 0.1)
                }
                fill(.white)
                material(.glass(ior: 1.8, thickness: 2.4,
                                dispersion: kind == .prismDispersive ? 1 : 0))
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

    /// The integrator probes read the raw estimate: they measure what the sampling
    /// returns, and the filter is pinned separately below. Each names `denoises`
    /// rather than leaning on its default, so changing that default later cannot
    /// quietly re-aim them.
    private func pathTraced(_ kind: Probe.Kind, samples: Int = 96) -> CGImage? {
        OllinApp.pathTracedExport = PathTracing(samplesPerPixel: samples, denoises: false)
        defer { OllinApp.pathTracedExport = nil }
        return try? OllinApp.image(of: Probe.make(kind), frame: 1)
    }

    /// The furnace: a white Lambert sphere in a uniform field must render the field
    /// itself, so the sphere's pixels must encode back to the ambient color's own
    /// 8-bit value (`Color(white: 0.5)` is sRGB, the field is its linearized 0.214,
    /// and a perfect surface returns exactly that: sRGB 127.5). A sampling or energy
    /// error of even a few percent moves the mean well past the tolerance.
    /// Mean red minus mean blue over the sphere's central region: zero through clear
    /// glass in a gray scene, and the fringe's signature through a prism.
    private func centerRedness(_ image: CGImage) -> Double {
        centerMean(image, channel: 0) - centerMean(image, channel: 2)
    }

    @Test(.enabled(if: Snapshot.hasRaytracing))
    func dispersionSplitsATracedPathByWavelength() throws {
        // Every path through clear glass in a gray scene carries a gray throughput,
        // so red and blue agree to the byte. A dispersive body hands each path one
        // wavelength (its own index and tint), and the lens image of the bar is a
        // different size in red than in blue, so the two channels part inside the
        // ball. The tint model sums to white, so a uniform backdrop alone would not
        // move this: the bar's edges are what the probe reads.
        let clear = try #require(pathTraced(.prismClear))
        let prism = try #require(pathTraced(.prismDispersive))
        let c = abs(centerRedness(clear)), p = abs(centerRedness(prism))
        #expect(c < 1.5, "clear glass should read gray: \(c)")
        #expect(p - c > 3, "expected the fringe through the prism: clear \(c), prism \(p)")
    }

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

    /// The metal furnace: a rough white metal in a uniform field. The single-scatter
    /// lobe alone keeps ~40% of the field here, so this pin is what holds the
    /// multiple-scattering energy compensation in place: the compensated lobe must
    /// hand the field back level, the same 8-bit target the matte furnace pins.
    @Test(.enabled(if: Snapshot.hasRaytracing))
    func theMetalFurnaceKeepsItsEnergy() throws {
        let image = try #require(pathTraced(.furnaceMetal))
        let m = centerMean(image)
        #expect(abs(m - 127.5) < 4.0, "metal furnace mean \(m), expected ~127.5")
    }

    /// Raster parity: a directional-lit matte sphere is the simplest scene both
    /// pipelines can draw, and their means must agree closely (the traced legacy
    /// shading mirrors the raster's own light conventions; the sphere is convex, so
    /// bounce light adds almost nothing).
    @Test(.enabled(if: Snapshot.hasRaytracing))
    func aSimpleSceneReadsTheSameThroughBothPipelines() throws {
        let traced = try #require(pathTraced(.parityDirectional))
        let raster = try OllinApp.image(of: Probe.make(.parityDirectional), frame: 1)
        let a = centerMean(traced), b = centerMean(raster)
        #expect(abs(a - b) < 6.0, "path traced \(a) vs raster \(b)")
    }

    /// The render-correctness pin: a small traced scene (an area light, mixed
    /// finishes, the mirror floor, the lens) against a committed reference, the
    /// same harness every raster snapshot uses. Sampling is deterministic, so the
    /// tolerance only absorbs cross-GPU float drift.
    @Test(.enabled(if: Snapshot.hasRaytracing))
    func theTracedFrameMatchesItsReference() throws {
        OllinApp.pathTracedExport = PathTracing(samplesPerPixel: 48, denoises: false)
        defer { OllinApp.pathTracedExport = nil }
        let diff = try Snapshot.meanDifference(of: SnapshotScene(), against: "path-traced-3d",
                                               frame: 1)
        #expect(diff < Snapshot.tolerance, "mean difference \(diff)")
    }

    /// The traced lens focuses at `focusDistance` from the eye, not a near plane
    /// farther: of two thin bright bars, one at the focus and one a near plane
    /// beyond it, the one at the focus stays sharp and the other blurs.
    @Test(.enabled(if: Snapshot.hasMetal))
    func theTracedLensFocusesAtTheDistanceFromTheEye() throws {
        OllinApp.pathTracedExport = PathTracing(samplesPerPixel: 64, denoises: false)
        defer { OllinApp.pathTracedExport = nil }
        let image = try #require(try OllinApp.image(of: FocusProbe(), frame: 1))
        let d = pixels(of: image)
        // The brightest column of each bar's row band, in the green channel.
        func peak(from x0: Int, to x1: Int) -> Int {
            var best = 0
            for x in x0 ... x1 {
                var sum = 0
                for y in 100 ... 156 { sum += Int(d[(y * image.width + x) * 4 + 1]) }
                best = max(best, sum)
            }
            return best
        }
        let atFocus = peak(from: 60, to: 100), beyond = peak(from: 156, to: 196)
        #expect(atFocus > beyond * 3 / 2,
                "the bar at the focus peaks at \(atFocus), the one a near plane beyond it at \(beyond)")
    }

    /// Two thin bright bars in a black scene: one at the focus, 6 from the eye, and
    /// one at 7, where a lens focused a near plane too far would land.
    final class FocusProbe: Sketch {
        override var canvasSize: CanvasSize { .square(256) }
        override func draw() {
            background(.black)
            var cam = Camera3D.perspective(eye: Vector3(0, 0, 6), target: .zero,
                                           fieldOfView: .pi / 4, near: 1, far: 20)
            cam.aperture = 0.5
            cam.focusDistance = 6
            camera(cam)
            let F = 128 / tan(Double.pi / 8)   // the focal length in pixels
            // Dim enough that a blurred bar's spread shows below white: a bright
            // one would saturate sharp and blurred alike.
            fill(.white)
            for (px, d) in [(-48.0, 6.0), (48.0, 7.0)] {
                let w = 1.5 * d / F, h = 120 * d / F
                withState {
                    translate(px * d / F, 0, 6 - d)
                    drawMesh(Mesh.box(width: w, height: h, depth: 0.02).glowing(0.2))
                }
            }
        }
    }

    /// The snapshot's scene: one of everything the tracer claims (an area panel,
    /// metal and dielectric and legacy finishes, an environment stand-in via flat
    /// ambient, the thin lens) at a small canvas so the suite stays quick.
    final class SnapshotScene: Sketch {
        override var canvasSize: CanvasSize { .square(320) }
        override func draw() {
            background(Color(hex: 0x101218))
            ambientLight(Color(white: 0.18))
            rectangleLight(Color(hue: 0.1, saturation: 0.3, brightness: 1.0),
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

    // MARK: - Glass, textures, and emissive meshes through the trace

    /// The scenes for the traced glass / texture / mesh-light probes.
    final class SliceProbe: Sketch {
        enum Kind {
            case glassFurnace          // a solid clear glass sphere in the uniform field
            case glassShadow           // a floor lit through a clear pane
            case redGlassShadow        // the same, through a red pane
            case opaqueShadow          // the same pane, opaque (the comparison anchor)
            case texturedSphere        // a two-tone textured sphere (parity vs raster)
            case emissivePanel         // a glowing panel over a matte floor, no lights
            case selfGlowQuad          // a vertex-colored quad glowing in its own colors, no lights
            case everything            // all three at once (the determinism scene)
        }
        var kind: Kind = .glassFurnace

        override var canvasSize: CanvasSize { .square(256) }

        /// The emissive panel's factor: `srgbToLinear` of this is the radiance the
        /// analytic check below prices.
        static let panelFactor = 6.0

        static func make(_ kind: Kind) -> SliceProbe {
            let p = SliceProbe()
            p.kind = kind
            return p
        }

        /// A 64x64 texture: left half red, right half blue.
        static let twoTone: Image = {
            var bytes = [UInt8]()
            bytes.reserveCapacity(64 * 64 * 4)
            for y in 0..<64 {
                for x in 0..<64 {
                    bytes.append(x < 32 ? 255 : 0)
                    bytes.append(0)
                    bytes.append(x < 32 ? 0 : 255)
                    bytes.append(255)
                }
            }
            return Image(width: 64, height: 64, premultipliedRGBA: bytes)!
        }()

        private func shadowSet(pane: (Color, Material)) {
            ambientLight(Color(white: 0.02))
            directionalLight(Color(white: 0.85), direction: Vector3(-1, -1, 0))
            camera(Camera3D(eye: Vector3(0, 6, 1.2), target: .zero))
            withState {
                translate(0, -0.5, 0)
                fill(Color(white: 0.4))
                material(Material())
                drawBox(width: 12, height: 1, depth: 12)
            }
            // The pane sits up and to the right, so its 45-degree shadow lands on
            // the floor centered at the origin while the pane itself projects well
            // outside the probe region in the top-down view.
            withState {
                translate(2.6, 2.6, 0)
                fill(pane.0)
                material(pane.1)
                drawBox(width: 2.6, height: 0.06, depth: 2.6)
            }
        }

        private func emissivePanelMesh() -> Mesh {
            var panel = Mesh.box(width: 0.4, height: 0.05, depth: 0.4)
            let f = Self.panelFactor
            panel.material = MeshMaterial(emissiveColor: Color(red: f, green: f, blue: f))
            return panel
        }

        override func draw() {
            background(.black)
            switch kind {
            case .glassFurnace:
                ambientLight(Color(white: 0.5))
                camera(Camera3D(eye: Vector3(0, 0, 4), target: .zero))
                fill(.white)
                material(.glass(thickness: 1))
                drawSphere(radius: 1.2)
            case .glassShadow:
                shadowSet(pane: (.white, .glass()))
            case .redGlassShadow:
                shadowSet(pane: (Color(red: 1, green: 0.15, blue: 0.15), .glass()))
            case .opaqueShadow:
                shadowSet(pane: (.white, Material()))
            case .texturedSphere:
                ambientLight(Color(white: 0.5))
                camera(Camera3D(eye: Vector3(0, 0, 4), target: .zero))
                fill(.white)
                material(Material())
                drawMesh(Mesh.sphere(radius: 1.2).textured(Self.twoTone))
            case .emissivePanel:
                ambientLight(.black)
                // The target sits on the floor under the panel, so the image
                // center is exactly the point the analytic check prices.
                camera(Camera3D(eye: Vector3(0, 2.2, 4.5), target: .zero))
                withState {
                    translate(0, -0.5, 0)
                    fill(Color(white: 0.5))
                    material(Material())
                    drawBox(width: 8, height: 1, depth: 8)
                }
                withState {
                    translate(0, 1.5, 0)
                    fill(.white)
                    material(Material())
                    drawMesh(emissivePanelMesh())
                }
            case .selfGlowQuad:
                // Red on the left, blue on the right, no light at all: only
                // the surface's own glow can put color on the frame.
                ambientLight(.black)
                camera(Camera3D(eye: Vector3(0, 0, 3), target: .zero))
                fill(.white)
                material(Material())
                var quad = Mesh(positions: [Vector3(-1, -1, 0), Vector3(1, -1, 0),
                                            Vector3(1, 1, 0), Vector3(-1, 1, 0)],
                                normals: [.unitZ, .unitZ, .unitZ, .unitZ],
                                indices: [0, 1, 2, 0, 2, 3])
                quad.colors = [.red, .blue, .blue, .red]
                drawMesh(quad.glowing(1))
            case .everything:
                ambientLight(Color(white: 0.1))
                directionalLight(Color(white: 0.5), direction: Vector3(-1, -1, -0.5))
                camera(Camera3D(eye: Vector3(0, 1.6, 5), target: Vector3(0, 0.4, 0)))
                withState {
                    translate(0, -0.5, 0)
                    fill(.white)
                    material(Material())
                    drawMesh(Mesh.box(width: 10, height: 1, depth: 8).textured(Self.twoTone))
                }
                withState {
                    translate(-0.9, 0.7, 0)
                    fill(Color(red: 1, green: 0.4, blue: 0.3))
                    material(.glass(thickness: 1))
                    drawSphere(radius: 0.7)
                }
                withState {
                    translate(0.9, 1.4, -0.4)
                    drawMesh(emissivePanelMesh())
                }
            }
        }
    }

    /// Mean of one channel over an arbitrary fractional region of the image.
    private func regionMean(_ image: CGImage, x0: Double, x1: Double,
                            y0: Double, y1: Double, channel: Int = 1) -> Double {
        let d = pixels(of: image)
        var sum = 0, count = 0
        for py in Int(Double(image.height) * y0)..<Int(Double(image.height) * y1) {
            for px in Int(Double(image.width) * x0)..<Int(Double(image.width) * x1) {
                sum += Int(d[(py * image.width + px) * 4 + channel]); count += 1
            }
        }
        return Double(sum) / Double(max(count, 1))
    }

    /// The fireflies in a region: how many of its pixels read more than `above`
    /// levels over the region's median green, which is what a rare bright path
    /// leaves and ordinary sampling noise does not.
    private func regionOutliers(_ image: CGImage, x0: Double, x1: Double,
                                y0: Double, y1: Double, above: Int) -> Int {
        let d = pixels(of: image)
        var values: [Int] = []
        for py in Int(Double(image.height) * y0)..<Int(Double(image.height) * y1) {
            for px in Int(Double(image.width) * x0)..<Int(Double(image.width) * x1) {
                values.append(Int(d[(py * image.width + px) * 4 + 1]))
            }
        }
        guard !values.isEmpty else { return 0 }
        let median = values.sorted()[values.count / 2]
        return values.filter { $0 > median + above }.count
    }

    /// Relative luminance noise over a region: per-pixel green-channel standard
    /// deviation over the mean (the mesh-light variance probe).
    private func regionRelativeNoise(_ image: CGImage, x0: Double, x1: Double,
                                     y0: Double, y1: Double) -> Double {
        let d = pixels(of: image)
        var values: [Double] = []
        for py in Int(Double(image.height) * y0)..<Int(Double(image.height) * y1) {
            for px in Int(Double(image.width) * x0)..<Int(Double(image.width) * x1) {
                values.append(Double(d[(py * image.width + px) * 4 + 1]))
            }
        }
        let mean = values.reduce(0, +) / Double(max(values.count, 1))
        guard mean > 0 else { return .infinity }
        let variance = values.reduce(0) { $0 + ($1 - mean) * ($1 - mean) }
                     / Double(max(values.count, 1))
        return variance.squareRoot() / mean
    }

    private func pathTracedSlice(_ kind: SliceProbe.Kind, samples: Int = 96,
                                 depth: Int = 8) -> CGImage? {
        OllinApp.pathTracedExport = PathTracing(samplesPerPixel: samples, maxDepth: depth,
                                                denoises: false)
        defer { OllinApp.pathTracedExport = nil }
        return try? OllinApp.image(of: SliceProbe.make(kind), frame: 1)
    }

    /// The glass furnace: a solid clear glass sphere in the uniform field must
    /// render the field, because a lossless dielectric redirects light without
    /// absorbing any. Every piece of the transmission path (the Fresnel split,
    /// Snell's bend, total internal reflection, the microfacet weight) has to
    /// conserve energy for the mean to stay put.
    @Test(.enabled(if: Snapshot.hasRaytracing))
    func theGlassFurnaceHoldsItsEnergy() throws {
        let image = try #require(pathTracedSlice(.glassFurnace, samples: 128, depth: 12))
        let m = centerMean(image)
        #expect(abs(m - 127.5) < 4.0, "glass furnace mean \(m), expected ~127.5")
    }

    /// The transparent shadow: a floor point lit through a clear pane must read
    /// far brighter than the same point under an opaque pane (the walk passes the
    /// light through instead of stopping at the silhouette), and a red pane must
    /// throw a red shadow (the tint rides the visibility, not just the view).
    @Test(.enabled(if: Snapshot.hasRaytracing))
    func glassPassesLightIntoItsShadow() throws {
        let glass = try #require(pathTracedSlice(.glassShadow, samples: 48))
        let opaque = try #require(pathTracedSlice(.opaqueShadow, samples: 48))
        // Compare in linear light (the sRGB curve compresses exactly the dark
        // region a shadow lives in); the opaque shadow keeps its real bounce
        // light, so the ratio is against that, not against black.
        let g = Color.srgbToLinear(centerMean(glass) / 255)
        let o = Color.srgbToLinear(centerMean(opaque) / 255)
        #expect(g > 4.0 * o, "through glass \(g) vs opaque \(o) (linear)")
        let red = try #require(pathTracedSlice(.redGlassShadow, samples: 48))
        let r = Color.srgbToLinear(centerMean(red, channel: 0) / 255)
        let b = Color.srgbToLinear(centerMean(red, channel: 2) / 255)
        #expect(r > 3.0 * b, "red shadow reads r \(r) vs b \(b) (linear)")
    }

    /// Image maps at a traced hit: a two-tone textured sphere must read the same
    /// through the trace as through the raster pipeline, on both halves, so the
    /// uv fetch, the sample orientation, and the color pipeline all line up.
    @Test(.enabled(if: Snapshot.hasRaytracing))
    func aTexturedMeshKeepsItsPictureThroughTheTrace() throws {
        let traced = try #require(pathTracedSlice(.texturedSphere))
        OllinApp.pathTracedExport = nil
        let raster = try OllinApp.image(of: SliceProbe.make(.texturedSphere), frame: 1)
        for channel in [0, 2] {
            let tl = regionMean(traced, x0: 0.34, x1: 0.44, y0: 0.44, y1: 0.56, channel: channel)
            let rl = regionMean(raster, x0: 0.34, x1: 0.44, y0: 0.44, y1: 0.56, channel: channel)
            #expect(abs(tl - rl) < 14.0, "left channel \(channel): traced \(tl) vs raster \(rl)")
            let tr = regionMean(traced, x0: 0.56, x1: 0.66, y0: 0.44, y1: 0.56, channel: channel)
            let rr = regionMean(raster, x0: 0.56, x1: 0.66, y0: 0.44, y1: 0.56, channel: channel)
            #expect(abs(tr - rr) < 14.0, "right channel \(channel): traced \(tr) vs raster \(rr)")
        }
    }

    /// The mesh light: a glowing panel over a matte floor, no other light at all.
    /// The floor under the panel must match the analytic small-emitter irradiance
    /// (radiance x area x cos^2 / d^2, through the floor's Lambert albedo / pi),
    /// which a double-counted or mis-priced strategy misses by a large factor, and
    /// it must be *smooth* at a sample count where waiting for lucky lobe hits
    /// would still be speckle (the reason the sampler exists).
    @Test(.enabled(if: Snapshot.hasRaytracing))
    func anEmissiveMeshLightsTheFloorSmoothly() throws {
        let image = try #require(pathTracedSlice(.emissivePanel, samples: 32))
        // The analytic expectation at the floor point under the panel's center.
        let radiance = Color.srgbToLinear(SliceProbe.panelFactor)
        let area = 0.4 * 0.4
        let d = 1.475           // panel underside (1.5 - 0.025) to the floor at 0
        let albedo = Color.srgbToLinear(0.5)
        let expected = radiance * area / (d * d) * albedo / .pi
        let mean = regionMean(image, x0: 0.47, x1: 0.53, y0: 0.47, y1: 0.53)
        let measured = Color.srgbToLinear(mean / 255)
        #expect(abs(measured - expected) < expected * 0.18,
                "floor reads \(measured) linear, expected ~\(expected)")
        let noise = regionRelativeNoise(image, x0: 0.44, x1: 0.56, y0: 0.44, y1: 0.56)
        #expect(noise < 0.35, "relative noise \(noise) at 32 spp")
    }

    /// The surface's own glow through the trace: a hit adds `emissiveIntensity`
    /// times its albedo after the maps, so a vertex-colored quad under no light
    /// at all traces red on its left and blue on its right, each side in its own
    /// hue, the way the raster fragment shows it.
    @Test(.enabled(if: Snapshot.hasRaytracing))
    func aSurfaceGlowingInItsOwnColorTracesEachHue() throws {
        let image = try #require(pathTracedSlice(.selfGlowQuad, samples: 16, depth: 2))
        let leftRed = regionMean(image, x0: 0.30, x1: 0.36, y0: 0.47, y1: 0.53, channel: 0)
        let leftBlue = regionMean(image, x0: 0.30, x1: 0.36, y0: 0.47, y1: 0.53, channel: 2)
        let rightRed = regionMean(image, x0: 0.64, x1: 0.70, y0: 0.47, y1: 0.53, channel: 0)
        let rightBlue = regionMean(image, x0: 0.64, x1: 0.70, y0: 0.47, y1: 0.53, channel: 2)
        #expect(leftRed > 120 && leftRed > leftBlue + 60, "the left traces red, got \(leftRed) / \(leftBlue)")
        #expect(rightBlue > 120 && rightBlue > rightRed + 60, "the right traces blue, got \(rightRed) / \(rightBlue)")
    }

    /// The house determinism rule: the same export command must produce the same
    /// bytes, because sampling is a pure function of (pixel, sample index, bounce).
    /// The whole slice stays deterministic: glass, a textured floor, and a mesh
    /// light in one scene render byte-identically across runs (the binary
    /// searches, the stochastic lobe mixes, and the transparent walk are all
    /// pure functions of the sample stream). The scene's ambient field, directional
    /// light, and plain matte finish are the simple case's too.
    @Test(.enabled(if: Snapshot.hasRaytracing))
    func theNewPathsStayDeterministic() throws {
        let a = try #require(pathTracedSlice(.everything, samples: 12))
        let b = try #require(pathTracedSlice(.everything, samples: 12))
        #expect(pixels(of: a) == pixels(of: b))
    }

    // MARK: - Surface maps through the trace

    /// The scenes for the traced surface-map probes: each map kind staged so its
    /// effect is either analytically exact or pinned against the raster pipeline,
    /// which reads the same maps through the surface-mapped fragment.
    final class MapsProbe: Sketch {
        enum Kind {
            case normalMapped          // half-tilted map on a face, oblique light
            case normalFlat            // the same face, no map (the comparison)
            case mrMapped              // a constant metallic-roughness map
            case mrFactors             // the same surface carried as bare factors
            case occlusionBlack        // a fully-occluding map in the furnace
            case occlusionWhite        // the identity map in the furnace
            case emissiveHeadOn        // a gray emissive map viewed straight on
            case emissiveFloor         // the analytic mesh-light floor, map-dimmed
            case triplanarFace         // the projected two-tone, trace vs raster
            case mapsEverything        // all of it at once (the determinism scene)
        }
        var kind: Kind = .normalFlat

        override var canvasSize: CanvasSize { .square(256) }

        static func make(_ kind: Kind) -> MapsProbe {
            let p = MapsProbe()
            p.kind = kind
            return p
        }

        /// A solid-color RGBA image (the constant-map builder).
        static func constant(_ r: UInt8, _ g: UInt8, _ b: UInt8) -> Image {
            var bytes = [UInt8]()
            bytes.reserveCapacity(16 * 16 * 4)
            for _ in 0..<(16 * 16) { bytes.append(contentsOf: [r, g, b, 255]) }
            return Image(width: 16, height: 16, premultipliedRGBA: bytes)!
        }

        /// A normal map whose left half leans 45° one way along u and whose right
        /// half leans the other: under an oblique light the two halves must shade
        /// apart by the bent cosine, and identically through both pipelines.
        static let halfTilt: Image = {
            var bytes = [UInt8]()
            bytes.reserveCapacity(64 * 64 * 4)
            for _ in 0..<64 {
                for x in 0..<64 {
                    bytes.append(x < 32 ? 218 : 37)   // ±0.707 in tangent x
                    bytes.append(128)
                    bytes.append(218)                 // 0.707 up
                    bytes.append(255)
                }
            }
            return Image(width: 64, height: 64, premultipliedRGBA: bytes)!
        }()

        /// Metallic-roughness, glTF packing: roughness 102/255 = 0.4 in g,
        /// metallic 1 in b (chosen so the byte decodes to the comparator's
        /// factor exactly).
        static let mrMap = constant(0, 102, 255)
        static let occlusionZero = constant(0, 0, 0)
        static let occlusionOne = constant(255, 255, 255)
        /// Emissive, sRGB: 188 decodes to ~0.502 linear, the dimming the two
        /// emissive probes price.
        static let emissiveGray = constant(188, 188, 188)
        static let emissiveGrayLinear = Color.srgbToLinear(188.0 / 255.0)

        private func frontFace(_ mesh: Mesh, fill fillColor: Color = .white) {
            camera(Camera3D(eye: Vector3(0, 0, 4), target: .zero))
            fill(fillColor)
            drawMesh(mesh)
        }

        /// A uv-carrying square face turned toward the camera (`Mesh.plane` faces
        /// +y with u along +x; the quarter turn about x brings it to +z with u
        /// still along world x and v running down the image).
        private func facingPlane(_ size: Double, dress: (Mesh) -> Mesh) {
            camera(Camera3D(eye: Vector3(0, 0, 4), target: .zero))
            withState {
                rotateX(.pi / 2)
                drawMesh(dress(Mesh.plane(width: size, depth: size)))
            }
        }

        override func draw() {
            background(.black)
            switch kind {
            case .normalMapped, .normalFlat:
                // An oblique light from the right: the half leaning toward it
                // catches nearly full light, the half leaning away falls to the
                // ambient floor.
                ambientLight(Color(white: 0.05))
                directionalLight(Color(white: 0.8), direction: Vector3(-1, 0, -0.6))
                material(Material())
                fill(Color(white: 0.9))
                let mapped = kind == .normalMapped
                facingPlane(3) { mapped ? $0.normalMapped(Self.halfTilt) : $0 }
            case .mrMapped, .mrFactors:
                ambientLight(Color(white: 0.1))
                directionalLight(Color(white: 0.8), direction: Vector3(-1, -1, -1))
                if kind == .mrMapped {
                    material(.physicallyBased(metallic: 1, roughness: 1))
                    camera(Camera3D(eye: Vector3(0, 0, 4), target: .zero))
                    fill(Color(white: 0.9))
                    drawMesh(Mesh.sphere(radius: 1.2).surfaceMapped(metallicRoughness: Self.mrMap))
                } else {
                    material(.physicallyBased(metallic: 1, roughness: 0.4))
                    camera(Camera3D(eye: Vector3(0, 0, 4), target: .zero))
                    fill(Color(white: 0.9))
                    drawSphere(radius: 1.2)
                }
            case .occlusionBlack, .occlusionWhite:
                // The furnace again: the occlusion map dims exactly the ambient
                // share, which in this scene is all the light there is.
                ambientLight(Color(white: 0.5))
                material(Material())
                let map = kind == .occlusionBlack ? Self.occlusionZero : Self.occlusionOne
                frontFace(Mesh.sphere(radius: 1.2).surfaceMapped(occlusion: map))
            case .emissiveHeadOn:
                // No lights at all: the panel's pixels are the factor (white)
                // times the map's linear value, an exact byte expectation.
                ambientLight(.black)
                material(Material())
                fill(.white)
                facingPlane(3) {
                    $0.surfaceMapped(emissive: Self.emissiveGray, emissiveColor: .white)
                }
            case .emissiveFloor:
                // The mesh-light analytic probe, with the panel's glow carried
                // through a gray map instead of the bare factor.
                ambientLight(.black)
                camera(Camera3D(eye: Vector3(0, 2.2, 4.5), target: .zero))
                withState {
                    translate(0, -0.5, 0)
                    fill(Color(white: 0.5))
                    material(Material())
                    drawBox(width: 8, height: 1, depth: 8)
                }
                withState {
                    // A flat emitting square (emission is two-sided, so the
                    // underside lights the floor); a plane rather than a slab
                    // because the map needs the plane's uvs.
                    translate(0, 1.5, 0)
                    fill(.white)
                    material(Material())
                    let f = SliceProbe.panelFactor
                    drawMesh(Mesh.plane(width: 0.4, depth: 0.4)
                        .surfaceMapped(emissive: Self.emissiveGray,
                                       emissiveColor: Color(red: f, green: f, blue: f)))
                }
            case .triplanarFace:
                ambientLight(Color(white: 0.5))
                material(Material())
                frontFace(Mesh.box(width: 3, height: 3, depth: 1)
                    .triplanarTextured(SliceProbe.twoTone, scale: 3))
            case .mapsEverything:
                ambientLight(Color(white: 0.15))
                directionalLight(Color(white: 0.6), direction: Vector3(-1, -1, -0.5))
                camera(Camera3D(eye: Vector3(0, 1.4, 5), target: Vector3(0, 0.4, 0)))
                withState {
                    translate(0, -0.5, 0)
                    fill(.white)
                    material(Material())
                    drawMesh(Mesh.box(width: 10, height: 1, depth: 8)
                        .triplanarTextured(SliceProbe.twoTone, scale: 4))
                }
                withState {
                    translate(-0.9, 0.7, 0)
                    fill(Color(white: 0.9))
                    material(.physicallyBased(metallic: 1, roughness: 1))
                    drawMesh(Mesh.sphere(radius: 0.7)
                        .normalMapped(Self.halfTilt)
                        .surfaceMapped(metallicRoughness: Self.mrMap,
                                       occlusion: Self.occlusionOne))
                }
                withState {
                    translate(0.9, 1.2, -0.4)
                    rotateX(.pi / 2)
                    fill(.white)
                    material(Material())
                    drawMesh(Mesh.plane(width: 0.5, depth: 0.5)
                        .surfaceMapped(emissive: Self.emissiveGray, emissiveColor: .white))
                }
            }
        }
    }

    private func pathTracedMaps(_ kind: MapsProbe.Kind, samples: Int = 96,
                                depth: Int = 8) -> CGImage? {
        OllinApp.pathTracedExport = PathTracing(samplesPerPixel: samples, maxDepth: depth,
                                                denoises: false)
        defer { OllinApp.pathTracedExport = nil }
        return try? OllinApp.image(of: MapsProbe.make(kind), frame: 1)
    }

    /// The normal map through the trace: the half-tilted face must shade its two
    /// halves apart (the bend reaches the lighting), and each half must read the
    /// same through the trace as through the raster normal-mapped pipeline (the
    /// same interpolated tangent frame, the same bend, the same light).
    @Test(.enabled(if: Snapshot.hasRaytracing))
    func aNormalMapBendsTheTracedLight() throws {
        let traced = try #require(pathTracedMaps(.normalMapped))
        OllinApp.pathTracedExport = nil
        let raster = try OllinApp.image(of: MapsProbe.make(.normalMapped), frame: 1)
        let tl = regionMean(traced, x0: 0.30, x1: 0.42, y0: 0.42, y1: 0.58)
        let tr = regionMean(traced, x0: 0.58, x1: 0.70, y0: 0.42, y1: 0.58)
        #expect(abs(tl - tr) > 40.0, "the tilted halves read \(tl) vs \(tr); the bend is missing")
        let rl = regionMean(raster, x0: 0.30, x1: 0.42, y0: 0.42, y1: 0.58)
        let rr = regionMean(raster, x0: 0.58, x1: 0.70, y0: 0.42, y1: 0.58)
        #expect(abs(tl - rl) < 10.0, "left half: traced \(tl) vs raster \(rl)")
        #expect(abs(tr - rr) < 10.0, "right half: traced \(tr) vs raster \(rr)")
    }

    /// The metallic-roughness map: a constant map whose channels decode to exact
    /// factors must render the same as the factors carried in the finish (the
    /// sampled g/b reach the same roughness/metalness the sampler and both
    /// heuristic sides read).
    @Test(.enabled(if: Snapshot.hasRaytracing))
    func aMetallicRoughnessMapEqualsItsFactors() throws {
        let mapped = try #require(pathTracedMaps(.mrMapped))
        let factors = try #require(pathTracedMaps(.mrFactors))
        let a = centerMean(mapped), b = centerMean(factors)
        #expect(abs(a - b) < 3.0, "mapped \(a) vs factors \(b)")
    }

    /// The occlusion map dims the environment share and nothing else: in the
    /// ambient furnace that share is all the light, so the fully-occluding map
    /// turns the sphere black while the identity map leaves the furnace exact.
    @Test(.enabled(if: Snapshot.hasRaytracing))
    func anOcclusionMapDimsTheAmbientShare() throws {
        let black = try #require(pathTracedMaps(.occlusionBlack))
        let white = try #require(pathTracedMaps(.occlusionWhite))
        let mb = centerMean(black), mw = centerMean(white)
        #expect(mb < 4.0, "fully occluded furnace reads \(mb), expected ~0")
        #expect(abs(mw - 127.5) < 3.0, "identity-occluded furnace reads \(mw), expected ~127.5")
    }

    /// The emissive map head-on: with a white factor and a constant gray map the
    /// panel's radiance is exactly the map's linear value, an analytic byte.
    @Test(.enabled(if: Snapshot.hasRaytracing))
    func anEmissiveMapSetsTheGlowExactly() throws {
        let image = try #require(pathTracedMaps(.emissiveHeadOn, samples: 32))
        let m = centerMean(image)
        let expected = 188.0
        #expect(abs(m - expected) < 3.0, "mapped glow reads \(m), expected ~\(expected)")
    }

    /// The emissive map through the light sampler: the analytic floor probe again,
    /// its expectation scaled by the map's linear gray, so the next-event samples
    /// carry the mapped radiance while the selection keeps pricing the factor.
    @Test(.enabled(if: Snapshot.hasRaytracing))
    func aMappedEmitterLightsTheFloorByItsMap() throws {
        let image = try #require(pathTracedMaps(.emissiveFloor, samples: 48))
        let radiance = Color.srgbToLinear(SliceProbe.panelFactor) * MapsProbe.emissiveGrayLinear
        let area = 0.4 * 0.4
        let d = 1.5             // the emitting plane sits at y 1.5, the floor at 0
        let albedo = Color.srgbToLinear(0.5)
        let expected = radiance * area / (d * d) * albedo / .pi
        let mean = regionMean(image, x0: 0.47, x1: 0.53, y0: 0.47, y1: 0.53)
        let measured = Color.srgbToLinear(mean / 255)
        #expect(abs(measured - expected) < expected * 0.18,
                "floor reads \(measured) linear, expected ~\(expected)")
    }

    /// The triplanar projection at a traced hit: the projected two-tone must show
    /// its two colors apart on the face (the world-space projection reaches the
    /// hit, not a smeared corner texel) and match the raster's own projection
    /// region for region.
    @Test(.enabled(if: Snapshot.hasRaytracing))
    func aTriplanarMeshKeepsItsProjectionThroughTheTrace() throws {
        let traced = try #require(pathTracedMaps(.triplanarFace))
        OllinApp.pathTracedExport = nil
        let raster = try OllinApp.image(of: MapsProbe.make(.triplanarFace), frame: 1)
        var apart = 0.0
        for channel in [0, 2] {
            let tl = regionMean(traced, x0: 0.30, x1: 0.42, y0: 0.42, y1: 0.58, channel: channel)
            let rl = regionMean(raster, x0: 0.30, x1: 0.42, y0: 0.42, y1: 0.58, channel: channel)
            #expect(abs(tl - rl) < 14.0, "left channel \(channel): traced \(tl) vs raster \(rl)")
            let tr = regionMean(traced, x0: 0.58, x1: 0.70, y0: 0.42, y1: 0.58, channel: channel)
            let rr = regionMean(raster, x0: 0.58, x1: 0.70, y0: 0.42, y1: 0.58, channel: channel)
            #expect(abs(tr - rr) < 14.0, "right channel \(channel): traced \(tr) vs raster \(rr)")
            apart = max(apart, abs(tl - tr))
        }
        #expect(apart > 40.0, "the projected halves read \(apart) apart; the projection is missing")
    }

    /// The mapped paths stay deterministic: every map kind in one scene renders
    /// byte-identically across runs.
    @Test(.enabled(if: Snapshot.hasRaytracing))
    func theMappedPathsStayDeterministic() throws {
        let a = try #require(pathTracedMaps(.mapsEverything, samples: 12))
        let b = try #require(pathTracedMaps(.mapsEverything, samples: 12))
        #expect(pixels(of: a) == pixels(of: b))
    }

    // MARK: - The grain filter

    /// Scenes built to be grainy at a low sample count. One small bright panel is
    /// the only light in the room, so most of what the picture shows arrived after
    /// a bounce and a thin render speckles. The second kind puts a hard two-tone
    /// texture in front of the camera under the same light: that edge belongs to
    /// the surface, not to the light, so the filter must leave it alone.
    final class GrainProbe: Sketch {
        enum Kind { case room, splitFace }
        var kind: Kind = .room

        override var canvasSize: CanvasSize { .square(160) }

        static func make(_ kind: Kind) -> GrainProbe {
            let p = GrainProbe()
            p.kind = kind
            return p
        }

        /// A hard vertical split, white against near-black, with nothing gradual
        /// anywhere: a filter that blurs across it cannot hide.
        static let split: Image = {
            var bytes = [UInt8]()
            bytes.reserveCapacity(64 * 64 * 4)
            for _ in 0..<64 {
                for x in 0..<64 {
                    let v: UInt8 = x < 32 ? 245 : 20
                    bytes.append(contentsOf: [v, v, v, 255])
                }
            }
            return Image(width: 64, height: 64, premultipliedRGBA: bytes)!
        }()

        /// The one light: small, bright, and off to the side, which is the shape
        /// that makes an unfinished render speckle.
        private func oneSmallPanel() {
            ambientLight(Color(white: 0.03))
            rectangleLight(Color(white: 7), at: Vector3(1.7, 2.4, 1.6),
                      direction: Vector3(-0.6, -1, -0.6), width: 0.45, height: 0.45)
        }

        override func draw() {
            background(.black)
            oneSmallPanel()
            fill(Color(white: 0.75))
            material(Material())
            switch kind {
            case .room:
                camera(Camera3D(eye: Vector3(0, 1.3, 4), target: Vector3(0, 0.35, 0)))
                withState {
                    translate(0, -0.55, 0)
                    drawBox(width: 9, height: 0.6, depth: 9)
                }
                withState {
                    translate(0, 0.45, 0)
                    drawSphere(radius: 0.9)
                }
            case .splitFace:
                camera(Camera3D(eye: Vector3(0, 0, 3.6), target: .zero))
                withState {
                    rotateX(.pi / 2)
                    drawMesh(Mesh.plane(width: 3.4, depth: 3.4).textured(Self.split))
                }
            }
        }
    }

    private func pathTracedGrain(_ kind: GrainProbe.Kind, samples: Int,
                                 denoises: Bool) -> CGImage? {
        OllinApp.pathTracedExport = PathTracing(samplesPerPixel: samples, denoises: denoises)
        defer { OllinApp.pathTracedExport = nil }
        return try? OllinApp.image(of: GrainProbe.make(kind), frame: 1)
    }

    /// How far two renders of the same frame sit apart, in 8-bit levels.
    private func rootMeanSquare(_ a: CGImage, _ b: CGImage) -> Double {
        let x = pixels(of: a), y = pixels(of: b)
        var sum = 0.0
        var count = 0
        for i in stride(from: 0, to: min(x.count, y.count), by: 4) {
            for c in 0..<3 {
                let d = Double(x[i + c]) - Double(y[i + c])
                sum += d * d
                count += 1
            }
        }
        return (sum / Double(max(count, 1))).squareRoot()
    }

    /// The filter is asked for, never assumed: a command that names no filter must
    /// render the raw estimate, byte for byte. This pins the *default* rather than
    /// the pass, which is what keeps every command written before the filter
    /// existed rendering what it always did.
    @Test(.enabled(if: Snapshot.hasRaytracing))
    func theFilterIsOffUnlessAskedFor() throws {
        #expect(PathTracing(samplesPerPixel: 8).denoises == false)
        OllinApp.pathTracedExport = PathTracing(samplesPerPixel: 8)
        let byDefault = Result { try OllinApp.image(of: GrainProbe.make(.room), frame: 1) }
        OllinApp.pathTracedExport = nil
        let named = try #require(pathTracedGrain(.room, samples: 8, denoises: false))
        #expect(pixels(of: try byDefault.get()) == pixels(of: named))
    }

    /// The headline claim, measured against the truth rather than against taste: a
    /// thin render is filtered *closer* to a converged one, not merely smoother.
    /// A blur that lost the picture would move away from the reference instead.
    ///
    /// And the property that makes the filter safe to leave on, and the one worth
    /// pinning: it never trades the picture for smoothness. A render already close
    /// to converged must come out *closer* still, not merely softer, which is what
    /// says the pass is removing what is left of the error rather than removing
    /// detail. The last read is the strength following the measurement: the same
    /// filter moves a thin render far and a deep one only a little. The thin and the
    /// deep claims are both measured against the one converged reference.
    @Test(.enabled(if: Snapshot.hasRaytracing))
    func theFilterStillHelpsANearlyConvergedRender() throws {
        let reference = try #require(pathTracedGrain(.room, samples: 2048, denoises: false))
        let deepRaw = try #require(pathTracedGrain(.room, samples: 256, denoises: false))
        let deepFiltered = try #require(pathTracedGrain(.room, samples: 256, denoises: true))
        let rawError = rootMeanSquare(deepRaw, reference)
        let filteredError = rootMeanSquare(deepFiltered, reference)
        #expect(filteredError < rawError,
                "deep raw \(rawError) vs deep filtered \(filteredError)")

        let thinRaw = try #require(pathTracedGrain(.room, samples: 8, denoises: false))
        let thinFiltered = try #require(pathTracedGrain(.room, samples: 8, denoises: true))
        let thinRawError = rootMeanSquare(thinRaw, reference)
        let thinFilteredError = rootMeanSquare(thinFiltered, reference)
        #expect(thinFilteredError < thinRawError * 0.7,
                "raw \(thinRawError) vs filtered \(thinFilteredError) against the reference")

        let thinMove = rootMeanSquare(thinRaw, thinFiltered)
        let deepMove = rootMeanSquare(deepRaw, deepFiltered)
        #expect(thinMove > deepMove * 3,
                "thin render moved \(thinMove), deep one moved \(deepMove)")
    }

    /// The demodulation claim: the light is divided by the surface's own color
    /// before filtering and put back after, so a hard texture edge keeps its step.
    /// The probe reads two narrow bands either side of the split and asks that the
    /// filtered step stay nearly the raw one; a filter working on the finished
    /// picture instead would round this edge off.
    @Test(.enabled(if: Snapshot.hasRaytracing))
    func theFilterKeepsAHardTextureEdge() throws {
        func step(_ image: CGImage) -> Double {
            let left = regionMean(image, x0: 0.44, x1: 0.49, y0: 0.35, y1: 0.65)
            let right = regionMean(image, x0: 0.51, x1: 0.56, y0: 0.35, y1: 0.65)
            return left - right
        }
        let raw = try #require(pathTracedGrain(.splitFace, samples: 16, denoises: false))
        let filtered = try #require(pathTracedGrain(.splitFace, samples: 16, denoises: true))
        let rawStep = step(raw), filteredStep = step(filtered)
        #expect(rawStep > 60, "the probe's own edge only reads \(rawStep) levels")
        #expect(filteredStep > rawStep * 0.9,
                "the edge fell from \(rawStep) to \(filteredStep) levels")
    }

    /// The furnace again, filtered this time: a uniform field is a fixed point of
    /// the filter (every neighbor agrees, so any weighting returns the same value),
    /// which is what says the pass conserves energy rather than merely hiding error.
    @Test(.enabled(if: Snapshot.hasRaytracing))
    func theFurnaceSurvivesTheFilter() throws {
        OllinApp.pathTracedExport = PathTracing(samplesPerPixel: 96, denoises: true)
        defer { OllinApp.pathTracedExport = nil }
        let image = try OllinApp.image(of: Probe.make(.furnaceMatte), frame: 1)
        let m = centerMean(image)
        #expect(abs(m - 127.5) < 3.0, "filtered furnace mean \(m), expected ~127.5")
    }

    /// The house determinism rule reaches the filter too: it is a pure function of
    /// the buffers the trace left behind, so the same command still renders the
    /// same bytes.
    @Test(.enabled(if: Snapshot.hasRaytracing))
    func theFilteredFrameStaysDeterministic() throws {
        let a = try #require(pathTracedGrain(.room, samples: 12, denoises: true))
        let b = try #require(pathTracedGrain(.room, samples: 12, denoises: true))
        #expect(pixels(of: a) == pixels(of: b))
    }

    // MARK: - Adaptive sampling

    /// Export one traced still to a file and read it back with the trace's part of
    /// its recipe, which is where the frame's own account of itself lives: the
    /// settings it ran under and, under a threshold, the mean count its pixels
    /// reached. The image comes back through the file too, so every frame a probe
    /// compares has taken the same route.
    private func pathTracedStill(_ sketch: Sketch, _ settings: PathTracing) throws
        -> (image: CGImage, traced: [String: Any]) {
        OllinApp.pathTracedExport = settings
        defer { OllinApp.pathTracedExport = nil }
        let path = ollinTempPath("ollin-pt-adaptive-\(UUID().uuidString).png")
        defer { try? FileManager.default.removeItem(atPath: path) }
        try OllinApp.export(sketch, to: path, frame: 1)
        // Read through the bytes, not the URL: an image source decodes from its file
        // when the image is first drawn, and the file is gone by then.
        let bytes = try Data(contentsOf: URL(fileURLWithPath: path))
        let source = try #require(CGImageSourceCreateWithData(bytes as CFData, nil))
        let image = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
        let props = try #require(CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any])
        let png = try #require(props[kCGImagePropertyPNGDictionary] as? [CFString: Any])
        let text = try #require(png[kCGImagePropertyPNGDescription] as? String)
        let recipe = try #require(try JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any])
        let traced = try #require(recipe["pathTraced"] as? [String: Any])
        return (image, traced)
    }

    /// The stop is asked for, never assumed: a count with no threshold traces every
    /// pixel to that count, and the minimum a pixel takes before it may stop follows
    /// the square root of the count, rounded up to the eight-sample check step and
    /// never under one step, unless the sketch names one.
    @Test func theStopIsOffUnlessAskedForAndTheMinimumFollowsTheSquareRoot() {
        #expect(PathTracing(samplesPerPixel: 8).noiseThreshold == 0)
        #expect(PathTracing(samplesPerPixel: 8).isAdaptive == false)
        #expect(PathTracing(samplesPerPixel: 128, noiseThreshold: 0.01).firstCheck == 16)
        #expect(PathTracing(samplesPerPixel: 4096, noiseThreshold: 0.01).firstCheck == 64)
        #expect(PathTracing(samplesPerPixel: 64, noiseThreshold: 0.01).firstCheck == 8)
        #expect(PathTracing(samplesPerPixel: 20, noiseThreshold: 0.01).firstCheck == 8)
        #expect(PathTracing(samplesPerPixel: 4, noiseThreshold: 0.01).firstCheck == 4)
        #expect(PathTracing(samplesPerPixel: 128, noiseThreshold: 0.01, minSamplesPerPixel: 40).firstCheck == 40)
        #expect(PathTracing(samplesPerPixel: 128, noiseThreshold: 0.01, minSamplesPerPixel: 500).firstCheck == 128)
        // One sample has no spread to read, so a count of one is never adaptive.
        #expect(PathTracing(samplesPerPixel: 1, noiseThreshold: 0.01).isAdaptive == false)
    }

    /// The firefly scene: a matte floor beside a polished ball under a small, very
    /// hot lamp. The floor's direct light comes through the lamp's own strategy and
    /// is smooth; what speckles it is the lamp seen through the ball, a path the
    /// floor's bounce finds every few hundred samples and that no light strategy can
    /// aim at. The lit plane is the other case: a matte floor under a directional
    /// light with nothing else in the scene, so no bounce ever carries light.
    final class FireflyProbe: Sketch {
        enum Kind { case causticFloor, litPlane }
        var kind: Kind = .causticFloor

        override var canvasSize: CanvasSize { .square(160) }

        static func make(_ kind: Kind) -> FireflyProbe {
            let p = FireflyProbe()
            p.kind = kind
            return p
        }

        override func draw() {
            background(.black)
            switch kind {
            case .causticFloor:
                camera(Camera3D(eye: Vector3(0, 1.6, 3.6), target: Vector3(0, 0.1, 0)))
                fill(Color(white: 0.7))
                material(Material())
                withState {
                    translate(0, -0.3, 0)
                    drawBox(width: 8, height: 0.2, depth: 8)
                }
                withState {
                    translate(-0.9, 0.5, 0)
                    // Glossy rather than a mirror: the wider lobe catches the lamp
                    // from more of the floor, so the caustic's fireflies are many.
                    material(.metal(roughness: 0.25))
                    fill(.white)
                    drawSphere(radius: 0.7)
                }
                withState {
                    // A mesh light, so the floor's own light comes through the lamp's
                    // strategy and is smooth; a `.glowing` surface has no strategy and
                    // would speckle the floor with one-bounce hits the bound leaves alone.
                    translate(1.6, 1.9, 0.4)
                    // The color decodes as sRGB, so 8 is about 130 times white: the
                    // floor's direct light reads a quarter of white and the caustic's
                    // hits a hundred times that.
                    var lamp = Mesh.sphere(radius: 0.12)
                    lamp.material = MeshMaterial(emissiveColor: Color(white: 8))
                    drawMesh(lamp)
                }
            case .litPlane:
                camera(Camera3D(eye: Vector3(0, 1.6, 3.6), target: Vector3(0, 0.1, 0)))
                directionalLight(Color(white: 0.9), direction: Vector3(-0.4, -1, -0.3))
                fill(Color(white: 0.7))
                material(Material())
                withState {
                    translate(0, -0.3, 0)
                    drawBox(width: 8, height: 0.2, depth: 8)
                }
            }
        }
    }

    /// A bound on what twice-bounced light may add to a sample takes the fireflies
    /// out of a polished scene: on the floor beside the ball, speckled by the lamp
    /// seen through the ball, the pixels far above the floor's level fall by more
    /// than half at the same count while the floor's own sampling noise stays, the
    /// recipe names the bound and the share of the frame's light it took, and that
    /// share is small (the fireflies are rare light) and above zero (something was
    /// taken, which is the bias the flag accepts). With the dots gone the
    /// per-pixel stop reads the floor sooner, so under a threshold the bounded
    /// frame settles at a lower mean count than the unbounded one.
    @Test(.enabled(if: Snapshot.hasRaytracing))
    func aBoundOnABounceCutsTheFirefliesAndSaysWhatItTook() throws {
        // The floor just in front of the ball, which sees the ball large and the
        // lamp's reflection in it often.
        let floor = (x0: 0.05, x1: 0.40, y0: 0.66, y1: 0.93)
        let plain = try pathTracedStill(FireflyProbe.make(.causticFloor), PathTracing(samplesPerPixel: 48))
        let bounded = try pathTracedStill(FireflyProbe.make(.causticFloor),
                                          PathTracing(samplesPerPixel: 48, maxBounceLight: 2))
        #expect(plain.traced["clamp"] == nil)
        #expect(plain.traced["clampDropped"] == nil)
        #expect(bounded.traced["clamp"] as? Double == 2)
        let dropped = try #require(bounded.traced["clampDropped"] as? Double)
        #expect(dropped > 0 && dropped < 0.1, "the bound took \(dropped) of the light")
        // The fireflies: pixels far above the floor's own level. The floor's
        // ordinary sampling noise (the lamp's area, sampled) stays either way, so
        // the whole spread falls by less than the outliers do.
        let plainOutliers = regionOutliers(plain.image, x0: floor.x0, x1: floor.x1, y0: floor.y0, y1: floor.y1, above: 24)
        let boundedOutliers = regionOutliers(bounded.image, x0: floor.x0, x1: floor.x1, y0: floor.y0, y1: floor.y1, above: 24)
        #expect(plainOutliers >= 10, "the unbounded floor shows \(plainOutliers) fireflies; the probe needs some to read")
        #expect(boundedOutliers * 2 < plainOutliers,
                "fireflies on the floor: \(plainOutliers) unbounded, \(boundedOutliers) bounded")
        let plainNoise = regionRelativeNoise(plain.image, x0: floor.x0, x1: floor.x1, y0: floor.y0, y1: floor.y1)
        let boundedNoise = regionRelativeNoise(bounded.image, x0: floor.x0, x1: floor.x1, y0: floor.y0, y1: floor.y1)
        #expect(boundedNoise < plainNoise * 0.75, "the floor's grain: \(plainNoise) unbounded, \(boundedNoise) bounded")
        // The floor keeps its light: the bound takes the rare bright paths, not the
        // direct light, so the region's mean moves by a few percent at most.
        let plainMean = regionMean(plain.image, x0: floor.x0, x1: floor.x1, y0: floor.y0, y1: floor.y1)
        let boundedMean = regionMean(bounded.image, x0: floor.x0, x1: floor.x1, y0: floor.y0, y1: floor.y1)
        #expect(abs(boundedMean - plainMean) < max(plainMean * 0.08, 3),
                "the floor's mean: \(plainMean) unbounded, \(boundedMean) bounded")

        let stopPlain = try pathTracedStill(FireflyProbe.make(.causticFloor),
                                            PathTracing(samplesPerPixel: 128, noiseThreshold: 0.04))
        let stopBounded = try pathTracedStill(FireflyProbe.make(.causticFloor),
                                              PathTracing(samplesPerPixel: 128, noiseThreshold: 0.04,
                                                          maxBounceLight: 2))
        let meanPlain = try #require(stopPlain.traced["meanSamples"] as? Double)
        let meanBounded = try #require(stopBounded.traced["meanSamples"] as? Double)
        #expect(meanBounded < meanPlain, "the stop reached a mean of \(meanPlain) unbounded, \(meanBounded) bounded")
    }

    /// The bound never touches what the eye sees directly: a floor under a
    /// directional light with nothing to bounce off renders the same bytes under
    /// any bound, and the recipe says the bound took nothing.
    @Test(.enabled(if: Snapshot.hasRaytracing))
    func theBoundLeavesTheFirstHitAlone() throws {
        let plain = try pathTracedStill(FireflyProbe.make(.litPlane), PathTracing(samplesPerPixel: 16))
        let bounded = try pathTracedStill(FireflyProbe.make(.litPlane),
                                          PathTracing(samplesPerPixel: 16, maxBounceLight: 0.01))
        #expect(pixels(of: plain.image).contains { $0 > 60 })
        #expect(pixels(of: plain.image) == pixels(of: bounded.image))
        #expect(bounded.traced["clampDropped"] as? Double == 0)
        // And the bound is off unless asked for.
        #expect(PathTracing(samplesPerPixel: 8).isBounded == false)
        #expect(PathTracing(samplesPerPixel: 8, maxBounceLight: 4).isBounded)
        #expect(PathTracing(samplesPerPixel: 8, maxBounceLight: -1).maxBounceLight == 0)
    }

    /// The headline claim, in the terms the published stopping conditions use: the
    /// same error for fewer samples. Under a threshold the pixels that have settled
    /// (the black margins, the evenly lit floor) stop, so the frame spends fewer
    /// samples than its cap; measured against a converged reference it then sits
    /// closer to the truth than a fixed render of the same mean count, since the
    /// samples it kept went where the grain was. A tight threshold reaches the full
    /// count's own error for a fraction of its samples, and a loose one spends
    /// less and errs more, which is what makes the threshold the dial. The recipe
    /// is read for the count, which is also what pins that the recipe carries it.
    /// Measured when written (160 pixels square, the cap 256, against 2048): at
    /// 0.005 the pixels reached a mean of 140 for an error of 0.77 against the full
    /// count's 0.75 and 1.01 at a fixed 140; at 0.02 a mean of 38 for 1.31 against
    /// 1.87 at a fixed 38.
    @Test(.enabled(if: Snapshot.hasRaytracing))
    func adaptiveSamplingSpendsTheCountWhereTheGrainIs() throws {
        let cap = 256
        func traced(_ threshold: Double) throws -> (image: CGImage, mean: Double, traced: [String: Any]) {
            let still = try pathTracedStill(GrainProbe.make(.room),
                                            PathTracing(samplesPerPixel: cap, noiseThreshold: threshold))
            let mean = try #require(still.traced["meanSamples"] as? Double)
            return (still.image, mean, still.traced)
        }
        let loose = try traced(0.02)
        #expect(loose.traced["samples"] as? Int == cap)
        #expect(loose.traced["depth"] as? Int == 8)
        #expect(loose.traced["noise"] as? Double == 0.02)
        #expect(loose.traced["minSamples"] as? Int == 16)
        #expect(loose.mean > 16 && loose.mean < Double(cap) * 0.3,
                "the pixels reached a mean of \(loose.mean) of \(cap)")

        let reference = try pathTracedStill(GrainProbe.make(.room), PathTracing(samplesPerPixel: 2048))
        // The pictures carry ink, or every distance below would be a vacuous zero.
        #expect(pixels(of: reference.image).contains { $0 > 40 })
        let fixed = try pathTracedStill(GrainProbe.make(.room),
                                        PathTracing(samplesPerPixel: Int(loose.mean.rounded())))
        #expect(fixed.traced["meanSamples"] == nil)
        #expect(fixed.traced["noise"] == nil)
        let looseError = rootMeanSquare(loose.image, reference.image)
        let fixedError = rootMeanSquare(fixed.image, reference.image)
        #expect(looseError < fixedError * 0.85,
                "adaptive at a mean of \(loose.mean): \(looseError); fixed at the same count: \(fixedError)")

        // The dial: a tighter threshold spends more and errs less, and at 0.005 it
        // reaches the full count's error for well under its samples.
        let tight = try traced(0.005)
        let full = try pathTracedStill(GrainProbe.make(.room), PathTracing(samplesPerPixel: cap))
        let tightError = rootMeanSquare(tight.image, reference.image)
        let fullError = rootMeanSquare(full.image, reference.image)
        #expect(tight.mean > loose.mean && tight.mean < Double(cap) * 0.7,
                "tight mean \(tight.mean), loose mean \(loose.mean)")
        #expect(tightError < looseError, "tight \(tightError), loose \(looseError)")
        #expect(tightError < fullError * 1.1,
                "adaptive at 0.005 \(tightError) against the full count's \(fullError)")
    }

    /// The frame is a pure function of its index: the stop reads a threshold off
    /// the running sums, so a last bit that followed the clock would move whole
    /// pixels. The host cuts each round of samples into dispatches by GPU time,
    /// and the kernel adds its samples onto the sums in sample order so the cut
    /// cannot show; the probe forces two cuts and asks for the same bytes, for a
    /// fixed count and under the stop alike.
    @Test(.enabled(if: Snapshot.hasRaytracing))
    func theTracedFrameIsTheSameBytesUnderAnyCut() throws {
        defer { OllinApp.pathTraceChunkSize = nil }
        let fixed = PathTracing(samplesPerPixel: 24)
        OllinApp.pathTraceChunkSize = 1
        let fixedByOne = try pathTracedStill(GrainProbe.make(.room), fixed)
        OllinApp.pathTraceChunkSize = 7
        let fixedBySeven = try pathTracedStill(GrainProbe.make(.room), fixed)
        #expect(pixels(of: fixedByOne.image) == pixels(of: fixedBySeven.image))

        let adaptive = PathTracing(samplesPerPixel: 48, noiseThreshold: 0.03)
        OllinApp.pathTraceChunkSize = 1
        let byOne = try pathTracedStill(GrainProbe.make(.room), adaptive)
        OllinApp.pathTraceChunkSize = 5
        let byFive = try pathTracedStill(GrainProbe.make(.room), adaptive)
        OllinApp.pathTraceChunkSize = nil
        let byTime = try pathTracedStill(GrainProbe.make(.room), adaptive)
        #expect(pixels(of: byOne.image) == pixels(of: byFive.image))
        #expect(pixels(of: byOne.image) == pixels(of: byTime.image))
        #expect(byOne.traced["meanSamples"] as? Double == byFive.traced["meanSamples"] as? Double)
        #expect(byOne.traced["meanSamples"] as? Double == byTime.traced["meanSamples"] as? Double)
    }

    // MARK: - A light that declines to throw

    /// A floor, a sphere above it, and one light: the scene where a cast shadow is
    /// the only thing on the floor to read. Ambient stays near zero so the shadow
    /// patch is dark for one reason alone, and the sphere sits off the light's
    /// axis so its shadow lands clear of its own silhouette.
    final class CasterProbe: Sketch {
        var throwsShadow = true

        override var canvasSize: CanvasSize { .square(256) }

        static func make(_ throwsShadow: Bool) -> CasterProbe {
            let p = CasterProbe()
            p.throwsShadow = throwsShadow
            return p
        }

        override func draw() {
            background(.black)
            ambientLight(Color(white: 0.02))
            camera(Camera3D(eye: Vector3(0, 3.2, 6.4), target: Vector3(0, 0, 0)))
            // The casting half names nothing, so it also pins the default: a light
            // that says nothing about shadows throws one.
            if throwsShadow {
                directionalLight(Color(white: 0.9), direction: Vector3(1, -0.8, -0.1))
            } else {
                directionalLight(Color(white: 0.9), direction: Vector3(1, -0.8, -0.1),
                                 castsShadow: false)
            }
            fill(Color(white: 0.85))
            material(Material())
            withState {
                translate(0, -0.8, 0)
                drawBox(width: 16, height: 0.4, depth: 16)
            }
            withState {
                translate(0, 0.7, 0)
                drawSphere(radius: 0.7)
            }
        }
    }

    private func casterProbe(_ throwsShadow: Bool, samples: Int = 24) -> CGImage? {
        OllinApp.pathTracedExport = PathTracing(samplesPerPixel: samples, denoises: false)
        defer { OllinApp.pathTracedExport = nil }
        return try? OllinApp.image(of: CasterProbe.make(throwsShadow), frame: 1)
    }

    /// The ruling: `castsShadow: false` reaches the traced export. The tracer keeps
    /// no caster list, so without the flag it throws a shadow from every light in the
    /// frame, and a curated preset's fill would cast one there while casting nothing
    /// in the preview. The probe reads the floor where the shadow falls: with the flag
    /// set the patch must come back to the brightness of the lit floor beside it.
    @Test(.enabled(if: Snapshot.hasRaytracing))
    func aLightThatDeclinesToThrowCastsNothingInTheTrace() throws {
        let casting = try #require(casterProbe(true))
        let open = try #require(casterProbe(false))
        let shadow = (x0: 0.64, x1: 0.72, y0: 0.52, y1: 0.60)
        let lit = (x0: 0.24, x1: 0.32, y0: 0.52, y1: 0.60)

        let castShadowPatch = regionMean(casting, x0: shadow.x0, x1: shadow.x1,
                                         y0: shadow.y0, y1: shadow.y1)
        let castLitPatch = regionMean(casting, x0: lit.x0, x1: lit.x1,
                                      y0: lit.y0, y1: lit.y1)
        // The probe must actually cast, or the comparison below proves nothing.
        #expect(castLitPatch - castShadowPatch > 40,
                "the probe casts no shadow: \(castShadowPatch) against \(castLitPatch)")

        let openShadowPatch = regionMean(open, x0: shadow.x0, x1: shadow.x1,
                                         y0: shadow.y0, y1: shadow.y1)
        let openLitPatch = regionMean(open, x0: lit.x0, x1: lit.x1,
                                      y0: lit.y0, y1: lit.y1)
        #expect(abs(openShadowPatch - openLitPatch) < 6,
                "the floor still darkens: \(openShadowPatch) against \(openLitPatch)")
        #expect(openShadowPatch - castShadowPatch > 40,
                "the flag moved the patch only \(openShadowPatch - castShadowPatch) levels")
    }

    // MARK: - A pixel's worth of a curved surface

    /// Small polished beads under a studio, and a flat polished mirror under the
    /// same, for the footprint the tracer reads the environment at: a bead five
    /// pixels across fans each pixel's reflections over a wide cone of directions,
    /// a flat mirror turns none.
    final class FootprintProbe: Sketch {
        enum Kind { case beads, mirror }
        var kind: Kind = .beads

        override var canvasSize: CanvasSize { .square(256) }

        static func make(_ kind: Kind) -> FootprintProbe {
            let p = FootprintProbe()
            p.kind = kind
            return p
        }

        let bead = Mesh.sphere(radius: 1, segments: 24, rings: 12)

        override func draw() {
            background(.black)
            camera(Camera3D(eye: Vector3(0, 0, 4), target: .zero))
            // The studio lights and reflects; the backdrop stays the black background.
            environment(.interior.lightingOnly())
            fill(Color(white: 200 / 255))
            material(.polishedMetal)
            switch kind {
            case .beads:
                var copies: [MeshInstance] = []
                for j in 0 ..< 6 {
                    for i in 0 ..< 6 {
                        copies.append(MeshInstance(position: Vector3((Double(i) - 2.5) * 0.5,
                                                                     (Double(j) - 2.5) * 0.5, 0),
                                                   scale: 0.08))
                    }
                }
                drawMesh(bead, instances: copies)
            case .mirror:
                withState {
                    rotateX(.pi / 2)
                    drawMesh(Mesh.plane(width: 2.4, depth: 2.4))
                }
            }
        }
    }

    private func footprint(_ kind: FootprintProbe.Kind, samples: Int) -> CGImage? {
        OllinApp.pathTracedExport = PathTracing(samplesPerPixel: samples, denoises: false)
        defer { OllinApp.pathTracedExport = nil }
        return try? OllinApp.image(of: FootprintProbe.make(kind), frame: 1)
    }

    /// Root-mean-square difference between two renders over the pixels the second
    /// lights, all three channels, in 8-bit levels, with that pixel count.
    private func rmsDifference(_ a: CGImage, _ b: CGImage) -> (rms: Double, lit: Int) {
        let da = pixels(of: a), db = pixels(of: b)
        var sum = 0.0, lit = 0
        for i in stride(from: 0, to: db.count, by: 4) {
            guard max(db[i], db[i + 1], db[i + 2]) > 8 else { continue }
            lit += 1
            for c in 0 ..< 3 {
                let d = Double(da[i + c]) - Double(db[i + c])
                sum += d * d
            }
        }
        return ((sum / Double(max(lit * 3, 1))).squareRoot(), lit)
    }

    /// Small polished beads mirror the studio, and each pixel's footprint on a bead
    /// fans its reflections over a wide cone of directions, so a sample that reads
    /// one direction of that cone sharp catches a lamp one time in a few hundred and
    /// then carries it whole, the grain no count settles. The tracer reads the
    /// environment at the footprint instead, so a thin render sits close to a full
    /// one: 32 samples against 512, the RMS over the beads' pixels under 14 levels
    /// (10.2 measured; the sharp read sat at 19.7).
    @Test(.enabled(if: Snapshot.hasRaytracing))
    func aPolishedBeadFieldConvergesAtItsFootprint() throws {
        let thin = try #require(footprint(.beads, samples: 32))
        let full = try #require(footprint(.beads, samples: 512))
        let (rms, lit) = rmsDifference(thin, full)
        #expect(lit > 400, "the beads cover \(lit) pixels")
        #expect(rms < 14, "RMS \(rms) over \(lit) bead pixels at 32 against 512 samples")
    }

    /// A flat polished mirror reads the environment as it did before the footprint
    /// read existed: its footprint turns no normals, so the cone stays under a texel
    /// and the lobe's own level is what the read takes. The reference was recorded
    /// before the cone, and the frame must still match it.
    @Test(.enabled(if: Snapshot.hasRaytracing))
    func aFlatMirrorReadsTheEnvironmentAsBefore() throws {
        OllinApp.pathTracedExport = PathTracing(samplesPerPixel: 48, denoises: false)
        defer { OllinApp.pathTracedExport = nil }
        let diff = try Snapshot.meanDifference(of: FootprintProbe.make(.mirror),
                                               against: "path-traced-mirror", frame: 1)
        #expect(diff < Snapshot.tolerance, "mean difference \(diff)")
    }
}
