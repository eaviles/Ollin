import Foundation
import Metal
import simd
import COllinShaders   // OllinLensFlareUniforms, shared with the shaders

// MARK: - Lens flare

extension MetalRenderer {

    /// Whether this frame flares. A flare needs a camera to be a defect of, and a
    /// light to be a defect about.
    func lensFlareActive(_ drawer: Drawer) -> Bool {
        drawer.lensFlareSetting != nil && drawer.camera3D != nil && !drawer.lights.isEmpty
    }

    /// Everything about a lens that does not move when the light does: the ghost
    /// list, the level the whole flare is set against, and the coating table.
    struct FlareLens {
        let lens: Lens
        let optics: LensOptics
        /// What multiplies a ghost's two reflectances over its spread to give
        /// linear light, at `amount` 1. See `lensFlareGain`.
        let level: Double
        /// What every reflecting surface sends back at every angle, a row per
        /// surface and direction. See `Lens.coatingTable`.
        let coating: MTLTexture
        let coatingRows: Int
        /// The lens as real rays meet it: every surface, its coating, and the
        /// index of every glass in each color a ray can be followed in. The
        /// frame's own terms are filled in per frame.
        let trace: OllinLensTraceUniforms?
    }

    /// What the streak is worth where it crosses its source, at `amount` and
    /// `streak` both 1, in linear light.
    static let flareStreakGain = 0.55
    /// What the halo's ring is worth at its brightest, the same way.
    static let flareHaloGain = 0.1
    /// The halo's width, as a share of its radius.
    static let flareHaloWidth = 0.035
    /// How many specks a thoroughly dirty lens carries.
    static let flareDirtSpecks = 160
    /// What a speck beside its light is worth, the same way.
    static let flareDirtGain = 0.05
    /// A speck's radius on the frame with the iris wide open, in y-normalized
    /// units, before its own size is counted. A speck is a picture of the iris,
    /// so it shrinks as the iris closes.
    static let flareDirtRadius = 0.05
    /// How far from its light a speck's glow has fallen to about a third, in
    /// y-normalized units.
    static let flareDirtReach = 0.55

    /// The grime on the front of the lens: where each speck sits on the frame
    /// (y-normalized, x still to be scaled by the aspect), how large it is
    /// beside the others, and how much it scatters. Drawn from one fixed seed,
    /// so a lens's dirt stays where it is from frame to frame and from run to
    /// run. Mostly small specks, with a few broad faint smears among them.
    static let flareDirt: [SIMD4<Float>] = {
        var state: UInt64 = 0x0D1_27ED_1E25
        func next() -> Double {
            state &+= 0x9E37_79B9_7F4A_7C15
            var z = state
            z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
            z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
            z ^= z >> 31
            return Double(z >> 11) / Double(1 << 53)
        }
        return (0..<flareDirtSpecks).map { index in
            let smear = index % 11 == 10
            let size = smear ? 2.6 + 2.4 * next() : 0.35 * pow(4.5, next())
            let weight = smear ? 0.10 + 0.10 * next() : 0.35 + 0.65 * next()
            return SIMD4(Float(next() * 2.2 - 1.1), Float(next() * 2.2 - 1.1), Float(size), Float(weight))
        }
    }()

    /// Whether ghosts are followed ray by ray at all. It is on, always, outside a
    /// test: turning it off leaves every ghost to first order, which is what a
    /// probe compares against to show what following the rays changed.
    nonisolated(unsafe) static var flareFollowsRays = true

    /// Rays along a side of the grid a followed ghost is drawn as, by how much of
    /// the frame the ghost covers. A wide ghost magnifies the front opening many
    /// times over, so a coarse grid's cells are a hundred pixels across on it and
    /// the barrel's round edge, read between rays that far apart, comes out as a
    /// polygon.
    static let flareGridSides = [16, 32, 64]
    /// How many canvas pixels one cell of a ghost's grid may span. At sixteen a
    /// barrel's arc three hundred pixels in radius strays from its chord by a
    /// tenth of a pixel, and every ray not followed is a ray not paid for.
    static let flareCellPixels = 16.0
    /// The linear light a ghost has to reach before its colors are followed one
    /// wavelength at a time. A fringe is a few pixels of color on a rim, and on a
    /// ghost dimmer than this there is no rim to see it on. Wide faint ghosts
    /// part their colors by the most pixels, being the largest, and would
    /// otherwise take seven passes each for nothing.
    static let flareColoredFrom = 0.02
    /// Samples per pixel on the canvas the followed ghosts are drawn on. A ghost's
    /// mesh folds over itself along a caustic, and the fold is a silhouette: the
    /// one edge of a ghost that no soft-edge test reaches, and at one sample a
    /// staircase.
    static let flareTraceSamples = 4
    /// The most ghost passes one frame draws by following rays. A ghost whose
    /// colors part takes seven; past this, the faintest give up their colors.
    static let flareMaxTracedDraws = 144

    /// The lens as the ray tracer needs it, or `nil` for one with more surfaces
    /// than it carries.
    private func traceUniforms(for lens: Lens) -> OllinLensTraceUniforms? {
        let count = lens.interfaces.count
        guard count >= 2, count <= Int(OLLIN_MAX_LENS_INTERFACES) else { return nil }
        var uniforms = OllinLensTraceUniforms()
        var vertex = 0.0
        withUnsafeMutablePointer(to: &uniforms.surfaces) { tuple in
            tuple.withMemoryRebound(to: simd_float4.self, capacity: Int(OLLIN_MAX_LENS_INTERFACES)) { out in
                for (i, face) in lens.interfaces.enumerated() {
                    out[i] = SIMD4(Float(vertex), Float(face.radius), Float(face.height), face.isIris ? 1 : 0)
                    vertex += face.thickness
                }
            }
        }
        withUnsafeMutablePointer(to: &uniforms.coatings) { tuple in
            tuple.withMemoryRebound(to: simd_float4.self, capacity: Int(OLLIN_MAX_LENS_INTERFACES)) { out in
                for (i, face) in lens.interfaces.enumerated() {
                    let design = lens.isExposed(i) ? (face.coating ?? lens.coatingWavelength) : 0
                    out[i] = SIMD4(Float(design), 0, 0, 0)
                }
            }
        }
        let slots = Int(OLLIN_LENS_WAVELENGTH_SLOTS), row = Int(OLLIN_MAX_LENS_INTERFACES)
        withUnsafeMutablePointer(to: &uniforms.index) { tuple in
            tuple.withMemoryRebound(to: Float.self, capacity: slots * row) { out in
                for slot in 0..<slots {
                    for (i, face) in lens.interfaces.enumerated() {
                        let wavelength = slot < Lens.spectrumWavelengths.count
                            ? Lens.spectrumWavelengths[slot] : nil
                        out[slot * row + i] = Float(wavelength.map { face.index(atWavelength: $0) } ?? face.ior)
                    }
                }
            }
        }
        uniforms.frame = SIMD4(0, 0, Float(vertex), Float(count))
        return uniforms
    }

    /// The multisampled canvas the followed ghosts are drawn on. Nothing is read
    /// from it but its resolve, so it lives in tile memory and costs no storage.
    private func flareSamples(width: Int, height: Int) -> MTLTexture? {
        if let cached = flareSampleCache, cached.width == width, cached.height == height { return cached }
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: linearFormat, width: width, height: height, mipmapped: false)
        descriptor.textureType = .type2DMultisample
        descriptor.sampleCount = MetalRenderer.flareTraceSamples
        descriptor.usage = .renderTarget
        descriptor.storageMode = .memoryless
        flareSampleCache = device.makeTexture(descriptor: descriptor)
        return flareSampleCache
    }

    /// A grid's triangles, built once per size.
    private func flareGrid(side: Int) -> (indices: MTLBuffer, count: Int)? {
        if let cached = flareGridCache[side] { return cached }
        var indices: [UInt16] = []
        indices.reserveCapacity((side - 1) * (side - 1) * 6)
        for line in 0..<(side - 1) {
            for column in 0..<(side - 1) {
                let a = UInt16(line * side + column), b = a + 1
                let c = UInt16((line + 1) * side + column), d = c + 1
                indices += [a, b, c, b, d, c]
            }
        }
        guard let buffer = device.makeBuffer(bytes: indices, length: indices.count * 2,
                                             options: .storageModeShared) else { return nil }
        flareGridCache[side] = (buffer, indices.count)
        return (buffer, indices.count)
    }

    /// How bright one ghost comes out, relative to the others, from a source of
    /// angular radius `source` at the representative angle: its two coatings
    /// over how widely it spreads the light, held down where the source's own
    /// size spreads a ghost that lands near focus wider still.
    ///
    /// `cover` is how much of a normal frame the ghost fills, which is what
    /// separates a ghost from a veil: the same brightness that reads as a clean
    /// shape across a twentieth of the picture is a fog across all of it.
    private func flareStanding(_ ghost: LensGhost, lens: Lens, optics: LensOptics,
                               source: Double) -> (level: Double, cover: Double) {
        let reflect = lens.ghostReflectance(ghost, angle: MetalRenderer.flareReferenceAngle)
        let luminance = 0.2126 * reflect.x + 0.7152 * reflect.y + 0.0722 * reflect.z
        let a = ghost.toSensor.a, b = ghost.toSensor.b
        let throughIris = ghost.toIris.a * b / a - ghost.toIris.b
        let overPupil = source * abs(b / a), overIris = source * abs(throughIris)
        var share = 1.0
        if overPupil > 0 { share = min(share, pow(optics.pupilRadius / overPupil, 2)) }
        if overIris > 0 { share = min(share, pow(optics.openIrisRadius / overIris, 2)) }
        // The ghost's own radius on the sensor, widened by the source's, against
        // a frame eight tenths of the focal length across, which is about what a
        // normal lens is asked to cover.
        let sharp = min(optics.openIrisRadius / max(abs(ghost.toIris.a), 1e-9),
                        optics.pupilRadius) * abs(a)
        let area = Double.pi * (sharp * sharp + pow(source * b, 2))
        let frame = pow(0.8 * max(abs(optics.focalLength), 1e-6), 2)
        return (luminance / max(a * a, 1e-8) * share, min(1, area / frame))
    }

    /// The paraxial description of a lens, worked out once and kept. None of it
    /// moves when the light does, so a sketch holding one lens pays for the ghost
    /// enumeration, the level, and the coating table on the first frame only.
    func flareLens(for lens: Lens) -> FlareLens? {
        if let cached = flareLensCache, cached.lens == lens { return cached }
        var optics = lens.optics()
        let source = MetalRenderer.flareReferenceSource
        if optics.ghosts.count > Int(OLLIN_MAX_FLARE_GHOSTS) {
            // A complicated lens makes more ghost paths than the frame can carry,
            // so keep the ones that will read. The angle is fixed rather than the
            // light's own, so which ghosts survive does not change as the light
            // crosses the frame, which would pop them in and out.
            let scored = optics.ghosts.map {
                ($0, flareStanding($0, lens: lens, optics: optics, source: source).level)
            }
            optics.ghosts = scored.sorted { $0.1 > $1.1 }
                .prefix(Int(OLLIN_MAX_FLARE_GHOSTS)).map(\.0)
        }
        // Two ceilings, and the lower one sets the level. No single ghost comes
        // out above `lensFlareGain`, which is what holds a lens of few, compact
        // ghosts. And all of them together add no more than `lensFlareVeil` to
        // the frame on average, which is what holds a lens whose ghosts are all
        // wide: each could sit at the first ceiling and the picture would still
        // drown under ten of them laid over one another.
        var peak = 0.0, veil = 0.0
        for ghost in optics.ghosts {
            let standing = flareStanding(ghost, lens: lens, optics: optics, source: source)
            peak = max(peak, standing.level)
            veil += standing.level * standing.cover
        }
        var level = 0.0
        if peak > 0, veil > 0 {
            level = min(MetalRenderer.lensFlareGain / peak, MetalRenderer.lensFlareVeil / veil)
        }

        let table = lens.coatingTable()
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba16Float, width: table.samples, height: table.rows, mipmapped: false)
        descriptor.usage = .shaderRead
        guard let texture = device.makeTexture(descriptor: descriptor) else { return nil }
        let half = table.values.map { Float16($0) }
        half.withUnsafeBytes { bytes in
            texture.replace(region: MTLRegionMake2D(0, 0, table.samples, table.rows),
                            mipmapLevel: 0, withBytes: bytes.baseAddress!,
                            bytesPerRow: table.samples * 8)
        }
        let built = FlareLens(lens: lens, optics: optics, level: level,
                              coating: texture, coatingRows: table.rows,
                              trace: traceUniforms(for: lens))
        flareLensCache = built
        return built
    }

    /// What the lens's brightest ghost is worth, in linear light, at `amount` 1,
    /// under standard conditions: the iris wide open, the source at a
    /// representative angle, and the source a standard size.
    ///
    /// One number sets the whole flare's level, and everything under it stays as
    /// the optics worked it out: how the ghosts compare to each other in size,
    /// place, and color, and how each source compares to the others in the same
    /// frame. Nothing is bent to make the picture read.
    ///
    /// A scale is needed at all because the physical number is unusably small.
    /// Two coated interfaces pass on a few parts in ten thousand, and a real
    /// flare shows only because the sun is many thousands of times brighter than
    /// anything it lights. A sketch's lights carry no such range, and a light's
    /// `intensity` is set to light the scene rather than to say how bright the
    /// source is, so reading it literally would make one sketch's flare invisible
    /// and the next one's blinding.
    ///
    /// The conditions are standard rather than the frame's own so that the level
    /// belongs to the lens. Measured against the frame instead, the level would
    /// move whenever the hottest ghost did: a smaller source sharpens a ghost
    /// near focus into a dot thousands of times brighter than the rest, and
    /// anchoring on that dot would dim every other ghost to nothing. As it is, a
    /// smaller source makes that one dot blow out, which is what it does in a
    /// photograph, and leaves the others alone.
    static let lensFlareGain = 0.1
    /// What all a lens's ghosts together may add to the frame, as an average
    /// over it, under the same standard conditions. See `flareLens(for:)`.
    static let lensFlareVeil = 0.025
    /// The angular radius, in radians, of the source the level is set for.
    static let flareReferenceSource = 0.02
    /// The angle off the axis, in radians, the level and the ghost ranking are
    /// worked out at.
    static let flareReferenceAngle = 0.15

    /// How much of a pixel a ghost's edge is softened by, over and above what the
    /// source's size does, so an edge is never a stair even from a point source.
    static let flarePixelSoftness = 0.6
    /// The linear light under which a ghost is not drawn. More than half of a
    /// lens's ghosts are usually far too faint to show, and they tend to be the
    /// widest, so the dearest to draw. The bar is low enough that a dozen ghosts
    /// left out together still add up to under two steps of an eight-bit frame,
    /// so none is seen arriving as the light moves.
    static let flareFaintest = 0.00012

    /// What one arm of the star is worth where the baked pattern reads 1, at
    /// `strength` and `star` both 1.
    ///
    /// The pattern's mean is 1 and its core runs thousands of times above that,
    /// so this level blows the core out (which is what a source does) and leaves
    /// the arms in a range the picture can hold.
    static let lensFlareStarGain = 0.4

    /// The star pattern for a blade count and an amount of wear, baked once and
    /// kept. Wear is held to twentieths, so a dial dragged across its range bakes
    /// twenty patterns rather than one per frame.
    func flareStar(blades: Int, wear: Double) -> MTLTexture? {
        let step = Int((min(1, max(0, wear)) * 20).rounded())
        if let cached = flareStarCache, cached.blades == blades, cached.wear == step {
            return cached.texture
        }
        let pattern = ApertureStar.bake(blades: blades, wear: Double(step) / 20)
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba16Float, width: pattern.size, height: pattern.size,
            mipmapped: false)
        descriptor.usage = .shaderRead
        guard let texture = device.makeTexture(descriptor: descriptor) else { return nil }
        // The bake is worked out in full floats and the texture holds halves, so
        // the core's ceiling is what keeps the brightest texels representable.
        let half = pattern.pixels.map { Float16($0) }
        half.withUnsafeBytes { bytes in
            texture.replace(region: MTLRegionMake2D(0, 0, pattern.size, pattern.size),
                            mipmapLevel: 0, withBytes: bytes.baseAddress!,
                            bytesPerRow: pattern.size * 8)
        }
        flareStarCache = (blades, step, texture)
        return texture
    }

    /// One source, worked out into the terms the flare uses.
    private struct FlareSource {
        /// The angle the source arrives at the front of the lens, in radians.
        var angle: SIMD2<Double>
        /// Where it sits on the frame, y-normalized.
        var frame: SIMD2<Double>
        /// The depth the visibility test compares the scene against.
        var depth: Double
        /// The source's own linear color, already carrying its intensity.
        var color: SIMD3<Double>
        /// How bright it is, which decides who gets carried when there are too many.
        var weight: Double
    }

    /// Add the lens flare to the resolved linear frame, returning the texture the
    /// rest of the chain should read, or the input untouched when the frame does
    /// not flare (no flare set, no camera, no light, an orthographic camera, or a
    /// lens that makes no ghosts), so a sketch without it is unchanged.
    ///
    /// This sits after the temporal resolve and the motion blur and before the
    /// frame filters, which puts it in linear light and ahead of the tone map. A
    /// flare is light arriving at the sensor, not paint on the finished picture,
    /// so a bloom placed after it glows the ghosts the way it glows everything
    /// else bright.
    func applyLensFlare(_ drawer: Drawer, resolved: MTLTexture, depth: MTLTexture?,
                        into cb: MTLCommandBuffer, width: Int, height: Int,
                        pooled: Bool) -> MTLTexture {
        guard let flare = drawer.lensFlareSetting, let camera = drawer.camera3D,
              let depth, !drawer.lights.isEmpty, width > 0, height > 0 else { return resolved }
        let aspect = Double(width) / Double(height)
        let projection = camera.projectionMatrix(aspect: aspect)
        // A flare needs a vantage point. An orthographic camera has no angle off
        // the axis to give a source, so it never makes one.
        guard projection.columns.3.w == 0,
              projection.columns.1.y > 0, projection.columns.0.x > 0 else { return resolved }
        let tanHalfFieldOfView = 1 / Double(projection.columns.1.y)
        let lensAspect = Double(projection.columns.1.y / projection.columns.0.x)
        guard let flareLens = flareLens(for: flare.lens) else { return resolved }
        let optics = flareLens.optics
        guard !optics.ghosts.isEmpty, optics.directScale != 0, flareLens.level > 0,
              optics.pupilRadius > 0, optics.irisRadius > 0 else { return resolved }

        let viewProjection = projection * camera.viewMatrix
        let eye = camera.eye.simd3
        var sources: [FlareSource] = []
        for light in drawer.resolvedLights {
            let clip: SIMD4<Float>
            var pulledBack: SIMD3<Float>?
            switch light.kind {
            case .directional:
                // The sun sits at the end of the direction it comes from, which is
                // as far away as the projection reaches.
                clip = viewProjection * SIMD4<Float>((light.direction * -1).normalized.simd3, 0)
            default:
                let position = light.position.simd3
                clip = viewProjection * SIMD4<Float>(position, 1)
                // The depth the visibility test compares against sits a little in
                // front of the light, so a fixture drawn around its own bulb does
                // not put out the flare it is there to make.
                pulledBack = eye + (position - eye) * 0.98
            }
            guard clip.w > 1e-6 else { continue }   // behind the camera
            let frame = SIMD2<Double>(Double(clip.x / clip.w) * lensAspect, Double(clip.y / clip.w))
            guard simd_length(frame) <= 1 + flare.reach else { continue }
            // A source beyond the far plane projects past 1, where nothing in the
            // depth buffer could ever be farther, so hold it at the back of the
            // scene: an empty pixel then reads as seeing it.
            var testDepth = min(Double(clip.z / clip.w), 1)
            if let pulledBack {
                let near = viewProjection * SIMD4<Float>(pulledBack, 1)
                if near.w > 1e-6 { testDepth = min(Double(near.z / near.w), 1) }
            }
            let intensity = light.intensity
            let color = SIMD3<Double>(Color.srgbToLinear(light.color.red) * intensity,
                                      Color.srgbToLinear(light.color.green) * intensity,
                                      Color.srgbToLinear(light.color.blue) * intensity)
            let weight = 0.2126 * color.x + 0.7152 * color.y + 0.0722 * color.z
            guard weight > 1e-4 else { continue }
            // An anamorphic front group squeezes the view sideways before the lens
            // sees it, so the light arrives at the lens itself from a shallower
            // angle across than it stands at on the frame.
            let seen = SIMD2(frame.x / flare.lens.squeeze, frame.y)
            sources.append(FlareSource(angle: seen * tanHalfFieldOfView, frame: frame,
                                       depth: testDepth, color: color, weight: weight))
        }
        if sources.count > Int(OLLIN_MAX_FLARE_LIGHTS) {
            sources = Array(sources.sorted { $0.weight > $1.weight }
                .prefix(Int(OLLIN_MAX_FLARE_LIGHTS)))
        }
        guard !sources.isEmpty else { return resolved }
        // The brightest source in the frame is the anchor the rest measure against.
        let brightest = sources.map(\.weight).max() ?? 1

        // The ghosts are worked out at half the frame's size each way and the
        // star at full size (see `ollin_flare_ghosts`).
        let ghostWidth = max(1, (width + 1) / 2), ghostHeight = max(1, (height + 1) / 2)
        guard let visibility = acquireFilterTexture(width: Int(OLLIN_MAX_FLARE_LIGHTS),
                                                    height: 1, pooled: pooled),
              let ghostLight = acquireFilterTexture(width: ghostWidth, height: ghostHeight,
                                                    pooled: pooled),
              let output = acquireFilterTexture(width: width, height: height, pooled: pooled),
              let tracedLight = acquireFilterTexture(width: ghostWidth, height: ghostHeight,
                                                     pooled: pooled),
              let ghostState = try? pipeline(.effect("ollin_flare_ghosts")),
              let state = try? pipeline(.effect("ollin_flare_composite")) else { return resolved }

        // How much of each source the camera can see, one light per pixel of a
        // four-pixel strip, so the composite pays one texture read per light
        // instead of a ring of depth taps per pixel.
        var visionParams = [SIMD4<Float>](repeating: .zero, count: 1 + Int(OLLIN_MAX_FLARE_LIGHTS))
        visionParams[0] = SIMD4(Float(flare.sourceSize), Float(lensAspect),
                                Float(sources.count), 2e-5)
        for (index, source) in sources.enumerated() {
            visionParams[1 + index] = SIMD4(Float(source.frame.x / lensAspect * 0.5 + 0.5),
                                            Float(0.5 - source.frame.y * 0.5),
                                            Float(source.depth), 1)
        }
        encodeEffectFragment("ollin_flare_visibility", inputs: [depth], output: visibility,
                             params: visionParams, into: cb)

        var uniforms = OllinLensFlareUniforms()
        uniforms.lightCount = Int32(sources.count)
        uniforms.ghostCount = Int32(optics.ghosts.count)
        uniforms.optics = SIMD4<Float>(Float(optics.pupilRadius), Float(optics.irisRadius),
                                       Float(optics.directScale * tanHalfFieldOfView),
                                       Float(lensAspect))
        // The star's drawn size is measured at the iris wide open and grows as the
        // iris closes, since light bending around a smaller opening spreads
        // further. The size itself is chosen rather than physical: a real star's
        // arms are visible only because the source is thousands of times brighter
        // than the scene, and that reach is far outside what a bake of this size
        // can hold. What stays physical is its shape and how it answers the iris.
        // More blades than the frame carries is an opening no eye tells from round.
        let asked = max(0, camera.apertureBlades)
        let blades = asked >= 3 && asked <= Int(OLLIN_MAX_FLARE_BLADES) ? asked : 0
        // A bladed opening is the polygon inscribed in the iris's circle, so the
        // distance to a blade's edge is shorter than the radius.
        let inner = optics.irisRadius * (blades >= 3 ? cos(Double.pi / Double(blades)) : 1)
        // Held at eight times, since a lens stopped past that is a pinhole and its
        // star would otherwise reach across the whole picture.
        let openness = min(8, optics.irisRadius > 0 ? optics.openIrisRadius / optics.irisRadius : 1)
        let starExtent = flare.star > 0 ? flare.starSize * openness : 0
        // The iris moves the flare's light around and neither adds nor removes
        // any. Closing it shrinks a ghost, and the same light in a smaller shape
        // is a brighter one, by as much as the shape shrank (`gathered`, below,
        // worked out per ghost: a ghost the front opening bounds rather than the
        // iris does not shrink, so it does not brighten either). The star goes
        // the other way for the same reason. It grows as the iris closes, so the
        // same light runs along longer arms and each stretch is fainter.
        let concentration = openness * openness
        /// How much brighter closing the iris has made one ghost: the area it
        /// covered wide open over the area it covers now.
        func gathered(_ ghost: LensGhost) -> Double {
            let across = max(abs(ghost.toIris.a), 1e-9)
            let open = min(optics.openIrisRadius / across, optics.pupilRadius)
            let now = min(optics.irisRadius / across, optics.pupilRadius)
            return min(64, (open * open) / max(now * now, 1e-12))
        }
        uniforms.iris = SIMD4<Float>(Float(blades), Float(starExtent),
                                     Float(inner), Float(flareLens.coatingRows))
        withUnsafeMutablePointer(to: &uniforms.blades) { tuple in
            tuple.withMemoryRebound(to: simd_float4.self,
                                   capacity: Int(OLLIN_MAX_FLARE_BLADES) / 2) { buffer in
                // An edge's normal points along the x axis first, which is how the
                // star's bake and the defocus filter turn the same opening.
                func normal(_ k: Int) -> SIMD2<Float> {
                    guard k < blades else { return .zero }
                    let turn = 2 * Double.pi * Double(k) / Double(blades)
                    return SIMD2(Float(cos(turn)), Float(sin(turn)))
                }
                for pair in 0..<(Int(OLLIN_MAX_FLARE_BLADES) / 2) {
                    let first = normal(pair * 2), second = normal(pair * 2 + 1)
                    buffer[pair] = SIMD4(first.x, first.y, second.x, second.y)
                }
            }
        }
        withUnsafeMutablePointer(to: &uniforms.bladeStretch) { tuple in
            tuple.withMemoryRebound(to: simd_float4.self,
                                   capacity: Int(OLLIN_MAX_FLARE_BLADES) / 4) { buffer in
                // A step `d` along a normal `n` on the sensor is `(s n.x, n.y) d`
                // on the frame, and the edge has turned with the stretch, so the
                // distance to it there is `d` over the length of `(n.x / s, n.y)`.
                let squeeze = max(flare.lens.squeeze, 1)
                func stretch(_ k: Int) -> Float {
                    guard k < blades else { return 1 }
                    let turn = 2 * Double.pi * Double(k) / Double(blades)
                    return Float(1 / (pow(cos(turn) / squeeze, 2) + pow(sin(turn), 2)).squareRoot())
                }
                for group in 0..<(Int(OLLIN_MAX_FLARE_BLADES) / 4) {
                    buffer[group] = SIMD4(stretch(group * 4), stretch(group * 4 + 1),
                                          stretch(group * 4 + 2), stretch(group * 4 + 3))
                }
            }
        }
        withUnsafeMutablePointer(to: &uniforms.starTints) { tuple in
            tuple.withMemoryRebound(to: simd_float4.self,
                                   capacity: Int(OLLIN_MAX_FLARE_LIGHTS)) { buffer in
                for (index, source) in sources.enumerated() {
                    let level = flare.amount * flare.star * MetalRenderer.lensFlareStarGain
                        / concentration
                    let color = (source.color / brightest) * level
                    buffer[index] = SIMD4(Float(color.x), Float(color.y), Float(color.z), 0)
                }
            }
        }
        withUnsafeMutablePointer(to: &uniforms.sourceTints) { tuple in
            tuple.withMemoryRebound(to: simd_float4.self,
                                   capacity: Int(OLLIN_MAX_FLARE_LIGHTS)) { buffer in
                for (index, source) in sources.enumerated() {
                    let color = (source.color / brightest) * flare.amount
                    buffer[index] = SIMD4(Float(color.x), Float(color.y), Float(color.z), 0)
                }
            }
        }
        // The streak, the halo and the dirt. A length given in frame heights is
        // twice as many y-normalized units, the frame being two of those tall.
        let thinnest = 1.3 * 2 / Double(height)
        let tint = flare.streakTint
        uniforms.streak = SIMD4(Float(flare.streak * MetalRenderer.flareStreakGain),
                                Float(flare.streakLength * 2),
                                Float(cos(flare.streakAngle)), Float(sin(flare.streakAngle)))
        uniforms.streakTint = SIMD4(Float(Color.srgbToLinear(tint.red)),
                                    Float(Color.srgbToLinear(tint.green)),
                                    Float(Color.srgbToLinear(tint.blue)),
                                    Float(max(flare.sourceSize * 2 * 0.6, thinnest)))
        uniforms.halo = SIMD4(Float(flare.halo * MetalRenderer.flareHaloGain),
                              Float(flare.haloSize * 2),
                              Float(flare.haloSize * 2 * MetalRenderer.flareHaloWidth),
                              Float(flare.lens.squeeze))
        let speckCount = Int((flare.dirt * Double(MetalRenderer.flareDirtSpecks)).rounded())
        uniforms.dirt = SIMD4(Float(speckCount), Float(MetalRenderer.flareDirtGain),
                              Float(MetalRenderer.flareDirtReach), 0)
        withUnsafeMutablePointer(to: &uniforms.lights) { tuple in
            tuple.withMemoryRebound(to: simd_float4.self,
                                   capacity: Int(OLLIN_MAX_FLARE_LIGHTS)) { buffer in
                for (index, source) in sources.enumerated() {
                    buffer[index] = SIMD4(Float(source.angle.x), Float(source.angle.y),
                                          Float(source.frame.x), Float(source.frame.y))
                }
            }
        }
        // The source's disc as an angle, and a pixel as a length on the sensor:
        // the two things that soften a ghost's edge. `sourceSize` is a radius in
        // frame heights, and the frame is two y-normalized units tall.
        let sourceAngle = flare.sourceSize * 2 * tanHalfFieldOfView
        let sensorPerUnit = optics.directScale * tanHalfFieldOfView
        // A pixel of the canvas the ghosts are drawn on, which is the half-size one.
        let pixel = MetalRenderer.flarePixelSoftness * abs(sensorPerUnit) * 2 / Double(ghostHeight)
        let ghostCount = optics.ghosts.count
        let squeeze = max(flare.lens.squeeze, 1)
        let widestAngle = sources.map { simd_length($0.angle) }.max() ?? 0
        var shares = [Double](repeating: 1, count: Int(OLLIN_MAX_FLARE_GHOSTS))
        // How much of each ghost is drawn by following rays, from 1 (all of it)
        // to 0 (none). Following rays is the truer picture wherever a ghost has
        // an edge to speak of: it is what bends the ghost, stops it at the
        // barrel, and folds caustics into it. Where the source is wider than the
        // opening the ghost is a picture of the source instead, all of that is
        // smeared away, and first order already draws it right, so such a ghost
        // stays with the pass above. Between the two a ghost is shared out, so
        // nothing changes hands in one step as a dial moves.
        var followed = [Double](repeating: 0, count: Int(OLLIN_MAX_FLARE_GHOSTS))
        var softness = [(barrel: Double, iris: Double, floor: Double)](
            repeating: (0, 0, 0), count: Int(OLLIN_MAX_FLARE_GHOSTS))
        var maps = [SIMD4<Float>](repeating: .zero, count: Int(OLLIN_MAX_FLARE_GHOSTS) * 3)
        var spreads = maps
        var incidence = [SIMD4<Float>](repeating: .zero, count: Int(OLLIN_MAX_FLARE_GHOSTS))
        var meeting = incidence
        // A ghost exactly in focus has no scale to run backwards through; holding
        // it a hair off keeps the map finite and looks the same.
        func held(_ scale: Double) -> Double {
            abs(scale) < 1e-4 ? (scale < 0 ? -1e-4 : 1e-4) : scale
        }
        for (index, ghost) in optics.ghosts.enumerated() {
            let rows = Double(ghost.secondInterface * 2) + 256 * Double(ghost.firstInterface * 2 + 1)
            var overPupils = [Double](repeating: 0, count: 3), overIrises = overPupils
            for channel in 0..<3 {
                let map = ghost.channels[channel]
                let a = held(map.sensorA), b = map.sensorB
                maps[index * 3 + channel] = SIMD4(Float(a), Float(b),
                                                  Float(map.irisA), Float(map.irisB))
                // Every point of the source throws its own copy of the ghost.
                // Moving the source by an angle moves the ray that lands on a
                // given pixel across the front opening by `b / a` of it, and
                // across the iris by `throughIris` of it, so those are the radii
                // the source's disc takes on the two planes the ghost is clipped
                // in. On the sensor that is one radius for every color, `b` times
                // the source's, which is why the spreads are worked out per
                // channel: a picture of the source is the same size in red as in
                // blue, however differently the two are magnified.
                let throughIris = map.irisA * b / a - map.irisB
                let overPupil = (pow(sourceAngle * b / a, 2) + pow(pixel / a, 2)).squareRoot()
                let overIris = (pow(sourceAngle * throughIris, 2)
                                + pow(pixel * map.irisA / a, 2)).squareRoot()
                // Both tests dim a ghost smaller than the source by the ratio of
                // the areas. Only the tighter of the two should: the wider
                // opening has the narrower one inside it.
                // Behind an anamorphic front group the source is an ellipse
                // `1 / squeeze` as wide as it is tall, so that much less in area,
                // which is the ratio the shader's own cap uses.
                let pupilShare = overPupil > 0 ? min(1, squeeze * pow(optics.pupilRadius / overPupil, 2)) : 1
                let irisShare = overIris > 0 ? min(1, squeeze * pow(inner / overIris, 2)) : 1
                spreads[index * 3 + channel] = SIMD4(Float(overPupil), Float(overIris),
                                                     Float(1 / max(pupilShare, irisShare, 1e-12)),
                                                     Float(rows))
                overPupils[channel] = overPupil
                overIrises[channel] = overIris
                if channel == 1 { shares[index] = min(pupilShare, irisShare) }
            }
            // How far the three channels part, measured on the two planes the
            // ghost is clipped in. It sets two things: how far out, by the green
            // map, a pixel can sit and still be reached by some channel, and how
            // deep inside the ghost a pixel has to be before all three agree it
            // is covered and their edges need not be worked out one by one.
            let own = ghost.channels[1]
            let ownScale = held(own.sensorA)
            var reach = 0.0, room = 0.0
            for channel in 0..<3 {
                let other = ghost.channels[channel]
                let scale = held(other.sensorA)
                let slip = abs(own.sensorB - other.sensorB) * widestAngle
                reach = max(reach, ((optics.pupilRadius + overPupils[channel]) * abs(scale) + slip)
                            / abs(ownScale))
                let onPupil = optics.pupilRadius * abs(ownScale / scale - 1) + slip / abs(scale)
                let onIris = abs(other.irisA) * onPupil
                    + abs(other.irisA - own.irisA) * optics.pupilRadius
                    + abs(other.irisB - own.irisB) * widestAngle
                room = max(room,
                           (onPupil + abs(overPupils[channel] - overPupils[1])) / optics.pupilRadius,
                           (onIris + abs(overIrises[channel] - overIrises[1])) / max(inner, 1e-9))
            }
            spreads[index * 3 + 1].w = Float(reach * 1.02)
            spreads[index * 3 + 2].w = room * 1.25 < 0.35 ? Float(room * 1.25 + 0.01) : 0

            if flareLens.trace != nil, MetalRenderer.flareFollowsRays {
                let wide = max(overPupils[1] / optics.pupilRadius, overIrises[1] / max(inner, 1e-9))
                let t = min(1, max(0, (wide - 0.3) / 0.3))
                followed[index] = 1 - t * t * (3 - 2 * t)
                // The least a bundle of rays can be squeezed to: the source's own
                // picture on the sensor, and a pixel, however hard the lens
                // focuses them. It is what keeps a caustic finite.
                // The squeezed source's picture is `1 / squeeze` the area, and this
                // floor is one on area, so each of its two lengths gives up the
                // root of that.
                let blur = (pow(sourceAngle * own.sensorB, 2) + pow(pixel, 2)).squareRoot()
                let narrow = blur / optics.pupilRadius / squeeze.squareRoot()
                softness[index] = (overPupils[1] / optics.pupilRadius, overIrises[1],
                                   narrow * max(abs(ownScale), narrow))
            }
            // What the analytic pass draws of this ghost: the share not followed
            // ray by ray, at the brightness the iris has gathered it to.
            for channel in 0..<3 {
                spreads[index * 3 + channel].z *= Float((1 - followed[index]) * gathered(ghost))
            }
            incidence[index] = SIMD4(Float(ghost.outerIncidence.pupil), Float(ghost.outerIncidence.angle),
                                     Float(ghost.innerIncidence.pupil), Float(ghost.innerIncidence.angle))

            let green = ghost.channels[1]
            let a = held(green.sensorA), b = green.sensorB
            let throughIris = green.irisA * b / a - green.irisB
            // As the source sees them: the front opening and the iris, each as a
            // disc of angles. When the source is wider than the smaller of the
            // two, that ghost is a picture of the source and the two openings
            // have to be checked against each other.
            let pupilAngle = abs(b) > 1e-9 ? optics.pupilRadius * abs(a / b) : Double.infinity
            let irisAngle = abs(throughIris) > 1e-9 ? inner / abs(throughIris) : Double.infinity
            let smaller = min(pupilAngle, irisAngle)
            guard smaller.isFinite, smaller > 0 else { continue }
            let t = min(1, max(0, (sourceAngle / smaller - 0.5) / 1.5))
            let weight = t * t * (3 - 2 * t)
            guard weight > 0 else { continue }
            if pupilAngle <= irisAngle {
                meeting[index] = SIMD4(Float(weight), 1, Float(green.irisB / b),
                                       Float(optics.pupilRadius * abs(a * throughIris / b)))
            } else {
                let carry = b / (a * throughIris)
                meeting[index] = SIMD4(Float(weight), 2, Float(carry), Float(inner * abs(carry)))
            }
        }
        var lightLevels: [SIMD3<Double>] = []
        var lightShows: [[(ghost: Int, peak: Double)]] = []
        withUnsafeMutablePointer(to: &uniforms.levels) { tuple in
            tuple.withMemoryRebound(to: simd_float4.self,
                                   capacity: Int(OLLIN_MAX_FLARE_LIGHTS)) { buffer in
                for (index, source) in sources.enumerated() {
                    // Measured against the frame's brightest source, so the dial
                    // means the same thing whatever a sketch lights its scene with.
                    let color = (source.color / brightest) * (flare.amount * flareLens.level)
                    // Which of this light's ghosts could show. A ghost is judged
                    // by the brightest its coatings come out anywhere across it,
                    // the middle and either rim, since a rim met steeply can
                    // reflect many times what the middle does.
                    let strongest = max(color.x, color.y, color.z)
                    let angle = simd_length(source.angle)
                    var shows: UInt32 = 0
                    lightLevels.append(color)
                    lightShows.append([])
                    for (ghostIndex, ghost) in optics.ghosts.enumerated() {
                        let rim = min(optics.pupilRadius,
                                      optics.irisRadius / max(abs(ghost.toIris.a), 1e-9))
                        var reflect = 0.0
                        for pupil in [0, rim, -rim] {
                            let value = flare.lens.ghostReflectance(ghost, angle: angle, pupil: pupil)
                            reflect = max(reflect, value.x, value.y, value.z)
                        }
                        let scale = held(ghost.channels[1].sensorA)
                        let peak = strongest * reflect * shares[ghostIndex] * gathered(ghost)
                            / (scale * scale)
                        guard peak >= MetalRenderer.flareFaintest else { continue }
                        lightShows[index].append((ghostIndex, peak))
                        if followed[ghostIndex] < 1 { shows |= 1 << UInt32(ghostIndex) }
                    }
                    buffer[index] = SIMD4(Float(color.x), Float(color.y), Float(color.z), Float(shows))
                }
            }
        }
        withUnsafeMutablePointer(to: &uniforms.ghosts) { tuple in
            tuple.withMemoryRebound(to: simd_float4.self, capacity: maps.count) { buffer in
                for index in 0..<(ghostCount * 3) { buffer[index] = maps[index] }
            }
        }
        withUnsafeMutablePointer(to: &uniforms.incidence) { tuple in
            tuple.withMemoryRebound(to: simd_float4.self, capacity: incidence.count) { buffer in
                for index in 0..<ghostCount { buffer[index] = incidence[index] }
            }
        }
        withUnsafeMutablePointer(to: &uniforms.spreads) { tuple in
            tuple.withMemoryRebound(to: simd_float4.self, capacity: spreads.count) { buffer in
                for index in 0..<(ghostCount * 3) { buffer[index] = spreads[index] }
            }
        }
        withUnsafeMutablePointer(to: &uniforms.meeting) { tuple in
            tuple.withMemoryRebound(to: simd_float4.self, capacity: meeting.count) { buffer in
                for index in 0..<ghostCount { buffer[index] = meeting[index] }
            }
        }

        let ghostPass = MTLRenderPassDescriptor()
        ghostPass.colorAttachments[0].texture = ghostLight
        ghostPass.colorAttachments[0].loadAction = .dontCare
        ghostPass.colorAttachments[0].storeAction = .store
        guard let ghostEncoder = countedEncoder(cb, ghostPass, caller: "lens flare ghosts") else {
            return resolved
        }
        ghostEncoder.setRenderPipelineState(ghostState)
        ghostEncoder.setFragmentTexture(visibility, index: 0)
        ghostEncoder.setFragmentTexture(flareLens.coating, index: 1)
        ghostEncoder.setFragmentSamplerState(imageSampler, index: 0)
        ghostEncoder.setFragmentBytes(&uniforms, length: MemoryLayout<OllinLensFlareUniforms>.stride,
                                      index: 0)
        ghostEncoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        ghostEncoder.endEncoding()

        // The dirt on the front of the lens, added onto the same canvas: a small
        // quad per speck per light, each a soft picture of the iris.
        if speckCount > 0, let dirtState = try? pipeline(.flareDirt) {
            let shrink = optics.openIrisRadius > 0 ? optics.irisRadius / optics.openIrisRadius : 1
            let specks = MetalRenderer.flareDirt.prefix(speckCount).map { speck -> SIMD4<Float> in
                SIMD4(speck.x * Float(lensAspect), speck.y,
                      Float(max(0.004, MetalRenderer.flareDirtRadius * shrink)) * speck.z, speck.w)
            }
            if let speckBuffer = device.makeBuffer(bytes: specks,
                                                   length: specks.count * MemoryLayout<SIMD4<Float>>.stride,
                                                   options: .storageModeShared) {
                let dirtPass = MTLRenderPassDescriptor()
                dirtPass.colorAttachments[0].texture = ghostLight
                dirtPass.colorAttachments[0].loadAction = .load
                dirtPass.colorAttachments[0].storeAction = .store
                if let dirtEncoder = countedEncoder(cb, dirtPass, caller: "lens flare dirt") {
                    dirtEncoder.setRenderPipelineState(dirtState)
                    dirtEncoder.setVertexBytes(&uniforms, length: MemoryLayout<OllinLensFlareUniforms>.stride,
                                               index: 0)
                    dirtEncoder.setVertexBuffer(speckBuffer, offset: 0, index: 1)
                    dirtEncoder.setVertexTexture(visibility, index: 0)
                    dirtEncoder.setFragmentBytes(&uniforms, length: MemoryLayout<OllinLensFlareUniforms>.stride,
                                                 index: 0)
                    dirtEncoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 6,
                                               instanceCount: speckCount * sources.count)
                    dirtEncoder.endEncoding()
                }
            }
        }

        // The ghosts that are followed ray by ray, added over the ones above.
        var hasTraced = false
        if var lens = flareLens.trace, let traceState = try? pipeline(.flareGhostTrace),
           let samples = flareSamples(width: ghostWidth, height: ghostHeight) {
            lens.frame.x = Float(sensorPerUnit)
            // The squeeze rides the aspect: a ghost's place across the sensor is
            // stretched back out by it on the way to the frame.
            lens.frame.y = Float(lensAspect / flare.lens.squeeze)
            // Each ghost in its one-pass form, and in its seven-pass form when its
            // colors part enough to need it.
            var entries: [(single: OllinFlareGhostDraw, spectrum: [OllinFlareGhostDraw],
                           peak: Double, side: Int)] = []
            for (lightIndex, source) in sources.enumerated() {
                let slope = source.angle
                for shown in lightShows[lightIndex] where followed[shown.ghost] > 0 {
                    let ghost = optics.ghosts[shown.ghost]
                    let map = ghost.channels[1]
                    // The grid covers the whole front opening, with room for the
                    // soft edge, and the barrel and the iris do the clipping, which
                    // they do exactly. Trimming the grid to the rays first order
                    // says can clear the iris would save rays, and it is wrong in
                    // the one case that matters: a strongly bent ghost's real rays
                    // enter nowhere near where first order puts them, and the ghost
                    // then comes out cut by the grid's own square, corners and all.
                    let soft = softness[shown.ghost]
                    let half = optics.pupilRadius * (1.12 + soft.barrel)
                    let center = SIMD2<Double>.zero
                    // Rays enough that a cell stays a few pixels across on the
                    // canvas, whatever the ghost magnifies the opening by.
                    let across = 2 * half * abs(held(ghost.toSensor.a)) * flare.lens.squeeze
                        / (pixel / MetalRenderer.flarePixelSoftness)
                    let side = MetalRenderer.flareGridSides.first {
                        Double($0) * MetalRenderer.flareCellPixels >= across }
                        ?? MetalRenderer.flareGridSides[MetalRenderer.flareGridSides.count - 1]
                    var draw = OllinFlareGhostDraw()
                    draw.grid = SIMD4(Float(center.x), Float(center.y), Float(half), Float(side))
                    draw.path = SIMD4(Float(slope.x), Float(slope.y),
                                      Float(ghost.firstInterface), Float(ghost.secondInterface))
                    let a = held(ghost.toSensor.a)
                    draw.ring = SIMD4(Float(ghost.ringScale), Float(a * a),
                                      Float(a), Float(ghost.toSensor.b))
                    draw.source = SIMD4(Float(lightIndex), 0, 0, 0)
                    let level = lightLevels[lightIndex] * (followed[shown.ghost] * gathered(ghost))

                    // How far apart this ghost's colors land, against a pixel of
                    // the canvas it is drawn on. Under a pixel, one pass carries
                    // all three at the index the table prints. Over it, the ghost
                    // is followed once per wavelength, each bent by its own glass.
                    var parts = 0.0
                    for channel in [0, 2] {
                        let other = ghost.channels[channel]
                        parts = max(parts, abs(other.sensorA - map.sensorA) * half
                                    + abs(other.sensorB - map.sensorB) * simd_length(slope))
                    }
                    let channels = Lens.channelWavelengths
                    var single = draw
                    single.colors.0 = SIMD4(Float(level.x), 0, 0, Float(channels.x))
                    single.colors.1 = SIMD4(0, Float(level.y), 0, Float(channels.y))
                    single.colors.2 = SIMD4(0, 0, Float(level.z), Float(channels.z))
                    single.soft = SIMD4(Float(soft.barrel), Float(soft.iris), Float(soft.floor),
                                        Float(Int(OLLIN_LENS_WAVELENGTH_SLOTS) - 1))
                    var spectrum: [OllinFlareGhostDraw] = []
                    if parts > 1.5 * pixel / MetalRenderer.flarePixelSoftness,
                       shown.peak >= MetalRenderer.flareColoredFrom {
                        for (slot, wavelength) in Lens.spectrumWavelengths.enumerated() {
                            var one = draw
                            let tint = Lens.spectrumColors[slot] * level
                            one.colors.0 = SIMD4(Float(tint.x), Float(tint.y), Float(tint.z), Float(wavelength))
                            one.soft = SIMD4(Float(soft.barrel), Float(soft.iris), Float(soft.floor), Float(slot))
                            spectrum.append(one)
                        }
                    }
                    entries.append((single, spectrum, shown.peak, side))
                }
            }
            // Over budget, the faintest ghosts give up their colors first.
            var total = entries.reduce(0) { $0 + max(1, $1.spectrum.count) }
            for index in entries.indices.sorted(by: { entries[$0].peak < entries[$1].peak })
            where total > MetalRenderer.flareMaxTracedDraws && !entries[index].spectrum.isEmpty {
                total -= entries[index].spectrum.count - 1
                entries[index].spectrum = []
            }
            // One pass, cleared and resolved whether or not anything is drawn, so
            // what the composite reads is always this frame's.
            let tracePass = MTLRenderPassDescriptor()
            tracePass.colorAttachments[0].texture = samples
            tracePass.colorAttachments[0].resolveTexture = tracedLight
            tracePass.colorAttachments[0].loadAction = .clear
            tracePass.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)
            tracePass.colorAttachments[0].storeAction = .multisampleResolve
            if let traceEncoder = countedEncoder(cb, tracePass, caller: "lens flare rays") {
                hasTraced = true
                traceEncoder.setRenderPipelineState(traceState)
                traceEncoder.setVertexBytes(&lens, length: MemoryLayout<OllinLensTraceUniforms>.stride, index: 0)
                traceEncoder.setVertexTexture(visibility, index: 0)
                traceEncoder.setFragmentBytes(&uniforms,
                                              length: MemoryLayout<OllinLensFlareUniforms>.stride, index: 0)
                // Ghosts of one grid size go out together, since they share triangles.
                for side in MetalRenderer.flareGridSides {
                    let draws = entries.filter { $0.side == side }
                        .flatMap { $0.spectrum.isEmpty ? [$0.single] : $0.spectrum }
                    guard !draws.isEmpty, let grid = flareGrid(side: side),
                          let drawBuffer = device.makeBuffer(
                            bytes: draws, length: draws.count * MemoryLayout<OllinFlareGhostDraw>.stride,
                            options: .storageModeShared) else { continue }
                    traceEncoder.setVertexBuffer(drawBuffer, offset: 0, index: 1)
                    traceEncoder.drawIndexedPrimitives(type: .triangle, indexCount: grid.count,
                                                       indexType: .uint16, indexBuffer: grid.indices,
                                                       indexBufferOffset: 0, instanceCount: draws.count)
                }
                traceEncoder.endEncoding()
            }
        }
        // Whether the composite has followed ghosts to add rides a slot the star
        // leaves free.
        uniforms.starTints.0.w = hasTraced ? 1 : 0

        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = output
        pass.colorAttachments[0].loadAction = .dontCare
        pass.colorAttachments[0].storeAction = .store
        guard let encoder = countedEncoder(cb, pass, caller: "lens flare") else { return resolved }
        encoder.setRenderPipelineState(state)
        encoder.setFragmentTexture(resolved, index: 0)
        encoder.setFragmentTexture(visibility, index: 1)
        encoder.setFragmentTexture(starExtent > 0
                                   ? flareStar(blades: blades, wear: flare.wear) : visibility,
                                   index: 2)
        encoder.setFragmentTexture(ghostLight, index: 3)
        encoder.setFragmentTexture(hasTraced ? tracedLight : ghostLight, index: 4)
        encoder.setFragmentSamplerState(imageSampler, index: 0)
        encoder.setFragmentBytes(&uniforms, length: MemoryLayout<OllinLensFlareUniforms>.stride,
                                 index: 0)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        encoder.endEncoding()
        return output
    }

}
