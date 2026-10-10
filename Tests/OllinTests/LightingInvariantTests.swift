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

    /// A lens only moves light: what the caustic adds to the floor is what the ball's
    /// shadow took from it, less what the glass reflects away, measured over the floor
    /// outside the ball's own silhouette through a Reinhard present unrolled on
    /// readback so the focused spot is counted whole rather than clipped at white.
    /// A clear glass ball passes at most 0.92 (two Fresnel passes head on) and, by the
    /// full Fresnel equations averaged over its disc, 0.84; more would be light the
    /// photons made up, much less light they lost. A point light runs a little higher
    /// (0.90): it has no falloff, so a photon carries its cone's light at the length
    /// of the path it took, and a refracted path is a few percent longer than the
    /// straight line to the shadow it fills. A light's reach thins both alike.
    ///
    /// Measured 2026-10-06 and pinned as a known issue until the review of
    /// 2026-10-07: the caustic added 1.5 times what the shadow took. The stages are
    /// in `CausticEnergyTests`.
    @Test(.enabled(if: Snapshot.hasMetal && Snapshot.hasRaytracing),
          arguments: CausticInvariantProbe.Light.allCases)
    func aLensGivesBackWhatItsShadowTookLessItsReflection(_ light: CausticInvariantProbe.Light) throws {
        let bare = try renderUnrolled(CausticInvariantProbe.make(.noBall, light: light))
        let shadowed = try renderUnrolled(CausticInvariantProbe.make(.ballNoCaustics, light: light))
        let focused = try renderUnrolled(CausticInvariantProbe.make(.ballCaustics, light: light))
        let region = try floorRegion()
        let removed = sum(bare, over: region) - sum(shadowed, over: region)
        let added = sum(focused, over: region) - sum(shadowed, over: region)
        #expect(removed > 1, "the ball cast no shadow to speak of: \(removed)")
        #expect(added <= removed * 0.92,
                "the caustic added \(added) where the shadow had only taken \(removed)")
        #expect(added >= removed * 0.78,
                "the caustic added only \(added) of the \(removed) the shadow took")
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

    // MARK: Region support

    /// Mean luma over a block of the frame.
    private func mean(_ f: Frame, x: Range<Int>, y: Range<Int>) -> Double {
        var sum = 0.0
        for py in y { for px in x { sum += f.luma(px, py) } }
        return sum / Double(max(x.count * y.count, 1))
    }

    /// Mean luma over the square of half-side `radius` around a projected point.
    private func around(_ f: Frame, _ p: Vector2, radius r: Int = 2) -> Double {
        let x = Int(p.x.rounded()), y = Int(p.y.rounded())
        return mean(f, x: max(0, x - r)..<min(f.width, x + r + 1),
                    y: max(0, y - r)..<min(f.height, y + r + 1))
    }

    /// A frame rendered through the path tracer at a fixed count with no filter, so
    /// the read is the raw estimate.
    private func traced(_ sketch: Sketch, samples: Int, maxDepth: Int? = nil) throws -> Frame {
        var settings = PathTracing(samplesPerPixel: samples, denoises: false)
        if let maxDepth { settings.maxDepth = maxDepth }
        OllinApp.pathTracedExport = settings
        defer { OllinApp.pathTracedExport = nil }
        return try render(sketch)
    }

    // MARK: The furnace from every side

    /// A white dielectric returns the field from every side: under a uniform field,
    /// what its specular lobe does not reflect, the diffuse body under it gives back,
    /// so a plate reads the field head on, at 60 degrees, and at grazing, at any
    /// roughness (the published split puts 1 - (FssEss + FmsEms) into the diffuse).
    /// The sphere above is read over a disc that is mostly head on; a plate seen at
    /// one angle is where a split that leans on the view angle shows.
    @Test(.enabled(if: Snapshot.hasMetal), arguments: [0.2, 0.4, 0.5, 0.7, 1.0])
    func aWhiteDielectricReturnsTheFieldFromEverySide(roughness: Double) throws {
        for cosine in [1.0, 0.5, 0.15] {
            let f = try render(PlateInvariantProbe.make(roughness: roughness, cosine: cosine,
                                                        envURL: furnace()))
            let field = mean(f, x: 76..<116, y: 2..<12)
            let kept = mean(f, x: 76..<116, y: 90..<102) / field
            func check() {
                #expect(abs(kept - 1) < 0.02,
                        "a white plate at roughness \(roughness) seen at cosine \(cosine) kept \(kept * 100)% of the field")
            }
            // Where the measured gap shows: at grazing below roughness 1, and head on and
            // at 60 degrees at roughness 1 (97.0% and 97.9%).
            let pinned = cosine < 0.5 ? (0.2...0.7).contains(roughness) : roughness == 1
            if pinned {
                withKnownIssue("the environment's diffuse weight is 1 - F at the view angle, not 1 minus the lobe's albedo: at grazing a plate kept 90.3% at roughness 0.5 and 102.8% at 0.2, and head on 97.0% at roughness 1, measured 2026-10-09") {
                    check()
                }
            } else {
                check()
            }
        }
    }

    // MARK: A coating

    /// A coating whose index lies between the air's and the glass's reflects at both of
    /// its faces with the same change of phase, so the two reflections at best add back
    /// to the bare glass's (a half wave, where the layer is optically absent) and at a
    /// quarter wave cancel to ((n0 n2 - n1^2) / (n0 n2 + n1^2))^2, 0.353 of the bare
    /// reflection for 1.38 on 1.5 at the design wavelength (about 0.36 averaged over the
    /// visible). It never brightens the glass at any thickness.
    @Test(.enabled(if: Snapshot.hasMetal))
    func anAntireflectionCoatingNeverBrightensTheGlass() throws {
        let bare = mean(try render(CoatingInvariantProbe.make(film: nil)), x: 60..<132, y: 60..<132)
        #expect(bare > 0.05 && bare < 0.6, "the bare glass's highlight read \(bare), outside the unclipped range")
        for nanometers in [50.0, 80, 99.6, 120, 150, 200, 250, 300, 400, 500, 600] {
            let coated = mean(try render(CoatingInvariantProbe.make(film: nanometers)), x: 60..<132, y: 60..<132)
            let ratio = coated / bare
            #expect(ratio <= 1.02, "a \(nanometers) nm coating reflected \(ratio) of the bare glass")
            if nanometers == 99.6 {
                #expect(ratio > 0.31 && ratio < 0.42, "the quarter-wave coating reflected \(ratio) of the bare glass")
            }
        }
    }

    // MARK: The sky

    /// A clear day's light is mostly the sun's beam, and haze takes the beam and gives
    /// it to the sky, so a surface facing the sun stands out from one facing away by
    /// several times on a clear day and by less on a hazy one (the beam's transmittance
    /// falls with turbidity). Clear-sky measurements put that contrast near ten at this
    /// elevation; four is a conservative floor.
    @Test(.enabled(if: Snapshot.hasMetal))
    func aClearerSkyCastsHarderLight() throws {
        func contrast(_ turbidity: Double) throws -> Double {
            let toward = mean(try render(SkyInvariantProbe.make(turbidity: turbidity, facing: true)),
                              x: 86..<106, y: 86..<106)
            let away = mean(try render(SkyInvariantProbe.make(turbidity: turbidity, facing: false)),
                            x: 86..<106, y: 86..<106)
            return toward / away
        }
        let clear = try contrast(2), hazy = try contrast(8)
        #expect(clear > 1 && hazy > 1, "the side facing the sun read darker: \(clear), \(hazy)")
        withKnownIssue("the sky's sun is a disc at 25 times the sky beside it with no beam of its own, so the contrast rises with haze: 2.0 at turbidity 2 against 5.8 at 8, measured 2026-10-09") {
            #expect(clear > hazy, "a clear sky's contrast \(clear) did not exceed a hazy one's \(hazy)")
            #expect(clear >= 4, "a clear sky's contrast was \(clear)")
        }
    }

    /// An environment's light reaches the scene whole: a small sun on a flat field adds
    /// its own irradiance to a surface facing it, so the facing-to-away ratio of a white
    /// sphere's disc is 1 plus the sun's radiance times its solid angle over pi times
    /// the field's radiance, summed from the authored pixels (the ratio cancels the
    /// exposure). Below the largest half float the decode keeps the sun; past it the
    /// sun must still arrive.
    @Test(.enabled(if: Snapshot.hasMetal), arguments: [30_000.0, 60_000.0, 200_000.0])
    func anEnvironmentsSunReachesTheScene(sun: Double) throws {
        let url = try sunMap(sun: Float(sun))
        let toward = mean(try renderUnrolled(SunInvariantProbe.make(envURL: url, facing: true)),
                          x: 86..<106, y: 86..<106)
        let away = mean(try renderUnrolled(SunInvariantProbe.make(envURL: url, facing: false)),
                        x: 86..<106, y: 86..<106)
        let texel: Double = (2 * Double.pi / 256) * (Double.pi / 128)
        let fieldIrradiance: Double = Double.pi * Double(Self.sunField)
        let expected: Double = 1 + 4 * sun * texel / fieldIrradiance
        let ratio = toward / away
        func check() {
            #expect(abs(ratio / expected - 1) < 0.03,
                    "a sun of \(sun) gave a facing-to-away ratio of \(ratio) where its pixels give \(expected)")
        }
        if sun > 65_504 {
            withKnownIssue("the decode clamps a texel past the largest half float, 65,504, so a brighter sun arrives at that level: a sun of 200,000 gave 6.27 of an expected 17.1, measured 2026-10-09") {
                check()
            }
        } else {
            check()
        }
    }

    /// The field around the sun, in linear radiance.
    private static let sunField: Float = 9.5

    /// A 256 by 128 float equirect, the field at `sunField` and a 2 by 2 sun on +z,
    /// written once per brightness as OpenEXR so values past a half float survive.
    private static var sunMaps: [Float: URL] = [:]

    private func sunMap(sun: Float) throws -> URL {
        if let known = Self.sunMaps[sun] { return known }
        let w = 256, h = 128
        var px = [Float](repeating: 0, count: w * h * 4)
        for i in 0..<(w * h) {
            px[i * 4] = Self.sunField; px[i * 4 + 1] = Self.sunField; px[i * 4 + 2] = Self.sunField
            px[i * 4 + 3] = 1
        }
        for y in 63...64 {
            for x in 191...192 {
                let i = (y * w + x) * 4
                px[i] = sun; px[i + 1] = sun; px[i + 2] = sun
            }
        }
        let space = try #require(CGColorSpace(name: CGColorSpace.extendedLinearSRGB))
        let info = CGBitmapInfo.floatComponents.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
            | CGImageAlphaInfo.premultipliedLast.rawValue
        let image = try px.withUnsafeMutableBytes { raw in
            let ctx = try #require(CGContext(data: raw.baseAddress, width: w, height: h,
                                             bitsPerComponent: 32, bytesPerRow: w * 16,
                                             space: space, bitmapInfo: info))
            return try #require(ctx.makeImage())
        }
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("ollin-lighting-invariant-sun-\(Int(sun)).exr")
        let dest = try #require(CGImageDestinationCreateWithURL(
            url as CFURL, UTType.exr.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(dest, image, nil)
        #expect(CGImageDestinationFinalize(dest))
        Self.sunMaps[sun] = url
        return url
    }

    // MARK: The air

    /// Light is linear, the air's included: the light the air scatters toward the eye
    /// is the light falling on it, so doubling the scene's one light doubles every pixel
    /// of the frame, the far wall the veil covers as much as the open view.
    @Test(.enabled(if: Snapshot.hasMetal))
    func theFrameIsLinearInItsLightUnderAerialPerspective() throws {
        func farWall(aerial: Bool, gain: Double) throws -> Double {
            mean(try renderUnrolled(AerialInvariantProbe.make(aerial: aerial, gain: gain)),
                 x: 120..<180, y: 60..<90)
        }
        let open = try farWall(aerial: false, gain: 2) / farWall(aerial: false, gain: 1)
        #expect(abs(open - 2) < 0.05, "with no air, doubling the light scaled the wall by \(open)")
        let veiled = try farWall(aerial: true, gain: 2) / farWall(aerial: true, gain: 1)
        withKnownIssue("the veil's in-scattered light is a fixed level that no light in the scene scales: doubling the light scaled the veiled wall by 1.001, measured 2026-10-09") {
            #expect(abs(veiled - 2) < 0.05, "under the air, doubling the light scaled the wall by \(veiled)")
        }
    }

    // MARK: The bounce, measured

    /// The bounce is the light that arrives after the first surface, so on a ceiling
    /// the lamp never reaches it is the whole of the ceiling's light, and an export's
    /// field must give what a deep path trace of the same room gives there.
    @Test(.enabled(if: Snapshot.hasMetal && Snapshot.hasRaytracing), arguments: [0.5, 0.8])
    func theBounceMatchesADeepTrace(albedo: Double) throws {
        let lit = GIInvariantProbe.make(gi: true, walls: Color.linearToSrgb(albedo))
        let field = try render(lit)
        let unlit = try render(GIInvariantProbe.make(gi: false, walls: Color.linearToSrgb(albedo)))
        let reference = try traced(GIInvariantProbe.make(gi: false, walls: Color.linearToSrgb(albedo)),
                                   samples: 256, maxDepth: 64)
        let direct = around(unlit, lit.ceiling, radius: 6)
        #expect(direct < 0.001, "the lamp reached the ceiling directly: \(direct)")
        let bounce = around(field, lit.ceiling, radius: 6) - direct
        let truth = around(reference, lit.ceiling, radius: 6)
        #expect(truth > 0.003, "the trace found no bounce on the ceiling: \(truth)")
        func check() {
            #expect(bounce / truth > 0.85 && bounce / truth < 1.15,
                    "at albedo \(albedo) the field gave the ceiling \(bounce) where the trace gives \(truth)")
        }
        if albedo > 0.7 {
            withKnownIssue("in a light room an export's field gives the ceiling 0.77 of the bounce a 64-deep trace gives it at albedo 0.8 (0.5 holds), measured 2026-10-09") {
                check()
            }
        } else {
            check()
        }
    }

    /// A surface that glows lights what faces it under global illumination, as the docs
    /// promise and as the path tracer does: the floor under a glowing slab, which no
    /// light reaches directly, is lit by the field about as much as by the trace.
    @Test(.enabled(if: Snapshot.hasMetal && Snapshot.hasRaytracing))
    func anEmitterLightsItsNeighborsUnderGlobalIllumination() throws {
        func floor(_ f: Frame, _ p: EmitterInvariantProbe) -> Double { around(f, p.floorMark, radius: 4) }
        let darkProbe = EmitterInvariantProbe.make(gi: false, glows: false)
        let glowProbe = EmitterInvariantProbe.make(gi: false, glows: true)
        let tracedGlow = floor(try traced(glowProbe, samples: 64), glowProbe)
            - floor(try traced(darkProbe, samples: 64), darkProbe)
        #expect(tracedGlow > 0.1, "the trace did not light the floor under the glow: \(tracedGlow)")
        let direct = floor(try render(glowProbe), glowProbe)
        #expect(direct < 0.004, "the floor was lit with no bounce at all: \(direct)")
        let onProbe = EmitterInvariantProbe.make(gi: true, glows: true)
        let offProbe = EmitterInvariantProbe.make(gi: true, glows: false)
        let bounced = floor(try render(onProbe), onProbe) - floor(try render(offProbe), offProbe)
        withKnownIssue("the probe trace gathers lights, the previous field, and the environment, never emission: the floor read 0 where the trace reads 0.37, measured 2026-10-09") {
            #expect(bounced > 0.5 * tracedGlow && bounced < 1.5 * tracedGlow,
                    "the field lit the floor under the glow by \(bounced) where the trace lights it by \(tracedGlow)")
        }
    }

    /// A lamp with a reach lights nothing past it, and so bounces nothing from past it:
    /// a lamp whose reach touches no surface leaves the room dark with the field on.
    @Test(.enabled(if: Snapshot.hasMetal && Snapshot.hasRaytracing))
    func aLampAddsNoBounceBeyondItsReach() throws {
        let off = try render(ReachRoomInvariantProbe.make(gi: false))
        let on = try render(ReachRoomInvariantProbe.make(gi: true))
        let brightestDirect = off.linear.max() ?? 0
        #expect(brightestDirect < 0.004, "the lamp lit a surface past its reach: \(brightestDirect)")
        var worst = 0
        for i in 0..<(on.pixelCount * 4) where i % 4 != 3 {
            worst = max(worst, abs(Int(on.bytes[i]) - Int(off.bytes[i])))
        }
        withKnownIssue("the probe trace lights every hit at the lamp's full strength, its reach unread: the field added 255 levels and a mean of 0.68, measured 2026-10-09") {
            #expect(worst <= 3, "the field added \(worst) levels to a room the lamp cannot reach")
        }
    }

    // MARK: Shadows, measured

    /// A shadow starts where its caster stands: on the floor just past a box's base, in
    /// the umbra of a spot that casts it, the floor is dark from the first hundredth of
    /// a unit (about ten texels of the map), with no lit gap between box and shadow.
    @Test(.enabled(if: Snapshot.hasMetal))
    func aSpotShadowMeetsItsCastersBase() throws {
        let lit = SpotContactInvariantProbe.make(shadows: false)
        let shadowed = SpotContactInvariantProbe.make(shadows: true)
        let a = try render(lit), b = try render(shadowed)
        for (i, mark) in shadowed.marks.enumerated() {
            let open = around(a, lit.marks[i]), shaded = around(b, mark)
            #expect(open > 0.05, "the floor at mark \(i) was not lit with the shadow off: \(open)")
            #expect(shaded <= 0.05 * open,
                    "the floor \(SpotContactInvariantProbe.offsets[i]) past the base kept \(shaded / open) of its light")
        }
    }

    /// A disk light over a floor lights it by the disk's form factor, which has a closed
    /// form: E(r) is proportional to 1 - (h^2 + r^2 - R^2) / sqrt((h^2 + r^2 + R^2)^2 -
    /// 4 r^2 R^2), so the floor's profile against its center follows it whatever the
    /// light's units.
    @Test(.enabled(if: Snapshot.hasMetal))
    func aDiskLightFallsOffAsItsFormFactor() throws {
        let probe = DiskInvariantProbe()
        let f = try render(probe)
        let center = around(f, probe.marks[0])
        #expect(center > 0.05, "the floor under the disk read \(center)")
        let h = 1.5, R = 1.0
        func formFactor(_ r: Double) -> Double {
            let a = h * h + r * r + R * R
            return 0.5 * (1 - (h * h + r * r - R * R) / (a * a - 4 * r * r * R * R).squareRoot())
        }
        for (i, r) in DiskInvariantProbe.radii.enumerated() {
            let rendered = around(f, probe.marks[i]) / center
            let analytic = formFactor(r) / formFactor(0)
            #expect(abs(rendered - analytic) < 0.015,
                    "at \(r) from the disk's foot the floor read \(rendered) of its center where the form factor gives \(analytic)")
        }
    }

    /// A panel's shadow is the share of the panel's light the blocker stops, each spot
    /// of the panel weighted by how much it lights the floor (cos at both ends over the
    /// distance squared), computed here by a midpoint sum. Directly under the blocker's
    /// edge half the panel is hidden either way; off the edge, the unweighted count and
    /// the weighted share part.
    @Test(.enabled(if: Snapshot.hasMetal && Snapshot.hasRaytracing))
    func aPanelsShadowIsTheShareOfItsLightThatIsBlocked() throws {
        let open = PanelInvariantProbe.make(slab: false), blocked = PanelInvariantProbe.make(slab: true)
        let a = try render(open), b = try render(blocked)
        for (i, x) in PanelInvariantProbe.offsets.enumerated() {
            let rendered = around(b, blocked.marks[i]) / around(a, open.marks[i])
            var weight = 0.0, seen = 0.0
            let n = 200
            for iq in 0..<n {
                for jq in 0..<n {
                    let qx = -1 + 2 * (Double(iq) + 0.5) / Double(n), qz = -1 + 2 * (Double(jq) + 0.5) / Double(n)
                    let d2 = (qx - x) * (qx - x) + 1.5 * 1.5 + qz * qz
                    let w = 1.5 * 1.5 / (d2 * d2)
                    weight += w
                    if qx > -x { seen += w }   // the blocker at half height covers x < 0
                }
            }
            let share = seen / weight
            func check() {
                #expect(abs(rendered - share) < 0.03,
                        "at \(x) the floor kept \(rendered) of its light where the panel's weighted share is \(share)")
            }
            if x == 0 {
                check()
            } else {
                withKnownIssue("a panel's shadow rays count the panel's points unweighted: the floor kept 0.213 at -0.6 where the weighted share is 0.091, measured 2026-10-09") {
                    check()
                }
            }
        }
    }

    /// A shadow belongs to its light and its caster, not to the camera: two frames from
    /// the same eye along the same sight line, aimed at a near target and at a far one,
    /// show the same picture, the shadows included.
    @Test(.enabled(if: Snapshot.hasMetal && Snapshot.hasRaytracing))
    func aShadowIgnoresWhereTheCameraAims() throws {
        func worst(shadows: Bool) throws -> Int {
            let near = try render(AimInvariantProbe.make(shadows: shadows, far: false))
            let far = try render(AimInvariantProbe.make(shadows: shadows, far: true))
            var worst = 0
            for i in 0..<(near.pixelCount * 4) where i % 4 != 3 {
                worst = max(worst, abs(Int(near.bytes[i]) - Int(far.bytes[i])))
            }
            return worst
        }
        let unshadowed = try worst(shadows: false)
        #expect(unshadowed <= 2, "with no shadows the two aims differed by \(unshadowed) levels")
        let shadowed = try worst(shadows: true)
        withKnownIssue("a traced point light's softness scales with its distance to the camera's target, so the penumbra moves with the aim: 0.53 in linear light, measured 2026-10-09") {
            #expect(shadowed <= 2, "with shadows the two aims differed by \(shadowed) levels")
        }
    }

    // MARK: The trace

    /// A lamp with a reach lights nothing past it, in the window and in the path-traced
    /// export alike: the floor past the reach reads black either way. The traced case
    /// runs where the device traces rays.
    @Test(.enabled(if: Snapshot.hasMetal), arguments: Snapshot.hasRaytracing ? [false, true] : [false])
    func aLampLightsNothingPastItsReach(traced isTraced: Bool) throws {
        let probe = ReachFloorInvariantProbe()
        let f = isTraced ? try traced(probe, samples: 32, maxDepth: 1) : try render(probe)
        let inside = around(f, probe.inside, radius: 3), outside = around(f, probe.outside, radius: 3)
        #expect(inside > 0.02, "the floor under the lamp was not lit: \(inside)")
        func check() {
            #expect(outside < 0.004, "the floor past the reach read \(outside)")
        }
        if isTraced {
            withKnownIssue("the tracer's direct light never reads the reach: 0.108 past it, measured 2026-10-09") {
                check()
            }
        } else {
            check()
        }
    }

    /// Glass of the air's own index, with no thickness, is not there: it reflects nothing
    /// and bends nothing, so a mirror ball seen through it reads as it does without it.
    @Test(.enabled(if: Snapshot.hasMetal && Snapshot.hasRaytracing), arguments: [0.08, 0.5])
    func anIndexMatchedPaneChangesNothingInTheTrace(roughness: Double) throws {
        let bare = mean(try traced(PaneInvariantProbe.make(pane: false, roughness: roughness), samples: 128),
                        x: 52..<76, y: 52..<76)
        let through = mean(try traced(PaneInvariantProbe.make(pane: true, roughness: roughness), samples: 128),
                           x: 52..<76, y: 52..<76)
        #expect(bare > 0.05, "the ball read \(bare)")
        withKnownIssue("a ball seen through a pane of index 1 reads 12% brighter at roughness 0.08 and 8% at 0.5, measured 2026-10-09") {
            #expect(abs(through / bare - 1) < 0.03,
                    "through the pane the ball at roughness \(roughness) read \(through / bare) of itself")
        }
    }

    /// The trace's furnace with the environment sampled: in the constant field every
    /// lossless surface returns the field, so the importance tables and both halves of
    /// the multiple-importance pair are exercised against a known answer (the furnaces
    /// in `PathTraceTests` run under the flat ambient, where those tables stay off).
    @Test(.enabled(if: Snapshot.hasMetal && Snapshot.hasRaytracing))
    func theTracedFurnaceHoldsWithTheEnvironmentSampled() throws {
        let finishes: [(String, Material, ClosedRange<Double>)] = [
            ("Lambert", Material(), 0.98...1.02),
            ("a rough dielectric", Material(shading: .physicallyBased, metallic: 0, roughness: 1), 0.96...1.03),
            ("a metal at 0.3", .metal(roughness: 0.3), 0.98...1.02),
            ("a metal at 1", .metal(roughness: 1), 0.97...1.02),
        ]
        for (name, finish, bound) in finishes {
            let f = try traced(TracedFurnaceInvariantProbe.make(finish, envURL: furnace()), samples: 64)
            let kept = mean(f, x: 76..<116, y: 76..<116) / mean(f, x: 2..<30, y: 2..<30)
            #expect(bound.contains(kept), "traced, \(name) kept \(kept * 100)% of the field")
        }
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
    /// Where a point on the ceiling, which the lamp's cone never reaches, lands.
    var ceiling = Vector2.zero

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
        ceiling = project(Vector3(0, 4.0, -2)) ?? .zero
    }
}

/// A clear glass ball hovering at its own focal distance over a matte floor, lit from
/// straight above so the shadow and the caustic land right under it, and seen from
/// low on one side so the ball's silhouette sits on the screen above the floor it
/// shades rather than over it. The mask variant draws the ball alone, white under
/// ambient light, so a test can read the silhouette off the picture.
final class CausticInvariantProbe: Sketch {
    enum Kind { case noBall, ballNoCaustics, ballCaustics, ballDispersed, ballMask }
    /// The light over the ball: the sun, a lamp straight above it, or the same lamp
    /// given a reach that thins its light to about a ninth at the floor.
    enum Light: CaseIterable, Sendable { case directional, point, pointWithReach }
    var kind: Kind = .ballCaustics
    var light = Light.directional

    static func make(_ kind: Kind, light: Light = .directional) -> CausticInvariantProbe {
        let p = CausticInvariantProbe()
        p.kind = kind
        p.light = light
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
            switch light {
            case .directional:
                directionalLight(.white, direction: Vector3(-0.05, -1, 0.02), intensity: 1.5)
            case .point:
                pointLight(.white, at: Vector3(0, 6.5, 0.05), intensity: 1.5)
            case .pointWithReach:
                pointLight(.white, at: Vector3(0, 6.5, 0.05), intensity: 1.5, reach: 9)
            }
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

/// A white plate of one roughness in the constant field, seen at one angle through an
/// orthographic lens, sized so it covers the same band of the frame at every angle and
/// leaves the field showing above it.
private final class PlateInvariantProbe: Sketch {
    var roughness = 0.5
    var cosine = 1.0
    var envURL = URL(fileURLWithPath: "/dev/null")

    static func make(roughness: Double, cosine: Double, envURL: URL) -> PlateInvariantProbe {
        let p = PlateInvariantProbe()
        p.roughness = roughness
        p.cosine = cosine
        p.envURL = envURL
        return p
    }

    override var canvasSize: CanvasSize { .square(192) }

    override func draw() {
        background(.black)
        camera(Camera3D.orthographic(eye: Vector3(0, 0, 100), target: .zero, height: 4,
                                     near: 1, far: 200))
        environment(.hdri(url: envURL))
        withState {
            fill(.white)
            material(Material(shading: .physicallyBased, metallic: 0, roughness: roughness))
            rotateX(asin(cosine))
            drawPlane(width: 40, depth: 1.8 / cosine)
        }
    }
}

/// Black glass of index 1.5 under a light along the eye, bare or with a 1.38 film of one
/// thickness, so the plate's whole light is its specular reflection.
private final class CoatingInvariantProbe: Sketch {
    var film: Double?

    static func make(film: Double?) -> CoatingInvariantProbe {
        let p = CoatingInvariantProbe()
        p.film = film
        return p
    }

    override var canvasSize: CanvasSize { .square(192) }

    override func draw() {
        background(.black)
        camera(Camera3D.orthographic(eye: Vector3(0, 0, 100), target: .zero, height: 4,
                                     near: 1, far: 200))
        ambientLight(.black)
        directionalLight(.white, direction: Vector3(0, 0, -1), intensity: 0.5)
        withState {
            fill(.black)
            var m = Material(shading: .physicallyBased, metallic: 0, roughness: 0.3)
            m.ior = 1.5
            if let film {
                m.thinFilm = 1
                m.thinFilmIOR = 1.38
                m.thinFilmThickness = film
            }
            material(m)
            rotateX(.pi / 2)
            drawPlane(width: 40, depth: 40)
        }
    }
}

/// A white diffuse sphere lit by the procedural sky alone, seen from the sun's side or
/// from the opposite one.
private final class SkyInvariantProbe: Sketch {
    var turbidity = 2.0
    var facing = true

    static func make(turbidity: Double, facing: Bool) -> SkyInvariantProbe {
        let p = SkyInvariantProbe()
        p.turbidity = turbidity
        p.facing = facing
        return p
    }

    override var canvasSize: CanvasSize { .square(192) }

    override func draw() {
        background(.black)
        let elevation = 0.6
        let towardSun = Vector3(0, sin(elevation), cos(elevation))
        camera(Camera3D(eye: towardSun * (facing ? 10 : -10), target: .zero,
                        projection: .perspective(fieldOfView: .pi / 4.2)))
        environment(.sky(turbidity: turbidity, sunElevation: elevation).lightingOnly())
        fill(.white)
        material(Material(shading: .physicallyBased, metallic: 0, roughness: 1))
        drawSphere(radius: 2)
    }
}

/// A white diffuse sphere lit by an environment with a small sun on +z, seen from the
/// sun's side or the opposite one, through a Reinhard present so a bright disc is kept.
private final class SunInvariantProbe: Sketch {
    var envURL = URL(fileURLWithPath: "/dev/null")
    var facing = true

    static func make(envURL: URL, facing: Bool) -> SunInvariantProbe {
        let p = SunInvariantProbe()
        p.envURL = envURL
        p.facing = facing
        return p
    }

    override var canvasSize: CanvasSize { .square(192) }

    override func draw() {
        background(.black)
        toneMap(.reinhard)
        camera(Camera3D(eye: Vector3(0, 0, facing ? 10 : -10), target: .zero,
                        projection: .perspective(fieldOfView: .pi / 4.2)))
        environment(.hdri(url: envURL).lightingOnly())
        fill(.white)
        material(Material(shading: .physicallyBased, metallic: 0, roughness: 1))
        drawSphere(radius: 2)
    }
}

/// A gray wall near and a gray wall far under one light, the air on or off, through a
/// Reinhard present.
private final class AerialInvariantProbe: Sketch {
    var aerial = true
    var gain = 1.0

    static func make(aerial: Bool, gain: Double) -> AerialInvariantProbe {
        let p = AerialInvariantProbe()
        p.aerial = aerial
        p.gain = gain
        return p
    }

    override var canvasSize: CanvasSize { .square(192) }

    override func draw() {
        background(.black)
        toneMap(.reinhard)
        camera(Camera3D(eye: Vector3(0, 1, 0), target: Vector3(0, 1, -10)))
        ambientLight(.black)
        directionalLight(.white, direction: Vector3(0.5, -0.6, -0.6), intensity: gain)
        if aerial { aerialPerspective(density: 0.02, haziness: 0.3) }
        fill(Color(white: 0.5))
        material(.dielectric(roughness: 1))
        withState { translate(-2, 1, -8); drawBox(width: 3, height: 3, depth: 0.2) }
        withState { translate(0, 1, -200); drawBox(width: 400, height: 400, depth: 1) }
    }
}

/// A white floor with a black slab hovering over it, the slab's underside glowing or
/// not; the one light shines straight up, so it lights no surface the camera sees.
private final class EmitterInvariantProbe: Sketch {
    var gi = true
    var glows = true
    var floorMark = Vector2.zero

    static func make(gi: Bool, glows: Bool) -> EmitterInvariantProbe {
        let p = EmitterInvariantProbe()
        p.gi = gi
        p.glows = glows
        return p
    }

    override var canvasSize: CanvasSize { .square(192) }

    override func draw() {
        background(.black)
        camera(Camera3D(eye: Vector3(0, 1.2, 4), target: Vector3(0, 0.3, 0), near: 0.1, far: 40))
        directionalLight(.white, direction: Vector3(0, 1, 0), intensity: 1)
        if gi { globalIllumination() }
        fill(Color(white: 0.906))
        material(.dielectric(roughness: 1))
        withState { translate(0, -0.1, 0); drawBox(width: 8, height: 0.2, depth: 8) }
        withState {
            fill(.black)
            translate(0, 1.0, 0)
            drawMesh(Mesh.box(width: 2, height: 0.04, depth: 2)
                .surfaceMapped(emissiveColor: glows ? .white : .black))
        }
        floorMark = project(Vector3(0, 0, 0.6)) ?? .zero
    }
}

/// The five-walled room with a lamp in its middle whose reach ends before any wall,
/// the floor, the ceiling, or anything else.
private final class ReachRoomInvariantProbe: Sketch {
    var gi = true

    static func make(gi: Bool) -> ReachRoomInvariantProbe {
        let p = ReachRoomInvariantProbe()
        p.gi = gi
        return p
    }

    override var canvasSize: CanvasSize { .square(192) }

    override func draw() {
        background(.black)
        camera(.orbiting(target: Vector3(0, 2, 0), radius: 9.5,
                         azimuth: 0, elevation: 0.02, fieldOfView: .pi / 3.2,
                         near: 1, far: 40))
        ambientLight(.black)
        pointLight(.white, at: Vector3(0, 2.1, 0), intensity: 3, reach: 1.5)
        castShadows()
        if gi { globalIllumination() }
        let wall = Color(white: 0.9)
        withState { fill(wall); translate(0, -0.1, 0); drawBox(width: 8, height: 0.2, depth: 8) }
        withState { fill(wall); translate(0, 4.1, 0); drawBox(width: 8, height: 0.2, depth: 8) }
        withState { fill(wall); translate(0, 2, -4.1); drawBox(width: 8, height: 4.4, depth: 0.2) }
        withState { fill(wall); translate(-4.1, 2, 0); drawBox(width: 0.2, height: 4.4, depth: 8) }
        withState { fill(wall); translate(4.1, 2, 0); drawBox(width: 0.2, height: 4.4, depth: 8) }
    }
}

/// A unit box on a floor under a hard spot from one side, with marks on the floor just
/// past the box's far base, all inside the umbra.
private final class SpotContactInvariantProbe: Sketch {
    static let offsets = [0.03, 0.08, 0.15, 0.6]
    var shadows = true
    var marks: [Vector2] = []

    static func make(shadows: Bool) -> SpotContactInvariantProbe {
        let p = SpotContactInvariantProbe()
        p.shadows = shadows
        return p
    }

    override var canvasSize: CanvasSize { .square(192) }

    override func draw() {
        background(.black)
        camera(Camera3D(eye: Vector3(3, 2.5, 5), target: Vector3(0.5, 0, 0), near: 0.1, far: 40))
        ambientLight(.black)
        spotLight(.white, at: Vector3(-3, 3, 0), direction: Vector3(1, -1, 0),
                  coneAngle: .pi / 3, penumbra: 0.2, intensity: 2)
        if shadows { castShadows() }
        shadowSoftness(0)
        fill(Color(white: 0.7))
        material(.dielectric(roughness: 1))
        withState { translate(0, -0.1, 0); drawBox(width: 12, height: 0.2, depth: 12) }
        withState { translate(0, 0.5, 0); drawBox(width: 1, height: 1, depth: 1) }
        marks = Self.offsets.map { project(Vector3(0.5 + $0, 0, 0)) ?? .zero }
    }
}

/// A unit disk light facing down at height 1.5 over a Lambert floor, seen from straight
/// above, with marks along the floor at set distances from the disk's foot.
private final class DiskInvariantProbe: Sketch {
    static let radii = [0.0, 0.5, 1.0, 1.5, 2.5]
    var marks: [Vector2] = []

    override var canvasSize: CanvasSize { .square(192) }

    override func draw() {
        background(.black)
        camera(Camera3D.orthographic(eye: Vector3(0, 10, 0.001), target: .zero, height: 7,
                                     near: 1, far: 40))
        ambientLight(.black)
        diskLight(.white, at: Vector3(0, 1.5, 0), direction: Vector3(0, -1, 0), radius: 1,
                  intensity: 1, castsShadow: false)
        fill(Color(white: 0.7))
        material(Material())
        withState { translate(0, -0.1, 0); drawBox(width: 12, height: 0.2, depth: 12) }
        marks = Self.radii.map { project(Vector3($0, 0, 0)) ?? .zero }
    }
}

/// A 2 by 2 panel facing down at height 1.5 over a Lambert floor, with a thin blocker at
/// half height covering everything at negative x, seen from low in front.
private final class PanelInvariantProbe: Sketch {
    static let offsets = [-0.6, -0.3, 0.0, 0.3, 0.6]
    var slab = true
    var marks: [Vector2] = []

    static func make(slab: Bool) -> PanelInvariantProbe {
        let p = PanelInvariantProbe()
        p.slab = slab
        return p
    }

    override var canvasSize: CanvasSize { .square(192) }

    override func draw() {
        background(.black)
        camera(Camera3D(eye: Vector3(0, 0.3, 5), target: .zero, near: 0.1, far: 40))
        ambientLight(.black)
        rectangleLight(.white, at: Vector3(0, 1.5, 0), direction: Vector3(0, -1, 0),
                       width: 2, height: 2, intensity: 2)
        castShadows()
        shadowSamples(256)
        fill(Color(white: 0.7))
        material(Material())
        withState { translate(0, -0.1, 0); drawBox(width: 12, height: 0.2, depth: 12) }
        if slab { withState { translate(-3, 0.75, 0); drawBox(width: 6, height: 0.02, depth: 8) } }
        marks = Self.offsets.map { project(Vector3($0, 0, 0)) ?? .zero }
    }
}

/// The shadow box of `ShadowInvariantProbe` under its point light, the camera aimed at
/// the box or at a point three times as far along the same sight line.
private final class AimInvariantProbe: Sketch {
    var shadows = true
    var far = false

    static func make(shadows: Bool, far: Bool) -> AimInvariantProbe {
        let p = AimInvariantProbe()
        p.shadows = shadows
        p.far = far
        return p
    }

    override var canvasSize: CanvasSize { .square(192) }

    override func draw() {
        background(.black)
        let eye = Vector3(0, 5, 8), target = Vector3(0, 0.5, 0)
        camera(Camera3D(eye: eye, target: far ? eye + (target - eye) * 3 : target))
        pointLight(.white, at: Vector3(1.5, 4, 1), intensity: 10)
        if shadows { castShadows() }
        material(.dielectric(roughness: 0.8))
        fill(Color(white: 0.7))
        withState { translate(0, -0.1, 0); drawBox(width: 10, height: 0.2, depth: 10) }
        fill(Color(white: 0.6))
        withState { translate(0, 1.2, 0); drawBox(width: 1.2, height: 2.4, depth: 1.2) }
    }
}

/// A lamp with a reach of 2.5 one unit over a Lambert floor, with a mark under it and a
/// mark well past the reach.
private final class ReachFloorInvariantProbe: Sketch {
    var inside = Vector2.zero
    var outside = Vector2.zero

    override var canvasSize: CanvasSize { .square(128) }

    override func draw() {
        background(.black)
        camera(Camera3D(eye: Vector3(0, 6, 6), target: .zero, near: 0.1, far: 40))
        ambientLight(.black)
        pointLight(.white, at: Vector3(-2, 1, 0), intensity: 1, reach: 2.5)
        fill(Color(white: 0.7))
        material(Material())
        withState { translate(0, -0.1, 0); drawBox(width: 12, height: 0.2, depth: 12) }
        inside = project(Vector3(-2, 0, 0)) ?? .zero
        outside = project(Vector3(2, 0, 0)) ?? .zero
    }
}

/// A white metal ball under the interior environment, seen bare or through a pane of
/// clear glass of index 1 and no thickness.
private final class PaneInvariantProbe: Sketch {
    var pane = true
    var roughness = 0.08

    static func make(pane: Bool, roughness: Double) -> PaneInvariantProbe {
        let p = PaneInvariantProbe()
        p.pane = pane
        p.roughness = roughness
        return p
    }

    override var canvasSize: CanvasSize { .square(128) }

    override func draw() {
        background(.black)
        camera(Camera3D(eye: Vector3(0, 0, 5), target: .zero))
        environment(Environment.interior.lightingOnly())
        withState { fill(.white); material(.metal(roughness: roughness)); drawSphere(radius: 1.2) }
        if pane {
            withState {
                fill(.white)
                material(.glass(roughness: 0, ior: 1, thickness: 0))
                translate(0, 0, 3)
                drawBox(width: 4, height: 4, depth: 0.01)
            }
        }
    }
}

/// A white sphere of one finish in the constant field, for the path tracer.
private final class TracedFurnaceInvariantProbe: Sketch {
    var finish = Material()
    var envURL = URL(fileURLWithPath: "/dev/null")

    static func make(_ finish: Material, envURL: URL) -> TracedFurnaceInvariantProbe {
        let p = TracedFurnaceInvariantProbe()
        p.finish = finish
        p.envURL = envURL
        return p
    }

    override var canvasSize: CanvasSize { .square(192) }

    override func draw() {
        background(.black)
        camera(Camera3D(eye: Vector3(0, 0, 10), target: .zero,
                        projection: .perspective(fieldOfView: .pi / 4.2)))
        environment(.hdri(url: envURL))
        fill(.white)
        material(finish)
        drawSphere(radius: 2)
    }
}
