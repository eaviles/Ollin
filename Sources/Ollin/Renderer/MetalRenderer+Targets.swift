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

    /// The shadow map: a square single-sample `.private` depth texture the shadow
    /// pass renders into and the lit mesh fragment samples. Allocated lazily on the
    /// first shadow-casting frame (a sketch that never casts shadows allocates none),
    /// then reused.
    private func ensureShadowMap() -> MTLTexture? {
        if let m = shadowMap { return m }
        let n = MetalRenderer.shadowMapResolution
        let desc = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: depthPixelFormat, width: n, height: n, mipmapped: false)
        desc.usage = [.renderTarget, .shaderRead]
        desc.storageMode = .private
        shadowMap = device.makeTexture(descriptor: desc)
        return shadowMap
    }

    /// A 1×1 depth texture bound to the mesh fragment's shadow slot when shadows are
    /// off, so its declared `depth2d` argument is always satisfied (the fragment only
    /// samples it when `shadowLight >= 0`). Cleared once on creation so it's never
    /// read uninitialized.
    func ensureDummyShadowMap() -> MTLTexture? {
        if let m = dummyShadowMap { return m }
        let desc = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: depthPixelFormat, width: 1, height: 1, mipmapped: false)
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
            cb.makeRenderCommandEncoder(descriptor: pass)?.endEncoding()
            cb.commit()
        }
        dummyShadowMap = texture
        return dummyShadowMap
    }

    /// The omnidirectional (point) shadow map, a `.private` **`rg32Float` cube** for
    /// mid-point shadow mapping: R holds the nearest occluder's distance to the light
    /// (normalized by the far plane), G the farthest, per direction. The lit fragment
    /// shadows where the receiver's distance exceeds the midpoint `(R+G)/2`. Allocated
    /// lazily on the first point-casting frame, then reused.
    static let pointShadowColorFormat: MTLPixelFormat = .rg32Float
    private func ensurePointShadowMap() -> MTLTexture? {
        if let m = pointShadowMap { return m }
        let n = MetalRenderer.pointShadowMapResolution
        let desc = MTLTextureDescriptor.textureCubeDescriptor(
            pixelFormat: MetalRenderer.pointShadowColorFormat, size: n, mipmapped: false)
        desc.usage = [.renderTarget, .shaderRead]
        desc.storageMode = .private
        pointShadowMap = device.makeTexture(descriptor: desc)
        return pointShadowMap
    }

    /// A 1×1 `rg32Float` cube bound to the mesh fragment's cube-shadow slot when no point
    /// caster is active, so its declared `texturecube` argument is always satisfied (the
    /// fragment only samples it when `shadowKind == 1`). Cleared to (1, 0) once on
    /// creation (all six faces in one layered pass) so it's never read uninitialized.
    func ensureDummyPointShadowMap() -> MTLTexture? {
        if let m = dummyPointShadowMap { return m }
        let desc = MTLTextureDescriptor.textureCubeDescriptor(
            pixelFormat: MetalRenderer.pointShadowColorFormat, size: 1, mipmapped: false)
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
            cb.makeRenderCommandEncoder(descriptor: pass)?.endEncoding()
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
                                  sdf3DGroupBuffer: MTLBuffer? = nil,
                                  sdf3DNodeBuffer: MTLBuffer? = nil) -> ShadowMaps {
        let lighting = drawer.makeLighting()
        let meshVertices = drawer.meshVertices
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
        guard lighting.enabled != 0, !meshVertices.isEmpty, let meshBuffer,
              lighting.shadowLight >= 0 || wantReflect || wantGI else { return ShadowMaps() }

        meshVertices.withUnsafeBytes { raw in
            meshBuffer.contents().copyMemory(from: raw.baseAddress!, byteCount: raw.count)
        }

        // A point caster: ray-trace it on a capable device (exact, no cube/depth-compare
        // artifacts), else render the omnidirectional mid-point cube. The one accel serves
        // both the shadow (shadowKind 2) and, when on, reflections.
        if lighting.shadowLight >= 0, lighting.shadowKind == 1 {
            if rayTracedShadows,
               let built = buildShadowAccel(drawer, into: commandBuffer, meshBuffer: meshBuffer) {
                return ShadowMaps(accel: built.accel,
                                  reflectAccel: wantReflect ? built.accel : nil,
                                  reflectGeoOffsets: wantReflect ? built.offsets : nil,
                                  giAccel: wantGI ? built.accel : nil,
                                  giGeoOffsets: wantGI ? built.offsets : nil)
            }
            let cube = encodePointShadowPass(drawer, lighting: lighting,
                                             into: commandBuffer, meshBuffer: meshBuffer)
            return ShadowMaps(cube: cube)
        }

        // An area (rect/disk) caster on a ray-tracing device: trace visibility to the
        // panel's actual surface instead of rendering the spot-style map (the exact
        // penumbra, including a rect's anisotropy). Elsewhere it falls through to the
        // 2D map below, whose PCSS penumbra the packing already sized from the panel's
        // extent, so both devices soften by the same physical size.
        if lighting.shadowLight >= 0, casterGPUKind(lighting) >= 3, rayTracedShadows,
           let built = buildShadowAccel(drawer, into: commandBuffer, meshBuffer: meshBuffer) {
            return ShadowMaps(accel: built.accel,
                              reflectAccel: wantReflect ? built.accel : nil,
                              reflectGeoOffsets: wantReflect ? built.offsets : nil,
                              giAccel: wantGI ? built.accel : nil,
                              giGeoOffsets: wantGI ? built.offsets : nil)
        }

        // Reflections and/or GI with no shadow-casting light: build only the accel.
        if lighting.shadowLight < 0 {
            guard let built = buildShadowAccel(drawer, into: commandBuffer, meshBuffer: meshBuffer)
            else { return ShadowMaps() }
            return ShadowMaps(reflectAccel: wantReflect ? built.accel : nil,
                              reflectGeoOffsets: wantReflect ? built.offsets : nil,
                              giAccel: wantGI ? built.accel : nil,
                              giGeoOffsets: wantGI ? built.offsets : nil)
        }

        // A directional/spot caster's 2D map below, plus a reflection/GI accel when either
        // is on (both precede the main geometry pass, so trace order is satisfied either way).
        let reflect = (wantReflect || wantGI)
            ? buildShadowAccel(drawer, into: commandBuffer, meshBuffer: meshBuffer) : nil
        guard let shadowMap = ensureShadowMap(),
              let shadowPipeline = try? pipeline(.meshShadow) else {
            return ShadowMaps(reflectAccel: wantReflect ? reflect?.accel : nil,
                              reflectGeoOffsets: wantReflect ? reflect?.offsets : nil,
                              giAccel: wantGI ? reflect?.accel : nil,
                              giGeoOffsets: wantGI ? reflect?.offsets : nil)
        }
        let pass = MTLRenderPassDescriptor()
        pass.depthAttachment.texture = shadowMap
        pass.depthAttachment.loadAction = .clear
        pass.depthAttachment.clearDepth = 1.0
        pass.depthAttachment.storeAction = .store
        guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: pass) else { return ShadowMaps() }
        encoder.setRenderPipelineState(shadowPipeline)
        encoder.setDepthStencilState(depthTestState)
        // Slope-scaled depth bias on the stored depth keeps self-shadowing acne off
        // (paired with the fragment's normal-offset + constant bias).
        encoder.setDepthBias(0.0015, slopeScale: 2.0, clamp: 0.01)
        var lightVP = lighting.lightViewProjection
        encoder.setVertexBytes(&lightVP, length: MemoryLayout<simd_float4x4>.stride, index: 2)
        drawShadowCasters(drawer, encoder: encoder, meshBuffer: meshBuffer, instanceCount: 1)
        // Marched 3D fields cast into the same map: sphere-trace each from the light's POV and
        // write its depth, z-tested against the mesh casters already there, so meshes receive a
        // field's shadow too. The field keeps its analytic self-shadow in the main pass and
        // doesn't sample this map, so there's no double-shadowing (directional/spot only).
        encodeFieldShadowCasters(drawer, encoder: encoder, lighting: lighting,
                                 groupBuffer: sdf3DGroupBuffer, nodeBuffer: sdf3DNodeBuffer)
        encoder.endEncoding()
        return ShadowMaps(twoD: shadowMap,
                          reflectAccel: wantReflect ? reflect?.accel : nil,
                          reflectGeoOffsets: wantReflect ? reflect?.offsets : nil,
                          giAccel: wantGI ? reflect?.accel : nil,
                          giGeoOffsets: wantGI ? reflect?.offsets : nil)
    }

    /// Render the marched 3D fields into the active 2D shadow map (directional/spot). Each field
    /// is one instanced fullscreen triangle whose fragment sphere-traces it from the light's
    /// point of view and writes the hit's light-clip depth (depth-only, z-tested against the
    /// mesh casters already in the map). A no-op when the frame has no fields or no buffers.
    private func encodeFieldShadowCasters(_ drawer: Drawer, encoder: MTLRenderCommandEncoder,
                                          lighting: OllinLighting,
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
            lightViewProjection: lighting.lightViewProjection,
            inverseLightViewProjection: simd_inverse(lighting.lightViewProjection),
            raymarchSteps: Float(casterSteps))
        encoder.setRenderPipelineState(fieldPipeline)
        encoder.setFragmentBuffer(groupBuffer, offset: 0, index: 0)
        encoder.setFragmentBuffer(nodeBuffer, offset: 0, index: 1)
        encoder.setFragmentBytes(&u, length: MemoryLayout<OllinRaymarchShadowUniforms>.stride, index: 2)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3,
                               instanceCount: groups3D.count)
    }

    /// The omnidirectional (point) shadow pass: render the scene into all six cube faces
    /// in **one** layered pass (the geometry instanced six times, each instance routed to
    /// a face by `render_target_array_index`). The fragment writes each occluder's linear
    /// distance to the light (normalized by the far plane) as the stored value, so the
    /// lit mesh fragment later compares plain world-space distances. The light position
    /// and far plane come from the lighting uniform. Returns the populated cube.
    private func encodePointShadowPass(_ drawer: Drawer, lighting: OllinLighting,
                                       into commandBuffer: MTLCommandBuffer,
                                       meshBuffer: MTLBuffer) -> MTLTexture? {
        guard let cube = ensurePointShadowMap(),
              let minPipeline = try? pipeline(.meshPointShadowMin),
              let maxPipeline = try? pipeline(.meshPointShadowMax) else { return nil }

        // The casting light's world position from the uniform's fixed-size light array.
        let caster = Int(lighting.shadowLight)
        var lightPos = SIMD3<Float>(0, 0, 0)
        withUnsafePointer(to: lighting.lights) { ptr in
            ptr.withMemoryRebound(to: OllinLight.self, capacity: Int(OLLIN_MAX_LIGHTS)) { buf in
                let p = buf[caster].position
                lightPos = SIMD3<Float>(p.x, p.y, p.z)
            }
        }
        // The far plane is carried directly (`shadowDepthA`); the fragment normalizes the
        // stored linear distance by it. The face perspective near/far only frame the
        // rasterization (the stored value is the fragment's own linear distance), so a
        // small near and that far suffice.
        let far = lighting.shadowDepthA
        let near = max(Float(0.05), far * 0.02)
        let proj = Camera3D.perspective(fovY: .pi / 2, aspect: 1, near: near, far: far)
        // The six cube faces (forward axis, up), in Metal's +X/−X/+Y/−Y/+Z/−Z order.
        let faces: [(SIMD3<Float>, SIMD3<Float>)] = [
            (SIMD3(1,  0,  0), SIMD3(0, -1,  0)),
            (SIMD3(-1,  0,  0), SIMD3(0, -1,  0)),
            (SIMD3(0,  1,  0), SIMD3(0,  0,  1)),
            (SIMD3(0, -1,  0), SIMD3(0,  0, -1)),
            (SIMD3(0,  0,  1), SIMD3(0, -1,  0)),
            (SIMD3(0,  0, -1), SIMD3(0, -1,  0)),
        ]
        let faceVP = faces.map { proj * Camera3D.lookAt(eye: lightPos, center: lightPos + $0.0, up: $0.1) }

        // Mid-point shadow mapping: clear R = 1 (far, for the MIN pass) and G = 0 (near,
        // for the MAX pass), then make two draws of the scene with NO culling — the MIN
        // pass fills R with the nearest occluder distance per direction, the MAX pass
        // fills G with the farthest. The receiver shadows past the midpoint (R+G)/2, so a
        // surface compares against a point *inside* the occluder: no self-shadow acne on
        // edge-on faces, and no contact leak, without any face culling.
        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = cube
        pass.colorAttachments[0].loadAction = .clear
        pass.colorAttachments[0].clearColor = MTLClearColor(red: 1, green: 0, blue: 0, alpha: 0)
        pass.colorAttachments[0].storeAction = .store
        pass.renderTargetArrayLength = 6
        guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: pass) else { return nil }
        faceVP.withUnsafeBytes { encoder.setVertexBytes($0.baseAddress!, length: $0.count, index: 2) }
        var lightPosFar = SIMD4<Float>(lightPos.x, lightPos.y, lightPos.z, far)
        encoder.setFragmentBytes(&lightPosFar, length: MemoryLayout<SIMD4<Float>>.stride, index: 0)
        encoder.setRenderPipelineState(minPipeline)   // nearest -> R
        drawShadowCasters(drawer, encoder: encoder, meshBuffer: meshBuffer, instanceCount: 6)
        encoder.setRenderPipelineState(maxPipeline)   // farthest -> G
        drawShadowCasters(drawer, encoder: encoder, meshBuffer: meshBuffer, instanceCount: 6)
        encoder.endEncoding()
        return cube
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

    /// Resolve a `.ambientOcclusion` quality tier to a gather sample count. Fewer samples
    /// than the bokeh gather (each reconstructs a view-space position and accumulates a
    /// scalar, not a colour), distributed over the same smooth golden-angle spiral so the
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
    func makeRaymarchUniforms3D(_ drawer: Drawer, viewport: SIMD2<Float>) -> Uniforms3D? {
        guard let camera = drawer.camera3D else { return nil }
        let aspect = viewport.y > 0 ? Double(viewport.x / viewport.y) : 1
        let proj = camera.projectionMatrix(aspect: aspect)
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
        if shadowAccelPresent {
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
        guard let enc = cb.makeRenderCommandEncoder(descriptor: pass) else { return nil }
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
            enc.useResource(accel, usage: .read, stages: .fragment)
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
    /// (0 for a mesh-only or directional/spot scene, the byte-identical mesh path). Shared by the
    /// main encode and the half-res field-shadow pre-pass so both agree on whether the cast is on.
    func resolveFieldCasterCount(_ lighting: OllinLighting, _ drawer: Drawer) -> Int32 {
        (lighting.shadowLight >= 0 && lighting.shadowKind != 0 && !drawer.sdf3DGroups.isEmpty)
            ? Int32(drawer.sdf3DGroups.count) : 0
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
    func makeUniforms3D(_ drawer: Drawer, camera: Camera3D, viewport: SIMD2<Float>) -> Uniforms3D {
        let aspect = viewport.y > 0 ? Double(viewport.x / viewport.y) : 1
        let proj = camera.projectionMatrix(aspect: aspect)
        let steps = resolveRaymarchSteps(drawer.raymarchQualitySetting)
        return Uniforms3D(view: camera.viewMatrix, projection: proj,
                          inverseViewProjection: simd_inverse(proj * camera.viewMatrix),
                          viewport: viewport,
                          raymarchSteps: SIMD2<Float>(Float(steps.march), Float(steps.shadow)),
                          raymarchScale: SIMD2<Float>(1, 0))
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
        guard let enc = cb.makeRenderCommandEncoder(descriptor: pass) else { return nil }
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

    /// A multisample `linearFormat` colour target that is *also* shader-readable (per-sample,
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
                                      supersample: Bool, pooled: Bool) -> MTLTexture? {
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
        guard let enc = cb.makeRenderCommandEncoder(descriptor: pass) else { return nil }
        enc.setViewport(MTLViewport(originX: 0, originY: 0, width: Double(width),
                                    height: Double(height), znear: 0, zfar: 1))
        enc.setRenderPipelineState(gbufPipe)
        enc.setDepthStencilState(depthTestState)
        var u3 = makeUniforms3D(drawer, camera: camera, viewport: SIMD2(Float(width), Float(height)))
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
        guard let trace = cb.makeRenderCommandEncoder(descriptor: tracePass) else { return nil }
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
        trace.setFragmentSamplerState(imageSampler, index: 0)
        var traceParams = SIMD4<Float>(1 / Float(width), 1 / Float(height), Float(samples), seed)
        trace.setFragmentBytes(&traceParams, length: MemoryLayout<SIMD4<Float>>.stride, index: 0)
        trace.setFragmentBytes(&lighting, length: MemoryLayout<OllinLighting>.stride, index: 1)
        trace.setFragmentBytes(&u3, length: MemoryLayout<Uniforms3D>.stride, index: 2)
        trace.useResource(accel, usage: .read, stages: .fragment)
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
        let invVP = u3.inverseViewProjection
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

    /// Fixed probe grid resolution (v1): 8 per axis, 512 probes. The volume auto-fits
    /// the frame's caster geometry, so density adapts through spacing, not count.
    private static let giProbesPerAxis = 8
    /// Probe tiles per atlas row. The blend/sample shaders re-derive it from the atlas
    /// width (width / tile), so the layout constant lives only here.
    private static let giTilesPerRow = 32

    /// The frame's mesh-geometry world bounds, folded over the same caster batches the
    /// acceleration structure is built from, so the probe volume covers exactly what
    /// the probe rays can hit. Nil when the frame has no eligible mesh.
    private func giSceneBounds(_ drawer: Drawer) -> (lo: SIMD3<Float>, hi: SIMD3<Float>)? {
        var lo = SIMD3<Float>(repeating: .greatestFiniteMagnitude)
        var hi = SIMD3<Float>(repeating: -.greatestFiniteMagnitude)
        var found = false
        let batches = drawer.batches
        let count = drawer.meshVertices.count
        drawer.meshVertices.withUnsafeBufferPointer { verts in
            for i in batches.indices {
                let batch = batches[i]
                guard batch.kind == .mesh3D, batch.target == nil,
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

    /// Rays per probe per update, resolved through the automatic tier and scaled to the
    /// GPU like the shadow rays (software ray tracing pays several times more per ray).
    private func resolveGIRays() -> Int {
        switch effectiveQuality(.default) {
        case .performance: return hasHardwareRayTracing ? 64 : 32
        case .default:     return hasHardwareRayTracing ? 96 : 64
        case .detail:      return hasHardwareRayTracing ? 192 : 96
        }
    }

    /// Whole trace+blend iterations for the historyless (headless/export) path: each
    /// deepens the bounce recursion by one and averages the noise down (the blend runs
    /// a progressive mean), so a single frame converges deterministically with no
    /// history, and a video export cannot flicker.
    private func resolveGIIterations() -> Int {
        switch effectiveQuality(.default) {
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
    }

    /// One blend pass: fold the traced surfels into an atlas's back texture against its
    /// front (the previous update), whole-atlas (gutter texels recompute their wrapped
    /// interior source in-shader, so no separate border pass).
    private func encodeGIBlend(_ pipe: MTLRenderPipelineState, surfels: MTLTexture,
                               previous: MTLTexture, output: MTLTexture,
                               params: [SIMD4<Float>], into cb: MTLCommandBuffer) {
        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = output
        pass.colorAttachments[0].loadAction = .dontCare
        pass.colorAttachments[0].storeAction = .store
        guard let enc = cb.makeRenderCommandEncoder(descriptor: pass) else { return }
        enc.setRenderPipelineState(pipe)
        params.withUnsafeBytes { raw in
            enc.setFragmentBytes(raw.baseAddress!, length: raw.count, index: 0)
        }
        enc.setFragmentTexture(surfels, index: 0)
        enc.setFragmentTexture(previous, index: 1)
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
                              biasScale: giBiasScale(s.spacing))
        }

        guard let bounds = giSceneBounds(drawer) else { return nil }
        let n = Self.giProbesPerAxis
        let counts = SIMD3<Int32>(repeating: Int32(n))
        let probeCount = n * n * n
        let state: GIProbeState
        if let existing = giState {
            state = existing
        } else {
            let perRow = Self.giTilesPerRow
            let rows = (probeCount + perRow - 1) / perRow
            guard let iA = makeFloatResolve(width: perRow * 10, height: rows * 10),
                  let iB = makeFloatResolve(width: perRow * 10, height: rows * 10),
                  let dA = makeFloatResolve(width: perRow * 18, height: rows * 18),
                  let dB = makeFloatResolve(width: perRow * 18, height: rows * 18),
                  let oA = makeFloatResolve(width: probeCount, height: 1),
                  let oB = makeFloatResolve(width: probeCount, height: 1)
            else { return nil }
            state = GIProbeState(irrA: iA, irrB: iB, depA: dA, depB: dB, offA: oA, offB: oB)
            giState = state
        }
        // Headless: a pure function of this frame, so never inherit a live volume
        // or its half-converged field.
        if supersample { state.valid = false }
        var needFit = !state.valid
        if !needFit {
            let gridMax = state.origin + state.spacing * Float(n - 1)
            if bounds.lo.x < state.origin.x || bounds.lo.y < state.origin.y
                || bounds.lo.z < state.origin.z || bounds.hi.x > gridMax.x
                || bounds.hi.y > gridMax.y || bounds.hi.z > gridMax.z {
                needFit = true
            } else {
                let heldExt = gridMax - state.origin
                let rawExt = simd_max(bounds.hi - bounds.lo, SIMD3<Float>(repeating: 1e-6))
                let heldVol = heldExt.x * heldExt.y * heldExt.z
                let targetVol = rawExt.x * rawExt.y * rawExt.z * (1.3 * 1.3 * 1.3)
                if heldVol > targetVol * 6 { needFit = true }
            }
        }
        if needFit {
            var ext = bounds.hi - bounds.lo
            // Floor degenerate axes (a flat ground plane) so spacing never collapses.
            let maxExt = max(max(ext.x, ext.y), max(ext.z, 0.001))
            ext = simd_max(ext, SIMD3<Float>(repeating: maxExt * 0.05))
            let center = (bounds.hi + bounds.lo) * 0.5
            ext *= 1.3   // 15% pad each side: boundary surfaces sit inside the outer cage
            state.origin = center - ext * 0.5
            state.spacing = ext / Float(n - 1)
            state.counts = counts
            state.valid = false
            // Relocation offsets belong to a grid; a new grid starts from zero.
            let clear = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)
            clearFloatTexture(state.offA, color: clear, into: cb)
            clearFloatTexture(state.offB, color: clear, into: cb)
        }

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
                          biasScale: giBiasScale(state.spacing)),
               into: &lighting, intensity: 1)

        let farCap = 2 * simd_length(state.spacing * Float(n - 1))
        // The visibility moments cap at cage scale (1.5x the largest axial spacing, the
        // reference's rule): the Chebyshev test only ever asks about a probe's own cage,
        // and far geometry in the statistics collapses near-surface variance.
        let depthCap = 1.5 * max(state.spacing.x, max(state.spacing.y, state.spacing.z))
        let rays = resolveGIRays()
        let iterations = supersample ? resolveGIIterations() : 1
        guard let tracePipe = try? pipeline(.effect("ollin_gi_trace")),
              let blendIrrPipe = try? pipeline(.effect("ollin_gi_blend_irradiance")),
              let blendDepPipe = try? pipeline(.effect("ollin_gi_blend_depth")),
              let relocatePipe = try? pipeline(.effect("ollin_gi_relocate")),
              let surfels = acquireFilterTexture(width: rays, height: probeCount, pooled: pooled)
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
            guard let trace = cb.makeRenderCommandEncoder(descriptor: tracePass) else { return nil }
            trace.setRenderPipelineState(tracePipe)
            let traceParams = [SIMD4<Float>(Float(rays), seed, farCap, Float(probeCount)),
                               SIMD4<Float>(prevValid, farCap, 0, 0)]
            traceParams.withUnsafeBytes { raw in
                trace.setFragmentBytes(raw.baseAddress!, length: raw.count, index: 0)
            }
            trace.setFragmentBytes(&lighting, length: MemoryLayout<OllinLighting>.stride, index: 1)
            trace.useResource(accel, usage: .read, stages: .fragment)
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

            let blendParams = [SIMD4<Float>(Float(rays), seed, hysteresis, Float(probeCount)),
                               SIMD4<Float>(prevValid, depthCap, 0, 0)]
            encodeGIBlend(blendIrrPipe, surfels: surfels, previous: state.irrFront,
                          output: state.irrBack, params: blendParams, into: cb)
            encodeGIBlend(blendDepPipe, surfels: surfels, previous: state.depFront,
                          output: state.depBack, params: blendParams, into: cb)
            // Relocation: walk embedded probes out through this update's surfel
            // statistics (the next trace starts from the moved positions).
            let relocateParams = [SIMD4<Float>(Float(rays), seed, Float(probeCount), farCap),
                                  SIMD4<Float>(state.spacing, 0)]
            encodeGIBlend(relocatePipe, surfels: surfels, previous: state.offFront,
                          output: state.offBack, params: relocateParams, into: cb)
            state.flipped.toggle()   // the just-written backs are the next fronts
            state.valid = true
        }
        return GIResolved(irradiance: state.irrFront, depth: state.depFront,
                          offsets: state.lastTraceOffsets ?? state.offFront,
                          origin: state.origin, spacing: state.spacing, counts: counts,
                          biasScale: giBiasScale(state.spacing))
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
        guard let enc = cb.makeRenderCommandEncoder(descriptor: pass) else { return nil }
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
    private func buildShadowAccel(_ drawer: Drawer, into commandBuffer: MTLCommandBuffer,
                                  meshBuffer: MTLBuffer)
        -> (accel: MTLAccelerationStructure, offsets: MTLBuffer)? {
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
        var runStart = -1, runEnd = 0
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
            runStart = -1
        }
        for i in batches.indices {
            let batch = batches[i]
            // Exclude the ground-grid chrome like `drawShadowCasters` does: its huge
            // opaque y=0 quad would otherwise occlude every downward reflection ray
            // (and RT shadow ray) whenever the live grid toggle is on.
            let isCaster = batch.kind == .mesh3D && !batch.meshWireframe && !batch.meshGrid
            let end = i + 1 < batches.count ? batches[i + 1].meshStart : meshVertices.count
            if isCaster {
                if runStart < 0 { runStart = batch.meshStart }
                runEnd = end
            } else {
                flushRun()
            }
        }
        flushRun()
        guard !geometries.isEmpty else { return nil }

        // A plain (non-refittable) build: a refittable structure trades traversal speed for
        // the cheaper refit, and on a software-ray-tracing GPU (no RT hardware, e.g. M1/M2)
        // the per-ray traversal — millions of rays — dwarfs the per-frame build, so the
        // faster-to-traverse tree wins. Rebuild each frame; grow the structure in place only
        // when the scene outgrows it.
        let desc = MTLPrimitiveAccelerationStructureDescriptor()
        desc.geometryDescriptors = geometries
        let sizes = device.accelerationStructureSizes(descriptor: desc)
        if shadowAccel == nil || shadowAccelCapacity < sizes.accelerationStructureSize {
            shadowAccel = device.makeAccelerationStructure(size: sizes.accelerationStructureSize)
            shadowAccelCapacity = sizes.accelerationStructureSize
        }
        if (shadowAccelScratch?.length ?? 0) < sizes.buildScratchBufferSize {
            shadowAccelScratch = device.makeBuffer(length: max(1, sizes.buildScratchBufferSize),
                                                   options: .storageModePrivate)
        }
        guard let accel = shadowAccel, let scratch = shadowAccelScratch,
              let enc = commandBuffer.makeAccelerationStructureCommandEncoder() else { return nil }
        enc.build(accelerationStructure: accel, descriptor: desc,
                  scratchBuffer: scratch, scratchBufferOffset: 0)
        enc.endEncoding()
        // The per-geometry base-vertex offsets, uploaded for the reflection hit fetch. Filled
        // CPU-side here (before the command buffer commits), so the main pass reads them this
        // frame, through the frame ring, never a shared buffer an in-flight frame still reads.
        let offsetsLength = max(MemoryLayout<UInt32>.stride, geoOffsets.count * MemoryLayout<UInt32>.stride)
        if (meshGeoOffsetBuffers[frameIndex]?.length ?? 0) < offsetsLength {
            meshGeoOffsetBuffers[frameIndex] = device.makeBuffer(length: offsetsLength, options: .storageModeShared)
        }
        guard let offsetsBuffer = meshGeoOffsetBuffers[frameIndex] else { return nil }
        geoOffsets.withUnsafeBytes { raw in
            offsetsBuffer.contents().copyMemory(from: raw.baseAddress!, byteCount: raw.count)
        }
        return (accel, offsetsBuffer)
    }

    /// A 1-triangle acceleration structure bound to the lit mesh fragment whenever no
    /// ray-traced point shadow is active this frame, so the fragment's declared
    /// `primitive_acceleration_structure` argument is always satisfied (it only traces
    /// when `shadowKind == 2`). Built once, far from any scene so it never matters.
    func ensureDummyShadowAccel() -> MTLAccelerationStructure? {
        if let a = dummyShadowAccel { return a }
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
        guard let accel = device.makeAccelerationStructure(size: sizes.accelerationStructureSize),
              let scratch = device.makeBuffer(length: max(1, sizes.buildScratchBufferSize),
                                              options: .storageModePrivate),
              let cb = commandQueue.makeCommandBuffer(),
              let enc = cb.makeAccelerationStructureCommandEncoder() else { return nil }
        enc.build(accelerationStructure: accel, descriptor: desc,
                  scratchBuffer: scratch, scratchBufferOffset: 0)
        enc.endEncoding(); cb.commit(); cb.waitUntilCompleted()
        dummyShadowAccel = accel
        return dummyShadowAccel
    }

    /// A 1-element per-geometry-offset buffer bound at fragment buffer 7 whenever ray-traced
    /// reflections aren't producing real offsets this frame, so the RT-compiled mesh
    /// fragment's declared offsets argument is always satisfied (it's read only on a
    /// reflection hit, which can't happen when `lighting.rtReflections == 0`).
    func ensureDummyGeoOffsets() -> MTLBuffer? {
        if let b = dummyGeoOffsets { return b }
        var zero: UInt32 = 0
        dummyGeoOffsets = device.makeBuffer(bytes: &zero, length: MemoryLayout<UInt32>.stride,
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
    func encodePresent(from source: MTLTexture, drawer: Drawer,
                               into encoder: MTLRenderCommandEncoder) {
        guard let state = try? pipeline(.present) else { return }
        encoder.setRenderPipelineState(state)
        encoder.setFragmentTexture(source, index: 0)
        encoder.setFragmentSamplerState(imageSampler, index: 0)
        var present = OllinPresentUniforms(toneMapMode: drawer.toneMapMode.shaderIndex,
                                           exposure: Float(drawer.toneMapExposure))
        encoder.setFragmentBytes(&present, length: MemoryLayout<OllinPresentUniforms>.stride, index: 0)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
    }
}
