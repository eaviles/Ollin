// MetalRenderer, the layered-effects half: resolving the deferred effect graph
// (render targets, filters, generators, combines, feedback, and sim fields) at
// render time, entirely GPU-resident. One extension of the renderer; the stored
// state it drives lives with the type in MetalRenderer.swift.

import Foundation
import Metal
import MetalKit
import simd
import CoreGraphics
import COllinShaders
import MetalPerformanceShaders   // tuned image kernels (Gaussian blur) behind the effect filters

extension MetalRenderer {
    // MARK: Layered effects (render targets + filters)

    /// The frame's geometry buffers, bundled so the effect-target passes and the
    /// main pass draw from the same uploads.
    struct GeometryBuffers {
        var triangle: MTLBuffer?
        var sdf: MTLBuffer?
        var image: MTLBuffer?
        var glyph: MTLBuffer?
        var point: MTLBuffer?
        var mesh: MTLBuffer?
        var sdfGroup: MTLBuffer?
        var sdfNode: MTLBuffer?
        var sdf3DGroup: MTLBuffer?
        var sdf3DNode: MTLBuffer?
    }

    /// Fill every effects layer this frame, ahead of the main pass: render each
    /// geometry target's tagged batches into its own texture, then run each filter
    /// op into its output texture. Each layer ends with `texture` set, so the main
    /// pass (and later filters) can sample it. A no-op when the frame used no
    /// targets, so the ordinary path is byte-identical. `pooled` reuses per-frame
    /// textures on the live ring; the headless paths allocate fresh and wait.
    func encodeEffectTargets(_ drawer: Drawer, into cb: MTLCommandBuffer,
                                     buffers: GeometryBuffers, pooled: Bool) {
        // Reset the user-shader error state for this frame; any failing shader below
        // sets it, and the host reads it afterward to drive the error overlay.
        currentUserShaderError = nil
        frameComputeUniforms = drawer.computeUniforms   // for user-shader ShaderInfo
        // Frame-scoped state, reset before the no-targets early-out: the deferred
        // reflection pass acquires from the same pool and reads the same repeat stamp
        // on frames that use no effect layers, so gating these on effects work would
        // grow the pool by one texture per frame (and leave the stamp stale) in a
        // reflections-only sketch.
        targetTexNext = 0
        filterTexNext = 0
        targetDepthNext = 0
        ssrOccurrenceThisFrame.removeAll(keepingCapacity: true)
        // A second encode of the same sketch frame (the frame-grab / Syphon off-screen
        // re-render) must not advance persistent state twice; see `lastStatefulEncode`.
        let stamp = (drawer: ObjectIdentifier(drawer), frame: drawer.computeUniforms.frameCount)
        statefulEncodeIsRepeat = lastStatefulEncode?.drawer == stamp.drawer
            && lastStatefulEncode?.frame == stamp.frame
        if !statefulEncodeIsRepeat { lastStatefulEncode = stamp }
        guard !drawer.renderTargets.isEmpty || !drawer.filterOps.isEmpty
            || !drawer.frameFilters.isEmpty else { return }
        // Generators read no input, so fill them first (a filter may sample one),
        // each a single fullscreen fragment pass into a sampleable filter texture.
        for target in drawer.renderTargets {
            guard case let .generator(generator) = target.origin else { continue }
            guard let out = acquireFilterTexture(width: target.pixelWidth,
                                                 height: target.pixelHeight, pooled: pooled) else { continue }
            encodeGenerator(generator, output: out,
                            width: target.pixelWidth, height: target.pixelHeight, into: cb)
            target.texture = out
        }
        for target in drawer.renderTargets {
            guard case .geometry = target.origin else { continue }
            let pw = target.pixelWidth, ph = target.pixelHeight
            guard let tex = acquireTargetTextures(width: pw, height: ph, pooled: pooled) else { continue }
            let pass = MTLRenderPassDescriptor()
            pass.colorAttachments[0].texture = tex.msaa
            pass.colorAttachments[0].resolveTexture = tex.resolve
            pass.colorAttachments[0].loadAction = .clear
            pass.colorAttachments[0].clearColor = target.clearColor.mtlClearColor
            pass.colorAttachments[0].storeAction = .multisampleResolve
            // A target that holds a 3D scene carries a depth attachment so its meshes
            // z-test (and so the `depth` layer can read it). The MSAA depth resolves
            // (nearest sample) into a sampleable single-sample buffer; a 2D target
            // takes none of this, so its pass is byte-identical to before.
            var depthResolve: MTLTexture? = nil
            if target.needsDepth, let depth = acquireTargetDepth(width: pw, height: ph, pooled: pooled) {
                pass.depthAttachment.texture = depth.msaa
                pass.depthAttachment.resolveTexture = depth.resolve
                pass.depthAttachment.loadAction = .clear
                pass.depthAttachment.clearDepth = 1.0
                pass.depthAttachment.storeAction = .multisampleResolve
                pass.depthAttachment.depthResolveFilter = .min
                depthResolve = depth.resolve
            }
            // A clip pushed inside this layer gives its pass a stencil attachment.
            let passHasStencil = attachClipStencil(to: pass, active: target.needsStencil,
                                                   width: pw, height: ph)
            guard let enc = cb.makeRenderCommandEncoder(descriptor: pass) else { continue }
            // Geometry inside the block used canvas coordinates, so map by the logical
            // size; a fraction-res layer's smaller attachment just downsamples.
            encode(drawer, viewport: SIMD2(Float(target.width), Float(target.height)), into: enc,
                   triangleBuffer: buffers.triangle, sdfBuffer: buffers.sdf, imageBuffer: buffers.image,
                   glyphBuffer: buffers.glyph, pointBuffer: buffers.point, meshBuffer: buffers.mesh,
                   sdfGroupBuffer: buffers.sdfGroup, sdfNodeBuffer: buffers.sdfNode,
                   sdf3DGroupBuffer: buffers.sdf3DGroup, sdf3DNodeBuffer: buffers.sdf3DNode,
                   depthFormat: depthResolve != nil ? depthPixelFormat : nil,
                   stencil: passHasStencil, target: target)
            enc.endEncoding()
            target.texture = tex.resolve
            // Expose the scene's depth as a gray layer when the sketch read `.depth`:
            // linearize the clip-space depth over the camera's near/far into 0…1,
            // encoded so the existing perceptual DoF decode recovers it exactly. Only
            // run when the layer was actually accessed: a 3D target you don't defocus
            // pays only for its own occlusion above, not this pass.
            if let depthResolve, let depthLayer = target.depthLayer {
                depthLayer.texture = normalizeDepth(depthResolve, camera: drawer.camera3D,
                                                    width: pw, height: ph, into: cb, pooled: pooled)
                // Stamp the camera geometry on the depth layer so a combine that
                // reconstructs view-space position from it (ambient occlusion) can.
                if let cam = drawer.camera3D {
                    depthLayer.depthReconstruction = DepthReconstruction(camera: cam,
                                                                         pixelWidth: pw, pixelHeight: ph)
                }
            }
            // The mesh-normal G-buffer, when this 3D target feeds an ambient-occlusion
            // combine: a dedicated single-sample mesh pass so SSAO occludes against a true
            // surface normal rather than one reconstructed from depth. Gated on
            // `needsNormals` (set when an `.ambientOcclusion` combine reads a 3D target), so
            // a target that doesn't run AO never encodes it and stays byte-identical. The
            // `normals` accessor instantiates the layer here (the sketch never names it, so
            // unlike `depth` nothing else creates it); the combine then reads its texture.
            if target.needsNormals {
                target.normals.texture = encodeMeshNormals(drawer, for: target, into: cb,
                                                           meshBuffer: buffers.mesh,
                                                           width: pw, height: ph, pooled: pooled)
            }
        }
        // Feedback layers: like a geometry target, but rendered into persistent
        // ping-pong storage. The block reads the *front* (last frame, exposed as
        // `previous`) while drawing into the *back*; the pair flips after the frame.
        for target in drawer.renderTargets {
            guard case let .feedback(fb) = target.origin else { continue }
            let pw = target.pixelWidth, ph = target.pixelHeight
            guard let slot = feedbackSlot(for: fb, width: pw, height: ph, into: cb),
                  let msaa = makeFloatMSAA(width: pw, height: ph, storage: .memoryless) else { continue }
            let front = slot.flipped ? slot.b : slot.a
            let back  = slot.flipped ? slot.a : slot.b
            if statefulEncodeIsRepeat {
                // This frame's first encode already rendered into what is now the
                // front and flipped the pair. Re-rendering would read this frame's
                // own result as `previous` (one step ahead); serve the existing
                // textures instead, with no second flip.
                fb.previousLayer.texture = back  // what the first encode read
                target.texture = front           // what the first encode produced
                continue
            }
            fb.previousLayer.texture = front     // `previous` resolves to last frame
            let pass = MTLRenderPassDescriptor()
            pass.colorAttachments[0].texture = msaa
            pass.colorAttachments[0].resolveTexture = back
            pass.colorAttachments[0].loadAction = .clear
            pass.colorAttachments[0].clearColor = target.clearColor.mtlClearColor
            pass.colorAttachments[0].storeAction = .multisampleResolve
            let passHasStencil = attachClipStencil(to: pass, active: target.needsStencil,
                                                   width: pw, height: ph)
            guard let enc = cb.makeRenderCommandEncoder(descriptor: pass) else { continue }
            encode(drawer, viewport: SIMD2(Float(target.width), Float(target.height)), into: enc,
                   triangleBuffer: buffers.triangle, sdfBuffer: buffers.sdf, imageBuffer: buffers.image,
                   glyphBuffer: buffers.glyph, pointBuffer: buffers.point, meshBuffer: buffers.mesh,
                   sdfGroupBuffer: buffers.sdfGroup, sdfNodeBuffer: buffers.sdfNode,
                   sdf3DGroupBuffer: buffers.sdf3DGroup, sdf3DNodeBuffer: buffers.sdf3DNode,
                   depthFormat: nil, stencil: passHasStencil, target: target)
            enc.endEncoding()
            target.texture = back                // `image` resolves to this frame
            feedbackUsedThisFrame.insert(ObjectIdentifier(fb))
        }
        // Simulation fields: a persistent ping-pong like feedback, but the renderer
        // evolves the state itself. Render this frame's drawn seeds into a transient
        // texture, then run the field's `Sim` (inject the seeds onto the front state,
        // step it N times) writing the result into the back buffer.
        for target in drawer.renderTargets {
            guard case let .simField(sf) = target.origin else { continue }
            let pw = target.pixelWidth, ph = target.pixelHeight
            if statefulEncodeIsRepeat {
                // The sim already stepped (and flipped) for this frame; re-stepping
                // would run it at 2x speed while recording. Serve the stepped state.
                if sf.sim.fluidConfig != nil {
                    if let slot = fluidSlot(for: sf, width: pw, height: ph, into: cb) {
                        target.texture = slot.flipped ? slot.dyeB : slot.dyeA
                    }
                } else if let slot = feedbackSlot(for: sf, width: pw, height: ph,
                                                  fill: turingNoiseFill(sf.sim, into: cb),
                                                  into: cb) {
                    target.texture = slot.flipped ? slot.b : slot.a
                }
                continue
            }
            guard let msaa = makeFloatMSAA(width: pw, height: ph, storage: .memoryless),
                  let seed = acquireFilterTexture(width: pw, height: ph, pooled: pooled) else { continue }
            // Render this frame's drawn seed marks into `seed` (cleared transparent so
            // an empty block seeds nothing and the field just evolves). Shared by both
            // the single-field sims and the fluid.
            let pass = MTLRenderPassDescriptor()
            pass.colorAttachments[0].texture = msaa
            pass.colorAttachments[0].resolveTexture = seed
            pass.colorAttachments[0].loadAction = .clear
            pass.colorAttachments[0].clearColor = target.clearColor.mtlClearColor
            pass.colorAttachments[0].storeAction = .multisampleResolve
            let passHasStencil = attachClipStencil(to: pass, active: target.needsStencil,
                                                   width: pw, height: ph)
            if let enc = cb.makeRenderCommandEncoder(descriptor: pass) {
                encode(drawer, viewport: SIMD2(Float(target.width), Float(target.height)), into: enc,
                       triangleBuffer: buffers.triangle, sdfBuffer: buffers.sdf, imageBuffer: buffers.image,
                       glyphBuffer: buffers.glyph, pointBuffer: buffers.point, meshBuffer: buffers.mesh,
                   sdfGroupBuffer: buffers.sdfGroup, sdfNodeBuffer: buffers.sdfNode,
                   sdf3DGroupBuffer: buffers.sdf3DGroup, sdf3DNodeBuffer: buffers.sdf3DNode,
                       depthFormat: nil, stencil: passHasStencil, target: target)
                enc.endEncoding()
            }
            if let config = sf.sim.fluidConfig {
                // Multi-field fluid: its own persistent velocity + dye pairs, evolved by
                // the dedicated solver. `image` resolves to the freshly advected dye.
                guard let slot = fluidSlot(for: sf, width: pw, height: ph, into: cb) else { continue }
                let velFront = slot.flipped ? slot.velB : slot.velA
                let velBack  = slot.flipped ? slot.velA : slot.velB
                let dyeFront = slot.flipped ? slot.dyeB : slot.dyeA
                let dyeBack  = slot.flipped ? slot.dyeA : slot.dyeB
                runFluid(config, force: sf.seedForce, seed: seed,
                         velFront: velFront, velBack: velBack, dyeFront: dyeFront, dyeBack: dyeBack,
                         width: pw, height: ph, into: cb, pooled: pooled)
                target.texture = dyeBack
                fluidUsedThisFrame.insert(ObjectIdentifier(sf))
            } else {
                // Single-field sim (reaction-diffusion, Game of Life, multi-scale Turing):
                // one ping-pong pair. Turing steps through its own multi-pass pipeline,
                // since one step needs a blur pyramid and a whole-field extent first, but
                // its storage is the same single pair, so it shares the slot, the flip,
                // and the repeat arm above.
                let rest = sf.sim.restState
                guard let slot = feedbackSlot(for: sf, width: pw, height: ph,
                                              restState: MTLClearColor(red: Double(rest.x), green: Double(rest.y),
                                                                       blue: Double(rest.z), alpha: Double(rest.w)),
                                              fill: turingNoiseFill(sf.sim, into: cb),
                                              into: cb) else { continue }
                let front = slot.flipped ? slot.b : slot.a
                let back  = slot.flipped ? slot.a : slot.b
                if let turing = sf.sim.turingConfig {
                    runMultiScaleTuring(turing.scales, state: front, seed: seed, output: back,
                                        width: pw, height: ph, into: cb, pooled: pooled)
                } else {
                    runSimulation(sf.sim, state: front, seed: seed, output: back,
                                  width: pw, height: ph, into: cb, pooled: pooled)
                }
                target.texture = back
                feedbackUsedThisFrame.insert(ObjectIdentifier(sf))
            }
        }
        // Filter and combine ops share one list, resolved in record order so an op's
        // inputs (filled earlier in this loop, or by the geometry/generator passes
        // above) are ready before it runs.
        for output in drawer.filterOps {
            switch output.origin {
            case let .filter(input, filter):
                guard let src = input.texture else { continue }
                output.texture = applyFilter(filter, input: src,
                                             width: output.pixelWidth, height: output.pixelHeight,
                                             into: cb, pooled: pooled)
            case let .combine(base, aux, op):
                guard let b = base.texture, let a = aux.texture else { continue }
                // Ambient occlusion reads the base's mesh-normal G-buffer when it was
                // captured (a 3D base feeding AO); nil otherwise → the shader's
                // depth-reconstruction fallback.
                output.texture = applyCombine(op, base: b, aux: a, depth: aux.depthReconstruction,
                                              normals: base.normalLayer?.texture,
                                              width: output.pixelWidth, height: output.pixelHeight,
                                              into: cb, pooled: pooled)
            default:
                continue
            }
        }
        // Advance each feedback layer drawn this frame (its back becomes next frame's
        // front), then prune slots whose owner the sketch has released (live reload,
        // or a layer no longer held) so the map stays bounded.
        for id in feedbackUsedThisFrame { feedbackSlots[id]?.flipped.toggle() }
        feedbackUsedThisFrame.removeAll(keepingCapacity: true)
        if feedbackSlots.contains(where: { $0.value.owner == nil }) {
            feedbackSlots = feedbackSlots.filter { $0.value.owner != nil }
        }
        for id in fluidUsedThisFrame { fluidSlots[id]?.flipped.toggle() }
        fluidUsedThisFrame.removeAll(keepingCapacity: true)
        if fluidSlots.contains(where: { $0.value.owner == nil }) {
            fluidSlots = fluidSlots.filter { $0.value.owner != nil }
        }
        // Advance each SSR temporal history drawn this frame (its back becomes next frame's
        // front). Slots aren't pruned here (`ssrHistorySlot` bounds the map on allocation),
        // so a skipped SSR frame keeps its accumulation.
        for id in ssrHistoryUsedThisFrame { ssrHistorySlots[id]?.flipped.toggle() }
        ssrHistoryUsedThisFrame.removeAll(keepingCapacity: true)
    }

    /// Apply the whole-frame `postProcess` filters to the resolved float frame,
    /// returning the texture to present (the input itself when there are none).
    func applyFrameFilters(_ drawer: Drawer, resolved: MTLTexture,
                                   width: Int, height: Int, into cb: MTLCommandBuffer,
                                   pooled: Bool) -> MTLTexture {
        var current = resolved
        for filter in drawer.frameFilters {
            if let out = applyFilter(filter, input: current, width: width, height: height,
                                     into: cb, pooled: pooled) {
                current = out
            }
        }
        return current
    }

    /// Run one `filter` from `input` into a freshly acquired output texture. Blur is
    /// a hardware MPS kernel and bloom a bright-pass + blur + add-back chain; the rest
    /// are single fullscreen fragment passes, each reading premultiplied-linear input
    /// and writing the same. `f` is the float vector of the type's parameters.
    private func applyFilter(_ filter: Filter, input: MTLTexture, width: Int, height: Int,
                             into cb: MTLCommandBuffer, pooled: Bool) -> MTLTexture? {
        // One fragment pass into a fresh output texture (the common shape).
        func pass(_ fragment: String, _ inputs: [MTLTexture], _ params: [SIMD4<Float>]) -> MTLTexture? {
            guard let output = acquireFilterTexture(width: width, height: height, pooled: pooled) else { return nil }
            encodeEffectFragment(fragment, inputs: inputs, output: output, params: params, into: cb)
            return output
        }
        let texel = SIMD4<Float>(1 / Float(width), 1 / Float(height), 0, 0)
        let aspect = Float(width) / Float(max(1, height))
        let f = { (a: Double, b: Double, c: Double, d: Double) in
            SIMD4<Float>(Float(a), Float(b), Float(c), Float(d)) }

        switch filter.kind {
        case let .shader(shader):
            guard let output = acquireFilterTexture(width: width, height: height, pooled: pooled) else { return nil }
            encodeUserShader(shader, variant: .filter, inputs: [input], output: output,
                             width: width, height: height, into: cb)
            return output
        case .gaussianBlur(let radius):
            guard let output = acquireFilterTexture(width: width, height: height, pooled: pooled) else { return nil }
            let blur = MPSImageGaussianBlur(device: device, sigma: Float(max(0.1, radius)))
            blur.edgeMode = .clamp
            blur.encode(commandBuffer: cb, sourceTexture: input, destinationTexture: output)
            return output
        case .bloom(let threshold, let intensity, let radius):
            guard let bright = acquireFilterTexture(width: width, height: height, pooled: pooled),
                  let blurred = acquireFilterTexture(width: width, height: height, pooled: pooled),
                  let output = acquireFilterTexture(width: width, height: height, pooled: pooled) else { return nil }
            // Bright-pass → blur → add the glow back onto the original.
            encodeEffectFragment("ollin_fx_brightpass", inputs: [input], output: bright,
                                 params: [f(threshold, 0, 0, 0)], into: cb)
            let blur = MPSImageGaussianBlur(device: device, sigma: Float(max(0.1, radius)))
            blur.edgeMode = .clamp
            blur.encode(commandBuffer: cb, sourceTexture: bright, destinationTexture: blurred)
            encodeEffectFragment("ollin_fx_bloom_combine", inputs: [input, blurred], output: output,
                                 params: [f(intensity, 0, 0, 0)], into: cb)
            return output

        case let .colorGrade(brightness, contrast, saturation, hue):
            return pass("ollin_fx_color_grade", [input], [f(brightness, contrast, saturation, hue)])
        case .invert(let amount):
            return pass("ollin_fx_invert", [input], [f(amount, 0, 0, 0)])
        case .posterize(let levels):
            return pass("ollin_fx_posterize", [input], [f(levels, 0, 0, 0)])
        case let .threshold(value, softness):
            return pass("ollin_fx_threshold", [input], [f(value, softness, 0, 0)])
        case .sepia(let amount):
            return pass("ollin_fx_sepia", [input], [f(amount, 0, 0, 0)])
        case let .duotone(dark, light, amount):
            return pass("ollin_fx_duotone", [input], [f(amount, 0, 0, 0), dark, light])
        case let .gradientMap(lut, amount):
            guard let lutTex = makeLUTTexture(lut) else { return nil }
            return pass("ollin_fx_gradient_map", [input, lutTex], [f(amount, 0, 0, 0)])

        case .edges(let intensity):
            return pass("ollin_fx_edges", [input], [SIMD4(texel.x, texel.y, Float(intensity), 0)])
        case .sharpen(let amount):
            return pass("ollin_fx_sharpen", [input], [SIMD4(texel.x, texel.y, Float(amount), 0)])
        case let .vignette(amount, radius, softness):
            return pass("ollin_fx_vignette", [input], [SIMD4(Float(amount), Float(radius), Float(softness), aspect)])
        case .chromaticAberration(let amount):
            return pass("ollin_fx_chromatic", [input], [f(amount, 0, 0, 0)])
        case let .halftone(scale, angle):
            return pass("ollin_fx_halftone", [input], [SIMD4(Float(scale), Float(angle), aspect, 0)])
        case let .dither(levels, pixelSize):
            return pass("ollin_fx_dither", [input], [f(levels, pixelSize, 0, 0)])
        case let .ditherDuo(dark, light, bias, pixelSize):
            return pass("ollin_fx_dither_duo", [input], [f(bias, pixelSize, 0, 0), dark, light])
        case let .grain(amount, seed):
            return pass("ollin_fx_grain", [input], [f(amount, seed, 0, 0)])
        case let .pixelate(size, channel, tint):
            let cols = max(1, (Double(width) / size).rounded())
            return pass("ollin_fx_pixelate", [input],
                        [SIMD4(Float(cols), aspect, channel.rawIndex, tint == nil ? 0 : 1),
                         tint ?? SIMD4<Float>(repeating: 0)])
        case let .lineScreen(scale, softness, angle, foreground, background):
            return pass("ollin_fx_linescreen", [input],
                        [SIMD4(Float(scale), Float(softness), Float(angle), aspect), foreground, background])

        // Color & tone (continued)
        case let .solarize(value, softness):
            return pass("ollin_fx_solarize", [input], [f(value, softness, 0, 0)])
        case let .temperature(amount, tint):
            return pass("ollin_fx_temperature", [input], [f(amount, tint, 0, 0)])
        case .vibrance(let amount):
            return pass("ollin_fx_vibrance", [input], [f(amount, 0, 0, 0)])
        case .exposure(let gain):
            return pass("ollin_fx_exposure", [input], [f(gain, 0, 0, 0)])
        case let .levels(blackPoint, whitePoint, gamma):
            return pass("ollin_fx_levels", [input], [f(blackPoint, whitePoint, gamma, 0)])
        case let .colorama(cycles, shift):
            return pass("ollin_fx_colorama", [input], [f(cycles, shift, 0, 0)])
        case let .lumaKey(low, high, invert):
            return pass("ollin_fx_lumakey", [input], [f(low, high, invert ? 1 : 0, 0)])

        // Blur
        case let .motionBlur(angle, distance):
            return pass("ollin_fx_motion_blur", [input], [f(angle, distance, 0, 0)])
        case .radialBlur(let amount):
            return pass("ollin_fx_radial_blur", [input], [f(amount, 0, 0, 0)])
        case let .bilateral(radius, sigma):
            return pass("ollin_fx_bilateral", [input], [SIMD4(texel.x, texel.y, Float(radius), Float(sigma))])

        // Stylize & optical (continued)
        case let .emboss(amount, angle):
            return pass("ollin_fx_emboss", [input], [SIMD4(texel.x, texel.y, Float(amount), Float(angle))])
        case .oilPaint(let radius):
            return pass("ollin_fx_oilpaint", [input], [SIMD4(texel.x, texel.y, Float(radius), 0)])
        case let .crosshatch(scale, foreground, background):
            return pass("ollin_fx_crosshatch", [input],
                        [SIMD4(Float(scale), aspect, 0, 0), foreground, background])
        case let .toon(levels, edges):
            return pass("ollin_fx_toon", [input], [SIMD4(Float(levels), Float(edges), texel.x, texel.y)])
        case .median:
            return pass("ollin_fx_median", [input], [SIMD4(texel.x, texel.y, 0, 0)])
        case let .contour(levels, intensity):
            return pass("ollin_fx_contour", [input], [f(levels, intensity, 0, 0)])
        case .cmykHalftone(let scale):
            return pass("ollin_fx_cmyk_halftone", [input], [SIMD4(Float(scale), aspect, 0, 0)])
        case .normalMap(let strength):
            return pass("ollin_fx_normal_map", [input], [SIMD4(texel.x, texel.y, Float(strength), 0)])
        case let .relight(finish, angle, elevation, height, intensity, color):
            return pass("ollin_fx_relight", [input],
                        [SIMD4(texel.x, texel.y, Float(height), finish.rawIndex),
                         SIMD4(Float(angle), Float(elevation), Float(intensity),
                               color == nil ? 0 : 1),
                         color ?? SIMD4<Float>(repeating: 0)])
        case let .iridescence(amount, scale, bands, shift):
            return pass("ollin_fx_iridescence", [input],
                        [f(amount, scale, bands, shift), SIMD4(aspect, 0, 0, 0)])
        case let .glitter(density, amount, size, saturation, phase):
            return pass("ollin_fx_glitter", [input],
                        [SIMD4(Float(density), Float(amount), Float(phase), aspect),
                         f(saturation, size, 0, 0)])

        // Retro / optical
        case let .scanlines(count, intensity):
            return pass("ollin_fx_scanlines", [input], [f(count, intensity, 0, 0)])
        case let .glitch(amount, seed):
            return pass("ollin_fx_glitch", [input], [f(amount, seed, 0, 0)])
        case let .crt(curvature, scanline, aberration):
            return pass("ollin_fx_crt", [input], [f(curvature, scanline, aberration, 0)])

        // Distortion
        case let .kaleidoscope(segments, angle):
            return pass("ollin_fx_kaleidoscope", [input], [SIMD4(Float(segments), Float(angle), aspect, 0)])
        case let .swirl(angle, radius, center):
            return pass("ollin_fx_swirl", [input],
                        [SIMD4(Float(angle), Float(radius), aspect, 0),
                         SIMD4(Float(center.x), Float(center.y), 0, 0)])
        case let .bulge(amount, radius, center):
            return pass("ollin_fx_bulge", [input],
                        [SIMD4(Float(amount), Float(radius), aspect, 0),
                         SIMD4(Float(center.x), Float(center.y), 0, 0)])
        case let .wave(amplitude, frequency, phase, vertical):
            return pass("ollin_fx_wave", [input],
                        [SIMD4(Float(amplitude), Float(frequency), Float(phase), vertical ? 1 : 0)])
        case let .ripple(amplitude, frequency, phase, center):
            return pass("ollin_fx_ripple", [input],
                        [SIMD4(Float(amplitude), Float(frequency), Float(phase), aspect),
                         SIMD4(Float(center.x), Float(center.y), 0, 0)])
        case let .mirror(vertical, flip):
            return pass("ollin_fx_mirror", [input], [SIMD4(vertical ? 1 : 0, flip ? 1 : 0, 0, 0)])
        case .polar(let amount):
            return pass("ollin_fx_polar", [input], [SIMD4(Float(amount), aspect, 0, 0)])
        case let .tile(count, mirror):
            return pass("ollin_fx_tile", [input], [SIMD4(Float(count), mirror ? 1 : 0, 0, 0)])
        case let .perturb(amount, scale, phase):
            return pass("ollin_fx_perturb", [input],
                        [SIMD4(Float(amount), Float(scale), Float(phase), aspect)])

        // Design filters. The three alpha-shape effects (liquid metal, heatmap,
        // gem smoke) first extract the layer's alpha as a mask and Gaussian-blur
        // it into smooth interior/halo fields; the fragment reads those beside
        // the layer. Blur sigmas scale with the layer so shapes read the same at
        // any resolution.
        case let .flutedGlass(flutes, shape, profile, distortion, shift, stretch,
                              blur, edges, highlights, shadows, margins, angle):
            return pass("ollin_fx_fluted_glass", [input],
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
            return pass("ollin_fx_water", [input],
                        [SIMD4(Float(scale), Float(waves), Float(refraction), Float(edges)),
                         SIMD4(Float(highlights), Float(phase), aspect, Float(layering)), highlight])
        case let .paperTexture(paper, shading, contrast, roughness, fiber, crumples,
                               folds, drops, seed):
            return pass("ollin_fx_paper_texture", [input],
                        [SIMD4(Float(contrast), Float(roughness), Float(fiber), Float(crumples)),
                         SIMD4(Float(folds), Float(drops), Float(seed), aspect),
                         paper, shading])
        case let .liquidMetal(repetition, softness, dispersion, distortion, contour,
                              angle, tint, phase):
            guard let field = poissonInteriorField(of: input, width: width, height: height,
                                                   into: cb, pooled: pooled),
                  let output = acquireFilterTexture(width: width, height: height, pooled: pooled)
            else { return nil }
            encodeEffectFragment("ollin_fx_liquid_metal", inputs: [input, field], output: output,
                                 params: [SIMD4(Float(repetition), Float(softness),
                                                Float(dispersion), Float(distortion)),
                                          SIMD4(Float(contour), Float(angle), Float(phase), aspect),
                                          tint,
                                          SIMD4(Float(max(1, height)), 0, 0, 0)], into: cb)
            return output
        case let .heatmap(colors, contour, innerGlow, outerGlow, angle, noise, phase):
            guard let (wide, tight) = blurredAlphaFields(of: input, width: width, height: height,
                                                         sigmas: (0.10, 0.02), into: cb, pooled: pooled),
                  let tightTex = tight,
                  let output = acquireFilterTexture(width: width, height: height, pooled: pooled)
            else { return nil }
            encodeEffectFragment("ollin_fx_heatmap", inputs: [input, tightTex, wide], output: output,
                                 params: [SIMD4(Float(colors.count), Float(contour),
                                                Float(innerGlow), Float(outerGlow)),
                                          SIMD4(Float(angle), Float(noise), Float(phase), aspect)]
                                         + colors, into: cb)
            return output
        case let .gemSmoke(colors, body, innerSwirl, outerSwirl, innerGlow, outerGlow,
                           offset, scale, angle, phase):
            guard let field = poissonInteriorField(of: input, width: width, height: height,
                                                   into: cb, pooled: pooled),
                  let output = acquireFilterTexture(width: width, height: height, pooled: pooled)
            else { return nil }
            encodeEffectFragment("ollin_fx_gem_smoke", inputs: [input, field], output: output,
                                 params: [SIMD4(Float(colors.count), Float(innerSwirl),
                                                Float(outerSwirl), Float(innerGlow)),
                                          SIMD4(Float(outerGlow), Float(offset), Float(scale),
                                                Float(angle)),
                                          SIMD4(Float(phase), aspect, 0, 0),
                                          body] + colors, into: cb)
            return output
        case let .melt(colors, scale, warp, liquify, blend, phase):
            return pass("ollin_fx_melt", [input],
                        [SIMD4(Float(scale), Float(liquify), Float(blend), aspect),
                         SIMD4(Float(warp), Float(phase), 0, 0)] + colors)
        }
    }

    /// Solve the interior-inflation field of `input`'s alpha shape (a constant-
    /// source Poisson problem, zero at the silhouette) as coarse-to-fine Jacobi
    /// relaxation passes, and hand back the normalized silhouette ramp
    /// R = 1 − u/u_max (1 at the edge, 0 at the deepest interior; 1 outside).
    /// Coarse levels converge the pillow's bulk cheaply; each finer level seeds
    /// from the previous solution (the pass reads its predecessor by uv, so the
    /// upsample is a free bilinear sample) and refines the boundary.
    private func poissonInteriorField(of input: MTLTexture, width: Int, height: Int,
                                      into cb: MTLCommandBuffer, pooled: Bool) -> MTLTexture? {
        guard let mask = acquireFilterTexture(width: width, height: height, pooled: pooled)
        else { return nil }
        encodeEffectFragment("ollin_fx_alpha_mask", inputs: [input], output: mask,
                             params: [], into: cb)

        let aspect = Double(width) / Double(max(1, height))
        func dims(_ minSide: Int) -> (Int, Int) {
            width >= height
                ? (max(1, Int((Double(minSide) * aspect).rounded())), minSide)
                : (minSide, max(1, Int((Double(minSide) / aspect).rounded())))
        }

        var solved: MTLTexture? = nil
        var solveDims = (0, 0)
        for (minSide, iterations) in [(32, 24), (64, 16), (128, 10), (256, 8)] {
            let (lw, lh) = dims(minSide)
            guard let texA = acquireFilterTexture(width: lw, height: lh, pooled: pooled),
                  let texB = acquireFilterTexture(width: lw, height: lh, pooled: pooled)
            else { return nil }
            var read = solved ?? mask
            for i in 0..<iterations {
                let out = i % 2 == 0 ? texA : texB
                let seedZero: Float = (solved == nil && i == 0) ? 1 : 0
                encodeEffectFragment("ollin_fx_poisson_jacobi", inputs: [mask, read], output: out,
                                     params: [SIMD4(1 / Float(lw), 1 / Float(lh), 0.05, seedZero)],
                                     into: cb)
                read = out
            }
            solved = read
            solveDims = (lw, lh)
        }
        guard let u = solved else { return nil }

        // Reduce to the field's peak (the normalizer), then bake the ramp.
        var peak = u
        var (mw, mh) = solveDims
        while mw > 1 || mh > 1 {
            let nw = max(1, mw / 4), nh = max(1, mh / 4)
            guard let out = acquireFilterTexture(width: nw, height: nh, pooled: pooled)
            else { return nil }
            encodeEffectFragment("ollin_fx_max_reduce", inputs: [peak], output: out,
                                 params: [SIMD4(1 / Float(mw), 1 / Float(mh), 0, 0)], into: cb)
            peak = out
            (mw, mh) = (nw, nh)
        }
        guard let field = acquireFilterTexture(width: solveDims.0, height: solveDims.1,
                                               pooled: pooled) else { return nil }
        encodeEffectFragment("ollin_fx_poisson_normalize", inputs: [u, peak, mask], output: field,
                             params: [], into: cb)
        return field
    }

    /// Extract `input`'s alpha as a grayscale mask and Gaussian-blur it into the
    /// smooth interior/halo field(s) the alpha-shape design filters read. Sigmas
    /// are fractions of the layer's shorter side; the second is optional.
    private func blurredAlphaFields(of input: MTLTexture, width: Int, height: Int,
                                    sigmas: (Double, Double?), into cb: MTLCommandBuffer,
                                    pooled: Bool) -> (MTLTexture, MTLTexture?)? {
        guard let mask = acquireFilterTexture(width: width, height: height, pooled: pooled),
              let wide = acquireFilterTexture(width: width, height: height, pooled: pooled)
        else { return nil }
        encodeEffectFragment("ollin_fx_alpha_mask", inputs: [input], output: mask,
                             params: [], into: cb)
        let side = Double(min(width, height))
        let wideBlur = MPSImageGaussianBlur(device: device, sigma: Float(sigmas.0 * side))
        wideBlur.edgeMode = .clamp
        wideBlur.encode(commandBuffer: cb, sourceTexture: mask, destinationTexture: wide)
        var tight: MTLTexture? = nil
        if let s2 = sigmas.1 {
            guard let t = acquireFilterTexture(width: width, height: height, pooled: pooled)
            else { return nil }
            let tightBlur = MPSImageGaussianBlur(device: device, sigma: Float(s2 * side))
            tightBlur.edgeMode = .clamp
            tightBlur.encode(commandBuffer: cb, sourceTexture: mask, destinationTexture: t)
            tight = t
        }
        return (wide, tight)
    }

    /// Run one two-input `op` (mask / displace / mix) over `base` modulated by `aux`
    /// into a freshly acquired output texture, the multi-input sibling of
    /// `applyFilter`. Each is a single fullscreen fragment pass binding both layers,
    /// reading premultiplied-linear and writing the same. The two inputs may differ
    /// in size; the fragment samples by normalized coordinates, so it doesn't matter.
    private func applyCombine(_ op: Combine, base: MTLTexture, aux: MTLTexture,
                              depth: DepthReconstruction? = nil, normals: MTLTexture? = nil,
                              width: Int, height: Int,
                              into cb: MTLCommandBuffer, pooled: Bool) -> MTLTexture? {
        func pass(_ fragment: String, _ params: [SIMD4<Float>]) -> MTLTexture? {
            guard let output = acquireFilterTexture(width: width, height: height, pooled: pooled) else { return nil }
            encodeEffectFragment(fragment, inputs: [base, aux], output: output, params: params, into: cb)
            return output
        }
        switch op.kind {
        case let .shader(shader):
            guard let output = acquireFilterTexture(width: width, height: height, pooled: pooled) else { return nil }
            encodeUserShader(shader, variant: .combine, inputs: [base, aux], output: output,
                             width: width, height: height, into: cb)
            return output
        case let .mask(channel, invert):
            return pass("ollin_fx_mask", [SIMD4(channel.rawIndex, invert ? 1 : 0, 0, 0)])
        case let .displace(amount):
            return pass("ollin_fx_displace", [SIMD4(Float(amount), 0, 0, 0)])
        case let .mix(amount):
            return pass("ollin_fx_mix", [SIMD4(Float(amount), 0, 0, 0)])
        case let .defocus(focus, range, maxBlur, quality):
            // maxBlur is in layer pixels; the gather works in texels, so at this
            // layer's resolution one is the other (the texel-size row keeps the disk
            // round on a non-square layer). The third texel slot carries the resolved
            // bokeh tap budget for the gather.
            //
            // Two passes: a pre-pass reduces the aux depth to per-pixel circle-of-
            // confusion sizes (the size a pixel scatters by, min-filtered so an
            // anti-aliased silhouette can't fling the colour under it across the whole
            // blur radius, and the size it receives, seam-dilated), then the bokeh
            // gather reads that instead of the raw depth. It costs one fullscreen pass
            // and takes the dilation's 8 taps back out of the per-pixel gather.
            let taps = Float(resolveDofTaps(quality))
            let texel = SIMD4<Float>(1 / Float(width), 1 / Float(height), taps, 0)
            let dof = SIMD4(Float(focus), Float(range), Float(maxBlur), 0)
            guard let coc = acquireFilterTexture(width: width, height: height, pooled: pooled),
                  let out = acquireFilterTexture(width: width, height: height, pooled: pooled)
            else { return nil }
            encodeEffectFragment("ollin_fx_dof_prepass", inputs: [aux], output: coc,
                                 params: [dof, texel], into: cb)
            encodeEffectFragment("ollin_fx_depth_of_field", inputs: [base, coc], output: out,
                                 params: [dof, texel], into: cb)
            return out
        case let .ambientOcclusion(radius, intensity, bias, quality):
            // Two passes: a hemisphere-kernel occlusion estimate (rebuilding view-space
            // position + normal from the aux depth, with the camera geometry stamped on
            // the depth layer, a neutral perspective when the aux carries none, e.g. a
            // hand-drawn depth map), then a depth-aware blur that softens it and multiplies
            // the base. The sample budget rides the texel row's third slot, as the bokeh
            // gather's does.
            let samples = Float(resolveSSAOSamples(quality))
            let texel = SIMD4<Float>(1 / Float(width), 1 / Float(height), samples, 0)
            let d = depth ?? .neutral
            guard let aoTex = acquireFilterTexture(width: width, height: height, pooled: pooled),
                  let out = acquireFilterTexture(width: width, height: height, pooled: pooled) else { return nil }
            // The mesh-normal G-buffer at texture index 1 (depth stays 0) when it was
            // captured: the shader reads a true view-space normal instead of reconstructing
            // one from depth. A never-sampled stand-in (the depth) keeps the binding valid
            // otherwise, gated by the `hasNormals` flag in params[0].w.
            let hasNormals: Float = normals != nil ? 1 : 0
            encodeEffectFragment("ollin_fx_ssao", inputs: [aux, normals ?? aux], output: aoTex,
                                 params: [SIMD4(Float(radius), Float(intensity), Float(bias), hasNormals), texel,
                                          SIMD4(d.near, d.far, d.tanHalfFovX, d.tanHalfFovY),
                                          SIMD4(d.principalX, d.principalY, d.isPerspective ? 1 : 0, 0)],
                                 into: cb)
            encodeEffectFragment("ollin_fx_ssao_blur", inputs: [base, aoTex, aux], output: out,
                                 params: [SIMD4(Float(intensity), 0, 0, 0), texel], into: cb)
            return out
        case let .screenSpaceReflections(intensity, maxDistance, thickness, roughness, fresnel, edgeFade, quality):
            // Four passes: a screen-space ray march (rebuilding view-space position + normal from
            // the aux depth, reflecting the eye ray about the normal, then marching until it
            // crosses the depth buffer) writes a premultiplied reflection; a depth-aware,
            // roughness-scaled blur softens it; a temporal pass reprojects last frame's reflection
            // and accumulates it (killing the contact-seam flicker that no spatial filter removes);
            // a final pass composites the accumulated reflection over the base. The march/blur/
            // temporal run at a quality-resolved fraction of the resolution and the composite
            // upsamples back to full, so live trades reflection resolution for frame rate while
            // export resolves to full (snapshots and exported art are never downscaled). The
            // camera geometry rides params[2..3] byte-for-byte as SSAO's does; the march budget
            // rides the texel row's third slot.
            let steps = Float(resolveSSRSteps(quality))
            let scale = resolveSSRScale(quality)
            let sw = max(1, Int((Double(width) * scale).rounded()))
            let sh = max(1, Int((Double(height) * scale).rounded()))
            let texel = SIMD4<Float>(1 / Float(sw), 1 / Float(sh), steps, Float(fresnel))
            let d = depth ?? .neutral
            let occurrence = ssrOccurrenceThisFrame[op.sourceID, default: 0]
            ssrOccurrenceThisFrame[op.sourceID] = occurrence + 1
            let slotKey = SSRSlotKey(source: op.sourceID, occurrence: occurrence)
            guard let reflTex = acquireFilterTexture(width: sw, height: sh, pooled: pooled),
                  let reflBlur = acquireFilterTexture(width: sw, height: sh, pooled: pooled),
                  let slot = ssrHistorySlot(key: slotKey, width: sw, height: sh, into: cb),
                  let out = acquireFilterTexture(width: width, height: height, pooled: pooled) else { return nil }
            let hasNormals: Float = normals != nil ? 1 : 0
            let front = slot.flipped ? slot.b : slot.a
            let back  = slot.flipped ? slot.a : slot.b
            if statefulEncodeIsRepeat && slot.valid {
                // The frame's first encode already traced, blended, and flipped: the
                // front holds this frame's accumulated reflection. Re-blending would
                // advance the EMA twice per displayed frame and hand a recorder a
                // frame one temporal step ahead of the screen; composite only.
                encodeEffectFragment("ollin_fx_ssr_composite", inputs: [base, front], output: out,
                                     params: [SIMD4(0, 0, 0, 0),
                                              SIMD4(1 / Float(width), 1 / Float(height), 0, 0)], into: cb)
                return out
            }
            // Pass 1: trace the premultiplied reflection.
            encodeEffectFragment("ollin_fx_ssr", inputs: [base, aux, normals ?? aux], output: reflTex,
                                 params: [SIMD4(Float(intensity), Float(maxDistance), Float(thickness), hasNormals),
                                          texel,
                                          SIMD4(d.near, d.far, d.tanHalfFovX, d.tanHalfFovY),
                                          SIMD4(d.principalX, d.principalY, d.isPerspective ? 1 : 0, 0),
                                          SIMD4(Float(edgeFade), Float(roughness), 6, 0)],
                                 into: cb)
            // Pass 2: roughness blur, reflection only (composite flag 0).
            encodeEffectFragment("ollin_fx_ssr_resolve", inputs: [base, reflTex, aux], output: reflBlur,
                                 params: [SIMD4(Float(roughness), 0, 0, 0), texel], into: cb)
            // Pass 3: temporal accumulation into the history back buffer (reading the front +
            // last frame's view·projection), then advance the slot's previous transform.
            let alpha = slot.valid ? Float(resolveSSRAlpha(quality)) : 0
            let iv = d.inverseView, pv = slot.previousViewProjection
            encodeEffectFragment("ollin_fx_ssr_temporal", inputs: [reflBlur, aux, front], output: back,
                                 params: [SIMD4(1 / Float(sw), 1 / Float(sh), alpha, slot.valid ? 1 : 0),
                                          SIMD4(0, 0, 0, 0),
                                          SIMD4(d.near, d.far, d.tanHalfFovX, d.tanHalfFovY),
                                          SIMD4(d.principalX, d.principalY, d.isPerspective ? 1 : 0, 0),
                                          iv.columns.0, iv.columns.1, iv.columns.2, iv.columns.3,
                                          pv.columns.0, pv.columns.1, pv.columns.2, pv.columns.3],
                                 into: cb)
            slot.previousViewProjection = d.viewProjection
            slot.valid = true
            ssrHistoryUsedThisFrame.insert(slotKey)
            // Pass 4: composite the accumulated reflection (upsampled from `back`) over the base.
            encodeEffectFragment("ollin_fx_ssr_composite", inputs: [base, back], output: out,
                                 params: [SIMD4(0, 0, 0, 0),
                                          SIMD4(1 / Float(width), 1 / Float(height), 0, 0)], into: cb)
            return out
        }
    }

    /// Evolve a `SimField` one frame: inject the drawn `seed` onto the `state` (the
    /// front buffer), then run the sim's step fragment N times, ping-ponging between
    /// two scratch textures and landing the last step in `output` (the back buffer).
    /// All fragment passes on the effect pipeline, reading/writing the float field.
    private func runSimulation(_ sim: Sim, state: MTLTexture, seed: MTLTexture, output: MTLTexture,
                               width: Int, height: Int, into cb: MTLCommandBuffer, pooled: Bool) {
        guard let s0 = acquireFilterTexture(width: width, height: height, pooled: pooled),
              let s1 = acquireFilterTexture(width: width, height: height, pooled: pooled) else { return }
        let texel = SIMD4<Float>(1 / Float(width), 1 / Float(height), 0, 0)
        // Inject the seed marks onto the current state (composited by the seed's
        // alpha, or added, per the sim's inject fragment). The sim's parameter rows
        // ride along for the injects that read one (the sandpile's pour); the rest
        // never look past the texel row.
        encodeEffectFragment(sim.injectFragment, inputs: [state, seed], output: s0,
                             params: [texel] + sim.params, into: cb)
        // Step: read s0, ping-pong s0↔s1 between steps, write the final step into the
        // back buffer. Read and write are always distinct, so there's no in-pass hazard.
        var read = s0
        let steps = max(1, sim.subSteps)
        for i in 0..<steps {
            let write = (i == steps - 1) ? output : (read === s0 ? s1 : s0)
            encodeEffectFragment(sim.stepFragment, inputs: [read], output: write,
                                 params: [texel] + sim.params, into: cb)
            read = write
        }
    }

    /// Evolve a fluid `SimField` one frame: splat the drawn `seed` (its colour into the
    /// dye, the block's `force` into the velocity), confine the vorticity, project the
    /// velocity to a divergence-free field with a Jacobi pressure solve + gradient
    /// subtraction, then advect velocity and dye along the flow. The persistent
    /// `velFront`/`dyeFront` are read; the evolved fields land in `velBack`/`dyeBack`
    /// (next frame's fronts). Every intermediate field is pooled scratch — each
    /// `acquireFilterTexture` call returns a distinct texture, so the passes never
    /// alias — and Metal serializes the read-after-write chain across the passes.
    private func runFluid(_ config: Sim.FluidConfig, force: Vector2, seed: MTLTexture,
                          velFront: MTLTexture, velBack: MTLTexture,
                          dyeFront: MTLTexture, dyeBack: MTLTexture,
                          width: Int, height: Int, into cb: MTLCommandBuffer, pooled: Bool) {
        func scratch() -> MTLTexture? { acquireFilterTexture(width: width, height: height, pooled: pooled) }
        guard let velSplat = scratch(), let dyeSplat = scratch(), let curl = scratch(),
              let velVort = scratch(), let div = scratch(), let pA = scratch(), let pB = scratch(),
              let velProj = scratch() else { return }
        let texel = SIMD4<Float>(1 / Float(width), 1 / Float(height), 0, 0)
        let dt = config.dt

        // 1. Splat: push the velocity by `force`, add the dye colour, where marks landed.
        //    `force` is canvas points per frame (the brush's motion); dividing by the
        //    timestep turns it into a velocity, so advecting by `dt` moves the dye at the
        //    brush's own speed.
        let inv = dt > 0 ? 1 / dt : 0
        encodeEffectFragment("ollin_fluid_splat_velocity", inputs: [velFront, seed], output: velSplat,
                             params: [texel, SIMD4(Float(force.x) * inv, Float(force.y) * inv, 0, 0)], into: cb)
        encodeEffectFragment("ollin_fluid_splat_dye", inputs: [dyeFront, seed], output: dyeSplat,
                             params: [texel], into: cb)
        // 2. Vorticity confinement: read the curl of the splatted velocity, push the
        //    swirl back in (buoyancy reads the dye for an optional upward lift).
        encodeEffectFragment("ollin_fluid_curl", inputs: [velSplat], output: curl,
                             params: [texel], into: cb)
        encodeEffectFragment("ollin_fluid_vorticity", inputs: [velSplat, curl, dyeSplat], output: velVort,
                             params: [texel, SIMD4(config.curl, dt, config.buoyancy, 0)], into: cb)
        // 3. Projection: divergence → clear pressure → Jacobi iterations → subtract its
        //    gradient, leaving the velocity incompressible. The ping-pong leaves the
        //    converged pressure in `pRead`.
        encodeEffectFragment("ollin_fluid_divergence", inputs: [velVort], output: div,
                             params: [texel], into: cb)
        clearFloatTexture(pA, into: cb)
        var pRead = pA, pWrite = pB
        for _ in 0..<max(1, config.pressureIterations) {
            encodeEffectFragment("ollin_fluid_pressure", inputs: [pRead, div], output: pWrite,
                                 params: [texel], into: cb)
            swap(&pRead, &pWrite)
        }
        encodeEffectFragment("ollin_fluid_gradient_subtract", inputs: [pRead, velVort], output: velProj,
                             params: [texel], into: cb)
        // 4. Advect velocity by itself, then the dye by the new velocity, into the
        //    persistent back buffers (next frame's fronts).
        encodeEffectFragment("ollin_fluid_advect", inputs: [velProj, velProj], output: velBack,
                             params: [texel, SIMD4(dt, config.velocityDissipation, 0, 0)], into: cb)
        encodeEffectFragment("ollin_fluid_advect", inputs: [velBack, dyeSplat], output: dyeBack,
                             params: [texel, SIMD4(dt, config.densityDissipation, 0, 0)], into: cb)
    }

    /// The starting-state fill a multi-scale Turing field needs (seeded white noise),
    /// or `nil` for every other sim, which starts from a constant rest state. Handed to
    /// `feedbackSlot` so it applies exactly once, when the pair is first allocated.
    private func turingNoiseFill(_ sim: Sim, into cb: MTLCommandBuffer) -> ((MTLTexture) -> Void)? {
        guard let turing = sim.turingConfig else { return nil }
        return { tex in
            let texel = SIMD4<Float>(1 / Float(tex.width), 1 / Float(tex.height), 0, 0)
            self.encodeEffectFragment("ollin_sim_turing_seed", inputs: [], output: tex,
                                      params: [texel, SIMD4(Float(turing.seed), 0, 0, 0)], into: cb)
        }
    }

    /// One step of a multi-scale Turing field, McCabe's rule: at every pixel each scale
    /// compares the field's average over a small disc against its average over a larger
    /// one, the scale whose two averages differ least wins and nudges the pixel toward
    /// whichever average is the greater, and the whole field is then stretched back
    /// across its full range so the nudges cannot accumulate into a runaway.
    ///
    /// The passes, in order: inject the drawn seed marks; build a blur pyramid down to
    /// 1x1 (each rung the 2x2 mean of the one above, so one texel holds the mean of a
    /// 2^k box and any radius is a fractional rung); per scale, measure its disagreement
    /// and run it down the same halving chain to the rung matching its variation radius;
    /// step; reduce the stepped field to its minimum and maximum through a 4x4 chain;
    /// normalize into the back buffer.
    ///
    /// The pyramid is what makes this real time. Gathering a disc of radius 32 costs
    /// thousands of taps per pixel per scale, where a rung costs one, and the radii a
    /// multi-scale field wants (doubling from 1 to 32 or beyond) are exactly the rungs a
    /// halving pyramid produces. It also serves the variation averaging for free, so a
    /// scale's disagreement is smoothed by the same chain that blurs the field.
    private func runMultiScaleTuring(_ scales: [TuringScale], state: MTLTexture, seed: MTLTexture,
                                     output: MTLTexture, width: Int, height: Int,
                                     into cb: MTLCommandBuffer, pooled: Bool) {
        guard !scales.isEmpty else { return }
        func scratch(_ w: Int, _ h: Int) -> MTLTexture? {
            acquireFilterTexture(width: w, height: h, pooled: pooled)
        }
        // Pyramid rung sizes, halving (rounding up, so an odd side keeps its last
        // half-block) until 1x1. Rung 0 is the injected field itself, at full size.
        var rungs: [(w: Int, h: Int)] = [(width, height)]
        while rungs.count < MetalRenderer.turingPyramidLevels {
            let last = rungs[rungs.count - 1]
            guard last.w > 1 || last.h > 1 else { break }
            rungs.append((max(1, (last.w + 1) / 2), max(1, (last.h + 1) / 2)))
        }
        // Extent chain sizes, quartering until 1x1, over the stepped field.
        var extentSizes: [(w: Int, h: Int)] = []
        var (ew, eh) = (width, height)
        repeat {
            ew = max(1, (ew + 3) / 4)
            eh = max(1, (eh + 3) / 4)
            extentSizes.append((ew, eh))
        } while ew > 1 || eh > 1

        // How many rungs down a radius sits: a radius r spans a box of side 2r, which is
        // rung log2(2r). Kept in step with `ollin_turing_blur`.
        func rung(for radius: Double) -> Int {
            let level = (Foundation.log2(max(radius, 0.5) * 2)).rounded()
            return min(max(Int(level), 0), rungs.count - 1)
        }

        // Acquire every texture before encoding anything, so a pool miss aborts the
        // step cleanly rather than leaving a half-run pipeline.
        guard let injected = scratch(width, height), let stepped = scratch(width, height)
        else { return }
        var levels: [MTLTexture] = [injected]
        for rung in rungs.dropFirst() {
            guard let tex = scratch(rung.w, rung.h) else { return }
            levels.append(tex)
        }
        // Each scale's variation chain: measured at full size, then halved down to the
        // rung its variation radius names, so a fine scale's chain is short.
        var variationChains: [[MTLTexture]] = []
        for scale in scales {
            var chain: [MTLTexture] = []
            for depth in 0...rung(for: scale.variationRadius) {
                guard let tex = scratch(rungs[depth].w, rungs[depth].h) else { return }
                chain.append(tex)
            }
            variationChains.append(chain)
        }
        var extents: [MTLTexture] = []
        for size in extentSizes {
            guard let tex = scratch(size.w, size.h) else { return }
            extents.append(tex)
        }

        let texel = SIMD4<Float>(1 / Float(width), 1 / Float(height), 0, 0)
        let frame = SIMD4<Float>(1 / Float(width), 1 / Float(height),
                                 Float(width) / Float(height), Float(levels.count))
        encodeEffectFragment("ollin_sim_inject_luma", inputs: [state, seed], output: injected,
                             params: [texel], into: cb)
        for i in 1..<levels.count {
            let src = rungs[i - 1], dst = rungs[i]
            encodeEffectFragment("ollin_sim_turing_downsample", inputs: [levels[i - 1]], output: levels[i],
                                 params: [SIMD4(1 / Float(src.w), 1 / Float(src.h),
                                                Float(dst.w), Float(dst.h))], into: cb)
        }
        // The passes read a fixed-width binding, so a shallow pyramid repeats its top
        // rung to fill it; `levelCount` keeps the shader off the padding.
        var boundLevels = levels
        while boundLevels.count < MetalRenderer.turingPyramidLevels {
            boundLevels.append(levels[levels.count - 1])
        }
        for (i, scale) in scales.enumerated() {
            let chain = variationChains[i]
            encodeEffectFragment("ollin_sim_turing_variation", inputs: boundLevels, output: chain[0],
                                 params: [frame, SIMD4(Float(scale.activatorRadius),
                                                       Float(scale.inhibitorRadius),
                                                       Float(scale.symmetry), Float(scale.weight))],
                                 into: cb)
            for depth in 1..<chain.count {
                let src = rungs[depth - 1], dst = rungs[depth]
                encodeEffectFragment("ollin_sim_turing_downsample", inputs: [chain[depth - 1]],
                                     output: chain[depth],
                                     params: [SIMD4(1 / Float(src.w), 1 / Float(src.h),
                                                    Float(dst.w), Float(dst.h))], into: cb)
            }
        }
        var params: [SIMD4<Float>] = [frame, SIMD4(Float(scales.count), 0, 0, 0)]
        for scale in scales {
            params.append(SIMD4(Float(scale.activatorRadius), Float(scale.inhibitorRadius),
                                Float(scale.amount), Float(scale.weight)))
            params.append(SIMD4(Float(scale.symmetry), 0, 0, 0))
        }
        var boundVariations = variationChains.map { $0[$0.count - 1] }
        while boundVariations.count < TuringScale.maxScales {
            boundVariations.append(boundVariations[boundVariations.count - 1])
        }
        encodeEffectFragment("ollin_sim_turing_step", inputs: boundLevels + boundVariations,
                             output: stepped, params: params, into: cb)
        var source = stepped
        var sourceSize = (w: width, h: height)
        for (i, tex) in extents.enumerated() {
            encodeEffectFragment("ollin_sim_turing_extent", inputs: [source], output: tex,
                                 params: [SIMD4(1 / Float(sourceSize.w), 1 / Float(sourceSize.h),
                                                Float(extentSizes[i].w), Float(extentSizes[i].h))], into: cb)
            source = tex
            sourceSize = extentSizes[i]
        }
        encodeEffectFragment("ollin_sim_turing_normalize", inputs: [stepped, source], output: output,
                             params: [texel], into: cb)
    }

    /// Fill a generator's layer: one fullscreen fragment pass that reads no input,
    /// just its parameters. `aspect` lets the fragment keep cells square.
    private func encodeGenerator(_ generator: Generator, output: MTLTexture,
                                 width: Int, height: Int, into cb: MTLCommandBuffer) {
        let aspect = Float(width) / Float(max(1, height))
        switch generator.kind {
        case let .shader(shader):
            encodeUserShader(shader, variant: .generator, inputs: [], output: output,
                             width: width, height: height, into: cb)
        case let .checkers(scale, fg, bg):
            encodeEffectFragment("ollin_gen_checkers", inputs: [], output: output,
                                 params: [SIMD4(Float(scale), aspect, 0, 0), fg, bg], into: cb)
        case let .gridLines(scale, weight, fg, bg):
            encodeEffectFragment("ollin_gen_grid", inputs: [], output: output,
                                 params: [SIMD4(Float(scale), Float(weight), aspect, 0), fg, bg], into: cb)
        case let .bars(scale, vertical, fg, bg):
            encodeEffectFragment("ollin_gen_bars", inputs: [], output: output,
                                 params: [SIMD4(Float(scale), vertical ? 1 : 0, aspect, 0), fg, bg], into: cb)
        case let .noise(scale, sharpness, warp, fg, bg):
            encodeEffectFragment("ollin_gen_noise", inputs: [], output: output,
                                 params: [SIMD4(Float(scale), Float(sharpness), aspect, Float(warp)), fg, bg], into: cb)
        case let .cellular(scale, jitter, style, fg, bg, phase):
            encodeEffectFragment("ollin_gen_cellular", inputs: [], output: output,
                                 params: [SIMD4(Float(scale), Float(jitter), aspect, Float(phase)),
                                          SIMD4(style.rawIndex, 0, 0, 0), fg, bg], into: cb)

        // Design patterns. Each packs its scalars into leading rows and appends
        // the palette as trailing color rows the fragment indexes past them.
        case let .meshGradient(colors, distortion, swirl, mixing, grain, phase):
            // The blend knob maps to the inverse-distance power piecewise so the
            // 0.5 default is *exactly* the classic 3.5 (snapshot-pinned): 0 is a
            // hard near-Voronoi 16, 1 a buttery 1.
            let power = mixing <= 0.5 ? 16.0 - (16.0 - 3.5) * (mixing * 2)
                                      : 3.5 - 2.5 * ((mixing - 0.5) * 2)
            encodeEffectFragment("ollin_gen_mesh_gradient", inputs: [], output: output,
                                 params: [SIMD4(Float(colors.count), aspect, Float(distortion), Float(swirl)),
                                          SIMD4(Float(grain), Float(phase), Float(power), 0)] + colors, into: cb)
        case let .filaments(color, highlight, background, scale, brightness, contrast, phase):
            encodeEffectFragment("ollin_gen_filaments", inputs: [], output: output,
                                 params: [SIMD4(Float(scale), aspect, Float(brightness), Float(contrast)),
                                          SIMD4(Float(phase), 0, 0, 0),
                                          color, highlight, background], into: cb)
        case let .smokeRing(colors, background, radius, thickness, fill, scale, detail, phase):
            encodeEffectFragment("ollin_gen_smoke_ring", inputs: [], output: output,
                                 params: [SIMD4(Float(colors.count), aspect, Float(radius), Float(thickness)),
                                          SIMD4(Float(fill), Float(scale), Float(detail), Float(phase)),
                                          background] + colors, into: cb)
        case let .colorPanels(colors, background, density, length, skew, blur,
                              fadeIn, fadeOut, gradient, phase):
            // Panels tile the palette an even number of times (≥ 12 panes) so the
            // two mirrored half-phase sets stay color-aligned across the wrap.
            var panels = 12
            while panels % colors.count != 0 || (panels / colors.count) % 2 != 0 { panels += 1 }
            encodeEffectFragment("ollin_gen_color_panels", inputs: [], output: output,
                                 params: [SIMD4(Float(colors.count), aspect, Float(density), Float(length)),
                                          SIMD4(Float(skew), Float(blur), Float(gradient), Float(phase)),
                                          SIMD4(Float(fadeIn), Float(fadeOut), Float(panels),
                                                Float(panels) / 12),
                                          background] + colors, into: cb)
        case let .spiral(foreground, background, density, distortion, strokeWidth,
                         taper, cap, noise, noiseScale, softness, scale, phase):
            encodeEffectFragment("ollin_gen_spiral", inputs: [], output: output,
                                 params: [SIMD4(aspect, Float(density), Float(distortion), Float(strokeWidth)),
                                          SIMD4(Float(taper), Float(cap), Float(noise), Float(noiseScale)),
                                          SIMD4(Float(softness), Float(scale), Float(phase), 0),
                                          foreground, background], into: cb)
        case let .waves(foreground, background, shape, frequency, amplitude,
                        spacing, proportion, softness, scale, phase):
            encodeEffectFragment("ollin_gen_waves", inputs: [], output: output,
                                 params: [SIMD4(aspect, Float(shape), Float(frequency), Float(amplitude)),
                                          SIMD4(Float(spacing), Float(proportion), Float(softness), Float(scale)),
                                          SIMD4(Float(phase), 0, 0, 0),
                                          foreground, background], into: cb)
        case let .dotOrbit(colors, background, scale, size, sizeVariation, spread, steps, phase):
            encodeEffectFragment("ollin_gen_dot_orbit", inputs: [], output: output,
                                 params: [SIMD4(Float(colors.count), aspect, Float(scale), Float(size)),
                                          SIMD4(Float(sizeVariation), Float(spread), Float(steps), Float(phase)),
                                          background] + colors, into: cb)
        case let .grainGradient(colors, background, shape, softness, intensity, noise, phase):
            encodeEffectFragment("ollin_gen_grain_gradient", inputs: [], output: output,
                                 params: [SIMD4(Float(colors.count), aspect, shape.rawIndex, Float(softness)),
                                          SIMD4(Float(intensity), Float(noise), Float(phase),
                                                Float(max(1, height))),
                                          background] + colors, into: cb)
        case let .pulsingBorder(colors, background, roundness, thickness, softness, intensity,
                                bloom, spots, spotSize, pulse, smoke, smokeScale, margins, phase):
            // Margins arrive in layer pixels; the border lives in centered
            // square units, so convert per side.
            let unit = Double(min(aspect, 1))
            let mL = margins.left / Double(width) * Double(aspect) / unit
            let mR = margins.right / Double(width) * Double(aspect) / unit
            let mT = margins.top / Double(max(1, height)) / unit
            let mB = margins.bottom / Double(max(1, height)) / unit
            encodeEffectFragment("ollin_gen_pulsing_border", inputs: [], output: output,
                                 params: [SIMD4(Float(colors.count), aspect, Float(roundness), Float(thickness)),
                                          SIMD4(Float(softness), Float(intensity), Float(bloom), Float(spots)),
                                          SIMD4(Float(spotSize), Float(pulse), Float(smoke), Float(smokeScale)),
                                          SIMD4(Float(phase), Float(mL), Float(mR), Float(mT)),
                                          SIMD4(Float(mB), 0, 0, 0),
                                          background] + colors, into: cb)
        case let .godRays(colors, background, x, y, density, breakup, coreSize,
                          coreIntensity, intensity, bloom, bloomTint, phase):
            encodeEffectFragment("ollin_gen_god_rays", inputs: [], output: output,
                                 params: [SIMD4(Float(colors.count), aspect, Float(x), Float(y)),
                                          SIMD4(Float(density), Float(breakup), Float(coreSize),
                                                Float(coreIntensity)),
                                          SIMD4(Float(intensity), Float(bloom), Float(phase), 0),
                                          bloomTint, background] + colors, into: cb)

        // Pattern fields: scalars in the leading rows, background at params[2],
        // the palette (where one applies) as trailing rows.
        case let .quasicrystal(colors, background, symmetry, scale, contrast, phase):
            encodeEffectFragment("ollin_gen_quasicrystal", inputs: [], output: output,
                                 params: [SIMD4(Float(colors.count), aspect, Float(symmetry), Float(scale)),
                                          SIMD4(Float(contrast), Float(phase), 0, 0),
                                          background] + colors, into: cb)
        case let .moire(foreground, background, sources, frequency, scale, phase):
            encodeEffectFragment("ollin_gen_moire", inputs: [], output: output,
                                 params: [SIMD4(aspect, Float(sources), Float(frequency), Float(scale)),
                                          SIMD4(Float(phase), 0, 0, 0),
                                          foreground, background], into: cb)
        case let .gyroid(foreground, background, scale, thickness, phase):
            encodeEffectFragment("ollin_gen_gyroid", inputs: [], output: output,
                                 params: [SIMD4(aspect, Float(scale), Float(thickness), Float(phase)),
                                          foreground, background], into: cb)
        case let .phyllotaxis(colors, background, count, dotSize, phase):
            encodeEffectFragment("ollin_gen_phyllotaxis", inputs: [], output: output,
                                 params: [SIMD4(Float(colors.count), aspect, Float(count), Float(dotSize)),
                                          SIMD4(Float(phase), 0, 0, 0),
                                          background] + colors, into: cb)
        case let .hexPulse(colors, background, scale, gap, phase):
            encodeEffectFragment("ollin_gen_hexpulse", inputs: [], output: output,
                                 params: [SIMD4(Float(colors.count), aspect, Float(scale), Float(gap)),
                                          SIMD4(Float(phase), 0, 0, 0),
                                          background] + colors, into: cb)
        case let .chladni(m, n, style, weight, grain, foreground, background, scale, phase):
            encodeEffectFragment("ollin_gen_chladni", inputs: [], output: output,
                                 params: [SIMD4(aspect, Float(m), Float(n), Float(scale)),
                                          SIMD4(style.rawIndex, Float(weight), Float(grain), Float(phase)),
                                          foreground, background], into: cb)
        case let .escapeTime(colors, interior, mode, c, center, zoom, iterations, cycles, phase):
            encodeEffectFragment("ollin_gen_escape", inputs: [], output: output,
                                 params: [SIMD4(Float(colors.count), aspect, Float(mode), Float(iterations)),
                                          SIMD4(Float(center.x), Float(center.y), Float(zoom), Float(cycles)),
                                          SIMD4(Float(c.x), Float(c.y), Float(phase), 0),
                                          interior] + colors, into: cb)
        }
    }

    /// Encode one fullscreen filter (or generator) fragment pass: bind `inputs` as
    /// fragment textures 0… (empty for a generator, which reads nothing), the packed
    /// `params` rows as fragment buffer 0, and draw the present triangle into
    /// `output` (single-sample, replace). Shaders read `constant float4 *params`.
    func encodeEffectFragment(_ fragment: String, inputs: [MTLTexture],
                                      output: MTLTexture, params: [SIMD4<Float>],
                                      into cb: MTLCommandBuffer) {
        guard let state = try? pipeline(.effect(fragment)) else { return }
        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = output
        pass.colorAttachments[0].loadAction = .dontCare
        pass.colorAttachments[0].storeAction = .store
        guard let enc = cb.makeRenderCommandEncoder(descriptor: pass) else { return }
        enc.setRenderPipelineState(state)
        for (i, tex) in inputs.enumerated() { enc.setFragmentTexture(tex, index: i) }
        enc.setFragmentSamplerState(imageSampler, index: 0)
        let p = params.isEmpty ? [SIMD4<Float>(repeating: 0)] : params
        p.withUnsafeBytes { enc.setFragmentBytes($0.baseAddress!, length: $0.count, index: 0) }
        enc.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        enc.endEncoding()
    }

    /// Encode one user-supplied `Shader` pass: compile (and cache) its pipeline, then
    /// draw the present triangle into `output`, binding the input layer(s) as fragment
    /// textures 0…, the user `params` at buffer 0, and the per-frame `OllinShaderUniforms`
    /// at buffer 1. A compile error is reported (stderr once per source, and to the host
    /// sink) and the pass is skipped, so a broken shader never crashes the frame; a
    /// later clean compile clears the reported error.
    private func encodeUserShader(_ shader: Shader, variant: UserShaderVariant,
                                  inputs: [MTLTexture], output: MTLTexture,
                                  width: Int, height: Int,
                                  into cb: MTLCommandBuffer) {
        let (state, hash) = userShaderState(for: shader, variant: variant)
        guard let state else {
            if let err = userShaderErrors[hash] {
                currentUserShaderError = err   // surfaced to the host after the frame
                if !printedShaderErrorHashes.contains(hash) {
                    FileHandle.standardError.write(Data(
                        "Ollin: shader compile failed\n\(err.message)\n".utf8))
                    printedShaderErrorHashes.insert(hash)
                }
            }
            return
        }

        var u = OllinShaderUniforms(
            resolution: SIMD2(Float(width), Float(height)),
            mouse: frameComputeUniforms.mouse,
            time: frameComputeUniforms.time,
            deltaTime: frameComputeUniforms.dt,
            frame: frameComputeUniforms.frameCount,
            paramCount: UInt32(min(shader.params.count, Int(OLLIN_SHADER_PARAM_COUNT))))
        let params = shader.paddedParams

        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = output
        pass.colorAttachments[0].loadAction = .dontCare
        pass.colorAttachments[0].storeAction = .store
        guard let enc = cb.makeRenderCommandEncoder(descriptor: pass) else { return }
        enc.setRenderPipelineState(state)
        for (i, tex) in inputs.enumerated() { enc.setFragmentTexture(tex, index: i) }
        enc.setFragmentSamplerState(imageSampler, index: 0)
        params.withUnsafeBytes { enc.setFragmentBytes($0.baseAddress!, length: $0.count, index: 0) }
        enc.setFragmentBytes(&u, length: MemoryLayout<OllinShaderUniforms>.stride, index: 1)
        enc.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        enc.endEncoding()
    }

    /// The compiled pipeline for a user shader, built and cached on first use (keyed by
    /// the composed-source hash, returned alongside). Returns `(nil, hash)` on a compile
    /// error, recording it in `userShaderErrors[hash]` so it isn't retried every frame.
    private func userShaderState(for shader: Shader,
                                 variant: UserShaderVariant) -> (MTLRenderPipelineState?, UInt64) {
        let userSource = resolveUserShaderSource(shader)
        let sourceName = shader.diagnosticSourceName
        let startLine = shader.diagnosticStartLine
        let (composed, offset) = MetalRenderer.composeUserShaderSource(
            userSource: userSource, modules: shader.modules, variant: variant,
            sourceName: sourceName, sourceStartLine: startLine)
        let hash = MetalRenderer.fnv1a(composed)
        if let p = userShaderPipelines[hash] { return (p, hash) }
        if userShaderErrors[hash] != nil { return (nil, hash) }   // cached failure
        do {
            let lib: MTLLibrary
            if let cached = userShaderLibraries[hash] { lib = cached }
            else { lib = try device.makeLibrary(source: composed, options: nil); userShaderLibraries[hash] = lib }
            guard let vfn = lib.makeFunction(name: "ollin_user_vertex"),
                  let ffn = lib.makeFunction(name: "ollin_user_fragment") else {
                userShaderErrors[hash] = ShaderCompileError(
                    message: "\(sourceName):\(startLine): the shader has no "
                        + "shade(float2 uv, ShaderInfo info) function.", raw: "")
                return (nil, hash)
            }
            let desc = MTLRenderPipelineDescriptor()
            desc.vertexFunction = vfn
            desc.fragmentFunction = ffn
            desc.rasterSampleCount = 1
            desc.colorAttachments[0].pixelFormat = linearFormat
            let state = try device.makeRenderPipelineState(descriptor: desc)
            userShaderPipelines[hash] = state
            return (state, hash)
        } catch {
            let cleaned = MetalRenderer.cleanShaderDiagnostics(
                (error as NSError).localizedDescription, userLineOffset: offset,
                sourceName: sourceName, sourceStartLine: startLine)
            userShaderErrors[hash] = ShaderCompileError(
                message: cleaned, raw: (error as NSError).localizedDescription)
            return (nil, hash)
        }
    }

    /// Drop every cached user-shader library, pipeline, and error, so the next encode
    /// recompiles from source. Used on a framework-shader reload (the spliced library
    /// may have changed) and when OllinLive reloads a watched user `.metal` file.
    func invalidateUserShaderCaches() {
        userShaderLibraries.removeAll()
        userShaderPipelines.removeAll()
        userShaderErrors.removeAll()
        userShaderSources.removeAll()
        printedShaderErrorHashes.removeAll()
    }

    /// The user's MSL for a shader: the inline source, or the cached contents of its
    /// `.metal` resource (read once per path, re-read after an invalidation so an
    /// edited file hot-reloads).
    private func resolveUserShaderSource(_ shader: Shader) -> String {
        if !shader.source.isEmpty { return shader.source }
        guard !shader.resourcePath.isEmpty else { return "" }
        if let cached = userShaderSources[shader.resourcePath] { return cached }
        let content = (try? String(contentsOfFile: shader.resourcePath, encoding: .utf8)) ?? ""
        userShaderSources[shader.resourcePath] = content
        return content
    }

    /// A small linear-float lookup texture (256×1) for `gradientMap`, uploaded from
    /// baked straight-alpha samples. `rgba32Float` so the `[SIMD4<Float>]` uploads
    /// verbatim; tiny, so allocated per use rather than pooled.
    private func makeLUTTexture(_ samples: [SIMD4<Float>]) -> MTLTexture? {
        let desc = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba32Float, width: samples.count, height: 1, mipmapped: false)
        desc.usage = .shaderRead
        desc.storageMode = .shared
        guard let tex = device.makeTexture(descriptor: desc) else { return nil }
        samples.withUnsafeBytes {
            tex.replace(region: MTLRegionMake2D(0, 0, samples.count, 1), mipmapLevel: 0,
                        withBytes: $0.baseAddress!, bytesPerRow: samples.count * MemoryLayout<SIMD4<Float>>.stride)
        }
        return tex
    }

    /// `fb`'s persistent ping-pong slot, allocating both textures (and clearing them
    /// to transparent, so the very first frame's `previous` reads clean) on first use,
    /// a size change, or after the address was reused by a different layer.
    ///
    /// `fill` overrides the constant clear for a field whose starting state is not
    /// uniform: a multi-scale Turing field must begin as noise, because a constant
    /// field is a fixed point of its rule (every average equal, so no scale ever
    /// fires) and it would sit there forever.
    private func feedbackSlot(for fb: AnyObject, width: Int, height: Int,
                              restState: MTLClearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0),
                              fill: ((MTLTexture) -> Void)? = nil,
                              into cb: MTLCommandBuffer) -> FeedbackSlot? {
        let id = ObjectIdentifier(fb)
        if let slot = feedbackSlots[id], slot.owner === fb, slot.w == width, slot.h == height {
            return slot
        }
        guard let a = makeFloatResolve(width: width, height: height),
              let b = makeFloatResolve(width: width, height: height) else { return nil }
        // A freshly allocated pair starts at the owner's rest state (transparent for a
        // feedback layer, the sim's substrate for a SimField) rather than undefined.
        if let fill {
            fill(a)
            fill(b)
        } else {
            clearFloatTexture(a, color: restState, into: cb)
            clearFloatTexture(b, color: restState, into: cb)
        }
        let slot = FeedbackSlot(a: a, b: b, w: width, h: height, owner: fb)
        feedbackSlots[id] = slot
        return slot
    }

    /// The SSR temporal-history slot for `key`, allocating the ping-pong pair (cleared to
    /// zero, so the first frame's accumulation starts from a clean, reflection-free history) on
    /// first use or a size change (live half-res versus full-res export reallocates and
    /// reconverges rather than reading a mismatched slot). Allocating past a small budget
    /// first drops slots untouched this frame: call-site keys are static per binary, but a
    /// live-reload edit that moves the call's line orphans the old key, and an orphan should
    /// cost two textures at most briefly (a dropped-but-live slot only loses its history and
    /// reconverges).
    private func ssrHistorySlot(key: SSRSlotKey, width: Int, height: Int,
                                into cb: MTLCommandBuffer) -> SSRHistorySlot? {
        if let slot = ssrHistorySlots[key], slot.w == width, slot.h == height { return slot }
        if ssrHistorySlots.count >= 32 {
            for stale in ssrHistorySlots.keys where !ssrHistoryUsedThisFrame.contains(stale) {
                ssrHistorySlots.removeValue(forKey: stale)
            }
        }
        guard let a = makeFloatResolve(width: width, height: height),
              let b = makeFloatResolve(width: width, height: height) else { return nil }
        let clear = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)
        clearFloatTexture(a, color: clear, into: cb)
        clearFloatTexture(b, color: clear, into: cb)
        let slot = SSRHistorySlot(a: a, b: b, w: width, h: height)
        ssrHistorySlots[key] = slot
        return slot
    }

    /// `sf`'s persistent fluid slot, allocating the velocity and dye ping-pong pairs
    /// (cleared to a still, dye-free rest state) on first use, a size change, or after
    /// the address was reused by a different field. The fluid analogue of
    /// `feedbackSlot`, keeping two pairs instead of one.
    private func fluidSlot(for sf: AnyObject, width: Int, height: Int,
                           into cb: MTLCommandBuffer) -> FluidSlot? {
        let id = ObjectIdentifier(sf)
        if let slot = fluidSlots[id], slot.owner === sf, slot.w == width, slot.h == height {
            return slot
        }
        guard let velA = makeFloatResolve(width: width, height: height),
              let velB = makeFloatResolve(width: width, height: height),
              let dyeA = makeFloatResolve(width: width, height: height),
              let dyeB = makeFloatResolve(width: width, height: height) else { return nil }
        let rest = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)
        for tex in [velA, velB, dyeA, dyeB] { clearFloatTexture(tex, color: rest, into: cb) }
        let slot = FluidSlot(velA: velA, velB: velB, dyeA: dyeA, dyeB: dyeB,
                             w: width, h: height, owner: sf)
        fluidSlots[id] = slot
        return slot
    }

    /// Clear `tex` to `color` with an empty render pass (a render target has no
    /// blit fill-to-color), so a freshly allocated persistent texture starts clean
    /// rather than with undefined contents.
    func clearFloatTexture(_ tex: MTLTexture,
                                   color: MTLClearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0),
                                   into cb: MTLCommandBuffer) {
        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = tex
        pass.colorAttachments[0].loadAction = .clear
        pass.colorAttachments[0].clearColor = color
        pass.colorAttachments[0].storeAction = .store
        cb.makeRenderCommandEncoder(descriptor: pass)?.endEncoding()
    }

    /// Acquire an MSAA + resolve pair for a geometry target. Pooled: reuse the slot
    /// for this frame-ring index (safe: the frame semaphore gates slot reuse).
    private func acquireTargetTextures(width: Int, height: Int, pooled: Bool) -> (msaa: MTLTexture, resolve: MTLTexture)? {
        guard pooled else {
            guard let msaa = makeFloatMSAA(width: width, height: height, storage: .memoryless),
                  let resolve = makeFloatResolve(width: width, height: height) else { return nil }
            return (msaa, resolve)
        }
        let slot = targetTexNext; targetTexNext += 1
        var pool = targetTexPool[frameIndex]
        if slot < pool.count, pool[slot].w == width, pool[slot].h == height {
            return (pool[slot].msaa, pool[slot].resolve)
        }
        guard let msaa = makeFloatMSAA(width: width, height: height, storage: .memoryless),
              let resolve = makeFloatResolve(width: width, height: height) else { return nil }
        let entry = (msaa, resolve, width, height)
        if slot < pool.count { pool[slot] = entry } else { pool.append(entry) }
        targetTexPool[frameIndex] = pool
        return (msaa, resolve)
    }

    /// Acquire an MSAA + resolve depth pair for a 3D-holding render target, mirroring
    /// `acquireTargetTextures`. The MSAA buffer is memoryless (tile-only); the resolve
    /// is the sampleable single-sample `depth32Float` the `depth` layer reads from.
    private func acquireTargetDepth(width: Int, height: Int, pooled: Bool) -> (msaa: MTLTexture, resolve: MTLTexture)? {
        guard pooled else {
            guard let msaa = makeDepthMSAA(width: width, height: height),
                  let resolve = makeDepthResolve(width: width, height: height) else { return nil }
            return (msaa, resolve)
        }
        let slot = targetDepthNext; targetDepthNext += 1
        var pool = targetDepthPool[frameIndex]
        if slot < pool.count, pool[slot].w == width, pool[slot].h == height {
            return (pool[slot].msaa, pool[slot].resolve)
        }
        guard let msaa = makeDepthMSAA(width: width, height: height),
              let resolve = makeDepthResolve(width: width, height: height) else { return nil }
        let entry = (msaa, resolve, width, height)
        if slot < pool.count { pool[slot] = entry } else { pool.append(entry) }
        targetDepthPool[frameIndex] = pool
        return (msaa, resolve)
    }

    /// Acquire a single-sample linear-float intermediate for a filter result.
    func acquireFilterTexture(width: Int, height: Int, pooled: Bool) -> MTLTexture? {
        guard pooled else { return makeFilterTexture(width: width, height: height) }
        let slot = filterTexNext; filterTexNext += 1
        var pool = filterTexPool[frameIndex]
        if slot < pool.count, pool[slot].w == width, pool[slot].h == height { return pool[slot].tex }
        guard let tex = makeFilterTexture(width: width, height: height) else { return nil }
        let entry = (tex, width, height)
        if slot < pool.count { pool[slot] = entry } else { pool.append(entry) }
        filterTexPool[frameIndex] = pool
        return tex
    }

    /// A single-sample linear-float texture for an intermediate filter result:
    /// sampled, MPS-written, and fragment-rendered, so it carries all three usages.
    func makeFilterTexture(width: Int, height: Int) -> MTLTexture? {
        let desc = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: linearFormat, width: width, height: height, mipmapped: false)
        desc.usage = [.shaderRead, .shaderWrite, .renderTarget]
        desc.storageMode = .private
        return device.makeTexture(descriptor: desc)
    }

    /// Upload `drawer`'s recorded geometry and issue its draws into `encoder`,
    /// one per batch in call order so triangles and SDF shapes composite
    /// front-to-back as the sketch drew them. Shared by the on-screen and
    /// off-screen (export) paths.
    func encode(_ drawer: Drawer, viewport: SIMD2<Float>,
                        into encoder: MTLRenderCommandEncoder,
                        triangleBuffer: MTLBuffer?, sdfBuffer: MTLBuffer?,
                        imageBuffer: MTLBuffer?, glyphBuffer: MTLBuffer?,
                        pointBuffer: MTLBuffer?, meshBuffer: MTLBuffer?,
                        sdfGroupBuffer: MTLBuffer? = nil, sdfNodeBuffer: MTLBuffer? = nil,
                        sdf3DGroupBuffer: MTLBuffer? = nil, sdf3DNodeBuffer: MTLBuffer? = nil,
                        depthFormat: MTLPixelFormat?,
                        stencil hasStencil: Bool = false,
                        shadowMap: MTLTexture? = nil,
                        shadowCube: MTLTexture? = nil,
                        shadowAccel: MTLAccelerationStructure? = nil,
                        reflectAccel: MTLAccelerationStructure? = nil,
                        reflectGeoOffsets: MTLBuffer? = nil,
                        halfResField: (color: MTLTexture, depth: MTLTexture, region: SIMD4<Float>)? = nil,
                        halfResFieldShadow: MTLTexture? = nil,
                        deferredReflection: MTLTexture? = nil,
                        target passTarget: RenderTarget? = nil) {
        let vertices = drawer.vertices
        let instances = drawer.sdfInstances
        let imageVertices = drawer.imageVertices
        let glyphVertices = drawer.glyphVertices
        let points = drawer.points
        let meshVertices = drawer.meshVertices
        let groups = drawer.sdfGroups
        let nodes = drawer.sdfNodes
        let groups3D = drawer.sdf3DGroups
        let nodes3D = drawer.sdf3DNodes
        let batches = drawer.batches
        guard !batches.isEmpty else { return }

        if !vertices.isEmpty, let triangleBuffer {
            vertices.withUnsafeBytes { raw in
                triangleBuffer.contents().copyMemory(from: raw.baseAddress!, byteCount: raw.count)
            }
        }
        if !instances.isEmpty, let sdfBuffer {
            instances.withUnsafeBytes { raw in
                sdfBuffer.contents().copyMemory(from: raw.baseAddress!, byteCount: raw.count)
            }
        }
        if !imageVertices.isEmpty, let imageBuffer {
            imageVertices.withUnsafeBytes { raw in
                imageBuffer.contents().copyMemory(from: raw.baseAddress!, byteCount: raw.count)
            }
        }
        if !glyphVertices.isEmpty, let glyphBuffer {
            glyphVertices.withUnsafeBytes { raw in
                glyphBuffer.contents().copyMemory(from: raw.baseAddress!, byteCount: raw.count)
            }
        }
        if !points.isEmpty, let pointBuffer {
            points.withUnsafeBytes { raw in
                pointBuffer.contents().copyMemory(from: raw.baseAddress!, byteCount: raw.count)
            }
        }
        if !meshVertices.isEmpty, let meshBuffer {
            meshVertices.withUnsafeBytes { raw in
                meshBuffer.contents().copyMemory(from: raw.baseAddress!, byteCount: raw.count)
            }
        }
        if !groups.isEmpty, let sdfGroupBuffer {
            groups.withUnsafeBytes { raw in
                sdfGroupBuffer.contents().copyMemory(from: raw.baseAddress!, byteCount: raw.count)
            }
        }
        if !nodes.isEmpty, let sdfNodeBuffer {
            nodes.withUnsafeBytes { raw in
                sdfNodeBuffer.contents().copyMemory(from: raw.baseAddress!, byteCount: raw.count)
            }
        }
        if !groups3D.isEmpty, let sdf3DGroupBuffer {
            groups3D.withUnsafeBytes { raw in
                sdf3DGroupBuffer.contents().copyMemory(from: raw.baseAddress!, byteCount: raw.count)
            }
        }
        if !nodes3D.isEmpty, let sdf3DNodeBuffer {
            nodes3D.withUnsafeBytes { raw in
                sdf3DNodeBuffer.contents().copyMemory(from: raw.baseAddress!, byteCount: raw.count)
            }
        }

        var uniforms = Uniforms(viewport: viewport, clipDepth: 0,
                                batchTransformed: 0,
                                batchTransform: matrix_identity_float3x3)
        encoder.setVertexBytes(&uniforms, length: MemoryLayout<Uniforms>.stride, index: 1)

        // 3D camera constants for the points3D batches, bound once at index 2 —
        // distinct from the 2D Uniforms at index 1, so the 2D batches around a 3D
        // one are undisturbed. Built from the camera and the viewport's aspect.
        var uniforms3D: Uniforms3D? = nil
        if let camera = drawer.camera3D {
            var u3 = makeUniforms3D(drawer, camera: camera, viewport: viewport)
            encoder.setVertexBytes(&u3, length: MemoryLayout<Uniforms3D>.stride, index: 2)
            uniforms3D = u3   // the raymarch fragment also reads it (the ray + depth + step budget)
        }

        // 3D mesh lighting (per-frame), bound to the mesh fragment per mesh batch
        // below. `enabled` is 0 when the sketch set no light, so the mesh fragment
        // keeps the byte-identical normal-as-color path.
        var lighting = drawer.makeLighting()
        // Image-based lighting: when an environment baked successfully this frame (resolved
        // by the caller before this pass), light the physically-based materials through its
        // maps. Otherwise leave iblEnabled 0 — the flat-ambient path, byte-identical.
        if lighting.enabled != 0, drawer.environment != nil, currentIBL != nil {
            lighting.iblEnabled = 1
            // The user intensity times the per-environment auto-exposure normalization.
            lighting.iblIntensity = Float(drawer.environment?.intensity ?? 1) * currentIBLNormalization
            lighting.iblMaxMip = Float(currentIBLMaxMip)
            lighting.iblRotation = Float(drawer.environment?.rotation ?? 0)
        } else {
            lighting.iblEnabled = 0   // noLights() stays flat; no environment → flat ambient
        }
        // Skybox backdrop: when the environment shows as the scene's background, fill the
        // frame with it (a fullscreen view-ray cube sample) before the geometry, with depth
        // disabled, so the depth-tested meshes composite in front and a mirror's reflection
        // matches what's behind it. The per-batch loop resets the pipeline + depth state.
        var skyKey = PipelineKey.skybox(depth: depthFormat)
        if hasStencil { skyKey.stencilFormat = .stencil8 }
        if lighting.iblEnabled != 0, drawer.environment?.showsBackground == true,
           var skyUniforms = uniforms3D, let skyTex = currentIBLSkyboxTexture,
           let skyPipe = try? pipeline(skyKey) {
            encoder.setRenderPipelineState(skyPipe)
            // Always-pass, no write. The explicit state, not nil: the Metal
            // validation layer rejects a nil depth-stencil state.
            encoder.setDepthStencilState(noDepthState)
            encoder.setFragmentBytes(&skyUniforms, length: MemoryLayout<Uniforms3D>.stride, index: 0)
            // params.y is the auto-exposure-normalized intensity (shared with the lighting);
            // params.z the backdrop blur as an equirect mip LOD. The blur is the user's value
            // or auto — a gentle soft-focus at 1K easing to sharp at 4K (a magnified low-res
            // backdrop wants softening; the bicubic reconstruction keeps it un-blocky either way).
            let autoBlur = max(0, min(0.15, 0.15 * (4096 - Float(skyTex.width)) / 3072))
            let blur = drawer.environment?.backgroundBlur.map { Float($0) } ?? autoBlur
            var skyParams = SIMD4<Float>(lighting.iblRotation, lighting.iblIntensity, blur * 4.0, 0)
            encoder.setFragmentBytes(&skyParams, length: MemoryLayout<SIMD4<Float>>.stride, index: 1)
            encoder.setFragmentTexture(skyTex, index: 0)
            encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        }
        // Shadows only apply when the shadow pass actually populated a map / structure
        // (the render/image paths); the accumulation/texture paths pass nil, so clear the
        // caster index there and bind the 1×1 / dummy stand-ins so the fragment never
        // reads them. A directional/spot caster populates the 2D map, a point caster the
        // cube — or, on a ray-tracing device, the acceleration structure.
        // Clear the caster only when nothing can use it: a marched SDF field self-shadows
        // analytically (no map), so it keeps the caster index even when the map pass didn't
        // run. Meshes still see no shadow without a map (they'd sample the all-lit dummy).
        if shadowMap == nil && shadowCube == nil && shadowAccel == nil && drawer.sdf3DGroups.isEmpty {
            lighting.shadowLight = -1
        }
        // A ray-traced point caster: switch the fragment to the RT path (shadowKind 2) and
        // resolve the sketch's quality tier to a concrete ray count for this GPU.
        if shadowAccel != nil {
            lighting.shadowKind = 2
            lighting.shadowSamples = resolveShadowSamples(drawer.shadowQualitySetting)
        } else if lighting.shadowLight >= 0 && lighting.shadowKind == 0 {
            // A directional/spot 2D caster runs PCSS (soft shadows): it budgets texture taps,
            // not rays, and the count is hardware-independent (cheap samples on any GPU).
            lighting.shadowSamples = resolveShadowTaps2D(drawer.shadowQualitySetting)
        }
        // Ray-traced reflections: a physically-based metal traces the caster accel for its
        // reflection (replacing the IBL prefilter sample). The flag gates it; off → the
        // byte-identical IBL-prefilter path. The renderer owns the hardware check, so this is
        // set only when the shadow pass actually built a reflection accel on a tracing device.
        // When the pre-pass traced (and, live, accumulated) the reflection off-screen, the
        // fragments sample that texture by screen position instead of tracing inline (the
        // anti-aliased path); the scale is 1 while the layer renders at full resolution.
        if reflectAccel != nil { lighting.rtReflections = 1 }
        if deferredReflection != nil {
            lighting.rtReflectionDeferred = 1
            lighting.rtReflectionScale = 1.0
        }
        // A directional/spot caster has each field render into the 2D map (so meshes receive it
        // from there); a point/ray-traced caster has no map a field can render into, so the lit
        // mesh fragments resolve the cast another way. `fieldCasterCount` > 0 turns that on (only
        // for a point/RT caster with fields); 0 keeps the mesh path byte-identical.
        lighting.fieldCasterCount = resolveFieldCasterCount(lighting, drawer)
        // How they resolve it: sample a precomputed half-res field-shadow texture by screen
        // position (the live RenderQuality path) when one was rendered this frame, else the inline
        // per-pixel march (full-res / export, byte-identical). The viewport scales the screen uv.
        if halfResFieldShadow != nil {
            lighting.fieldShadowMode = 1
            lighting.fieldShadowScale = Float(resolveRaymarchScale(drawer.raymarchQualitySetting))
        }
        let shadowTexture = shadowMap ?? ensureDummyShadowMap()
        let shadowCubeTexture = shadowCube ?? ensureDummyPointShadowMap()
        // When the mesh fragments are compiled with RT shadows, an acceleration structure
        // is always part of their signature, so bind the real one this frame or a dummy
        // that's never traced (the fragment only traces it when shadowKind == 2).
        // Bind one acceleration structure at fragment buffer 3: the fragment traces it for
        // both the point shadow (shadowKind 2) and the reflection (rtReflections); when both
        // are active they're the same object, otherwise whichever is set (a never-traced dummy
        // when neither). The per-geometry offsets at buffer 7 feed the reflection hit fetch.
        let traceAccel = shadowAccel ?? reflectAccel
        let shadowAccelStructure = rayTracedShadows ? (traceAccel ?? ensureDummyShadowAccel()) : nil
        let geoOffsetsBuffer = rayTracedShadows ? (reflectGeoOffsets ?? ensureDummyGeoOffsets()) : nil

        // The strip must be bound whenever the SDF fragment runs (it references
        // the texture even for all-solid frames), so resolve it once per encode.
        let strip = gradientStripTexture(for: drawer.gradientRows)

        let vertexStride = MemoryLayout<OllinVertex>.stride
        let instanceStride = MemoryLayout<SDFInstance>.stride
        let groupStride = MemoryLayout<SDFGroupInstance>.stride
        let group3DStride = MemoryLayout<SDF3DGroupInstance>.stride
        let imageStride = MemoryLayout<OllinImageVertex>.stride
        let pointStride = MemoryLayout<OllinPoint>.stride
        let meshStride = MemoryLayout<OllinMeshVertex>.stride
        // On the half-res raymarch tier all fields composite in one upsample at the first field
        // batch; this flag skips the rest (their geometry already merged into the half-res target).
        var compositedHalfResFields = false
        for i in batches.indices {
            let batch = batches[i]
            let next = i + 1 < batches.count ? batches[i + 1] : nil
            // Each pass draws only its own batches: the main pass (passTarget nil)
            // skips target-tagged runs, and a target pass skips everything but its
            // own. `next` stays the globally-next batch so the buffer range is right.
            if batch.target !== passTarget { continue }
            // A clip batch without a stencil attachment can't draw (its pipeline
            // declares the stencil format); skip it, so a failed stencil allocation
            // degrades to unclipped drawing rather than a validation error.
            if !hasStencil, batch.kind == .clipPush || batch.kind == .clipPop { continue }
            // A retained `Batch` replay: hand the whole reference off before the
            // pipeline lookup (each of its inner runs resolves its own pipeline),
            // then restore this loop's uniforms binding and carry on.
            if batch.kind == .retained {
                if let handle = batch.retained {
                    encodeRetained(handle, reference: batch, drawer: drawer,
                                   loopUniforms: uniforms, into: encoder,
                                   depthFormat: depthFormat, hasStencil: hasStencil)
                }
                continue
            }
            // The pipeline for this batch's geometry kind, blend mode, *and* the
            // pass's depth format; built on first use of a combination. A mesh batch
            // selects its variant: wireframe (edges only) or textured (a material
            // texture). Skip the batch if it can't be built (never expected; same shaders).
            let meshWireframe = batch.kind == .mesh3D && batch.meshWireframe
            let meshGrid = batch.kind == .mesh3D && batch.meshGrid
            let meshMatcap = batch.kind == .mesh3D && !batch.meshWireframe && !meshGrid && batch.matcap != nil
            let meshTextured = batch.kind == .mesh3D && !batch.meshWireframe && !meshGrid && !meshMatcap && batch.material?.texture != nil
            var pipelineKey = PipelineKey.forBatch(batch.kind, batch.blendMode, depth: depthFormat,
                                                   textured: meshTextured, wireframe: meshWireframe,
                                                   matcap: meshMatcap, grid: meshGrid)
            // A stencil-carrying pass (clipping active) needs every pipeline in it
            // to declare the stencil format, clipped or not.
            if hasStencil { pipelineKey.stencilFormat = .stencil8 }
            guard let state = try? pipeline(pipelineKey) else { continue }
            // In a depth pass (active camera): 3D batches z-test + write depth. A 2D
            // batch that opted into a depth (`depth(at:)`) does too: its constant
            // clip-z is fed to the 2D vertex shader so it occludes / is occluded by
            // 3D geometry, while a plain 2D batch leaves depth alone (clip-z 0) and
            // composites over in draw order. With no depth attachment the encoder
            // keeps its default state, so 2D-only frames are byte-identical to before.
            // A stencil pass layers the clip test on top: a content batch at a clip
            // level tests `equal` against it (the reference value), the clip push/pop
            // batches raise and lower it, and level-0 batches keep the plain states.
            if depthFormat != nil || hasStencil {
                // 3D splats, a depth-scene backdrop, and any depth-placed 2D batch
                // z-test + write; a plain 2D batch leaves depth alone. The depth
                // scene and 3D batches set their own clip-z (a fragment SV_Depth and
                // the camera projection), so only plain 2D batches feed `clipDepth`.
                let wantsDepth = depthFormat != nil && (batch.kind == .points3D || batch.kind == .mesh3D
                    || batch.kind == .depthScene || batch.kind == .sdfGroup3D || batch.depth != nil)
                if hasStencil {
                    switch batch.kind {
                    case .clipPush:
                        // Raise the level where the enclosing level passes, so nested
                        // clips intersect. Depth is untouched.
                        encoder.setDepthStencilState(
                            clipDepthStencilState(ClipStateKey(depth: .always, stencil: .push)))
                        encoder.setStencilReferenceValue(UInt32(max(0, batch.clipLevel - 1)))
                    case .clipPop:
                        // Lower the popped level back, everywhere it was raised.
                        encoder.setDepthStencilState(
                            clipDepthStencilState(ClipStateKey(depth: .always, stencil: .pop)))
                        encoder.setStencilReferenceValue(UInt32(batch.clipLevel))
                    default:
                        if batch.clipLevel > 0 {
                            let depthMode: ClipStateKey.Depth = meshGrid ? .testNoWrite
                                : (wantsDepth ? .test : .always)
                            encoder.setDepthStencilState(
                                clipDepthStencilState(ClipStateKey(depth: depthMode, stencil: .equal)))
                            encoder.setStencilReferenceValue(UInt32(batch.clipLevel))
                        } else if depthFormat != nil {
                            encoder.setDepthStencilState(meshGrid ? depthTestNoWriteState
                                                         : (wantsDepth ? depthTestState : noDepthState))
                        } else {
                            // Unclipped content in a stencil-only pass: back to
                            // always-pass (nil is rejected by the validation layer).
                            encoder.setDepthStencilState(noDepthState)
                        }
                    }
                } else {
                    // The grid z-tests but doesn't write depth (occluded by the scene, occludes nothing).
                    encoder.setDepthStencilState(meshGrid ? depthTestNoWriteState
                                                 : (wantsDepth ? depthTestState : noDepthState))
                }
                if depthFormat != nil,
                   batch.kind != .points3D && batch.kind != .mesh3D && batch.kind != .depthScene && batch.kind != .sdfGroup3D {
                    uniforms.clipDepth = batch.depth ?? 0
                    encoder.setVertexBytes(&uniforms, length: MemoryLayout<Uniforms>.stride, index: 1)
                }
            }
            switch batch.kind {
            case .triangles, .fringe:   // .fringe shares the triangle vertex buffer; only the pipeline differs (coverage rides in `aa.x`)
                let end = next?.vertexStart ?? vertices.count
                let count = end - batch.vertexStart
                guard count > 0, let triangleBuffer else { continue }
                encoder.setRenderPipelineState(state)
                encoder.setVertexBuffer(triangleBuffer, offset: batch.vertexStart * vertexStride, index: 0)
                encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: count)
            case .sdf:
                let end = next?.instanceStart ?? instances.count
                let count = end - batch.instanceStart
                guard count > 0, let sdfBuffer else { continue }
                encoder.setRenderPipelineState(state)
                encoder.setVertexBuffer(sdfBuffer, offset: batch.instanceStart * instanceStride, index: 0)
                // Rebind per batch — an image/glyph batch in between binds its own
                // texture at the same index.
                encoder.setFragmentTexture(strip, index: 0)
                encoder.setFragmentSamplerState(imageSampler, index: 0)
                encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 6, instanceCount: count)
            case .sdfGroup:
                // Composed SDF fields: each group is a covering quad whose fragment runs
                // the node VM. The group buffer is offset to this batch's first group; the
                // node buffer is bound whole to the fragment (groups carry an absolute
                // nodeStart), which walks [nodeStart, nodeStart + nodeCount).
                let end = next?.sdfGroupStart ?? groups.count
                let count = end - batch.sdfGroupStart
                guard count > 0, let sdfGroupBuffer, let sdfNodeBuffer else { continue }
                encoder.setRenderPipelineState(state)
                encoder.setVertexBuffer(sdfGroupBuffer, offset: batch.sdfGroupStart * groupStride, index: 0)
                encoder.setFragmentBuffer(sdfNodeBuffer, offset: 0, index: 0)
                // The gradient strip + sampler (a gradient `fill`/`stroke` paints the merged
                // field/outline by field position); bound at 0 like the per-shape SDF path.
                encoder.setFragmentTexture(strip, index: 0)
                encoder.setFragmentSamplerState(imageSampler, index: 0)
                encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 6, instanceCount: count)
            case .sdfGroup3D:
                // Half-res tier: the fields were already sphere-traced into the half-res
                // color+depth in the pre-pass, and all of them composite in one upsample at
                // the first field batch (depth still decides mesh occlusion), so skip the rest.
                if let hf = halfResField {
                    if compositedHalfResFields { continue }
                    compositedHalfResFields = true
                    var upKey = PipelineKey.raymarchUpsample(depth: depthFormat ?? depthPixelFormat)
                    if hasStencil { upKey.stencilFormat = .stencil8 }
                    guard let upState = try? pipeline(upKey) else { continue }
                    encoder.setRenderPipelineState(upState)
                    var region = hf.region
                    encoder.setFragmentBytes(&region, length: MemoryLayout<SIMD4<Float>>.stride, index: 0)
                    encoder.setFragmentTexture(hf.color, index: 0)
                    encoder.setFragmentTexture(hf.depth, index: 1)
                    encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
                    continue
                }
                // Raymarched composed 3D fields: one instanced fullscreen triangle per
                // field, the fragment sphere-tracing it and writing depth so it z-tests
                // against the meshes (state set above). The group buffer is offset to this
                // batch's first field; the node buffer is bound whole (fields carry an
                // absolute nodeStart). Reuses the mesh lighting / material finish / shadow
                // bindings, plus the camera (with its inverse view-projection) for the ray.
                let end = next?.sdf3DGroupStart ?? groups3D.count
                let count = end - batch.sdf3DGroupStart
                guard count > 0, let sdf3DGroupBuffer, let sdf3DNodeBuffer,
                      var u3 = uniforms3D else { continue }
                encoder.setRenderPipelineState(state)
                encoder.setFragmentBuffer(sdf3DGroupBuffer, offset: batch.sdf3DGroupStart * group3DStride, index: 0)
                encoder.setFragmentBuffer(sdf3DNodeBuffer, offset: 0, index: 1)
                encoder.setFragmentBytes(&lighting, length: MemoryLayout<OllinLighting>.stride, index: 2)
                var finish3D = batch.finish
                encoder.setFragmentBytes(&finish3D, length: MemoryLayout<OllinMaterial>.stride, index: 3)
                encoder.setFragmentBytes(&u3, length: MemoryLayout<Uniforms3D>.stride, index: 4)
                encoder.setFragmentTexture(shadowTexture, index: 1)
                encoder.setFragmentTexture(shadowCubeTexture, index: 2)
                if let shadowSampler { encoder.setFragmentSamplerState(shadowSampler, index: 1) }
                if let shadowCubeSampler { encoder.setFragmentSamplerState(shadowCubeSampler, index: 2) }
                // The gradient strip + sampler (a gradient `fill` paints the field by screen
                // position); bound at 0, free here since the shadow textures take 1/2.
                encoder.setFragmentTexture(strip, index: 0)
                encoder.setFragmentSamplerState(imageSampler, index: 0)
                // The image-based-lighting maps (tex 4/5/6), so a field under an environment
                // takes the same ambient a mesh does; never-sampled stand-ins otherwise
                // (`lighting.iblEnabled` gates the read), like the mesh path below.
                if iblPlaceholderCube == nil { iblPlaceholderCube = makeCubeTexture(face: 1, mipped: false) }
                encoder.setFragmentTexture(currentIBLIrradiance ?? iblPlaceholderCube, index: 4)
                encoder.setFragmentTexture(currentIBLPrefilter ?? iblPlaceholderCube, index: 5)
                encoder.setFragmentTexture(iblBRDFLUTTexture ?? strip, index: 6)
                // The mesh acceleration structure at buffer 5 so a marched field receives a mesh's
                // cast shadow under a ray-traced point caster (it traces toward the light, the
                // reverse of the cast). A dummy when shadowKind != 2, never traced; the cube path
                // (shadowKind 1) needs nothing, its cube + sampler are already bound at 2.
                if let accel = shadowAccelStructure {
                    encoder.useResource(accel, usage: .read, stages: .fragment)
                    encoder.setFragmentAccelerationStructure(accel, bufferIndex: 5)
                }
                // The reflection-trace inputs (buffers 6/7), read only under `lighting.rtReflections`
                // (which implies meshes exist, so `meshBuffer` is real there); the offsets dummy
                // stands in for both on a mesh-less RT frame so the bindings are never missing.
                if rayTracedShadows {
                    if let verts = meshBuffer ?? geoOffsetsBuffer {
                        encoder.setFragmentBuffer(verts, offset: 0, index: 6)
                    }
                    if let geoOffsetsBuffer {
                        encoder.setFragmentBuffer(geoOffsetsBuffer, offset: 0, index: 7)
                    }
                }
                encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3, instanceCount: count)
            case .image:
                let end = next?.imageStart ?? imageVertices.count
                let count = end - batch.imageStart
                guard count > 0, let imageBuffer, let source = batch.image,
                      let texture = source.texture(for: device) else { continue }
                encoder.setRenderPipelineState(state)
                encoder.setVertexBuffer(imageBuffer, offset: batch.imageStart * imageStride, index: 0)
                encoder.setFragmentTexture(texture, index: 0)
                encoder.setFragmentSamplerState(imageSampler, index: 0)
                encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: count)
            case .glyphAtlas:
                let end = next?.glyphStart ?? glyphVertices.count
                let count = end - batch.glyphStart
                guard count > 0, let glyphBuffer, let atlas = batch.atlas,
                      let texture = atlas.texture(for: device) else { continue }
                encoder.setRenderPipelineState(state)
                encoder.setVertexBuffer(glyphBuffer, offset: batch.glyphStart * imageStride, index: 0)
                encoder.setFragmentTexture(texture, index: 0)
                encoder.setFragmentSamplerState(imageSampler, index: 0)
                encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: count)
            case .particles:
                // GPU-resident particle buffer (written by a compute dispatch this
                // frame), drawn as one instanced disc per particle. Uniforms are
                // already bound at index 1; the particle struct is read at index 0.
                guard batch.particleCount > 0,
                      let buffer = batch.particleBuffer?.metalBuffer(for: device) else { continue }
                encoder.setRenderPipelineState(state)
                encoder.setVertexBuffer(buffer, offset: 0, index: 0)
                encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 6,
                                       instanceCount: batch.particleCount)
            case .points3D:
                // 3D point-cloud splats: one instanced camera-facing quad per point,
                // projected by the camera constants bound at index 2 above. Each draw
                // is a run in the per-frame `points` array (count from the next
                // batch's start), like the SDF/triangle paths.
                let end = next?.pointStart ?? points.count
                let count = end - batch.pointStart
                guard count > 0, let pointBuffer, drawer.camera3D != nil else { continue }
                encoder.setRenderPipelineState(state)
                encoder.setVertexBuffer(pointBuffer, offset: batch.pointStart * pointStride, index: 0)
                encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 6, instanceCount: count)
            case .mesh3D:
                // Solid 3D mesh: a flat triangle list (indices already expanded), drawn
                // through the camera constants bound at index 2. Depth-tested + writing
                // (state set above), so meshes occlude each other and the point clouds
                // / depth scene in the same pass.
                let end = next?.meshStart ?? meshVertices.count
                let count = end - batch.meshStart
                guard count > 0, let meshBuffer, drawer.camera3D != nil else { continue }
                // A textured or matcap mesh needs its texture at fragment index 0; if it
                // can't be built, skip rather than draw against the wrong pipeline.
                if meshTextured {
                    guard let texture = batch.material?.texture?.texture(for: device) else { continue }
                    encoder.setFragmentTexture(texture, index: 0)
                    encoder.setFragmentSamplerState(imageSampler, index: 0)
                } else if meshMatcap {
                    guard let texture = batch.matcap?.texture(for: device) else { continue }
                    encoder.setFragmentTexture(texture, index: 0)
                    encoder.setFragmentSamplerState(imageSampler, index: 0)
                }
                encoder.setRenderPipelineState(state)
                encoder.setVertexBuffer(meshBuffer, offset: batch.meshStart * meshStride, index: 0)
                // Lighting, the shadow map, and the material finish feed only the lit
                // solid/textured fragments — the wireframe and matcap pipelines declare
                // none of them (matcap bakes its lighting into the texture), and the grid
                // overlay is unlit (it binds only its own params).
                if meshGrid {
                    var grid = batch.gridParams
                    encoder.setFragmentBytes(&grid, length: MemoryLayout<OllinGridParams>.stride, index: 0)
                } else if !meshWireframe && !meshMatcap {
                    // Shadow maps at fragment textures 1 (2D, directional/spot) and 2
                    // (cube, point): the real map when that caster is active, a 1×1 dummy
                    // otherwise (`lighting.shadowLight`/`shadowKind` gate the sampling).
                    // Both share the one comparison sampler (lessEqual hardware PCF).
                    encoder.setFragmentTexture(shadowTexture, index: 1)
                    encoder.setFragmentTexture(shadowCubeTexture, index: 2)
                    // 2D map: comparison sampler (hardware PCF). Cube: plain sampler (it
                    // stores linear distance, read with `.sample`, manual PCF in-shader).
                    if let shadowSampler { encoder.setFragmentSamplerState(shadowSampler, index: 1) }
                    if let shadowCubeSampler { encoder.setFragmentSamplerState(shadowCubeSampler, index: 2) }
                    encoder.setFragmentBytes(&lighting, length: MemoryLayout<OllinLighting>.stride, index: 0)
                    // The surface finish (shading model + Blinn-Phong/rim/subsurface/
                    // iridescence) is one uniform bound per batch.
                    var finish = batch.finish
                    encoder.setFragmentBytes(&finish, length: MemoryLayout<OllinMaterial>.stride, index: 1)
                    // Ray-traced point shadows: the fragment traces this acceleration
                    // structure at buffer 3 (a dummy when shadowKind != 2, never traced).
                    if let accel = shadowAccelStructure {
                        encoder.useResource(accel, usage: .read, stages: .fragment)
                        encoder.setFragmentAccelerationStructure(accel, bufferIndex: 3)
                    }
                    // Ray-traced reflections: the flat mesh buffer (whole, offset 0, for absolute
                    // indexing) at fragment buffer 6 and the per-geometry base-vertex offsets at 7,
                    // so a physically-based fragment can fetch a reflection hit's triangle. Bound
                    // whenever the fragment is RT-compiled (a dummy offsets buffer when reflections
                    // are off; `lighting.rtReflections` gates the read). Both feed `ollin_rt_reflection`.
                    if rayTracedShadows {
                        encoder.setFragmentBuffer(meshBuffer, offset: 0, index: 6)
                    }
                    if let geoOffsetsBuffer {
                        encoder.setFragmentBuffer(geoOffsetsBuffer, offset: 0, index: 7)
                    }
                    // The SDF field group + nodes (buffers 4/5) so a lit mesh can march them
                    // toward a point/ray-traced caster (a field's cast shadow). Always allocated
                    // (min one element) for a 3D frame; `lighting.fieldCasterCount` gates the
                    // march, so this is inert (and byte-identical) when there are no fields.
                    if let sdf3DGroupBuffer { encoder.setFragmentBuffer(sdf3DGroupBuffer, offset: 0, index: 4) }
                    if let sdf3DNodeBuffer { encoder.setFragmentBuffer(sdf3DNodeBuffer, offset: 0, index: 5) }
                    // The half-res field-shadow texture (the live RenderQuality path) the fragment
                    // samples when `lighting.fieldShadowMode == 1`; a never-sampled stand-in (the
                    // gradient `strip`) otherwise, so the declared texture is always bound.
                    encoder.setFragmentTexture(halfResFieldShadow ?? strip, index: 3)
                    // The image-based-lighting maps the physically-based fragment samples when
                    // `lighting.iblEnabled == 1`: the irradiance + prefiltered cubes (tex 4/5)
                    // and the BRDF LUT (tex 6). Never-sampled stand-ins (a 1×1 cube, the
                    // gradient strip) otherwise, so the declared textures are always bound.
                    if iblPlaceholderCube == nil { iblPlaceholderCube = makeCubeTexture(face: 1, mipped: false) }
                    encoder.setFragmentTexture(currentIBLIrradiance ?? iblPlaceholderCube, index: 4)
                    encoder.setFragmentTexture(currentIBLPrefilter ?? iblPlaceholderCube, index: 5)
                    encoder.setFragmentTexture(iblBRDFLUTTexture ?? strip, index: 6)
                    // The pre-traced reflection layer (tex 7) when the deferred path is on;
                    // a never-sampled stand-in otherwise (`rtReflectionDeferred` gates the
                    // read). Only part of the RT-compiled fragment signature.
                    if rayTracedShadows {
                        encoder.setFragmentTexture(deferredReflection ?? strip, index: 7)
                    }
                }
                encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: count)
            case .depthScene:
                // A backdrop quad (in `imageVertices`, like an image) whose fragment
                // also writes per-pixel depth from the depth map: color at texture 0,
                // depth at texture 1. The depth-test state (set above) writes the
                // fragment's SV_Depth so 2D drawn after composites against it.
                let end = next?.imageStart ?? imageVertices.count
                let count = end - batch.imageStart
                // Depth comes from either a metric float map (meters) or the
                // normalized gray map; the fragment branches on the quad's tint.a.
                let depthTex = batch.metricDepth?.texture(for: device)
                    ?? batch.depthImage?.texture(for: device)
                guard count > 0, let imageBuffer, let color = batch.image,
                      let colorTex = color.texture(for: device), let depthTex
                else { continue }
                encoder.setRenderPipelineState(state)
                encoder.setVertexBuffer(imageBuffer, offset: batch.imageStart * imageStride, index: 0)
                encoder.setFragmentTexture(colorTex, index: 0)
                encoder.setFragmentTexture(depthTex, index: 1)
                encoder.setFragmentSamplerState(imageSampler, index: 0)
                encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: count)
            case .clipPush:
                // The clip region's fill triangles, drawn stencil-only (color masked
                // off; the increment state + reference were set above). Rides the
                // triangle buffer like a `.triangles` run.
                let end = next?.vertexStart ?? vertices.count
                let count = end - batch.vertexStart
                guard count > 0, let triangleBuffer else { continue }
                encoder.setRenderPipelineState(state)
                encoder.setVertexBuffer(triangleBuffer, offset: batch.vertexStart * vertexStride, index: 0)
                encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: count)
            case .clipPop:
                // One fullscreen triangle decrementing the popped level (state +
                // reference set above); the vertex stage synthesizes its corners,
                // so no buffer is bound.
                encoder.setRenderPipelineState(state)
                encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
            case .retained:
                continue   // handed off before the pipeline lookup above
            }
        }
    }

    /// Replay a recorded `Batch` from its own persistent buffers: the retained
    /// sibling of the per-batch arms in `encode` above, restricted to the kinds a
    /// recording can hold (2D geometry, images, atlas text, SDF groups, point
    /// clouds). The reference batch supplies the draw-time context: its CTM rides
    /// the flag-gated `batchTransform` uniform (identity leaves the flag 0, so an
    /// untransformed replay renders byte-identically to the recording), and its
    /// clip level / 2D depth apply to every inner run. Inner runs keep their own
    /// recorded blend modes. On exit the loop's uniforms binding is restored, so
    /// the batches after the replay are undisturbed.
    private func encodeRetained(_ handle: Batch, reference: GeometryBatch,
                                drawer: Drawer, loopUniforms: Uniforms,
                                into encoder: MTLRenderCommandEncoder,
                                depthFormat: MTLPixelFormat?, hasStencil: Bool) {
        let resources = handle.gpuResources(for: device)
        var u = loopUniforms
        if depthFormat != nil { u.clipDepth = reference.depth ?? 0 }
        if let t = reference.retainedTransform {
            u.batchTransformed = 1
            u.batchTransform = t
        }
        encoder.setVertexBytes(&u, length: MemoryLayout<Uniforms>.stride, index: 1)

        let vertexStride = MemoryLayout<OllinVertex>.stride
        let instanceStride = MemoryLayout<SDFInstance>.stride
        let groupStride = MemoryLayout<SDFGroupInstance>.stride
        let imageStride = MemoryLayout<OllinImageVertex>.stride
        let pointStride = MemoryLayout<OllinPoint>.stride
        let inner = handle.innerBatches
        for j in inner.indices {
            let run = inner[j]
            let next = j + 1 < inner.count ? inner[j + 1] : nil
            var key = PipelineKey.forBatch(run.kind, run.blendMode, depth: depthFormat)
            if hasStencil { key.stencilFormat = .stencil8 }
            guard let state = try? pipeline(key) else { continue }
            // Depth/stencil per the main loop's rules, at the reference batch's
            // clip level and depth: point-cloud runs z-test + write, 2D runs do
            // only when the replay was depth-placed. Untouched when the pass
            // carries neither attachment (the byte-identical rule).
            if depthFormat != nil || hasStencil {
                let wantsDepth = depthFormat != nil
                    && (run.kind == .points3D || reference.depth != nil)
                if hasStencil, reference.clipLevel > 0 {
                    encoder.setDepthStencilState(clipDepthStencilState(
                        ClipStateKey(depth: wantsDepth ? .test : .always, stencil: .equal)))
                    encoder.setStencilReferenceValue(UInt32(reference.clipLevel))
                } else if depthFormat != nil {
                    encoder.setDepthStencilState(wantsDepth ? depthTestState : noDepthState)
                } else {
                    encoder.setDepthStencilState(noDepthState)
                }
            }
            switch run.kind {
            case .triangles, .fringe:
                let end = next?.vertexStart ?? handle.vertices.count
                let count = end - run.vertexStart
                guard count > 0, let buffer = resources.triangle else { continue }
                encoder.setRenderPipelineState(state)
                encoder.setVertexBuffer(buffer, offset: run.vertexStart * vertexStride, index: 0)
                encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: count)
            case .sdf:
                let end = next?.instanceStart ?? handle.sdfInstances.count
                let count = end - run.instanceStart
                guard count > 0, let buffer = resources.sdf, let strip = resources.strip else { continue }
                encoder.setRenderPipelineState(state)
                encoder.setVertexBuffer(buffer, offset: run.instanceStart * instanceStride, index: 0)
                // The batch's own strip: recorded instances carry handle-relative
                // gradient rows. Later frame batches rebind theirs, like after an
                // image batch.
                encoder.setFragmentTexture(strip, index: 0)
                encoder.setFragmentSamplerState(imageSampler, index: 0)
                encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 6, instanceCount: count)
            case .sdfGroup:
                let end = next?.sdfGroupStart ?? handle.sdfGroups.count
                let count = end - run.sdfGroupStart
                guard count > 0, let groupBuffer = resources.sdfGroup,
                      let nodeBuffer = resources.sdfNode, let strip = resources.strip else { continue }
                encoder.setRenderPipelineState(state)
                encoder.setVertexBuffer(groupBuffer, offset: run.sdfGroupStart * groupStride, index: 0)
                encoder.setFragmentBuffer(nodeBuffer, offset: 0, index: 0)
                encoder.setFragmentTexture(strip, index: 0)
                encoder.setFragmentSamplerState(imageSampler, index: 0)
                encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 6, instanceCount: count)
            case .image:
                let end = next?.imageStart ?? handle.imageVertices.count
                let count = end - run.imageStart
                guard count > 0, let buffer = resources.image, let source = run.image,
                      let texture = source.texture(for: device) else { continue }
                encoder.setRenderPipelineState(state)
                encoder.setVertexBuffer(buffer, offset: run.imageStart * imageStride, index: 0)
                encoder.setFragmentTexture(texture, index: 0)
                encoder.setFragmentSamplerState(imageSampler, index: 0)
                encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: count)
            case .glyphAtlas:
                let end = next?.glyphStart ?? handle.glyphVertices.count
                let count = end - run.glyphStart
                guard count > 0, let buffer = resources.glyph, let atlas = run.atlas,
                      let texture = atlas.texture(for: device) else { continue }
                encoder.setRenderPipelineState(state)
                encoder.setVertexBuffer(buffer, offset: run.glyphStart * imageStride, index: 0)
                encoder.setFragmentTexture(texture, index: 0)
                encoder.setFragmentSamplerState(imageSampler, index: 0)
                encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: count)
            case .points3D:
                // Recorded world-space splats replay through whatever camera is
                // active this frame (Uniforms3D is already bound at index 2 when
                // one is); without a camera there's nothing to project, like a
                // live drawPointCloud. The replay CTM is 2D-only, so it doesn't
                // apply here.
                let end = next?.pointStart ?? handle.points.count
                let count = end - run.pointStart
                guard count > 0, let buffer = resources.point, drawer.camera3D != nil else { continue }
                encoder.setRenderPipelineState(state)
                encoder.setVertexBuffer(buffer, offset: run.pointStart * pointStride, index: 0)
                encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 6, instanceCount: count)
            default:
                continue   // unsupported kinds are gated out at record time
            }
        }

        // Restore the loop's uniforms binding for the batches after the replay.
        var restore = loopUniforms
        encoder.setVertexBytes(&restore, length: MemoryLayout<Uniforms>.stride, index: 1)
    }

    /// Encode the frame's recorded compute dispatches into one compute encoder,
    /// ahead of the geometry render pass in the *same* command buffer — so a
    /// simulation step and the draw that reads its output stay ordered within the
    /// frame (Metal's intra-command-buffer hazard tracking inserts the dependency).
    /// The standard `OllinComputeUniforms` are bound at index 10 (with this
    /// dispatch's thread count as `particleCount`) and the custom params, if any, at
    /// index 11; the kernel's own buffers bind at 0…9. Threadgroup size comes from
    /// the pipeline, dispatched non-uniformly so the count needn't be a multiple.
    func encodeCompute(_ drawer: Drawer, into commandBuffer: MTLCommandBuffer) {
        guard !drawer.dispatches.isEmpty,
              let encoder = commandBuffer.makeComputeCommandEncoder() else { return }
        for dispatch in drawer.dispatches {
            guard dispatch.threadCount > 0,
                  let state = try? computePipeline(for: dispatch.kernel) else { continue }
            encoder.setComputePipelineState(state)
            for (index, bindable) in dispatch.buffers.enumerated() {
                encoder.setBuffer(bindable?.metalBuffer(for: device), offset: 0, index: index)
            }
            for (index, bindable) in dispatch.textures.enumerated() {
                encoder.setTexture(bindable?.metalTexture(for: device), index: index)
            }
            var uniforms = drawer.computeUniforms
            uniforms.particleCount = UInt32(dispatch.threadCount)
            encoder.setBytes(&uniforms, length: MemoryLayout<OllinComputeUniforms>.stride, index: 10)
            if !dispatch.params.isEmpty {
                dispatch.params.withUnsafeBytes {
                    encoder.setBytes($0.baseAddress!, length: $0.count, index: 11)
                }
            }
            // Threadgroup shaped to the grid: the execution width along x, the rest
            // of the budget along y. A 1-D buffer dispatch (height 1) collapses to
            // the old `width × 1`; a 2-D texture dispatch tiles in both axes.
            // `dispatchThreads` handles a grid that isn't a multiple of the group.
            let tew = state.threadExecutionWidth
            let groupWidth = max(1, min(dispatch.gridWidth, tew))
            let groupHeight = max(1, min(dispatch.gridHeight, state.maxTotalThreadsPerThreadgroup / tew))
            encoder.dispatchThreads(
                MTLSize(width: dispatch.gridWidth, height: dispatch.gridHeight, depth: 1),
                threadsPerThreadgroup: MTLSize(width: groupWidth, height: groupHeight, depth: 1))
        }
        encoder.endEncoding()
    }

    /// Execute this frame's recorded compute dispatches *without* rendering geometry —
    /// for headless drivers advancing a stateful sim (a `Simulation`, a ping-pong
    /// `ComputeTexture`) through frames they don't capture: the frames before the one
    /// being grabbed, and `--skip` warmup. The live window and a captured frame run
    /// the steps as part of their full render, but an *un*-captured frame otherwise
    /// records its dispatches and drops them, so the sim never evolves on the GPU.
    /// This runs just the compute, in its own command buffer (no geometry pass, no
    /// readback), so the GPU-resident state carries forward to the next frame at a
    /// fraction of a full render's cost. A no-op when nothing was recorded.
    func stepCompute(_ drawer: Drawer) {
        guard !drawer.dispatches.isEmpty,
              let commandBuffer = commandQueue.makeCommandBuffer() else { return }
        encodeCompute(drawer, into: commandBuffer)
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()
    }

    /// The gradient strip texture holding `rows` (one baked ramp per row),
    /// reused while the rows are unchanged and rebuilt — as a fresh texture, see
    /// `gradientStrip` — when they differ. With no gradients in the frame a
    /// 1-row placeholder keeps the SDF fragment's texture argument valid.
    func gradientStripTexture(for rows: [[UInt8]]) -> MTLTexture? {
        if let existing = gradientStrip, rows == gradientStripRows { return existing }
        guard let texture = MetalRenderer.makeGradientStrip(device: device, rows: rows) else { return nil }
        gradientStrip = texture
        gradientStripRows = rows
        return texture
    }

    /// Bake `rows` into a strip texture. The shared builder behind the frame's
    /// cached strip above and each retained `Batch`'s own strip (a batch's SDF
    /// instances carry handle-relative row indices, so it resolves them against
    /// its own bake, never the frame's). A pure function of its inputs, so it
    /// stays callable off the main actor.
    nonisolated static func makeGradientStrip(device: MTLDevice, rows: [[UInt8]]) -> MTLTexture? {
        let height = max(rows.count, 1)
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba8Unorm_srgb, width: BakedGradient.width,
            height: height, mipmapped: false)
        descriptor.usage = .shaderRead
        guard let texture = device.makeTexture(descriptor: descriptor) else { return nil }

        let bytesPerRow = BakedGradient.width * 4
        var flat: [UInt8] = []
        flat.reserveCapacity(bytesPerRow * height)
        for row in rows { flat.append(contentsOf: row) }
        if rows.isEmpty { flat = [UInt8](repeating: 0, count: bytesPerRow) }
        flat.withUnsafeBytes { raw in
            texture.replace(region: MTLRegionMake2D(0, 0, BakedGradient.width, height),
                            mipmapLevel: 0, withBytes: raw.baseAddress!,
                            bytesPerRow: bytesPerRow)
        }
        return texture
    }
}
