import Foundation
import simd

/// One fullscreen fragment pass of the effect graph, as data: the fragment it
/// runs, the `float4` rows it binds at buffer 0, and what it reads at texture 0
/// onward. The renderer encodes one; the web recorder writes one down, so the
/// two never disagree about how a filter packs its numbers. A filter or combine
/// that takes more than one pass (a blur, a solve, a ladder, a lookup the page
/// cannot carry) has no single description and answers `nil`, so its
/// orchestration stays with the renderer.
struct EffectPass: Equatable {
    var fragment: String
    var inputs: [EffectInput]
    var params: [SIMD4<Float>]
}

/// What a pass binds at one texture index.
enum EffectInput: Equatable {
    /// The op's own layer: 0 is a filter's input or a combine's base, 1 a
    /// combine's aux. A filter may bind its input twice where a shader expects a
    /// second texture it will not read.
    case layer(Int)
    /// A lookup strip read beside the layer, one texel per sample, in linear
    /// float.
    case table([SIMD4<Float>])
}

/// The tap and step counts a quality tier resolves to. The renderer reads
/// `.default` as the device's automatic tier and an export reads it as
/// `.detail`; the tables themselves are the same either way.
enum EffectQuality {
    static func dispersionTaps(_ resolved: RenderQuality) -> Int {
        switch resolved {
        case .performance: return 7
        case .default:     return 15
        case .detail:      return 31
        }
    }

    static func antialiasSteps(_ resolved: RenderQuality) -> Int {
        switch resolved {
        case .performance: return 4
        case .default:     return 8
        case .detail:      return 12
        }
    }
}

extension Filter {
    /// The single fragment pass this filter is, at a layer of `width` by
    /// `height` pixels, or `nil` for one that takes several. `resolve` turns a
    /// `.default` quality into the tier it means here.
    func singlePass(width: Int, height: Int,
                    resolve: (RenderQuality) -> RenderQuality) -> EffectPass? {
        let texel = SIMD4<Float>(1 / Float(width), 1 / Float(height), 0, 0)
        let aspect = Float(width) / Float(max(1, height))
        let f = { (a: Double, b: Double, c: Double, d: Double) in
            SIMD4<Float>(Float(a), Float(b), Float(c), Float(d)) }
        func pass(_ fragment: String, _ params: [SIMD4<Float>],
                  inputs: [EffectInput] = [.layer(0)]) -> EffectPass {
            EffectPass(fragment: fragment, inputs: inputs, params: params)
        }

        switch kind {
        case let .colorGrade(brightness, contrast, saturation, hue):
            return pass("ollin_fx_color_grade", [f(brightness, contrast, saturation, hue)])
        case .invert(let amount):
            return pass("ollin_fx_invert", [f(amount, 0, 0, 0)])
        case .posterize(let levels):
            return pass("ollin_fx_posterize", [f(levels, 0, 0, 0)])
        case let .threshold(value, softness):
            return pass("ollin_fx_threshold", [f(value, softness, 0, 0)])
        case .sepia(let amount):
            return pass("ollin_fx_sepia", [f(amount, 0, 0, 0)])
        case .colorVision(let vision):
            let m = vision.matrix
            return pass("ollin_fx_color_vision",
                        [f(m[0], m[1], m[2], 0), f(m[3], m[4], m[5], 0), f(m[6], m[7], m[8], 0)])
        case let .duotone(dark, light, amount):
            return pass("ollin_fx_duotone", [f(amount, 0, 0, 0), dark, light])
        case let .gradientMap(lut, amount):
            return pass("ollin_fx_gradient_map", [f(amount, 0, 0, 0)],
                        inputs: [.layer(0), .table(lut)])

        case let .antialias(amount, threshold, quality):
            // The floor under the relative test is half of it. A ratio alone finds
            // "edges" in near-black, where a step of a few thousandths is a large
            // fraction of nothing, so one parameter sets both and they stay in step.
            return pass("ollin_fx_antialias",
                        [SIMD4(texel.x, texel.y, Float(threshold), Float(threshold) * 0.5),
                         SIMD4(Float(amount), Float(EffectQuality.antialiasSteps(resolve(quality))), 0, 0)])
        case .edges(let intensity):
            return pass("ollin_fx_edges", [SIMD4(texel.x, texel.y, Float(intensity), 0)])
        case .sharpen(let amount):
            return pass("ollin_fx_sharpen", [SIMD4(texel.x, texel.y, Float(amount), 0)])
        case let .vignette(amount, radius, softness):
            return pass("ollin_fx_vignette", [SIMD4(Float(amount), Float(radius), Float(softness), aspect)])
        case let .chromaticAberration(amount, mode, spectral, quality):
            // Texture 1 is the per-pixel drive, unused here (the driven flag is 0), so the
            // input stands in for it and the binding stays valid.
            let taps = spectral ? Float(EffectQuality.dispersionTaps(resolve(quality))) : 3
            return pass("ollin_fx_chromatic",
                        [SIMD4(Float(amount), mode.rawIndex, mode.shapeA, mode.shapeB),
                         SIMD4(aspect, taps, 0, 0), texel],
                        inputs: [.layer(0), .layer(0)])
        case let .halftone(scale, angle):
            return pass("ollin_fx_halftone", [SIMD4(Float(scale), Float(angle), aspect, 0)])
        case let .dither(levels, pixelSize):
            return pass("ollin_fx_dither", [f(levels, pixelSize, 0, 0)])
        case let .ditherDuo(dark, light, bias, pixelSize):
            return pass("ollin_fx_dither_duo", [f(bias, pixelSize, 0, 0), dark, light])
        case let .grain(amount, seed):
            return pass("ollin_fx_grain", [f(amount, seed, 0, 0)])
        case let .pixelate(size, channel, tint):
            let cols = max(1, (Double(width) / size).rounded())
            return pass("ollin_fx_pixelate",
                        [SIMD4(Float(cols), aspect, channel.rawIndex, tint == nil ? 0 : 1),
                         tint ?? SIMD4<Float>(repeating: 0)])
        case let .lineScreen(scale, softness, angle, foreground, background):
            return pass("ollin_fx_linescreen",
                        [SIMD4(Float(scale), Float(softness), Float(angle), aspect), foreground, background])

        // Color & tone (continued)
        case let .solarize(value, softness):
            return pass("ollin_fx_solarize", [f(value, softness, 0, 0)])
        case let .temperature(amount, tint):
            return pass("ollin_fx_temperature", [f(amount, tint, 0, 0)])
        case .vibrance(let amount):
            return pass("ollin_fx_vibrance", [f(amount, 0, 0, 0)])
        case .exposure(let gain):
            return pass("ollin_fx_exposure", [f(gain, 0, 0, 0)])
        case let .develop(exposure, ground):
            return pass("ollin_fx_develop", [f(exposure, 0, 0, 0), ground])
        case let .levels(blackPoint, whitePoint, gamma):
            return pass("ollin_fx_levels", [f(blackPoint, whitePoint, gamma, 0)])
        case let .colorama(cycles, shift):
            return pass("ollin_fx_colorama", [f(cycles, shift, 0, 0)])
        case let .lumaKey(low, high, invert):
            return pass("ollin_fx_lumakey", [f(low, high, invert ? 1 : 0, 0)])

        // Blur
        case let .motionBlur(angle, distance):
            return pass("ollin_fx_motion_blur", [f(angle, distance, 0, 0)])
        case .radialBlur(let amount):
            return pass("ollin_fx_radial_blur", [f(amount, 0, 0, 0)])
        case let .bilateral(radius, sigma):
            return pass("ollin_fx_bilateral", [SIMD4(texel.x, texel.y, Float(radius), Float(sigma))])

        // Stylize & optical (continued)
        case let .emboss(amount, angle):
            return pass("ollin_fx_emboss", [SIMD4(texel.x, texel.y, Float(amount), Float(angle))])
        case .oilPaint(let radius):
            return pass("ollin_fx_oilpaint", [SIMD4(texel.x, texel.y, Float(radius), 0)])
        case let .crosshatch(scale, foreground, background):
            return pass("ollin_fx_crosshatch",
                        [SIMD4(Float(scale), aspect, 0, 0), foreground, background])
        case let .toon(levels, edges):
            return pass("ollin_fx_toon", [SIMD4(Float(levels), Float(edges), texel.x, texel.y)])
        case .median:
            return pass("ollin_fx_median", [SIMD4(texel.x, texel.y, 0, 0)])
        case let .contour(levels, intensity):
            return pass("ollin_fx_contour", [f(levels, intensity, 0, 0)])
        case .cmykHalftone(let scale):
            return pass("ollin_fx_cmyk_halftone", [SIMD4(Float(scale), aspect, 0, 0)])
        case .normalMap(let strength):
            return pass("ollin_fx_normal_map", [SIMD4(texel.x, texel.y, Float(strength), 0)])
        case let .relight(finish, angle, elevation, height, intensity, color):
            return pass("ollin_fx_relight",
                        [SIMD4(texel.x, texel.y, Float(height), finish.rawIndex),
                         SIMD4(Float(angle), Float(elevation), Float(intensity),
                               color == nil ? 0 : 1),
                         color ?? SIMD4<Float>(repeating: 0)])
        case let .iridescence(amount, scale, bands, shift):
            return pass("ollin_fx_iridescence",
                        [f(amount, scale, bands, shift), SIMD4(aspect, 0, 0, 0)])
        case let .glitter(density, amount, size, saturation, phase):
            return pass("ollin_fx_glitter",
                        [SIMD4(Float(density), Float(amount), Float(phase), aspect),
                         f(saturation, size, 0, 0)])
        case let .thinFilm(amount, thickness, variation, ior, scale, shift, quality):
            return pass("ollin_fx_thin_film",
                        [f(amount, thickness, variation, ior),
                         SIMD4(Float(scale), Float(shift), aspect, 0)]
                        + SpectralTaps.block(EffectQuality.dispersionTaps(resolve(quality))))
        case let .diffraction(amount, angle, orders, falloff, quality):
            return pass("ollin_fx_diffraction",
                        [f(amount, angle, orders, falloff),
                         SIMD4(aspect, 0, 0, 0)]
                        + SpectralTaps.block(EffectQuality.dispersionTaps(resolve(quality))))

        // Retro / optical
        case let .scanlines(count, intensity):
            return pass("ollin_fx_scanlines", [f(count, intensity, 0, 0)])
        case let .glitch(amount, seed):
            return pass("ollin_fx_glitch", [f(amount, seed, 0, 0)])
        case let .crt(curvature, scanline, aberration):
            return pass("ollin_fx_crt", [f(curvature, scanline, aberration, 0)])

        // Distortion
        case let .kaleidoscope(segments, angle):
            return pass("ollin_fx_kaleidoscope", [SIMD4(Float(segments), Float(angle), aspect, 0)])
        case let .swirl(angle, radius, center):
            return pass("ollin_fx_swirl",
                        [SIMD4(Float(angle), Float(radius), aspect, 0),
                         SIMD4(Float(center.x), Float(center.y), 0, 0)])
        case let .droste(inner, twist, zoom, center, rotation):
            return pass("ollin_fx_droste",
                        [SIMD4(Float(inner), Float(twist), aspect, Float(zoom)),
                         SIMD4(Float(center.x), Float(center.y), Float(rotation), 0)])
        case let .bulge(amount, radius, center):
            return pass("ollin_fx_bulge",
                        [SIMD4(Float(amount), Float(radius), aspect, 0),
                         SIMD4(Float(center.x), Float(center.y), 0, 0)])
        case let .wave(amplitude, frequency, phase, vertical):
            return pass("ollin_fx_wave",
                        [SIMD4(Float(amplitude), Float(frequency), Float(phase), vertical ? 1 : 0)])
        case let .ripple(amplitude, frequency, phase, center):
            return pass("ollin_fx_ripple",
                        [SIMD4(Float(amplitude), Float(frequency), Float(phase), aspect),
                         SIMD4(Float(center.x), Float(center.y), 0, 0)])
        case let .mirror(vertical, flip):
            return pass("ollin_fx_mirror", [SIMD4(vertical ? 1 : 0, flip ? 1 : 0, 0, 0)])
        case .polar(let amount):
            return pass("ollin_fx_polar", [SIMD4(Float(amount), aspect, 0, 0)])
        case let .tile(count, mirror):
            return pass("ollin_fx_tile", [SIMD4(Float(count), mirror ? 1 : 0, 0, 0)])
        case let .perturb(amount, scale, phase):
            return pass("ollin_fx_perturb",
                        [SIMD4(Float(amount), Float(scale), Float(phase), aspect)])

        // Design filters that read the layer alone.
        case let .flutedGlass(flutes, shape, profile, distortion, shift, stretch,
                              blur, edges, highlights, shadows, margins, angle):
            return pass("ollin_fx_fluted_glass",
                        [SIMD4(Float(flutes), aspect, shape.rawIndex, profile.rawIndex),
                         SIMD4(Float(distortion), Float(shift), Float(stretch), Float(blur)),
                         SIMD4(Float(edges), Float(highlights), Float(shadows), Float(angle)),
                         SIMD4(Float(margins.left / Double(width)),
                               Float(margins.right / Double(width)),
                               Float(margins.top / Double(max(1, height))),
                               Float(margins.bottom / Double(max(1, height)))),
                         SIMD4<Float>(1, 1, 1, 1), SIMD4<Float>(0, 0, 0, 1),
                         SIMD4(Float(max(1, height)), 0, 0, 0)])
        case let .water(scale, waves, refraction, layering, edges, highlights, highlight, phase):
            return pass("ollin_fx_water",
                        [SIMD4(Float(scale), Float(waves), Float(refraction), Float(edges)),
                         SIMD4(Float(highlights), Float(phase), aspect, Float(layering)), highlight])
        case let .paperTexture(paper, shading, contrast, roughness, fiber, crumples,
                               folds, drops, seed):
            return pass("ollin_fx_paper_texture",
                        [SIMD4(Float(contrast), Float(roughness), Float(fiber), Float(crumples)),
                         SIMD4(Float(folds), Float(drops), Float(seed), aspect),
                         paper, shading])
        case let .melt(colors, scale, warp, liquify, blend, phase):
            return pass("ollin_fx_melt",
                        [SIMD4(Float(scale), Float(liquify), Float(blend), aspect),
                         SIMD4(Float(warp), Float(phase), 0, 0)] + colors)
        case let .fieldMap(lut, from, to, repeating):
            return pass("ollin_fx_field_map", [f(from, to, repeating ? 1 : 0, 0)],
                        inputs: [.layer(0), .table(lut)])

        // Every pass that is more than one fragment, or reads what a page cannot
        // hold, stays with the renderer.
        case .shader, .gaussianBlur, .bloom, .softProof, .fourier, .inverseFourier, .spectrum,
             .liquidMetal, .heatmap, .gemSmoke, .diffuse, .distanceField, .boxBlur,
             .adaptiveThreshold, .xdog, .brushwork, .shock:
            return nil
        }
    }
}

extension Combine {
    /// The single fragment pass this combine is over its base and aux, or `nil`
    /// for one that takes several.
    func singlePass(width: Int, height: Int,
                    resolve: (RenderQuality) -> RenderQuality) -> EffectPass? {
        func pass(_ fragment: String, _ params: [SIMD4<Float>]) -> EffectPass {
            EffectPass(fragment: fragment, inputs: [.layer(0), .layer(1)], params: params)
        }
        switch kind {
        case let .mask(channel, invert):
            return pass("ollin_fx_mask", [SIMD4(channel.rawIndex, invert ? 1 : 0, 0, 0)])
        case let .displace(amount):
            return pass("ollin_fx_displace", [SIMD4(Float(amount), 0, 0, 0)])
        case let .lineIntegralConvolution(length, field):
            // Half the streak each way, in texels of the base, walked one texel a
            // step up to a fixed cap; past the cap the step grows so a long streak
            // still spans its length at the same cost.
            let half = Float(length) * 0.5 * Float(max(width, height))
            let steps = min(128, max(0, Int(half.rounded())))
            let stepTexels = steps == 0 ? 0 : half / Float(steps)
            return pass("ollin_fx_lic", [SIMD4(1 / Float(width), 1 / Float(height),
                                               Float(steps), stepTexels),
                                         field.row])
        case let .disperse(amount, mode, spectral, quality):
            let taps = spectral ? Float(EffectQuality.dispersionTaps(resolve(quality))) : 3
            let aspect = Float(width) / Float(max(1, height))
            return pass("ollin_fx_chromatic",
                        [SIMD4(Float(amount), mode.rawIndex, mode.shapeA, mode.shapeB),
                         SIMD4(aspect, taps, 1, 0),
                         SIMD4(1 / Float(width), 1 / Float(height), 0, 0)])
        case let .mix(amount):
            return pass("ollin_fx_mix", [SIMD4(Float(amount), 0, 0, 0)])
        case let .paintMix(amount, quality):
            return pass("ollin_fx_paint_mix",
                        [SIMD4(Float(amount), 0, 0, 0)]
                        + SpectralTaps.block(EffectQuality.dispersionTaps(resolve(quality))))
        case .shader, .seamlessClone, .defocus, .ambientOcclusion, .light, .screenSpaceReflections:
            return nil
        }
    }
}

extension Generator {
    /// The fragment pass that fills a layer of `width` by `height` pixels with
    /// this pattern; `nil` for a user shader, which the renderer compiles itself.
    func pass(width: Int, height: Int, scale: Double = 1) -> EffectPass? {
        let aspect = Float(width) / Float(max(1, height))
        func pass(_ fragment: String, _ params: [SIMD4<Float>]) -> EffectPass {
            EffectPass(fragment: fragment, inputs: [], params: params)
        }
        switch kind {
        case .shader:
            return nil
        case let .checkers(scale, fg, bg):
            return pass("ollin_gen_checkers", [SIMD4(Float(scale), aspect, 0, 0), fg, bg])
        case let .gridLines(scale, weight, fg, bg):
            return pass("ollin_gen_grid", [SIMD4(Float(scale), Float(weight), aspect, 0), fg, bg])
        case let .bars(scale, vertical, fg, bg):
            return pass("ollin_gen_bars", [SIMD4(Float(scale), vertical ? 1 : 0, aspect, 0), fg, bg])
        case let .noise(scale, sharpness, warp, fg, bg):
            return pass("ollin_gen_noise",
                        [SIMD4(Float(scale), Float(sharpness), aspect, Float(warp)), fg, bg])
        case let .cellular(scale, jitter, style, fg, bg, phase):
            return pass("ollin_gen_cellular",
                        [SIMD4(Float(scale), Float(jitter), aspect, Float(phase)),
                         SIMD4(style.rawIndex, 0, 0, 0), fg, bg])
        case let .gaborNoise(wavelength, bandwidth, angle, spread, impulses, phase, seed, fg, bg):
            // Measured in pixels, so the wavelength scales with the layer (a
            // 2x export keeps the picture) and the CPU form reads the same
            // field at the same point. The seed rides as a plain integer in a
            // float (24 bits is every seed a sketch hands out).
            return pass("ollin_gen_gabor",
                        [SIMD4(Float(wavelength * scale), Float(bandwidth), Float(angle), Float(spread)),
                         SIMD4(Float(impulses), Float(phase), Float(GaborNoise.seedBits(seed)), 0),
                         SIMD4(Float(width), Float(height), 0, 0), fg, bg])

        // Design patterns. Each packs its scalars into leading rows and appends
        // the palette as trailing color rows the fragment indexes past them.
        case let .meshGradient(colors, distortion, swirl, mixing, grain, phase):
            // The blend parameter maps to the inverse-distance power piecewise so the
            // 0.5 default is *exactly* the classic 3.5 (snapshot-pinned): 0 is a
            // hard near-Voronoi 16, 1 a buttery 1.
            let power = mixing <= 0.5 ? 16.0 - (16.0 - 3.5) * (mixing * 2)
                                      : 3.5 - 2.5 * ((mixing - 0.5) * 2)
            return pass("ollin_gen_mesh_gradient",
                        [SIMD4(Float(colors.count), aspect, Float(distortion), Float(swirl)),
                         SIMD4(Float(grain), Float(phase), Float(power), 0)] + colors)
        case let .filaments(color, highlight, background, scale, brightness, contrast, phase):
            return pass("ollin_gen_filaments",
                        [SIMD4(Float(scale), aspect, Float(brightness), Float(contrast)),
                         SIMD4(Float(phase), 0, 0, 0),
                         color, highlight, background])
        case let .smokeRing(colors, background, radius, thickness, fill, scale, detail, phase):
            return pass("ollin_gen_smoke_ring",
                        [SIMD4(Float(colors.count), aspect, Float(radius), Float(thickness)),
                         SIMD4(Float(fill), Float(scale), Float(detail), Float(phase)),
                         background] + colors)
        case let .colorPanels(colors, background, density, length, skew, blur,
                              fadeIn, fadeOut, gradient, phase):
            // Panels tile the palette an even number of times (at least 12 panes) so
            // the two mirrored half-phase sets stay color-aligned across the wrap.
            var panels = 12
            while panels % colors.count != 0 || (panels / colors.count) % 2 != 0 { panels += 1 }
            return pass("ollin_gen_color_panels",
                        [SIMD4(Float(colors.count), aspect, Float(density), Float(length)),
                         SIMD4(Float(skew), Float(blur), Float(gradient), Float(phase)),
                         SIMD4(Float(fadeIn), Float(fadeOut), Float(panels),
                               Float(panels) / 12),
                         background] + colors)
        case let .spiral(foreground, background, density, distortion, strokeWidth,
                         taper, cap, noise, noiseScale, softness, scale, phase):
            return pass("ollin_gen_spiral",
                        [SIMD4(aspect, Float(density), Float(distortion), Float(strokeWidth)),
                         SIMD4(Float(taper), Float(cap), Float(noise), Float(noiseScale)),
                         SIMD4(Float(softness), Float(scale), Float(phase), 0),
                         foreground, background])
        case let .waves(foreground, background, shape, frequency, amplitude,
                        spacing, proportion, softness, scale, phase):
            return pass("ollin_gen_waves",
                        [SIMD4(aspect, Float(shape), Float(frequency), Float(amplitude)),
                         SIMD4(Float(spacing), Float(proportion), Float(softness), Float(scale)),
                         SIMD4(Float(phase), 0, 0, 0),
                         foreground, background])
        case let .dotOrbit(colors, background, scale, size, sizeVariation, spread, steps, phase):
            return pass("ollin_gen_dot_orbit",
                        [SIMD4(Float(colors.count), aspect, Float(scale), Float(size)),
                         SIMD4(Float(sizeVariation), Float(spread), Float(steps), Float(phase)),
                         background] + colors)
        case let .grainGradient(colors, background, shape, softness, intensity, noise, phase):
            return pass("ollin_gen_grain_gradient",
                        [SIMD4(Float(colors.count), aspect, shape.rawIndex, Float(softness)),
                         SIMD4(Float(intensity), Float(noise), Float(phase),
                               Float(max(1, height))),
                         background] + colors)
        case let .pulsingBorder(colors, background, roundness, thickness, softness, intensity,
                                bloom, spots, spotSize, pulse, smoke, smokeScale, margins, phase):
            // Margins arrive in layer pixels; the border lives in centered
            // square units, so convert per side.
            let unit = Double(min(aspect, 1))
            let mL = margins.left / Double(width) * Double(aspect) / unit
            let mR = margins.right / Double(width) * Double(aspect) / unit
            let mT = margins.top / Double(max(1, height)) / unit
            let mB = margins.bottom / Double(max(1, height)) / unit
            return pass("ollin_gen_pulsing_border",
                        [SIMD4(Float(colors.count), aspect, Float(roundness), Float(thickness)),
                         SIMD4(Float(softness), Float(intensity), Float(bloom), Float(spots)),
                         SIMD4(Float(spotSize), Float(pulse), Float(smoke), Float(smokeScale)),
                         SIMD4(Float(phase), Float(mL), Float(mR), Float(mT)),
                         SIMD4(Float(mB), 0, 0, 0),
                         background] + colors)
        case let .godRays(colors, background, x, y, density, breakup, coreSize,
                          coreIntensity, intensity, bloom, bloomTint, phase):
            return pass("ollin_gen_god_rays",
                        [SIMD4(Float(colors.count), aspect, Float(x), Float(y)),
                         SIMD4(Float(density), Float(breakup), Float(coreSize),
                               Float(coreIntensity)),
                         SIMD4(Float(intensity), Float(bloom), Float(phase), 0),
                         bloomTint, background] + colors)

        // Pattern fields: scalars in the leading rows, background at params[2],
        // the palette (where one applies) as trailing rows.
        case let .quasicrystal(colors, background, symmetry, scale, contrast, phase):
            return pass("ollin_gen_quasicrystal",
                        [SIMD4(Float(colors.count), aspect, Float(symmetry), Float(scale)),
                         SIMD4(Float(contrast), Float(phase), 0, 0),
                         background] + colors)
        case let .moire(foreground, background, sources, frequency, scale, phase):
            return pass("ollin_gen_moire",
                        [SIMD4(aspect, Float(sources), Float(frequency), Float(scale)),
                         SIMD4(Float(phase), 0, 0, 0),
                         foreground, background])
        case let .gyroid(foreground, background, scale, thickness, phase):
            return pass("ollin_gen_gyroid",
                        [SIMD4(aspect, Float(scale), Float(thickness), Float(phase)),
                         foreground, background])
        case let .phyllotaxis(colors, background, count, dotSize, phase):
            return pass("ollin_gen_phyllotaxis",
                        [SIMD4(Float(colors.count), aspect, Float(count), Float(dotSize)),
                         SIMD4(Float(phase), 0, 0, 0),
                         background] + colors)
        case let .hexPulse(colors, background, scale, gap, phase):
            return pass("ollin_gen_hexpulse",
                        [SIMD4(Float(colors.count), aspect, Float(scale), Float(gap)),
                         SIMD4(Float(phase), 0, 0, 0),
                         background] + colors)
        case let .chladni(m, n, style, weight, grain, foreground, background, scale, phase):
            return pass("ollin_gen_chladni",
                        [SIMD4(aspect, Float(m), Float(n), Float(scale)),
                         SIMD4(style.rawIndex, Float(weight), Float(grain), Float(phase)),
                         foreground, background])
        case let .escapeTime(colors, interior, mode, c, center, zoom, iterations, cycles, phase):
            return pass("ollin_gen_escape",
                        [SIMD4(Float(colors.count), aspect, Float(mode), Float(iterations)),
                         SIMD4(Float(center.x), Float(center.y), Float(zoom), Float(cycles)),
                         SIMD4(Float(c.x), Float(c.y), Float(phase), 0),
                         interior] + colors)
        case let .orbitTrap(colors, trap, mode, c, center, zoom, iterations, glow, angle):
            return pass("ollin_gen_orbittrap",
                        [SIMD4(Float(colors.count), aspect, Float(mode), Float(iterations)),
                         SIMD4(Float(center.x), Float(center.y), Float(zoom), Float(glow)),
                         SIMD4(Float(c.x), Float(c.y), trap.rawIndex, Float(angle)),
                         SIMD4(Float(trap.trapCenter.x), Float(trap.trapCenter.y),
                               Float(trap.trapRadius), 0)] + colors)
        case let .domainColoring(colors, mode, exponent, zeros, poles, shading,
                                 strength, center, zoom, phase):
            return pass("ollin_gen_domain",
                        [SIMD4(Float(colors.count), aspect, Float(mode), shading.rawIndex),
                         SIMD4(Float(center.x), Float(center.y), Float(zoom), Float(phase)),
                         SIMD4(Float(strength), Float(exponent),
                               Float(zeros.count), Float(poles.count))]
                        + EffectPass.pointPairRows(zeros) + EffectPass.pointPairRows(poles) + colors)
        case let .newton(colors, trapped, roots, shading, relaxation, center, zoom,
                         iterations, phase):
            return pass("ollin_gen_newton",
                        [SIMD4(Float(colors.count), aspect, Float(roots.count), Float(iterations)),
                         SIMD4(Float(center.x), Float(center.y), Float(zoom), Float(phase)),
                         SIMD4(Float(shading), Float(relaxation), 0, 0),
                         trapped] + EffectPass.pointPairRows(roots, capacity: 8) + colors)
        }
    }
}

extension EffectPass {
    /// Up to `capacity` points packed two to a row, zero where fewer were given.
    static func pointPairRows(_ points: [Vector2], capacity: Int = 4) -> [SIMD4<Float>] {
        stride(from: 0, to: capacity, by: 2).map { i in
            let a = i < points.count ? points[i] : Vector2.zero
            let b = i + 1 < points.count ? points[i + 1] : Vector2.zero
            return SIMD4(Float(a.x), Float(a.y), Float(b.x), Float(b.y))
        }
    }
}
