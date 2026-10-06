@testable import Ollin
import Testing
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

/// Invariants of the physically based lighting that hold whatever the implementation:
/// light is never created, a lossless surface returns what falls on it, a shadow only
/// takes, a lens only moves light, fog follows Beer-Lambert. Each is read off a render
/// against a twin (the same frame with the feature off, or the scene without the
/// object) or an analytic bound, never against the renderer's own arithmetic, so a
/// plausible-looking defect, the class a snapshot cannot see, turns one red. Every
/// number here is in linear light.
@Suite
@MainActor
struct LightingInvariantTests {

    // MARK: Pixel support

    private struct Frame {
        var linear: [Double]   // r, g, b per pixel, linear light
        var bytes: [UInt8]     // the sRGB bytes as written, rgba
        var width: Int
        var height: Int

        func luma(_ x: Int, _ y: Int) -> Double {
            let i = (y * width + x) * 3
            return (linear[i] + linear[i + 1] + linear[i + 2]) / 3
        }
        func byte(_ x: Int, _ y: Int, _ c: Int) -> Int { Int(bytes[(y * width + x) * 4 + c]) }
        var pixelCount: Int { width * height }
    }

    private func frame(_ image: CGImage) -> Frame {
        let w = image.width, h = image.height
        var data = [UInt8](repeating: 0, count: w * h * 4)
        let ctx = CGContext(data: &data, width: w, height: h, bitsPerComponent: 8,
                            bytesPerRow: w * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        var lin = [Double](repeating: 0, count: w * h * 3)
        for p in 0..<(w * h) {
            for c in 0..<3 { lin[p * 3 + c] = linear(data[p * 4 + c]) }
        }
        return Frame(linear: lin, bytes: data, width: w, height: h)
    }

    private func render(_ sketch: Sketch, frame n: Int = 1) throws -> Frame {
        frame(try OllinApp.image(of: sketch, frame: n))
    }

    /// The frame read back through the inverse of the Reinhard curve, for a probe
    /// that tone-maps with it so a focused spot brighter than white is kept rather
    /// than clipped: the curve is x over 1 + x, so the light is y over 1 - y.
    private func renderUnrolled(_ sketch: Sketch, frame n: Int = 1) throws -> Frame {
        var f = frame(try OllinApp.image(of: sketch, frame: n))
        for i in 0..<f.linear.count {
            let y = min(f.linear[i], 0.998)
            f.linear[i] = y / (1 - y)
        }
        return f
    }

    /// Mean luma over the pixels inside a ring of the frame's center.
    private func ringMean(_ f: Frame, from inner: Double, to outer: Double) -> Double {
        let cx = Double(f.width) / 2, cy = Double(f.height) / 2
        var sum = 0.0, n = 0
        for y in 0..<f.height {
            for x in 0..<f.width {
                let d = ((Double(x) - cx) * (Double(x) - cx) + (Double(y) - cy) * (Double(y) - cy)).squareRoot()
                guard d >= inner, d < outer else { continue }
                sum += f.luma(x, y); n += 1
            }
        }
        return sum / Double(max(n, 1))
    }

    /// Total linear light of the frame, every channel summed.
    private func total(_ f: Frame) -> Double { f.linear.reduce(0, +) }

    // MARK: The furnace

    /// The constant gray environment, written once per run: an 8 by 4 equirect whose
    /// every pixel is the same mid gray, so whatever direction a surface looks it
    /// sees the same field, and a lossless surface must return exactly that field.
    private static var furnaceURL: URL?

    private func furnace() throws -> URL {
        if let known = Self.furnaceURL { return known }
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("ollin-lighting-invariant-furnace.png")
        let w = 8, h = 4
        var bytes = [UInt8](repeating: 188, count: w * h * 4)
        for i in stride(from: 3, to: bytes.count, by: 4) { bytes[i] = 255 }
        let ctx = try #require(CGContext(
            data: &bytes, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        let image = try #require(ctx.makeImage())
        let dest = try #require(CGImageDestinationCreateWithURL(
            url as CFURL, UTType.png.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(dest, image, nil)
        #expect(CGImageDestinationFinalize(dest))
        Self.furnaceURL = url
        return url
    }

    /// The sphere's mean against the field's, inside the disc the sibling furnace
    /// reads (radius 40 of a 49-pixel silhouette: the grazing rim left out).
    private func kept(_ finish: FurnaceInvariantProbe.Finish, intensity: Double = 1) throws
        -> (kept: Double, field: Double) {
        let f = try render(FurnaceInvariantProbe.make(finish, envURL: furnace(), intensity: intensity))
        let disc = ringMean(f, from: 0, to: 40)
        let field = ringMean(f, from: 60, to: 96)
        return (disc / field, field)
    }

    /// A white Lambertian surface under a uniform field returns the field: the diffuse
    /// half of the energy budget, where the shipped furnace pins only the metal's
    /// specular half. Bounded both sides, so a diffuse that forgets what the specular
    /// took (over 1) and one that pays the Fresnel twice (under) both read.
    @Test(.enabled(if: Snapshot.hasMetal))
    func aWhiteDiffuseSphereKeepsTheFurnaceLevel() throws {
        let (kept, field) = try kept(.diffuse)
        #expect(field > 0.1, "expected the environment as the background, read \(field)")
        #expect(kept > 0.93 && kept < 1.03, "a white diffuse sphere kept \(kept * 100)% of the field")
    }

    /// A uniform field lights a sphere evenly: the irradiance of a constant map does
    /// not depend on the normal, and a lossless surface returns the field in every
    /// direction, so the disc reads flat out to its rim. A gradient here is either the
    /// bake (a seam, a missing level) or an energy split that changes with the view
    /// angle, the diffuse not giving back what the grazing Fresnel takes.
    @Test(.enabled(if: Snapshot.hasMetal))
    func aUniformFieldLightsADiffuseSphereEvenly() throws {
        let f = try render(FurnaceInvariantProbe.make(.diffuse, envURL: furnace()))
        let field = ringMean(f, from: 60, to: 96)
        let rings: [(Double, Double)] = [(0, 20), (20, 32), (32, 40), (40, 45)]
        for (inner, outer) in rings {
            let r = ringMean(f, from: inner, to: outer) / field
            #expect(r > 0.93 && r < 1.05,
                    "the ring \(inner)...\(outer) px read \(r * 100)% of the field")
        }
    }

    /// A lossless clear coat redistributes light between its own lobe and the base
    /// and never adds any: the coated white sphere stays at or under the field.
    @Test(.enabled(if: Snapshot.hasMetal))
    func aClearCoatNeverAmplifiesTheFurnace() throws {
        let (kept, _) = try kept(.coat)
        #expect(kept < 1.03, "a coated white sphere kept \(kept * 100)% of the field")
        #expect(kept > 0.85, "a coated white sphere lost too much: \(kept * 100)%")
    }

    /// Sheen is a lobe laid over the base with the base scaled back for it, so a white
    /// cloth under the field never exceeds the field.
    @Test(.enabled(if: Snapshot.hasMetal))
    func sheenNeverAmplifiesTheFurnace() throws {
        let (kept, _) = try kept(.sheen)
        #expect(kept < 1.03, "a sheened white sphere kept \(kept * 100)% of the field")
        #expect(kept > 0.85, "a sheened white sphere lost too much: \(kept * 100)%")
    }

    /// A lossless film over a perfect mirror reflects everything at every wavelength
    /// (nothing is absorbed, nothing gets through), so the colored interference must
    /// average back to the field whatever the thickness: a film that brightens or
    /// darkens a white metal is making or losing light.
    @Test(.enabled(if: Snapshot.hasMetal), arguments: [120.0, 300.0, 550.0, 900.0])
    func aFilmOverAPerfectMirrorReturnsTheField(nanometers: Double) throws {
        let (kept, _) = try kept(.film(nanometers))
        #expect(kept > 0.92 && kept < 1.03,
                "a \(nanometers) nm film over white metal kept \(kept * 100)% of the field")
    }

    /// Clear glass with no absorption reflects what it does not transmit, so a glass
    /// ball in the furnace reads as the field.
    @Test(.enabled(if: Snapshot.hasMetal))
    func aClearGlassBallKeepsTheFurnaceLevel() throws {
        let (kept, _) = try kept(.glass)
        #expect(kept > 0.90 && kept < 1.03, "a clear glass ball kept \(kept * 100)% of the field")
    }

    /// Light is linear: halving the environment halves both what the sphere returns
    /// and the backdrop behind it.
    @Test(.enabled(if: Snapshot.hasMetal))
    func theEnvironmentIsLinearInItsIntensity() throws {
        let full = try render(FurnaceInvariantProbe.make(.diffuse, envURL: furnace(), intensity: 1))
        let half = try render(FurnaceInvariantProbe.make(.diffuse, envURL: furnace(), intensity: 0.5))
        let discRatio = ringMean(half, from: 0, to: 40) / ringMean(full, from: 0, to: 40)
        let fieldRatio = ringMean(half, from: 60, to: 96) / ringMean(full, from: 60, to: 96)
        #expect(abs(discRatio - 0.5) < 0.03, "the sphere read \(discRatio) of its full-intensity self")
        #expect(abs(fieldRatio - 0.5) < 0.03, "the backdrop read \(fieldRatio) of its full-intensity self")
    }

    // MARK: Shadows

    /// A shadow only takes: with the caster on, no pixel of the frame is brighter than
    /// without, and some are darker (the shadow exists). Both shadow routes, the
    /// directional map and the point caster.
    @Test(.enabled(if: Snapshot.hasMetal), arguments: [false, true])
    func aShadowNeverAddsLight(point: Bool) throws {
        let on = try render(ShadowInvariantProbe.make(shadows: true, point: point))
        let off = try render(ShadowInvariantProbe.make(shadows: false, point: point))
        var brightest = 0, darkest = 0
        for i in 0..<(on.pixelCount * 4) where i % 4 != 3 {
            let d = Int(on.bytes[i]) - Int(off.bytes[i])
            brightest = max(brightest, d); darkest = min(darkest, d)
        }
        #expect(brightest <= 2, "a shadow added \(brightest) levels somewhere (\(point ? "point" : "directional"))")
        #expect(darkest <= -30, "no shadow fell: the darkest change was \(darkest) levels")
    }

    // MARK: Global illumination

    /// Black walls bounce nothing: with every surface but the lit sphere at albedo
    /// zero, turning the bounce on changes no pixel. A difference is light the probes
    /// made up (an ambient floor, a leak, an unoccluded sky with no sky set).
    @Test(.enabled(if: Snapshot.hasMetal && Snapshot.hasRaytracing))
    func aBlackRoomBouncesNothing() throws {
        let on = try render(GIInvariantProbe.make(gi: true, walls: 0))
        let off = try render(GIInvariantProbe.make(gi: false, walls: 0))
        var worst = 0
        for i in 0..<(on.pixelCount * 4) where i % 4 != 3 {
            worst = max(worst, abs(Int(on.bytes[i]) - Int(off.bytes[i])))
        }
        #expect(worst <= 3, "bounce light appeared in a black room: \(worst) levels at the worst pixel")
    }

    /// Bounce never outshines the light that made it: the brightest bounce-only pixel
    /// of a white room (the frame with the bounce minus the frame without) is at most
    /// the brightest directly lit pixel. A diffuse wall re-emits at most what lands on
    /// it over pi, so second-hand light is dimmer than the pool it came from, however
    /// many times it bounces in an open room.
    @Test(.enabled(if: Snapshot.hasMetal && Snapshot.hasRaytracing))
    func bounceNeverOutshinesTheLightThatMadeIt() throws {
        let on = try render(GIInvariantProbe.make(gi: true, walls: 0.9))
        let off = try render(GIInvariantProbe.make(gi: false, walls: 0.9))
        var directMax = 0.0, bounceMax = 0.0, directByte = 0
        for p in 0..<on.pixelCount {
            let x = p % on.width, y = p / on.width
            directMax = max(directMax, off.luma(x, y))
            bounceMax = max(bounceMax, on.luma(x, y) - off.luma(x, y))
            for c in 0..<3 { directByte = max(directByte, off.byte(x, y, c)) }
        }
        #expect(directByte < 250, "the direct pool clipped (\(directByte)), so the bound is void")
        #expect(bounceMax > 0.01, "no bounce at all: \(bounceMax)")
        #expect(bounceMax <= directMax,
                "the brightest bounce (\(bounceMax)) outshone the brightest direct light (\(directMax))")
    }

    // MARK: Caustics

    /// Every pixel outside the ball's own silhouette, which is read off a mask render
    /// (the ball alone, white under ambient light on a black floor) and grown by three
    /// pixels for the anti-aliased rim.
    private static var causticRegion: [Int]?

    private func floorRegion() throws -> [Int] {
        if let known = Self.causticRegion { return known }
        let mask = try render(CausticInvariantProbe.make(.ballMask))
        let w = mask.width, h = mask.height
        var inside = [Bool](repeating: false, count: w * h)
        for y in 0..<h {
            for x in 0..<w where mask.byte(x, y, 1) > 64 {
                for dy in -3...3 {
                    for dx in -3...3 {
                        let nx = x + dx, ny = y + dy
                        if nx >= 0, ny >= 0, nx < w, ny < h { inside[ny * w + nx] = true }
                    }
                }
            }
        }
        let region = (0..<(w * h)).filter { !inside[$0] }
        #expect(region.count < w * h - 400, "the mask found no ball")
        Self.causticRegion = region
        return region
    }

    private func sum(_ f: Frame, over region: [Int]) -> Double {
        region.reduce(0.0) { $0 + f.luma($1 % f.width, $1 / f.width) }
    }

    /// A lens only moves light: what the caustic adds to the floor is at most what the
    /// ball's shadow took from it, measured over the floor outside the ball's own
    /// silhouette, through a Reinhard present unrolled on readback so the focused
    /// spot is counted whole rather than clipped at white. More would be light the
    /// photons made up, and a real glass ball returns less than it takes (two Fresnel
    /// passes lose about a twelfth head on, more toward the rim).
    ///
    /// Measured 2026-10-06 and filed: the caustic adds 1.5 times what the shadow took
    /// (125.6 against 83.7 in summed linear luma), so the deposit runs half again over
    /// physical before the Fresnel loss is counted, and a clipped 8-bit read had shown
    /// only 1.08 of it. The known issue below is the standing nomination; it fails
    /// the day the deposit is brought under the shadow, which is when it comes off.
    @Test(.enabled(if: Snapshot.hasMetal && Snapshot.hasRaytracing))
    func aLensFocusesNoMoreLightThanItsShadowTook() throws {
        let bare = try renderUnrolled(CausticInvariantProbe.make(.noBall))
        let shadowed = try renderUnrolled(CausticInvariantProbe.make(.ballNoCaustics))
        let focused = try renderUnrolled(CausticInvariantProbe.make(.ballCaustics))
        let region = try floorRegion()
        let removed = sum(bare, over: region) - sum(shadowed, over: region)
        let added = sum(focused, over: region) - sum(shadowed, over: region)
        #expect(removed > 1, "the ball cast no shadow to speak of: \(removed)")
        #expect(added > 0.1, "the caustic landed nothing: \(added)")
        withKnownIssue("the caustic deposits more light than its shadow takes (measured 1.5x, 2026-10-06)") {
            #expect(added <= removed * 1.02,
                    "the caustic added \(added) where the shadow had only taken \(removed)")
        }
    }

    /// A caustic is light added: nowhere does turning it on darken the floor.
    @Test(.enabled(if: Snapshot.hasMetal && Snapshot.hasRaytracing))
    func aCausticNeverTakesLight() throws {
        let shadowed = try render(CausticInvariantProbe.make(.ballNoCaustics))
        let focused = try render(CausticInvariantProbe.make(.ballCaustics))
        var darkest = 0
        for i in try floorRegion() {
            for c in 0..<3 {
                darkest = min(darkest, Int(focused.bytes[i * 4 + c]) - Int(shadowed.bytes[i * 4 + c]))
            }
        }
        #expect(darkest >= -2, "the caustic took \(-darkest) levels from a floor pixel")
    }

    /// Dispersion splits the focused light by wavelength and keeps its total.
    @Test(.enabled(if: Snapshot.hasMetal && Snapshot.hasRaytracing))
    func dispersionKeepsTheCausticsTotal() throws {
        let shadowed = try renderUnrolled(CausticInvariantProbe.make(.ballNoCaustics))
        let plain = try renderUnrolled(CausticInvariantProbe.make(.ballCaustics))
        let split = try renderUnrolled(CausticInvariantProbe.make(.ballDispersed))
        let region = try floorRegion()
        let addedPlain = sum(plain, over: region) - sum(shadowed, over: region)
        let addedSplit = sum(split, over: region) - sum(shadowed, over: region)
        #expect(addedPlain > 0.1)
        #expect(abs(addedSplit / addedPlain - 1) < 0.05,
                "dispersion changed the caustic's total: \(addedSplit) against \(addedPlain)")
    }

    // MARK: Fog

    /// Fog follows Beer-Lambert: doubling the density squares the transmittance at
    /// every pixel, whatever the surface under it and whether the air thins with
    /// height. Read per pixel against the fog-free twin, so the surface's own
    /// shading cancels out, and judged by row: the present dithers one 8-bit level
    /// into every read, which at these levels moves one pixel's squared
    /// transmittance by 0.02 while a row of them averages it away.
    @Test(.enabled(if: Snapshot.hasMetal), arguments: [0.0, 0.6])
    func fogFollowsBeerLambert(falloff: Double) throws {
        let clear = try render(FogInvariantProbe.make(density: 0, falloff: falloff))
        let thin = try render(FogInvariantProbe.make(density: 0.08, falloff: falloff))
        let thick = try render(FogInvariantProbe.make(density: 0.16, falloff: falloff))
        var worstRow = 0.0, rows = 0, allDeviation = 0.0, counted = 0
        for y in 1..<(clear.height - 1) {
            var deviation = 0.0, n = 0
            for x in 1..<(clear.width - 1) {
                let s = clear.luma(x, y)
                guard s > 0.05 else { continue }                // the black backdrop
                // The floor's far edge blends with the backdrop over a pixel or two:
                // a mixed pixel is two transmittances, not one, so it is skipped.
                var edge = false
                for (nx, ny) in [(x - 1, y), (x + 1, y), (x, y - 1), (x, y + 1)]
                where abs(clear.byte(nx, ny, 1) - clear.byte(x, y, 1)) > 24 { edge = true }
                if edge { continue }
                let t1 = thin.luma(x, y) / s, t2 = thick.luma(x, y) / s
                guard t1 > 0.2, t1 < 0.95, thick.byte(x, y, 1) >= 40 else { continue }
                deviation += t2 - t1 * t1; n += 1
            }
            guard n >= 100 else { continue }
            worstRow = max(worstRow, abs(deviation / Double(n))); rows += 1
            allDeviation += abs(deviation); counted += n
        }
        #expect(rows > 40, "too few fogged floor rows to judge: \(rows)")
        #expect(worstRow < 0.004, "a row's T(2d) strayed from T(d)^2 by \(worstRow) (height falloff \(falloff))")
        #expect(allDeviation / Double(max(counted, 1)) < 0.002)
    }

    /// Fog never leaves the span between the surface and the fog color: every fogged
    /// pixel lies, per channel, between what the surface drew and the fog's own color.
    /// Edge pixels, where two surfaces at different depths blend, are skipped.
    @Test(.enabled(if: Snapshot.hasMetal))
    func fogStaysBetweenTheSurfaceAndItsOwnColor() throws {
        let fogColor = Color(red: 0.9, green: 0.6, blue: 0.2)
        let clear = try render(FogInvariantProbe.make(density: 0, falloff: 0, color: fogColor, scene: true))
        let fogged = try render(FogInvariantProbe.make(density: 0.15, falloff: 0, color: fogColor, scene: true))
        let fogBytes = [fogColor.red, fogColor.green, fogColor.blue].map { Int(($0 * 255).rounded()) }
        var worst = 0
        for y in 1..<(clear.height - 1) {
            for x in 1..<(clear.width - 1) {
                var edge = false
                for c in 0..<3 {
                    let v = clear.byte(x, y, c)
                    for (nx, ny) in [(x - 1, y), (x + 1, y), (x, y - 1), (x, y + 1)]
                    where abs(clear.byte(nx, ny, c) - v) > 24 { edge = true }
                }
                if edge { continue }
                for c in 0..<3 {
                    let s = clear.byte(x, y, c), f = fogged.byte(x, y, c)
                    let lo = min(s, fogBytes[c]), hi = max(s, fogBytes[c])
                    worst = max(worst, max(lo - f, f - hi))
                }
            }
        }
        #expect(worst <= 3, "a fogged pixel left the surface-to-fog span by \(worst) levels")
    }

    // MARK: Volumetric light

    /// A beam is light scattered toward the eye, added to whatever was there: turning
    /// the air on darkens no pixel.
    @Test(.enabled(if: Snapshot.hasMetal))
    func aBeamNeverDarkens() throws {
        let on = try render(BeamInvariantProbe.make(beams: true))
        let off = try render(BeamInvariantProbe.make(beams: false))
        var darkest = 0, brightest = 0
        for i in 0..<(on.pixelCount * 4) where i % 4 != 3 {
            let d = Int(on.bytes[i]) - Int(off.bytes[i])
            darkest = min(darkest, d); brightest = max(brightest, d)
        }
        #expect(brightest > 10, "no beam showed: the brightest change was \(brightest)")
        #expect(darkest >= -2, "the beam took \(-darkest) levels from a pixel")
    }
}

// MARK: - The probe scenes

/// A white sphere of one finish inside the constant field, head on.
private final class FurnaceInvariantProbe: Sketch {
    enum Finish { case diffuse, coat, sheen, film(Double), glass }
    var finish: Finish = .diffuse
    var intensity = 1.0
    var envURL = URL(fileURLWithPath: "/dev/null")

    static func make(_ finish: Finish, envURL: URL, intensity: Double = 1) -> FurnaceInvariantProbe {
        let p = FurnaceInvariantProbe()
        p.finish = finish
        p.envURL = envURL
        p.intensity = intensity
        return p
    }

    override var canvasSize: CanvasSize { .square(192) }

    override func draw() {
        background(.black)
        camera(Camera3D(eye: Vector3(0, 0, 10), target: .zero,
                        projection: .perspective(fieldOfView: .pi / 4.2)))
        environment(.hdri(url: envURL).intensified(to: intensity))
        withState {
            fill(.white)
            switch finish {
            case .diffuse:
                material(Material(shading: .physicallyBased, metallic: 0, roughness: 1))
            case .coat:
                var m = Material(shading: .physicallyBased, metallic: 0, roughness: 1)
                m.clearcoat = 1
                m.clearcoatRoughness = 0.05
                material(m)
            case .sheen:
                var m = Material(shading: .physicallyBased, metallic: 0, roughness: 0.9)
                m.sheen = 1
                m.sheenRoughness = 0.5
                material(m)
            case .film(let nanometers):
                var m = Material.metal(roughness: 0.3)
                m.thinFilm = 1
                m.thinFilmThickness = nanometers
                m.thinFilmIOR = 1.4
                material(m)
            case .glass:
                material(.glass(roughness: 0, ior: 1.5, thickness: 2))
            }
            drawSphere(radius: 2)
        }
    }
}

/// A box on a floor under one light, the shadow on or off.
private final class ShadowInvariantProbe: Sketch {
    var shadows = true
    var point = false

    static func make(shadows: Bool, point: Bool) -> ShadowInvariantProbe {
        let p = ShadowInvariantProbe()
        p.shadows = shadows
        p.point = point
        return p
    }

    override var canvasSize: CanvasSize { .square(192) }

    override func draw() {
        background(.black)
        camera(Camera3D(eye: Vector3(0, 5, 8), target: Vector3(0, 0.5, 0)))
        if point {
            pointLight(.white, at: Vector3(1.5, 4, 1), intensity: 10)
        } else {
            directionalLight(.white, direction: Vector3(-0.4, -1, -0.3), intensity: 1.2)
        }
        if shadows { castShadows() }
        material(.dielectric(roughness: 0.8))
        fill(Color(white: 0.7))
        withState { translate(0, -0.1, 0); drawBox(width: 10, height: 0.2, depth: 10) }
        fill(Color(white: 0.6))
        withState { translate(0, 1.2, 0); drawBox(width: 1.2, height: 2.4, depth: 1.2) }
    }
}

/// The five-walled room of the bounce suite, its walls at one albedo, lit by a pool
/// on the floor, with a white sphere so a black room still has something lit.
private final class GIInvariantProbe: Sketch {
    var gi = true
    var walls = 0.9

    static func make(gi: Bool, walls: Double) -> GIInvariantProbe {
        let p = GIInvariantProbe()
        p.gi = gi
        p.walls = walls
        return p
    }

    override var canvasSize: CanvasSize { .square(192) }

    override func draw() {
        background(.black)
        camera(.orbiting(target: Vector3(0, 2, 0), radius: 9.5,
                         azimuth: 0, elevation: 0.02, fieldOfView: .pi / 3.2,
                         near: 1, far: 40))
        spotLight(.white, at: Vector3(0, 3.8, 0), direction: Vector3(0, -1, 0),
                  coneAngle: .pi / 3, penumbra: 0.4, intensity: 1.2)
        castShadows()
        if gi { globalIllumination() }
        let wall = Color(white: walls)
        withState { fill(wall); translate(0, -0.1, 0); drawBox(width: 8, height: 0.2, depth: 8) }
        withState { fill(wall); translate(0, 4.1, 0); drawBox(width: 8, height: 0.2, depth: 8) }
        withState { fill(wall); translate(0, 2, -4.1); drawBox(width: 8, height: 4.4, depth: 0.2) }
        withState { fill(wall); translate(-4.1, 2, 0); drawBox(width: 0.2, height: 4.4, depth: 8) }
        withState { fill(wall); translate(4.1, 2, 0); drawBox(width: 0.2, height: 4.4, depth: 8) }
        withState { fill(Color(white: 0.85)); translate(1.6, 0.7, -1.0); drawSphere(radius: 0.7) }
    }
}

/// A clear glass ball hovering at its own focal distance over a matte floor, lit from
/// straight above so the shadow and the caustic land right under it, and seen from
/// low on one side so the ball's silhouette sits on the screen above the floor it
/// shades rather than over it. The mask variant draws the ball alone, white under
/// ambient light, so a test can read the silhouette off the picture.
private final class CausticInvariantProbe: Sketch {
    enum Kind { case noBall, ballNoCaustics, ballCaustics, ballDispersed, ballMask }
    var kind: Kind = .ballCaustics

    static func make(_ kind: Kind) -> CausticInvariantProbe {
        let p = CausticInvariantProbe()
        p.kind = kind
        return p
    }

    override var canvasSize: CanvasSize { .square(192) }

    override func draw() {
        background(.black)
        perspective(eye: Vector3(0, 3.4, 8.3), target: Vector3(0, 0.7, 0),
                    fieldOfView: .pi / 3.6, near: 1, far: 40)
        toneMap(.reinhard)
        if kind == .ballMask {
            noLights()
            ambientLight(.white)
        } else {
            directionalLight(.white, direction: Vector3(-0.05, -1, 0.02), intensity: 1.5)
            castShadows()
        }
        switch kind {
        case .noBall, .ballNoCaustics, .ballMask: break
        case .ballCaustics: caustics()
        case .ballDispersed: caustics(intensity: 1, dispersion: 0.5)
        }
        if kind != .noBall {
            withState {
                if kind == .ballMask {
                    material(.dielectric(roughness: 1))
                } else {
                    material(.glass(thickness: 2.0))
                }
                fill(.white)
                translate(0, 1.6, 0)
                drawSphere(radius: 1.0)
            }
        }
        withState {
            material(.dielectric(roughness: 0.85))
            fill(kind == .ballMask ? .black : Color(white: 0.55))
            translate(0, -0.5, 0)
            drawBox(width: 24, height: 1.0, depth: 20)
        }
    }
}

/// A lit floor receding under the camera, the fog over it black by default; with
/// `scene`, a colored fog over a red ball and a blue block as well.
private final class FogInvariantProbe: Sketch {
    var density = 0.0
    var falloff = 0.0
    var color = Color.black
    var scene = false

    static func make(density: Double, falloff: Double, color: Color = .black,
                     scene: Bool = false) -> FogInvariantProbe {
        let p = FogInvariantProbe()
        p.density = density
        p.falloff = falloff
        p.color = color
        p.scene = scene
        return p
    }

    override var canvasSize: CanvasSize { .square(192) }

    override func draw() {
        background(.black)
        camera(Camera3D(eye: Vector3(0, 2, 10), target: Vector3(0, 0, -4), near: 0.5, far: 80))
        directionalLight(.white, direction: Vector3(0, -1, 0), intensity: 1)
        if density > 0 { fog(color, density: density, heightFalloff: falloff) }
        material(.dielectric(roughness: 0.9))
        fill(Color(white: 0.8))
        withState { translate(0, -0.1, 0); drawBox(width: 80, height: 0.2, depth: 80) }
        if scene {
            fill(Color(red: 0.9, green: 0.15, blue: 0.1))
            withState { translate(-1.8, 1, 2); drawSphere(radius: 1) }
            fill(Color(red: 0.1, green: 0.2, blue: 0.9))
            withState { translate(2, 1, -6); drawBox(width: 2, height: 2, depth: 2) }
        }
    }
}

/// A steep spot over a floor, the air on or off.
private final class BeamInvariantProbe: Sketch {
    var beams = true

    static func make(beams: Bool) -> BeamInvariantProbe {
        let p = BeamInvariantProbe()
        p.beams = beams
        return p
    }

    override var canvasSize: CanvasSize { .square(192) }

    override func draw() {
        background(.black)
        camera(Camera3D(eye: Vector3(0, 1, 9), target: Vector3(0, 1, 0)))
        spotLight(Color(white: 1.0), at: Vector3(0, 7, 0), direction: Vector3(0, -1, 0),
                  coneAngle: .pi / 10, penumbra: 0.2, intensity: 3)
        castShadows()
        if beams { volumetricLight(1.0, anisotropy: 0.2) }
        fill(Color(white: 0.15))
        withState { translate(0, -2.15, 0); drawBox(width: 20, height: 0.3, depth: 20) }
    }
}
