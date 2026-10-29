import Metal
import simd
import COllinShaders

// Volumes (`drawVolume`): density grids composited over a pass's finished
// geometry. The march (ShaderVolume.metal) needs the depth of every solid in
// the frame, and the geometry pass cannot read its own depth attachment, so a
// volume is not a batch in the call-ordered list: it draws after the pass ends,
// over the pass's resolved color, reading the resolved depth. That is also the
// order a translucent medium wants: a solid drawn after the volume in code still
// sits inside it, veiled by what lies in front of it.
//
// What a volume needs from the GPU is resolved in two steps. `prepareVolumes`
// runs ahead of the frame's first geometry pass, right after the sketch's own
// compute dispatches (so a grid a kernel writes this frame is already written):
// it realizes each grid and computes its light-transmittance grid toward each
// lit light. The geometry passes read those grids for the cloud's shadow on
// their solids (`volumeShadowTable`), and the composite after each pass
// (`encodeVolumes`) reads them for the cloud's own shading.

/// What the geometry pass resolved for the volumes that follow it: the lighting
/// every light set shades against, the shadow map it was rendered with, and the
/// camera (with the pass's own sub-pixel jitter), so the march lines up with
/// the depth it reads and lights exactly as the solids did.
struct VolumePassLight {
    var lighting: [Int: OllinLighting]
    var shadowMap: MTLTexture?
    var uniforms3D: Uniforms3D
}

/// A light-transmittance grid's identity: the samples (a grid's buffer, or a
/// kernel-written texture at its write count), where they sit, the medium's
/// thickness, and the light. A change to any of them is a new grid (computed
/// into another texture, never over one a frame in flight may read).
struct VolumeLightKey: Hashable {
    var content: UInt64
    var generation: UInt64
    var model: [Float]
    var density: Float
    var lightRay: SIMD4<Float>
}

/// Which blocks of a volume source's samples hold any medium, at two block
/// sizes (`ollin_volume_occupancy_kernel`): the march reads it where its
/// sample comes back zero and steps past the rest of an empty block, which on
/// a plume filling a third of its box is most of the steps it would take. A
/// block counts the samples a read inside it can reach, so a skipped step is
/// one that would have read zero, and the march leaves the bytes a march
/// through every step leaves.
struct VolumeOccupancy {
    var fine: MTLTexture
    var coarse: MTLTexture
    /// The span of fine blocks that hold anything, as the occupancy kernel
    /// folds it (six `UInt32`s: the lowest block per axis, then the
    /// complement of the highest).
    var bounds: MTLBuffer
    /// The samples' generation it was worked out for (`VolumeSource.contentGeneration`).
    var generation: UInt64
    /// The frame it last served, as `volumeLightCache` counts them.
    var used: UInt64
}

/// One `drawVolume` with its GPU resources resolved for the frame: the grid,
/// the transmittance grid toward each of the first lit lights, and the draw
/// record the composite fills its phase into.
struct PreparedVolume {
    /// Its position in `drawer.volumeDraws` (the tie-break of the composite's sort).
    var index: Int
    var draw: OllinVolumeDraw
    var grid: MTLTexture
    /// The transmittance grid per lit slot (`OLLIN_VOLUME_MAX_LIT`).
    var lit: [MTLTexture?]
    /// The light-list index each lit slot serves, -1 for none.
    var litIndices: SIMD4<Float>
    var target: RenderTarget?
    var lightSet: Int
    /// The grid's fine and coarse occupancy, or nil when there is none (the
    /// march then reads the stand-in and skips nothing).
    var occupancy: (fine: MTLTexture, coarse: MTLTexture, bounds: MTLBuffer)?
}

extension MetalRenderer {
    /// The step budget per view ray: enough for a 128-sample grid crossed
    /// corner to corner at two steps a sample, with room to spare.
    static let volumeMaxSteps: Float = 768
    /// The finest light-transmittance grid per axis; a finer density grid is
    /// read at this resolution for its self-shadow (a shadow is smoother than
    /// the medium casting it).
    static let volumeLightMaxSamples = 128

    /// The table of volumes casting a shadow onto one pass's solids, as the lit
    /// mesh fragments read it at buffer 11, with the textures it names (for
    /// residency) and the buffer that holds it.
    struct VolumeShadowTable {
        var entries: [OllinVolumeShadow] = []
        var textures: [MTLTexture] = []
        var buffer: MTLBuffer?
    }

    /// Resolve every volume drawn this frame ahead of its first geometry pass:
    /// realize each grid, and compute (or find cached) its light-transmittance
    /// grid toward each of the first `OLLIN_VOLUME_MAX_LIT` lit lights, in a
    /// compute pass on `cb`. Called right after the sketch's compute dispatches,
    /// so a grid a kernel wrote this frame is read as written. The grids are
    /// computed when the medium has a thickness and the lights are on: for the
    /// medium's own shading when it scatters, and for its shadow on the solids
    /// whenever the frame casts shadows; a medium with no thickness, and a frame
    /// with no lights, computes none (and casts nothing).
    func prepareVolumes(_ drawer: Drawer, into cb: MTLCommandBuffer) {
        preparedVolumes.removeAll(keepingCapacity: true)
        guard !drawer.volumeDraws.isEmpty else { return }
        drawerVolumetricQuality = drawer.volumetricQualitySetting
        volumeLightGeneration &+= 1
        var lightings: [Int: OllinLighting] = [:]
        var pending: [(texture: MTLTexture, grid: MTLTexture, draw: OllinVolumeDraw, ray: SIMD4<Float>)] = []
        var occupancyJobs: [(grid: MTLTexture, occupancy: VolumeOccupancy)] = []
        for (index, item) in drawer.volumeDraws.enumerated() {
            guard let grid = item.source.texture(for: device) else { continue }
            let occupancy = volumeOccupancy(for: item.source, grid: grid, jobs: &occupancyJobs)
            let lighting: OllinLighting
            if let known = lightings[item.lightSet] {
                lighting = known
            } else {
                lighting = drawer.makeLighting(set: item.lightSet)
                lightings[item.lightSet] = lighting
            }
            var gpu = makeVolumeDraw(item, phase: 0)
            var lit: [MTLTexture?] = []
            var litIndices = SIMD4<Float>(repeating: -1)
            let wantsGrids = gpu.medium.x > 0 && lighting.enabled != 0
                && (gpu.scatter.w > 0 || drawer.castsShadows)
            if wantsGrids {
                let count = min(Int(lighting.lightCount), Int(OLLIN_MAX_LIGHTS))
                for lightIndex in 0 ..< count where lit.count < Int(OLLIN_VOLUME_MAX_LIT) {
                    let light = lightAt(lighting, lightIndex)
                    let ray: SIMD4<Float>
                    switch light.kind {
                    case 0: ray = SIMD4(light.direction.x, light.direction.y, light.direction.z, 0)
                    case 1, 2: ray = SIMD4(light.position.x, light.position.y, light.position.z, 1)
                    default: continue
                    }
                    let lightKey = VolumeLightKey(content: item.source.contentID,
                                                  generation: item.source.contentGeneration,
                                                  model: item.model.flatArray,
                                                  density: gpu.medium.x, lightRay: ray)
                    if let cached = volumeLightCache[lightKey] {
                        volumeLightCache[lightKey]?.used = volumeLightGeneration
                        lit.append(cached.texture)
                    } else if let texture = makeVolumeLightTexture(for: item.source) {
                        volumeLightCache[lightKey] = (texture, volumeLightGeneration)
                        pending.append((texture, grid, gpu, ray))
                        lit.append(texture)
                    } else {
                        continue
                    }
                    litIndices[lit.count - 1] = Float(lightIndex)
                }
            }
            gpu.litLights = litIndices
            preparedVolumes.append(PreparedVolume(index: index, draw: gpu, grid: grid, lit: lit,
                                                  litIndices: litIndices, target: item.target,
                                                  lightSet: item.lightSet,
                                                  occupancy: occupancy.map { ($0.fine, $0.coarse, $0.bounds) }))
        }
        // A transmittance grid no volume has asked for in a few frames goes to
        // the pool, where a grid of its size is taken from before a new texture
        // is made: a kernel-written cloud asks for a fresh grid every frame, and
        // this keeps that from being an allocation every frame. Eight frames
        // unused is past any frame still in flight, so a pooled texture is never
        // one the GPU is still reading.
        for (key, entry) in volumeLightCache where volumeLightGeneration &- entry.used >= 8 {
            volumeLightCache[key] = nil
            if volumeLightPool.count < 8 { volumeLightPool.append(entry.texture) }
        }
        for (key, entry) in volumeOccupancyCache where volumeLightGeneration &- entry.used >= 8 {
            volumeOccupancyCache[key] = nil
        }
        guard !pending.isEmpty || !occupancyJobs.isEmpty,
              let encoder = cb.makeComputeCommandEncoder() else { return }
        encoder.label = "Ollin volume light"
        // The occupancy first: the tight box reset, the fine blocks (which
        // fold the tight box too), then the coarse ones. Dispatches on one
        // encoder run in order, each seeing what the one before it wrote.
        if !occupancyJobs.isEmpty,
           let resetKernel = try? libraryComputePipeline("ollin_volume_bounds_reset_kernel"),
           let fineKernel = try? libraryComputePipeline("ollin_volume_occupancy_kernel"),
           let coarseKernel = try? libraryComputePipeline("ollin_volume_coarse_occupancy_kernel") {
            encoder.setComputePipelineState(resetKernel)
            for job in occupancyJobs {
                encoder.setBuffer(job.occupancy.bounds, offset: 0, index: 0)
                encoder.dispatchThreads(MTLSize(width: 6, height: 1, depth: 1),
                                        threadsPerThreadgroup: MTLSize(width: 6, height: 1, depth: 1))
            }
            for (pass, kernel) in [fineKernel, coarseKernel].enumerated() {
                encoder.setComputePipelineState(kernel)
                for job in occupancyJobs {
                    let out = pass == 0 ? job.occupancy.fine : job.occupancy.coarse
                    encoder.setTexture(out, index: 0)
                    encoder.setTexture(pass == 0 ? job.grid : job.occupancy.fine, index: 1)
                    encoder.setBuffer(job.occupancy.bounds, offset: 0, index: 0)
                    encoder.dispatchThreads(MTLSize(width: out.width, height: out.height, depth: out.depth),
                                            threadsPerThreadgroup: MTLSize(width: 4, height: 4, depth: 4))
                }
            }
        }
        guard !pending.isEmpty, let kernel = try? libraryComputePipeline("ollin_volume_light_kernel") else {
            encoder.endEncoding()
            return
        }
        encoder.setComputePipelineState(kernel)
        for job in pending {
            var draw = job.draw
            var ray = job.ray
            encoder.setTexture(job.texture, index: 0)
            encoder.setTexture(job.grid, index: 1)
            encoder.setBytes(&draw, length: MemoryLayout<OllinVolumeDraw>.stride, index: 0)
            encoder.setBytes(&ray, length: MemoryLayout<SIMD4<Float>>.stride, index: 1)
            encoder.dispatchThreads(MTLSize(width: job.texture.width, height: job.texture.height,
                                            depth: job.texture.depth),
                                    threadsPerThreadgroup: MTLSize(width: 4, height: 4, depth: 4))
        }
        encoder.endEncoding()
    }

    /// The volumes casting a shadow onto `target`'s solids under `lighting`'s
    /// casters: every prepared volume drawn into the target with a thickness,
    /// each naming, per caster, the transmittance grid it computed toward that
    /// caster's light (the first four lit lights have one; a caster past them,
    /// or an area kind, is skipped by its `casts` lane). Empty when the pass
    /// casts no shadow, which is where `castShadows()` gates the cloud's shadow
    /// with the solids'. The table is written to a small buffer of its own for
    /// the pass; with nothing to cast, the one zero entry every lit mesh
    /// fragment's declared argument is bound to.
    func volumeShadowTable(target: RenderTarget?, lighting: OllinLighting) -> VolumeShadowTable {
        var table = VolumeShadowTable()
        let casters = min(Int(lighting.shadowCasterCount), Int(OLLIN_MAX_SHADOW_CASTERS))
        if lighting.enabled != 0, casters > 0, let standIn = volumeStandIn() {
            let standInID = unsafeBitCast(standIn.gpuResourceID, to: UInt64.self)
            for item in preparedVolumes where item.target === target && item.draw.medium.x > 0 {
                var entry = OllinVolumeShadow()
                entry.inverseModel = item.draw.inverseModel
                var casts = SIMD4<Float>(repeating: 0)
                var handles = [UInt64](repeating: standInID, count: Int(OLLIN_MAX_SHADOW_CASTERS))
                for caster in 0 ..< casters {
                    let lightIndex = casterAt(lighting, caster).lightIndex
                    guard lightIndex >= 0,
                          let slot = (0 ..< item.lit.count).first(where: {
                              item.litIndices[$0] == Float(lightIndex)
                          }),
                          let texture = item.lit[slot] else { continue }
                    handles[caster] = unsafeBitCast(texture.gpuResourceID, to: UInt64.self)
                    casts[caster] = 1
                    table.textures.append(texture)
                }
                guard casts != .zero else { continue }
                withUnsafeMutablePointer(to: &entry.lit) { tuple in
                    tuple.withMemoryRebound(to: UInt64.self, capacity: handles.count) { ids in
                        for (i, id) in handles.enumerated() { ids[i] = id }
                    }
                }
                entry.casts = casts
                table.entries.append(entry)
                if table.entries.count == Int(OLLIN_MAX_VOLUME_SHADOWS) { break }
            }
            if !table.entries.isEmpty { table.textures.append(standIn) }
        }
        if table.entries.isEmpty {
            if volumeShadowStandIn == nil {
                var zero = OllinVolumeShadow()
                volumeShadowStandIn = device.makeBuffer(bytes: &zero,
                                                        length: MemoryLayout<OllinVolumeShadow>.stride,
                                                        options: .storageModeShared)
                volumeShadowStandIn?.label = "Ollin volume shadow (none)"
            }
            table.buffer = volumeShadowStandIn
        } else {
            table.buffer = table.entries.withUnsafeBytes { raw in
                device.makeBuffer(bytes: raw.baseAddress!, length: raw.count, options: .storageModeShared)
            }
            table.buffer?.label = "Ollin volume shadow"
        }
        return table
    }

    /// Note what this pass resolved, for the volumes drawn into it. Called from
    /// `encode` once its lighting is packed; a pass with no volume keeps nothing.
    func keepVolumeLight(_ drawer: Drawer, target: RenderTarget?, lighting: OllinLighting,
                         sets: [Int: OllinLighting], shadowMap: MTLTexture?,
                         uniforms3D: Uniforms3D?) {
        guard let uniforms3D, drawer.hasVolumes(for: target) else { return }
        var all = sets
        all[0] = lighting
        volumePassLights[target.map { ObjectIdentifier($0) }] =
            VolumePassLight(lighting: all, shadowMap: shadowMap, uniforms3D: uniforms3D)
    }

    /// Composite this pass's volumes over `color`, ending each march at `depth`
    /// (the pass's resolved depth). `phase` shifts every march's start offset;
    /// a frame taking several temporal samples gives each its own, so their
    /// average resolves the jitter instead of keeping one fixed grain. A pass
    /// with no volume (or no depth to read) leaves `color` untouched.
    func encodeVolumes(_ drawer: Drawer, target: RenderTarget?, color: MTLTexture,
                       depth: MTLTexture?, phase: Float, into cb: MTLCommandBuffer) {
        let key = target.map { ObjectIdentifier($0) }
        guard let depth, let pass = volumePassLights[key] else { return }
        volumePassLights[key] = nil
        let items = preparedVolumes.filter { $0.target === target }
        guard !items.isEmpty else { return }

        // Farthest first, so nearer volumes composite over farther ones (by the
        // boxes' centers; two volumes that interpenetrate order as wholes). Two
        // centers the same distance away keep their call order, the later one
        // on top, so an absorbing medium drawn after a glow over the same box
        // dims the glow, and drawn before it dims only what lies behind both.
        let eye = pass.lighting[0].map { SIMD3<Float>($0.cameraPosition.x, $0.cameraPosition.y,
                                                       $0.cameraPosition.z) } ?? .zero
        let ordered = items.sorted { a, b in
            let farA = simd_distance(a.draw.model.columns.3.xyz, eye)
            let farB = simd_distance(b.draw.model.columns.3.xyz, eye)
            return farA != farB ? farA > farB : a.index < b.index
        }

        let colorFormat: MTLPixelFormat? = color.pixelFormat == linearFormat ? nil : color.pixelFormat
        guard let state = try? pipeline(.volume(color: colorFormat)) else { return }
        let descriptor = MTLRenderPassDescriptor()
        descriptor.colorAttachments[0].texture = color
        descriptor.colorAttachments[0].loadAction = .load
        descriptor.colorAttachments[0].storeAction = .store
        guard let encoder = countedEncoder(cb, descriptor, caller: "volumes") else { return }
        encoder.setRenderPipelineState(state)
        var uniforms = pass.uniforms3D
        encoder.setFragmentBytes(&uniforms, length: MemoryLayout<Uniforms3D>.stride, index: 2)
        encoder.setFragmentTexture(depth, index: 1)
        encoder.setFragmentTexture(pass.shadowMap ?? ensureDummyShadowMap(), index: 2)
        if let shadowSampler { encoder.setFragmentSamplerState(shadowSampler, index: 0) }
        if iblPlaceholderCube == nil { iblPlaceholderCube = makeCubeTexture(face: 1, mipped: false) }
        encoder.setFragmentTexture(currentIBLIrradiance ?? iblPlaceholderCube, index: 8)
        encoder.setFragmentTexture(iesArrayTexture ?? shapingStandIn(), index: 10)
        encoder.setFragmentTexture(cookieArrayTexture ?? shapingStandIn(), index: 11)
        let standIn = volumeStandIn()
        let occupancyStandIn = volumeOccupancyHeld()
        let boundsStandIn = volumeBoundsWhole()
        for item in ordered {
            var draw = item.draw
            draw.medium.z = phase
            var lighting = pass.lighting[item.lightSet] ?? pass.lighting[0]!
            encoder.setFragmentBytes(&draw, length: MemoryLayout<OllinVolumeDraw>.stride, index: 0)
            encoder.setFragmentBytes(&lighting, length: MemoryLayout<OllinLighting>.stride, index: 1)
            encoder.setFragmentTexture(item.grid, index: 0)
            for slot in 0 ..< Int(OLLIN_VOLUME_MAX_LIT) {
                let texture = slot < item.lit.count ? item.lit[slot] : nil
                encoder.setFragmentTexture(texture ?? standIn, index: 4 + slot)
            }
            let occupancy = MetalRenderer.skipsEmptyVolumeBlocks ? item.occupancy : nil
            encoder.setFragmentTexture(occupancy?.fine ?? occupancyStandIn, index: 12)
            encoder.setFragmentTexture(occupancy?.coarse ?? occupancyStandIn, index: 13)
            encoder.setFragmentBuffer(occupancy?.bounds ?? boundsStandIn, offset: 0, index: 3)
            let scissor = volumeScissor(item.draw.model, uniforms: pass.uniforms3D,
                                        width: color.width, height: color.height)
                ?? MTLScissorRect(x: 0, y: 0, width: color.width, height: color.height)
            guard scissor.width > 0, scissor.height > 0 else { continue }
            encoder.setScissorRect(scissor)
            profile.drawCalls += 1
            encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        }
        encoder.endEncoding()
    }

    /// The march's start-offset shift for temporal sample `index`: golden-ratio
    /// steps, so any run of samples spreads its offsets evenly over a step.
    func volumeJitterPhase(_ index: Int) -> Float {
        let phase = Double(index) * 0.618_033_988_749_895
        return Float(phase - phase.rounded(.down))
    }

    /// How many march steps a view ray takes per sample spacing of the grid,
    /// by the frame's volumetric quality: two at `.detail` (every export and
    /// test, the rule the integral's closed forms are read against), one and a
    /// half at the live default, one at `.performance`. The march's cost is its
    /// step count times the pixels the box covers, so a fine grid in a big
    /// window pays here; the per-step jitter turns a coarser march into grain
    /// rather than bands, and temporal anti-aliasing averages the grain away. A
    /// step count given outright (`volumetricSteps`) is the beams' and leaves
    /// the volume at two.
    func volumeStepsPerSample(_ setting: VolumetricQualitySetting) -> Float {
        switch setting {
        case .absolute:
            return 2
        case .tier(let quality):
            switch effectiveQuality(quality) {
            case .performance: return 1
            case .default: return 1.5
            case .detail: return 2
            }
        }
    }

    /// The draw's GPU record: placement, step, and the medium in linear light.
    func makeVolumeDraw(_ item: VolumeDraw, phase: Float) -> OllinVolumeDraw {
        let source = item.source
        let finest = 1 / Float(max(source.width, source.height, source.depth) - 1)
        let step = finest / volumeStepsPerSample(drawerVolumetricQuality)
        let medium = item.medium
        let density = Float(max(0, medium.density))
        let scatter = medium.color.linearRGBA
        let glow = medium.glow.linearRGBA * Float(max(0, medium.glowIntensity))
        let scatters: Float = density > 0 && max(scatter.x, scatter.y, scatter.z) > 0 ? 1 : 0
        // The octave sum's contribution factor, the share each further octave
        // keeps of the last: 0.43 at a bounce of 1, the value at which a white,
        // evenly scattering slab of any thickness lit and seen along its normal
        // reads what the exact solution for such a half-space gives, 1.057 of
        // a white matte surface under the same light (Chandrasekhar's H
        // function, H(1)^2 / 8; the sum over the octaves of b^k / (1 + 2^-k)
        // reaches 1.06 there, where the paper's 1/2 reaches 1.26), and under
        // the thinning factor of 1/2, which keeps an octave from scattering
        // more light than it stops (Hillaire's rule).
        let bounce = Float(min(1, max(0, medium.bounce))) * 0.43
        return OllinVolumeDraw(
            model: item.model,
            inverseModel: item.model.inverse,
            grid: SIMD4(Float(source.width), Float(source.height), Float(source.depth), step),
            medium: SIMD4(density, Float(min(0.95, max(-0.95, medium.anisotropy))),
                          phase, MetalRenderer.volumeMaxSteps),
            scatter: SIMD4(scatter.x, scatter.y, scatter.z, scatters),
            glow: SIMD4(glow.x, glow.y, glow.z, bounce),
            litLights: SIMD4(repeating: -1))
    }

    /// The occupancy of `source`'s samples for this frame: kept while the
    /// samples hold, and when they are new (or a kernel rewrote them) a job
    /// added to `jobs` that works it out ahead of the march. A kernel-written
    /// grid keeps one pair of textures and has them rewritten in place; a
    /// frame still reading the old ones is ahead of the rewrite on the queue.
    private func volumeOccupancy(for source: VolumeSource, grid: MTLTexture,
                                 jobs: inout [(grid: MTLTexture, occupancy: VolumeOccupancy)]) -> VolumeOccupancy? {
        let id = source.contentID, generation = source.contentGeneration
        if var known = volumeOccupancyCache[id] {
            known.used = volumeLightGeneration
            if known.generation != generation {
                known.generation = generation
                jobs.append((grid, known))
            }
            volumeOccupancyCache[id] = known
            return known
        }
        func blocks(_ samples: Int, _ side: Int) -> Int { max(1, (samples - 1 + side - 1) / side) }
        let block = Int(OLLIN_VOLUME_BLOCK)
        let fineSize = (blocks(source.width, block), blocks(source.height, block), blocks(source.depth, block))
        guard let fine = makeOccupancyTexture(fineSize.0, fineSize.1, fineSize.2),
              let coarse = makeOccupancyTexture((fineSize.0 + block - 1) / block,
                                                (fineSize.1 + block - 1) / block,
                                                (fineSize.2 + block - 1) / block),
              let bounds = device.makeBuffer(length: 6 * MemoryLayout<UInt32>.stride,
                                             options: .storageModePrivate) else { return nil }
        bounds.label = "Ollin volume tight box"
        let occupancy = VolumeOccupancy(fine: fine, coarse: coarse, bounds: bounds,
                                        generation: generation, used: volumeLightGeneration)
        volumeOccupancyCache[id] = occupancy
        jobs.append((grid, occupancy))
        return occupancy
    }

    private func makeOccupancyTexture(_ width: Int, _ height: Int, _ depth: Int) -> MTLTexture? {
        let descriptor = MTLTextureDescriptor()
        descriptor.textureType = .type3D
        descriptor.pixelFormat = .r8Uint
        descriptor.width = width
        descriptor.height = height
        descriptor.depth = depth
        descriptor.usage = [.shaderRead, .shaderWrite]
        descriptor.storageMode = .private
        let texture = device.makeTexture(descriptor: descriptor)
        texture?.label = "Ollin volume occupancy"
        return texture
    }

    /// The one-block occupancy that says every block holds medium.
    private func volumeOccupancyHeld() -> MTLTexture? {
        if let volumeOccupancyStandIn { return volumeOccupancyStandIn }
        let descriptor = MTLTextureDescriptor()
        descriptor.textureType = .type3D
        descriptor.pixelFormat = .r8Uint
        descriptor.width = 1
        descriptor.height = 1
        descriptor.depth = 1
        descriptor.usage = .shaderRead
        descriptor.storageMode = .shared
        guard let texture = device.makeTexture(descriptor: descriptor) else { return nil }
        var one: UInt8 = 1
        texture.replace(region: MTLRegionMake3D(0, 0, 0, 1, 1, 1), mipmapLevel: 0, slice: 0,
                        withBytes: &one, bytesPerRow: 1, bytesPerImage: 1)
        volumeOccupancyStandIn = texture
        return texture
    }

    /// The tight box that is the whole grid: the lowest block 0 on every axis
    /// and a highest one past any grid's last.
    private func volumeBoundsWhole() -> MTLBuffer? {
        if let volumeBoundsStandIn { return volumeBoundsStandIn }
        var whole: [UInt32] = [0, 0, 0, ~UInt32(1 << 20), ~UInt32(1 << 20), ~UInt32(1 << 20)]
        volumeBoundsStandIn = device.makeBuffer(bytes: &whole, length: 6 * MemoryLayout<UInt32>.stride,
                                                options: .storageModeShared)
        volumeBoundsStandIn?.label = "Ollin volume tight box (whole)"
        return volumeBoundsStandIn
    }

    /// A light-transmittance grid sized for `source` (its own resolution, up to
    /// `volumeLightMaxSamples` a side), written by the light kernel: one of that
    /// size from the pool when there is one, else a new texture.
    private func makeVolumeLightTexture(for source: VolumeSource) -> MTLTexture? {
        let cap = MetalRenderer.volumeLightMaxSamples
        let width = min(source.width, cap), height = min(source.height, cap), depth = min(source.depth, cap)
        if let pooled = volumeLightPool.firstIndex(where: {
            $0.width == width && $0.height == height && $0.depth == depth
        }) {
            return volumeLightPool.remove(at: pooled)
        }
        let descriptor = MTLTextureDescriptor()
        descriptor.textureType = .type3D
        descriptor.pixelFormat = .r16Float
        descriptor.width = width
        descriptor.height = height
        descriptor.depth = depth
        descriptor.usage = [.shaderRead, .shaderWrite]
        descriptor.storageMode = .private
        let texture = device.makeTexture(descriptor: descriptor)
        texture?.label = "Ollin volume light"
        return texture
    }

    /// The fully lit transmittance grid an unused light slot reads (never
    /// sampled, since no light index names the slot; bound so every argument is).
    private func volumeStandIn() -> MTLTexture? {
        if let volumeLightStandIn { return volumeLightStandIn }
        let descriptor = MTLTextureDescriptor()
        descriptor.textureType = .type3D
        descriptor.pixelFormat = .r16Float
        descriptor.width = 2
        descriptor.height = 2
        descriptor.depth = 2
        descriptor.usage = .shaderRead
        descriptor.storageMode = .shared
        guard let texture = device.makeTexture(descriptor: descriptor) else { return nil }
        let ones = [Float16](repeating: 1, count: 8)
        ones.withUnsafeBytes { raw in
            texture.replace(region: MTLRegionMake3D(0, 0, 0, 2, 2, 2), mipmapLevel: 0, slice: 0,
                            withBytes: raw.baseAddress!, bytesPerRow: 4, bytesPerImage: 8)
        }
        volumeLightStandIn = texture
        return texture
    }

    /// The box's footprint on the target, from its eight corners through the
    /// pass's view-projection, padded a pixel; nil (the whole target) when a
    /// corner lies behind the camera, where a projected bound means nothing.
    private func volumeScissor(_ model: simd_float4x4, uniforms: Uniforms3D,
                               width: Int, height: Int) -> MTLScissorRect? {
        let viewProjection = uniforms.projection * uniforms.view
        var lo = SIMD2<Float>(repeating: .greatestFiniteMagnitude)
        var hi = SIMD2<Float>(repeating: -.greatestFiniteMagnitude)
        for corner in 0 ..< 8 {
            let p = SIMD4<Float>(corner & 1 == 0 ? -0.5 : 0.5, corner & 2 == 0 ? -0.5 : 0.5,
                                 corner & 4 == 0 ? -0.5 : 0.5, 1)
            let clip = viewProjection * (model * p)
            if clip.w <= 1e-4 { return nil }
            let ndc = SIMD2(clip.x, clip.y) / clip.w
            lo = simd_min(lo, ndc)
            hi = simd_max(hi, ndc)
        }
        let x0 = Int(((lo.x + 1) * 0.5 * Float(width)).rounded(.down)) - 1
        let x1 = Int(((hi.x + 1) * 0.5 * Float(width)).rounded(.up)) + 1
        let y0 = Int(((1 - hi.y) * 0.5 * Float(height)).rounded(.down)) - 1
        let y1 = Int(((1 - lo.y) * 0.5 * Float(height)).rounded(.up)) + 1
        let left = max(0, min(width, x0)), right = max(0, min(width, x1))
        let top = max(0, min(height, y0)), bottom = max(0, min(height, y1))
        return MTLScissorRect(x: left, y: top, width: max(0, right - left), height: max(0, bottom - top))
    }

    /// Light `index` of a lighting uniform's fixed-size inline list.
    private func lightAt(_ lighting: OllinLighting, _ index: Int) -> OllinLight {
        withUnsafeBytes(of: lighting.lights) { raw in
            raw.bindMemory(to: OllinLight.self)[index]
        }
    }

    /// Shadow caster `index` of a lighting uniform's fixed-size inline list.
    private func casterAt(_ lighting: OllinLighting, _ index: Int) -> OllinShadowCaster {
        withUnsafeBytes(of: lighting.shadowCasters) { raw in
            raw.bindMemory(to: OllinShadowCaster.self)[index]
        }
    }
}

private extension SIMD4 where Scalar == Float {
    var xyz: SIMD3<Float> { SIMD3(x, y, z) }
}

private extension simd_float4x4 {
    var flatArray: [Float] {
        [columns.0, columns.1, columns.2, columns.3].flatMap { [$0.x, $0.y, $0.z, $0.w] }
    }
}
