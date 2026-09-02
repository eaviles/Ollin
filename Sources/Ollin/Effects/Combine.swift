import Foundation

/// A two-input image operation that combines one `RenderTarget` with another on
/// the GPU: a base layer plus an auxiliary layer that modulates it. Where a
/// `Filter` transforms a single layer, a `Combine` reads *two* — the base it runs
/// on and an aux it samples per pixel — so it covers the effects a single-input
/// filter can't: masking by a second layer, displacing by a second layer, and
/// cross-dissolving toward one.
///
/// Like `Filter` and `Generator`, a `Combine` is a plain value descriptor: it
/// carries the operation and its scalar parameters, not the aux layer itself (a
/// `Sendable` value can't hold a `RenderTarget`). The aux is passed alongside it
/// to `RenderTarget.combined(with:_:)`, which records the op and hands back the
/// result as a new, filterable layer:
///
/// ```swift
/// let scene = makeRenderTarget()
/// withTarget(scene) { background(.black); fill(.orange); drawCircle(width / 2, height / 2, 300) }
/// let mask = makeRenderTarget()
/// withTarget(mask) { fill(.white); drawCircle(mouseX, mouseY, 200) }   // white where visible
/// drawImage(scene.combined(with: mask, .mask()).image, 0, 0)           // scene seen through the mask
/// ```
///
/// In a `compose { }` block, the same ops read as `aside` modifiers on a layer
/// (`.masked(by:)` / `.displaced(by:amount:)` / `.mixed(with:amount:)`), where the
/// aux is itself a small layer the compositor draws only to feed the combine.
public struct Combine: Sendable {

    /// Which channel of the aux layer a `mask` reads as its mask value: the aux's
    /// luminance (draw the mask in white/gray, the default) or its alpha (draw any
    /// opaque shape, transparent elsewhere).
    public enum MaskChannel: Sendable {
        case luminance, alpha

        /// The shader's mode index (kept in step with `ollin_fx_mask`).
        var rawIndex: Float { self == .luminance ? 0 : 1 }
    }

    /// How `lineIntegralConvolution` reads a direction out of the aux layer.
    public enum FieldEncoding: Sendable, Equatable {
        /// Red and green as a vector, recentered from mid-gray (the same reading
        /// `displace` makes): a layer of `.normalMap`, or one you drew with the
        /// field's x and y in its colors.
        case vector
        /// Brightness as an angle: black is a stroke to the right, white a full
        /// `turns` turns around from it. A gray noise layer through this is the
        /// quickest flow field. Keep it smooth: at a hard edge between two tones
        /// the half-covered texel reads as the angle between them, a line along
        /// the edge that a streak follows instead of crossing.
        case angle(turns: Double = 1)
        /// Across the brightness gradient, so streaks follow the contour lines of
        /// any grayscale picture (a height map, a blurred photo, a distance field).
        case contour

        /// The shader's mode index and its turns (kept in step with `ollin_fx_lic`).
        var row: SIMD4<Float> {
            switch self {
            case .vector: return SIMD4(0, 0, 0, 0)
            case let .angle(turns): return SIMD4(1, Float(turns), 0, 0)
            case .contour: return SIMD4(2, 0, 0, 0)
            }
        }
    }

    /// The concrete operations the renderer knows how to run. Internal: a sketch
    /// builds a `Combine` through the static factories below, never this directly.
    enum Kind: Sendable {
        /// A user-supplied `Shader` run as a two-input combine (reads the base with
        /// `sample(info, uv)` and the aux with `sampleAux(info, uv)`).
        case shader(Shader)
        /// Keep the base only where the aux is bright (or opaque): multiply the base
        /// by the aux's `channel` value, optionally inverted.
        case mask(channel: MaskChannel, invert: Bool)
        /// Push the base's pixels around: offset each sample by the aux's red/green
        /// recentred to `±amount` (a fraction of the layer), the classic displacement map.
        case displace(amount: Double)
        /// Smear the base along the aux read as a direction field: each pixel is the
        /// average of the base along the streamline through it, `length` of the
        /// layer end to end, read out of the aux by `field`.
        case lineIntegralConvolution(length: Double, field: FieldEncoding)
        /// Chromatic aberration whose split is scaled per pixel by the aux layer's
        /// luminance, so dispersion sits only where something is.
        case disperse(amount: Double, mode: Filter.Dispersion, spectral: Bool,
                      quality: RenderQuality)
        /// Cross-dissolve the base toward the aux by `amount` (0 = base, 1 = aux).
        case mix(amount: Double)
        /// Blend the base toward the aux the way scattering paints blend: per pixel,
        /// per wavelength tap, through the Kubelka-Munk model over reflectance
        /// spectra, gated by the aux's own coverage.
        case paintMix(amount: Double, quality: RenderQuality)
        /// Depth-of-field: blur the base by the aux read as a depth map. The band
        /// `focus ± range` stays sharp; the blur radius grows with distance from it
        /// up to `maxBlur` pixels. `quality` sets the bokeh sample count tier.
        case defocus(focus: Double, range: Double, maxBlur: Double, quality: RenderQuality,
                     blades: Int?, irisAngle: Double, catsEye: Double)
        /// Ambient occlusion: darken the base in crevices and contacts, reading the aux
        /// as a depth map. View-space position and normal are reconstructed from the
        /// depth, and obscurance is gathered over a hemisphere `radius` world units
        /// across; `intensity` scales the darkening, `bias` rejects self-occlusion, and
        /// `quality` sets the sample-count tier.
        case ambientOcclusion(radius: Double, intensity: Double, bias: Double, quality: RenderQuality)
        /// Seamless clone: paste the aux layer into the base so the join disappears,
        /// the patch keeping its own detail and taking the base's color and brightness.
        /// The aux's opaque region is where it lands; `amount` dials the correction
        /// (0 = a plain paste, seam and all). `threshold` is the alpha a texel needs
        /// to count as covered.
        case seamlessClone(amount: Double, threshold: Double)
                /// Screen-space reflections: reflect the rendered scene onto its own surfaces,
        /// reading the aux as a depth map and the base's mesh normals. Each pixel's
        /// reflection ray is marched through screen space; where it meets the scene the
        /// base color there is sampled and composited back, weighted by Fresnel, an edge
        /// fade, and reflection distance. `roughness` blurs the reflection for a glossy
        /// finish. Only on-screen geometry can reflect (the screen-space limit).
        case screenSpaceReflections(intensity: Double, maxDistance: Double, thickness: Double,
                                    roughness: Double, fresnel: Double, edgeFade: Double,
                                    quality: RenderQuality)
        /// Light a flat scene: the base is what the light meets (its color, and its
        /// alpha stops light), the aux is what gives light off, and the result is the
        /// light arriving at every pixel.
        case light(reach: Double?, brightness: Double, bounces: Int,
                   sky: SIMD4<Float>, quality: RenderQuality)
    }

    let kind: Kind

    /// The call site that built this combine (`#fileID:#line`, captured by the factory),
    /// for ops that keep per-op state across frames. Screen-space reflections' temporal
    /// history is keyed on it: a call site is stable across frames however many *other*
    /// combines a sketch records conditionally, where a frame-wide ordinal would shift
    /// and hand a later op the wrong history. Empty for the stateless ops.
    var sourceID: String = ""

    /// A user-supplied `Shader` as a two-input combine: it reads the base with
    /// `sample(info, uv)` and `aux` with `sampleAux(info, uv)`. Use with
    /// `base.combined(with: aux, .shader(myShader))`.
    public static func shader(_ shader: Shader) -> Combine { Combine(kind: .shader(shader)) }

    /// Mask: keep the base where the aux layer reads bright (or, with
    /// `channel: .alpha`, where it's opaque), fading to transparent elsewhere. Draw
    /// the mask layer in white over transparent and the base shows through just
    /// those marks; `invert` flips it (hide where the mask is bright).
    public static func mask(channel: MaskChannel = .luminance, invert: Bool = false) -> Combine {
        Combine(kind: .mask(channel: channel, invert: invert))
    }

    /// Displace: offset the base's pixels by the aux layer, read as a vector field
    /// (red → horizontal, green → vertical, mid-gray = no shift). `amount` is the
    /// maximum shift as a fraction of the layer, so 0.05 nudges by up to 5%. Feed it
    /// a noise or gradient layer for ripples, smearing, and refraction looks.
    public static func displace(amount: Double = 0.05) -> Combine {
        Combine(kind: .displace(amount: amount))
    }

    /// Line integral convolution: smear the base along a direction field so its
    /// texture turns into streaks that trace the flow. Each pixel becomes the
    /// average of the base along the streamline through it, followed one texel at
    /// a time both ways for `length` of the layer end to end (0.04 is a short
    /// brushy stroke, 0.2 a long comb), so a picture of noise becomes a picture
    /// of the field itself, the classic way to see a flow: fill the base with
    /// mid-gray through `.grain(amount: 1)` and streak it along the field. Over a
    /// photograph the same call reads as a wind, or as hair combed the way the
    /// field runs.
    ///
    /// The aux is the field, read by `field`: `.vector` takes red and green as x
    /// and y around mid-gray (what `displace` reads, and what `.normalMap` writes),
    /// `.angle(turns:)` takes brightness as a direction (so any gray noise layer
    /// is a flow field), and `.contour` runs across the brightness gradient, so
    /// streaks follow the contour lines of whatever the aux pictures. A streamline
    /// stops where the field is zero and at the layer's edge, and a pixel is only
    /// ever averaged over the samples it reached, so a still field leaves the
    /// base as it was.
    ///
    /// ```swift
    /// let paper = makeRenderTarget()
    /// withTarget(paper) { background(.gray) }
    /// let flow = generate(.noise(scale: 3))
    /// drawImage(paper.filtered(.grain(amount: 1))
    ///                .combined(with: flow, .lineIntegralConvolution(length: 0.06,
    ///                                                                field: .angle(turns: 2)))
    ///                .image, 0, 0)
    /// ```
    public static func lineIntegralConvolution(length: Double = 0.04,
                                               field: FieldEncoding = .vector) -> Combine {
        Combine(kind: .lineIntegralConvolution(length: max(0, min(1, length)), field: field))
    }

    /// Disperse: chromatic aberration over the base layer, its `amount` scaled per
    /// pixel by the aux layer's luminance. A white aux splits by the full `amount`, a
    /// black one leaves the base alone, so the aux decides *where* the color comes
    /// apart rather than how much. The natural sibling of `displace`, and the way to
    /// put a fringe on one thing in a scene instead of on the whole frame.
    ///
    /// ```swift
    /// let heat = makeRenderTarget()
    /// withTarget(heat) { fill(.white); drawCircle(mouseX, mouseY, 220) }
    /// drawImage(scene.combined(with: heat, .disperse(amount: 0.02)).image, 0, 0)
    /// ```
    ///
    /// `mode`, `spectral`, and `quality` mean exactly what they mean on
    /// `Filter.chromaticAberration(amount:mode:spectral:quality:)`.
    public static func disperse(amount: Double = 0.02,
                                mode: Filter.Dispersion = .magnify,
                                spectral: Bool = false,
                                quality: RenderQuality = .default) -> Combine {
        Combine(kind: .disperse(amount: amount, mode: mode,
                                spectral: spectral, quality: quality))
    }

    /// Mix (cross-dissolve): blend the base toward the aux layer by `amount`, a
    /// per-pixel lerp (0 keeps the base, 1 becomes the aux, 0.5 is an even blend).
    public static func mix(amount: Double = 0.5) -> Combine {
        Combine(kind: .mix(amount: min(max(amount, 0), 1)))
    }

    /// Paint mix: blend the base toward the aux the way scattering paints blend,
    /// not the way lights cross-dissolve. Each pixel's two colors become
    /// reflectance spectra and mix through the Kubelka-Munk model over a
    /// `quality`-sized set of wavelength taps (the GPU form of
    /// `Color.mix(_:_:t:in: .paint)`), so a yellow wash over a blue field meets it
    /// in green and overlaps darken like glazes. The aux's coverage gates the mix:
    /// where the aux layer is empty the base passes through untouched, so the aux
    /// reads as paint laid over the base. `amount` is the mix at full coverage
    /// (0 keeps the base, 1 becomes the aux where it's opaque).
    public static func paintMix(amount: Double = 0.5,
                                quality: RenderQuality = .default) -> Combine {
        Combine(kind: .paintMix(amount: min(max(amount, 0), 1), quality: quality))
    }

    /// Depth of field: blur the base layer by the aux layer, read as a *depth map*
    /// (its luminance is the depth, 0 near … 1 far). Pixels whose depth lands in the
    /// band `focus ± range` stay sharp; outside it the blur grows with distance from
    /// the band, reaching `maxBlur` pixels one further `range` out. It's a circle-of-
    /// confusion bokeh gather with near/far separation, so the depth map can be anything
    /// the sketch supplies.
    ///
    /// The depth map can be a smooth gradient (a tilt-shift plane), a real depth feed, or
    /// hard-edged discrete per-object depths. Overlapping defocused regions blend like
    /// real bokeh; a defocused *foreground* spreads over what's behind it (covering an
    /// in-focus subject it sits in front of); and a sharp in-focus subject occludes the
    /// blurred things behind it with a crisp edge.
    ///
    /// A highlight comes out shaped like the opening the light passed through. An iris
    /// with `blades` makes it a polygon of that many sides, and `catsEye` clips it toward
    /// the corners the way a lens barrel does. Both leave the middle of a round opening
    /// exactly as it was.
    ///
    /// - Parameters:
    ///   - focus: the depth (0…1) that stays in focus.
    ///   - range: half-width of the sharp band, *and* the width of the falloff beyond
    ///     it (full blur is reached `2 × range` from `focus`). Smaller racks focus tighter.
    ///   - maxBlur: the largest blur radius, in layer pixels.
    ///   - quality: the bokeh sample-count tier (`.default`/`.performance`/`.detail`,
    ///     hardware-relative). More taps trade frame rate for creamier, structure-free blur.
    ///   - blades: how many blades the iris has, which is the shape an out-of-focus
    ///     highlight takes: `0` is a round opening, and 5 to 11 is what a real lens
    ///     carries. `nil` (the default) takes the blade count from the camera that drew
    ///     the depth layer (`Camera3D.apertureBlades`), so one setting shapes the live
    ///     blur, the path-traced export's own blur, and every flare ghost alike. Name it
    ///     here to shape a blur the camera knows nothing about, such as a tilt-shift over
    ///     a hand-drawn depth ramp.
    ///   - irisAngle: how far the opening is turned, in radians. It turns the highlights
    ///     with it, and has no effect on a round opening.
    ///   - catsEye: how hard the barrel clips the opening away from the middle of the
    ///     frame (0 = not at all, the default; 1 = as hard as a fast lens wide open).
    ///     Highlights stay whole in the middle and lie down into lemon shapes toward the
    ///     corners, the long way around the frame. It changes the *shape* only: reach for
    ///     the `.vignette` filter to darken the corners as well.
    public static func defocus(focus: Double = 0.5, range: Double = 0.1,
                               maxBlur: Double = 24, quality: RenderQuality = .default,
                               blades: Int? = nil, irisAngle: Double = 0,
                               catsEye: Double = 0) -> Combine {
        Combine(kind: .defocus(focus: min(max(focus, 0), 1),
                               range: max(0.001, range), maxBlur: max(0, maxBlur), quality: quality,
                               blades: blades.map { max(0, $0) }, irisAngle: irisAngle,
                               catsEye: min(max(catsEye, 0), 1)))
    }

    /// Ambient occlusion: darken the base layer where the aux layer's depth says it
    /// sits in a crevice or against a contact: the soft self-shadowing that grounds a
    /// 3D scene. Feed it a real 3D scene's own depth as the aux
    /// (`scene.combined(with: scene.depth, .ambientOcclusion())`): view-space position
    /// and surface normal are reconstructed from the depth (no separate normal buffer),
    /// then occlusion is estimated over a hemisphere of nearby samples and smoothed with
    /// a depth-aware blur, then multiplied into the base.
    ///
    /// `scene.depth` carries the camera's near/far and field of view, which set the
    /// world scale, so `radius` reads in world units. As a post-process it darkens the
    /// final image (not just the ambient term), the standard screen-space trade; dial it
    /// with `intensity`.
    ///
    /// ```swift
    /// let scene = makeRenderTarget()
    /// withTarget(scene) { camera(.perspective(eye: Vector3(0, 3, 7), target: .zero)); drawBox(...) }
    /// drawImage(scene.combined(with: scene.depth, .ambientOcclusion(radius: 0.6)).image, 0, 0)
    /// ```
    ///
    /// - Parameters:
    ///   - radius: the hemisphere radius the gather samples, in world units. Larger
    ///     reaches into broader cavities; smaller picks out fine contact shadows.
    ///   - intensity: how strongly the occlusion darkens (0 = none, 1 = the default).
    ///   - bias: rejects self-occlusion just off a flat surface, in world units. Raise
    ///     it if flat faces show faint speckle (acne), lower it if contacts look weak.
    ///   - quality: the sample-count tier (`.default`/`.performance`/`.detail`,
    ///     hardware-relative). More samples trade frame rate for smoother occlusion.
    public static func ambientOcclusion(radius: Double = 0.5, amount: Double = 1,
                                        bias: Double = 0.05, quality: RenderQuality = .default) -> Combine {
        Combine(kind: .ambientOcclusion(radius: max(0.0001, radius), intensity: max(0, amount),
                                        bias: max(0, bias), quality: quality))
    }

    /// Seamless clone: drop the aux layer into the base so the join disappears. The
    /// patch keeps its own detail and texture but takes on the color and brightness of
    /// whatever surrounds it, which is what stops a cut-out reading as a cut-out.
    ///
    /// Draw the patch into a layer of its own, transparent everywhere else: **its
    /// opaque region is where it lands**, so the shape you draw is the shape that gets
    /// cloned. Position it by drawing it where you want it.
    ///
    /// ```swift
    /// let backdrop = makeRenderTarget()
    /// withTarget(backdrop) { drawImage(wall, 0, 0) }
    /// let patch = makeRenderTarget()
    /// withTarget(patch) { drawImage(leaf, mouseX - 120, mouseY - 120) }   // transparent elsewhere
    /// drawImage(backdrop.combined(with: patch, .seamlessClone()).image, 0, 0)
    /// ```
    ///
    /// What it does is worth knowing, because it explains what it will and won't fix.
    /// Around the rim of the patch it measures how far the patch's color sits from the
    /// base's, then spreads that difference across the inside of the patch as smoothly
    /// as it can (the same settling the [`.diffuse`](Filter.swift) filter runs). Adding
    /// that back means the rim matches the base exactly, and the inside is nudged by
    /// the gentlest correction that reaches it. So a patch cut from a differently lit
    /// photo blends; a patch whose *rim* crosses a hard edge in the base smears that
    /// edge inward, which is the technique's own limit, not a bug. Keep the rim on
    /// quiet ground.
    ///
    /// - Parameters:
    ///   - amount: how much of the correction to apply. 1 is fully seamless; 0 is a
    ///     plain paste with the seam left in, which is the useful before picture.
    ///   - threshold: the alpha a texel needs to count as part of the patch. The rim
    ///     is found at this level, so raise it if a soft-edged patch reads as larger
    ///     than it looks.
    public static func seamlessClone(amount: Double = 1, threshold: Double = 0.5) -> Combine {
        Combine(kind: .seamlessClone(amount: min(max(amount, 0), 1),
                                     threshold: min(max(threshold, 0.01), 1)))
    }

    /// Screen-space reflections: make the scene reflect off its own surfaces (a glossy
    /// floor, wet asphalt, a polished tabletop). Feed the scene's own depth as the aux
    /// (`scene.combined(with: scene.depth, .screenSpaceReflections())`); view-space
    /// position and surface normal are reconstructed from it (a true mesh normal when the
    /// base holds a 3D scene), the reflection ray is marched through the depth buffer, and
    /// the scene color at the hit is composited back over the surface.
    ///
    /// It's a post-process over color + depth + normal, so every surface reflects
    /// (modulated by Fresnel and view angle), rather than a per-material property. Only
    /// what's already on screen can appear in a reflection: rays that leave the frame fade
    /// out (`edgeFade`), and off-screen or hidden geometry can't be reflected.
    ///
    /// ```swift
    /// let scene = makeRenderTarget()
    /// withTarget(scene) { camera(.perspective(eye: Vector3(0, 2, 6), target: .zero)); drawBox(...) }
    /// drawImage(scene.combined(with: scene.depth, .screenSpaceReflections()).image, 0, 0)
    /// ```
    ///
    /// - Parameters:
    ///   - intensity: overall reflection strength (0 = off, 1 = a full mirror at the
    ///     reflecting angle).
    ///   - maxDistance: how far a reflection ray travels, in world units (the depth layer
    ///     carries the camera scale). Longer reaches farther reflections at more cost.
    ///   - thickness: how close a reflection ray must pass a surface to count as a hit,
    ///     measured as a **fraction of that surface's distance** (so it scales with the scene).
    ///     Larger fills gaps between surfaces; too large smears a reflection past an edge into a
    ///     "cylinder". The 0.025 default suits most scenes.
    ///   - roughness: blurs the reflection for a glossy (rather than mirror) finish, 0…1.
    ///   - fresnel: how much the reflection strengthens at grazing angles (0 = flat
    ///     reflectivity, 1 = a strong grazing rim).
    ///   - edgeFade: fraction of the layer over which a reflection fades as its hit nears
    ///     the screen border, hiding the screen-space cutoff.
    ///   - quality: the ray-march step-count tier (`.default`/`.performance`/`.detail`).
    public static func screenSpaceReflections(
        amount: Double = 0.6, maxDistance: Double = 8, thickness: Double = 0.025,
        roughness: Double = 0, fresnel: Double = 0.5, edgeFade: Double = 0.1,
        quality: RenderQuality = .default,
        file: String = #fileID, line: Int = #line) -> Combine {
        Combine(kind: .screenSpaceReflections(
            intensity: max(0, amount), maxDistance: max(0.0001, maxDistance),
            thickness: max(0.0001, thickness), roughness: min(max(roughness, 0), 1),
            fresnel: max(0, fresnel), edgeFade: min(max(edgeFade, 0), 0.5), quality: quality),
                sourceID: "\(file):\(line)")
    }

    /// Light a flat scene: work out how much light reaches every pixel of the base
    /// layer from the lamps drawn in the aux layer, and hand that back as a layer of
    /// its own.
    ///
    /// The base is **the scene**: whatever you draw there is solid, and its alpha is
    /// how much of a ray it stops. The aux is **the lights**: whatever you draw there
    /// gives light off in its own color. The result is a picture of the light itself,
    /// so you draw it as the frame rather than over the scene.
    ///
    /// ```swift
    /// let room = makeRenderTarget()
    /// withTarget(room) { fill(Color(hex: 0x2E6F5E)); drawRect(300, 500, 480, 40) }
    /// let lamps = makeRenderTarget()
    /// withTarget(lamps) { fill(.white); drawCircle(mouseX, mouseY, 18) }
    /// drawImage(room.combined(with: lamps, .light()).image, 0, 0)
    /// ```
    ///
    /// Light behaves the way light behaves, and none of it is drawn by hand: a shape
    /// throws a shadow that is sharp beside it and soft further away, a small lamp
    /// falls off with distance because it covers less and less of the sky a pixel
    /// sees, and a lit wall gives its own color back to what stands near it.
    ///
    /// The work is done by a ladder of light fields, each with fewer places and more
    /// directions than the one below it (radiance cascades). It costs the same
    /// whatever the scene holds: one lamp and two hundred lamps take the same time,
    /// as do ten shapes and ten thousand.
    ///
    /// - Parameters:
    ///   - reach: how far light travels, in pixels. `nil` reaches across the whole
    ///     layer. A shorter reach is the speed parameter, since it takes rungs off the
    ///     ladder, and it also reads as a smaller room.
    ///   - brightness: scales the lights before anything is traced. Raise it for a
    ///     small lamp that has to fill a large space.
    ///   - bounces: how many times light comes back off what it lands on. `0` leaves
    ///     every surface black, which is the plain shadow look; `1` is the default and
    ///     is what makes a red wall throw red onto its neighbors; more is softer and
    ///     costs one more ladder each.
    ///   - sky: the light that arrives from beyond the reach of the field, for a scene
    ///     that is outdoors or in a lit room. Clear (the default) is a dark room.
    ///   - quality: how closely the light is measured (`.default` / `.performance` /
    ///     `.detail`, hardware-relative). It sets how far apart the probes of the first
    ///     rung sit and how many steps a ray may take.
    public static func light(reach: Double? = nil, brightness: Double = 1,
                             bounces: Int = 1, sky: Color = .clear,
                             quality: RenderQuality = .default) -> Combine {
        Combine(kind: .light(reach: reach.map { max(1, $0) },
                             brightness: max(0, brightness),
                             bounces: min(max(bounces, 0), 4),
                             sky: sky.linearRGBA, quality: quality))
    }
}
