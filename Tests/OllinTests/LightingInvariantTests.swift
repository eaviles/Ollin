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

    /// Pieces of one solid touch face to face, so a probe ray inside it meets the face
    /// one piece is left by and the face the next is entered by at one distance. An
    /// opaque traversal committed whichever it reached first, which was not the same one
    /// from render to render, and the field moved a level on a lit face (a peer's
    /// fractured cube: 12 of 35 frames of two quiet exports, 2026-10-15). The probe
    /// trace settles a tie by a fixed order, so the same frame draws the same bytes.
    @Test(.enabled(if: Snapshot.hasMetal && Snapshot.hasRaytracing))
    func touchingPiecesBounceTheSameLightEveryTime() throws {
        let first = try render(TouchingPiecesProbe())
        for run in 1..<4 {
            let again = try render(TouchingPiecesProbe())
            let moved = zip(first.bytes, again.bytes).filter { $0 != $1 }.count
            #expect(moved == 0, "render \(run) moved \(moved) bytes off the first")
        }
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

    /// The mean of each channel over the same square, for a reading of a color.
    private func channels(_ f: Frame, _ p: Vector2, radius r: Int = 2) -> SIMD3<Double> {
        let cx = Int(p.x.rounded()), cy = Int(p.y.rounded())
        var sum = SIMD3<Double>.zero
        var n = 0
        for y in max(0, cy - r)..<min(f.height, cy + r + 1) {
            for x in max(0, cx - r)..<min(f.width, cx + r + 1) {
                let i = (y * f.width + x) * 3
                sum += SIMD3(f.linear[i], f.linear[i + 1], f.linear[i + 2])
                n += 1
            }
        }
        return sum / Double(max(n, 1))
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

    /// The same, read back through the inverse of the Reinhard curve, for a probe that
    /// tone-maps with it.
    private func tracedUnrolled(_ sketch: Sketch, samples: Int) throws -> Frame {
        let settings = PathTracing(samplesPerPixel: samples, denoises: false)
        OllinApp.pathTracedExport = settings
        defer { OllinApp.pathTracedExport = nil }
        return try renderUnrolled(sketch)
    }

    // MARK: The furnace from every side

    /// A white dielectric returns the field from every side: under a uniform field,
    /// what its specular lobe does not reflect, the diffuse body under it gives back,
    /// so a plate reads the field head on, at 60 degrees, and at grazing, at any
    /// roughness (the published split puts 1 - (FssEss + FmsEms) into the diffuse).
    /// The sphere above is read over a disc that is mostly head on; a plate seen at
    /// one angle is where a split that leans on the view angle shows.
    /// The plate is read twice, plain and with a white occlusion map, which shades through
    /// the surface-mapped pipeline's own copy of the environment's split.
    @Test(.enabled(if: Snapshot.hasMetal), arguments: [0.2, 0.4, 0.5, 0.7, 1.0])
    func aWhiteDielectricReturnsTheFieldFromEverySide(roughness: Double) throws {
        for mapped in [false, true] {
            for cosine in [1.0, 0.5, 0.15] {
                let f = try render(PlateInvariantProbe.make(roughness: roughness, cosine: cosine,
                                                            mapped: mapped, envURL: furnace()))
                let field = mean(f, x: 76..<116, y: 2..<12)
                let kept = mean(f, x: 76..<116, y: 90..<102) / field
                #expect(abs(kept - 1) < 0.02,
                        "a white plate\(mapped ? " with maps" : "") at roughness \(roughness) seen at cosine \(cosine) kept \(kept * 100)% of the field")
            }
        }
    }

    /// The same plate under the lamps' own terms: the path tracer shades every light and
    /// every bounce through the surface function the lit fragments use for a lamp, so its
    /// furnace is the lamps' furnace. What the lobe does not reflect toward the eye the
    /// body gives back, at every angle; a body kept by one minus the Fresnel at the half
    /// vector returned 135% of the field at grazing at roughness 0.2 (2026-10-16).
    @Test(.enabled(if: Snapshot.hasMetal && Snapshot.hasRaytracing), arguments: [0.2, 0.5, 1.0])
    func aWhiteDielectricReturnsTheFieldFromEverySideInTheTrace(roughness: Double) throws {
        for cosine in [1.0, 0.5, 0.15] {
            let f = try traced(PlateInvariantProbe.make(roughness: roughness, cosine: cosine,
                                                        envURL: furnace()), samples: 128)
            let field = mean(f, x: 76..<116, y: 2..<12)
            let kept = mean(f, x: 76..<116, y: 90..<102) / field
            #expect(abs(kept - 1) < 0.02,
                    "traced, a white plate at roughness \(roughness) seen at cosine \(cosine) kept \(kept * 100)% of the field")
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

    /// A clear day's light is mostly the sun's beam. The procedural sky's sun is the sky
    /// model's own solar radiance, integrated over the disc and through the observer
    /// into the sky's unit, so a white surface facing it stands out from one facing away
    /// by the model's own ratio: 4.76 at turbidity 2 and this elevation, worked out from
    /// the published model's full source in a separate program (the disc over 512 rings,
    /// the sky's irradiance over 130,000 directions, the channels' plain mean as the
    /// frame's luma), where the sky without a sun gives 1.99 (the 2.0 this read before
    /// the sun was a light, 2026-10-09). The surface facing away sees the ground over
    /// half its hemisphere, and the ground is a matte ground the sun lights: the sky's
    /// dimmed mirror stood there until 2026-10-26, about a quarter as bright, which read
    /// 8.59 in the same program.
    ///
    /// Haze takes the beam and gives it to the sky, so a hazy day's shadows are softer: a
    /// white floor in the sun against the same floor in a slab's shadow reads 3.45 at
    /// turbidity 2 and 1.89 at 8 in that program. The surface facing the sun is not the
    /// reading for haze: the haze's glow gathers around the sun and lights that surface
    /// too, so its contrast rises with haze (5.29 at turbidity 8 in the same program).
    @Test(.enabled(if: Snapshot.hasMetal))
    func aClearerSkyCastsHarderLight() throws {
        let toward = mean(try renderUnrolled(SkyInvariantProbe.make(turbidity: 2, facing: true)),
                          x: 86..<106, y: 86..<106)
        let away = mean(try renderUnrolled(SkyInvariantProbe.make(turbidity: 2, facing: false)),
                        x: 86..<106, y: 86..<106)
        let facing = toward / away
        #expect(facing >= 4, "a clear sky's facing-to-away contrast was \(facing)")
        #expect(abs(facing / 4.76 - 1) < 0.05,
                "a clear sky's facing-to-away contrast was \(facing) where the model gives 4.76")
        func shadow(_ turbidity: Double) throws -> Double {
            let probe = SkyShadowInvariantProbe.make(turbidity: turbidity)
            let f = try renderUnrolled(probe)
            return around(f, probe.lit, radius: 4) / around(f, probe.shaded, radius: 4)
        }
        let clear = try shadow(2), hazy = try shadow(8)
        #expect(abs(clear / 3.45 - 1) < 0.05, "a clear sky's sun-to-shadow contrast was \(clear) where the model gives 3.45")
        #expect(abs(hazy / 1.89 - 1) < 0.05, "a hazy sky's sun-to-shadow contrast was \(hazy) where the model gives 1.89")
        #expect(clear > hazy, "a clear sky's shadow contrast \(clear) did not exceed a hazy one's \(hazy)")
    }

    /// A floor gathers the whole sky: a white plain floor under the procedural sky without
    /// its sun receives the sky's irradiance on a level surface, the model's own (worked
    /// out in a separate program over 23 million directions: 12.58, 21.77, 37.62 at
    /// turbidity 2 and 43.93, 47.38, 51.65 at 8, in the sky's unit), at the bake's
    /// exposure. The bake once read the middle of its up face through the environment's
    /// coarsest level, the whole face averaged with the ground, and floors lost 3 to 8% of
    /// a clear sky and 14% of a hazy one (measured 2026-10-14). The hazy sky's glow is so
    /// sharp at the sun that the cube's box-filtered levels spread it a little wide, which
    /// reads 2 to 6% high; the clear sky reads within 2%.
    @Test(.enabled(if: Snapshot.hasMetal), arguments: [2.0, 8.0])
    func aFloorGathersTheWholeSky(turbidity: Double) throws {
        let model = turbidity == 2 ? SIMD3<Double>(12.584, 21.769, 37.616) : SIMD3<Double>(43.933, 47.375, 51.649)
        let probe = SkyFloorInvariantProbe.make(turbidity: turbidity)
        let f = try renderUnrolled(probe)
        let read = channels(f, Vector2(32, 32), radius: 4)
        let exposure = Double(SkySun(turbidity: turbidity, elevation: 0.6, groundAlbedo: 0.3)
            .exposure(sunLit: false, coverage: nil))
        let tolerance = turbidity == 2 ? 0.03 : 0.08
        for k in 0..<3 {
            let gathered = read[k] * Double.pi / exposure
            #expect(abs(gathered / model[k] - 1) < tolerance,
                    "at turbidity \(turbidity) channel \(k) the floor gathered \(gathered) where the sky gives \(model[k])")
        }
    }

    /// The same for a loaded map: a flat field with a bright ring overhead (the
    /// equirect's rows 22 to 28, from 30.9 to 40.8 degrees off the zenith), where a level
    /// floor gathers the field over the sky less the ring, and the ring: pi F plus
    /// pi (C - F) (sin^2 b - sin^2 a), so the ring lights the floor 1 + (C - F)(sin^2 b -
    /// sin^2 a) / F times as much as the field alone (1.35 for this ring). Each map is
    /// auto-exposed to one average, the decoder's mean of the rows weighted by the sine of
    /// their polar angle, so the frame's ratio carries the field's average over the
    /// ring's (1.218 in all). The ring crosses the up face, the face whose middle the bake
    /// once read through its coarsest level.
    @Test(.enabled(if: Snapshot.hasMetal))
    func aFloorGathersAnOverheadRing() throws {
        let field = Double(Self.sunField), ring = 30.0
        func floor(_ r: Float?) throws -> Double {
            let probe = MapFloorInvariantProbe.make(envURL: try ringMap(ring: r))
            return around(try renderUnrolled(probe), Vector2(32, 32), radius: 4)
        }
        let a = 22.0 / 128 * Double.pi, b = 29.0 / 128 * Double.pi
        let gathered = 1 + (ring - field) * (pow(sin(b), 2) - pow(sin(a), 2)) / field
        var weighted = 0.0, weights = 0.0
        for row in 0..<128 {
            let w = sin((Double(row) + 0.5) / 128 * Double.pi)
            weighted += ((22...28).contains(row) ? ring : field) * w
            weights += w
        }
        let expected = gathered * field / (weighted / weights)
        let ratio = try floor(Float(ring)) / floor(nil)
        #expect(abs(ratio / expected - 1) < 0.03,
                "a floor under an overhead ring read \(ratio) times the field's where the map gives \(expected)")
    }

    /// A 256 by 128 float equirect, the field at `sunField` and its rows 22 to 28 at
    /// `ring` (or none), written once per brightness as OpenEXR.
    private static var ringMaps: [Float: URL] = [:]

    private func ringMap(ring: Float?) throws -> URL {
        let key = ring ?? 0
        if let known = Self.ringMaps[key] { return known }
        let w = 256, h = 128
        var px = [Float](repeating: 0, count: w * h * 4)
        for i in 0..<(w * h) {
            let row = i / w
            let v = (ring != nil && (22...28).contains(row)) ? ring! : Self.sunField
            px[i * 4] = v; px[i * 4 + 1] = v; px[i * 4 + 2] = v
            px[i * 4 + 3] = 1
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
            .appendingPathComponent("ollin-lighting-invariant-ring-\(Int(key)).exr")
        let dest = try #require(CGImageDestinationCreateWithURL(
            url as CFURL, UTType.exr.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(dest, image, nil)
        #expect(CGImageDestinationFinalize(dest))
        Self.ringMaps[key] = url
        return url
    }

    // MARK: The ground under the sky, and the cloud before the sun

    /// The sky's irradiance on a level surface, worked out on the CPU for the sun-lit
    /// ground's exposure, is the model's own: the numbers the floor test reads (over 23
    /// million directions in a separate program), within half a percent.
    @Test(arguments: [2.0, 8.0])
    func theSkysLevelIrradianceIsTheModels(turbidity: Double) {
        let model = turbidity == 2 ? SIMD3<Double>(12.584, 21.769, 37.616) : SIMD3<Double>(43.933, 47.375, 51.649)
        let sun = SkySun(turbidity: turbidity, elevation: 0.6, groundAlbedo: 0.3)
        for k in 0..<3 {
            #expect(abs(sun.levelIrradiance[k] / model[k] - 1) < 0.005,
                    "at turbidity \(turbidity) channel \(k) the level irradiance was \(sun.levelIrradiance[k]) where the model gives \(model[k])")
        }
    }

    /// The ground under a sun-lit sky is a matte ground the sun lights: the backdrop
    /// below the horizon is one radiance, the albedo times the level irradiance of sky
    /// and beam over pi, at the bake's exposure. The bake reads the sky's half off its
    /// own upper hemisphere on the GPU; the CPU's closed form says the same within 3%.
    /// With the sun not a light the ground stays the sky's dimmed mirror, the ray
    /// mirrored into the sky at the sky's own exposure.
    @Test(.enabled(if: Snapshot.hasMetal))
    func theGroundUnderASunlitSkyIsAMatteGroundTheSunLights() throws {
        let sun = SkySun(turbidity: 2, elevation: 0.6, groundAlbedo: 0.3)
        let lit = channels(try renderUnrolled(SkyGroundInvariantProbe.make(look: .ground)),
                           Vector2(96, 96), radius: 6)
        let model = sun.groundRadiance(coverage: nil) * Double(sun.exposure(sunLit: true, coverage: nil))
        for k in 0..<3 {
            #expect(abs(lit[k] / model[k] - 1) < 0.03,
                    "channel \(k) of the sunlit ground read \(lit[k]) where the model gives \(model[k])")
        }
        let unlit = channels(try renderUnrolled(SkyGroundInvariantProbe.make(look: .ground, sunlight: .off)),
                             Vector2(96, 96), radius: 2)
        let (configs, radiances) = SkySun.configurations(turbidity: 2, albedo: 0.3, elevation: 0.6)
        let d = SkyGroundInvariantProbe.groundRay
        let s = SIMD3<Double>(0, sin(0.6), cos(0.6))
        let gamma = acos(max(-1, min(1, d.x * s.x - d.y * s.y + d.z * s.z)))
        let exposure = Double(sun.exposure(sunLit: false, coverage: nil))
        for k in 0..<3 {
            let mirror = 0.3 * SkySun.radiance(configs: configs, radiances: radiances,
                                               cosTheta: -d.y, gamma: gamma, channel: k) * exposure
            #expect(abs(unlit[k] / mirror - 1) < 0.05,
                    "channel \(k) of the unlit ground read \(unlit[k]) where the sky's mirror gives \(mirror)")
        }
    }

    /// The same ground against a trace: a white matte plane under the same sky, traced,
    /// returns the irradiance of sky and sun over pi (a white dielectric returns the
    /// field), so the baked ground over its albedo reads the traced plane within 5%.
    @Test(.enabled(if: Snapshot.hasRaytracing))
    func theGroundUnderTheSkyIsTheTracesGround() throws {
        let ground = channels(try renderUnrolled(SkyGroundInvariantProbe.make(look: .ground)),
                              Vector2(96, 96), radius: 6)
        let plane = channels(try tracedUnrolled(SkyGroundInvariantProbe.make(look: .whitePlane), samples: 64),
                             Vector2(96, 96), radius: 6)
        for k in 0..<3 {
            let ratio = (ground[k] / 0.3) / plane[k]
            #expect(abs(ratio - 1) < 0.05,
                    "channel \(k) of the baked ground over its albedo read \(ground[k] / 0.3) where the traced plane gives \(plane[k])")
        }
    }

    /// A face turned down reads the ground the trace sees: a white plate high over a
    /// matte floor of the sky's own ground albedo, its underside against its top, reads
    /// the same ratio through the raster (the irradiance bake's lower half) as through
    /// the trace (the floor itself), within 10%; a matte floor under the light that
    /// lights the top gives the underside its albedo's share, 0.3. Over the sky's
    /// mirror the raster read about a quarter of it.
    @Test(.enabled(if: Snapshot.hasRaytracing))
    func aFaceTurnedDownReadsTheGroundTheTraceSees() throws {
        func ratio(_ render: (Sketch) throws -> Frame) throws -> Double {
            let under = mean(try render(SkyGroundInvariantProbe.make(look: .underside)), x: 86..<106, y: 86..<106)
            let top = mean(try render(SkyGroundInvariantProbe.make(look: .top)), x: 86..<106, y: 86..<106)
            return under / top
        }
        let raster = try ratio { try renderUnrolled($0) }
        let traced = try ratio { try tracedUnrolled($0, samples: 64) }
        #expect(abs(raster / traced - 1) < 0.1,
                "the underside read \(raster) of the top through the raster and \(traced) through the trace")
        #expect(abs(raster / 0.3 - 1) < 0.1, "the underside read \(raster) of the top where a matte floor gives 0.3")
    }

    /// The sun's share follows the clouds the backdrop shows: the bake marches the cloud
    /// shell toward the sun with the same extinction the backdrop composites its disc
    /// with, so the beam's share is the disc's own dimming, 1 in a gap and under a fifth
    /// behind a thick cloud, and the light scales by it under one exposure (the exposure
    /// keeps the clouds' expected share, so a passing cloud never swings it). A headless
    /// frame reads the share of its own bake, so one image already has it.
    @Test(.enabled(if: Snapshot.hasMetal))
    func theSunsShareFollowsTheCloudsTheBackdropShows() throws {
        func sun(phase: Double) throws -> (share: Double?, disc: Double, light: Double?) {
            let probe = SkyGroundInvariantProbe.make(look: .sun,
                                                     clouds: Clouds(coverage: 0.45, tallness: 0.6, phase: phase))
            let f = try renderUnrolled(probe)
            return (probe.drawer.skySunTransmittance, mean(f, x: 90..<102, y: 90..<102),
                    probe.drawer.skySunLight()?.intensity)
        }
        let gap = try sun(phase: 5), behind = try sun(phase: 3)
        let gapShare = try #require(gap.share), behindShare = try #require(behind.share)
        #expect(gapShare > 0.95, "the sun in a gap kept \(gapShare) of its beam")
        #expect(behindShare < 0.2, "the sun behind a cloud kept \(behindShare) of its beam")
        let discRatio = behind.disc / gap.disc
        #expect(abs(discRatio - behindShare / gapShare) < 0.05,
                "the backdrop dimmed the disc to \(discRatio) where the beam kept \(behindShare / gapShare)")
        let gapLight = try #require(gap.light), behindLight = try #require(behind.light)
        #expect(abs(behindLight / gapLight - behindShare / gapShare) < 1e-6,
                "the light scaled by \(behindLight / gapLight) where the share is \(behindShare / gapShare)")
        // A clear sky's sun keeps its whole beam, with nothing to read back.
        let clear = SkyGroundInvariantProbe.make(look: .sun)
        _ = try renderUnrolled(clear)
        #expect(clear.drawer.skySunTransmittance == nil)
        let sky = SkySun(turbidity: 2, elevation: 0.6, groundAlbedo: 0.3)
        let expected = max(sky.beam.x, sky.beam.y, sky.beam.z) * Double(sky.exposure(sunLit: true, coverage: nil))
        #expect(abs((clear.drawer.skySunLight()?.intensity ?? 0) / expected - 1) < 1e-6)
    }

    /// An environment's light reaches the scene whole: a small sun on a flat field adds
    /// its own irradiance to a surface facing it, so the facing-to-away ratio of a white
    /// sphere's disc is 1 plus the sun's radiance times its solid angle over pi times
    /// the field's radiance, summed from the authored pixels (the ratio cancels the
    /// exposure). A sun past the largest half float, 65,504, arrives whole too: the
    /// decode scales the map into half range and the bake scales it back.
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
        #expect(abs(ratio / expected - 1) < 0.03,
                "a sun of \(sun) gave a facing-to-away ratio of \(ratio) where its pixels give \(expected)")
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
        func farWall(aerial: Bool, gain: Double, sky: Bool = false) throws -> Double {
            mean(try renderUnrolled(AerialInvariantProbe.make(aerial: aerial, gain: gain, sky: sky)),
                 x: 120..<180, y: 60..<90)
        }
        let open = try farWall(aerial: false, gain: 2) / farWall(aerial: false, gain: 1)
        #expect(abs(open - 2) < 0.05, "with no air, doubling the light scaled the wall by \(open)")
        let veiled = try farWall(aerial: true, gain: 2) / farWall(aerial: true, gain: 1)
        #expect(abs(veiled - 2) < 0.05, "under the air, doubling the light scaled the wall by \(veiled)")
        // Under a procedural sky the sky is the light, its sun and its glow together:
        // doubling its intensity doubles the veiled wall as well.
        let skyVeiled = try farWall(aerial: true, gain: 2, sky: true)
            / farWall(aerial: true, gain: 1, sky: true)
        #expect(abs(skyVeiled - 2) < 0.05, "under a sky's air, doubling the sky scaled the wall by \(skyVeiled)")
    }

    /// The air far away is the sky's own horizon: looking level through air thick enough
    /// to hide a far wall, the veil is the sky model's radiance at the horizon in that
    /// direction (the closed form the backdrop is filled from), at the backdrop's
    /// exposure, leaned toward the sun by the haze's own halo: the veil's light averages
    /// to the horizon's over every compass direction, so it meets the horizon where the
    /// halo is average and stands above it sunward. Read against the model rather than
    /// the backdrop's pixels, because the sky brightens steeply off the horizon (6%
    /// within a tenth of a degree at this sky), faster than a texel can follow.
    @Test(.enabled(if: Snapshot.hasMetal), arguments: [Double.pi / 3, 2 * Double.pi / 3, Double.pi])
    func theFarAirIsTheSkysHorizon(azimuth: Double) throws {
        let f = try renderUnrolled(HorizonInvariantProbe.make(azimuth: azimuth))
        // The middle of the frame, where the view is level and `azimuth` from the sun;
        // a wider read averages over compass directions the halo leans differently.
        let air = around(f, Vector2(96, 104), radius: 4)
        let sun = SkySun(turbidity: 2, elevation: 0.6, groundAlbedo: 0.3)
        let (configs, radiances) = SkySun.configurations(turbidity: 2, albedo: 0.3, elevation: 0.6)
        // The view's angle from the sun: the level ray (sin a, 0, cos a) against
        // (0, sin e, cos e).
        let c = cos(azimuth) * cos(0.6)
        let horizon = (0..<3).map {
            SkySun.radiance(configs: configs, radiances: radiances, cosTheta: 0, gamma: acos(c), channel: $0)
        }
        let haze = 0.3, g = 0.76
        let phaseM = (1 - g * g) / pow(1 + g * g - 2 * g * c, 1.5)
        let ratios = [0.428, 1.0, 2.442]
        let mean = Drawer.aerialPhaseMean(haziness: haze, sunHeight: sin(0.6))
        let exposure = Double(sun.exposure(sunLit: true, coverage: nil))
        var expected = 0.0
        for k in 0..<3 {
            let betaR = ratios[k] * (1 - haze)
            let lean = (betaR * 0.75 * (1 + c * c) + haze * phaseM) / (betaR + haze) / mean[k]
            let veil = sun.horizon[k] * lean * exposure
            expected += veil / 3   // the frame's luma is the channels' plain mean
        }
        let atHorizon = (horizon[0] + horizon[1] + horizon[2]) / 3 * exposure
        #expect(abs(air / expected - 1) < 0.04,
                "at \(azimuth) rad from the sun the far air read \(air) where the model gives \(expected)")
        // The lean stays a lean: within a third of the horizon itself away from the sun.
        #expect(abs(air / atHorizon - 1) < 0.35,
                "at \(azimuth) rad from the sun the far air read \(air) against a horizon of \(atHorizon)")
    }

    // MARK: The bounce, measured

    /// The bounce is the light that arrives after the first surface, so on a ceiling
    /// the lamp never reaches it is the whole of the ceiling's light, and an export's
    /// field must give what a deep path trace of the same room gives there. Two
    /// readings. The light room's bounce against the dark room's is the depth of the
    /// recursion: the deep bounces are most of a light room's light and little of a
    /// dark one's, so a field that stops short reads the light room low (0.75 of the
    /// trace's own ratio under a progressive mean from the first update, measured
    /// 2026-10-09), and the converged field keeps the ratio within 6%. Each room's
    /// absolute is within 8%: a surface reads the field from the probe row nearest it,
    /// a third of a cell inside the room, so a ceiling read the floor's pool from
    /// closer than it stands (1.12 to 1.21 of the trace, measured 2026-10-12), until
    /// the read was carried back to the surface by the probes' own dimming slopes
    /// (0.99 to 1.03 on 2026-10-24). A physically based room reads the same way,
    /// through the tracer's parity rule (its body over pi, its lobe beside it).
    @Test(.enabled(if: Snapshot.hasMetal && Snapshot.hasRaytracing), arguments: [false, true])
    func theBounceMatchesADeepTrace(physical: Bool) throws {
        var ratios: [Double] = []
        for albedo in [0.5, 0.8] {
            let walls = Color.linearToSrgb(albedo)
            let lit = GIInvariantProbe.make(gi: true, walls: walls, physical: physical)
            let field = try render(lit)
            let unlit = try render(GIInvariantProbe.make(gi: false, walls: walls, physical: physical))
            let reference = try traced(GIInvariantProbe.make(gi: false, walls: walls, physical: physical),
                                       samples: 256, maxDepth: 64)
            let direct = around(unlit, lit.ceiling, radius: 6)
            #expect(direct < 0.001, "the lamp reached the ceiling directly: \(direct)")
            let bounce = around(field, lit.ceiling, radius: 6) - direct
            let truth = around(reference, lit.ceiling, radius: 6)
            #expect(truth > 0.003, "the trace found no bounce on the ceiling: \(truth)")
            #expect(abs(bounce / truth - 1) < 0.08,
                    "at albedo \(albedo) the field gave the ceiling \(bounce) where the trace gives \(truth)")
            ratios.append(bounce / truth)
        }
        let depth = ratios[1] / ratios[0]
        #expect(abs(depth - 1) < 0.06,
                "the light room's bounce against the dark room's is \(depth) of the trace's own ratio")
    }

    /// A metal bounces through its lobe, not as the plaster its base color would make:
    /// a copper floor under a lamp's pool throws copper onto the ceiling, by about
    /// what the path trace throws, and nothing of the lamp's white. Read as the
    /// difference between the room with the copper floor and the same room with a
    /// black metal floor, which reflects nothing, so what the walls add cancels. A
    /// polished floor too: it reflects the lamp in a spike the probes' rays all but
    /// miss, so the bounce widens its lobe to what the field can hold (0.085 of the
    /// trace's copper on the ceiling before, measured 2026-10-24; 0.84 after, the rest
    /// spread onto the walls).
    @Test(.enabled(if: Snapshot.hasMetal && Snapshot.hasRaytracing), arguments: [0.9, 0.1])
    func aMetalFloorThrowsItsOwnColorIntoTheBounce(roughness: Double) throws {
        func ceiling(_ f: Frame, _ p: MetalFloorInvariantProbe) -> SIMD3<Double> {
            channels(f, p.ceilingMark, radius: 6)
        }
        let copperProbe = MetalFloorInvariantProbe.make(gi: false, copper: true, roughness: roughness)
        let blackProbe = MetalFloorInvariantProbe.make(gi: false, copper: false, roughness: roughness)
        let tracedCopper = ceiling(try traced(copperProbe, samples: 256, maxDepth: 16), copperProbe)
            - ceiling(try traced(blackProbe, samples: 256, maxDepth: 16), blackProbe)
        // The lobe of a rough metal sends the ceiling about a fifth of what a matte
        // copper would (0.0026 of red against 0.013, the trace's own figures), so the
        // reading is dim and the gate sits under it.
        #expect(tracedCopper.x > 0.0015, "the trace threw nothing from the copper floor: \(tracedCopper)")
        let direct = ceiling(try render(copperProbe), copperProbe)
        #expect((direct.x + direct.y + direct.z) / 3 < 0.002, "the lamp reached the ceiling directly: \(direct)")
        let onProbe = MetalFloorInvariantProbe.make(gi: true, copper: true, roughness: roughness)
        let offProbe = MetalFloorInvariantProbe.make(gi: true, copper: false, roughness: roughness)
        let bounced = ceiling(try render(onProbe), onProbe) - ceiling(try render(offProbe), offProbe)
        // The envelope the polished floor needs (its widened lobe gives the ceiling 0.84
        // of the trace's copper and the walls the rest); a floor bounced as the matte
        // copper reads five times over.
        #expect(bounced.x > 0.7 * tracedCopper.x && bounced.x < 1.4 * tracedCopper.x,
                "the field threw \(bounced) from the copper floor where the trace throws \(tracedCopper)")
        #expect(bounced.x > 1.4 * bounced.z,
                "what the copper floor threw is not copper: \(bounced) (the trace's is \(tracedCopper))")
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
        #expect(bounced > 0.5 * tracedGlow && bounced < 1.5 * tracedGlow,
                "the field lit the floor under the glow by \(bounced) where the trace lights it by \(tracedGlow)")
    }

    /// An emissive map glows by its pattern in the bounce, as at a path-traced hit: a panel
    /// whose map is half black and half white lights the floor under its middle, which
    /// sees the two halves alike, by half of what the same panel glowing white all over
    /// gives, in the field as in the trace.
    @Test(.enabled(if: Snapshot.hasMetal && Snapshot.hasRaytracing))
    func anEmissiveMapGlowsByItsPatternInTheBounce() throws {
        func share(_ frame: (EmitterInvariantProbe) throws -> Frame, gi: Bool) throws -> (Double, Double) {
            func floor(_ p: EmitterInvariantProbe) throws -> Double { around(try frame(p), p.centerMark, radius: 4) }
            let dark = try floor(.make(gi: gi, glows: false, panel: true))
            let flat = try floor(.make(gi: gi, glows: true, panel: true)) - dark
            let half = try floor(.make(gi: gi, glows: true, halfMapped: true)) - dark
            return (half / flat, flat)
        }
        let (traced, tracedFlat) = try share({ try self.traced($0, samples: 64) }, gi: false)
        #expect(tracedFlat > 0.1, "the trace did not light the floor under the panel: \(tracedFlat)")
        #expect(abs(traced - 0.5) < 0.05, "the trace lit the floor by \(traced) of the white panel's light")
        let (field, fieldFlat) = try share({ try self.render($0) }, gi: true)
        #expect(fieldFlat > 0.1, "the field did not light the floor under the panel: \(fieldFlat)")
        #expect(abs(field - 0.5) < 0.05,
                "the half-mapped panel lit the floor by \(field) of the white panel's bounce (the trace's share is \(traced))")
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
        #expect(worst <= 3, "the field added \(worst) levels to a room the lamp cannot reach")
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
            #expect(abs(rendered - share) < 0.03,
                    "at \(x) the floor kept \(rendered) of its light where the panel's weighted share is \(share)")
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
        #expect(shadowed <= 2, "with shadows the two aims differed by \(shadowed) levels")
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
        #expect(outside < 0.004, "the floor past the reach read \(outside)")
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
        #expect(abs(through / bare - 1) < 0.03,
                "through the pane the ball at roughness \(roughness) read \(through / bare) of itself")
    }

    /// A solid block of the air's own index is not there either: it bends nothing, so the
    /// ball behind it reads as it does without it. The light behind a solid is counted
    /// once: a surface's shadow rays pass the solid on the straight line, and the path
    /// that crosses it carries that surface's pairing on, weighed against the table at
    /// the direction it leaves with, so a lamp the table draws reliably is the straight
    /// pass's and the room the bent path's. Credited whole after the crossing, the ball
    /// at roughness 0.5 read 1.081 of itself; credited to the straight pass alone, the
    /// polished one read 0.42 at 256 samples, a near-mirror lobe being light only its
    /// own continuation samples well.
    @Test(.enabled(if: Snapshot.hasMetal && Snapshot.hasRaytracing), arguments: [0.08, 0.5])
    func anIndexMatchedBlockChangesNothingInTheTrace(roughness: Double) throws {
        let bare = mean(try traced(PaneInvariantProbe.make(pane: false, roughness: roughness), samples: 256),
                        x: 52..<76, y: 52..<76)
        let through = mean(try traced(PaneInvariantProbe.make(pane: true, roughness: roughness, thickness: 0.3),
                                      samples: 256),
                           x: 52..<76, y: 52..<76)
        #expect(bare > 0.05, "the ball read \(bare)")
        #expect(abs(through / bare - 1) < 0.03,
                "through the block the ball at roughness \(roughness) read \(through / bare) of itself")
    }

    /// The trace and the window agree on a white ball in a lit room: the window's ambient
    /// is the room's light convolved by each lobe, an estimate made a different way from
    /// the same environment, and the two read within 3% of a continuation-only trace
    /// (0.384 and 0.372 for a matte ball, 0.379 and 0.376 for a metal one at roughness
    /// 0.5). So the trace, with all its strategies, reads within 3% of the window. It
    /// pins the two strategies reading one picture: the environment's draw read sharp
    /// beside a continuation read blurred to its footprint counted a lamp's blurred skirt
    /// beside its sharp core (the matte ball traced 0.475, 24% above the window), and the
    /// two the other way round, the draw blurred beside a sharp miss, 25% under it.
    @Test(.enabled(if: Snapshot.hasMetal && Snapshot.hasRaytracing))
    func theTraceAgreesWithTheWindowOnABallInALitRoom() throws {
        for (name, finish) in [("a matte ball", Material(shading: .physicallyBased, metallic: 0, roughness: 1)),
                               ("a metal ball at roughness 0.5", Material.metal(roughness: 0.5)),
                               ("a dielectric ball at roughness 0.3",
                                Material(shading: .physicallyBased, metallic: 0, roughness: 0.3))] {
            let probe = LitRoomInvariantProbe.make(finish)
            let window = mean(try render(probe), x: 52..<76, y: 52..<76)
            let trace = mean(try traced(probe, samples: 256), x: 52..<76, y: 52..<76)
            #expect(window > 0.05, "\(name) read \(window) in the window")
            #expect(abs(trace / window - 1) < 0.03,
                    "traced, \(name) read \(trace / window) of the window's reading")
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

/// A cube cut into pieces that fit back together exactly, standing on a floor under a
/// key light with the bounce on: every cut is two coincident faces.
private final class TouchingPiecesProbe: Sketch {
    static let pieces = Mesh.box(size: 2).fractured(into: 96, seed: 3)

    override var canvasSize: CanvasSize { .square(192) }

    override func draw() {
        background(.black)
        camera(.orbiting(target: Vector3(0, 1, 0), radius: 6.5,
                         azimuth: 0.5, elevation: 0.35, fieldOfView: .pi / 3.2,
                         near: 0.5, far: 40))
        directionalLight(.white, direction: Vector3(0.6, -1, -0.4), intensity: 1.2, castsShadow: true)
        castShadows()
        globalIllumination()
        fill(Color(white: 0.8))
        withState { translate(0, -0.1, 0); drawBox(width: 10, height: 0.2, depth: 10) }
        fill(.white)
        withState {
            translate(0, 1, 0)
            for piece in Self.pieces { drawMesh(piece) }
        }
    }
}

/// The five-walled room of the bounce suite, its walls at one albedo, lit by a pool
/// on the floor, with a white sphere so a black room still has something lit.
private final class GIInvariantProbe: Sketch {
    var gi = true
    var walls = 0.9
    /// A physically based room (every surface `.dielectric(roughness: 1)`), which the
    /// probe trace shades through the microfacet lobes, against the standard one.
    var physical = false
    /// Where a point on the ceiling, which the lamp's cone never reaches, lands.
    var ceiling = Vector2.zero

    static func make(gi: Bool, walls: Double, physical: Bool = false) -> GIInvariantProbe {
        let p = GIInvariantProbe()
        p.gi = gi
        p.walls = walls
        p.physical = physical
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
        if physical { material(.dielectric(roughness: 1)) }
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
    var mapped = false
    var envURL = URL(fileURLWithPath: "/dev/null")

    static func make(roughness: Double, cosine: Double, mapped: Bool = false,
                     envURL: URL) -> PlateInvariantProbe {
        let p = PlateInvariantProbe()
        p.roughness = roughness
        p.cosine = cosine
        p.mapped = mapped
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
            if mapped {
                drawMesh(Mesh.plane(width: 40, depth: 1.8 / cosine)
                    .surfaceMapped(occlusion: Image(width: 4, height: 4, color: .white)))
            } else {
                drawPlane(width: 40, depth: 1.8 / cosine)
            }
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
        toneMap(.reinhard)
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

/// The sun-lit sky's ground and its sun through the clouds, through a Reinhard present:
/// the backdrop below the horizon with nothing in view (a sphere far behind every look
/// keeps the frame a 3D one, since a frame with no mesh draws no backdrop), a white
/// matte plane filling the frame from above, a white plate's underside and its top over
/// a matte floor, and the sun's own disc.
private final class SkyGroundInvariantProbe: Sketch {
    enum Look { case ground, whitePlane, underside, top, sun }
    var look = Look.ground
    var sunlight = Environment.Sunlight.automatic
    var clouds: Clouds?

    /// The `.ground` look's center ray: down and away from the sun.
    static let groundRay: SIMD3<Double> = {
        let d = SIMD3<Double>(0, -8, -10)
        return d / (d.x * d.x + d.y * d.y + d.z * d.z).squareRoot()
    }()

    static func make(look: Look, sunlight: Environment.Sunlight = .automatic,
                     clouds: Clouds? = nil) -> SkyGroundInvariantProbe {
        let p = SkyGroundInvariantProbe()
        p.look = look
        p.sunlight = sunlight
        p.clouds = clouds
        return p
    }

    override var canvasSize: CanvasSize { .square(192) }

    override func draw() {
        background(.black)
        toneMap(.reinhard)
        let elevation = 0.6
        let towardSun = Vector3(0, sin(elevation), cos(elevation))
        switch look {
        case .ground:
            camera(Camera3D(eye: Vector3(0, 4, 0), target: Vector3(0, -4, -10),
                            projection: .perspective(fieldOfView: .pi / 8)))
        case .whitePlane:
            camera(Camera3D(eye: Vector3(0, 30, 0), target: .zero, up: Vector3(0, 0, -1),
                            projection: .perspective(fieldOfView: .pi / 8)))
        case .underside:
            camera(Camera3D(eye: Vector3(0, 0.5, 0), target: Vector3(0, 6, 0), up: Vector3(0, 0, -1),
                            projection: .perspective(fieldOfView: .pi / 8)))
        case .top:
            camera(Camera3D(eye: Vector3(0, 12, 0), target: Vector3(0, 6, 0), up: Vector3(0, 0, -1),
                            projection: .perspective(fieldOfView: .pi / 8)))
        case .sun:
            camera(Camera3D(eye: .zero, target: towardSun * 10,
                            projection: .perspective(fieldOfView: .pi / 6)))
        }
        var env = Environment.sky(turbidity: 2, sunElevation: elevation).sunlight(sunlight)
        if let clouds { env = env.clouds(clouds) }
        environment(env)
        material(Material(shading: .physicallyBased, metallic: 0, roughness: 1))
        withState { translate(0, -300, 300); drawSphere(radius: 1) }
        switch look {
        case .whitePlane:
            fill(.white)
            drawPlane(width: 400, depth: 400)
        case .underside, .top:
            // The floor's albedo is the sky's ground albedo, a linear 0.3 (the bake's
            // ground is the model's reflectance; a fill is specified in sRGB).
            let albedo = Color.linearToSrgb(0.3)
            fill(Color(red: albedo, green: albedo, blue: albedo))
            drawPlane(width: 60, depth: 60)
            fill(.white)
            withState { translate(0, 6, 0); drawBox(width: 2, height: 0.2, depth: 2) }
        case .ground, .sun:
            break
        }
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
    var sky = false

    static func make(aerial: Bool, gain: Double, sky: Bool = false) -> AerialInvariantProbe {
        let p = AerialInvariantProbe()
        p.aerial = aerial
        p.gain = gain
        p.sky = sky
        return p
    }

    override var canvasSize: CanvasSize { .square(192) }

    override func draw() {
        background(.black)
        toneMap(.reinhard)
        camera(Camera3D(eye: Vector3(0, 1, 0), target: Vector3(0, 1, -10)))
        if sky {
            // The sky's sun from behind the camera's right shoulder, its glow the ambient.
            environment(.sky(turbidity: 3, sunElevation: 0.6).rotated(2.4)
                .intensified(to: gain).lightingOnly())
        } else {
            ambientLight(.black)
            directionalLight(.white, direction: Vector3(0.5, -0.6, -0.6), intensity: gain)
        }
        if aerial { aerialPerspective(density: 0.02, haziness: 0.3) }
        fill(Color(white: 0.5))
        material(.dielectric(roughness: 1))
        withState { translate(-2, 1, -8); drawBox(width: 3, height: 3, depth: 0.2) }
        withState { translate(0, 1, -200); drawBox(width: 400, height: 400, depth: 1) }
    }
}

/// A white plain floor seen from above under a loaded map.
private final class MapFloorInvariantProbe: Sketch {
    var envURL = URL(fileURLWithPath: "/dev/null")

    static func make(envURL: URL) -> MapFloorInvariantProbe {
        let p = MapFloorInvariantProbe()
        p.envURL = envURL
        return p
    }

    override var canvasSize: CanvasSize { .square(64) }

    override func draw() {
        background(.black)
        toneMap(.reinhard)
        camera(Camera3D(eye: Vector3(0, 12, 0.01), target: .zero,
                        projection: .perspective(fieldOfView: .pi / 5)))
        environment(.hdri(url: envURL).lightingOnly())
        fill(.white)
        withState { translate(0, -0.05, 0); drawBox(width: 8, height: 0.1, depth: 8) }
    }
}

/// A white plain floor seen from above under a procedural sky with no sun of its own.
private final class SkyFloorInvariantProbe: Sketch {
    var turbidity = 2.0

    static func make(turbidity: Double) -> SkyFloorInvariantProbe {
        let p = SkyFloorInvariantProbe()
        p.turbidity = turbidity
        return p
    }

    override var canvasSize: CanvasSize { .square(64) }

    override func draw() {
        background(.black)
        toneMap(.reinhard)
        camera(Camera3D(eye: Vector3(0, 12, 0.01), target: .zero,
                        projection: .perspective(fieldOfView: .pi / 5)))
        environment(.sky(turbidity: turbidity, sunElevation: 0.6).lightingOnly().sunlight(.off))
        fill(.white)
        withState { translate(0, -0.05, 0); drawBox(width: 8, height: 0.1, depth: 8) }
    }
}

/// A white floor seen from above under a procedural sky, a slab high over it throwing
/// the sun's shadow onto it; `lit` and `shaded` mark a sunlit spot and the shadow's
/// middle (the shadow falls toward -z by the slab's height over the sun's slope).
private final class SkyShadowInvariantProbe: Sketch {
    var turbidity = 2.0
    var lit = Vector2.zero
    var shaded = Vector2.zero

    static func make(turbidity: Double) -> SkyShadowInvariantProbe {
        let p = SkyShadowInvariantProbe()
        p.turbidity = turbidity
        return p
    }

    override var canvasSize: CanvasSize { .square(192) }

    override func draw() {
        background(.black)
        toneMap(.reinhard)
        let elevation = 0.6, height = 1.5
        camera(Camera3D(eye: Vector3(0, 12, 0.01), target: .zero,
                        projection: .perspective(fieldOfView: .pi / 5)))
        environment(.sky(turbidity: turbidity, sunElevation: elevation).lightingOnly())
        castShadows()
        fill(.white)
        material(Material(shading: .physicallyBased, metallic: 0, roughness: 1))
        withState { translate(0, -0.05, 0); drawBox(width: 8, height: 0.1, depth: 8) }
        withState { translate(0, height, 2); drawBox(width: 1.6, height: 0.05, depth: 1.6) }
        shaded = project(Vector3(0, 0, 2 - height / tan(elevation))) ?? .zero
        lit = project(Vector3(-2.4, 0, -1)) ?? .zero
    }
}

/// Looking level from a little above the ground, `azimuth` radians around from the
/// sky's sun, at a wall far away behind air thick enough to hide it (the frame's bottom
/// half the veil).
private final class HorizonInvariantProbe: Sketch {
    var azimuth = Double.pi / 3

    static func make(azimuth: Double) -> HorizonInvariantProbe {
        let p = HorizonInvariantProbe()
        p.azimuth = azimuth
        return p
    }

    override var canvasSize: CanvasSize { .square(192) }

    override func draw() {
        background(.black)
        toneMap(.reinhard)
        let ahead = Vector3(sin(azimuth), 0, cos(azimuth))
        camera(Camera3D(eye: Vector3(0, 1, 0), target: Vector3(0, 1, 0) + ahead * 10,
                        projection: .perspective(fieldOfView: .pi / 4)))
        environment(.sky(turbidity: 2, sunElevation: 0.6))
        aerialPerspective(density: 0.2, haziness: 0.3)
        fill(Color(white: 0.5))
        material(.dielectric(roughness: 1))
        withState {
            translate(ahead * 200 + Vector3(0, 1 - 100, 0))
            rotateY(azimuth)
            drawBox(width: 400, height: 200, depth: 1)
        }
    }
}

/// A white floor with a black slab hovering over it, the slab's underside glowing or
/// not; the one light shines straight up, so it lights no surface the camera sees.
private final class EmitterInvariantProbe: Sketch {
    var gi = true
    var glows = true
    /// A flat panel facing the floor in the slab's place, which carries the uvs a map
    /// needs (the box has none).
    var panel = false
    /// The panel glows through an emissive map whose one half is black and the other
    /// white, at the full factor, rather than white all over.
    var halfMapped = false
    var floorMark = Vector2.zero
    /// The floor straight under the panel's middle, which sees its two halves alike.
    var centerMark = Vector2.zero

    static func make(gi: Bool, glows: Bool, panel: Bool = false,
                     halfMapped: Bool = false) -> EmitterInvariantProbe {
        let p = EmitterInvariantProbe()
        p.gi = gi
        p.glows = glows
        p.panel = panel || halfMapped
        p.halfMapped = halfMapped
        return p
    }

    /// Black on the left half, white on the right.
    static let halfMap: Image = {
        let w = 64, h = 64
        var px = [UInt8](repeating: 255, count: w * h * 4)
        for y in 0..<h {
            for x in 0..<(w / 2) {
                let i = (y * w + x) * 4
                px[i] = 0; px[i + 1] = 0; px[i + 2] = 0
            }
        }
        return Image(width: w, height: h, premultipliedRGBA: px)!
    }()

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
            if panel { rotateX(.pi) }
            let slab = panel ? Mesh.plane(width: 2, depth: 2) : Mesh.box(width: 2, height: 0.04, depth: 2)
            drawMesh(halfMapped ? slab.surfaceMapped(emissive: Self.halfMap)
                                : slab.surfaceMapped(emissiveColor: glows ? .white : .black))
        }
        floorMark = project(Vector3(0, 0, 0.6)) ?? .zero
        centerMark = project(Vector3(0, 0, 0)) ?? .zero
    }
}

/// The gray room with its floor a rough copper metal (or a black one, which reflects
/// nothing), under the spot that pools on it from above: the pool's reflection leaves
/// the copper in a broad lobe about straight up, the ceiling never sees the lamp, so
/// the ceiling reads only bounce, and the copper's share of it is the difference
/// between the two floors.
private final class MetalFloorInvariantProbe: Sketch {
    var gi = true
    var copper = true
    var ceilingMark = Vector2.zero

    /// The floor's roughness: rough by default, polished for the lobe that is narrower
    /// than an irradiance texel.
    var roughness = 0.9

    static func make(gi: Bool, copper: Bool, roughness: Double = 0.9) -> MetalFloorInvariantProbe {
        let p = MetalFloorInvariantProbe()
        p.gi = gi
        p.copper = copper
        p.roughness = roughness
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
        let wall = Color(white: 0.5)
        withState {
            material(.metal(roughness: roughness))
            fill(copper ? Color(hex: 0xB87333) : .black)
            translate(0, -0.1, 0)
            drawBox(width: 8, height: 0.2, depth: 8)
        }
        withState { fill(wall); translate(0, 4.1, 0); drawBox(width: 8, height: 0.2, depth: 8) }
        withState { fill(wall); translate(0, 2, -4.1); drawBox(width: 8, height: 4.4, depth: 0.2) }
        withState { fill(wall); translate(-4.1, 2, 0); drawBox(width: 0.2, height: 4.4, depth: 8) }
        withState { fill(wall); translate(4.1, 2, 0); drawBox(width: 0.2, height: 4.4, depth: 8) }
        ceilingMark = project(Vector3(0, 4.0, -2)) ?? .zero
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

/// A white metal ball under the interior environment, seen bare or through clear glass
/// of index 1: a pane of no thickness, or a solid block when given one.
private final class PaneInvariantProbe: Sketch {
    var pane = true
    var roughness = 0.08
    var thickness = 0.0

    static func make(pane: Bool, roughness: Double, thickness: Double = 0) -> PaneInvariantProbe {
        let p = PaneInvariantProbe()
        p.pane = pane
        p.roughness = roughness
        p.thickness = thickness
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
                material(.glass(roughness: 0, ior: 1, thickness: thickness))
                translate(0, 0, 3)
                drawBox(width: 4, height: 4, depth: max(thickness, 0.01))
            }
        }
    }
}

/// A white ball of one finish in the bundled interior, lit by it and drawn over black.
private final class LitRoomInvariantProbe: Sketch {
    var finish = Material()

    static func make(_ finish: Material) -> LitRoomInvariantProbe {
        let p = LitRoomInvariantProbe()
        p.finish = finish
        return p
    }

    override var canvasSize: CanvasSize { .square(128) }

    override func draw() {
        background(.black)
        camera(Camera3D(eye: Vector3(0, 0, 5), target: .zero))
        environment(Environment.interior.lightingOnly())
        fill(.white)
        material(finish)
        drawSphere(radius: 1.2)
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
