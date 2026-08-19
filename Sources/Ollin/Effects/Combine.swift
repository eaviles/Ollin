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
/// let scene = renderTarget()
/// withTarget(scene) { background(.black); fill(.orange); drawCircle(width / 2, height / 2, 300) }
/// let mask = renderTarget()
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
        /// Cross-dissolve the base toward the aux by `amount` (0 = base, 1 = aux).
        case mix(amount: Double)
        /// Depth-of-field: blur the base by the aux read as a depth map. The band
        /// `focus ± range` stays sharp; the blur radius grows with distance from it
        /// up to `maxBlur` pixels. `quality` sets the bokeh sample count tier.
        case defocus(focus: Double, range: Double, maxBlur: Double, quality: RenderQuality)
        /// Ambient occlusion: darken the base in crevices and contacts, reading the aux
        /// as a depth map. View-space position and normal are reconstructed from the
        /// depth, and obscurance is gathered over a hemisphere `radius` world units
        /// across; `intensity` scales the darkening, `bias` rejects self-occlusion, and
        /// `quality` sets the sample-count tier.
        case ambientOcclusion(radius: Double, intensity: Double, bias: Double, quality: RenderQuality)
        /// Screen-space reflections: reflect the rendered scene onto its own surfaces,
        /// reading the aux as a depth map and the base's mesh normals. Each pixel's
        /// reflection ray is marched through screen space; where it meets the scene the
        /// base color there is sampled and composited back, weighted by Fresnel, an edge
        /// fade, and reflection distance. `roughness` blurs the reflection for a glossy
        /// finish. Only on-screen geometry can reflect (the screen-space limit).
        case screenSpaceReflections(intensity: Double, maxDistance: Double, thickness: Double,
                                    roughness: Double, fresnel: Double, edgeFade: Double,
                                    quality: RenderQuality)
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

    /// Mix (cross-dissolve): blend the base toward the aux layer by `amount`, a
    /// per-pixel lerp (0 keeps the base, 1 becomes the aux, 0.5 is an even blend).
    public static func mix(amount: Double = 0.5) -> Combine {
        Combine(kind: .mix(amount: min(max(amount, 0), 1)))
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
    /// - Parameters:
    ///   - focus: the depth (0…1) that stays in focus.
    ///   - range: half-width of the sharp band, *and* the width of the falloff beyond
    ///     it (full blur is reached `2 × range` from `focus`). Smaller racks focus tighter.
    ///   - maxBlur: the largest blur radius, in layer pixels.
    ///   - quality: the bokeh sample-count tier (`.default`/`.performance`/`.detail`,
    ///     hardware-relative). More taps trade frame rate for creamier, structure-free blur.
    public static func defocus(focus: Double = 0.5, range: Double = 0.1,
                               maxBlur: Double = 24, quality: RenderQuality = .default) -> Combine {
        Combine(kind: .defocus(focus: min(max(focus, 0), 1),
                               range: max(0.001, range), maxBlur: max(0, maxBlur), quality: quality))
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
    /// let scene = renderTarget()
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
    public static func ambientOcclusion(radius: Double = 0.5, intensity: Double = 1.0,
                                        bias: Double = 0.05, quality: RenderQuality = .default) -> Combine {
        Combine(kind: .ambientOcclusion(radius: max(0.0001, radius), intensity: max(0, intensity),
                                        bias: max(0, bias), quality: quality))
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
    /// let scene = renderTarget()
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
        intensity: Double = 0.6, maxDistance: Double = 8, thickness: Double = 0.025,
        roughness: Double = 0, fresnel: Double = 0.5, edgeFade: Double = 0.1,
        quality: RenderQuality = .default,
        file: String = #fileID, line: Int = #line) -> Combine {
        Combine(kind: .screenSpaceReflections(
            intensity: max(0, intensity), maxDistance: max(0.0001, maxDistance),
            thickness: max(0.0001, thickness), roughness: min(max(roughness, 0), 1),
            fresnel: max(0, fresnel), edgeFade: min(max(edgeFade, 0), 0.5), quality: quality),
                sourceID: "\(file):\(line)")
    }
}
