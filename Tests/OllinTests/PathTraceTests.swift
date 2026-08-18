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
            panel.material = MeshMaterial(emissiveFactor: Color(red: f, green: f, blue: f))
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
        OllinApp.pathTracedExport = PathTracing(samplesPerPixel: samples, maxDepth: depth)
        defer { OllinApp.pathTracedExport = nil }
        return OllinApp.image(of: SliceProbe.make(kind), frame: 1)
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
        let raster = try #require(OllinApp.image(of: SliceProbe.make(.texturedSphere), frame: 1))
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

    /// The whole slice stays deterministic: glass, a textured floor, and a mesh
    /// light in one scene render byte-identically across runs (the binary
    /// searches, the stochastic lobe mixes, and the transparent walk are all
    /// pure functions of the sample stream).
    @Test(.enabled(if: Snapshot.hasRaytracing))
    func theNewPathsStayDeterministic() throws {
        let a = try #require(pathTracedSlice(.everything, samples: 12))
        let b = try #require(pathTracedSlice(.everything, samples: 12))
        #expect(pixels(of: a) == pixels(of: b))
    }
}
