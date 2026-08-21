// MetalRenderer, the render-target factory half: the linear-float MSAA color and
// depth targets, the shadow and reflection pre-pass encoders, the quality-tier
// resolution (whose override knobs are stored properties on the type in
// MetalRenderer.swift), and the gradient LUT strips.

import Foundation
import Metal
import MetalKit
import simd
import CoreGraphics
import COllinShaders

extension MetalRenderer {
    // MARK: Render targets

    /// A linear-float MSAA color target. `storageMode` is `.memoryless` for the
    /// transient per-frame targets (the samples live only in tile memory, never
    /// backed by DRAM, since the frame clears each time) and `.private` for the
    /// accumulation target (its samples must persist across frames).
    func makeFloatMSAA(width: Int, height: Int, storage: MTLStorageMode) -> MTLTexture? {
        let desc = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: linearFormat, width: width, height: height, mipmapped: false)
        desc.textureType = .type2DMultisample
        desc.sampleCount = sampleCount
        desc.usage = .renderTarget
        desc.storageMode = storage
        return device.makeTexture(descriptor: desc)
    }

    /// A multisample depth target for a 3D pass, matching the geometry MSAA target's
    /// size and sample count. Memoryless — depth is consumed within the pass
    /// (storeAction `.dontCare`), never backed by DRAM.
    func makeDepthMSAA(width: Int, height: Int) -> MTLTexture? {
        let desc = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: depthPixelFormat, width: width, height: height, mipmapped: false)
        desc.textureType = .type2DMultisample
        desc.sampleCount = sampleCount
        desc.usage = .renderTarget
        desc.storageMode = .memoryless
        return device.makeTexture(descriptor: desc)
    }

    /// A multisample `stencil8` attachment for a clipping pass (`withClip`), matching
    /// the geometry MSAA target's size and sample count. Memoryless like the depth
    /// attachment: the stencil is cleared at pass start and consumed within the pass
    /// (storeAction `.dontCare`), so it holds no data between passes and one cached
    /// texture per size serves every pass and frame safely.
    func makeStencilMSAA(width: Int, height: Int) -> MTLTexture? {
        let desc = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .stencil8, width: width, height: height, mipmapped: false)
        desc.textureType = .type2DMultisample
        desc.sampleCount = sampleCount
        desc.usage = .renderTarget
        desc.storageMode = .memoryless
        return device.makeTexture(descriptor: desc)
    }

    /// Attach the clipping stencil to `pass` when `active` (the drawer pushed a clip
    /// on this pass's surface), returning whether the pass now carries one, which is
    /// what `encode` keys its stencil states and pipeline variants on. Cleared to 0
    /// (unclipped) and never stored; a failed allocation leaves the pass unclipped.
    func attachClipStencil(to pass: MTLRenderPassDescriptor, active: Bool,
                           width: Int, height: Int) -> Bool {
        guard active, let stencil = clipStencilTexture(width: width, height: height) else { return false }
        pass.stencilAttachment.texture = stencil
        pass.stencilAttachment.loadAction = .clear
        pass.stencilAttachment.clearStencil = 0
        pass.stencilAttachment.storeAction = .dontCare
        return true
    }

    /// The cached memoryless stencil attachment for a clipping pass at this size,
    /// made on first use. Bounded against size churn (a resize drops the cache; the
    /// textures have no backing store, so churn only costs the descriptor).
    func clipStencilTexture(width: Int, height: Int) -> MTLTexture? {
        if let cached = clipStencilTextures.first(where: { $0.width == width && $0.height == height }) {
            return cached
        }
        guard let made = makeStencilMSAA(width: width, height: height) else { return nil }
        if clipStencilTextures.count >= 8 { clipStencilTextures.removeAll(keepingCapacity: true) }
        clipStencilTextures.append(made)
        return made
    }

    /// A single-sample `depth32Float` the MSAA depth attachment of a 3D render target
    /// resolves into, sampled afterward by the depth-normalize pass. `.shaderRead` so
    /// it's sampleable, `.private` since it lives only on the GPU.
    func makeDepthResolve(width: Int, height: Int) -> MTLTexture? {
        let desc = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: depthPixelFormat, width: width, height: height, mipmapped: false)
        desc.usage = [.renderTarget, .shaderRead]
        desc.storageMode = .private
        return device.makeTexture(descriptor: desc)
    }

    /// Turn a 3D render target's resolved clip-space depth into a sampleable gray
    /// layer (0 near … 1 far): one fullscreen pass that linearizes the depth over the
    /// camera's near/far and encodes it so the perceptual depth-of-field decode reads
    /// back exactly that value (so `ollin_fx_depth_of_field` needs no change). A nil
    /// camera (a non-metric depth scene wrote normalized depth itself) passes through.
    func normalizeDepth(_ depth: MTLTexture, camera: Camera3D?,
                                width: Int, height: Int,
                                into cb: MTLCommandBuffer, pooled: Bool) -> MTLTexture? {
        guard let output = acquireFilterTexture(width: width, height: height, pooled: pooled) else { return nil }
        let near = Float(camera?.near ?? 0)
        let far = Float(camera?.far ?? 1)
        // Orthographic depth is already linear in distance; perspective and the
        // intrinsic (pinhole) projection are not, so the shader inverts the curve.
        // No camera → the depth is already normalized, so pass it straight through.
        var perspective: Float = 1
        if camera == nil { perspective = 0 }
        else if case .orthographic = camera?.projection { perspective = 0 }
        encodeEffectFragment("ollin_fx_depth_normalize", inputs: [depth], output: output,
                             params: [SIMD4(near, far, perspective, 0)], into: cb)
        return output
    }

    /// The shadow map: a square single-sample `.private` depth **array** the shadow
    /// pass renders into, one layer per 2D caster, and the lit mesh fragment samples.
    /// The layer index is the caster's slot index (`OllinLighting.shadowCasters`), so
    /// the primary caster always owns layer 0 and a cube or ray-traced primary simply
    /// leaves that layer cleared. Allocated lazily on the first shadow-casting frame (a
    /// sketch that never casts shadows allocates none), then reused; a frame that wants
    /// more layers than the current one holds allocates a fresh, wider texture rather
    /// than growing it, since an in-flight frame may still be reading the old one. A
    /// one-caster frame holds exactly one layer, so the common case costs what it always
    /// did.
    private func ensureShadowMap(layers: Int) -> MTLTexture? {
        let want = max(1, min(layers, Int(OLLIN_MAX_SHADOW_CASTERS)))
        if let m = shadowMap, m.arrayLength >= want { return m }
        let n = MetalRenderer.shadowMapResolution
        let desc = MTLTextureDescriptor()
        desc.textureType = .type2DArray
        desc.pixelFormat = depthPixelFormat
        desc.width = n
        desc.height = n
        desc.arrayLength = want
        desc.usage = [.renderTarget, .shaderRead]
        desc.storageMode = .private
        shadowMap = device.makeTexture(descriptor: desc)
        return shadowMap
    }

    /// A 1×1 single-layer depth array bound to the mesh fragment's shadow slot when
    /// shadows are off, so its declared `depth2d_array` argument is always satisfied (the
    /// fragment only samples it when a caster names it). Cleared once on creation so it's
    /// never read uninitialized.
    func ensureDummyShadowMap() -> MTLTexture? {
        if let m = dummyShadowMap { return m }
        let desc = MTLTextureDescriptor()
        desc.textureType = .type2DArray
        desc.pixelFormat = depthPixelFormat
        desc.width = 1
        desc.height = 1
        desc.arrayLength = 1
        desc.usage = [.renderTarget, .shaderRead]
        desc.storageMode = .private
        guard let texture = device.makeTexture(descriptor: desc) else { return nil }
        // Clear it (a depth-only pass) so the contents are defined.
        if let cb = commandQueue.makeCommandBuffer() {
            let pass = MTLRenderPassDescriptor()
            pass.depthAttachment.texture = texture
            pass.depthAttachment.loadAction = .clear
            pass.depthAttachment.clearDepth = 1.0
            pass.depthAttachment.storeAction = .store
            countedEncoder(cb, pass)?.endEncoding()
            cb.commit()
        }
        dummyShadowMap = texture
        return dummyShadowMap
    }

    /// The omnidirectional (point) shadow maps, a `.private` **`rg32Float` cube array**
    /// for mid-point shadow mapping: R holds the nearest occluder's distance to the light
    /// (normalized by the far plane), G the farthest, per direction. The lit fragment
    /// shadows where the receiver's distance exceeds the midpoint `(R+G)/2`. One cube per
    /// point caster, in slot order, so a point light casts from any slot. Allocated lazily
    /// on the first point-casting frame, then reused; a frame wanting more cubes than the
    /// current one holds allocates a fresh, wider texture rather than growing it, since an
    /// in-flight frame may still be reading the old one. A cube costs 6 faces of
    /// `pointShadowMapResolution` squared at 8 bytes a texel (50 MB at 1024), so the array
    /// is sized to the frame and never to the caster ceiling.
    static let pointShadowColorFormat: MTLPixelFormat = .rg32Float
    private func ensurePointShadowMap(cubes: Int) -> MTLTexture? {
        let want = max(1, min(cubes, Int(OLLIN_MAX_SHADOW_CASTERS)))
        if let m = pointShadowMap, m.arrayLength >= want { return m }
        let n = MetalRenderer.pointShadowMapResolution
        let desc = MTLTextureDescriptor()
        desc.textureType = .typeCubeArray
        desc.pixelFormat = MetalRenderer.pointShadowColorFormat
        desc.width = n
        desc.height = n
        desc.arrayLength = want
        desc.usage = [.renderTarget, .shaderRead]
        desc.storageMode = .private
        pointShadowMap = device.makeTexture(descriptor: desc)
        return pointShadowMap
    }

    /// A 1×1 single-cube `rg32Float` cube array bound to the mesh fragment's cube-shadow
    /// slot when no point caster is active, so its declared `texturecube_array` argument is
    /// always satisfied (the fragment only samples it for a caster of kind 1). Cleared to
    /// (1, 0) once on creation (all six faces in one layered pass) so it's never read
    /// uninitialized.
    func ensureDummyPointShadowMap() -> MTLTexture? {
        if let m = dummyPointShadowMap { return m }
        let desc = MTLTextureDescriptor()
        desc.textureType = .typeCubeArray
        desc.pixelFormat = MetalRenderer.pointShadowColorFormat
        desc.width = 1
        desc.height = 1
        desc.arrayLength = 1
        desc.usage = [.renderTarget, .shaderRead]
        desc.storageMode = .private
        guard let texture = device.makeTexture(descriptor: desc) else { return nil }
        if let cb = commandQueue.makeCommandBuffer() {
            let pass = MTLRenderPassDescriptor()
            pass.colorAttachments[0].texture = texture
            pass.colorAttachments[0].loadAction = .clear
            pass.colorAttachments[0].clearColor = MTLClearColor(red: 1, green: 0, blue: 0, alpha: 0)
            pass.colorAttachments[0].storeAction = .store
            pass.renderTargetArrayLength = 6      // clear all six faces at once
            countedEncoder(cb, pass)?.endEncoding()
            cb.commit()
        }
        dummyPointShadowMap = texture
        return dummyPointShadowMap
    }

    /// The shadow map(s) a frame produced: the 2D map for a directional/spot caster, or
    /// the cube map for a point caster (at most one is set; both nil = no shadow).
    struct ShadowMaps {
        var twoD: MTLTexture?
        var cube: MTLTexture?
        /// The ray-traced point caster's acceleration structure (RT devices), in place
        /// of the cube; the lit mesh fragment traces a visibility ray against it.
        var accel: MTLAccelerationStructure?
        /// Ray-traced reflections: the caster acceleration structure to trace reflection
        /// rays against (the same object as `accel` when an RT point caster is also present)
        /// and the per-geometry base-vertex offsets to fetch a hit triangle from the flat
        /// mesh buffer. Set only when `rayTracedReflections()` is on and the device can trace.
        var reflectAccel: MTLAccelerationStructure?
        var reflectGeoOffsets: MTLBuffer?
        /// Global illumination: the same acceleration structure + offsets for the probe
        /// trace (one build serves shadows, reflections, and GI). Set only when
        /// `globalIllumination()` is on and the device can trace.
        var giAccel: MTLAccelerationStructure?
        var giGeoOffsets: MTLBuffer?
        /// Caustics: the same structure + offsets for the photon trace, plus the
        /// per-geometry caustic materials (transmission / ior / attenuation). Set only
        /// when `caustics()` is on and the device can trace; the accel build then
        /// breaks its coalesced geometry runs where those materials change, so a
        /// photon hit's `geometryId` resolves a material-uniform surface.
        var causticAccel: MTLAccelerationStructure?
        var causticGeoOffsets: MTLBuffer?
        var causticGeoMats: MTLBuffer?
    }

    /// Render the scene's mesh geometry into the shadow map from the casting light's
    /// point of view (a depth-only pass), so the lit mesh fragment can compare each
    /// receiver against it. Encoded *before* the geometry pass in the same command
    /// buffer, so Metal's intra-buffer hazard tracking orders the geometry pass after it.
    /// Returns the populated map (2D for a directional/spot caster, a cube for a point
    /// caster), or empty when this frame casts no shadow (no `castShadows()`, no eligible
    /// light, or no meshes), in which case the caller shades unshadowed. Uses the same
    /// `meshBuffer` the geometry pass will use (it uploads the vertices here; the
    /// geometry pass re-copies the same bytes).
    func encodeShadowPass(_ drawer: Drawer, into commandBuffer: MTLCommandBuffer,
                                  meshBuffer: MTLBuffer?,
                                  instancedMeshBuffer: MTLBuffer? = nil,
                                  meshInstanceBuffer: MTLBuffer? = nil,
                                  sdf3DGroupBuffer: MTLBuffer? = nil,
                                  sdf3DNodeBuffer: MTLBuffer? = nil) -> ShadowMaps {
        pointShadowFars.removeAll(keepingCapacity: true)
        let lighting = drawer.makeLighting()
        let meshVertices = drawer.meshVertices
        // Instanced-mesh copies cast into the rasterized maps (2D + cube) but not
        // the ray-traced acceleration structure yet, so they matter here whenever
        // any exist; a frame with only instanced casters still renders its maps.
        let hasInstancedCasters = instancedMeshBuffer != nil
            && drawer.batches.contains { $0.kind == .meshInstanced }
        // Fields cast too, from their own retained buffers, UNCULLED (a copy
        // outside the camera frustum still throws its shadow into view).
        let hasFieldCasters = drawer.batches.contains { $0.kind == .meshField }
        // Ray-traced reflections want a caster acceleration structure even when no light casts
        // a shadow; build it once and reuse it for both. (A non-RT device can't reflect, so
        // `wantReflect` is already false there and the shadow paths stay byte-identical.)
        // An environment is required too: the traced hit integrates into the IBL specular
        // (`ollin_pbr_ibl_ambient`), which never runs without one, so building the accel
        // then would be per-frame GPU work nothing consumes.
        let wantReflect = drawer.rayTracedReflectionsEnabled && rayTracedShadows
            && drawer.environment != nil
        // Global illumination wants the same accel with neither of the above conditions:
        // the probe trace needs no environment (misses just read black) and no caster.
        let wantGI = drawer.globalIlluminationEnabled && rayTracedShadows
            && drawer.camera3D != nil
        // Caustics want it too, plus the per-geometry caustic materials (the build
        // then breaks runs at material changes). Only when a punctual light and a
        // casting material exist; otherwise the frame is inert and byte-identical.
        let wantCaustics = causticsWanted(drawer)
        guard lighting.enabled != 0,
              !meshVertices.isEmpty || hasInstancedCasters || hasFieldCasters,
              lighting.shadowLight >= 0 || wantReflect || wantGI || wantCaustics
        else { return ShadowMaps() }

        // Fill the caster buffers here: the shadow pass runs before the main
        // encode (which re-uploads the same bytes), so the GPU sees the geometry
        // when it renders the maps. The plain mesh buffer may be nil on a frame
        // whose only casters are instanced; each consumer below skips it then.
        if !meshVertices.isEmpty, let meshBuffer {
            meshVertices.withUnsafeBytes { raw in
                meshBuffer.contents().copyMemory(from: raw.baseAddress!, byteCount: raw.count)
            }
        }
        if hasInstancedCasters {
            if let instancedMeshBuffer, !drawer.instancedMeshVertices.isEmpty {
                drawer.instancedMeshVertices.withUnsafeBytes { raw in
                    instancedMeshBuffer.contents().copyMemory(from: raw.baseAddress!, byteCount: raw.count)
                }
            }
            if let meshInstanceBuffer, !drawer.meshInstances.isEmpty {
                drawer.meshInstances.withUnsafeBytes { raw in
                    meshInstanceBuffer.contents().copyMemory(from: raw.baseAddress!, byteCount: raw.count)
                }
            }
        }

        // The 2D casters, each with the array layer it renders into (the layer index is
        // the caster's slot). A frame whose only caster is a point light has none.
        let twoDCasters = shadowCasters(lighting).enumerated()
            .filter { $0.element.kind == 0 }
            .map { (layer: $0.offset, caster: $0.element) }

        // The point casters, in slot order (a point light casts from any slot): ray-trace
        // every one of them on a capable device (exact, no cube/depth-compare artifacts),
        // else render each into its own cube of the omnidirectional mid-point cube array.
        // The one accel serves the shadows (shadowKind 2) and, when on, reflections.
        // The traced path needs real mesh geometry in the accel; a frame with only
        // instanced casters falls to the cubes, which they render into.
        var accel: MTLAccelerationStructure?
        var accelOffsets: MTLBuffer?
        var accelCausticMats: MTLBuffer?
        var cube: MTLTexture?
        var tracedPrimary = false
        var tracedPoints = false
        let pointCasters = shadowCasters(lighting).filter { $0.kind == 1 }
        if !pointCasters.isEmpty, rayTracedShadows, let meshBuffer, !meshVertices.isEmpty,
           let built = buildShadowAccel(drawer, into: commandBuffer, meshBuffer: meshBuffer,
                                        causticMats: wantCaustics) {
            accel = built.accel
            accelOffsets = built.offsets
            accelCausticMats = built.causticMats
            tracedPoints = true
            // Slot 0 is one of them exactly when the primary itself is a point caster.
            tracedPrimary = lighting.shadowKind == 1
        }
        if !tracedPoints, !pointCasters.isEmpty {
            cube = encodePointShadowPass(drawer, lighting: lighting, casters: pointCasters,
                                         into: commandBuffer, meshBuffer: meshBuffer,
                                         instancedMeshBuffer: hasInstancedCasters ? instancedMeshBuffer : nil,
                                         meshInstanceBuffer: meshInstanceBuffer)
        }

        // A rect/disk **area** primary caster on a ray-tracing device: trace visibility to
        // the panel's actual surface instead of rendering its spot-style map (the exact
        // penumbra, including a rect's anisotropy). Elsewhere it falls through to the 2D
        // map below, whose PCSS penumbra the packing already sized from the panel's
        // extent, so both devices soften by the same physical size.
        if !tracedPrimary, lighting.shadowLight >= 0, casterGPUKind(lighting) >= 3, rayTracedShadows,
           let meshBuffer, !meshVertices.isEmpty {
            // A point caster beside it has already built the one structure; take that
            // rather than building a second copy of the same geometry.
            if accel != nil {
                tracedPrimary = true
            } else if let built = buildShadowAccel(drawer, into: commandBuffer, meshBuffer: meshBuffer,
                                                   causticMats: wantCaustics) {
                accel = built.accel
                accelOffsets = built.offsets
                accelCausticMats = built.causticMats
                tracedPrimary = true
            }
        }
        // A traced primary caster renders no map of its own, so drop its layer from the
        // 2D list; the extra casters beside it keep theirs.
        let mapCasters = tracedPrimary ? twoDCasters.filter { $0.layer != 0 } : twoDCasters

        // Reflections, GI, and/or caustics want the same structure with none of the above
        // conditions (the probe trace needs no environment and no caster), so build it once
        // for whichever of them is on. All of these precede the main geometry pass, so
        // trace order is satisfied either way.
        // A frame whose meshes are all copies still has a scene to trace, so the
        // instanced vertices count as geometry here as well.
        if accel == nil, wantReflect || wantGI || wantCaustics,
           !meshVertices.isEmpty || !drawer.instancedMeshVertices.isEmpty,
           let meshBuffer,
           let built = buildShadowAccel(drawer, into: commandBuffer, meshBuffer: meshBuffer,
                                        causticMats: wantCaustics) {
            accel = built.accel
            accelOffsets = built.offsets
            accelCausticMats = built.causticMats
        }

        /// Everything this frame produced, with each accel consumer taking it only when
        /// its own switch is on.
        func maps(twoD: MTLTexture?) -> ShadowMaps {
            ShadowMaps(twoD: twoD, cube: cube,
                       accel: (tracedPrimary || tracedPoints) ? accel : nil,
                       reflectAccel: wantReflect ? accel : nil,
                       reflectGeoOffsets: wantReflect ? accelOffsets : nil,
                       giAccel: wantGI ? accel : nil,
                       giGeoOffsets: wantGI ? accelOffsets : nil,
                       causticAccel: wantCaustics ? accel : nil,
                       causticGeoOffsets: wantCaustics ? accelOffsets : nil,
                       causticGeoMats: wantCaustics ? accelCausticMats : nil)
        }

        guard !mapCasters.isEmpty else { return maps(twoD: nil) }
        guard let shadowMap = ensureShadowMap(layers: Int(lighting.shadowCasterCount)),
              let shadowPipeline = try? pipeline(.meshShadow) else { return maps(twoD: nil) }

        // One depth-only pass per 2D caster, each into its own array layer. Separate
        // passes rather than one layered pass: every caster has its own projection, and
        // the depth-only vertex takes exactly one.
        for (layer, caster) in mapCasters {
            let pass = MTLRenderPassDescriptor()
            pass.depthAttachment.texture = shadowMap
            pass.depthAttachment.slice = layer
            pass.depthAttachment.loadAction = .clear
            pass.depthAttachment.clearDepth = 1.0
            pass.depthAttachment.storeAction = .store
            guard let encoder = countedEncoder(commandBuffer, pass) else { return maps(twoD: nil) }
            encoder.setRenderPipelineState(shadowPipeline)
            encoder.setDepthStencilState(depthTestState)
            // Slope-scaled depth bias on the stored depth keeps self-shadowing acne off
            // (paired with the fragment's normal-offset + constant bias).
            encoder.setDepthBias(0.0015, slopeScale: 2.0, clamp: 0.01)
            var lightVP = caster.lightViewProjection
            encoder.setVertexBytes(&lightVP, length: MemoryLayout<simd_float4x4>.stride, index: 2)
            if let meshBuffer, !meshVertices.isEmpty {
                drawShadowCasters(drawer, encoder: encoder, meshBuffer: meshBuffer, instanceCount: 1)
            }
            // Instanced-mesh copies cast into the same map through their own depth-only
            // pipeline (the instance matrices applied per vertex, then the light's clip).
            if hasInstancedCasters, let ip = try? pipeline(.meshInstancedShadow) {
                encoder.setRenderPipelineState(ip)
                drawInstancedShadowCasters(drawer, encoder: encoder,
                                           instancedMeshBuffer: instancedMeshBuffer,
                                           meshInstanceBuffer: meshInstanceBuffer, faces: 1)
            }
            // MeshFields cast from their retained buffers, whole (no culling here).
            if hasFieldCasters, let fp = try? pipeline(.meshFieldShadow) {
                encoder.setRenderPipelineState(fp)
                drawFieldShadowCasters(drawer, encoder: encoder, faces: 1)
            }
            // Marched 3D fields cast into the same map: sphere-trace each from the light's POV and
            // write its depth, z-tested against the mesh casters already there, so meshes receive a
            // field's shadow too. The field keeps its analytic self-shadow in the main pass and
            // doesn't sample this map, so there's no double-shadowing (directional/spot only).
            encodeFieldShadowCasters(drawer, encoder: encoder, lightViewProjection: caster.lightViewProjection,
                                     groupBuffer: sdf3DGroupBuffer, nodeBuffer: sdf3DNodeBuffer)
            encoder.endEncoding()
        }
        return maps(twoD: shadowMap)
    }

    /// Carry the frame's resolved single-caster fields back into slot 0, and give every
    /// extra caster what the device settled for its own kind.
    ///
    /// The renderer owns the device, so several caster facts are only settled after
    /// `makeLighting`: the flip to the traced path, the ray or tap counts, the far plane a
    /// cube was actually rendered with, and whether a map was produced at all. Slot 0
    /// mirrors those, so the lit mesh path can read one caster the same way whichever slot
    /// it sits in. Every extra caster then needs the resource its own kind names: a 2D one
    /// a rendered map layer, a point one either a rendered cube or the frame's acceleration
    /// structure. A caster whose resource is missing drops out of the list, and with none
    /// of them left the frame behaves as it did with one caster.
    func finalizeShadowCasters(_ drawer: Drawer, _ lighting: inout OllinLighting,
                               renderedMap: Bool, renderedCube: Bool = false,
                               traced: Bool = false) {
        guard lighting.shadowCasterCount > 0 else { return }
        guard lighting.shadowLight >= 0 else { lighting.shadowCasterCount = 0; return }
        var casters = shadowCasters(lighting)
        // The cube pass fits its own far plane to what the light reaches (the packing
        // could only guess from the camera), so the fragment must compare against that
        // one and not the guess. A traced point caster renders no cube, leaves this
        // empty, and keeps every packed field exactly as it was.
        for k in casters.indices where casters[k].kind == 1 {
            if let far = pointShadowFars[casters[k].lightIndex] { casters[k].depthA = far }
        }
        if lighting.shadowKind == 1, let far = pointShadowFars[lighting.shadowLight] {
            lighting.shadowDepthA = far
        }
        casters[0].lightIndex = lighting.shadowLight
        casters[0].kind = lighting.shadowKind
        casters[0].strength = lighting.shadowStrength
        casters[0].samples = lighting.shadowSamples
        casters[0].depthB = lighting.shadowDepthB
        let taps = resolveShadowTaps2D(drawer.shadowQualitySetting)
        let rays = resolveShadowSamples(drawer.shadowQualitySetting)
        var kept = [casters[0]]
        for k in 1..<casters.count {
            var c = casters[k]
            switch c.kind {
            case 0:
                guard renderedMap else { continue }
                c.samples = taps
            case 1:
                // A point caster traces beside the primary, or reads its own cube.
                if traced {
                    c.kind = 2
                    c.samples = rays
                } else if !renderedCube {
                    continue
                }
            default:
                continue
            }
            kept.append(c)
        }
        casters = kept
        // A cube caster's cube is its rank among the cube casters, which is the order the
        // cube pass rendered them in, so a cube primary is always cube 0.
        var cube: Int32 = 0
        for k in casters.indices where casters[k].kind == 1 {
            casters[k].cubeIndex = cube
            cube += 1
        }
        lighting.shadowCasterCount = Int32(casters.count)
        withUnsafeMutablePointer(to: &lighting.shadowCasters) { tuplePtr in
            tuplePtr.withMemoryRebound(to: OllinShadowCaster.self,
                                       capacity: Int(OLLIN_MAX_SHADOW_CASTERS)) { buf in
                for (slot, c) in casters.enumerated() { buf[slot] = c }
            }
        }
    }

    /// The frame's shadow casters as a plain array: a C fixed-size array imports as a
    /// homogeneous tuple, so reading one needs a typed pointer.
    func shadowCasters(_ lighting: OllinLighting) -> [OllinShadowCaster] {
        let n = min(Int(lighting.shadowCasterCount), Int(OLLIN_MAX_SHADOW_CASTERS))
        guard n > 0 else { return [] }
        return withUnsafePointer(to: lighting.shadowCasters) { ptr in
            ptr.withMemoryRebound(to: OllinShadowCaster.self,
                                  capacity: Int(OLLIN_MAX_SHADOW_CASTERS)) { buf in
                (0..<n).map { buf[$0] }
            }
        }
    }

    /// Render the marched 3D fields into the active 2D shadow map (directional/spot). Each field
    /// is one instanced fullscreen triangle whose fragment sphere-traces it from the light's
    /// point of view and writes the hit's light-clip depth (depth-only, z-tested against the
    /// mesh casters already in the map). A no-op when the frame has no fields or no buffers.
    private func encodeFieldShadowCasters(_ drawer: Drawer, encoder: MTLRenderCommandEncoder,
                                          lightViewProjection: simd_float4x4,
                                          groupBuffer: MTLBuffer?, nodeBuffer: MTLBuffer?) {
        let groups3D = drawer.sdf3DGroups
        let nodes3D = drawer.sdf3DNodes
        guard !groups3D.isEmpty, !nodes3D.isEmpty,
              let groupBuffer, let nodeBuffer,
              let fieldPipeline = try? pipeline(.raymarchShadow) else { return }
        // Fill the field buffers here: the shadow pass runs before the main encode (which
        // re-uploads the same bytes), so the GPU sees the geometry when it marches the map.
        groups3D.withUnsafeBytes { raw in
            groupBuffer.contents().copyMemory(from: raw.baseAddress!, byteCount: raw.count)
        }
        nodes3D.withUnsafeBytes { raw in
            nodeBuffer.contents().copyMemory(from: raw.baseAddress!, byteCount: raw.count)
        }
        let casterSteps = resolveRaymarchSteps(drawer.raymarchQualitySetting).march
        var u = OllinRaymarchShadowUniforms(
            lightViewProjection: lightViewProjection,
            inverseLightViewProjection: simd_inverse(lightViewProjection),
            raymarchSteps: Float(casterSteps))
        encoder.setRenderPipelineState(fieldPipeline)
        encoder.setFragmentBuffer(groupBuffer, offset: 0, index: 0)
        encoder.setFragmentBuffer(nodeBuffer, offset: 0, index: 1)
        encoder.setFragmentBytes(&u, length: MemoryLayout<OllinRaymarchShadowUniforms>.stride, index: 2)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3,
                               instanceCount: groups3D.count)
    }

    /// The omnidirectional (point) shadow pass: render the scene into all six faces of
    /// every point caster's cube in **one** layered pass (the geometry instanced six times
    /// per caster, each instance routed to a slice by `render_target_array_index`). The
    /// fragment writes each occluder's linear distance to the light (normalized by the far
    /// plane) as the stored value, so the lit mesh fragment later compares plain
    /// world-space distances. `casters` is the frame's kind-1 casters in slot order, and
    /// that order is the cube index each one carries, so a cube *primary* is always cube 0.
    /// Returns the populated cube array.
    private func encodePointShadowPass(_ drawer: Drawer, lighting: OllinLighting,
                                       casters: [OllinShadowCaster],
                                       into commandBuffer: MTLCommandBuffer,
                                       meshBuffer: MTLBuffer?,
                                       instancedMeshBuffer: MTLBuffer? = nil,
                                       meshInstanceBuffer: MTLBuffer? = nil) -> MTLTexture? {
        guard !casters.isEmpty,
              let cube = ensurePointShadowMap(cubes: casters.count),
              let minPipeline = try? pipeline(.meshPointShadowMin),
              let maxPipeline = try? pipeline(.meshPointShadowMax) else { return nil }

        // The casting lights' world positions from the uniform's fixed-size light array.
        // The casters are passed in rather than read off `shadowLight`: a cube belongs to
        // whichever caster wants one, which need not be the primary.
        let lightPositions: [SIMD3<Float>] = withUnsafePointer(to: lighting.lights) { ptr in
            ptr.withMemoryRebound(to: OllinLight.self, capacity: Int(OLLIN_MAX_LIGHTS)) { buf in
                casters.map { c in
                    let p = buf[Int(c.lightIndex)].position
                    return SIMD3<Float>(p.x, p.y, p.z)
                }
            }
        }
        // The far plane each caster's packing carried (`depthA`) is fitted from the camera's
        // own framing radius, which says nothing about how far the light reaches: a wide floor
        // under a near light runs well past it, and everything out there is clipped out of
        // the cube while still comparing against it. So fit it to the casters instead, and
        // hand the same number to the fragment through `pointShadowFars`. The scan runs once
        // for the whole frame, and only here, on the rasterized path, so a device that traces
        // its point casters never pays for it.
        let bounds = pointCasterBounds(drawer)
        let fars: [Float] = zip(casters, lightPositions).map { caster, lightPos in
            let far = pointCasterFar(bounds: bounds, from: lightPos, fallback: caster.depthA)
            pointShadowFars[caster.lightIndex] = far
            return far
        }

        // The six face views below use the standard cube-face basis, which is written for
        // an API whose framebuffer origin sits at the *bottom* left. Metal's sits at the
        // top left, while a cube face is addressed from the top left in both, so rendering
        // those views unchanged stores every face upside down: a receiver then samples the
        // mirror of the direction it meant, and a shadow lands on the wrong side of the
        // light (a box over a floor throws its shadow behind itself, and the floor's own
        // occlusion reads from the wrong place, which ripples it). Negating the
        // projection's y row flips each face back. Horizontal `u` already agrees, so only
        // this one row moves. It reverses the triangles' screen winding, which costs
        // nothing here: the pass culls no faces, by design.
        // The six cube faces (forward axis, up), in Metal's +X/-X/+Y/-Y/+Z/-Z order.
        let faces: [(SIMD3<Float>, SIMD3<Float>)] = [
            (SIMD3(1,  0,  0), SIMD3(0, -1,  0)),
            (SIMD3(-1,  0,  0), SIMD3(0, -1,  0)),
            (SIMD3(0,  1,  0), SIMD3(0,  0,  1)),
            (SIMD3(0, -1,  0), SIMD3(0,  0, -1)),
            (SIMD3(0,  0,  1), SIMD3(0, -1,  0)),
            (SIMD3(0,  0, -1), SIMD3(0, -1,  0)),
        ]
        let faceVPs: [[simd_float4x4]] = zip(lightPositions, fars).map { lightPos, far in
            let near = max(Float(0.05), far * 0.02)
            var proj = Camera3D.perspective(fovY: .pi / 2, aspect: 1, near: near, far: far)
            proj.columns.1.y = -proj.columns.1.y
            return faces.map { proj * Camera3D.lookAt(eye: lightPos, center: lightPos + $0.0, up: $0.1) }
        }

        // Mid-point shadow mapping: clear R = 1 (far, for the MIN pass) and G = 0 (near,
        // for the MAX pass), then make two draws of the scene with NO culling: the MIN
        // pass fills R with the nearest occluder distance per direction, the MAX pass
        // fills G with the farthest. The receiver shadows past the midpoint (R+G)/2, so a
        // surface compares against a point *inside* the occluder: no self-shadow acne on
        // edge-on faces, and no contact leak, without any face culling.
        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = cube
        pass.colorAttachments[0].loadAction = .clear
        pass.colorAttachments[0].clearColor = MTLClearColor(red: 1, green: 0, blue: 0, alpha: 0)
        pass.colorAttachments[0].storeAction = .store
        pass.renderTargetArrayLength = 6 * casters.count
        guard let encoder = countedEncoder(commandBuffer, pass) else { return nil }
        // The instanced siblings share the pass: each phase draws the plain casters,
        // then the instanced ones under the matching MIN/MAX pipeline (blend rides
        // the pipeline, so order within a phase doesn't matter).
        let instancedMin = instancedMeshBuffer != nil
            ? try? pipeline(.meshInstancedPointShadowMin) : nil
        let instancedMax = instancedMeshBuffer != nil
            ? try? pipeline(.meshInstancedPointShadowMax) : nil
        let hasFields = drawer.batches.contains { $0.kind == .meshField }
        for (cubeIndex, faceVP) in faceVPs.enumerated() {
            // Each cube writes the six slices from `6 * cubeIndex`; the vertex adds that
            // base to its face, so the same layered draw fills any cube of the array.
            var base = UInt32(6 * cubeIndex)
            encoder.setVertexBytes(&base, length: MemoryLayout<UInt32>.stride, index: 3)
            faceVP.withUnsafeBytes { encoder.setVertexBytes($0.baseAddress!, length: $0.count, index: 2) }
            let lp = lightPositions[cubeIndex]
            var lightPosFar = SIMD4<Float>(lp.x, lp.y, lp.z, fars[cubeIndex])
            encoder.setFragmentBytes(&lightPosFar, length: MemoryLayout<SIMD4<Float>>.stride, index: 0)
            encoder.setRenderPipelineState(minPipeline)   // nearest -> R
            if let meshBuffer {
                drawShadowCasters(drawer, encoder: encoder, meshBuffer: meshBuffer, instanceCount: 6)
            }
            if let instancedMin {
                encoder.setRenderPipelineState(instancedMin)
                drawInstancedShadowCasters(drawer, encoder: encoder,
                                           instancedMeshBuffer: instancedMeshBuffer,
                                           meshInstanceBuffer: meshInstanceBuffer, faces: 6)
            }
            if hasFields, let fieldMin = try? pipeline(.meshFieldPointShadowMin) {
                encoder.setRenderPipelineState(fieldMin)
                drawFieldShadowCasters(drawer, encoder: encoder, faces: 6)
            }
            encoder.setRenderPipelineState(maxPipeline)   // farthest -> G
            if let meshBuffer {
                drawShadowCasters(drawer, encoder: encoder, meshBuffer: meshBuffer, instanceCount: 6)
            }
            if let instancedMax {
                encoder.setRenderPipelineState(instancedMax)
                drawInstancedShadowCasters(drawer, encoder: encoder,
                                           instancedMeshBuffer: instancedMeshBuffer,
                                           meshInstanceBuffer: meshInstanceBuffer, faces: 6)
            }
            if hasFields, let fieldMax = try? pipeline(.meshFieldPointShadowMax) {
                encoder.setRenderPipelineState(fieldMax)
                drawFieldShadowCasters(drawer, encoder: encoder, faces: 6)
            }
        }
        encoder.endEncoding()
        return cube
    }

    /// Everything that casts into the frame's cube maps, as one world-space box.
    /// Worked out once per frame and shared by every point caster's far-plane fit.
    /// The plain meshes are a scan of the frame's own vertices. An instanced copy
    /// and a field's copy hold a matrix each instead, in a buffer of their own, so
    /// each carries its base mesh's bounding sphere into the world here: without
    /// that, a frame whose casters are all copies has nothing to fit to, and every
    /// copy past the caller's guess falls outside the cube and throws nothing.
    private func pointCasterBounds(_ drawer: Drawer) -> CasterBounds {
        var bounds = CasterBounds()
        for v in drawer.meshVertices {
            bounds.fold(SIMD3<Float>(v.position.x, v.position.y, v.position.z))
        }
        for batch in drawer.batches {
            switch batch.kind {
            case .meshInstanced:
                guard batch.instancedVertexCount > 0 else { continue }
                // Placements a compute kernel wrote never come back to the CPU, by
                // design, so this is the one caster the scan cannot see at all.
                guard batch.particleBuffer == nil else { bounds.complete = false; continue }
                guard batch.meshInstanceCount > 0 else { continue }
                let base = instancedBaseSphere(drawer, batch)
                for i in batch.meshInstanceStart ..< batch.meshInstanceStart + batch.meshInstanceCount {
                    bounds.fold(sphere: base, through: drawer.meshInstances[i].model)
                }
            case .meshField:
                guard let box = batch.field?.localBounds() else { continue }
                // The field's box sits in the field's own space, and the draw-time
                // transform can turn it as well as move it, so every corner goes
                // through and the box is taken again around what comes out.
                for corner in 0 ..< 8 {
                    let local = SIMD3<Float>(corner & 1 == 0 ? box.lo.x : box.hi.x,
                                             corner & 2 == 0 ? box.lo.y : box.hi.y,
                                             corner & 4 == 0 ? box.lo.z : box.hi.z)
                    let placed = batch.fieldTransform * SIMD4<Float>(local.x, local.y, local.z, 1)
                    bounds.fold(SIMD3<Float>(placed.x, placed.y, placed.z))
                }
            default:
                continue
            }
        }
        return bounds
    }

    /// The world box the point-shadow cube has to reach around, and whether the scan
    /// saw everything that casts into it. `complete` is false only for placements the
    /// CPU cannot read, which is what makes the caller keep its own guess as a floor.
    private struct CasterBounds {
        var lo = SIMD3<Float>(repeating: .greatestFiniteMagnitude)
        var hi = SIMD3<Float>(repeating: -.greatestFiniteMagnitude)
        var complete = true
        var isEmpty: Bool { lo.x > hi.x }

        mutating func fold(_ p: SIMD3<Float>) {
            lo = simd_min(lo, p)
            hi = simd_max(hi, p)
        }

        /// Fold in a local bounding sphere placed by `model`: the center through the
        /// matrix, the radius stretched by the most that matrix can stretch a length.
        /// It is the conservative world sphere the field cull kernel works out per
        /// copy, so a copy is bounded here exactly as it is bounded there.
        mutating func fold(sphere: (center: SIMD3<Float>, radius: Float), through model: simd_float4x4) {
            let c = sphere.center
            let placed = model * SIMD4<Float>(c.x, c.y, c.z, 1)
            let world = SIMD3<Float>(placed.x, placed.y, placed.z)
            let radius = sphere.radius * model.largestColumnScale
            fold(world - radius)
            fold(world + radius)
        }
    }

    /// The local bounding sphere of an instanced batch's base mesh, over the run of
    /// vertices that batch expanded (local space, one copy of the mesh however many
    /// copies are placed). Each placement then carries it into the world.
    private func instancedBaseSphere(_ drawer: Drawer, _ batch: GeometryBatch)
        -> (center: SIMD3<Float>, radius: Float) {
        let run = batch.instancedVertexStart ..< batch.instancedVertexStart + batch.instancedVertexCount
        var lo = SIMD3<Float>(repeating: .greatestFiniteMagnitude)
        var hi = SIMD3<Float>(repeating: -.greatestFiniteMagnitude)
        for i in run {
            let p = drawer.instancedMeshVertices[i].position
            let v = SIMD3<Float>(p.x, p.y, p.z)
            lo = simd_min(lo, v)
            hi = simd_max(hi, v)
        }
        guard lo.x <= hi.x else { return (.zero, 0) }
        let center = (lo + hi) / 2
        var radius: Float = 0
        for i in run {
            let p = drawer.instancedMeshVertices[i].position
            radius = max(radius, simd_length(SIMD3<Float>(p.x, p.y, p.z) - center))
        }
        return (center, radius)
    }

    /// How far the point caster's cube must reach: the distance from the light to the
    /// farthest corner of everything that casts into it, plus a small margin so the
    /// farthest surface still stores under the "nothing here" sentinel. The caller's
    /// value stays a floor when the frame holds a caster the scan could not read.
    private func pointCasterFar(bounds: CasterBounds, from lightPos: SIMD3<Float>,
                                fallback: Float) -> Float {
        var far: Float = 0
        if !bounds.isEmpty {
            // The farthest corner: per axis, whichever end of the box is further away.
            let arm = simd_max(abs(bounds.lo - lightPos), abs(bounds.hi - lightPos))
            far = simd_length(arm) * 1.02
        }
        if far <= 0 || !bounds.complete { far = max(far, fallback) }
        return max(far, 0.01)
    }

    /// Resolve the sketch's soft-shadow quality intent to a concrete ray count for this GPU.
    /// A `Quality` tier scales with the hardware (a dedicated-RT GPU affords more rays of a
    /// software-RT one at the same tier, so better hardware lifts the default quality on its
    /// own); an absolute count passes through unchanged. Frame-rate-band tiers (the software-RT
    /// M2 column is measured at the live drawable via `Scripts/benchmark.sh shadows`):
    /// `.performance` ~120fps (2 rays = 149fps), `.default` 60–90fps (4 = 88fps), `.detail`
    /// 15–30fps (16 = 25fps). The hw (apple9+) column is an estimate until benchmarked there.
    func resolveShadowSamples(_ setting: ShadowQualitySetting) -> Int32 {
        switch setting {
        case .absolute(let n):
            return Int32(n)
        case .tier(let quality):
            let hw = hasHardwareRayTracing
            switch effectiveQuality(quality) {
            case .performance: return hw ? 8  : 2
            case .default:     return hw ? 16 : 4
            case .detail:      return hw ? 48 : 16
            }
        }
    }

    /// Resolve the soft-shadow quality intent to a PCSS **tap budget** for the directional/spot
    /// 2D maps (shared between the blocker search and the variable-kernel PCF). Unlike the
    /// ray-traced path, these are cheap texture samples that run on every GPU, so the budget is
    /// hardware-independent (a tier maps to a fixed count, not a per-GPU one). Export/headless
    /// lands on `.detail` via `effectiveQuality` for the creamiest penumbra; live stays at
    /// `.default`. An absolute `shadowSamples(_:)` is clamped to a sane disk range.
    func resolveShadowTaps2D(_ setting: ShadowQualitySetting) -> Int32 {
        switch setting {
        case .absolute(let n):
            return Int32(min(max(n, 12), 96))
        case .tier(let quality):
            switch effectiveQuality(quality) {
            case .performance: return 24
            case .default:     return 40
            case .detail:      return 72
            }
        }
    }

    /// Resolve the volumetric-light quality intent to the in-scatter march's **step budget**
    /// (steps along each view ray, one shadow-map compare each). Cheap texture taps on any
    /// GPU, so the budget is hardware-independent like the PCSS taps. Export/headless lands
    /// on `.detail` via `effectiveQuality`, so exported beams never march coarser than live.
    func resolveVolumetricSteps(_ setting: VolumetricQualitySetting) -> Int {
        switch setting {
        case .absolute(let n):
            return min(max(n, 8), 128)
        case .tier(let quality):
            switch effectiveQuality(quality) {
            case .performance: return 16
            case .default:     return 32
            case .detail:      return 64
            }
        }
    }

    /// Map a feature's requested quality through the automatic fallback: `.default` means
    /// "unset", so it resolves to `automaticQuality`; anything else is an explicit choice and
    /// passes through. (Live keeps `.default` as `.default`; export lifts it to `.detail`.)
    private func effectiveQuality(_ q: RenderQuality) -> RenderQuality {
        q == .default ? automaticQuality : q
    }

    /// The contact-shadow march's step budget, by the automatic quality tier (the
    /// TAA/motion-blur rule: no per-feature knob, `.default` resolves per context and
    /// export lifts it to `.detail`). Hardware-independent: a step is one depth-texture
    /// tap plus a few multiplies, cheap on any GPU (the `resolveShadowTaps2D` shape).
    /// More steps turn the start-jitter dither finer over the same ray length.
    /// Measured M2 release 1080² (the example scene, `--bench --gpu`): the whole term,
    /// depth pre-pass + 16-step march + carrier sample, costs ~1.0 ms GPU (3.5 → 4.5).
    func resolveContactShadowSteps() -> Int {
        switch effectiveQuality(.default) {
        case .performance: return 8
        case .default: return 16
        case .detail: return 32
        }
    }

    /// Resolve a `.ambientOcclusion` quality tier to a gather sample count. Fewer samples
    /// than the bokeh gather (each reconstructs a view-space position and accumulates a
    /// scalar, not a color), distributed over the same smooth golden-angle spiral so the
    /// occlusion needs no noise texture or separate blur.
    func resolveSSAOSamples(_ quality: RenderQuality) -> Int {
        if let override = ssaoSamplesOverride { return max(4, min(override, 256)) }
        // Frame-rate-band tiers (measured on M2 at 1080² via `Scripts/benchmark.sh ssao`):
        // `.performance` ~120fps headroom (64 = 192fps), `.default` 60–90fps with headroom
        // (128 = 117fps). SSAO is cheap enough that reaching `.detail`'s 15–30fps target would
        // need ~600+ samples (far past where the occlusion estimate stops improving), so
        // `.detail` is capped at the useful ceiling (256 = 66fps), not the frame-rate band.
        switch effectiveQuality(quality) {
        case .performance: return 64
        case .default:     return 128
        case .detail:      return 256
        }
    }

    /// Resolve a `.screenSpaceReflections` quality tier to a coarse-march step count. The DDA
    /// covers the *whole* reflection ray in this many steps (the stride scales with the ray's
    /// pixel span), so the reach is resolution-independent and this is purely a precision knob:
    /// fewer coarse steps trade hit precision (before the binary refinement) for frame rate.
    /// GPU-independent, like the raymarch resolution. Tune later via `Scripts/benchmark.sh ssr`.
    func resolveSSRSteps(_ quality: RenderQuality) -> Int {
        if let override = ssrStepsOverride { return max(8, min(override, 1024)) }
        switch effectiveQuality(quality) {
        case .performance: return 128
        case .default:     return 256
        case .detail:      return 512
        }
    }

    /// Resolve a `.screenSpaceReflections` quality tier to the fraction of the resolution the
    /// march/blur/temporal passes run at (the composite upsamples back to full). Live trades
    /// reflection resolution for frame rate; export resolves to full (1.0) so exported art and
    /// snapshots are never downscaled. Mirrors `resolveRaymarchScale`.
    func resolveSSRScale(_ quality: RenderQuality) -> Double {
        if let s = ssrScaleOverride { return min(1.0, max(0.1, s)) }
        switch effectiveQuality(quality) {
        case .detail:      return 1.0
        case .default:     return 1.0    // full-res by default: reflections stay sharp + clean
        case .performance: return 0.5    // half-res only when trading quality for frame rate
        }
    }

    /// The fraction of the drawable the deferred ray-traced reflection layer renders at.
    /// `reflectionQuality(_:)` sets it: `.detail` and `.default` keep reflections full
    /// size, because a mirror image is the thing a viewer looks straight at, and
    /// `.performance` halves it in each direction, so the trace does a quarter of the work.
    /// The lit fragment already reads the layer as `position · scale / texture size`, so
    /// nothing in the shaders changes. An export resolves `.default` to `.detail`, so an
    /// exported frame and a snapshot render the layer full size and are never downscaled;
    /// only a frame that explicitly asked for `.performance` is halved. Mirrors
    /// `resolveSSRScale`.
    func resolveReflectionScale(_ quality: RenderQuality) -> Double {
        if let s = reflectionScaleOverride { return min(1.0, max(0.1, s)) }
        switch effectiveQuality(quality) {
        case .detail:      return 1.0
        case .default:     return 1.0
        case .performance: return 0.5
        }
    }

    /// Resolve a `.screenSpaceReflections` quality tier to the temporal history weight (the
    /// exponential-moving-average factor): more accumulation at higher tiers (steadier, slower to
    /// react), lighter at `.performance`. Reprojection + neighborhood clamping keep it responsive.
    func resolveSSRAlpha(_ quality: RenderQuality) -> Double {
        switch effectiveQuality(quality) {
        case .detail:      return 0.92
        case .default:     return 0.88
        case .performance: return 0.80
        }
    }

    /// Resolve a `.defocus` quality tier to a bokeh tap count, hardware-relative (richer on a
    /// dedicated-RT GPU). The software-RT (M1/M2) column is measured (`Scripts/benchmark.sh dof`
    /// on an M2 at 1080²: 96 taps hold ~120fps, 192 hold 60–90fps, 512 hold 15–30fps); the
    /// dedicated-RT column is a ~1.5× estimate until the benchmark is run on such a GPU (M3+).
    func resolveDofTaps(_ quality: RenderQuality) -> Int {
        if let override = dofTapsOverride { return max(8, min(override, 1024)) }
        // The tiers target frame-rate bands (measured on M2 at the 1080² `.defocus` layer via
        // `Scripts/benchmark.sh dof`): `.performance` ~120fps (96 taps = 126fps), `.default`
        // 60–90fps (192 = 69fps), `.detail` 15–30fps (512 = 27fps). The hw column (apple9+) is a
        // ~1.5× estimate until benchmarked on such a GPU.
        let hw = hasHardwareRayTracing
        switch effectiveQuality(quality) {
        case .performance: return hw ? 144 : 96
        case .default:     return hw ? 288 : 192
        case .detail:      return hw ? 768 : 512
        }
    }

    /// Resolve a raymarch quality setting to the camera-march and self-shadow step budgets.
    /// The `.default` tier returns the pre-dial constants (128 / 48) **exactly**, so a sketch
    /// that sets no quality renders byte-identically to before. The step budget is a fidelity
    /// (surface-resolution) knob, not a hardware-RT one, so the tiers are GPU-independent; the
    /// `.performance` *render-scale* drop (`resolveRaymarchScale`) is the bigger lever.
    private func resolveRaymarchSteps(_ setting: RaymarchQualitySetting) -> (march: Int32, shadow: Int32) {
        func pair(_ march: Int) -> (Int32, Int32) {
            let m = max(16, min(march, 512))
            return (Int32(m), Int32(max(8, m * 3 / 8)))   // shadow ≈ 3/8 of the march (128→48)
        }
        if let override = raymarchStepsOverride { return pair(override) }
        switch setting {
        case .absolute(let n): return pair(n)
        case .resolution: return (128, 48)   // a custom-resolution field keeps the default march budget
        case .tier(let quality):
            switch effectiveQuality(quality) {
            case .performance: return (64, 24)
            case .default:     return (128, 48)   // live `.default`; export lifts to `.detail`
            case .detail:      return (192, 72)
            }
        }
    }

    /// The internal live-preview render scale (a fraction of full resolution) for the raymarch,
    /// the dominant lever: the fullscreen sphere-tracer's cost is bound to pixel count (step
    /// count barely moves it), so the tiers scale resolution: `.detail` full (1.0), `.default`
    /// half (0.5, ¼ the pixels), `.performance` quarter (0.25, 1/16 the pixels), or an exact
    /// fraction from `raymarchResolution`. An upsample composites it back at full res. **This
    /// applies to the live preview only:** a `.detail` export marches at full resolution (scale
    /// 1.0 skips the pre-pass), so `--export`/snapshots are never downscaled and stay
    /// byte-identical. An absolute step count also marches at full resolution.
    func resolveRaymarchScale(_ setting: RaymarchQualitySetting) -> Double {
        switch setting {
        case .absolute: return 1.0
        case .resolution(let f): return min(1.0, max(0.1, f))   // an exact fraction (clamped)
        case .tier(let q):
            switch effectiveQuality(q) {
            case .detail:      return 1.0
            case .default:     return 0.5
            case .performance: return 0.25
            }
        }
    }

    /// The fraction of the screen the frame's 3D fields cover, estimated from each field's
    /// world AABB projected through the camera (per box, the smaller of its corners' clipped
    /// NDC bounding rect and their convex hull's area; summed and capped at 1). Conservative
    /// where the estimate can't be trusted: an unbounded field (a plane) or an AABB corner
    /// at/behind the camera counts as full coverage.
    ///
    /// This drives the *coverage-adaptive* raymarch scale: the resolved quality fraction is a
    /// marched-pixel *budget at full coverage*, not a fixed downscale. The pre-pass traces at
    /// `min(1, scale / sqrt(coverage))`, so a field that covers less of the screen is traced
    /// denser (up to full resolution, where the pre-pass is skipped entirely) for the same
    /// marched-pixel count the fraction allows when the field fills the screen. A dollied-out
    /// field therefore stays crisp instead of dissolving into an upsampled blur, and the cost
    /// never exceeds what the chosen fraction already costs at full coverage.
    func fieldScreenCoverage(_ groups: [SDF3DGroupInstance], viewProjection: simd_float4x4) -> Double {
        var total = 0.0
        for g in groups {
            if g.unbounded != 0 { return 1.0 }   // a plane spans the screen
            var lo = SIMD2<Float>(.greatestFiniteMagnitude, .greatestFiniteMagnitude)
            var hi = -lo
            var corners = [SIMD2<Double>](); corners.reserveCapacity(8)
            var conservative = false
            for i in 0..<8 {
                let corner = SIMD4<Float>((i & 1) == 0 ? g.boundsMin.x : g.boundsMax.x,
                                          (i & 2) == 0 ? g.boundsMin.y : g.boundsMax.y,
                                          (i & 4) == 0 ? g.boundsMin.z : g.boundsMax.z, 1)
                let clip = viewProjection * corner
                // A corner at or behind the camera plane: the projected-corner bound no longer
                // contains the box's silhouette (the camera is inside or beside the field), so
                // assume screen-filling rather than under-estimate.
                if clip.w <= 1e-4 { conservative = true; break }
                let ndc = SIMD2<Float>(clip.x, clip.y) / clip.w
                lo = simd_min(lo, ndc)
                hi = simd_max(hi, ndc)
                corners.append(SIMD2(Double(ndc.x), Double(ndc.y)))
            }
            if conservative { return 1.0 }
            let dx = Double(min(hi.x, 1) - max(lo.x, -1))
            let dy = Double(min(hi.y, 1) - max(lo.y, -1))
            if dx <= 0 || dy <= 0 { continue }   // fully off-screen: contributes nothing
            // The box's screen footprint is the projected corners' convex hull, and the
            // hull's area is well under its bounding rect's for the oblique views an orbit
            // camera spends most of its time in (a corner-on cube projects a hexagon). Both
            // are upper bounds of the true footprint, so take the smaller; the clipped rect
            // still caps a hull hanging partly off screen.
            total += min((dx * dy) / 4.0, Self.convexHullArea(corners) / 4.0)
        }
        return min(total, 1.0)
    }

    /// The area of a small point set's convex hull (Andrew's monotone chain + shoelace).
    static func convexHullArea(_ points: [SIMD2<Double>]) -> Double {
        guard points.count >= 3 else { return 0 }
        let p = points.sorted { $0.x != $1.x ? $0.x < $1.x : $0.y < $1.y }
        func cross(_ o: SIMD2<Double>, _ a: SIMD2<Double>, _ b: SIMD2<Double>) -> Double {
            (a.x - o.x) * (b.y - o.y) - (a.y - o.y) * (b.x - o.x)
        }
        var hull = [SIMD2<Double>]()
        for pass in 0..<2 {
            let run = pass == 0 ? p : p.reversed()
            let base = hull.count
            for pt in run {
                while hull.count >= base + 2,
                      cross(hull[hull.count - 2], hull[hull.count - 1], pt) <= 0 {
                    hull.removeLast()
                }
                hull.append(pt)
            }
            hull.removeLast()   // each chain's endpoint starts the other chain
        }
        var area = 0.0
        for i in 0..<hull.count {
            let a = hull[i], b = hull[(i + 1) % hull.count]
            area += a.x * b.y - b.x * a.y
        }
        return abs(area) / 2
    }

    /// Build the per-frame 3D camera constants (used by the points/mesh/raymarch pipelines),
    /// including the dial-resolved march-step budget. `nil` when no 3D camera is active. Shared
    /// by the main `encode` and the half-res raymarch pre-pass so they can't drift.
    func makeRaymarchUniforms3D(_ drawer: Drawer, viewport: SIMD2<Float>,
                                jitter: SIMD2<Float> = .zero) -> Uniforms3D? {
        guard let camera = drawer.camera3D else { return nil }
        let aspect = viewport.y > 0 ? Double(viewport.x / viewport.y) : 1
        let proj = MetalRenderer.jittered(camera.projectionMatrix(aspect: aspect), by: jitter)
        let steps = resolveRaymarchSteps(drawer.raymarchQualitySetting)
        return Uniforms3D(view: camera.viewMatrix, projection: proj,
                          inverseViewProjection: simd_inverse(proj * camera.viewMatrix),
                          viewport: viewport,
                          raymarchSteps: SIMD2<Float>(Float(steps.march), Float(steps.shadow)),
                          raymarchScale: SIMD2<Float>(1, 0))
    }

    /// Resolve this frame's lighting + shadow bindings (caster index, RT vs map kind, and the
    /// real-or-dummy shadow textures), the block shared by the main `encode` and the half-res
    /// raymarch pre-pass so a marched field shades identically at half resolution. `shadowAccel`
    /// is the frame's acceleration structure (RT point shadows), nil otherwise.
    func resolveFieldLighting(_ drawer: Drawer, shadowMap: MTLTexture?, shadowCube: MTLTexture?,
                                      shadowAccelPresent: Bool, reflectAccelPresent: Bool = false,
                                      gi: GIResolved? = nil)
        -> (lighting: OllinLighting, shadowTexture: MTLTexture?, shadowCubeTexture: MTLTexture?) {
        var lighting = drawer.makeLighting()
        if shadowMap == nil && shadowCube == nil && !shadowAccelPresent && drawer.sdf3DGroups.isEmpty {
            lighting.shadowLight = -1
        }
        if shadowAccelPresent, lighting.shadowKind == 1 || casterGPUKind(lighting) >= 3 {
            lighting.shadowKind = 2
            lighting.shadowSamples = resolveShadowSamples(drawer.shadowQualitySetting)
            // A traced *panel* caster reads `shadowDepthB` as the sampled panel's scale
            // about its center (the shadowSoftness dial; 0.5 default = the physical
            // extent); the packing left the 2D map's linearization term there.
            if casterGPUKind(lighting) >= 3 {
                lighting.shadowDepthB = Float(drawer.shadowSoftnessAmount * 2)
            }
        } else if lighting.shadowLight >= 0 && lighting.shadowKind == 0 {
            lighting.shadowSamples = resolveShadowTaps2D(drawer.shadowQualitySetting)
        }
        finalizeShadowCasters(drawer, &lighting, renderedMap: shadowMap != nil,
                              renderedCube: shadowCube != nil, traced: shadowAccelPresent)
        // Image-based lighting, mirroring the main encode's setup (resolveIBL already ran
        // this frame), so a field marched at half resolution takes the same environment
        // ambient, and traces the same reflections, as the full-res inline march.
        if lighting.enabled != 0, drawer.environment != nil, currentIBL != nil {
            lighting.iblEnabled = 1
            lighting.iblIntensity = Float(drawer.environment?.intensity ?? 1) * currentIBLNormalization
            lighting.iblMaxMip = Float(currentIBLMaxMip)
            lighting.iblRotation = Float(drawer.environment?.rotation ?? 0)
        } else {
            lighting.iblEnabled = 0
        }
        // Area lights, mirroring the main encode's LTC resolve, so a field marched at
        // half resolution takes the same panel light as the full-res inline march.
        if lighting.enabled != 0,
           drawer.lights.contains(where: { $0.kind == .rect || $0.kind == .disk || $0.kind == .tube }) {
            lighting.ltcEnabled = ensureLTCTables() ? 1 : 0
        }
        // Light shaping, same mirroring (the profile/cookie lists were rebuilt by this
        // pass's own `makeLighting`, so the layer indices agree with the packed lights).
        if lighting.enabled != 0, !drawer.usedIESProfiles.isEmpty {
            lighting.iesEnabled = ensureIESArray(drawer.usedIESProfiles) ? 1 : 0
        }
        if lighting.enabled != 0, !drawer.usedLightCookies.isEmpty {
            lighting.cookieEnabled = ensureCookieArray(drawer.usedLightCookies) ? 1 : 0
        }
        if reflectAccelPresent { lighting.rtReflections = 1 }
        // Global illumination, same mirroring: a field marched at half resolution takes
        // the same probe-sampled bounce light as the full-res inline march.
        packGI(gi, into: &lighting, intensity: drawer.giIntensity)
        // Atmosphere, same mirroring: the reduced-res field pass fogs its hits and marches
        // its shafts with the same step budget as the main pass.
        if lighting.fogColor.w > 0 {
            lighting.fogParams2.x = Float(resolveVolumetricSteps(drawer.volumetricQualitySetting))
        }
        return (lighting, shadowMap ?? ensureDummyShadowMap(), shadowCube ?? ensureDummyPointShadowMap())
    }

    /// Sphere-trace every `.normal`-blend field batch into the cached reduced-resolution color +
    /// depth targets (the reduced raymarch tiers / `raymarchResolution`). Returns the targets
    /// plus the subrect they render (as the upsample's UV mapping) for the main pass to
    /// upsample + composite, or `nil` when the reduced-res pass doesn't apply (full-res tier,
    /// no fields, the fields small enough on screen that the coverage-adaptive scale reaches
    /// full resolution, or any field uses a non-`.normal` blend, which would not composite
    /// premultiplied-over, so the whole frame falls back to the full-res inline march).
    ///
    /// The resolved scale is a *budget at full coverage* (see `fieldScreenCoverage`): the
    /// internal resolution rises as the fields' projected screen area shrinks, so a dollied-out
    /// field is traced dense and crisp for the same marched-pixel cost. The targets are
    /// grow-only and the pass renders into a `w × h` viewport subrect, so a continuous dolly
    /// (the scale drifting every frame) never reallocates textures per frame.
    ///
    /// The field batches share one depth-tested target, so they occlude one another exactly as
    /// in the full-res pass; each is drawn with its own material, the same fragment + bindings
    /// as the inline path.
    func encodeRaymarchHalfRes(_ drawer: Drawer, into cb: MTLCommandBuffer,
                                       groupBuffer: MTLBuffer?, nodeBuffer: MTLBuffer?,
                                       uniforms3D: Uniforms3D, lighting: OllinLighting,
                                       shadowTexture: MTLTexture?, shadowCubeTexture: MTLTexture?,
                                       traceAccel: MTLAccelerationStructure? = nil,
                                       meshBuffer: MTLBuffer? = nil,
                                       reflectGeoOffsets: MTLBuffer? = nil,
                                       giTextures: (irradiance: MTLTexture, depth: MTLTexture, offsets: MTLTexture)? = nil,
                                       fullWidth: Int, fullHeight: Int)
        -> (color: MTLTexture, depth: MTLTexture, region: SIMD4<Float>)? {
        let baseScale = resolveRaymarchScale(drawer.raymarchQualitySetting)
        let groups3D = drawer.sdf3DGroups
        guard baseScale < 1.0, !groups3D.isEmpty, let groupBuffer, let nodeBuffer else { return nil }
        for b in drawer.batches where b.kind == .sdfGroup3D && b.blendMode != .normal { return nil }

        // Coverage-adaptive scale: trace denser as the fields cover less of the screen, at the
        // same marched-pixel budget. At/above full resolution skip the pre-pass entirely: the
        // inline march is both crisper (no upsample) and cheaper (no second pass).
        let coverage = fieldScreenCoverage(groups3D,
                                           viewProjection: uniforms3D.projection * uniforms3D.view)
        let scale = min(1.0, baseScale / max(coverage.squareRoot(), 1e-3))
        guard scale < 1.0 else { return nil }

        let w = max(1, Int((Double(fullWidth) * scale).rounded()))
        let h = max(1, Int((Double(fullHeight) * scale).rounded()))
        if halfResColor == nil || halfResDepth == nil
            || halfResSize.width < w || halfResSize.height < h {
            let tw = max(halfResSize.width, w), th = max(halfResSize.height, h)
            guard let c = makeHalfResColor(width: tw, height: th),
                  let d = makeHalfResDepth(width: tw, height: th) else { return nil }
            halfResColor = c; halfResDepth = d; halfResSize = (tw, th)
        }
        guard let color = halfResColor, let depth = halfResDepth,
              let pipe = try? pipeline(.raymarchHalfRes(depth: depthPixelFormat)) else { return nil }

        // Upload the field buffers here: the pre-pass runs before the main encode (which
        // re-uploads the same bytes), and when the frame casts no shadow nothing else has
        // uploaded them yet, so the GPU would otherwise march stale geometry.
        groups3D.withUnsafeBytes { groupBuffer.contents().copyMemory(from: $0.baseAddress!, byteCount: $0.count) }
        let nodes3D = drawer.sdf3DNodes
        if !nodes3D.isEmpty {
            nodes3D.withUnsafeBytes { nodeBuffer.contents().copyMemory(from: $0.baseAddress!, byteCount: $0.count) }
        }

        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = color
        pass.colorAttachments[0].loadAction = .clear
        pass.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)  // over transparent → premultiplied
        pass.colorAttachments[0].storeAction = .store
        pass.depthAttachment.texture = depth
        pass.depthAttachment.loadAction = .clear
        pass.depthAttachment.clearDepth = 1.0
        pass.depthAttachment.storeAction = .store
        guard let enc = countedEncoder(cb, pass) else { return nil }
        enc.setViewport(MTLViewport(originX: 0, originY: 0, width: Double(w), height: Double(h), znear: 0, zfar: 1))
        enc.setRenderPipelineState(pipe)
        enc.setDepthStencilState(depthTestState)
        var u3 = uniforms3D
        // The internal render scale, so the fragment's pixel-cone AA matches the texel this
        // subrect actually shades (a full-res cone under-blurs the low-res image and the
        // upsample magnifies the aliasing into a staircase).
        u3.raymarchScale = SIMD2<Float>(Float(scale), 0)
        var lit = lighting
        enc.setFragmentBuffer(nodeBuffer, offset: 0, index: 1)
        enc.setFragmentBytes(&lit, length: MemoryLayout<OllinLighting>.stride, index: 2)
        enc.setFragmentBytes(&u3, length: MemoryLayout<Uniforms3D>.stride, index: 4)
        enc.setFragmentTexture(shadowTexture, index: 1)
        enc.setFragmentTexture(shadowCubeTexture, index: 2)
        if let shadowSampler { enc.setFragmentSamplerState(shadowSampler, index: 1) }
        if let shadowCubeSampler { enc.setFragmentSamplerState(shadowCubeSampler, index: 2) }
        let strip = gradientStripTexture(for: drawer.gradientRows)
        enc.setFragmentTexture(strip, index: 0)
        enc.setFragmentSamplerState(imageSampler, index: 0)
        // The image-based-lighting maps (tex 4/5/6), matching the main pass, so a half-res
        // field takes the same environment ambient; stand-ins when no environment baked.
        if iblPlaceholderCube == nil { iblPlaceholderCube = makeCubeTexture(face: 1, mipped: false) }
        enc.setFragmentTexture(currentIBLIrradiance ?? iblPlaceholderCube, index: 4)
        enc.setFragmentTexture(currentIBLPrefilter ?? iblPlaceholderCube, index: 5)
        enc.setFragmentTexture(iblBRDFLUTTexture ?? strip, index: 6)
        // The LTC tables (tex 8/9) for area lights, matching the main pass; never-sampled
        // stand-ins when unloaded (`lighting.ltcEnabled` gates the read).
        enc.setFragmentTexture(ltcMatTexture ?? strip, index: 8)
        enc.setFragmentTexture(ltcAmpTexture ?? strip, index: 9)
        // The light-shaping arrays (tex 10/11), matching the main pass; the array
        // stand-in otherwise (`iesEnabled`/`cookieEnabled` gate).
        enc.setFragmentTexture(iesArrayTexture ?? shapingStandIn(), index: 10)
        enc.setFragmentTexture(cookieArrayTexture ?? shapingStandIn(), index: 11)
        // The sheen directional-albedo LUT (tex 12), matching the main pass; a
        // never-sampled stand-in unless a material carries sheen.
        enc.setFragmentTexture(sheenLUT ?? strip, index: 12)
        // The GI probe atlases (tex 13/14), matching the main pass; never-sampled
        // stand-ins unless the frame resolved a probe field (`giOrigin.w` gates).
        if rayTracedShadows {
            enc.setFragmentTexture(giTextures?.irradiance ?? strip, index: 13)
            enc.setFragmentTexture(giTextures?.depth ?? strip, index: 14)
            enc.setFragmentTexture(giTextures?.offsets ?? strip, index: 15)
        }
        // The mesh acceleration structure at buffer 5, matching the main pass: RT point
        // shadows received by the field, and the reflection trace when `rtReflections`
        // is set. A dummy when neither is active, never traced.
        if let accel = rayTracedShadows ? (traceAccel ?? ensureDummyShadowAccel()) : nil {
            useTracedScene(enc, accel)
            enc.setFragmentAccelerationStructure(accel, bufferIndex: 5)
        }
        // The reflection-trace inputs (buffers 6/7), read only under `lighting.rtReflections`;
        // the offsets dummy stands in for both on a mesh-less RT frame (see the main pass).
        if rayTracedShadows {
            let offsets = reflectGeoOffsets ?? ensureDummyGeoOffsets()
            if let verts = meshBuffer ?? offsets {
                enc.setFragmentBuffer(verts, offset: 0, index: 6)
            }
            if let offsets {
                enc.setFragmentBuffer(offsets, offset: 0, index: 7)
            }
        }

        let group3DStride = MemoryLayout<SDF3DGroupInstance>.stride
        let batches = drawer.batches
        for i in batches.indices {
            let batch = batches[i]
            guard batch.kind == .sdfGroup3D else { continue }
            let next = i + 1 < batches.count ? batches[i + 1] : nil
            let end = next?.sdf3DGroupStart ?? groups3D.count
            let count = end - batch.sdf3DGroupStart
            guard count > 0 else { continue }
            enc.setFragmentBuffer(groupBuffer, offset: batch.sdf3DGroupStart * group3DStride, index: 0)
            var finish = batch.finish
            enc.setFragmentBytes(&finish, length: MemoryLayout<OllinMaterial>.stride, index: 3)
            enc.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3, instanceCount: count)
        }
        enc.endEncoding()
        // The subrect the pass rendered, as the upsample's UV mapping: .xy scales full-frame UV
        // into the subrect, .zw clamps half a texel inside it so bilinear filtering never reads
        // the (cleared) texels past the marched region of the grow-only texture.
        let region = SIMD4<Float>(Float(w) / Float(halfResSize.width),
                                  Float(h) / Float(halfResSize.height),
                                  (Float(w) - 0.5) / Float(halfResSize.width),
                                  (Float(h) - 0.5) / Float(halfResSize.height))
        return (color, depth, region)
    }

    /// The number of raymarched SDF fields casting onto meshes under a point/ray-traced caster
    /// (0 for a mesh-only or directional/spot scene, the byte-identical mesh path). Any caster in
    /// the frame's list turns it on, not the primary alone: the mesh fragments march one channel
    /// per such caster. A 2D caster is not counted here because a field renders into its own map
    /// layer instead. Shared by the main encode and the half-res field-shadow pre-pass so both
    /// agree on whether the cast is on.
    func resolveFieldCasterCount(_ lighting: OllinLighting, _ drawer: Drawer) -> Int32 {
        guard !drawer.sdf3DGroups.isEmpty,
              shadowCasters(lighting).contains(where: { $0.kind != 0 }) else { return 0 }
        return Int32(drawer.sdf3DGroups.count)
    }

    /// The GPU kind of this frame's shadow-casting light (0 directional / 1 point / 2 spot /
    /// 3 rect / 4 disk), or -1 with no caster. The routing that differs by caster shape (an
    /// area caster traces the panel on an RT device, else renders the spot-style 2D map)
    /// reads it from the packed uniform's fixed-size light array.
    func casterGPUKind(_ lighting: OllinLighting) -> Int32 {
        guard lighting.shadowLight >= 0 else { return -1 }
        return withUnsafePointer(to: lighting.lights) { ptr in
            ptr.withMemoryRebound(to: OllinLight.self, capacity: Int(OLLIN_MAX_LIGHTS)) { buf in
                buf[Int(lighting.shadowLight)].kind
            }
        }
    }

    /// The point/RT field-cast shadow is per-receiver-pixel (the lit mesh fragments march the field
    /// toward the light), which is GPU-heavy on a screen-filling receiver. The live RenderQuality
    /// path computes it once at reduced resolution here (re-rendering the receiver meshes,
    /// depth-tested so the front surface's factor wins, with a fragment that outputs only the
    /// field-shadow factor), and the full-res mesh pass samples it (`fieldShadowMode == 1`). `nil`
    /// at the full-res tier (`.detail`/export march inline → byte-identical), with no fields, or no
    /// point/RT caster. Mirrors `encodeRaymarchHalfRes` (same scale dial, same live-only gating).
    /// Build the 3D camera constants (`Uniforms3D`) for a camera + viewport: the same
    /// view / projection / inverse the geometry pass binds at vertex index 2. Shared with
    /// the inline build in `encode` so the auxiliary mesh passes (the normal G-buffer)
    /// build them identically.
    func makeUniforms3D(_ drawer: Drawer, camera: Camera3D, viewport: SIMD2<Float>,
                        jitter: SIMD2<Float> = .zero) -> Uniforms3D {
        let aspect = viewport.y > 0 ? Double(viewport.x / viewport.y) : 1
        let proj = MetalRenderer.jittered(camera.projectionMatrix(aspect: aspect), by: jitter)
        let steps = resolveRaymarchSteps(drawer.raymarchQualitySetting)
        return Uniforms3D(view: camera.viewMatrix, projection: proj,
                          inverseViewProjection: simd_inverse(proj * camera.viewMatrix),
                          viewport: viewport,
                          raymarchSteps: SIMD2<Float>(Float(steps.march), Float(steps.shadow)),
                          raymarchScale: SIMD2<Float>(1, 0))
    }

    // MARK: - Temporal anti-aliasing

    /// Premultiply an NDC translate onto a projection: clip.xy += jitter · clip.w, a
    /// constant sub-pixel shift after the perspective divide, exact for perspective,
    /// orthographic, and intrinsic projections alike (the z and w rows are untouched,
    /// so depth values and `depth(at:)` are unchanged). Zero jitter returns the
    /// projection untouched, so a TAA-off frame is byte-identical by construction.
    static func jittered(_ proj: simd_float4x4, by ndc: SIMD2<Float>) -> simd_float4x4 {
        guard ndc != .zero else { return proj }
        var j = matrix_identity_float4x4
        j.columns.3.x = ndc.x
        j.columns.3.y = ndc.y
        return j * proj
    }

    /// The sub-pixel jitter sequence: a low-discrepancy progressive 2D set (radical
    /// inverses in bases 2 and 3), offsets in [-0.5, 0.5]² pixels. The live TAA path
    /// cycles the first 8 by frame count; the export supersample takes the first N
    /// by tier; the temporal upscaler cycles up to all 32 (a scaler reconstructing
    /// s× the pixels needs about 8·s² distinct phases to visit every output
    /// position). One shared table so every consumer samples the same positions,
    /// and a progressive sequence so a prefix is itself well distributed.
    static let taaJitterOffsets: [SIMD2<Float>] = (0..<32).map {
        SIMD2(Float(halton($0 + 1, base: 2)) - 0.5, Float(halton($0 + 1, base: 3)) - 0.5)
    }

    /// The jitter for sequence position `index`, as the NDC offset
    /// `makeUniforms3D(jitter:)` applies (pixel offsets scaled onto the ±1 NDC span;
    /// NDC y runs up while pixel y runs down, hence the sign).
    func taaJitterNDC(index: Int, width: Int, height: Int) -> SIMD2<Float> {
        let px = MetalRenderer.taaJitterOffsets[index % MetalRenderer.taaJitterOffsets.count]
        return SIMD2(2 * px.x / Float(width), -2 * px.y / Float(height))
    }

    /// Whether temporal AA runs this frame: the sketch asked and a 3D camera is
    /// active. Notes once when asked without a camera (a 2D frame has nothing to
    /// jitter; its primitives carry analytic AA already).
    func temporalAAActive(_ drawer: Drawer) -> Bool {
        guard drawer.temporalAAEnabled else { return false }
        guard drawer.camera3D != nil else {
            drawer.noteOnce("temporalAntialiasing() applies to the 3D scene; without an active camera the frame is unchanged.")
            return false
        }
        return true
    }

    /// Samples for the historyless (headless/export) temporal-AA supersample: the
    /// within-one-frame equivalent of the live accumulation, deterministic (the fixed
    /// jitter sequence, in order), so exports and snapshots reproduce bit-exactly.
    func resolveTAASamples() -> Int {
        switch effectiveQuality(.default) {
        case .performance: return 4
        case .default:     return 8
        case .detail:      return 16
        }
    }

    /// The mover-velocity pass (live temporal AA): re-render this frame's declared
    /// movers (`withMotion` ranges) into an rg16Float screen-motion texture, in
    /// pixels, y-down, previous minus current (the value points at where the
    /// pixel's content came from), both view·projections **unjittered** like the
    /// resolve's own reprojection. Two phases in one encoder: everything that is
    /// *not* a mover draws depth-only first, so geometry in front of a mover keeps
    /// it from writing velocity through its occluder; then each mover range draws
    /// with its `previousOfCurrent` transform. Unwritten texels keep the sentinel
    /// clear, which the resolve reads as "use the depth-reprojection fallback", so
    /// the shipped camera path is untouched wherever no mover rendered. Returns
    /// nil (encoding nothing) when TAA isn't running, the frame declared no
    /// movers, there's no history yet, or on a same-frame repeat (the resolve
    /// serves its accumulated front and reads no velocity).
    func encodeVelocityPass(_ drawer: Drawer, into cb: MTLCommandBuffer,
                            meshBuffer: MTLBuffer?, width: Int, height: Int) -> MTLTexture? {
        guard temporalAAActive(drawer), !statefulEncodeIsRepeat,
              let slot = taaHistory, slot.valid, slot.w == width, slot.h == height
        else { return nil }
        return encodeMoverVelocity(drawer, into: cb, meshBuffer: meshBuffer,
                                   width: width, height: height,
                                   previousViewProjection: slot.previousViewProjection)
    }

    /// The mover-velocity encode core, shared by the temporal-AA pass above (which
    /// reprojects through its history slot's stored matrix) and the motion-blur
    /// chain (which reprojects through the drawer's previous camera, so it also
    /// runs on repeats and on the headless export path, where no slot exists).
    /// Same pipelines, same cached target, byte-identical encoding for a given
    /// previous view projection.
    func encodeMoverVelocity(_ drawer: Drawer, into cb: MTLCommandBuffer,
                             meshBuffer: MTLBuffer?, width: Int, height: Int,
                             previousViewProjection: simd_float4x4) -> MTLTexture? {
        guard let camera = drawer.camera3D, let meshBuffer,
              !drawer.moverRanges.isEmpty,
              let velPipe = try? pipeline(.meshVelocity(depth: depthPixelFormat)),
              let occPipe = try? pipeline(.meshVelocityOccluder(depth: depthPixelFormat))
        else { return nil }
        let target: (tex: MTLTexture, depth: MTLTexture, w: Int, h: Int)
        if let cached = velocityCache, cached.w == width, cached.h == height {
            target = cached
        } else {
            let colorDesc = MTLTextureDescriptor.texture2DDescriptor(
                pixelFormat: .rg16Float, width: width, height: height, mipmapped: false)
            colorDesc.usage = [.renderTarget, .shaderRead]
            colorDesc.storageMode = .private
            let depthDesc = MTLTextureDescriptor.texture2DDescriptor(
                pixelFormat: depthPixelFormat, width: width, height: height, mipmapped: false)
            depthDesc.usage = .renderTarget
            depthDesc.storageMode = .private
            guard let tex = device.makeTexture(descriptor: colorDesc),
                  let depth = device.makeTexture(descriptor: depthDesc) else { return nil }
            target = (tex, depth, width, height)
            velocityCache = target
        }
        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = target.tex
        pass.colorAttachments[0].loadAction = .clear
        pass.colorAttachments[0].clearColor = MTLClearColor(
            red: Double(OLLIN_VELOCITY_NONE), green: 0, blue: 0, alpha: 0)
        pass.colorAttachments[0].storeAction = .store
        pass.depthAttachment.texture = target.depth
        pass.depthAttachment.loadAction = .clear
        pass.depthAttachment.clearDepth = 1.0
        pass.depthAttachment.storeAction = .dontCare
        guard let enc = countedEncoder(cb, pass) else { return nil }
        enc.setViewport(MTLViewport(originX: 0, originY: 0, width: Double(width),
                                    height: Double(height), znear: 0, zfar: 1))
        enc.setDepthStencilState(depthTestState)
        // Unjittered on both ends (the resolve's own rule): `makeUniforms3D`'s
        // default zero jitter leaves the projection untouched, and the previous
        // view projection arrives unjittered from either caller.
        var u3 = makeUniforms3D(drawer, camera: camera,
                                viewport: SIMD2(Float(width), Float(height)))
        enc.setVertexBytes(&u3, length: MemoryLayout<Uniforms3D>.stride, index: 2)
        enc.setFragmentBytes(&u3, length: MemoryLayout<Uniforms3D>.stride, index: 2)
        let meshStride = MemoryLayout<OllinMeshVertex>.stride
        let meshCount = drawer.meshVertices.count
        let batches = drawer.batches
        let ranges = drawer.moverRanges
        // Phase 1: the occluders, depth only. Wireframes skip (their faces are
        // see-through, the normal G-buffer's rule) and a render target's meshes
        // never join (TAA is main-canvas only); mover ranges are cut out of their
        // batches' runs, which stays exact because ranges record in append order.
        enc.setRenderPipelineState(occPipe)
        for i in batches.indices {
            let batch = batches[i]
            guard batch.kind == .mesh3D, batch.target == nil, !batch.meshWireframe else { continue }
            let next = i + 1 < batches.count ? batches[i + 1] : nil
            let end = next?.meshStart ?? meshCount
            var cursor = batch.meshStart
            for r in ranges where r.start >= batch.meshStart && r.start < end {
                if r.start > cursor {
                    enc.setVertexBuffer(meshBuffer, offset: cursor * meshStride, index: 0)
                    enc.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: r.start - cursor)
                }
                cursor = r.start + r.count
            }
            if cursor < end {
                enc.setVertexBuffer(meshBuffer, offset: cursor * meshStride, index: 0)
                enc.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: end - cursor)
            }
        }
        // Phase 2: the movers, each carried back through last frame's matrices.
        enc.setRenderPipelineState(velPipe)
        for r in ranges {
            var vu = OllinVelocityUniforms(previousViewProjection: previousViewProjection,
                                           previousOfCurrent: r.previousOfCurrent)
            enc.setVertexBytes(&vu, length: MemoryLayout<OllinVelocityUniforms>.stride, index: 3)
            enc.setVertexBuffer(meshBuffer, offset: r.start * meshStride, index: 0)
            enc.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: r.count)
        }
        enc.endEncoding()
        return target.tex
    }

    /// TEST SEAM: run the mover-velocity pass for `drawer`'s recorded frame
    /// against an explicit previous view·projection and read the texture back as
    /// row-major (width × height) pixel deltas. Uploads the mesh vertices itself
    /// and fabricates a valid history slot, so a test can drive the live-only
    /// pass deterministically; nil when the pass declines to run (the same gates
    /// a live frame applies). Tests only.
    func debugVelocityReadback(_ drawer: Drawer, width: Int, height: Int,
                               previousViewProjection: simd_float4x4) -> [SIMD2<Float>]? {
        guard let meshBuffer = exportMeshBuffer(for: tracedMeshVertexCount(drawer)) else { return nil }
        if !drawer.meshVertices.isEmpty {
            drawer.meshVertices.withUnsafeBytes { raw in
                meshBuffer.contents().copyMemory(from: raw.baseAddress!, byteCount: raw.count)
            }
        }
        let slot: SSRHistorySlot
        if let existing = taaHistory, existing.w == width, existing.h == height {
            slot = existing
        } else {
            guard let a = makeFloatResolve(width: width, height: height),
                  let b = makeFloatResolve(width: width, height: height) else { return nil }
            slot = SSRHistorySlot(a: a, b: b, w: width, h: height)
            taaHistory = slot
        }
        slot.valid = true
        slot.previousViewProjection = previousViewProjection
        guard let cb = commandQueue.makeCommandBuffer(),
              let tex = encodeVelocityPass(drawer, into: cb, meshBuffer: meshBuffer,
                                           width: width, height: height) else { return nil }
        let bytesPerRow = width * 4
        guard let readback = device.makeBuffer(length: bytesPerRow * height,
                                               options: .storageModeShared),
              let blit = cb.makeBlitCommandEncoder() else { return nil }
        blit.copy(from: tex, sourceSlice: 0, sourceLevel: 0,
                  sourceOrigin: MTLOrigin(x: 0, y: 0, z: 0),
                  sourceSize: MTLSize(width: width, height: height, depth: 1),
                  to: readback, destinationOffset: 0,
                  destinationBytesPerRow: bytesPerRow,
                  destinationBytesPerImage: bytesPerRow * height)
        blit.endEncoding()
        cb.commit()
        cb.waitUntilCompleted()
        // Decode the rg16Float halves by bit pattern (portable half -> float).
        func half(_ h: UInt16) -> Float {
            let sign = Float((h & 0x8000) != 0 ? -1 : 1)
            let exponent = Int((h >> 10) & 0x1F)
            let mantissa = Int(h & 0x3FF)
            if exponent == 0 {
                return sign * Float(mantissa) * exp2(Float(-24))
            }
            if exponent == 0x1F {
                return mantissa == 0 ? sign * .infinity : .nan
            }
            return sign * (1 + Float(mantissa) / 1024) * exp2(Float(exponent - 15))
        }
        let words = readback.contents().bindMemory(to: UInt16.self, capacity: width * height * 2)
        return (0..<(width * height)).map {
            SIMD2(half(words[$0 * 2]), half(words[$0 * 2 + 1]))
        }
    }

    /// Temporal anti-aliasing resolve (the live path): reproject last frame's
    /// accumulation by the camera's motion (per-pixel resolved depth through the
    /// previous frame's unjittered view·projection), rectify it against the current
    /// 3×3 neighborhood (a moment-based clip in luma-compressed YCoCg), and blend as
    /// an adaptive exponential moving average into the history's back buffer, which
    /// becomes the presented frame. Returns `resolved` untouched when TAA isn't
    /// active this frame or the depth resolve is missing (byte-identical); a
    /// same-frame repeat serves the already-accumulated front rather than stepping
    /// the average again, like the other stateful passes. `jitter` must be the NDC
    /// offset this frame's 3D projection rasterized under, so the reconstruction
    /// matrix matches the depth buffer.
    func applyTemporalAA(_ drawer: Drawer, resolved: MTLTexture, depth: MTLTexture?,
                         velocity: MTLTexture? = nil,
                         jitter: SIMD2<Float>, into cb: MTLCommandBuffer,
                         width: Int, height: Int) -> MTLTexture {
        guard temporalAAActive(drawer), let camera = drawer.camera3D, let depth else {
            return resolved
        }
        if statefulEncodeIsRepeat, let slot = taaHistory, slot.valid,
           slot.w == width, slot.h == height {
            return slot.flipped ? slot.b : slot.a
        }
        let slot: SSRHistorySlot
        if let existing = taaHistory, existing.w == width, existing.h == height {
            slot = existing
        } else {
            guard let a = makeFloatResolve(width: width, height: height),
                  let b = makeFloatResolve(width: width, height: height) else { return resolved }
            let clear = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)
            clearFloatTexture(a, color: clear, into: cb)
            clearFloatTexture(b, color: clear, into: cb)
            slot = SSRHistorySlot(a: a, b: b, w: width, h: height)
            taaHistory = slot
        }
        let front = slot.flipped ? slot.b : slot.a
        let back = slot.flipped ? slot.a : slot.b
        let aspect = height > 0 ? Double(width) / Double(height) : 1
        // Both reprojection matrices are UNJITTERED: the jitter must be removed
        // from the velocity computation entirely (the published rule). Reconstruct
        // through the jittered inverse instead and a static camera reprojects the
        // history at uv minus this frame's jitter, so the history is sub-pixel
        // resampled by a different offset every frame and its content random-walks
        // with variance Var(jitter)/(1-feedback²), which read as a measured
        // px-scale live oscillation on every hairline edge. Unjittered on both
        // ends, a still pixel reprojects to exactly itself; the jittered depth
        // makes the reconstruction at most half a pixel off, which only perturbs
        // the *velocity* under camera motion, never the still case.
        let viewProjection = camera.projectionMatrix(aspect: aspect) * camera.viewMatrix
        let invVP = simd_inverse(viewProjection)
        var params = [SIMD4<Float>](repeating: .zero, count: 12)
        params[0] = SIMD4(1 / Float(width), 1 / Float(height), slot.valid ? 1 : 0, 0)
        // The jitter back in pixels (the resolve re-centers the current frame's
        // reconstruction on the unjittered pixel; NDC y runs opposite pixel y).
        // params[1].z: whether a mover-velocity texture rendered this frame.
        params[1] = SIMD4(jitter.x * Float(width) / 2, -jitter.y * Float(height) / 2,
                          velocity != nil ? 1 : 0, 0)
        params[4] = invVP.columns.0; params[5] = invVP.columns.1
        params[6] = invVP.columns.2; params[7] = invVP.columns.3
        let pv = slot.previousViewProjection
        params[8] = pv.columns.0; params[9] = pv.columns.1
        params[10] = pv.columns.2; params[11] = pv.columns.3
        encodeEffectFragment("ollin_fx_taa_resolve",
                             inputs: [resolved, depth, front, velocity ?? front],
                             output: back, params: params, into: cb)
        slot.previousViewProjection = viewProjection
        slot.valid = true
        slot.flipped.toggle()   // the just-written back is next frame's (and any repeat's) front
        return back
    }

    // MARK: - Motion blur

    /// Whether motion blur runs this frame: the sketch asked (with a nonzero
    /// shutter) and a 3D camera is active. Notes once when asked without a
    /// camera (a 2D frame has no depth to read motion from, and its content
    /// holds still by design).
    func motionBlurActive(_ drawer: Drawer) -> Bool {
        guard drawer.motionBlurEnabled, drawer.motionBlurShutter > 0 else { return false }
        guard drawer.camera3D != nil else {
            drawer.noteOnce("motionBlur() applies to the 3D scene; without an active camera the frame is unchanged.")
            return false
        }
        return true
    }

    /// Reconstruction taps per pixel along the dominant velocity, resolved from
    /// the frame-wide automatic quality (the temporal-AA sample rule: no
    /// per-feature knob; export's automatic `.detail` lifts it). Odd, so the
    /// tap comb is symmetric about the center pixel.
    func resolveMotionBlurSamples() -> Int {
        switch effectiveQuality(.default) {
        case .performance: return 9
        case .default:     return 15
        case .detail:      return 27
        }
    }

    /// The blur's tile size and maximum streak radius k, in pixels: resolution-
    /// relative so a streak covers the same fraction of the frame at any canvas
    /// size (h/36 reproduces the published 20 px at 720 tall), floored so tiles
    /// stay meaningful on tiny canvases and capped where a huge k would thrash
    /// the gather's texture locality.
    static func motionBlurTileSize(height: Int) -> Int {
        min(64, max(16, Int((Double(height) / 36).rounded())))
    }

    /// Apply the motion-blur reconstruction to the resolved linear frame,
    /// returning the texture the frame filters should read: the input itself
    /// when the blur isn't active, there's no depth resolve, no frame has gone
    /// before (nothing has moved), or the frame is exactly still (the camera
    /// float-equal to last frame's and no mover recorded), so a static scene
    /// with the blur on stays byte-identical to one without it.
    ///
    /// `moverVelocity` is the temporal-AA velocity texture when that pass
    /// already rendered this frame; otherwise (blur without TAA, a same-frame
    /// repeat, the headless export) the chain encodes its own through the same
    /// core against the drawer's previous camera, which is the same matrix the
    /// TAA slot carries when both are on, so the two sources cannot disagree.
    /// `moverScale` rescales a mover texture rendered at a different pixel size
    /// than this blur (the temporal upscaler's render-resolution velocity feeding
    /// a full-resolution blur); (1, 1) otherwise, which multiplies exactly and
    /// keeps the plain path byte-identical.
    func applyMotionBlur(_ drawer: Drawer, resolved: MTLTexture, depth: MTLTexture?,
                         moverVelocity: MTLTexture?, meshBuffer: MTLBuffer?,
                         into cb: MTLCommandBuffer, width: Int, height: Int,
                         pooled: Bool, moverScale: SIMD2<Float> = SIMD2(1, 1)) -> MTLTexture {
        guard motionBlurActive(drawer), let camera = drawer.camera3D, let depth,
              let previous = drawer.previousCamera3D else { return resolved }
        let aspect = height > 0 ? Double(width) / Double(height) : 1
        let curVP = camera.projectionMatrix(aspect: aspect) * camera.viewMatrix
        let prevVP = previous.projectionMatrix(aspect: aspect) * previous.viewMatrix
        if prevVP == curVP && drawer.moverRanges.isEmpty { return resolved }

        let mover = moverVelocity ?? encodeMoverVelocity(
            drawer, into: cb, meshBuffer: meshBuffer,
            width: width, height: height, previousViewProjection: prevVP)
        let k = MetalRenderer.motionBlurTileSize(height: height)
        let tilesW = (width + k - 1) / k
        let tilesH = (height + k - 1) / k
        guard let fill = acquireFilterTexture(width: width, height: height, pooled: pooled),
              let tileMax = acquireFilterTexture(width: tilesW, height: tilesH, pooled: pooled),
              let neighborMax = acquireFilterTexture(width: tilesW, height: tilesH, pooled: pooled),
              let output = acquireFilterTexture(width: width, height: height, pooled: pooled)
        else { return resolved }

        let invVP = simd_inverse(curVP)
        let eye = camera.eye.simd3
        let fwd = simd_normalize(camera.target.simd3 - eye)
        // The soft-depth extent scales with the scene (the eye-to-target framing
        // proxy every scale-dependent constant here rides), so "how close is a
        // depth tie" means the same thing in a hand-sized scene and a terrain.
        let sceneScale = max(simd_distance(camera.eye.simd3, camera.target.simd3), 1)
        var params = [SIMD4<Float>](repeating: .zero, count: 12)
        params[0] = SIMD4(1 / Float(width), 1 / Float(height),
                          Float(0.5 * drawer.motionBlurShutter), Float(k))
        params[1] = SIMD4(mover != nil ? 1 : 0, moverScale.x, moverScale.y, 0)
        params[2] = invVP.columns.0; params[3] = invVP.columns.1
        params[4] = invVP.columns.2; params[5] = invVP.columns.3
        params[6] = prevVP.columns.0; params[7] = prevVP.columns.1
        params[8] = prevVP.columns.2; params[9] = prevVP.columns.3
        params[10] = SIMD4(eye, 0)
        params[11] = SIMD4(fwd, 0)
        encodeEffectFragment("ollin_mb_fill", inputs: [depth, mover ?? resolved],
                             output: fill, params: params, into: cb)
        encodeEffectFragment("ollin_mb_tilemax", inputs: [fill], output: tileMax,
                             params: [SIMD4(1 / Float(width), 1 / Float(height), Float(k), 0)],
                             into: cb)
        encodeEffectFragment("ollin_mb_neighbormax", inputs: [tileMax], output: neighborMax,
                             params: [SIMD4(1 / Float(tilesW), 1 / Float(tilesH), 0, 0)],
                             into: cb)
        let taps = resolveMotionBlurSamples()
        encodeEffectFragment("ollin_mb_reconstruct", inputs: [resolved, fill, neighborMax],
                             output: output,
                             params: [SIMD4(1 / Float(width), 1 / Float(height),
                                            Float(k), Float(taps)),
                                      SIMD4(0.01 * sceneScale,
                                            1 / Float(tilesW), 1 / Float(tilesH), 0)],
                             into: cb)
        return output
    }

    /// The mesh-normal G-buffer pass: re-render a target's meshes MSAA + depth-tested,
    /// writing each surface's view-space normal so the ambient-occlusion combine reads a
    /// true normal instead of one reconstructed from depth (which is ambiguous at a concave
    /// seam and flickers as the camera turns). MSAA (not single-sample) then a depth-aware
    /// resolve (`ollin_mesh_normal_resolve`, front-surface samples only): a silhouette pixel
    /// carries a coverage-weighted mesh normal (renormalized on read) that matches the
    /// `.min`-resolved scene depth the SSAO reconstructs position from, instead of toggling to
    /// the cleared background sub-pixel (which shimmered the edge AO) or blending a farther
    /// surface's normal across an internal silhouette (which dashed it). A dedicated mesh-only
    /// re-encode, not a second attachment on the shared geometry pass (which would force
    /// every 2D pipeline in that pass to be MRT-compatible). Runs only when the target asked
    /// for normals (`needsNormals`, set when an `.ambientOcclusion` combine reads a 3D
    /// target), so a frame without AO pays nothing and is byte-identical. Returns the filled
    /// normal texture at the target's pixel size, or nil when there's no mesh to draw.
    func encodeMeshNormals(_ drawer: Drawer, for target: RenderTarget,
                                   into cb: MTLCommandBuffer,
                                   meshBuffer: MTLBuffer?, width: Int, height: Int,
                                   pooled: Bool) -> MTLTexture? {
        guard let camera = drawer.camera3D, let meshBuffer,
              drawer.batches.contains(where: { $0.kind == .mesh3D && $0.target === target }),
              let resolve = acquireFilterTexture(width: width, height: height, pooled: pooled),
              let color = makeReadableFloatMSAA(width: width, height: height),
              let depth = makeReadableDepthMSAA(width: width, height: height),
              let pipe = try? pipeline(.meshNormal(depth: depthPixelFormat)) else { return nil }

        // MSAA into a stored target, then a *depth-aware* resolve (`ollin_mesh_normal_resolve`)
        // into the single-sample `resolve` texture the SSAO samples, not the hardware box
        // average, which at an internal silhouette (a near box's edge against a farther box)
        // would blend the front and back surface normals into a tilted one that dashes the AO.
        // The custom resolve averages only the front surface's samples, so the stored normal
        // matches the `.min`-resolved scene depth the SSAO reconstructs position from; the
        // per-sample normal + depth therefore both `.store` (read back in the resolve pass).
        // The resolved alpha is the front-surface coverage (0 = a pixel no mesh touched).
        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = color
        pass.colorAttachments[0].loadAction = .clear
        pass.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)  // alpha 0 = no normal here
        pass.colorAttachments[0].storeAction = .store
        pass.depthAttachment.texture = depth
        pass.depthAttachment.loadAction = .clear
        pass.depthAttachment.clearDepth = 1.0
        pass.depthAttachment.storeAction = .store
        guard let enc = countedEncoder(cb, pass) else { return nil }
        enc.setViewport(MTLViewport(originX: 0, originY: 0, width: Double(width), height: Double(height), znear: 0, zfar: 1))
        enc.setRenderPipelineState(pipe)
        enc.setDepthStencilState(depthTestState)
        var u3 = makeUniforms3D(drawer, camera: camera, viewport: SIMD2(Float(width), Float(height)))
        enc.setVertexBytes(&u3, length: MemoryLayout<Uniforms3D>.stride, index: 2)

        let meshStride = MemoryLayout<OllinMeshVertex>.stride
        let meshCount = drawer.meshVertices.count
        let batches = drawer.batches
        for i in batches.indices {
            let batch = batches[i]
            guard batch.kind == .mesh3D else { continue }
            // Only this target's own meshes: a mesh drawn on the main canvas (or in
            // another target) shares the frame's camera, so without this filter it
            // would rasterize into this target's normal buffer and disagree with the
            // target-filtered depth layer wherever it lands nearer, giving wrong
            // occlusion and wrong reflection rays in those regions.
            guard batch.target === target else { continue }
            // Wireframe meshes have no surface to occlude; their sparse edge fragments
            // would write stray normals, so skip them. Solid / textured / matcap all
            // carry a real per-vertex normal and feed the buffer (the normal shader
            // ignores material).
            if batch.meshWireframe { continue }
            let next = i + 1 < batches.count ? batches[i + 1] : nil
            let end = next?.meshStart ?? meshCount
            let count = end - batch.meshStart
            guard count > 0 else { continue }
            enc.setVertexBuffer(meshBuffer, offset: batch.meshStart * meshStride, index: 0)
            enc.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: count)
        }
        enc.endEncoding()

        // Depth-aware resolve: front-surface-only normal average (see above), into `resolve`.
        encodeEffectFragment("ollin_mesh_normal_resolve", inputs: [color, depth],
                             output: resolve, params: [], into: cb)
        return resolve
    }

    /// A multisample `linearFormat` color target that is *also* shader-readable (per-sample,
    /// as a `texture2d_ms`), for the depth-aware mesh-normal resolve. `.private` + `.store`,
    /// unlike the geometry path's memoryless MSAA (which is hardware-resolved within its pass).
    private func makeReadableFloatMSAA(width: Int, height: Int) -> MTLTexture? {
        let desc = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: linearFormat, width: width, height: height, mipmapped: false)
        desc.textureType = .type2DMultisample
        desc.sampleCount = sampleCount
        desc.usage = [.renderTarget, .shaderRead]
        desc.storageMode = .private
        return device.makeTexture(descriptor: desc)
    }

    /// A multisample depth target that is shader-readable per-sample (as a `depth2d_ms`), so
    /// the normal resolve can tell the front surface's samples from a farther surface's.
    private func makeReadableDepthMSAA(width: Int, height: Int) -> MTLTexture? {
        let desc = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: depthPixelFormat, width: width, height: height, mipmapped: false)
        desc.textureType = .type2DMultisample
        desc.sampleCount = sampleCount
        desc.usage = [.renderTarget, .shaderRead]
        desc.storageMode = .private
        return device.makeTexture(descriptor: desc)
    }

    /// The deferred ray-traced-reflection pre-pass (main canvas): render the reflection
    /// G-buffer (world normal + metal/rough + its own depth), trace the jittered
    /// reflection per pixel into a float layer, and, on the live path, temporally
    /// accumulate it (reproject through the previous view·projection, 3×3 neighborhood
    /// clamp, exponential moving average: the SSR temporal's scheme). Returns the
    /// texture the lit mesh fragments sample by screen position, or nil when the frame
    /// has no active reflections (the caller then leaves the inline single-ray path on,
    /// which render targets and the raymarched fields keep regardless).
    ///
    /// `supersample` selects the historyless form (headless/export): N deterministic
    /// jittered rays averaged within the one frame, no history slot touched: a single
    /// exported frame is anti-aliased with no warmup, a video export can't flicker, and
    /// the live frame-grab's off-screen re-render (which routes through `image(of:)`)
    /// can't double-step the on-screen accumulation. The live path instead traces one
    /// jittered ray and blends it into the persistent `rtReflectHistory`; a same-frame
    /// repeat (`statefulEncodeIsRepeat`) serves the already-accumulated front rather
    /// than stepping the average again, like the other stateful passes.
    func encodeReflectionPass(_ drawer: Drawer, into cb: MTLCommandBuffer,
                                      meshBuffer: MTLBuffer?,
                                      reflectAccel: MTLAccelerationStructure?,
                                      reflectGeoOffsets: MTLBuffer?,
                                      width: Int, height: Int,
                                      supersample: Bool, pooled: Bool,
                                      gi: GIResolved? = nil,
                                      taaJitter: SIMD2<Float> = .zero) -> MTLTexture? {
        guard let camera = drawer.camera3D, let meshBuffer,
              let accel = reflectAccel, let geoOffsets = reflectGeoOffsets,
              let irradiance = currentIBLIrradiance, let prefilter = currentIBLPrefilter,
              drawer.batches.contains(where: { $0.kind == .mesh3D && $0.target == nil
                                               && !$0.meshWireframe && !$0.meshGrid })
        else { return nil }

        // Same-frame repeat (live): the history already holds this frame's accumulation.
        if !supersample, statefulEncodeIsRepeat,
           let slot = rtReflectHistory, slot.valid, slot.w == width, slot.h == height {
            return slot.flipped ? slot.b : slot.a
        }

        // Lighting for the trace pass: the same IBL exposure/rotation the main pass
        // will shade with (mirroring `encode`'s block), so hit and miss stay in the
        // same units as the prefilter sample the fragment composites against.
        var lighting = drawer.makeLighting()
        guard lighting.enabled != 0 else { return nil }
        lighting.rtReflections = 1
        lighting.iblEnabled = 1
        lighting.iblIntensity = Float(drawer.environment?.intensity ?? 1) * currentIBLNormalization
        lighting.iblMaxMip = Float(currentIBLMaxMip)
        lighting.iblRotation = Float(drawer.environment?.rotation ?? 0)
        // Area lights, mirroring the main encode's LTC resolve: the hit shade's exact
        // area-light diffuse gates on `ltcEnabled`, so without this a panel-lit surface
        // would go dark in its deferred reflection while staying lit inline.
        if lighting.ltcEnabled == 0,
           drawer.lights.contains(where: { $0.kind == .rect || $0.kind == .disk || $0.kind == .tube }) {
            lighting.ltcEnabled = ensureLTCTables() ? 1 : 0
        }
        // Light shaping, the same mirroring: without it a profiled or cookied spot
        // would lose its pattern only in deferred reflections.
        if lighting.iesEnabled == 0, !drawer.usedIESProfiles.isEmpty {
            lighting.iesEnabled = ensureIESArray(drawer.usedIESProfiles) ? 1 : 0
        }
        if lighting.cookieEnabled == 0, !drawer.usedLightCookies.isEmpty {
            lighting.cookieEnabled = ensureCookieArray(drawer.usedLightCookies) ? 1 : 0
        }
        // The probe field, the same mirroring: without it a bounce-lit surface would go
        // direct-only in its deferred reflection while staying bounce-lit inline (and in
        // the direct view). Nil keeps `giOrigin.w` 0 and the hit shade's GI branch
        // untaken, byte-identical.
        packGI(gi, into: &lighting, intensity: drawer.giIntensity)

        // 1. The G-buffer: re-render the main canvas's solid meshes (the same batch walk
        // as the mesh-normal pass; wireframes and the grid chrome carry no reflective
        // surface; the grid is also excluded from the accel, so the two stay in step).
        if rtReflectGBuf == nil || rtReflectGBuf!.w != width || rtReflectGBuf!.h != height {
            guard let normal = makeFilterTexture(width: width, height: height),
                  let material = makeFilterTexture(width: width, height: height),
                  let depth = makeDepthResolve(width: width, height: height) else { return nil }
            rtReflectGBuf = (normal, material, depth, width, height)
        }
        guard let gbuf = rtReflectGBuf,
              let gbufPipe = try? pipeline(.rtReflectGBuffer(depth: depthPixelFormat)),
              let traced = acquireFilterTexture(width: width, height: height, pooled: pooled)
        else { return nil }

        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = gbuf.normal
        pass.colorAttachments[0].loadAction = .clear
        pass.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)
        pass.colorAttachments[0].storeAction = .store
        pass.colorAttachments[1].texture = gbuf.material
        pass.colorAttachments[1].loadAction = .clear
        pass.colorAttachments[1].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)
        pass.colorAttachments[1].storeAction = .store
        pass.depthAttachment.texture = gbuf.depth
        pass.depthAttachment.loadAction = .clear
        pass.depthAttachment.clearDepth = 1.0
        pass.depthAttachment.storeAction = .store
        guard let enc = countedEncoder(cb, pass) else { return nil }
        enc.setViewport(MTLViewport(originX: 0, originY: 0, width: Double(width),
                                    height: Double(height), znear: 0, zfar: 1))
        enc.setRenderPipelineState(gbufPipe)
        enc.setDepthStencilState(depthTestState)
        // Under temporal AA the G-buffer carries the frame's jitter, so the traced
        // reflection lands exactly where the jittered geometry pass composites it
        // (and the reflection temporal's own reprojection unjitters like the frame's).
        var u3 = makeUniforms3D(drawer, camera: camera,
                                viewport: SIMD2(Float(width), Float(height)),
                                jitter: taaJitter)
        enc.setVertexBytes(&u3, length: MemoryLayout<Uniforms3D>.stride, index: 2)
        let meshStride = MemoryLayout<OllinMeshVertex>.stride
        let meshCount = drawer.meshVertices.count
        let batches = drawer.batches
        for i in batches.indices {
            let batch = batches[i]
            guard batch.kind == .mesh3D, batch.target == nil,
                  !batch.meshWireframe, !batch.meshGrid else { continue }
            let next = i + 1 < batches.count ? batches[i + 1] : nil
            let end = next?.meshStart ?? meshCount
            let count = end - batch.meshStart
            guard count > 0 else { continue }
            enc.setVertexBuffer(meshBuffer, offset: batch.meshStart * meshStride, index: 0)
            enc.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: count)
        }
        enc.endEncoding()

        // 2. The trace: one fullscreen pass, N jittered rays per pixel (1 on the live path).
        let samples = supersample ? resolveRTReflectionSamples() : 1
        let seed = supersample ? 0 : Float(frameComputeUniforms.frameCount % 4096)
        guard let traceState = try? pipeline(.effect("ollin_rt_reflect_trace")) else { return nil }
        let tracePass = MTLRenderPassDescriptor()
        tracePass.colorAttachments[0].texture = traced
        tracePass.colorAttachments[0].loadAction = .dontCare
        tracePass.colorAttachments[0].storeAction = .store
        guard let trace = countedEncoder(cb, tracePass) else { return nil }
        trace.setRenderPipelineState(traceState)
        trace.setFragmentTexture(gbuf.normal, index: 0)
        trace.setFragmentTexture(gbuf.material, index: 1)
        trace.setFragmentTexture(gbuf.depth, index: 2)
        trace.setFragmentTexture(irradiance, index: 4)
        trace.setFragmentTexture(prefilter, index: 5)
        // The LTC amp table feeds the hit shade's exact area-light diffuse; the
        // G-buffer normal is the never-sampled stand-in when the tables aren't
        // loaded (`ltcEnabled` gates every read, matching the mesh fragments).
        trace.setFragmentTexture(ltcAmpTexture ?? gbuf.normal, index: 9)
        // The light-shaping arrays (tex 10/11), so the hit shade keeps a shaped
        // light's pattern; the array stand-in otherwise (the gates guard the reads).
        trace.setFragmentTexture(iesArrayTexture ?? shapingStandIn(), index: 10)
        trace.setFragmentTexture(cookieArrayTexture ?? shapingStandIn(), index: 11)
        // The GI probe atlases (tex 13/14/15), so a hit's diffuse carries the bounce
        // field; never-sampled stand-ins while the field is inactive.
        let giStand = gradientStripTexture(for: drawer.gradientRows)
        trace.setFragmentTexture(gi?.irradiance ?? giStand, index: 13)
        trace.setFragmentTexture(gi?.depth ?? giStand, index: 14)
        trace.setFragmentTexture(gi?.offsets ?? giStand, index: 15)
        trace.setFragmentSamplerState(imageSampler, index: 0)
        var traceParams = SIMD4<Float>(1 / Float(width), 1 / Float(height), Float(samples), seed)
        trace.setFragmentBytes(&traceParams, length: MemoryLayout<SIMD4<Float>>.stride, index: 0)
        trace.setFragmentBytes(&lighting, length: MemoryLayout<OllinLighting>.stride, index: 1)
        trace.setFragmentBytes(&u3, length: MemoryLayout<Uniforms3D>.stride, index: 2)
        useTracedScene(trace, accel)
        trace.setFragmentAccelerationStructure(accel, bufferIndex: 3)
        trace.setFragmentBuffer(meshBuffer, offset: 0, index: 6)
        trace.setFragmentBuffer(geoOffsets, offset: 0, index: 7)
        trace.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        trace.endEncoding()

        // Headless/export: the in-frame average IS the anti-aliased reflection.
        if supersample { return traced }

        // 3. The temporal resolve (live): reproject + clamp + EMA into the history's back.
        let slot: SSRHistorySlot
        if let existing = rtReflectHistory, existing.w == width, existing.h == height {
            slot = existing
        } else {
            guard let a = makeFloatResolve(width: width, height: height),
                  let b = makeFloatResolve(width: width, height: height) else { return traced }
            let clear = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)
            clearFloatTexture(a, color: clear, into: cb)
            clearFloatTexture(b, color: clear, into: cb)
            slot = SSRHistorySlot(a: a, b: b, w: width, h: height)
            rtReflectHistory = slot
        }
        let front = slot.flipped ? slot.b : slot.a
        let back = slot.flipped ? slot.a : slot.b
        let aspect = height > 0 ? Double(width) / Double(height) : 1
        let viewProjection = camera.projectionMatrix(aspect: aspect) * camera.viewMatrix
        // Unjittered, never `u3.inverseViewProjection`: under temporal AA the
        // G-buffer's u3 carries the frame's jitter, and a jittered reconstruction
        // feeds the reprojection a per-frame sub-pixel offset that random-walks
        // the accumulated reflection (the TAA resolve's remove-the-jitter rule).
        let invVP = simd_inverse(viewProjection)
        let alpha = slot.valid ? Float(resolveRTReflectionAlpha()) : 0
        var params = [SIMD4<Float>](repeating: .zero, count: 12)
        params[0] = SIMD4(1 / Float(width), 1 / Float(height), alpha, slot.valid ? 1 : 0)
        params[4] = invVP.columns.0; params[5] = invVP.columns.1
        params[6] = invVP.columns.2; params[7] = invVP.columns.3
        let pv = slot.previousViewProjection
        params[8] = pv.columns.0; params[9] = pv.columns.1
        params[10] = pv.columns.2; params[11] = pv.columns.3
        encodeEffectFragment("ollin_rt_reflect_temporal", inputs: [traced, gbuf.depth, front],
                             output: back, params: params, into: cb)
        slot.previousViewProjection = viewProjection
        slot.valid = true
        slot.flipped.toggle()   // the just-written back is next frame's (and any repeat's) front
        return back
    }

    /// EMA history weight for the deferred reflection's temporal accumulation, resolved
    /// through the automatic quality (no per-feature knob yet): the SSR temporal's tiers.
    private func resolveRTReflectionAlpha() -> Double {
        switch effectiveQuality(.default) {
        case .detail:      return 0.92
        case .default:     return 0.88
        case .performance: return 0.80
        }
    }

    /// Rays per pixel for the historyless (headless/export) reflection supersample: the
    /// within-one-frame equivalent of the temporal accumulation, deterministic (fixed
    /// jitter sequence, seed 0) so exports and snapshots reproduce bit-exactly.
    private func resolveRTReflectionSamples() -> Int {
        switch effectiveQuality(.default) {
        case .performance: return 4
        case .default:     return 8
        case .detail:      return 16
        }
    }

    // MARK: - Global illumination (the probe-field update)

    /// The probe budget: the per-axis counts adapt to the fitted volume's aspect (a
    /// flat scene spends its probes horizontally instead of stacking unused vertical
    /// rows) but their product never exceeds this, so the atlases allocate once at
    /// this capacity and a refit never reallocates. 512 is the shipped 8x8x8's total,
    /// which a cubic volume still resolves to exactly.
    private static let giProbeBudget = 512
    /// The per-axis probe cap: 16x16x2 spends the whole budget on a pancake, and a
    /// still-more-extreme aspect gains nothing from thinner slabs of probes.
    private static let giAxisCap: Int32 = 16
    /// Probe tiles per atlas row. The blend/sample shaders re-derive it from the atlas
    /// width (width / tile), so the layout constant lives only here.
    private static let giTilesPerRow = 32
    /// Fixed statistics rays per probe, the surfel texture's FIRST columns: never
    /// rotated, distance-only, read by the relocation pass alone so its threshold
    /// decisions can't flicker with the radiance fan's per-update rotation (the
    /// production papers' fixed rays). Mirrors `OLLIN_GI_FIXED_RAYS` in
    /// ShaderGI.metal; keep the two in step.
    private static let giFixedRays = 32

    /// Per-axis probe counts for a fitted volume: near-isotropic spacing (counts
    /// proportional to extent) under the fixed total budget, each axis at least 2 (a
    /// trilinear cage needs both walls) and at most `giAxisCap`. A binary search for
    /// the smallest isotropic spacing whose (clamped) counts fit the budget; counts
    /// are non-increasing in the spacing, so the search is sound, and the whole
    /// derivation is a pure function of the extent (exports reproduce; internal so
    /// the unit tests can pin it exactly).
    static func giAxisCounts(for ext: SIMD3<Float>) -> SIMD3<Int32> {
        func counts(at h: Float) -> SIMD3<Int32> {
            let raw = SIMD3<Int32>(Int32((ext.x / h).rounded()) + 1,
                                   Int32((ext.y / h).rounded()) + 1,
                                   Int32((ext.z / h).rounded()) + 1)
            return raw.clamped(lowerBound: SIMD3(repeating: 2),
                               upperBound: SIMD3(repeating: giAxisCap))
        }
        func product(_ c: SIMD3<Int32>) -> Int { Int(c.x) * Int(c.y) * Int(c.z) }
        // Bracket: at `hi` every axis floors to 2 (8 probes); walk `lo` down only
        // while it still overflows the budget, then bisect to the smallest fitting h.
        var hi = max(ext.x, max(ext.y, ext.z))
        var lo = hi / 32
        if product(counts(at: lo)) <= Self.giProbeBudget { return counts(at: lo) }
        for _ in 0..<40 {
            let mid = (lo + hi) * 0.5
            if product(counts(at: mid)) <= Self.giProbeBudget { hi = mid } else { lo = mid }
        }
        return counts(at: hi)
    }

    /// The camera-cascade axis cap: 8 per axis keeps a full cube inside one 512-probe
    /// atlas slot, and a slab-clamped axis spends fewer.
    private static let giCascadeAxisCap: Int32 = 8
    /// Test seam: the counterfactual probes force the single-volume path on a scene
    /// past the coarseness threshold (false = never derive camera cascades), because
    /// nothing user-facing can hold the scene and camera fixed while removing only
    /// the cascades. Always true outside the tests.
    static var giCascadesEnabledForTesting = true
    /// The coarseness threshold: cascades exist only while the fitted volume's spacing
    /// exceeds this fraction of the eye-to-target distance. Calibrated so a room with
    /// the camera inside it stays single-volume (the mirror probe room fits ~1.5-unit
    /// spacing against a 5-unit working distance, 0.6x this line) while any
    /// terrain-scale scene crosses it by an order of magnitude.
    private static let giCascadeActivation: Float = 0.5
    /// How fine the camera wants its nearest probes, as a fraction of the eye-to-target
    /// distance: the ladder halves the scene spacing until it reaches this, so at the
    /// activation boundary exactly one cascade appears and a vast scene ladders to the
    /// full three.
    private static let giCascadeTargetFraction: Float = 0.25

    /// Derive the camera-anchored cascade ladder for a fitted scene volume: empty while
    /// the fitted spacing serves the camera's working scale (every room-scale scene,
    /// the shipped single-volume path), else cascades halving from the scene spacing
    /// toward `workingScale * giCascadeTargetFraction`, at most
    /// `OLLIN_GI_MAX_CAMERA_CASCADES`, each camera-anchored on the axes its span
    /// cannot cover and pinned (centered on the scene's slab) on the axes it can.
    /// Ordered coarsest first (the cascade table's order; the sampler walks it from
    /// the finest down). A pure function of (volume, eye, working scale), so headless
    /// re-derivation reproduces bit-exactly and the unit tests pin it; the quality
    /// tier deliberately never touches it (the grid-never-rides-the-tier rule).
    static func giCascadeLadder(volumeOrigin: SIMD3<Float>, volumeSpan: SIMD3<Float>,
                                spacing: SIMD3<Float>, eye: SIMD3<Float>,
                                workingScale: Float) -> [GICascadeState] {
        let s0 = max(spacing.x, max(spacing.y, spacing.z))
        guard giCascadesEnabledForTesting else { return [] }
        guard workingScale > 1e-5, workingScale.isFinite, s0.isFinite else { return [] }
        guard s0 > workingScale * giCascadeActivation else { return [] }
        let target = workingScale * giCascadeTargetFraction
        let k = min(max(Int(ceil(log2(Double(s0 / target)))), 1),
                    Int(OLLIN_GI_MAX_CAMERA_CASCADES))
        var ladder: [GICascadeState] = []
        for i in 1...k {
            let s = s0 / Float(1 << i)
            var counts = SIMD3<Int32>.zero
            var origin = SIMD3<Float>.zero
            var scrolls = SIMD3<Int32>.zero
            for a in 0..<3 {
                let cover = volumeSpan[a]
                let n = min(max(Int32((cover / s).rounded(.up)) + 1, 2), Self.giCascadeAxisCap)
                let span = Float(n - 1) * s
                counts[a] = n
                if span >= cover {
                    // Pinned: the window already covers the scene's slab on this axis,
                    // so it centers there and never scrolls (a terrain's vertical).
                    origin[a] = volumeOrigin[a] + cover * 0.5 - span * 0.5
                } else {
                    origin[a] = eye[a] - span * 0.5
                    scrolls[a] = 1
                }
            }
            ladder.append(GICascadeState(origin: origin, spacing: s,
                                         counts: counts, scrolls: scrolls))
        }
        return ladder
    }

    /// Whole-plane scroll for a camera cascade: how many probe planes the window moves
    /// this frame so its center chases the anchor, per scrolling axis. Truncation
    /// toward zero is the reference's dead zone (no scroll until the anchor is a full
    /// plane away), so a camera hovering at a boundary never flickers a plane in and
    /// out. Clamped to one full wrap (a teleport clears the whole cascade, not more).
    static func giScrollDelta(origin: SIMD3<Float>, spacing: Float, counts: SIMD3<Int32>,
                              scrolls: SIMD3<Int32>, anchor: SIMD3<Float>) -> SIMD3<Int32> {
        var delta = SIMD3<Int32>.zero
        for a in 0..<3 where scrolls[a] == 1 {
            let center = origin[a] + Float(counts[a] - 1) * spacing * 0.5
            let raw = (anchor[a] - center) / spacing
            guard raw.isFinite else { continue }
            let bound = Float(counts[a])
            delta[a] = Int32(max(min(raw, bound), -bound))
        }
        return delta
    }

    /// The scroll phase after moving `delta` planes: the wrap that keeps a stationary
    /// world lattice point on the same atlas texel (phys = (grid + phase) mod counts).
    static func giWrappedPhase(_ phase: SIMD3<Int32>, delta: SIMD3<Int32>,
                               counts: SIMD3<Int32>) -> SIMD3<Int32> {
        var p = SIMD3<Int32>.zero
        for a in 0..<3 {
            let n = max(counts[a], 1)
            p[a] = ((phase[a] + delta[a]) % n + n) % n
        }
        return p
    }

    /// The grid-coordinate slab (in the NEW window) whose planes scrolled in: delta > 0
    /// enters at the high edge, delta < 0 at the low one, |delta| >= counts is the
    /// whole cascade. What the invalidation pass tests each probe against.
    static func giEnteredRange(delta: Int32, count: Int32) -> (lo: Int32, length: Int32) {
        let d = max(min(delta, count), -count)
        if d > 0 { return (count - d, d) }
        if d < 0 { return (0, -d) }
        return (0, 0)
    }

    /// The frame's mesh-geometry world bounds, folded over the same caster batches the
    /// acceleration structure is built from (target-drawn meshes included, matching
    /// `buildShadowAccel`'s walk), so the probe volume covers exactly what the probe
    /// rays can hit; that parity is also what gives a scene drawn entirely inside a
    /// render target (the depth-of-field shape) a field at all. Nil when the frame has
    /// no eligible mesh.
    private func giSceneBounds(_ drawer: Drawer) -> (lo: SIMD3<Float>, hi: SIMD3<Float>)? {
        var lo = SIMD3<Float>(repeating: .greatestFiniteMagnitude)
        var hi = SIMD3<Float>(repeating: -.greatestFiniteMagnitude)
        var found = false
        let batches = drawer.batches
        let count = drawer.meshVertices.count
        drawer.meshVertices.withUnsafeBufferPointer { verts in
            for i in batches.indices {
                let batch = batches[i]
                guard batch.kind == .mesh3D,
                      !batch.meshWireframe, !batch.meshGrid else { continue }
                let next = i + 1 < batches.count ? batches[i + 1] : nil
                let end = next?.meshStart ?? count
                guard end > batch.meshStart else { continue }
                for v in batch.meshStart..<end {
                    let p = verts[v].position
                    lo = simd_min(lo, SIMD3<Float>(p.x, p.y, p.z))
                    hi = simd_max(hi, SIMD3<Float>(p.x, p.y, p.z))
                }
                found = true
            }
        }
        return found ? (lo, hi) : nil
    }

    /// The self-shadow bias magnitude for a probe spacing (the published constants:
    /// 0.75 of the minimum axial spacing times the 0.3 tunable's default).
    private func giBiasScale(_ spacing: SIMD3<Float>) -> Float {
        0.75 * min(spacing.x, min(spacing.y, spacing.z)) * 0.3
    }

    /// Rays per probe per update, resolved through the sketch's GI quality tier
    /// (`globalIlluminationQuality`; `.default` follows the automatic path) and scaled
    /// to the GPU like the shadow rays (software ray tracing pays several times more
    /// per ray).
    private func resolveGIRays(_ quality: RenderQuality) -> Int {
        switch effectiveQuality(quality) {
        case .performance: return hasHardwareRayTracing ? 64 : 32
        case .default:     return hasHardwareRayTracing ? 96 : 64
        case .detail:      return hasHardwareRayTracing ? 192 : 96
        }
    }

    /// Whole trace+blend iterations for the historyless (headless/export) path: each
    /// deepens the bounce recursion by one and averages the noise down (the blend runs
    /// a progressive mean), so a single frame converges deterministically with no
    /// history, and a video export cannot flicker. Resolved through the same GI
    /// quality tier as the rays.
    private func resolveGIIterations(_ quality: RenderQuality) -> Int {
        switch effectiveQuality(quality) {
        case .performance: return 8
        case .default:     return 12
        case .detail:      return 16
        }
    }

    /// Pack a resolved GI field into a lighting struct: the one packing every consumer
    /// shares (the main encode, `resolveFieldLighting`, and the probe trace itself), so
    /// the carriers and the recursion describe the same grid. `intensity` is the
    /// sketch's artistic dial; the probe trace packs 1 so recursion can't compound it.
    func packGI(_ gi: GIResolved?, into lighting: inout OllinLighting, intensity: Double) {
        guard let gi else { return }
        lighting.giOrigin = SIMD4<Float>(gi.origin, 1)
        lighting.giSpacing = SIMD4<Float>(gi.spacing, Float(intensity))
        lighting.giCounts = SIMD4<Float>(Float(gi.counts.x), Float(gi.counts.y),
                                         Float(gi.counts.z), gi.biasScale)
        lighting.giCascadeInfo = SIMD4<Float>(Float(1 + gi.cascades.count), 0, 0, 0)
        guard !gi.cascades.isEmpty else { return }
        withUnsafeMutablePointer(to: &lighting.giCascades) { tuplePtr in
            tuplePtr.withMemoryRebound(to: OllinGICascade.self,
                                       capacity: Int(OLLIN_GI_MAX_CAMERA_CASCADES)) { slots in
                for (i, cas) in gi.cascades.prefix(Int(OLLIN_GI_MAX_CAMERA_CASCADES)).enumerated() {
                    let iso = SIMD3<Float>(repeating: cas.spacing)
                    slots[i].originBias = SIMD4<Float>(cas.origin, giBiasScale(iso))
                    slots[i].spacingBase = SIMD4<Float>(cas.spacing, Float((i + 1) * 512),
                                                        1.5 * cas.spacing, 0)
                    let packedPhase = cas.phase.x + 32 * cas.phase.y + 1024 * cas.phase.z
                    slots[i].countsPhase = SIMD4<Float>(Float(cas.counts.x), Float(cas.counts.y),
                                                        Float(cas.counts.z), Float(packedPhase))
                }
            }
        }
    }

    /// One blend pass: fold the traced surfels into an atlas's back texture against its
    /// front (the previous update), whole-atlas (gutter texels recompute their wrapped
    /// interior source in-shader, so no separate border pass).
    private func encodeGIBlend(_ pipe: MTLRenderPipelineState, surfels: MTLTexture,
                               previous: MTLTexture, output: MTLTexture,
                               params: [SIMD4<Float>], into cb: MTLCommandBuffer,
                               offsets: MTLTexture? = nil) {
        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = output
        pass.colorAttachments[0].loadAction = .dontCare
        pass.colorAttachments[0].storeAction = .store
        guard let enc = countedEncoder(cb, pass) else { return }
        enc.setRenderPipelineState(pipe)
        params.withUnsafeBytes { raw in
            enc.setFragmentBytes(raw.baseAddress!, length: raw.count, index: 0)
        }
        enc.setFragmentTexture(surfels, index: 0)
        enc.setFragmentTexture(previous, index: 1)
        // The offsets texture's w channel is the per-probe validity the atlas blends
        // read (the scroll pass's invalidation flag; the same texture the trace took
        // its positions from).
        if let offsets { enc.setFragmentTexture(offsets, index: 2) }
        enc.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        enc.endEncoding()
    }

    /// Update the global-illumination probe field and hand back the atlases the lit
    /// carriers sample. Live: one trace+blend update per frame, hysteresis 0.97 (plus
    /// the per-texel convergence heuristics in the blend shader), into the persistent
    /// ping-ponged state; a same-frame repeat (the frame-grab re-render) serves the
    /// already-advanced front, like the other stateful passes. Headless/export
    /// (`supersample`): the volume refits from this frame's own bounds and K whole
    /// iterations run from scratch with a progressive-mean hysteresis and seed = the
    /// iteration index, so the result is a pure function of the frame (byte-stable
    /// snapshots, flicker-free video) and multi-bounce converges within it.
    ///
    /// The probe *volume* otherwise holds across live frames (probes must not move for
    /// the hysteresis to mean anything): it refits only when the scene's raw bounds
    /// escape it or shrink to a fraction of it, and a refit restarts the field.
    func encodeGIPass(_ drawer: Drawer, into cb: MTLCommandBuffer,
                      meshBuffer: MTLBuffer?,
                      accel: MTLAccelerationStructure?, geoOffsets: MTLBuffer?,
                      supersample: Bool, pooled: Bool) -> GIResolved? {
        guard drawer.globalIlluminationEnabled, rayTracedShadows,
              let accel, let geoOffsets, let meshBuffer else { return nil }
        var lighting = drawer.makeLighting()
        guard lighting.enabled != 0 else { return nil }

        // Same-frame repeat (live): the field already advanced this frame.
        if !supersample, statefulEncodeIsRepeat, let s = giState, s.valid,
           let sampled = s.lastTraceOffsets {
            return GIResolved(irradiance: s.irrFront, depth: s.depFront, offsets: sampled,
                              origin: s.origin, spacing: s.spacing, counts: s.counts,
                              biasScale: giBiasScale(s.spacing), cascades: s.cascades)
        }

        guard let bounds = giSceneBounds(drawer) else { return nil }
        // The vast-scene cascades anchor on the camera's eye and derive their fineness
        // from the eye-to-target distance (the sceneScale proxy); no camera, no ladder.
        var anchor = SIMD3<Float>.zero
        var workingScale: Float = 0
        if let camera = drawer.camera3D {
            anchor = SIMD3<Float>(camera.eye.simd3)
            workingScale = Float(simd_distance(camera.eye.simd3, camera.target.simd3))
        }
        // Headless: a pure function of this frame, so never inherit a live volume
        // or its half-converged field.
        if supersample { giState?.valid = false }
        var needFit = !(giState?.valid ?? false)
        if let held = giState, !needFit {
            let gridMax = held.origin + held.spacing * SIMD3<Float>(held.counts &- 1)
            if bounds.lo.x < held.origin.x || bounds.lo.y < held.origin.y
                || bounds.lo.z < held.origin.z || bounds.hi.x > gridMax.x
                || bounds.hi.y > gridMax.y || bounds.hi.z > gridMax.z {
                needFit = true
            } else {
                let heldExt = gridMax - held.origin
                let rawExt = simd_max(bounds.hi - bounds.lo, SIMD3<Float>(repeating: 1e-6))
                let heldVol = heldExt.x * heldExt.y * heldExt.z
                let targetVol = rawExt.x * rawExt.y * rawExt.z * (1.3 * 1.3 * 1.3)
                if heldVol > targetVol * 6 { needFit = true }
            }
            // The ladder's own hold: the cascade set stands until the camera's working
            // scale drifts past half/double the scale it derived from, and even then
            // only a *structural* change (spacing, counts, or scroll axes) restarts
            // the field; origins scroll and phases wrap without ever refitting.
            if !needFit, held.ladderScale > 0, workingScale > 0,
               abs(log2(workingScale / held.ladderScale)) > 0.5 {
                let fresh = Self.giCascadeLadder(volumeOrigin: held.origin,
                                                 volumeSpan: gridMax - held.origin,
                                                 spacing: held.spacing, eye: anchor,
                                                 workingScale: workingScale)
                if fresh.count == held.cascades.count,
                   zip(fresh, held.cascades).allSatisfy({ $0.matches($1) }) {
                    held.ladderScale = workingScale
                } else {
                    needFit = true
                }
            }
        }
        if needFit {
            var ext = bounds.hi - bounds.lo
            // Floor degenerate axes (a flat ground plane) so spacing never collapses.
            let maxExt = max(max(ext.x, ext.y), max(ext.z, 0.001))
            ext = simd_max(ext, SIMD3<Float>(repeating: maxExt * 0.05))
            let center = (bounds.hi + bounds.lo) * 0.5
            ext *= 1.3   // 15% pad each side: boundary surfaces sit inside the outer cage
            // Per-axis counts from the padded volume's aspect: a flat scene spends its
            // probes horizontally instead of stacking unused vertical rows. Derived at
            // fit time and held with the volume, so probes stay put between refits.
            let counts = Self.giAxisCounts(for: ext)
            let origin = center - ext * 0.5
            let spacing = ext / SIMD3<Float>(counts &- 1)
            let ladder = Self.giCascadeLadder(volumeOrigin: origin, volumeSpan: ext,
                                              spacing: spacing, eye: anchor,
                                              workingScale: workingScale)
            let capacity = 1 + ladder.count
            if giState == nil || giState!.slotCapacity != capacity {
                // (Re)allocate at this ladder's slot capacity, the atlases stacking one
                // 512-probe slot per cascade. A capacity change only ever rides a refit
                // (the coarseness threshold is crossed by scene growth or a big camera
                // rescale), and the single-volume allocation is exactly the shipped
                // one, so a room-scale scene keeps its sampling UVs byte-identical.
                let perRow = Self.giTilesPerRow
                let rows = (Self.giProbeBudget + perRow - 1) / perRow
                guard let iA = makeFloatResolve(width: perRow * 10, height: rows * 10 * capacity),
                      let iB = makeFloatResolve(width: perRow * 10, height: rows * 10 * capacity),
                      let dA = makeFloatResolve(width: perRow * 18, height: rows * 18 * capacity),
                      let dB = makeFloatResolve(width: perRow * 18, height: rows * 18 * capacity),
                      let oA = makeFloatResolve(width: Self.giProbeBudget * capacity, height: 1),
                      let oB = makeFloatResolve(width: Self.giProbeBudget * capacity, height: 1)
                else { return nil }
                giState = GIProbeState(irrA: iA, irrB: iB, depA: dA, depB: dB,
                                       offA: oA, offB: oB, slotCapacity: capacity)
            }
            guard let state = giState else { return nil }
            state.counts = counts
            state.origin = origin
            state.spacing = spacing
            state.cascades = ladder
            state.ladderScale = workingScale
            state.valid = false
            state.lastTraceOffsets = nil
            // Relocation offsets (and the per-probe validity riding their w) belong
            // to a grid; a new grid starts from zero.
            let clear = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)
            clearFloatTexture(state.offA, color: clear, into: cb)
            clearFloatTexture(state.offB, color: clear, into: cb)
        }
        guard let state = giState else { return nil }

        // Live scrolling (the infinite-scrolling-volume model): a camera cascade
        // chases the eye in whole probe planes; the pass invalidates exactly the
        // scrolled-in planes on the offsets ping-pong (validity w = 0, offset zeroed)
        // and every stationary probe keeps its texel, so the field's interior never
        // re-converges. Headless never scrolls: it refit above, a pure function of
        // the frame.
        if !supersample, !needFit, !state.cascades.isEmpty,
           let scrollPipe = try? pipeline(.effect("ollin_gi_scroll")) {
            var scrollParams = [SIMD4<Float>](repeating: .zero,
                                              count: 1 + 3 * Int(OLLIN_GI_MAX_CAMERA_CASCADES))
            scrollParams[0].x = Float(1 + state.cascades.count)
            var scrolled = false
            for i in state.cascades.indices {
                var cas = state.cascades[i]
                let delta = Self.giScrollDelta(origin: cas.origin, spacing: cas.spacing,
                                               counts: cas.counts, scrolls: cas.scrolls,
                                               anchor: anchor)
                var lo = SIMD4<Float>.zero
                var len = SIMD4<Float>.zero
                if delta != .zero {
                    scrolled = true
                    cas.origin += SIMD3<Float>(Float(delta.x), Float(delta.y),
                                               Float(delta.z)) * cas.spacing
                    cas.phase = Self.giWrappedPhase(cas.phase, delta: delta, counts: cas.counts)
                    for a in 0..<3 {
                        let r = Self.giEnteredRange(delta: delta[a], count: cas.counts[a])
                        lo[a] = Float(r.lo)
                        len[a] = Float(r.length)
                    }
                }
                let packedPhase = cas.phase.x + 32 * cas.phase.y + 1024 * cas.phase.z
                scrollParams[1 + 3 * i] = SIMD4<Float>(Float(cas.counts.x), Float(cas.counts.y),
                                                       Float(cas.counts.z), Float(packedPhase))
                scrollParams[2 + 3 * i] = lo
                scrollParams[3 + 3 * i] = len
                state.cascades[i] = cas
            }
            if scrolled {
                encodeGIBlend(scrollPipe, surfels: state.offFront, previous: state.offFront,
                              output: state.offBack, params: scrollParams, into: cb)
                state.offFlipped.toggle()
            }
        }
        let counts = state.counts
        let probeCount = Int(counts.x) * Int(counts.y) * Int(counts.z)
        // Physical probe rows: the scene volume's own count while single (the shipped
        // layout), whole 512-probe slots while cascaded.
        let probeRows = state.cascades.isEmpty
            ? probeCount : Self.giProbeBudget * (1 + state.cascades.count)
        // The per-cascade parameter slots the blend/relocate passes share, appended
        // after their two global slots: (local count, moment cap, spacing, 0). Empty
        // while single, so those passes' params are byte-for-byte the shipped ones.
        let cascadeSlots: [SIMD4<Float>] = state.cascades.map { cas in
            SIMD4<Float>(Float(Int(cas.counts.x) * Int(cas.counts.y) * Int(cas.counts.z)),
                         1.5 * cas.spacing, cas.spacing, 0)
        }
        let cascadeCountParam: Float = state.cascades.isEmpty
            ? 0 : Float(1 + state.cascades.count)

        // The trace shades hits with the same exposure/table state the main pass will
        // use (the reflection pass's mirroring rule), plus its own field for the
        // bounce recursion, at intensity 1.
        if drawer.environment != nil, currentIBL != nil {
            lighting.iblEnabled = 1
            lighting.iblIntensity = Float(drawer.environment?.intensity ?? 1) * currentIBLNormalization
            lighting.iblMaxMip = Float(currentIBLMaxMip)
            lighting.iblRotation = Float(drawer.environment?.rotation ?? 0)
        }
        if lighting.ltcEnabled == 0,
           drawer.lights.contains(where: { $0.kind == .rect || $0.kind == .disk || $0.kind == .tube }) {
            lighting.ltcEnabled = ensureLTCTables() ? 1 : 0
        }
        if lighting.iesEnabled == 0, !drawer.usedIESProfiles.isEmpty {
            lighting.iesEnabled = ensureIESArray(drawer.usedIESProfiles) ? 1 : 0
        }
        if lighting.cookieEnabled == 0, !drawer.usedLightCookies.isEmpty {
            lighting.cookieEnabled = ensureCookieArray(drawer.usedLightCookies) ? 1 : 0
        }
        packGI(GIResolved(irradiance: state.irrFront, depth: state.depFront,
                          offsets: state.offFront,
                          origin: state.origin, spacing: state.spacing, counts: counts,
                          biasScale: giBiasScale(state.spacing), cascades: state.cascades),
               into: &lighting, intensity: 1)

        let farCap = 2 * simd_length(state.spacing * SIMD3<Float>(counts &- 1))
        // The visibility moments cap at cage scale (1.5x the largest axial spacing, the
        // reference's rule): the Chebyshev test only ever asks about a probe's own cage,
        // and far geometry in the statistics collapses near-surface variance.
        let depthCap = 1.5 * max(state.spacing.x, max(state.spacing.y, state.spacing.z))
        let rays = resolveGIRays(drawer.giQualitySetting)
        let iterations = supersample ? resolveGIIterations(drawer.giQualitySetting) : 1
        // The cascaded trace is a separate fragment so the single-volume one keeps its
        // exact shipped codegen (fast-math re-contracts unchanged expressions when a
        // function's control flow grows; the ulp is a byte off every dithered frame).
        let traceName = state.cascades.isEmpty ? "ollin_gi_trace" : "ollin_gi_trace_cascaded"
        guard let tracePipe = try? pipeline(.effect(traceName)),
              let blendIrrPipe = try? pipeline(.effect("ollin_gi_blend_irradiance")),
              let blendDepPipe = try? pipeline(.effect("ollin_gi_blend_depth")),
              let relocatePipe = try? pipeline(.effect("ollin_gi_relocate")),
              let surfels = acquireFilterTexture(width: rays + Self.giFixedRays,
                                                 height: probeRows, pooled: pooled)
        else { return nil }
        if iblPlaceholderCube == nil { iblPlaceholderCube = makeCubeTexture(face: 1, mipped: false) }
        let stand = gradientStripTexture(for: drawer.gradientRows)

        for i in 0..<iterations {
            let seed: Float = supersample ? Float(i) : Float(frameComputeUniforms.frameCount % 4096)
            let prevValid: Float = (state.valid || i > 0) ? 1 : 0
            let hysteresis: Float = supersample ? Float(i) / Float(i + 1) : 0.97

            let tracePass = MTLRenderPassDescriptor()
            tracePass.colorAttachments[0].texture = surfels
            tracePass.colorAttachments[0].loadAction = .dontCare
            tracePass.colorAttachments[0].storeAction = .store
            guard let trace = countedEncoder(cb, tracePass) else { return nil }
            trace.setRenderPipelineState(tracePipe)
            let traceParams = [SIMD4<Float>(Float(rays), seed, farCap, Float(probeCount)),
                               SIMD4<Float>(prevValid, farCap, 0, 0)]
            traceParams.withUnsafeBytes { raw in
                trace.setFragmentBytes(raw.baseAddress!, length: raw.count, index: 0)
            }
            trace.setFragmentBytes(&lighting, length: MemoryLayout<OllinLighting>.stride, index: 1)
            useTracedScene(trace, accel)
            trace.setFragmentAccelerationStructure(accel, bufferIndex: 3)
            trace.setFragmentBuffer(meshBuffer, offset: 0, index: 6)
            trace.setFragmentBuffer(geoOffsets, offset: 0, index: 7)
            trace.setFragmentTexture(currentIBLPrefilter ?? iblPlaceholderCube, index: 5)
            trace.setFragmentTexture(ltcAmpTexture ?? stand, index: 9)
            trace.setFragmentTexture(iesArrayTexture ?? shapingStandIn(), index: 10)
            trace.setFragmentTexture(cookieArrayTexture ?? shapingStandIn(), index: 11)
            trace.setFragmentTexture(state.irrFront, index: 13)
            trace.setFragmentTexture(state.depFront, index: 14)
            trace.setFragmentTexture(state.offFront, index: 15)
            trace.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
            trace.endEncoding()
            state.lastTraceOffsets = state.offFront

            // params[1].z arms the irradiance blend's live temporal-response pair
            // (darkening hysteresis cut + brightening rate limit); headless leaves it
            // off so the iterations converge an unbiased progressive mean. The blends
            // read per-probe validity off the offsets the trace just used, so a
            // scrolled-in probe blends like a refit (fresh at full weight).
            let blendParams = [SIMD4<Float>(Float(rays), seed, hysteresis, Float(probeCount)),
                               SIMD4<Float>(prevValid, depthCap, supersample ? 0 : 1,
                                            cascadeCountParam)] + cascadeSlots
            encodeGIBlend(blendIrrPipe, surfels: surfels, previous: state.irrFront,
                          output: state.irrBack, params: blendParams, into: cb,
                          offsets: state.offFront)
            encodeGIBlend(blendDepPipe, surfels: surfels, previous: state.depFront,
                          output: state.depBack, params: blendParams, into: cb,
                          offsets: state.offFront)
            // Relocation: walk embedded probes out through this update's surfel
            // statistics (the next trace starts from the moved positions).
            let relocateParams = [SIMD4<Float>(Float(rays), seed, Float(probeCount), farCap),
                                  SIMD4<Float>(state.spacing, cascadeCountParam)] + cascadeSlots
            encodeGIBlend(relocatePipe, surfels: surfels, previous: state.offFront,
                          output: state.offBack, params: relocateParams, into: cb)
            state.flipped.toggle()      // the just-written backs are the next fronts
            state.offFlipped.toggle()   // the offsets advance in step (scrolls aside)
            state.valid = true
        }
        return GIResolved(irradiance: state.irrFront, depth: state.depFront,
                          offsets: state.lastTraceOffsets ?? state.offFront,
                          origin: state.origin, spacing: state.spacing, counts: counts,
                          biasScale: giBiasScale(state.spacing), cascades: state.cascades)
    }

    func encodeFieldShadowHalfRes(_ drawer: Drawer, into cb: MTLCommandBuffer,
                                          meshBuffer: MTLBuffer?, groupBuffer: MTLBuffer?, nodeBuffer: MTLBuffer?,
                                          uniforms3D: Uniforms3D, lighting: OllinLighting,
                                          fullWidth: Int, fullHeight: Int) -> MTLTexture? {
        let scale = resolveRaymarchScale(drawer.raymarchQualitySetting)
        guard scale < 1.0, lighting.fieldCasterCount > 0,
              let meshBuffer, let groupBuffer, let nodeBuffer,
              drawer.batches.contains(where: { $0.kind == .mesh3D }) else { return nil }

        let w = max(1, Int((Double(fullWidth) * scale).rounded()))
        let h = max(1, Int((Double(fullHeight) * scale).rounded()))
        if halfResFieldShadowSize != (w, h) || halfResFieldShadow == nil || halfResFieldShadowDepth == nil {
            guard let c = makeHalfResColor(width: w, height: h),
                  let d = makeHalfResDepth(width: w, height: h) else { return nil }
            halfResFieldShadow = c; halfResFieldShadowDepth = d; halfResFieldShadowSize = (w, h)
        }
        guard let color = halfResFieldShadow, let depth = halfResFieldShadowDepth,
              let pipe = try? pipeline(.fieldShadowHalfRes(depth: depthPixelFormat)) else { return nil }

        // Upload the field buffers here (this pre-pass may run before anything else uploads them).
        let groups3D = drawer.sdf3DGroups, nodes3D = drawer.sdf3DNodes
        groups3D.withUnsafeBytes { groupBuffer.contents().copyMemory(from: $0.baseAddress!, byteCount: $0.count) }
        if !nodes3D.isEmpty {
            nodes3D.withUnsafeBytes { nodeBuffer.contents().copyMemory(from: $0.baseAddress!, byteCount: $0.count) }
        }

        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = color
        pass.colorAttachments[0].loadAction = .clear
        pass.colorAttachments[0].clearColor = MTLClearColor(red: 1, green: 1, blue: 1, alpha: 1)  // lit where no mesh
        pass.colorAttachments[0].storeAction = .store
        pass.depthAttachment.texture = depth
        pass.depthAttachment.loadAction = .clear
        pass.depthAttachment.clearDepth = 1.0
        pass.depthAttachment.storeAction = .dontCare
        guard let enc = countedEncoder(cb, pass) else { return nil }
        enc.setViewport(MTLViewport(originX: 0, originY: 0, width: Double(w), height: Double(h), znear: 0, zfar: 1))
        enc.setRenderPipelineState(pipe)
        enc.setDepthStencilState(depthTestState)
        var u3 = uniforms3D
        var lit = lighting
        enc.setVertexBytes(&u3, length: MemoryLayout<Uniforms3D>.stride, index: 2)
        enc.setFragmentBytes(&lit, length: MemoryLayout<OllinLighting>.stride, index: 0)
        enc.setFragmentBuffer(groupBuffer, offset: 0, index: 4)
        enc.setFragmentBuffer(nodeBuffer, offset: 0, index: 5)

        // Every mesh batch (every receiver) renders, for correct depth occlusion; the factor for a
        // matcap/wireframe mesh is computed but unused (those fragments don't sample it).
        let meshStride = MemoryLayout<OllinMeshVertex>.stride
        let meshCount = drawer.meshVertices.count
        let batches = drawer.batches
        for i in batches.indices {
            let batch = batches[i]
            guard batch.kind == .mesh3D else { continue }
            let next = i + 1 < batches.count ? batches[i + 1] : nil
            let end = next?.meshStart ?? meshCount
            let count = end - batch.meshStart
            guard count > 0 else { continue }
            enc.setVertexBuffer(meshBuffer, offset: batch.meshStart * meshStride, index: 0)
            enc.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: count)
        }
        enc.endEncoding()
        return color
    }

    /// Contact shadows (`contactShadows()`): march a short screen-space ray from each
    /// pixel toward the casting light through the scene's own depth, so a resting
    /// object's fine contact darkens where the shadow map's resolution and bias leave
    /// a gap. Two stages in one command buffer: the frame's solid canvas meshes
    /// re-rendered depth-only from the camera (the shadow-map pipeline fed the
    /// camera's view-projection, jittered with the frame so the mask stays aligned
    /// under temporal AA), then a fullscreen march (`ollin_contact_shadow`) writing
    /// the per-pixel visibility mask the mesh fragments sample by screen position.
    /// Returns nil when the frame has no caster, no camera, or no meshes; the
    /// carriers' gate then zeroes and their sample branch is untaken (byte-identical).
    /// Only what the camera sees can occlude (the screen-space envelope); marched
    /// fields and target-drawn meshes are outside it by design.
    func encodeContactShadowPass(_ drawer: Drawer, into cb: MTLCommandBuffer,
                                 meshBuffer: MTLBuffer?,
                                 width: Int, height: Int,
                                 taaJitter: SIMD2<Float> = .zero) -> MTLTexture? {
        guard drawer.contactShadowsEnabled, let camera = drawer.camera3D, let meshBuffer,
              !drawer.meshVertices.isEmpty,
              drawer.batches.contains(where: {
                  $0.kind == .mesh3D && $0.target == nil && !$0.meshWireframe && !$0.meshGrid
              }) else { return nil }
        var lighting = drawer.makeLighting()
        let rayLen = lighting.contactShadow.x
        guard lighting.enabled != 0, lighting.shadowLight >= 0, rayLen > 0 else { return nil }

        if contactShadowSize != (width, height) || contactShadowMaskTex == nil || contactShadowDepthTex == nil {
            guard let m = makeFilterTexture(width: width, height: height),
                  let d = makeDepthResolve(width: width, height: height) else { return nil }
            contactShadowMaskTex = m; contactShadowDepthTex = d; contactShadowSize = (width, height)
        }
        guard let mask = contactShadowMaskTex, let depth = contactShadowDepthTex,
              let depthPipe = try? pipeline(.meshShadow),
              let marchPipe = try? pipeline(.effect("ollin_contact_shadow")) else { return nil }

        // Stage 1: the scene's depth as the camera sees it. The main pass's own depth
        // is a memoryless MSAA attachment, so the march renders its own single-sample
        // copy (the scatter-mask precedent), reusing the depth-only shadow pipeline
        // with the camera's view-projection in the light-matrix slot.
        var u3 = makeUniforms3D(drawer, camera: camera,
                                viewport: SIMD2(Float(width), Float(height)),
                                jitter: taaJitter)
        var vp = u3.projection * u3.view
        let pass = MTLRenderPassDescriptor()
        pass.depthAttachment.texture = depth
        pass.depthAttachment.loadAction = .clear
        pass.depthAttachment.clearDepth = 1.0
        pass.depthAttachment.storeAction = .store
        guard let enc = countedEncoder(cb, pass) else { return nil }
        enc.setViewport(MTLViewport(originX: 0, originY: 0, width: Double(width),
                                    height: Double(height), znear: 0, zfar: 1))
        enc.setRenderPipelineState(depthPipe)
        enc.setDepthStencilState(depthTestState)
        enc.setVertexBytes(&vp, length: MemoryLayout<simd_float4x4>.stride, index: 2)
        let meshStride = MemoryLayout<OllinMeshVertex>.stride
        let meshCount = drawer.meshVertices.count
        let batches = drawer.batches
        for i in batches.indices {
            let batch = batches[i]
            // Every solid canvas mesh occludes (wireframes have no surface, the grid
            // is live chrome, and a target-drawn mesh isn't on this canvas): the
            // scatter-mask walk's filter.
            guard batch.kind == .mesh3D, batch.target == nil,
                  !batch.meshWireframe, !batch.meshGrid else { continue }
            let next = i + 1 < batches.count ? batches[i + 1] : nil
            let end = next?.meshStart ?? meshCount
            let count = end - batch.meshStart
            guard count > 0 else { continue }
            enc.setVertexBuffer(meshBuffer, offset: batch.meshStart * meshStride, index: 0)
            enc.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: count)
        }
        enc.endEncoding()

        // Stage 2: the march. One fullscreen pass; the config rides params row 0
        // (w is the camera-ward ray-start lift as a fraction of the eye distance,
        // the no-normals self-occlusion guard; the acceptance band derives in the
        // shader from the ray's own projected span, so the one knob stays one),
        // the caster comes from the packed lighting, the matrices from Uniforms3D.
        let marchPass = MTLRenderPassDescriptor()
        marchPass.colorAttachments[0].texture = mask
        marchPass.colorAttachments[0].loadAction = .dontCare
        marchPass.colorAttachments[0].storeAction = .store
        guard let menc = countedEncoder(cb, marchPass) else { return nil }
        menc.setRenderPipelineState(marchPipe)
        menc.setFragmentTexture(depth, index: 0)
        var params = SIMD4<Float>(rayLen, 0,
                                  Float(resolveContactShadowSteps()), 0.002)
        menc.setFragmentBytes(&params, length: MemoryLayout<SIMD4<Float>>.stride, index: 0)
        menc.setFragmentBytes(&lighting, length: MemoryLayout<OllinLighting>.stride, index: 1)
        menc.setFragmentBytes(&u3, length: MemoryLayout<Uniforms3D>.stride, index: 2)
        menc.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        menc.endEncoding()
        return mask
    }

    /// A half-resolution sampleable linear-float color target for the raymarch pre-pass.
    private func makeHalfResColor(width: Int, height: Int) -> MTLTexture? {
        let desc = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: linearFormat, width: width, height: height, mipmapped: false)
        desc.usage = [.renderTarget, .shaderRead]
        desc.storageMode = .private
        return device.makeTexture(descriptor: desc)
    }

    /// A half-resolution sampleable depth target for the raymarch pre-pass (read in the
    /// upsample as a `depth2d<float>`, so meshes still z-test against the field).
    private func makeHalfResDepth(width: Int, height: Int) -> MTLTexture? {
        let desc = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: depthPixelFormat, width: width, height: height, mipmapped: false)
        desc.usage = [.renderTarget, .shaderRead]
        desc.storageMode = .private
        return device.makeTexture(descriptor: desc)
    }

    /// Build (in place) the per-frame primitive acceleration structure over the shadow
    /// casters for a ray-traced point light — one geometry descriptor per solid/textured
    /// mesh batch (wireframe doesn't cast), reading world-space positions straight from
    /// the `meshBuffer` the geometry pass uses (position is the first field of
    /// `OllinMeshVertex`, so a `.float3` read at the vertex stride lands on it). Encoded
    /// ahead of the geometry pass in the same command buffer, so Metal orders build →
    /// trace. The structure + scratch grow in place only when the scene outgrows them.
    /// Returns nil when there's nothing to cast (the caller then falls back / unshadows).
    /// The path-traced export's extra per-geometry scene tables, built beside the
    /// acceleration structure: the bindless surface-map handles a hit samples (base
    /// color, normal, metallic-roughness, occlusion, emissive; five slots per
    /// geometry, the `OllinPTTexEntry` layout), the emissive-triangle table the
    /// mesh-light strategy draws from, and the transmission flag that gates the
    /// transparent shadow walk.
    struct PTSceneTables {
        var textures: MTLBuffer        // per-geometry map resource IDs (bindless, 5 slots)
        var textureList: [MTLTexture]  // the real textures to mark resident
        var emissive: MTLBuffer        // the OllinPTEmissiveTri power-CDF table
        var emissiveCount: Int         // triangles in it (0 = no mesh lights)
        var emissivePower: Float       // total power (luminance x area), the pdf scale
        var anyTransmission: Bool      // any traced geometry transmits
    }

    /// The gated surface-map set one traced geometry wears: each slot carries the
    /// mesh material's map only when the batch finish's matching gate is up (the
    /// raster encode's own binding rule), so identity over the slots is exactly
    /// "would a hit read different texels", both for the accel run-breaking and
    /// for the table upload. The base slot has no gate; a texture-wearing batch
    /// on a sampling pipeline always reads it.
    struct PTGeoMaps {
        var base: Image?
        var normal: Image?
        var metallicRoughness: Image?
        var occlusion: Image?
        var emissive: Image?

        static func same(_ a: PTGeoMaps, _ b: PTGeoMaps) -> Bool {
            a.base === b.base && a.normal === b.normal
                && a.metallicRoughness === b.metallicRoughness
                && a.occlusion === b.occlusion && a.emissive === b.emissive
        }
    }

    func buildShadowAccel(_ drawer: Drawer, into commandBuffer: MTLCommandBuffer,
                          meshBuffer: MTLBuffer, causticMats: Bool = false,
                          pathTraceMats: Bool = false)
        -> (accel: MTLAccelerationStructure, offsets: MTLBuffer, causticMats: MTLBuffer?,
            ptMats: MTLBuffer?, ptScene: PTSceneTables?)? {
        let meshStride = MemoryLayout<OllinMeshVertex>.stride
        let meshVertices = drawer.meshVertices
        let batches = drawer.batches
        // Coalesce maximal runs of contiguous caster batches into one geometry descriptor
        // each (a non-casting batch — wireframe, or a non-mesh kind — breaks the run). The
        // caster vertices of a run are contiguous in `meshBuffer`, so one descriptor covers
        // them; fewer descriptors means a cheaper structure build (its per-geometry overhead
        // dominates at creative-coding triangle counts). A fully solid scene becomes one.
        var geometries: [MTLAccelerationStructureTriangleGeometryDescriptor] = []
        // The base vertex index (the run start) of each geometry, in build order, so a
        // reflection hit's `geometryId` recovers where its triangles begin in `meshBuffer`.
        var geoOffsets: [UInt32] = []
        // With `causticMats`, a change in the caustic-relevant material fields also
        // breaks the run, so each geometry is material-uniform for the photon trace,
        // and the per-geometry `OllinCausticGeo` entries fill in parallel. With
        // `pathTraceMats` (the offline path-traced export), *any* change in the batch
        // finish breaks the run instead, and the full `OllinMaterial` fills in
        // parallel, so a path-trace hit's `geometryId` resolves its whole material.
        var geoMats: [OllinCausticGeo] = []
        var geoFinishes: [OllinMaterial] = []
        // The path-traced build's parallels: each geometry's vertex count (for the
        // emissive-triangle scan) and its gated surface-map set (empty slots =
        // untextured; map identity also breaks the run, so a geometry is
        // map-uniform across all five slots).
        var geoCounts: [Int] = []
        var geoTextures: [PTGeoMaps] = []
        var runStart = -1, runEnd = 0
        var runMat = OllinCausticGeo()
        var runFinish = OllinMaterial()
        var runMaps = PTGeoMaps()
        func ptMaps(_ batch: GeometryBatch) -> PTGeoMaps {
            let m = batch.material
            let f = batch.finish
            return PTGeoMaps(base: m?.texture,
                             normal: f.normalScale > 0 ? m?.normalTexture : nil,
                             metallicRoughness: f.mrGate > 0 ? m?.metallicRoughnessTexture : nil,
                             occlusion: f.occlusionStrength > 0 ? m?.occlusionTexture : nil,
                             emissive: f.emissive.w > 0 ? m?.emissiveTexture : nil)
        }
        func causticGeo(_ f: OllinMaterial) -> OllinCausticGeo {
            var g = OllinCausticGeo()
            g.refractive = SIMD4(f.transmission, f.ior, f.thickness > 0 ? 0 : 1, 0)
            g.attenuation = f.attenuation
            return g
        }
        // The imported C struct has no synthesized ==; the finishes are packed
        // CPU-side from the same inputs, so a bytewise compare is exact.
        func sameFinish(_ a: OllinMaterial, _ b: OllinMaterial) -> Bool {
            var x = a, y = b
            return memcmp(&x, &y, MemoryLayout<OllinMaterial>.size) == 0
        }
        func flushRun() {
            guard runStart >= 0, runEnd - runStart >= 3 else { runStart = -1; return }
            let geo = MTLAccelerationStructureTriangleGeometryDescriptor()
            geo.vertexBuffer = meshBuffer
            geo.vertexBufferOffset = runStart * meshStride
            geo.vertexStride = meshStride
            geo.vertexFormat = .float3        // position.xyz from each vertex (field offset 0)
            geo.triangleCount = (runEnd - runStart) / 3
            geo.opaque = true                 // load-bearing: else triangle hits never commit
            geometries.append(geo)
            geoOffsets.append(UInt32(runStart))
            geoMats.append(runMat)
            geoFinishes.append(runFinish)
            geoCounts.append(runEnd - runStart)
            geoTextures.append(runMaps)
            runStart = -1
        }
        for i in batches.indices {
            let batch = batches[i]
            // Exclude the ground-grid chrome like `drawShadowCasters` does: its huge
            // opaque y=0 quad would otherwise occlude every downward reflection ray
            // (and RT shadow ray) whenever the live grid toggle is on. The path-traced
            // build also excludes matcap batches: a matcap is the unlit, emissive-look
            // finish (the glowing prop a sketch draws exactly over an area light), so
            // it keeps rastering over the traced layer instead, and its body must not
            // swallow the light's own next-event visibility rays.
            let isCaster = batch.kind == .mesh3D && !batch.meshWireframe && !batch.meshGrid
                && !(pathTraceMats && batch.matcap != nil)
            let end = i + 1 < batches.count ? batches[i + 1].meshStart : meshVertices.count
            if isCaster {
                let mat = causticMats ? causticGeo(batch.finish) : OllinCausticGeo()
                if runStart >= 0, causticMats,
                   mat.refractive != runMat.refractive || mat.attenuation != runMat.attenuation {
                    flushRun()
                }
                if runStart >= 0, pathTraceMats,
                   !sameFinish(batch.finish, runFinish)
                       || !PTGeoMaps.same(ptMaps(batch), runMaps) {
                    flushRun()
                }
                if runStart < 0 {
                    runStart = batch.meshStart
                    runMat = mat
                    runFinish = batch.finish
                    runMaps = ptMaps(batch)
                }
                runEnd = end
            } else {
                flushRun()
            }
        }
        flushRun()

        // The copies of every instanced draw. Each becomes one instance of its base
        // mesh's own structure, so the copy costs a matrix rather than a triangle list,
        // which is the whole reason the instanced call exists. Their base vertices are
        // appended to the mesh buffer after the plain ones, so a single pointer still
        // serves the hit fetch. Two exclusions: the path-traced export takes the plain
        // meshes alone (its material tables are per geometry, and a copy has none of its
        // own), and a mesh buffer that has no room for the appended vertices leaves the
        // copies out rather than writing past its end.
        struct CopyGroup {
            var vertexStart = 0, vertexCount = 0, instanceStart = 0, instanceCount = 0
        }
        var copyGroups: [CopyGroup] = []
        let copyVertexBase = meshVertices.count
        let copyVertices = drawer.instancedMeshVertices
        if !pathTraceMats, !copyVertices.isEmpty,
           meshBuffer.length >= (copyVertexBase + copyVertices.count) * meshStride {
            for batch in batches where batch.kind == .meshInstanced && batch.meshInstanceCount > 0 {
                guard batch.instancedVertexCount >= 3,
                      batch.meshInstanceStart + batch.meshInstanceCount <= drawer.meshInstances.count
                else { continue }
                copyGroups.append(CopyGroup(vertexStart: batch.instancedVertexStart,
                                            vertexCount: batch.instancedVertexCount,
                                            instanceStart: batch.meshInstanceStart,
                                            instanceCount: batch.meshInstanceCount))
            }
            if !copyGroups.isEmpty {
                copyVertices.withUnsafeBytes { raw in
                    meshBuffer.contents().advanced(by: copyVertexBase * meshStride)
                        .copyMemory(from: raw.baseAddress!, byteCount: raw.count)
                }
            }
        }
        guard !geometries.isEmpty || !copyGroups.isEmpty else { return nil }

        // A plain (non-refittable) build: a refittable structure trades traversal speed for
        // the cheaper refit, and on a software-ray-tracing GPU (no RT hardware, e.g. M1/M2)
        // the per-ray traversal — millions of rays — dwarfs the per-frame build, so the
        // faster-to-traverse tree wins. Rebuild each frame; grow the structures in place
        // only when the scene outgrows them.
        var descs: [MTLPrimitiveAccelerationStructureDescriptor] = []
        if !geometries.isEmpty {
            let d = MTLPrimitiveAccelerationStructureDescriptor()
            d.geometryDescriptors = geometries
            descs.append(d)
        }
        let hasScene = !geometries.isEmpty
        for group in copyGroups {
            let geo = MTLAccelerationStructureTriangleGeometryDescriptor()
            geo.vertexBuffer = meshBuffer
            geo.vertexBufferOffset = (copyVertexBase + group.vertexStart) * meshStride
            geo.vertexStride = meshStride
            geo.vertexFormat = .float3
            geo.triangleCount = group.vertexCount / 3
            geo.opaque = true
            let d = MTLPrimitiveAccelerationStructureDescriptor()
            d.geometryDescriptors = [geo]
            descs.append(d)
        }

        // Every structure this frame needs, allocated (and grown) before anything builds,
        // so the one scratch buffer below can be sized for the whole set at once.
        var structures: [MTLAccelerationStructure] = []
        var scratchNeeded = 0
        var scratchOffsets: [Int] = []
        for (i, d) in descs.enumerated() {
            let sizes = device.accelerationStructureSizes(descriptor: d)
            let structure: MTLAccelerationStructure?
            if i == 0 && hasScene {
                if shadowAccel == nil || shadowAccelCapacity < sizes.accelerationStructureSize {
                    shadowAccel = device.makeAccelerationStructure(size: sizes.accelerationStructureSize)
                    shadowAccelCapacity = sizes.accelerationStructureSize
                }
                structure = shadowAccel
            } else {
                let slot = hasScene ? i - 1 : i
                while rtCopyAccels.count <= slot {
                    guard let fresh = device.makeAccelerationStructure(size: max(1, sizes.accelerationStructureSize))
                    else { return nil }
                    rtCopyAccels.append(fresh)
                    rtCopyAccelCapacities.append(sizes.accelerationStructureSize)
                }
                if rtCopyAccelCapacities[slot] < sizes.accelerationStructureSize {
                    guard let grown = device.makeAccelerationStructure(size: sizes.accelerationStructureSize)
                    else { return nil }
                    rtCopyAccels[slot] = grown
                    rtCopyAccelCapacities[slot] = sizes.accelerationStructureSize
                }
                structure = rtCopyAccels[slot]
            }
            guard let structure else { return nil }
            structures.append(structure)
            scratchOffsets.append(scratchNeeded)
            scratchNeeded += (sizes.buildScratchBufferSize + 255) / 256 * 256
        }

        // One instance per copy, plus one for the plain meshes when the frame drew any.
        // The plain-mesh instance goes first and sits square at the origin: its vertices
        // carry their own placement already, so its matrix is the identity.
        var instanceDescs: [MTLAccelerationStructureInstanceDescriptor] = []
        var records: [UInt32] = []
        func record(vertexBase: UInt32, tint: SIMD4<Float>) {
            records.append(vertexBase)
            records.append(tint.x.bitPattern)
            records.append(tint.y.bitPattern)
            records.append(tint.z.bitPattern)
        }
        func instance(_ model: simd_float4x4, structureIndex: Int) {
            var d = MTLAccelerationStructureInstanceDescriptor()
            d.accelerationStructureIndex = UInt32(structureIndex)
            d.options = .opaque
            d.mask = 0xFF
            d.intersectionFunctionTableOffset = 0
            d.transformationMatrix = MTLPackedFloat4x3(columns: (
                MTLPackedFloat3Make(model.columns.0.x, model.columns.0.y, model.columns.0.z),
                MTLPackedFloat3Make(model.columns.1.x, model.columns.1.y, model.columns.1.z),
                MTLPackedFloat3Make(model.columns.2.x, model.columns.2.y, model.columns.2.z),
                MTLPackedFloat3Make(model.columns.3.x, model.columns.3.y, model.columns.3.z)))
            instanceDescs.append(d)
        }
        if hasScene {
            instance(matrix_identity_float4x4, structureIndex: 0)
            record(vertexBase: MetalRenderer.rtPlainMesh, tint: SIMD4<Float>(1, 1, 1, 1))
        }
        for (i, group) in copyGroups.enumerated() {
            let structureIndex = (hasScene ? 1 : 0) + i
            let base = UInt32(copyVertexBase + group.vertexStart)
            for k in 0..<group.instanceCount {
                let placement = drawer.meshInstances[group.instanceStart + k]
                instance(placement.model, structureIndex: structureIndex)
                record(vertexBase: base, tint: placement.color)
            }
        }

        let instanceStride = MemoryLayout<MTLAccelerationStructureInstanceDescriptor>.stride
        let instanceLength = max(instanceStride, instanceDescs.count * instanceStride)
        if (rtInstanceDescriptorBuffers[frameIndex]?.length ?? 0) < instanceLength {
            rtInstanceDescriptorBuffers[frameIndex] = device.makeBuffer(length: instanceLength,
                                                                        options: .storageModeShared)
        }
        guard let instanceBuffer = rtInstanceDescriptorBuffers[frameIndex] else { return nil }
        instanceDescs.withUnsafeBytes { raw in
            instanceBuffer.contents().copyMemory(from: raw.baseAddress!, byteCount: raw.count)
        }
        let instanceDesc = MTLInstanceAccelerationStructureDescriptor()
        instanceDesc.instancedAccelerationStructures = structures
        instanceDesc.instanceCount = instanceDescs.count
        instanceDesc.instanceDescriptorBuffer = instanceBuffer
        let instanceSizes = device.accelerationStructureSizes(descriptor: instanceDesc)
        if rtInstanceAccel == nil || rtInstanceAccelCapacity < instanceSizes.accelerationStructureSize {
            rtInstanceAccel = device.makeAccelerationStructure(size: instanceSizes.accelerationStructureSize)
            rtInstanceAccelCapacity = instanceSizes.accelerationStructureSize
        }
        let instanceScratchOffset = scratchNeeded
        scratchNeeded += (instanceSizes.buildScratchBufferSize + 255) / 256 * 256
        if (shadowAccelScratch?.length ?? 0) < scratchNeeded {
            shadowAccelScratch = device.makeBuffer(length: max(1, scratchNeeded),
                                                   options: .storageModePrivate)
        }
        rtReferencedAccels = structures
        guard let accel = rtInstanceAccel, let scratch = shadowAccelScratch,
              let enc = commandBuffer.makeAccelerationStructureCommandEncoder() else { return nil }
        for (i, d) in descs.enumerated() {
            enc.build(accelerationStructure: structures[i], descriptor: d,
                      scratchBuffer: scratch, scratchBufferOffset: scratchOffsets[i])
        }
        enc.endEncoding()
        // The instance structure refers to the ones just built, so it takes its own
        // encoder: two encoders in one command buffer run in the order they were made.
        guard let instanceEnc = commandBuffer.makeAccelerationStructureCommandEncoder() else { return nil }
        instanceEnc.build(accelerationStructure: accel, descriptor: instanceDesc,
                          scratchBuffer: scratch, scratchBufferOffset: instanceScratchOffset)
        instanceEnc.endEncoding()
        // The hit-lookup table, uploaded for the reflection hit fetch. Filled CPU-side here
        // (before the command buffer commits), so the main pass reads it this frame, through
        // the frame ring, never a shared buffer an in-flight frame still reads. Layout, which
        // `ollin_rt_hit_lookup` reads back: the instance count, then that many four-uint
        // records, then one base-vertex index per geometry of the plain-mesh instance.
        var table: [UInt32] = [UInt32(instanceDescs.count)]
        table.append(contentsOf: records)
        table.append(contentsOf: geoOffsets)
        let offsetsLength = max(MemoryLayout<UInt32>.stride, table.count * MemoryLayout<UInt32>.stride)
        if (meshGeoOffsetBuffers[frameIndex]?.length ?? 0) < offsetsLength {
            meshGeoOffsetBuffers[frameIndex] = device.makeBuffer(length: offsetsLength, options: .storageModeShared)
        }
        guard let offsetsBuffer = meshGeoOffsetBuffers[frameIndex] else { return nil }
        table.withUnsafeBytes { raw in
            offsetsBuffer.contents().copyMemory(from: raw.baseAddress!, byteCount: raw.count)
        }
        // The per-geometry caustic materials, riding the same per-frame ring.
        var matsBuffer: MTLBuffer? = nil
        if causticMats {
            let matsLength = max(MemoryLayout<OllinCausticGeo>.stride,
                                 geoMats.count * MemoryLayout<OllinCausticGeo>.stride)
            if (causticGeoMatBuffers[frameIndex]?.length ?? 0) < matsLength {
                causticGeoMatBuffers[frameIndex] = device.makeBuffer(length: matsLength,
                                                                     options: .storageModeShared)
            }
            matsBuffer = causticGeoMatBuffers[frameIndex]
            geoMats.withUnsafeBytes { raw in
                matsBuffer?.contents().copyMemory(from: raw.baseAddress!, byteCount: raw.count)
            }
        }
        // The per-geometry full finishes for the path-traced export, same ring rule.
        var finishBuffer: MTLBuffer? = nil
        var ptScene: PTSceneTables? = nil
        if pathTraceMats {
            let finishLength = max(MemoryLayout<OllinMaterial>.stride,
                                   geoFinishes.count * MemoryLayout<OllinMaterial>.stride)
            if (ptGeoMatBuffers[frameIndex]?.length ?? 0) < finishLength {
                ptGeoMatBuffers[frameIndex] = device.makeBuffer(length: finishLength,
                                                                options: .storageModeShared)
            }
            finishBuffer = ptGeoMatBuffers[frameIndex]
            geoFinishes.withUnsafeBytes { raw in
                finishBuffer?.contents().copyMemory(from: raw.baseAddress!, byteCount: raw.count)
            }
            ptScene = buildPTSceneTables(drawer, geoOffsets: geoOffsets, geoCounts: geoCounts,
                                         geoFinishes: geoFinishes, geoTextures: geoTextures)
        }
        return (accel, offsetsBuffer, matsBuffer, finishBuffer, ptScene)
    }

    /// The path-traced export's per-geometry scene tables: the bindless surface-map
    /// handles, the emissive-triangle power CDF, and the transmission gate.
    /// Transient allocations (the export waits on its own command buffers, so no
    /// in-flight frame shares them).
    private func buildPTSceneTables(_ drawer: Drawer, geoOffsets: [UInt32],
                                    geoCounts: [Int], geoFinishes: [OllinMaterial],
                                    geoTextures: [PTGeoMaps]) -> PTSceneTables? {
        // The bindless map table: five GPU resource IDs per geometry (the
        // `OllinPTTexEntry` slot order: base, normal, metallic-roughness,
        // occlusion, emissive), the white stand-in where a slot is unbound (the
        // base slot's sample is then the identity; the gated slots are never
        // read unbound), so the kernel indexes without a gate. Base and emissive
        // are color (sRGB), the value-encoding maps data (the raster encode's
        // own split). The textures ride along for the encoder's residency call.
        guard let white = whiteStandIn() else { return nil }
        var textureList: [MTLTexture] = [white]
        var ids: [UInt64] = []
        ids.reserveCapacity(geoTextures.count * 5)
        let whiteID = unsafeBitCast(white.gpuResourceID, to: UInt64.self)
        func slot(_ tex: MTLTexture?) {
            if let tex {
                textureList.append(tex)
                ids.append(unsafeBitCast(tex.gpuResourceID, to: UInt64.self))
            } else {
                ids.append(whiteID)
            }
        }
        for maps in geoTextures {
            slot(maps.base?.texture(for: device))
            slot(maps.normal?.linearTexture(for: device))
            slot(maps.metallicRoughness?.linearTexture(for: device))
            slot(maps.occlusion?.linearTexture(for: device))
            slot(maps.emissive?.texture(for: device))
        }
        guard let texBuffer = ids.withUnsafeBytes({ raw in
            device.makeBuffer(bytes: raw.baseAddress!, length: max(raw.count, 8),
                              options: .storageModeShared)
        }) else { return nil }

        // The emissive-triangle table: every triangle of every glowing geometry,
        // weighted by luminance x area into a running CDF, so the kernel draws
        // mesh-light samples by each triangle's share of the scene's power.
        var tris: [OllinPTEmissiveTri] = []
        var totalPower = 0.0
        let verts = drawer.meshVertices
        for g in geoFinishes.indices {
            let e = geoFinishes[g].emissive
            let lum = Double(0.2126 * e.x + 0.7152 * e.y + 0.0722 * e.z)
            guard lum > 0 else { continue }
            let start = Int(geoOffsets[g])
            for t in 0..<(geoCounts[g] / 3) {
                let base = start + t * 3
                let a = SIMD3(verts[base].position.x, verts[base].position.y, verts[base].position.z)
                let b = SIMD3(verts[base + 1].position.x, verts[base + 1].position.y, verts[base + 1].position.z)
                let c = SIMD3(verts[base + 2].position.x, verts[base + 2].position.y, verts[base + 2].position.z)
                let area = 0.5 * Double(simd_length(simd_cross(b - a, c - a)))
                guard area > 1e-9 else { continue }
                totalPower += lum * area
                var entry = OllinPTEmissiveTri()
                entry.cdf = Float(totalPower)   // normalized below
                entry.tri = UInt32(base)
                entry.geo = UInt32(g)
                tris.append(entry)
            }
        }
        if totalPower > 0 {
            for i in tris.indices { tris[i].cdf /= Float(totalPower) }
            tris[tris.count - 1].cdf = 1        // guard the search's top end
        } else {
            tris = []
        }
        let emLength = max(MemoryLayout<OllinPTEmissiveTri>.stride,
                           tris.count * MemoryLayout<OllinPTEmissiveTri>.stride)
        guard let emBuffer = device.makeBuffer(length: emLength, options: .storageModeShared)
        else { return nil }
        tris.withUnsafeBytes { raw in
            if let base = raw.baseAddress, raw.count > 0 {
                emBuffer.contents().copyMemory(from: base, byteCount: raw.count)
            }
        }
        let anyTransmission = geoFinishes.contains { $0.shadingModel == 3 && $0.transmission > 0 }
        return PTSceneTables(textures: texBuffer, textureList: textureList,
                             emissive: emBuffer, emissiveCount: tris.count,
                             emissivePower: Float(totalPower),
                             anyTransmission: anyTransmission)
    }

    /// A 1-triangle acceleration structure bound to the lit mesh fragment whenever no
    /// ray-traced point shadow is active this frame, so the fragment's declared
    /// `primitive_acceleration_structure` argument is always satisfied (it only traces
    /// when `shadowKind == 2`). Built once, far from any scene so it never matters.
    /// Bind-time residency for the traced scene. The bound structure is an *instance*
    /// structure, which reaches the structures it was built over indirectly, and an
    /// encoder does not make those resident on its own. Every site that binds the scene
    /// goes through here so none of them can forget.
    func useTracedScene(_ enc: MTLRenderCommandEncoder, _ accel: MTLAccelerationStructure) {
        enc.useResource(accel, usage: .read, stages: .fragment)
        let referenced = rtReferencedAccels + [dummyShadowAccel].compactMap { $0 }
        if !referenced.isEmpty { enc.useResources(referenced, usage: .read, stages: .fragment) }
    }

    func useTracedScene(_ enc: MTLComputeCommandEncoder, _ accel: MTLAccelerationStructure) {
        enc.useResource(accel, usage: .read)
        let referenced = rtReferencedAccels + [dummyShadowAccel].compactMap { $0 }
        if !referenced.isEmpty { enc.useResources(referenced, usage: .read) }
    }

    func ensureDummyShadowAccel() -> MTLAccelerationStructure? {
        if let a = dummyInstanceAccel { return a }
        var verts: [SIMD3<Float>] = [SIMD3(1e6, 1e6, 1e6), SIMD3(1e6 + 1, 1e6, 1e6),
                                     SIMD3(1e6, 1e6 + 1, 1e6)]
        let vbuf = device.makeBuffer(bytes: &verts, length: MemoryLayout<SIMD3<Float>>.stride * 3,
                                     options: .storageModeShared)
        let geo = MTLAccelerationStructureTriangleGeometryDescriptor()
        geo.vertexBuffer = vbuf
        geo.vertexStride = MemoryLayout<SIMD3<Float>>.stride
        geo.vertexFormat = .float3
        geo.triangleCount = 1
        let desc = MTLPrimitiveAccelerationStructureDescriptor()
        desc.geometryDescriptors = [geo]
        let sizes = device.accelerationStructureSizes(descriptor: desc)
        // The bound argument is an instance structure, so the stand-in is one too: one
        // instance of the single far-away triangle, at the origin.
        var one = MTLAccelerationStructureInstanceDescriptor()
        one.accelerationStructureIndex = 0
        one.options = .opaque
        one.mask = 0xFF
        one.transformationMatrix = MTLPackedFloat4x3(columns: (
            MTLPackedFloat3Make(1, 0, 0), MTLPackedFloat3Make(0, 1, 0),
            MTLPackedFloat3Make(0, 0, 1), MTLPackedFloat3Make(0, 0, 0)))
        guard let accel = device.makeAccelerationStructure(size: sizes.accelerationStructureSize),
              let instanceBuffer = device.makeBuffer(
                  bytes: &one,
                  length: MemoryLayout<MTLAccelerationStructureInstanceDescriptor>.stride,
                  options: .storageModeShared)
        else { return nil }
        let instanceDesc = MTLInstanceAccelerationStructureDescriptor()
        instanceDesc.instancedAccelerationStructures = [accel]
        instanceDesc.instanceCount = 1
        instanceDesc.instanceDescriptorBuffer = instanceBuffer
        let instanceSizes = device.accelerationStructureSizes(descriptor: instanceDesc)
        guard let instanceAccel = device.makeAccelerationStructure(size: instanceSizes.accelerationStructureSize),
              let scratch = device.makeBuffer(
                  length: max(1, max(sizes.buildScratchBufferSize,
                                     instanceSizes.buildScratchBufferSize)),
                  options: .storageModePrivate),
              let cb = commandQueue.makeCommandBuffer(),
              let enc = cb.makeAccelerationStructureCommandEncoder() else { return nil }
        enc.build(accelerationStructure: accel, descriptor: desc,
                  scratchBuffer: scratch, scratchBufferOffset: 0)
        enc.endEncoding()
        guard let instanceEnc = cb.makeAccelerationStructureCommandEncoder() else { return nil }
        instanceEnc.build(accelerationStructure: instanceAccel, descriptor: instanceDesc,
                          scratchBuffer: scratch, scratchBufferOffset: 0)
        instanceEnc.endEncoding(); cb.commit(); cb.waitUntilCompleted()
        dummyShadowAccel = accel        // held: the instance structure refers to it
        dummyInstanceAccel = instanceAccel
        return dummyInstanceAccel
    }

    /// A 1-element per-geometry-offset buffer bound at fragment buffer 7 whenever ray-traced
    /// reflections aren't producing real offsets this frame, so the RT-compiled mesh
    /// fragment's declared offsets argument is always satisfied (it's read only on a
    /// reflection hit, which can't happen when `lighting.rtReflections == 0`).
    func ensureDummyGeoOffsets() -> MTLBuffer? {
        if let b = dummyGeoOffsets { return b }
        // Two elements, not one: the lookup table reads its instance count first, and a
        // count of zero then sends the geometry read to the element after it.
        var empty: [UInt32] = [0, 0]
        dummyGeoOffsets = device.makeBuffer(bytes: &empty,
                                            length: MemoryLayout<UInt32>.stride * 2,
                                            options: .storageModeShared)
        return dummyGeoOffsets
    }

    /// Draw every shadow-casting mesh batch into the active shadow encoder. Solid and
    /// textured meshes cast; wireframe (see-through edges) does not. `instanceCount` is
    /// 1 for the 2D pass and 6 for the layered cube pass (one instance per face).
    private func drawShadowCasters(_ drawer: Drawer, encoder: MTLRenderCommandEncoder,
                                   meshBuffer: MTLBuffer, instanceCount: Int) {
        let meshStride = MemoryLayout<OllinMeshVertex>.stride
        let meshVertices = drawer.meshVertices
        let batches = drawer.batches
        for i in batches.indices {
            let batch = batches[i]
            // Solid/textured meshes cast; wireframe (see-through edges) and the live
            // ground-grid overlay (a mostly-transparent sheet) do not; a grid that cast
            // would flood the whole floor below it into shadow.
            guard batch.kind == .mesh3D, !batch.meshWireframe, !batch.meshGrid else { continue }
            let next = i + 1 < batches.count ? batches[i + 1] : nil
            let end = next?.meshStart ?? meshVertices.count
            let count = end - batch.meshStart
            guard count > 0 else { continue }
            encoder.setVertexBuffer(meshBuffer, offset: batch.meshStart * meshStride, index: 0)
            encoder.drawPrimitives(type: .triangle, vertexStart: 0,
                                   vertexCount: count, instanceCount: instanceCount)
        }
    }

    /// Draw every instanced-mesh batch into the active shadow encoder (the caller
    /// sets the matching instanced pipeline first). `faces` is 1 for the 2D pass
    /// and 6 for the layered cube pass, where the draw runs `copies * 6` instances
    /// and the vertex routes `iid % 6` to a face, `iid / 6` to a copy.
    private func drawInstancedShadowCasters(_ drawer: Drawer, encoder: MTLRenderCommandEncoder,
                                            instancedMeshBuffer: MTLBuffer?,
                                            meshInstanceBuffer: MTLBuffer?, faces: Int) {
        guard let instancedMeshBuffer else { return }
        let meshStride = MemoryLayout<OllinMeshVertex>.stride
        let instStride = MemoryLayout<OllinMeshInstance>.stride
        for batch in drawer.batches where batch.kind == .meshInstanced {
            guard batch.instancedVertexCount > 0 else { continue }
            let copies: Int
            if let gpuBuffer = batch.particleBuffer {
                guard batch.particleCount > 0,
                      let ib = gpuBuffer.metalBuffer(for: device) else { continue }
                encoder.setVertexBuffer(ib, offset: 0, index: 4)
                copies = batch.particleCount
            } else {
                guard batch.meshInstanceCount > 0, let meshInstanceBuffer else { continue }
                encoder.setVertexBuffer(meshInstanceBuffer,
                                        offset: batch.meshInstanceStart * instStride, index: 4)
                copies = batch.meshInstanceCount
            }
            encoder.setVertexBuffer(instancedMeshBuffer,
                                    offset: batch.instancedVertexStart * meshStride, index: 0)
            encoder.drawPrimitives(type: .triangle, vertexStart: 0,
                                   vertexCount: batch.instancedVertexCount,
                                   instanceCount: copies * faces)
        }
    }

    /// Draw every `MeshField` batch into the active shadow encoder from the
    /// field's own retained buffers. The 2D (directional/spot) pass runs the
    /// GPU-written indirect draws culled against the LIGHT's frustum
    /// (`shadowArguments`/`shadowCompacted`, filled by `encodeMeshFieldCulling`);
    /// the layered cube pass is omnidirectional, so it draws each entry's whole
    /// copy run directly, every copy on all six faces. The caller sets the
    /// matching field shadow pipeline first; `faces` is 1 for the 2D map, 6 for
    /// the cube.
    private func drawFieldShadowCasters(_ drawer: Drawer, encoder: MTLRenderCommandEncoder,
                                        faces: Int) {
        let instStride = MemoryLayout<OllinMeshInstance>.stride
        let argStride = MemoryLayout<MTLDrawPrimitivesIndirectArguments>.stride
        for batch in drawer.batches where batch.kind == .meshField {
            guard let field = batch.field,
                  let resources = field.gpuResources(for: device) else { continue }
            encoder.setVertexBuffer(resources.vertices, offset: 0, index: 0)
            var fieldModel = batch.fieldTransform
            encoder.setVertexBytes(&fieldModel, length: MemoryLayout<simd_float4x4>.stride, index: 6)
            if faces == 1 {
                encoder.setVertexBuffer(resources.instances, offset: 0, index: 4)
                encoder.setVertexBuffer(resources.shadowCompacted, offset: 0, index: 5)
                for entry in 0 ..< resources.entryCount {
                    encoder.drawPrimitives(type: .triangle,
                                           indirectBuffer: resources.shadowArguments,
                                           indirectBufferOffset: entry * argStride)
                }
            } else {
                for entry in field.entries where entry.copyCount > 0 {
                    encoder.setVertexBuffer(resources.instances,
                                            offset: Int(entry.copyStart) * instStride, index: 4)
                    encoder.drawPrimitives(type: .triangle, vertexStart: Int(entry.vertexStart),
                                           vertexCount: Int(entry.vertexCount),
                                           instanceCount: Int(entry.copyCount) * faces)
                }
            }
        }
    }

    /// The single-sample linear-float resolve target: the MSAA resolve destination
    /// (`.renderTarget`) that the present pass then samples (`.shaderRead`).
    func makeFloatResolve(width: Int, height: Int) -> MTLTexture? {
        let desc = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: linearFormat, width: width, height: height, mipmapped: false)
        desc.usage = [.renderTarget, .shaderRead]
        desc.storageMode = .private
        return device.makeTexture(descriptor: desc)
    }

    /// A single-sample sRGB display texture: the present pass's tone-mapped output,
    /// for the off-screen paths (export read-back, Syphon/grab hand-off).
    /// `.pixelFormatView` lets a consumer (Syphon) reinterpret its sRGB bytes.
    func makeDisplayTexture(width: Int, height: Int) -> MTLTexture? {
        let desc = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: pixelFormat, width: width, height: height, mipmapped: false)
        desc.usage = [.renderTarget, .shaderRead, .pixelFormatView]
        desc.storageMode = .private
        return device.makeTexture(descriptor: desc)
    }

    /// A render-pass descriptor that tone-maps the resolved float frame into
    /// `destination` (the drawable or a display texture). The present pass
    /// overwrites every pixel, so the load action doesn't matter.
    func presentPass(into destination: MTLTexture) -> MTLRenderPassDescriptor {
        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = destination
        pass.colorAttachments[0].loadAction = .dontCare
        pass.colorAttachments[0].storeAction = .store
        return pass
    }

    /// Encode the final tone-map pass: a fullscreen triangle sampling `source` (the
    /// resolved linear-float frame) with the drawer's exposure + tone-map mode,
    /// dithering and sRGB-encoding to the bound display attachment. Shared by every
    /// output path (on-screen drawable, export texture, Syphon/grab texture).
    /// - Parameter projected: whether this present is the one the audience sees
    ///   on a wall, and so carries the corner-pin warp and the edge fades the
    ///   run was calibrated with. Only the two paths that present into a
    ///   drawable pass true: an export, a frame grab, and a Syphon feed all
    ///   re-render the canvas itself, which has no wall to fit.
    /// - Parameter placement: the placement to fit through, for a display other
    ///   than the one being drawn in. Left out, the run's own is used, which is
    ///   the drawing display's.
    func encodePresent(from source: MTLTexture, drawer: Drawer,
                               into encoder: MTLRenderCommandEncoder,
                               projected: Bool = false,
                               placement: ProjectionPlacement? = nil) {
        let place = projected ? (placement ?? projection) : nil
        guard let state = try? pipeline(place == nil ? .present : .presentProjected) else { return }
        encoder.setRenderPipelineState(state)
        encoder.setFragmentTexture(source, index: 0)
        encoder.setFragmentSamplerState(imageSampler, index: 0)
        var present = OllinPresentUniforms(toneMapMode: drawer.toneMapMode.shaderIndex,
                                           exposure: Float(drawer.toneMapExposure),
                                           outputSpace: presentEncoding.rawValue,
                                           ceiling: max(1, presentCeiling),
                                           referenceNits: Float(ColorOutput.referenceWhiteNits),
                                           peakNits: Float(ColorOutput.peakNits))
        encoder.setFragmentBytes(&present, length: MemoryLayout<OllinPresentUniforms>.stride, index: 0)
        if var fit = place?.uniforms {
            encoder.setFragmentBytes(&fit, length: MemoryLayout<OllinProjectionUniforms>.stride, index: 1)
        }
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
    }
}

extension ProjectionPlacement {

    /// The placement in the form the projected present pass reads.
    var uniforms: OllinProjectionUniforms {
        OllinProjectionUniforms(
            fromOutput: homography.shaderInverse,
            sourceOrigin: SIMD2<Float>(Float(source.x), Float(source.y)),
            sourceSize: SIMD2<Float>(Float(source.width), Float(source.height)),
            fade: SIMD4<Float>(Float(fade.left), Float(fade.right),
                               Float(fade.top), Float(fade.bottom)),
            curve: Float(curve),
            gammaExponent: Float(gammaExponent))
    }
}
