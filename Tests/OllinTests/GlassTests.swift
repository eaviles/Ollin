@testable import Ollin
import Testing
import CoreGraphics
import COllinShaders

/// Behavioral probes for the transmissive (glass) material: the invariants a mean-diff
/// snapshot can't pin. Transmission must be *inert without an environment* (byte-equal
/// to the plain dielectric it would otherwise be), absorption must deepen with the
/// interior span, and on a ray-tracing GPU the traced walk must show the actual scene
/// through the glass where the environment path can't.
@Suite
@MainActor
struct GlassRenderProbes {

    private func pixels(of image: CGImage) -> [UInt8] {
        let w = image.width, h = image.height
        var data = [UInt8](repeating: 0, count: w * h * 4)
        let ctx = CGContext(data: &data, width: w, height: h, bitsPerComponent: 8,
                            bytesPerRow: w * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        return data
    }

    /// Mean of one channel over a fractional region (top-left origin).
    private func mean(_ data: [UInt8], width: Int, height: Int, channel: Int,
                      x: ClosedRange<Double>, y: ClosedRange<Double>) -> Double {
        var sum = 0, count = 0
        for py in Int(Double(height) * y.lowerBound)..<Int(Double(height) * y.upperBound) {
            for px in Int(Double(width) * x.lowerBound)..<Int(Double(width) * x.upperBound) {
                sum += Int(data[(py * width + px) * 4 + channel]); count += 1
            }
        }
        return Double(sum) / Double(max(count, 1))
    }

    @Test(.enabled(if: Snapshot.hasMetal))
    func withoutAnEnvironmentGlassIsAPlainDielectric() throws {
        // No environment means nothing to transmit: the glass sphere must render
        // byte-identical to the same sphere as an opaque dielectric (the documented
        // gate; the transmission block and the direct-light diffKeep never engage).
        let glass = try #require(OllinApp.image(of: GlassProbe.make(kind: .noEnvGlass), frame: 1))
        let plain = try #require(OllinApp.image(of: GlassProbe.make(kind: .noEnvDielectric), frame: 1))
        #expect(pixels(of: glass) == pixels(of: plain))
    }

    @Test(.enabled(if: Snapshot.hasMetal))
    func absorptionDeepensWithTheInteriorSpan() throws {
        // Two green-attenuated solid spheres differing only in thickness: the thicker
        // body's interior span is longer, so its center must come out darker.
        let thin = try #require(OllinApp.image(of: GlassProbe.make(kind: .attenuationThin), frame: 1))
        let thick = try #require(OllinApp.image(of: GlassProbe.make(kind: .attenuationThick), frame: 1))
        let dThin = pixels(of: thin), dThick = pixels(of: thick)
        func luma(_ d: [UInt8], _ img: CGImage) -> Double {
            mean(d, width: img.width, height: img.height, channel: 1,
                 x: 0.42...0.58, y: 0.42...0.58)
        }
        let a = luma(dThin, thin), b = luma(dThick, thick)
        #expect(a - b > 8, "expected the thicker body darker at center: thin \(a), thick \(b)")
    }

    @Test(.enabled(if: Snapshot.hasMetal && Snapshot.hasRaytracing))
    func theTracedWalkShowsTheSceneThroughTheGlass() throws {
        // A red wall stands behind a thin glass pane, out of the environment's picture.
        // The environment-refraction base path can only show the studio behind the
        // pane; the traced walk passes through the pane's own shell and hits the wall,
        // so the pane's interior must go red only when rayTracedReflections() is on.
        let traced = try #require(OllinApp.image(of: GlassProbe.make(kind: .paneTraced), frame: 1))
        let envOnly = try #require(OllinApp.image(of: GlassProbe.make(kind: .paneEnvOnly), frame: 1))
        let dT = pixels(of: traced), dE = pixels(of: envOnly)
        func redness(_ d: [UInt8], _ img: CGImage) -> Double {
            mean(d, width: img.width, height: img.height, channel: 0,
                 x: 0.40...0.60, y: 0.40...0.60)
            - mean(d, width: img.width, height: img.height, channel: 2,
                   x: 0.40...0.60, y: 0.40...0.60)
        }
        let r = redness(dT, traced), e = redness(dE, envOnly)
        #expect(r - e > 25, "expected the wall's red through the traced pane: traced \(r), env-only \(e)")
    }

    @Test(.enabled(if: Snapshot.hasMetal && Snapshot.hasRaytracing))
    func aGlassFieldAbsorbsLikeAGlassMesh() throws {
        // The same green-attenuated glass body, once as a mesh sphere and once as a
        // marched field of the same radius, with a white slab behind. A field owns no
        // triangles for the traced transmission walk to hit, so it has to hand the walk
        // its own far interface; without that the walk takes the slab for the exit and
        // absorbs over the run to it, which reads far darker than the mesh and moves
        // when the slab does. Two things are pinned: the two shapes agree, and the
        // field's tint doesn't follow the slab.
        let meshImg = try #require(OllinApp.image(of: GlassProbe.make(kind: .absorbingMesh), frame: 1))
        let fieldImg = try #require(OllinApp.image(of: GlassProbe.make(kind: .absorbingField), frame: 1))
        let farImg = try #require(OllinApp.image(of: GlassProbe.make(kind: .absorbingFieldFarSlab), frame: 1))
        func center(_ img: CGImage, _ channel: Int) -> Double {
            mean(pixels(of: img), width: img.width, height: img.height, channel: channel,
                 x: 0.45...0.55, y: 0.47...0.53)
        }
        // The tint has to be there at all, or agreeing on nothing would pass.
        let meshTint = center(meshImg, 1) - center(meshImg, 0)
        #expect(meshTint > 60, "expected the mesh body visibly green-tinted: \(meshTint)")
        for channel in 0...2 {
            let m = center(meshImg, channel), f = center(fieldImg, channel)
            #expect(abs(m - f) < 6,
                    "channel \(channel): field \(f) should absorb like the mesh \(m)")
        }
        for channel in 0...2 {
            let near = center(fieldImg, channel), far = center(farImg, channel)
            #expect(abs(near - far) < 6,
                    "channel \(channel): the field's absorption followed the slab, \(near) to \(far)")
        }
        // Both bodies sit in the same place, so the interior compares pixel by pixel.
        // A mean alone would miss a banded interior: a march that resolves the exit at
        // some radii and not at others prints the body in thin rings that average away.
        let (meanDiff, peakDiff) = interiorDifference(meshImg, fieldImg)
        #expect(meanDiff < 8, "the field's interior differs from the mesh's by \(meanDiff)")
        #expect(peakDiff < 40, "the field's interior is banded, peaking at \(peakDiff)")
    }

    @Test(.enabled(if: Snapshot.hasMetal && Snapshot.hasRaytracing))
    func aFieldRimShadesLikeAMeshRim() throws {
        // The silhouette rim, pixel by pixel: the one region the interior disc
        // deliberately leaves out. A field is absent from the deferred reflection
        // layer, so its fragment must trace reflections inline; if the deferred
        // flag reaches the field's lighting, the ambient's deferred branch reads the
        // fragment's zero stand-in sample and quietly leaves the raw environment in
        // place of the traced scene. The environment outshines the traced slab at
        // grazing incidence, so the field wears a blown-white band three or four
        // pixels wide just inside its silhouette, with one dark pixel outside it,
        // where the mesh descends smoothly. A patch mean cannot see a band this
        // thin; only a scanline can, which is how it survived the snapshot suite
        // and was found by eye. Each row aligns on its own first covered pixel, so
        // a sub-pixel silhouette offset between the two bodies doesn't register.
        let meshImg = try #require(OllinApp.image(of: GlassProbe.make(kind: .absorbingMesh), frame: 1))
        let fieldImg = try #require(OllinApp.image(of: GlassProbe.make(kind: .absorbingField), frame: 1))
        let dm = pixels(of: meshImg), df = pixels(of: fieldImg)
        let w = meshImg.width
        func edge(_ data: [UInt8], row: Int) -> Int? {
            // The slab reference comes from a column strip left of the body.
            var ref = [0.0, 0.0, 0.0]
            for x in 20..<30 { for c in 0...2 { ref[c] += Double(data[(row * w + x) * 4 + c]) } }
            for c in 0...2 { ref[c] /= 10 }
            for x in 35..<(w / 2) {
                for c in 0...2 where abs(Double(data[(row * w + x) * 4 + c]) - ref[c]) > 30 {
                    return x
                }
            }
            return nil
        }
        var worst = 0.0
        for fraction in [0.40, 0.50, 0.60] {
            let row = Int(Double(meshImg.height) * fraction)
            let me = try #require(edge(dm, row: row), "no mesh silhouette on row \(row)")
            let fe = try #require(edge(df, row: row), "no field silhouette on row \(row)")
            // The first pixel is the two AA models disagreeing (multisampled against
            // analytic), so the shading comparison starts one pixel inside the edge.
            for offset in 1...5 {
                for c in 0...2 {
                    let m = Double(dm[(row * w + me + offset) * 4 + c])
                    let f = Double(df[(row * w + fe + offset) * 4 + c])
                    worst = max(worst, abs(m - f))
                }
            }
        }
        #expect(worst < 45, "the field's rim shading diverges from the mesh's by \(worst)")
    }

    /// Mean and worst per-pixel channel difference over a disc that stops a few
    /// pixels short of the silhouette. The mask is a disc, not a square: the body
    /// fills most of the frame, so a square's corners reach the rim, and the
    /// outermost pixels legitimately differ (the AA models disagree, multisampled
    /// against analytic, and the rim compresses the mirror image so the field's
    /// single inline reflection ray reads a value the mesh's supersampled deferred
    /// layer averages). The rim's own agreement is `aFieldRimShadesLikeAMeshRim`.
    private func interiorDifference(_ a: CGImage, _ b: CGImage) -> (Double, Double) {
        let da = pixels(of: a), db = pixels(of: b)
        var sum = 0.0, count = 0.0, peak = 0.0
        let radius = 0.19 * Double(a.width)          // ~81% of the body's screen radius
        let cx = 0.5 * Double(a.width), cy = 0.5 * Double(a.height)
        for py in 0..<a.height {
            for px in 0..<a.width {
                let dx = Double(px) - cx, dy = Double(py) - cy
                guard dx * dx + dy * dy <= radius * radius else { continue }
                for channel in 0...2 {
                    let i = (py * a.width + px) * 4 + channel
                    let d = abs(Double(da[i]) - Double(db[i]))
                    sum += d; count += 1; peak = max(peak, d)
                }
            }
        }
        return (sum / max(count, 1), peak)
    }
}

/// The probe scene, one variant per case: a single glass body under a fixed camera,
/// with the environment / tracing / thickness varied by `kind`.
private final class GlassProbe: Sketch {
    enum Kind {
        case noEnvGlass, noEnvDielectric      // no environment: must match exactly
        case attenuationThin, attenuationThick
        case paneTraced, paneEnvOnly
        case absorbingMesh, absorbingField, absorbingFieldFarSlab
    }
    var kind: Kind = .noEnvGlass

    static func make(kind: Kind) -> GlassProbe {
        let probe = GlassProbe()
        probe.kind = kind
        return probe
    }

    override var canvasSize: CanvasSize { .square(192) }

    override func draw() {
        background(Color(white: 0.05))
        camera(.orbiting(target: .zero, radius: 5, azimuth: 0, elevation: 0.0,
                         fieldOfView: .pi / 4, near: 1, far: 20))
        switch kind {
        case .noEnvGlass, .noEnvDielectric:
            directionalLight(.white, direction: Vector3(-0.4, -1, -0.3), intensity: 1)
            fill(Color(hue: 0.58, saturation: 0.5, brightness: 0.9))
            material(kind == .noEnvGlass ? .glass() : .dielectric(roughness: 0))
            drawSphere(radius: 1.2)
        case .attenuationThin, .attenuationThick:
            environment(.studio)
            fill(.white)
            let t = kind == .attenuationThin ? 0.6 : 3.0
            material(.glass(thickness: t, attenuationColor: Color(hex: 0x2e8f5b),
                            attenuationDistance: 0.8))
            drawSphere(radius: 1.2)
        case .paneTraced, .paneEnvOnly:
            environment(.studio)
            if kind == .paneTraced { rayTracedReflections() }
            // The red wall the environment knows nothing about.
            withState {
                fill(Color(hex: 0xd94430))
                material(.dielectric(roughness: 0.8))
                translate(0, 0, -2.5)
                drawBox(width: 8, height: 8, depth: 0.4)
            }
            fill(.white)
            material(.glass())
            drawSphere(radius: 1.2)
        case .absorbingMesh, .absorbingField, .absorbingFieldFarSlab:
            environment(.studio.intensified(to: 1.4))
            rayTracedReflections()
            // The white slab the interior ray would otherwise mistake for the body's exit.
            withState {
                translate(0, 0, kind == .absorbingFieldFarSlab ? -9 : -3)
                fill(.white)
                material(.matte)
                drawBox(width: 24, height: 16, depth: 0.2)
            }
            fill(.white)
            material(.glass(thickness: 1.6,
                            attenuationColor: Color(hue: 0.33, saturation: 0.95, brightness: 0.7),
                            attenuationDistance: 2))
            if kind == .absorbingMesh {
                drawSphere(radius: 0.95)
            } else {
                drawSDF3D(.sphere(radius: 0.95))
            }
        }
    }
}

/// Behavioral probes for the scene *through* the glass on a GPU that never traces a ray
/// (`sceneThroughGlass()`): the renderer draws the frame a second time with every
/// transmissive run left out, and a transmissive fragment reads that layer where its own
/// refracted view ray leaves the body. What a mean-diff snapshot cannot pin is that the
/// scene arrives at all, that a frame without glass is untouched, that one piece of glass
/// stays out of another, that the body's own shape decides *where* it looks, that
/// roughness blurs what it finds, and that a traced frame takes over unchanged.
@Suite
@MainActor
struct SceneThroughGlassProbes {

    private func pixels(of image: CGImage) -> [UInt8] {
        let w = image.width, h = image.height
        var data = [UInt8](repeating: 0, count: w * h * 4)
        let ctx = CGContext(data: &data, width: w, height: h, bitsPerComponent: 8,
                            bytesPerRow: w * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        return data
    }

    private func mean(_ data: [UInt8], width: Int, height: Int, channel: Int,
                      x: ClosedRange<Double>, y: ClosedRange<Double>) -> Double {
        var sum = 0, count = 0
        for py in Int(Double(height) * y.lowerBound)..<Int(Double(height) * y.upperBound) {
            for px in Int(Double(width) * x.lowerBound)..<Int(Double(width) * x.upperBound) {
                sum += Int(data[(py * width + px) * 4 + channel]); count += 1
            }
        }
        return Double(sum) / Double(max(count, 1))
    }

    /// How red a region reads against its own blue: the wall's signature, and immune to
    /// the overall exposure the environment sets.
    private func redness(_ img: CGImage, x: ClosedRange<Double>, y: ClosedRange<Double>) -> Double {
        let d = pixels(of: img)
        return mean(d, width: img.width, height: img.height, channel: 0, x: x, y: y)
             - mean(d, width: img.width, height: img.height, channel: 2, x: x, y: y)
    }

    private func render(_ kind: SceneThroughGlassProbe.Kind) throws -> CGImage {
        try #require(OllinApp.image(of: SceneThroughGlassProbe.make(kind: kind), frame: 1))
    }

    @Test(.enabled(if: Snapshot.hasMetal))
    func theSceneShowsThroughTheGlassWithoutTracing() throws {
        // A red wall stands behind a glass sphere, out of the environment's picture. The
        // environment path can only show the studio through the sphere; the screen-space
        // read finds the wall the frame already drew, so the sphere's interior goes red
        // only when sceneThroughGlass() is on. This is the whole feature in one probe.
        let shown = try render(.wallShown)
        let envOnly = try render(.wallEnvOnly)
        let r = redness(shown, x: 0.42...0.58, y: 0.42...0.58)
        let e = redness(envOnly, x: 0.42...0.58, y: 0.42...0.58)
        #expect(r - e > 25, "expected the wall's red inside the glass: shown \(r), env-only \(e)")
    }

    @Test(.enabled(if: Snapshot.hasMetal))
    func aFrameWithNoGlassIsUntouched() throws {
        // The same scene with the sphere opaque: nothing transmits, so the pre-pass
        // never runs and the frame must come out byte-identical either way. The gate,
        // pinned at the pixel rather than by reading the code.
        let on = try render(.noGlassShown)
        let off = try render(.noGlassEnvOnly)
        #expect(pixels(of: on) == pixels(of: off))
    }

    @Test(.enabled(if: Snapshot.hasMetal))
    func oneGlassStaysOutOfAnother() throws {
        // A strongly blue-tinted glass pane stands between the red wall and a clear glass
        // sphere. The pre-pass leaves every transmissive run out, so the sphere reads the
        // wall directly and the pane never prints inside it: the sphere's interior has to
        // match the frame where the pane is absent altogether. The pane is checked to be
        // visible somewhere else first, or "absent" and "present" would agree trivially.
        let withPane = try render(.stackedWithPane)
        let without = try render(.stackedNoPane)
        let paneEdge = redness(withPane, x: 0.06...0.20, y: 0.42...0.58)
        let bareEdge = redness(without, x: 0.06...0.20, y: 0.42...0.58)
        #expect(bareEdge - paneEdge > 12,
                "the pane should be visible beside the sphere: with \(paneEdge), without \(bareEdge)")
        let inside = redness(withPane, x: 0.44...0.56, y: 0.44...0.56)
        let insideBare = redness(without, x: 0.44...0.56, y: 0.44...0.56)
        #expect(abs(inside - insideBare) < 10,
                "the pane printed inside the sphere: with \(inside), without \(insideBare)")
    }

    @Test(.enabled(if: Snapshot.hasMetal))
    func aSolidBodyLooksSomewhereElseThanAThinOne() throws {
        // The wall behind is red to the left of a vertical seam and blue to the right,
        // with the seam placed so a shifted read crosses it. A thin wall leaves parallel
        // to the view, so a pixel left of the seam still shows red; a solid body refracts
        // in, travels its interior span, and leaves further along, so the same pixel
        // shows the blue past the seam. The difference *is* the exit point being
        // projected rather than the fragment's own pixel being read, which nothing about
        // the tint or the roughness could imitate.
        let solid = try render(.barsSolid)
        let thin = try render(.barsThin)
        let s = redness(solid, x: 0.37...0.41, y: 0.47...0.53)
        let t = redness(thin, x: 0.37...0.41, y: 0.47...0.53)
        #expect(t - s > 20, "expected the solid body to read past the seam: thin \(t), solid \(s)")
    }

    @Test(.enabled(if: Snapshot.hasMetal))
    func roughnessBlursWhatShowsThrough() throws {
        // The wall behind is striped. A frosted body reads the layer at a higher mip, so
        // the stripes inside it flatten; a clear one keeps them. Measured as the spread
        // along one row through the interior, which a blur reduces and nothing else here
        // does. Both bodies are otherwise identical.
        let clear = try render(.stripesClear)
        let frosted = try render(.stripesFrosted)
        func spread(_ img: CGImage) -> Double {
            let d = pixels(of: img), w = img.width
            let row = img.height / 2
            var values: [Double] = []
            for px in Int(Double(w) * 0.38)..<Int(Double(w) * 0.62) {
                values.append(Double(d[(row * w + px) * 4]))       // the red channel
            }
            let m = values.reduce(0, +) / Double(values.count)
            return (values.reduce(0) { $0 + ($1 - m) * ($1 - m) } / Double(values.count)).squareRoot()
        }
        let sharp = spread(clear), soft = spread(frosted)
        #expect(sharp - soft > 4, "expected frosting to flatten the stripes: clear \(sharp), frosted \(soft)")
    }

    @Test(.enabled(if: Snapshot.hasMetal && Snapshot.hasRaytracing))
    func tracingTakesOverUnchanged() throws {
        // With rayTracedReflections() on, the trace walks the real geometry and the
        // screen read has nothing to add, so the renderer skips the pre-pass entirely and
        // the fragments ignore the layer. Asking for both must therefore render
        // byte-identical to asking for the trace alone: the feature costs nothing there.
        let both = try render(.tracedAndShown)
        let tracedOnly = try render(.tracedOnly)
        #expect(pixels(of: both) == pixels(of: tracedOnly))
    }

    /// How blue a region reads against its own red: the post's signature.
    private func blueness(_ img: CGImage, x: ClosedRange<Double>, y: ClosedRange<Double>) -> Double {
        -redness(img, x: x, y: y)
    }

    @Test(.enabled(if: Snapshot.hasMetal))
    func aSolidBodyIsALens() throws {
        // Far behind a solid sphere stand a red bar above the center and a blue post
        // left of it, past the distance where the bundle of rays through the ball
        // crosses. A ball lens turns that picture over: the bar has to show in the
        // lower half of the sphere and the post on its right. A thin wall reads the
        // layer at its own pixel and shows both where they stand, so the same regions
        // read the other way round. Measured as the difference between the two halves,
        // which the exposure and the tint cannot move.
        let solid = try render(.lensSolid)
        let thin = try render(.lensThin)
        func barBelow(_ img: CGImage) -> Double {
            redness(img, x: 0.42...0.58, y: 0.55...0.68) - redness(img, x: 0.42...0.58, y: 0.32...0.45)
        }
        func postRight(_ img: CGImage) -> Double {
            blueness(img, x: 0.55...0.68, y: 0.44...0.56) - blueness(img, x: 0.32...0.45, y: 0.44...0.56)
        }
        let sb = barBelow(solid), tb = barBelow(thin)
        #expect(sb > 15, "expected the red bar in the lower half of the lens: \(sb)")
        #expect(tb < -5, "expected the thin wall to show the bar upright: \(tb)")
        let sp = postRight(solid), tp = postRight(thin)
        #expect(sp > 15, "expected the blue post on the right of the lens: \(sp)")
        #expect(tp < -5, "expected the thin wall to show the post on the left: \(tp)")
    }

    @Test(.enabled(if: Snapshot.hasMetal))
    func whatStandsInFrontOfTheGlassNeverPrintsInsideIt() throws {
        // A yellow post stands between the camera and the sphere, just right of the
        // center on screen, where the exit points of the sphere's right rim project.
        // Every read of the layer lands on the post's pixels for those fragments, but
        // the post is nearer than the glass, so the ray cannot have reached it: the
        // read is refused and the environment shows there instead. The rim beside the
        // post must therefore carry none of its yellow (with the refusal gone, it
        // prints the post: verified red). The post is checked to be visible first, or
        // the two frames would agree trivially.
        let withPost = try render(.frontPost)
        let bare = try render(.frontNone)
        func yellowness(_ img: CGImage, x: ClosedRange<Double>, y: ClosedRange<Double>) -> Double {
            let d = pixels(of: img)
            let r = mean(d, width: img.width, height: img.height, channel: 0, x: x, y: y)
            let g = mean(d, width: img.width, height: img.height, channel: 1, x: x, y: y)
            let b = mean(d, width: img.width, height: img.height, channel: 2, x: x, y: y)
            return (r + g) / 2 - b
        }
        let postSeen = yellowness(withPost, x: 0.565...0.595, y: 0.05...0.15)
        let postAbsent = yellowness(bare, x: 0.565...0.595, y: 0.05...0.15)
        #expect(postSeen - postAbsent > 40,
                "the post should be visible in front: with \(postSeen), without \(postAbsent)")
        // Absolute, not against the bare frame: without the post that rim holds the
        // blue post's lens image, and with it the neutral environment, so the two
        // differ either way. Printed, the post reads above 80 here.
        let inside = yellowness(withPost, x: 0.64...0.72, y: 0.44...0.56)
        #expect(inside < 20, "the post printed inside the sphere: \(inside)")
    }

    @Test
    func theLightingConstantsStillFitAFragmentPush() {
        // `OllinLighting` travels through `setFragmentBytes`, which tops out at 4 KB on
        // Apple GPUs. The struct grows a field every few features, so the headroom is
        // worth a number rather than a hope.
        #expect(MemoryLayout<OllinLighting>.stride < 4096,
                "OllinLighting is \(MemoryLayout<OllinLighting>.stride) bytes")
    }
}

/// The probe scene for the screen-space read, one variant per case: a glass body in
/// front of content the environment knows nothing about, under a fixed camera.
private final class SceneThroughGlassProbe: Sketch {
    enum Kind {
        case wallShown, wallEnvOnly
        case noGlassShown, noGlassEnvOnly
        case stackedWithPane, stackedNoPane
        case barsSolid, barsThin
        case stripesClear, stripesFrosted
        case tracedAndShown, tracedOnly
        case lensSolid, lensThin
        case frontPost, frontNone
    }
    var kind: Kind = .wallShown

    static func make(kind: Kind) -> SceneThroughGlassProbe {
        let probe = SceneThroughGlassProbe()
        probe.kind = kind
        return probe
    }

    override var canvasSize: CanvasSize { .square(192) }

    /// The red wall the environment knows nothing about.
    private func drawWall(_ color: Color, z: Double = -2.5) {
        withState {
            fill(color)
            material(.dielectric(roughness: 0.8))
            translate(0, 0, z)
            drawBox(width: 8, height: 8, depth: 0.4)
        }
    }

    override func draw() {
        background(Color(white: 0.05))
        camera(.orbiting(target: .zero, radius: 5, azimuth: 0, elevation: 0,
                         fieldOfView: .pi / 4, near: 1, far: 20))
        environment(.studio)
        switch kind {
        case .wallShown, .wallEnvOnly:
            if kind == .wallShown { sceneThroughGlass() }
            drawWall(Color(hex: 0xd94430))
            fill(.white)
            material(.glass())
            drawSphere(radius: 1.2)

        case .noGlassShown, .noGlassEnvOnly:
            if kind == .noGlassShown { sceneThroughGlass() }
            drawWall(Color(hex: 0xd94430))
            fill(.white)
            material(.dielectric(roughness: 0.2))
            drawSphere(radius: 1.2)

        case .stackedWithPane, .stackedNoPane:
            sceneThroughGlass()
            drawWall(Color(hex: 0xd94430), z: -3.4)
            if kind == .stackedWithPane {
                withState {
                    fill(Color(hex: 0x2a4fd6))
                    material(.glass())
                    translate(0, 0, -1.8)
                    drawBox(width: 8, height: 8, depth: 0.2)
                }
            }
            fill(.white)
            material(.glass())
            drawSphere(radius: 1.0)

        case .barsSolid, .barsThin:
            // The seam sits at x = -0.375, which is where the probe's sampled column
            // reads once a solid body's exit point has moved it along.
            sceneThroughGlass()
            withState {
                fill(Color(hex: 0xd94430))
                material(.dielectric(roughness: 0.8))
                translate(-2.2, 0, -2.5)
                drawBox(width: 3.65, height: 8, depth: 0.4)
            }
            withState {
                fill(Color(hex: 0x2a4fd6))
                material(.dielectric(roughness: 0.8))
                translate(1.8, 0, -2.5)
                drawBox(width: 4.35, height: 8, depth: 0.4)
            }
            fill(.white)
            // A high index bends hard enough for the shift to clear the seam by a
            // comfortable margin rather than by a pixel or two.
            material(kind == .barsSolid ? .glass(ior: 2.4, thickness: 2.4) : .glass(ior: 2.4))
            drawSphere(radius: 1.2)

        case .stripesClear, .stripesFrosted:
            sceneThroughGlass()
            for i in 0..<9 {
                withState {
                    fill(i.isMultiple(of: 2) ? Color(hex: 0xe6533c) : Color(hex: 0x1a1d26))
                    material(.dielectric(roughness: 0.8))
                    translate((Double(i) - 4) * 0.62, 0, -2.5)
                    drawBox(width: 0.34, height: 8, depth: 0.4)
                }
            }
            fill(.white)
            material(kind == .stripesFrosted ? .glass(roughness: 0.6) : .glass())
            drawSphere(radius: 1.2)

        case .tracedAndShown, .tracedOnly:
            rayTracedReflections()
            if kind == .tracedAndShown { sceneThroughGlass() }
            drawWall(Color(hex: 0xd94430))
            fill(.white)
            material(.glass())
            drawSphere(radius: 1.2)

        case .lensSolid, .lensThin, .frontPost, .frontNone:
            // A ball of radius 1.2 at index 1.5 focuses 1.8 past its center, and the
            // bundle from a camera 5 away crosses 2.8 past it; the wall stands well
            // beyond that, where the lens's picture is the turned-over one.
            sceneThroughGlass()
            drawWall(Color(white: 0.12), z: -6.2)
            withState {
                fill(Color(hex: 0xd94430))
                material(.dielectric(roughness: 0.8))
                translate(0, 0.9, -5.9)
                drawBox(width: 8, height: 0.5, depth: 0.1)
            }
            withState {
                fill(Color(hex: 0x2a4fd6))
                material(.dielectric(roughness: 0.8))
                translate(-0.9, 0, -5.9)
                drawBox(width: 0.4, height: 8, depth: 0.1)
            }
            if kind == .frontPost {
                withState {
                    fill(Color(hex: 0xe8c23a))
                    material(.dielectric(roughness: 0.8))
                    translate(0.2, 0, 2.0)
                    drawBox(width: 0.25, height: 8, depth: 0.1)
                }
            }
            fill(.white)
            material(kind == .lensThin ? .glass() : .glass(thickness: 2.4))
            drawSphere(radius: 1.2)
        }
    }
}
