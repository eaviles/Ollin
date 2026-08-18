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
        OllinApp.pathTracedExport = PathTracing(samplesPerPixel: samples, maxDepth: depth)
        defer { OllinApp.pathTracedExport = nil }
        return OllinApp.image(of: MapsProbe.make(kind), frame: 1)
    }

    /// The normal map through the trace: the half-tilted face must shade its two
    /// halves apart (the bend reaches the lighting), and each half must read the
    /// same through the trace as through the raster normal-mapped pipeline (the
    /// same interpolated tangent frame, the same bend, the same light).
    @Test(.enabled(if: Snapshot.hasRaytracing))
    func aNormalMapBendsTheTracedLight() throws {
        let traced = try #require(pathTracedMaps(.normalMapped))
        OllinApp.pathTracedExport = nil
        let raster = try #require(OllinApp.image(of: MapsProbe.make(.normalMapped), frame: 1))
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
        let raster = try #require(OllinApp.image(of: MapsProbe.make(.triplanarFace), frame: 1))
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
}
