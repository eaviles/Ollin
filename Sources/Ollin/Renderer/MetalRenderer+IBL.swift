// MetalRenderer, the image-based-lighting half: resolving Environment sources
// (bundled and downloaded HDRIs, the procedural sky), the equirect decode and
// blob cache, and the bake into irradiance/prefilter/BRDF maps, with the
// LRU-bounded in-memory cache types.

import Foundation
import Metal
import MetalKit
import simd
import CoreGraphics
import COllinShaders
import os   // OSAllocatedUnfairLock for the off-thread equirect decode handoff
import CHosekWilkie   // ollin_hosek_rgb_configs, the procedural-sky coefficient cook

/// One `iblCache` slot: the baked maps, their approximate GPU footprint (driving the
/// byte-budget eviction), and the resolve tick of their last use (the LRU order).
struct IBLCacheEntry {
    let maps: IBLMaps
    let bytes: Int
    var lastUse: UInt64
}

/// The baked image-based-lighting maps for one environment, cached by source. The
/// `envCube` is the environment itself (for a skybox and mirror reflections), `irradiance`
/// the cosine-convolved diffuse cube, `prefilter` the GGX-prefiltered specular mip-cube.
final class IBLMaps {
    let irradiance: MTLTexture
    let prefilter: MTLTexture
    let envCube: MTLTexture
    /// The full-resolution equirectangular source, kept so the skybox samples it directly
    /// (sharp) rather than the low-resolution cube. For a procedural sky it's the generated
    /// equirect. Optional only for a bake that produced no source texture.
    let equirect: MTLTexture?
    let maxMip: Int
    /// An auto-exposure factor: the environments range ~800× in average brightness, so each
    /// is scaled to a common target average luminance, applied to both the lighting and the
    /// skybox. Keeps a bright noon or a night from blowing out or crushing.
    let normalization: Float
    init(irradiance: MTLTexture, prefilter: MTLTexture, envCube: MTLTexture,
         equirect: MTLTexture?, maxMip: Int, normalization: Float) {
        self.irradiance = irradiance
        self.prefilter = prefilter
        self.envCube = envCube
        self.equirect = equirect
        self.maxMip = maxMip
        self.normalization = normalization
    }
}

extension MetalRenderer {
    private static let iblEnvFace = 256
    private static let iblIrradianceFace = 32
    private static let iblPrefilterFace = 256   // mirror (roughness 0) reflection sharpness
    private static let iblPrefilterMips = 6
    private static let iblBRDFSize = 256
    /// The sheen directional-albedo LUT edge: E is smooth in both axes, so a small
    /// table linearly sampled is exact to well under a shading step.
    private static let sheenLUTSize = 64
    private static let iblTargetLuminance: Float = 0.4   // auto-exposure target average
    /// A neutral midday sky used to light a scene while a non-bundled HDRI downloads, instead
    /// of leaving it unlit (see resolveEnvironmentSources). The env's own intensity/rotation
    /// still apply, since the placeholder is a copy of it with only the source swapped.
    static let skyPlaceholderSource = Environment.Source.sky(turbidity: 2.5, sunElevation: 0.6,
                                                             groundAlbedo: 0.3)

    /// Resolve the frame's environment to its baked IBL maps, baking once on the given
    /// command buffer and caching by source (the bake is a few fullscreen passes; a frame
    /// that reuses an environment pays nothing). A `.remote` source resolves to its cached
    /// file (or a downloading placeholder); `blocking` true (the export path) waits for the
    /// download so exported art is the full-resolution version. Returns whether IBL is active.
    func resolveIBL(for environment: Environment?, commandBuffer cb: MTLCommandBuffer,
                    blocking: Bool = false) -> Bool {
        iblResolveTick += 1
        defer { pruneStaleEquirects() }
        guard let environment else { currentIBL = nil; return false }
        let (primary, placeholder) = resolveEnvironmentSources(environment, blocking: blocking)
        // Bake the requested environment once its pixels are ready; until then (a heavy HDRI
        // still downloading, or decoding off-thread) show the bundled placeholder, so the
        // scene is never unlit and the live window never blocks on the decode.
        if let primary, let maps = bakeReady(primary, blocking: blocking, commandBuffer: cb) {
            currentIBL = maps; return true
        }
        if let placeholder, let maps = bakeReady(placeholder, blocking: false, commandBuffer: cb) {
            currentIBL = maps; return true
        }
        currentIBL = nil; return false
    }

    /// Bake (or reuse) the IBL maps for an already-resolved `.resource`/`.url` environment, or
    /// nil when its equirect isn't decoded yet (a heavy `.url` decodes off-thread). Cached by
    /// source so the bake runs once; the raw float pixels are freed once baked into textures.
    private func bakeReady(_ env: Environment, blocking: Bool,
                           commandBuffer cb: MTLCommandBuffer) -> IBLMaps? {
        // A static sky (or an HDRI) keys on its exact source, so it bakes once and then reuses
        // the cache every frame. An animated sky is a fresh source each frame, so it re-bakes
        // entirely on the GPU (no CPU read-back), which a smoothly moving sun needs.
        if var entry = iblCache[env.source] {
            entry.lastUse = iblResolveTick
            iblCache[env.source] = entry
            return entry.maps
        }

        let loaded: MTLTexture, avg: Float
        let isSky: Bool
        if case .sky(let t, let e, let a) = env.source {
            guard let sky = generateSkyEquirectTexture(turbidity: t, sunElevation: e,
                                                       groundAlbedo: a, commandBuffer: cb) else { return nil }
            (loaded, avg) = sky
            isSky = true
        } else {
            guard let bytes = equirectBytes(for: env, blocking: blocking),
                  let tex = uploadEquirect(bytes) else { return nil }
            (loaded, avg) = (tex, bytes.avg)
            equirectReady.withLock { $0[env.source] = nil }
            isSky = false
        }
        guard let maps = bakeIBL(env, equirectTexture: loaded, avgLuminance: avg,
                                 fastSky: isSky, commandBuffer: cb) else { return nil }
        // An animated sky makes a fresh source each frame; drop the previous sky bake so its GPU
        // textures don't accumulate over the animation (a static sky keeps its one entry).
        if case .sky = env.source {
            for k in iblCache.keys where k != env.source {
                if case .sky = k { iblCache[k] = nil }
            }
        }
        let bytes = Self.textureFootprint(maps.irradiance) + Self.textureFootprint(maps.prefilter)
            + Self.textureFootprint(maps.envCube) + Self.textureFootprint(maps.equirect)
        iblCache[env.source] = IBLCacheEntry(maps: maps, bytes: bytes, lastUse: iblResolveTick)
        evictIBLOverBudget(keeping: env.source)
        return maps
    }

    /// The baked-map budget: enough for a handful of high-resolution environments (a 4K
    /// HDRI's maps are ~85 MB, an 8K's ~270 MB) while keeping a gallery that cycles many
    /// of them bounded. Past it, the least-recently-used entries go; an evicted source
    /// re-bakes from its cached disk blob, so the cost of a wrong eviction is small.
    private static let iblCacheBudgetBytes = 512 << 20

    /// Evict least-recently-used baked maps until the cache fits the budget, never
    /// touching `current` (the source just baked or reused for this frame).
    private func evictIBLOverBudget(keeping current: Environment.Source) {
        let budget = iblCacheBudgetOverride ?? Self.iblCacheBudgetBytes
        var total = iblCache.values.reduce(0) { $0 + $1.bytes }
        while total > budget,
              let victim = iblCache.filter({ $0.key != current })
                  .min(by: { $0.value.lastUse < $1.value.lastUse }) {
            total -= victim.value.bytes
            iblCache[victim.key] = nil
        }
    }

    /// Test seam: the cache's entry count and approximate byte total.
    var iblCacheStats: (count: Int, bytes: Int) {
        (iblCache.count, iblCache.values.reduce(0) { $0 + $1.bytes })
    }

    /// Approximate GPU footprint of a texture (faces × mips × bytes per texel), for the
    /// cache budget. Estimation is fine here: eviction needs proportions, not exact bytes.
    private static func textureFootprint(_ t: MTLTexture?) -> Int {
        guard let t else { return 0 }
        let faces = t.textureType == .typeCube ? 6 : max(t.arrayLength, 1)
        let bytesPerTexel: Int
        switch t.pixelFormat {
        case .rgba32Float: bytesPerTexel = 16
        case .rgba16Float: bytesPerTexel = 8
        default: bytesPerTexel = 4
        }
        let base = t.width * t.height * faces * bytesPerTexel
        return t.mipmapLevelCount > 1 ? base * 4 / 3 : base
    }

    /// Free decoded equirect pixels whose source hasn't been requested for a few resolves
    /// (the environment moved on before its off-thread decode landed). A consumed entry is
    /// cleared by the bake itself, so anything lingering here is an orphan holding the
    /// full-resolution float pixels (tens of MB); a re-requested source just re-reads its
    /// disk blob. The window is a few ticks so pixels landing between two frames' resolves
    /// are never dropped before the bake that wants them.
    private func pruneStaleEquirects() {
        guard iblResolveTick > 4 else { return }
        let cutoff = iblResolveTick - 4
        let requests = equirectLastRequest   // copied: the lock's closure is Sendable
        equirectReady.withLock { ready in
            for key in ready.keys where (requests[key] ?? 0) < cutoff {
                ready[key] = nil
            }
        }
        equirectLastRequest = equirectLastRequest.filter { $0.value >= cutoff }
    }

    /// Resolve an environment to (primary, placeholder): the form to bake when its pixels are
    /// ready, and a bundled fallback to show meanwhile. Handles a `.remote` source: the
    /// cached download if present, else (export) a synchronous download, else (live) kick off
    /// the download and offer the placeholder until it lands.
    private func resolveEnvironmentSources(_ env: Environment, blocking: Bool)
        -> (primary: Environment?, placeholder: Environment?) {
        func with(_ source: Environment.Source) -> Environment { var e = env; e.source = source; return e }
        switch env.source {
        case .resource, .url:
            return (env, nil)
        case .sky:
            return (env, nil)   // generated on the GPU when its pixels are baked
        case .remote(let url, let fallback):
            let cache = EnvironmentCache.shared
            // While a non-bundled HDRI downloads, light the scene with a procedural sky
            // (keeping the env's own intensity/rotation/backdrop) instead of leaving it
            // unlit, unless an explicit bundled placeholder was given.
            let placeholder = fallback.map { with(.resource(name: $0, bundleID: nil)) }
                ?? with(Self.skyPlaceholderSource)
            if let file = cache.cachedFile(for: url) {
                return (with(.url(file)), placeholder)
            }
            if blocking, let file = cache.downloadBlocking(url) {
                return (with(.url(file)), nil)
            }
            cache.ensureDownloading(url)
            return (nil, placeholder)   // not downloaded yet: only the placeholder
        }
    }

    /// The processed equirect pixels for a bakeable env, or nil if not ready. A bundled
    /// `.resource` decodes inline (small, fast). A `.url` HDRI can be large, so it decodes off
    /// the render thread (live), returning nil until it lands, or synchronously when
    /// `blocking` (export). A disk blob of the processed pixels makes a relaunch skip the
    /// expensive PIZ decode.
    private func equirectBytes(for env: Environment, blocking: Bool) -> EquirectBytes? {
        equirectLastRequest[env.source] = iblResolveTick
        if let ready = equirectReady.withLock({ $0[env.source] }) { return ready }
        switch env.source {
        case .resource:
            guard let bytes = Self.loadEquirectBytes(env) else { return nil }
            equirectReady.withLock { $0[env.source] = bytes }
            return bytes
        case .url(let file):
            if let failedStamp = equirectFailed.withLock({ $0[env.source] }) {
                // Skip the re-decode only while the bytes it failed on are still there;
                // a replaced file (different size/mtime) may decode fine, so retry it.
                guard Self.equirectSourceStamp(file) != failedStamp else { return nil }
                equirectFailed.withLock { $0[env.source] = nil }
            }
            if blocking {
                guard let bytes = Self.loadEquirectBytes(env) else {
                    Self.noteEquirectDecodeFailure(file, memo: equirectFailed, source: env.source)
                    return nil
                }
                equirectReady.withLock { $0[env.source] = bytes }
                return bytes
            }
            let source = env.source
            let started = equirectLoading.withLock { loading -> Bool in
                guard !loading.contains(source) else { return false }
                loading.insert(source); return true
            }
            if started {
                let envCopy = env, ready = equirectReady, loading = equirectLoading
                let failed = equirectFailed
                Task.detached {
                    if let bytes = Self.loadEquirectBytes(envCopy) {
                        ready.withLock { $0[source] = bytes }
                    } else {
                        Self.noteEquirectDecodeFailure(file, memo: failed, source: source)
                    }
                    loading.withLock { _ = $0.remove(source) }
                }
            }
            return nil
        case .sky, .remote:
            // .sky is generated as a texture directly in bakeReady (no CPU pixels); .remote was
            // resolved to a cached .url or a placeholder before reaching here.
            return nil
        }
    }

    /// The IBL maps bound to the mesh fragment this frame (irradiance / prefilter / BRDF
    /// LUT), or `nil` when no environment is set. `nil` for any of these keeps the mesh
    /// fragment on its byte-identical no-IBL path.
    var currentIBLIrradiance: MTLTexture? { currentIBL?.irradiance }
    var currentIBLPrefilter: MTLTexture? { currentIBL?.prefilter }
    var currentIBLEnvCube: MTLTexture? { currentIBL?.envCube }
    var currentIBLSkyboxTexture: MTLTexture? { currentIBL?.equirect }
    var currentIBLMaxMip: Int { currentIBL?.maxMip ?? 0 }
    var currentIBLNormalization: Float { currentIBL?.normalization ?? 1 }
    var iblBRDFLUTTexture: MTLTexture? { iblBRDFLUT }

    /// Load the two 64×64 LTC lookup tables for area-light shading from the bundled
    /// fit (`Resources/LTC/ltc_tables.bin`: table 1 then table 2, RGBA float32 rows;
    /// provenance and license in the notice beside it). Returns `true` once both
    /// textures exist. A failed load (a corrupt bundle) logs once and stays failed,
    /// so area lights contribute nothing rather than shading through garbage.
    @discardableResult
    func ensureLTCTables() -> Bool {
        if ltcMatTexture != nil && ltcAmpTexture != nil { return true }
        if ltcLoadFailed { return false }
        let side = 64
        let tableBytes = side * side * 4 * MemoryLayout<Float>.size
        guard let url = Bundle.module.url(forResource: "ltc_tables", withExtension: "bin",
                                          subdirectory: "LTC"),
              let data = try? Data(contentsOf: url),
              data.count == 2 * tableBytes else {
            ltcLoadFailed = true
            FileHandle.standardError.write(Data(
                "Ollin: the bundled LTC tables failed to load; area lights (rectLight/diskLight/tubeLight) will not shade.\n".utf8))
            return false
        }
        let desc = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rgba32Float,
                                                            width: side, height: side,
                                                            mipmapped: false)
        desc.usage = .shaderRead
        guard let mat = device.makeTexture(descriptor: desc),
              let amp = device.makeTexture(descriptor: desc) else {
            ltcLoadFailed = true
            return false
        }
        let bytesPerRow = side * 4 * MemoryLayout<Float>.size
        data.withUnsafeBytes { (raw: UnsafeRawBufferPointer) in
            let base = raw.baseAddress!
            mat.replace(region: MTLRegionMake2D(0, 0, side, side), mipmapLevel: 0,
                        withBytes: base, bytesPerRow: bytesPerRow)
            amp.replace(region: MTLRegionMake2D(0, 0, side, side), mipmapLevel: 0,
                        withBytes: base + tableBytes, bytesPerRow: bytesPerRow)
        }
        ltcMatTexture = mat
        ltcAmpTexture = amp
        return true
    }

    /// The baked IES-profile texture resolution: vertical angle 0…π across the
    /// width, azimuth 0…2π down the height (the shader's sampler wraps it).
    static let iesBakeWidth = 256
    static let iesBakeHeight = 64

    /// Bake the frame's distinct IES profiles (from `Drawer.usedIESProfiles`, whose
    /// order the packed `shaping.x` layer indices follow) into an `r16Float`
    /// `texture2d_array`, one layer per profile. Cached by the profiles' content
    /// hashes; a change allocates a fresh texture (never replaced in place). Returns
    /// `false` only if the device can't make the texture.
    func ensureIESArray(_ profiles: [IESProfile]) -> Bool {
        guard !profiles.isEmpty else { return false }
        let key = profiles.map(\.contentHash)
        if key == iesArrayKey, iesArrayTexture != nil { return true }
        let w = Self.iesBakeWidth, h = Self.iesBakeHeight
        let desc = MTLTextureDescriptor()
        desc.textureType = .type2DArray
        desc.pixelFormat = .r16Float
        desc.width = w
        desc.height = h
        desc.arrayLength = profiles.count
        desc.usage = .shaderRead
        desc.storageMode = .shared
        guard let texture = device.makeTexture(descriptor: desc) else { return false }
        for (layer, profile) in profiles.enumerated() {
            let half = profile.bakedTable(width: w, height: h).map(Float16.init)
            half.withUnsafeBytes { raw in
                texture.replace(region: MTLRegionMake2D(0, 0, w, h), mipmapLevel: 0,
                                slice: layer, withBytes: raw.baseAddress!,
                                bytesPerRow: w * MemoryLayout<Float16>.size,
                                bytesPerImage: w * h * MemoryLayout<Float16>.size)
            }
        }
        iesArrayTexture = texture
        iesArrayKey = key
        return true
    }

    /// Upload the frame's distinct light cookies (from `Drawer.usedLightCookies`,
    /// the `shaping.y` order) into an sRGB `texture2d_array`; each `LightCookie`
    /// already resampled itself to the shared square at init, so a layer is one
    /// byte copy. Same fresh-texture cache discipline as the profiles.
    func ensureCookieArray(_ cookies: [LightCookie]) -> Bool {
        guard !cookies.isEmpty else { return false }
        let key = cookies.map(\.contentHash)
        if key == cookieArrayKey, cookieArrayTexture != nil { return true }
        let side = LightCookie.resolution
        let desc = MTLTextureDescriptor()
        desc.textureType = .type2DArray
        desc.pixelFormat = .rgba8Unorm_srgb
        desc.width = side
        desc.height = side
        desc.arrayLength = cookies.count
        desc.usage = .shaderRead
        desc.storageMode = .shared
        guard let texture = device.makeTexture(descriptor: desc) else { return false }
        for (layer, cookie) in cookies.enumerated() {
            cookie.pixels.withUnsafeBytes { raw in
                texture.replace(region: MTLRegionMake2D(0, 0, side, side), mipmapLevel: 0,
                                slice: layer, withBytes: raw.baseAddress!,
                                bytesPerRow: side * 4, bytesPerImage: side * side * 4)
            }
        }
        cookieArrayTexture = texture
        cookieArrayKey = key
        return true
    }

    /// The never-sampled 1×1×1 array stand-in for the light-shaping texture slots
    /// (10/11) when a frame has no profile or cookie bound there.
    func shapingStandIn() -> MTLTexture? {
        if let existing = lightShapingStandIn { return existing }
        let desc = MTLTextureDescriptor()
        desc.textureType = .type2DArray
        desc.pixelFormat = .r8Unorm
        desc.width = 1
        desc.height = 1
        desc.arrayLength = 1
        desc.usage = .shaderRead
        lightShapingStandIn = device.makeTexture(descriptor: desc)
        return lightShapingStandIn
    }

    private func bakeIBL(_ environment: Environment, equirectTexture loaded: MTLTexture,
                         avgLuminance: Float, fastSky: Bool = false,
                         commandBuffer cb: MTLCommandBuffer) -> IBLMaps? {
        guard let env = makeEnvCube(equirectTexture: loaded, commandBuffer: cb) else { return nil }
        let envCube = env.cube
        if let blit = cb.makeBlitCommandEncoder() {
            blit.generateMipmaps(for: envCube)   // the prefilter samples these mips
            blit.endEncoding()
        }
        guard let irradiance = makeCubeTexture(face: Self.iblIrradianceFace, mipped: false),
              let prefilter = makeCubeTexture(face: Self.iblPrefilterFace, mipped: true),
              let irrPipe = try? pipeline(.ibl("ollin_ibl_irradiance")),
              let prePipe = try? pipeline(.ibl("ollin_ibl_prefilter")) else { return nil }

        // A procedural sky is low-frequency, so its convolutions converge with far fewer samples
        // than an HDRI; the cheaper bake lets a moving sun re-bake every frame smoothly. `0`
        // selects the default fine bake in the shader, keeping the HDRI path byte-identical.
        let irrStep: Float = fastSky ? 0.08 : 0      // coarser hemisphere step (~10x fewer samples)
        let preSamples: Float = fastSky ? 32 : 0     // fewer GGX samples (vs the default 256)
        for face in 0..<6 {
            bakeIBLFace(pipeline: irrPipe, inputs: [envCube], output: irradiance, slice: face,
                        level: 0, params: SIMD4<Float>(Float(face), 0, irrStep, 0), commandBuffer: cb)
        }
        let mips = Self.iblPrefilterMips
        for mip in 0..<mips {
            let roughness = mips > 1 ? Float(mip) / Float(mips - 1) : 0
            for face in 0..<6 {
                bakeIBLFace(pipeline: prePipe, inputs: [envCube], output: prefilter, slice: face,
                            level: mip, params: SIMD4<Float>(Float(face), roughness, preSamples, 0),
                            commandBuffer: cb)
            }
        }
        ensureBRDFLUT(commandBuffer: cb)
        // Auto-exposure: scale to a common target average luminance (clamped so a near-black
        // night or a blinding noon stays sane), applied to the lighting and the skybox.
        let normalization = avgLuminance > 1e-5
            ? min(max(Self.iblTargetLuminance / avgLuminance, 0.01), 12)
            : 1
        return IBLMaps(irradiance: irradiance, prefilter: prefilter, envCube: envCube,
                       equirect: env.equirect, maxMip: mips - 1, normalization: normalization)
    }

    /// Reproject an equirect texture (a decoded HDRI or a generated sky) into an environment
    /// cube map for the bake, returning the cube and the equirect itself (the skybox samples it
    /// directly). Returns nil on cube/pipeline failure, so the frame stays on the no-IBL path.
    private func makeEnvCube(equirectTexture loaded: MTLTexture, commandBuffer cb: MTLCommandBuffer)
        -> (cube: MTLTexture, equirect: MTLTexture)? {
        guard let cube = makeCubeTexture(face: Self.iblEnvFace, mipped: true),
              let pipe = try? pipeline(.ibl("ollin_ibl_equirect_to_cube")) else { return nil }
        // Mip the equirect *before* the cube bake: a high-res equirect → small cube face is a
        // big minification, so the equirect→cube sample needs valid mips (and the skybox blur
        // samples them too). Generating them afterward would leave the cube reading empty mips.
        if let blit = cb.makeBlitCommandEncoder() {
            blit.generateMipmaps(for: loaded)
            blit.endEncoding()
        }
        for face in 0..<6 {
            bakeIBLFace(pipeline: pipe, inputs: [loaded], output: cube, slice: face, level: 0,
                        params: SIMD4<Float>(Float(face), 0, 0, 0), commandBuffer: cb)
        }
        return (cube, loaded)
    }

    /// Upload processed equirect float pixels into a mipmapped `rgba16Float` texture (the
    /// skybox samples a blurred level for soft focus; `makeEnvCube` generates the mips). The
    /// `.shared` storage lets the level-0 upload run regardless of thread.
    private func uploadEquirect(_ bytes: EquirectBytes) -> MTLTexture? {
        let desc = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rgba16Float,
                                                            width: bytes.width, height: bytes.height,
                                                            mipmapped: true)
        desc.usage = [.shaderRead]
        desc.storageMode = .shared
        guard let tex = device.makeTexture(descriptor: desc) else { return nil }
        bytes.data.withUnsafeBytes { raw in
            tex.replace(region: MTLRegionMake2D(0, 0, bytes.width, bytes.height), mipmapLevel: 0,
                        withBytes: raw.baseAddress!, bytesPerRow: bytes.width * 8)
        }
        return tex
    }

    /// Generate a Hosek-Wilkie procedural sky directly as a mipmapped equirect *texture* on the
    /// given (frame) command buffer, plus its average luminance for auto-exposure. The
    /// per-channel sky coefficients are cooked once on the CPU (the vendored model, the step
    /// that reads its dataset); a fullscreen pass then fills the equirect on the GPU. Crucially
    /// there's no CPU round-trip: the texture feeds the cube / irradiance / prefilter bake on the
    /// same command buffer, and the average is integrated analytically from the same coefficients
    /// (a cheap CPU sphere sum), so an animated sun re-bakes entirely on the GPU with no stall.
    /// 1024x512 is ample for the lighting and a smooth backdrop.
    private func generateSkyEquirectTexture(turbidity: Double, sunElevation: Double,
                                            groundAlbedo: Double, commandBuffer cb: MTLCommandBuffer)
        -> (texture: MTLTexture, avgLuminance: Float)? {
        let width = 1024, height = 512
        let turb = min(max(turbidity, 1), 10)
        let albedo = min(max(groundAlbedo, 0), 1)
        let elevation = min(max(sunElevation, 0.001), Double.pi / 2 - 0.001)
        var configs = [Double](repeating: 0, count: 27)
        var radiances = [Double](repeating: 0, count: 3)
        configs.withUnsafeMutableBufferPointer { cp in
            radiances.withUnsafeMutableBufferPointer { rp in
                ollin_hosek_rgb_configs(turb, albedo, elevation, cp.baseAddress, rp.baseAddress)
            }
        }
        // Pack 11 float4s (see ollin_ibl_sky_gen): 9 coefficient rows (rgb = the R/G/B value of
        // coefficient i), the per-channel radiance + ground albedo, the sun direction + radius.
        var sky = [SIMD4<Float>](repeating: .zero, count: 11)
        for i in 0..<9 {
            sky[i] = SIMD4<Float>(Float(configs[i]), Float(configs[9 + i]), Float(configs[18 + i]), 0)
        }
        sky[9] = SIMD4<Float>(Float(radiances[0]), Float(radiances[1]), Float(radiances[2]), Float(albedo))
        // The sun rises in a fixed compass direction (+Z), raised by its elevation; rotated(_:) spins it.
        let solarRadius: Float = 0.0255   // ~1.5 deg disc, a touch wider than the sun for visible reflections
        let sunDir = SIMD3<Float>(0, Float(sin(elevation)), Float(cos(elevation)))
        sky[10] = SIMD4<Float>(sunDir.x, sunDir.y, sunDir.z, solarRadius)

        // Render the sky equirect on the frame's command buffer (no read-back), mipmapped so the
        // cube bake and the skybox blur sample valid levels (makeEnvCube generates the mips).
        let desc = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rgba16Float,
                                                            width: width, height: height, mipmapped: true)
        desc.usage = [.renderTarget, .shaderRead]
        desc.storageMode = .private
        guard let tex = device.makeTexture(descriptor: desc),
              let pipe = try? pipeline(.ibl("ollin_ibl_sky_gen")) else { return nil }
        let rp = MTLRenderPassDescriptor()
        rp.colorAttachments[0].texture = tex
        rp.colorAttachments[0].loadAction = .dontCare
        rp.colorAttachments[0].storeAction = .store
        guard let enc = cb.makeRenderCommandEncoder(descriptor: rp) else { return nil }
        enc.setRenderPipelineState(pipe)
        enc.setFragmentBytes(&sky, length: sky.count * MemoryLayout<SIMD4<Float>>.stride, index: 0)
        enc.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        enc.endEncoding()
        let avg = Self.skyAverageLuminance(configs: configs, radiances: radiances,
                                           albedo: albedo, sunDir: sunDir)
        return (tex, avg)
    }

    /// The solid-angle-weighted average luminance of the procedural sky, integrated on the CPU
    /// from the Hosek-Wilkie coefficients over a coarse sphere (the same upper-hemisphere-sky /
    /// lower-hemisphere-ground-bounce split the shader uses), so auto-exposure needs no GPU
    /// read-back. Coarse is fine: it only sets the exposure scale.
    nonisolated private static func skyAverageLuminance(configs: [Double], radiances: [Double],
                                                        albedo: Double, sunDir: SIMD3<Float>) -> Float {
        func radiance(_ cosTheta: Double, _ gamma: Double, _ c: Int) -> Double {
            let b = c * 9
            let A = configs[b], B = configs[b + 1], C = configs[b + 2], D = configs[b + 3], E = configs[b + 4]
            let F = configs[b + 5], G = configs[b + 6], H = configs[b + 7], I = configs[b + 8]
            let cg = cos(gamma)
            let mieM = (1 + cg * cg) / pow(max(1 + I * I - 2 * I * cg, 1e-4), 1.5)
            let zenith = cosTheta > 0 ? sqrt(cosTheta) : 0
            let v = (1 + A * exp(B / (cosTheta + 0.01)))
                  * (C + D * exp(E * gamma) + F * cg * cg + G * mieM + H * zenith)
            return max(v, 0) * radiances[c]
        }
        let sx = Double(sunDir.x), sy = Double(sunDir.y), sz = Double(sunDir.z)
        let rows = 32, cols = 16   // coarse: it only sets the exposure scale, and runs per re-bake
        var lumSum = 0.0, weightSum = 0.0
        for y in 0..<rows {
            let lat = (Double(y) + 0.5) / Double(rows) * Double.pi   // 0 top .. pi bottom
            let rowWeight = sin(lat)
            var rowLum = 0.0
            for x in 0..<cols {
                let lon = (Double(x) + 0.5) / Double(cols) * 2 * Double.pi
                var dy = cos(lat)
                let dxz = sin(lat)
                let dx = dxz * cos(lon), dz = dxz * sin(lon)
                var ground = 1.0
                if dy < 0 { dy = -dy; ground = albedo }              // ground = dimmed mirror sky
                let gamma = acos(max(-1, min(1, dx * sx + dy * sy + dz * sz)))
                rowLum += (0.2126 * radiance(dy, gamma, 0)
                         + 0.7152 * radiance(dy, gamma, 1)
                         + 0.0722 * radiance(dy, gamma, 2)) * ground
            }
            lumSum += rowLum / Double(cols) * rowWeight
            weightSum += rowWeight
        }
        return weightSum > 0 ? Float(lumSum / weightSum) : 1
    }

    func makeCubeTexture(face size: Int, mipped: Bool) -> MTLTexture? {
        let desc = MTLTextureDescriptor.textureCubeDescriptor(pixelFormat: .rgba16Float,
                                                              size: size, mipmapped: mipped)
        desc.usage = [.renderTarget, .shaderRead]
        desc.storageMode = .private
        return device.makeTexture(descriptor: desc)
    }

    /// Render one fullscreen-triangle bake pass into a cube face (slice) at a mip level.
    private func bakeIBLFace(pipeline: MTLRenderPipelineState, inputs: [MTLTexture],
                             output: MTLTexture, slice: Int, level: Int,
                             params: SIMD4<Float>, commandBuffer cb: MTLCommandBuffer) {
        let rp = MTLRenderPassDescriptor()
        rp.colorAttachments[0].texture = output
        rp.colorAttachments[0].slice = slice
        rp.colorAttachments[0].level = level
        rp.colorAttachments[0].loadAction = .dontCare
        rp.colorAttachments[0].storeAction = .store
        guard let enc = cb.makeRenderCommandEncoder(descriptor: rp) else { return }
        enc.setRenderPipelineState(pipeline)
        for (i, t) in inputs.enumerated() { enc.setFragmentTexture(t, index: i) }
        var p = params
        enc.setFragmentBytes(&p, length: MemoryLayout<SIMD4<Float>>.stride, index: 0)
        enc.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        enc.endEncoding()
    }

    /// Bake the environment-independent BRDF integration LUT once (the split-sum scale/bias).
    private func ensureBRDFLUT(commandBuffer cb: MTLCommandBuffer) {
        guard iblBRDFLUT == nil else { return }
        let desc = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rg16Float,
                                                            width: Self.iblBRDFSize,
                                                            height: Self.iblBRDFSize, mipmapped: false)
        desc.usage = [.renderTarget, .shaderRead]
        desc.storageMode = .private
        guard let lut = device.makeTexture(descriptor: desc),
              let pipe = try? pipeline(.ibl("ollin_ibl_brdf_lut", color: .rg16Float)) else { return }
        let rp = MTLRenderPassDescriptor()
        rp.colorAttachments[0].texture = lut
        rp.colorAttachments[0].loadAction = .dontCare
        rp.colorAttachments[0].storeAction = .store
        guard let enc = cb.makeRenderCommandEncoder(descriptor: rp) else { return }
        enc.setRenderPipelineState(pipe)
        enc.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        enc.endEncoding()
        iblBRDFLUT = lut
    }

    /// Bake the sheen directional-albedo LUT once, the first frame whose batches carry a
    /// sheen material. Environment-independent like the BRDF LUT, but a sheen surface
    /// needs it under plain lights too, so it triggers off the frame's materials rather
    /// than the environment bake. A frame with no sheen (or one already baked) is a no-op.
    func ensureSheenLUT(for drawer: Drawer, commandBuffer cb: MTLCommandBuffer) {
        guard sheenLUT == nil,
              drawer.batches.contains(where: {
                  $0.finish.sheenColor.x + $0.finish.sheenColor.y + $0.finish.sheenColor.z > 0
              }) else { return }
        let desc = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .r16Float,
                                                            width: Self.sheenLUTSize,
                                                            height: Self.sheenLUTSize, mipmapped: false)
        desc.usage = [.renderTarget, .shaderRead]
        desc.storageMode = .private
        guard let lut = device.makeTexture(descriptor: desc),
              let pipe = try? pipeline(.ibl("ollin_ibl_sheen_lut", color: .r16Float)) else { return }
        let rp = MTLRenderPassDescriptor()
        rp.colorAttachments[0].texture = lut
        rp.colorAttachments[0].loadAction = .dontCare
        rp.colorAttachments[0].storeAction = .store
        guard let enc = cb.makeRenderCommandEncoder(descriptor: rp) else { return }
        enc.setRenderPipelineState(pipe)
        enc.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        enc.endEncoding()
        sheenLUT = lut
    }

    /// The processed equirect pixels for a `.resource`/`.url` env: a cached blob if present (a
    /// fast read, no decode), else decode the source HDRI and (for a `.url`) write the blob
    /// so the next launch skips the decode. CPU-only, so it can run off the render thread.
    nonisolated fileprivate static func loadEquirectBytes(_ env: Environment) -> EquirectBytes? {
        let sourceFile: URL? = {
            if case .url(let file) = env.source { return file }
            return nil   // a bundled .resource decodes fast and its EXR is compact: skip the blob
        }()
        let blobURL = sourceFile.map { EnvironmentCache.shared.equirectBlobFile(for: $0) }
        if let blobURL, let sourceFile, let bytes = readEquirectBlob(blobURL, source: sourceFile) {
            return bytes
        }
        // A real `.url` decode (blob miss): the heavy step after a download, so note it. A
        // bundled `.resource` decodes fast from a compact EXR, so it stays silent.
        if let sourceFile { print("Ollin: decoding \(EnvironmentCache.displayName(for: sourceFile))…") }
        guard let cg = env.loadEquirectImage(), let bytes = processEquirect(cg) else { return nil }
        if let blobURL, let sourceFile { writeEquirectBlob(bytes, to: blobURL, source: sourceFile) }
        return bytes
    }

    /// The source file's (size, mtime-seconds) stamp carried in the blob header, so a
    /// blob is served only for the exact bytes it was decoded from. Keyed by path alone
    /// the blob would keep serving stale pixels after a user replaces their own
    /// `hdri(path:)` EXR at the same path.
    nonisolated private static func equirectSourceStamp(_ source: URL) -> EquirectStamp {
        let attrs = try? FileManager.default.attributesOfItem(atPath: source.path)
        let size = (attrs?[.size] as? NSNumber)?.uint64Value ?? 0
        let mtime = (attrs?[.modificationDate] as? Date).map { UInt32(clamping: Int($0.timeIntervalSince1970)) } ?? 0
        return EquirectStamp(size: size, mtime: mtime)
    }

    /// Record a source whose decode failed, stamped with the file it failed on, and say
    /// so once per distinct file (the memo keeps both the re-decode and the message from
    /// repeating every frame; a *replaced* broken file gets its own one-time message).
    nonisolated private static func noteEquirectDecodeFailure(
        _ file: URL, memo: OSAllocatedUnfairLock<[Environment.Source: EquirectStamp]>,
        source: Environment.Source) {
        let stamp = equirectSourceStamp(file)
        let fresh = memo.withLock { $0.updateValue(stamp, forKey: source) != stamp }
        if fresh {
            print("Ollin: could not decode \(EnvironmentCache.displayName(for: file)); "
                + "the file is not a readable HDRI (Scripts/clear-caches.sh --environments "
                + "discards a broken download)")
        }
    }

    nonisolated private static let equirectBlobMagic: UInt32 = 0x4F4C4548   // "OLEH"

    /// Decode a linear-HDR equirectangular `CGImage` into `rgba16Float` pixels, clamping any
    /// blown-out (inf/NaN half) texel to the max finite half so a bright sun doesn't propagate
    /// inf through the convolutions, and computing the solid-angle-weighted average luminance
    /// (for auto-exposure: the environments range ~800× in brightness).
    nonisolated private static func processEquirect(_ cg: CGImage) -> EquirectBytes? {
        let w = cg.width, h = cg.height
        guard w > 0, h > 0, let cs = CGColorSpace(name: CGColorSpace.extendedLinearSRGB) else { return nil }
        let bpr = w * 8
        let info = CGBitmapInfo.floatComponents.rawValue | CGBitmapInfo.byteOrder16Little.rawValue
                 | CGImageAlphaInfo.premultipliedLast.rawValue
        guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 16,
                                  bytesPerRow: bpr, space: cs, bitmapInfo: info) else { return nil }
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))
        guard let raw = ctx.data else { return nil }
        let halfs = raw.bindMemory(to: UInt16.self, capacity: w * h * 4)
        let avg = clampAndAverageLuminance(halfs, width: w, height: h)
        return EquirectBytes(data: Data(bytes: raw, count: w * h * 8), width: w, height: h, avg: avg)
    }

    /// Clamp any blown-out (inf/NaN) half to the max finite half (so a bright sun doesn't push
    /// inf through the convolutions) and return the solid-angle-weighted average luminance (rows
    /// near the poles cover less sky), for auto-exposure. Shared by the HDRI decode and the
    /// procedural-sky readback; mutates the pixels in place.
    nonisolated private static func clampAndAverageLuminance(
        _ halfs: UnsafeMutablePointer<UInt16>, width w: Int, height h: Int) -> Float {
        for i in 0..<(w * h * 4) where (halfs[i] & 0x7C00) == 0x7C00 {
            halfs[i] = (halfs[i] & 0x8000) | 0x7BFF
        }
        var lumSum = 0.0, weightSum = 0.0
        for y in 0..<h {
            let rowWeight = Double(sin((Double(y) + 0.5) / Double(h) * Double.pi))
            var rowLum = 0.0
            let row = y * w * 4
            for x in 0..<w {
                let i = row + x * 4
                let r = Float(Float16(bitPattern: halfs[i]))
                let g = Float(Float16(bitPattern: halfs[i + 1]))
                let b = Float(Float16(bitPattern: halfs[i + 2]))
                rowLum += Double(0.2126 * r + 0.7152 * g + 0.0722 * b)
            }
            lumSum += rowLum / Double(w) * rowWeight
            weightSum += rowWeight
        }
        return weightSum > 0 ? Float(lumSum / weightSum) : 1
    }

    /// Write processed equirect pixels to a cache blob (a small header + raw float16 pixels),
    /// best-effort; a failed write just means the next launch re-decodes. Header version 2
    /// carries the source file's size + mtime, checked on read (see `equirectSourceStamp`).
    nonisolated private static func writeEquirectBlob(_ bytes: EquirectBytes, to url: URL, source: URL) {
        let stamp = equirectSourceStamp(source)
        var header: [UInt32] = [equirectBlobMagic, 2, UInt32(bytes.width), UInt32(bytes.height),
                                bytes.avg.bitPattern,
                                UInt32(truncatingIfNeeded: stamp.size),
                                UInt32(truncatingIfNeeded: stamp.size >> 32),
                                stamp.mtime]
        var out = Data(bytes: &header, count: header.count * MemoryLayout<UInt32>.size)
        out.append(bytes.data)
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                 withIntermediateDirectories: true)
        let tmp = url.appendingPathExtension("writing")
        if (try? out.write(to: tmp, options: .atomic)) != nil {
            try? FileManager.default.removeItem(at: url)
            try? FileManager.default.moveItem(at: tmp, to: url)
        }
    }

    /// Read a processed-equirect blob, or nil if absent / corrupt / size-mismatched / decoded
    /// from different source bytes than `source` now holds (any of which falls back to a
    /// fresh decode). Version-1 blobs (no source stamp) are rejected and re-created once.
    nonisolated private static func readEquirectBlob(_ url: URL, source: URL) -> EquirectBytes? {
        let headerSize = 32
        guard let data = try? Data(contentsOf: url, options: .mappedIfSafe), data.count >= headerSize
        else { return nil }
        let header = data.prefix(headerSize).withUnsafeBytes { Array($0.bindMemory(to: UInt32.self)) }
        guard header[0] == equirectBlobMagic, header[1] == 2 else { return nil }
        let w = Int(header[2]), h = Int(header[3]), avg = Float(bitPattern: header[4])
        guard w > 0, h > 0, data.count == headerSize + w * h * 8 else { return nil }
        let stamp = equirectSourceStamp(source)
        let size = UInt64(header[5]) | (UInt64(header[6]) << 32)
        guard size == stamp.size, header[7] == stamp.mtime else { return nil }
        return EquirectBytes(data: data.subdata(in: headerSize..<data.count), width: w, height: h, avg: avg)
    }
}

/// The (size, mtime-seconds) identity of a source HDRI file, carried in the equirect blob
/// header (so a blob is served only for the exact bytes it was decoded from) and in the
/// decode-failure memo (so replacing a broken file retries instead of holding the failure
/// for the session).
struct EquirectStamp: Equatable, Sendable {
    let size: UInt64
    let mtime: UInt32
}

/// Processed equirect float pixels (`rgba16Float`, `width·height·8` bytes) plus the source's
/// solid-angle-weighted average luminance, handed from the decode (possibly off-thread) to
/// the bake. `Sendable` so the off-thread load can return it across the task boundary.
struct EquirectBytes: Sendable {
    let data: Data
    let width: Int
    let height: Int
    let avg: Float
}
