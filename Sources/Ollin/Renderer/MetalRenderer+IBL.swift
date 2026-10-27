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

/// One `iblCache` slot: the baked maps, their approximate GPU footprint (driving the
/// byte-budget eviction), and the resolve tick of their last use (the LRU order).
struct IBLCacheEntry {
    let maps: IBLMaps
    let bytes: Int
    var lastUse: UInt64
}

/// The bake-cache key: an environment's pixels plus, for the procedural sky, the
/// cloudscape baked into them (clouds change every baked map, so they must key the
/// cache; a non-sky source ignores clouds and keys on its source alone, so an HDRI
/// with a stray clouds value never fragments its slot).
struct IBLKey: Hashable {
    let source: Environment.Source
    let clouds: Clouds?
    /// For a `.feed` source, the frame generation the bake was made from (a new
    /// camera/video frame bumps it, so the stale bake stops matching and is evicted).
    /// Always 0 for every other source, so their keys never vary on it.
    var feedGeneration: UInt64 = 0
    /// For a `.sky` source, whether its sun lights the frame (`Drawer.skySunLit`): the
    /// sun's beam then joins the exposure's average and the clear sky's disc leaves the
    /// bake (the light carries the sun and the backdrop draws it), so a sky baked both
    /// ways keys two entries. Always false for every other source.
    var sunLit = false
}

/// The renderer's per-feed record for a `.feed` environment: the frame `Image` it last
/// baked (compared by identity, and *held*, so a freed frame's recycled object address
/// can never read as "unchanged") and the generation its bake key carries.
struct FeedBakeState {
    var image: Image?
    var generation: UInt64 = 0
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
    /// For a procedural sky whose sun lights the scene, the 32 bytes its bake writes
    /// back: the ground's radiance and the sky's level irradiance (its luminance) in the
    /// first float4, and in the second the share of the beam the clouds pass toward the
    /// sun (1 for a clear sky), the raw transmittance, and the horizon fade. Shared
    /// memory the CPU reads once the bake's command buffer has completed; nil for every
    /// other bake.
    let sunReadback: MTLBuffer?
    /// The share of its beam the baked cloudscape passes toward the sun, read off
    /// `sunReadback` when the bake completes (from its command buffer's completion, so
    /// a window reads it a frame late; a headless frame waits for it). Nil until then.
    let sunTransmittance = OSAllocatedUnfairLock<Float?>(initialState: nil)

    init(irradiance: MTLTexture, prefilter: MTLTexture, envCube: MTLTexture,
         equirect: MTLTexture?, maxMip: Int, normalization: Float, sunReadback: MTLBuffer? = nil) {
        self.irradiance = irradiance
        self.prefilter = prefilter
        self.envCube = envCube
        self.equirect = equirect
        self.maxMip = maxMip
        self.normalization = normalization
        self.sunReadback = sunReadback
    }

    /// Read the sun's share off the readback, once its command buffer has completed.
    func readSunTransmittance() {
        guard let sunReadback else { return }
        let share = sunReadback.contents().load(fromByteOffset: 16, as: Float.self)
        sunTransmittance.withLock { $0 = share }
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
    private static let iblTargetLuminance: Float = SkySun.targetLuminance   // auto-exposure target average
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
    /// `sunLit` is the frame's word on whether a `.sky` environment's sun lights it
    /// (`Drawer.skySunLit`); the placeholder a download shows meanwhile never is.
    func resolveIBL(for environment: Environment?, sunLit: Bool = false,
                    commandBuffer cb: MTLCommandBuffer, blocking: Bool = false) -> Bool {
        iblResolveTick += 1
        defer { pruneStaleEquirects() }
        guard let environment else { currentIBL = nil; return false }
        let (primary, placeholder) = resolveEnvironmentSources(environment, blocking: blocking)
        // Bake the requested environment once its pixels are ready; until then (a heavy HDRI
        // still downloading, or decoding off-thread) show the bundled placeholder, so the
        // scene is never unlit and the live window never blocks on the decode.
        if let primary, let maps = bakeReady(primary, sunLit: sunLit, blocking: blocking,
                                             commandBuffer: cb) {
            currentIBL = maps; return true
        }
        if let placeholder, let maps = bakeReady(placeholder, sunLit: false, blocking: false,
                                                 commandBuffer: cb) {
            currentIBL = maps; return true
        }
        currentIBL = nil; return false
    }

    /// Bake (or reuse) the IBL maps for an already-resolved `.resource`/`.url` environment, or
    /// nil when its equirect isn't decoded yet (a heavy `.url` decodes off-thread). Cached by
    /// source so the bake runs once; the raw float pixels are freed once baked into textures.
    private func bakeReady(_ env: Environment, sunLit: Bool, blocking: Bool,
                           commandBuffer cb: MTLCommandBuffer) -> IBLMaps? {
        // A live feed bakes on its own path (a per-feed generation keys its cache
        // entries), so the HDRI/sky path below never sees a feed.
        if case .feed(let feedID) = env.source {
            return bakeFeed(env, feedID: feedID, commandBuffer: cb)
        }
        // A static sky (or an HDRI) keys on its exact source (clouds included, for the
        // sky), so it bakes once and then reuses the cache every frame. An animated sky
        // is a fresh key each frame, so it re-bakes entirely on the GPU (no CPU
        // read-back), which a smoothly moving sun or a drifting cloudscape needs.
        let isSkySource = { if case .sky = env.source { return true } else { return false } }()
        let key = IBLKey(source: env.source, clouds: isSkySource ? env.clouds : nil,
                         sunLit: isSkySource && sunLit)
        if env.clouds != nil, !isSkySource {
            let fresh = Self.warnedCloudsOnHDRI.withLock { warned in
                warned ? false : { warned = true; return true }()
            }
            if fresh { print("Ollin: clouds apply to the procedural .sky environment only; an HDRI's clouds are already in its pixels") }
        }
        if var entry = iblCache[key] {
            entry.lastUse = iblResolveTick
            iblCache[key] = entry
            return entry.maps
        }

        let loaded: MTLTexture, avg: Float
        var prescale: Float = 1
        let isSky: Bool
        var sunReadback: MTLBuffer? = nil
        if case .sky(let t, let e, let a) = env.source {
            guard let sky = generateSkyEquirectTexture(turbidity: t, sunElevation: e,
                                                       groundAlbedo: a, clouds: key.clouds,
                                                       sunLit: key.sunLit,
                                                       commandBuffer: cb) else { return nil }
            (loaded, avg) = (sky.texture, sky.avgLuminance)
            sunReadback = sky.readback
            isSky = true
        } else {
            guard let bytes = equirectBytes(for: env, blocking: blocking),
                  let tex = uploadEquirect(bytes) else { return nil }
            (loaded, avg) = (tex, bytes.avg)
            prescale = bytes.prescale
            equirectReady.withLock { $0[env.source] = nil }
            isSky = false
        }
        guard let maps = bakeIBL(env, equirectTexture: loaded, avgLuminance: avg,
                                 prescale: prescale, fastSky: isSky, sunReadback: sunReadback,
                                 commandBuffer: cb) else { return nil }
        if let sunReadback {
            // The sun's share lands when the GPU has finished the bake: off the main
            // actor, so the handler touches the lock alone (the buffer is kept alive by
            // the capture, since the entry holding it may be evicted first).
            nonisolated(unsafe) let readback = sunReadback
            let landed = maps.sunTransmittance
            cb.addCompletedHandler { _ in
                let share = readback.contents().load(fromByteOffset: 16, as: Float.self)
                landed.withLock { $0 = share }
            }
        }
        // An animated sky makes a fresh key each frame; drop the previous sky bake so its GPU
        // textures don't accumulate over the animation (a static sky keeps its one entry).
        if isSky {
            for k in iblCache.keys where k != key {
                if case .sky = k.source { iblCache[k] = nil }
            }
        }
        let bytes = Self.textureFootprint(maps.irradiance) + Self.textureFootprint(maps.prefilter)
            + Self.textureFootprint(maps.envCube) + Self.textureFootprint(maps.equirect)
        iblCache[key] = IBLCacheEntry(maps: maps, bytes: bytes, lastUse: iblResolveTick)
        evictIBLOverBudget(keeping: key)
        return maps
    }

    /// Once-only note for a clouds value on a non-sky environment (ignored by design).
    private static let warnedCloudsOnHDRI = OSAllocatedUnfairLock(initialState: false)

    /// Bake (or reuse) the IBL maps for a `.feed` environment: the feed's latest frame,
    /// wrapped into an equirect on the GPU and run through the reduced-budget convolution
    /// the animated sky uses. The bake key carries a per-feed generation that bumps when
    /// a new frame arrives, so an unchanged frame reuses its bake for free and a new one
    /// re-bakes (the stale generation is evicted below, the animated-sky discipline). A
    /// GPU-backed frame (a live texture updated in place) can't signal newness by
    /// identity, so it re-bakes every resolve, the animated sky's own per-frame cost.
    /// Returns nil (the placeholder sky lights the scene) until the first frame arrives
    /// or once the feed has deallocated.
    private func bakeFeed(_ env: Environment, feedID: Int,
                          commandBuffer cb: MTLCommandBuffer) -> IBLMaps? {
        guard let feed = FeedEnvironments.feed(for: feedID),
              let frame = feed.frame,
              let frameTexture = frame.texture(for: device) else { return nil }
        var state = feedBakeStates[feedID] ?? FeedBakeState()
        if frame.hasCPUPixels {
            if state.image !== frame {
                state.generation &+= 1
                state.image = frame
            }
        } else {
            state.generation &+= 1
            state.image = frame
        }
        feedBakeStates[feedID] = state
        let key = IBLKey(source: env.source, clouds: nil, feedGeneration: state.generation)
        if var entry = iblCache[key] {
            entry.lastUse = iblResolveTick
            iblCache[key] = entry
            return entry.maps
        }
        // Auto-exposure stays at exactly 1 for a feed (the target average IS the
        // average passed): a camera exposes itself, and reading the frame's pixels
        // back for a real average would be a per-bake CPU copy of every frame.
        guard let equirect = generateFeedEquirectTexture(from: frameTexture, commandBuffer: cb),
              let maps = bakeIBL(env, equirectTexture: equirect,
                                 avgLuminance: Self.iblTargetLuminance,
                                 fastSky: true, commandBuffer: cb) else { return nil }
        for k in iblCache.keys where k != key {
            if case .feed(let kid) = k.source, kid == feedID { iblCache[k] = nil }
        }
        let bytes = Self.textureFootprint(maps.irradiance) + Self.textureFootprint(maps.prefilter)
            + Self.textureFootprint(maps.envCube) + Self.textureFootprint(maps.equirect)
        iblCache[key] = IBLCacheEntry(maps: maps, bytes: bytes, lastUse: iblResolveTick)
        evictIBLOverBudget(keeping: key)
        return maps
    }

    /// Wrap a feed frame into a mipmapped equirect texture on the frame's command buffer
    /// (`ollin_ibl_feed_gen`): the picture covers the front hemisphere, its mirror the
    /// back, pinched to its center column at the poles, so the wrap is continuous
    /// everywhere and the rest of the IBL bake runs on it exactly as on a loaded HDRI.
    /// No CPU round-trip, the procedural sky's own rule.
    private func generateFeedEquirectTexture(from frameTexture: MTLTexture,
                                             commandBuffer cb: MTLCommandBuffer) -> MTLTexture? {
        let width = 1024, height = 512
        let desc = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rgba16Float,
                                                            width: width, height: height,
                                                            mipmapped: true)
        desc.usage = [.renderTarget, .shaderRead]
        desc.storageMode = .private
        guard let tex = device.makeTexture(descriptor: desc),
              let pipe = try? pipeline(.ibl("ollin_ibl_feed_gen")) else { return nil }
        let rp = MTLRenderPassDescriptor()
        rp.colorAttachments[0].texture = tex
        rp.colorAttachments[0].loadAction = .dontCare
        rp.colorAttachments[0].storeAction = .store
        guard let enc = countedEncoder(cb, rp) else { return nil }
        enc.setRenderPipelineState(pipe)
        enc.setFragmentTexture(frameTexture, index: 0)
        enc.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        enc.endEncoding()
        return tex
    }

    /// The baked-map budget: enough for a handful of high-resolution environments (a 4K
    /// HDRI's maps are ~85 MB, an 8K's ~270 MB) while keeping a gallery that cycles many
    /// of them bounded. Past it, the least-recently-used entries go; an evicted source
    /// re-bakes from its cached disk blob, so the cost of a wrong eviction is small.
    private static let iblCacheBudgetBytes = 512 << 20

    /// Evict least-recently-used baked maps until the cache fits the budget, never
    /// touching `current` (the key just baked or reused for this frame).
    private func evictIBLOverBudget(keeping current: IBLKey) {
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
        case .feed:
            // Generated on the GPU from the feed's latest frame when baked; until the
            // first frame arrives (camera permission pending, a video still opening),
            // the neutral sky lights the scene, the remote-download discipline.
            return (env, with(Self.skyPlaceholderSource))
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
        case .sky, .remote, .feed:
            // .sky and .feed are generated as textures directly in bakeReady (no CPU
            // pixels); .remote was resolved to a cached .url or a placeholder first.
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
        guard let url = OllinResources.bundle.url(forResource: "ltc_tables", withExtension: "bin",
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

    /// Upload the frame's distinct decal images (from `Drawer.usedDecals`, the
    /// `params.x` layer order) into an sRGB `texture2d_array`; each `Decal`
    /// already resampled itself to the shared square at init, so a layer is one
    /// byte copy. Same fresh-texture cache discipline as the cookies.
    func ensureDecalArray(_ decals: [Decal]) -> Bool {
        guard !decals.isEmpty else { return false }
        let key = decals.map(\.contentHash)
        if key == decalArrayKey, decalArrayTexture != nil { return true }
        let side = Decal.resolution
        let desc = MTLTextureDescriptor()
        desc.textureType = .type2DArray
        desc.pixelFormat = .rgba8Unorm_srgb
        desc.width = side
        desc.height = side
        desc.arrayLength = decals.count
        desc.usage = .shaderRead
        desc.storageMode = .shared
        guard let texture = device.makeTexture(descriptor: desc) else { return false }
        for (layer, decal) in decals.enumerated() {
            decal.pixels.withUnsafeBytes { raw in
                texture.replace(region: MTLRegionMake2D(0, 0, side, side), mipmapLevel: 0,
                                slice: layer, withBytes: raw.baseAddress!,
                                bytesPerRow: side * 4, bytesPerImage: side * side * 4)
            }
        }
        decalArrayTexture = texture
        decalArrayKey = key
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
                         avgLuminance: Float, prescale: Float = 1, fastSky: Bool = false,
                         sunReadback: MTLBuffer? = nil,
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
        // night or a blinding noon stays sane), applied to the lighting and the skybox. A
        // decoded map whose brightest texel was scaled down to fit half range (`prescale`)
        // is scaled back up here, outside the clamp: a unit restored, not an exposure.
        let exposure = SkySun.exposure(average: avgLuminance)
        let normalization = exposure / max(prescale, 1e-6)
        return IBLMaps(irradiance: irradiance, prefilter: prefilter, envCube: envCube,
                       equirect: env.equirect, maxMip: mips - 1, normalization: normalization,
                       sunReadback: sunReadback)
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
    /// 1024x512 is ample for the lighting and a smooth backdrop. When the sun lights the
    /// scene (`sunLit`), a clear sky leaves its disc out (the directional light carries the
    /// sun's energy and the backdrop draws the disc itself, at the sun's own size, which a
    /// texel this coarse could not hold) and the beam joins the average the exposure is
    /// set from; a cloudy sky keeps its disc, which the clouds in front of it dim. A
    /// sun-lit sky's lower hemisphere is the sunlit ground rather than the sky's dimmed
    /// mirror: one matte radiance, the albedo times the level irradiance of sky and beam
    /// over pi, with the sky's half reduced off the baked upper hemisphere by a kernel
    /// (so a cloudy sky's ground is lit by the cloudy sky); under a cloudscape a third
    /// kernel marches the shell toward the sun and writes the beam's share through it.
    /// Both land in `readback`, shared memory the CPU reads once the buffer completes.
    private func generateSkyEquirectTexture(turbidity: Double, sunElevation: Double,
                                            groundAlbedo: Double, clouds: Clouds?,
                                            sunLit: Bool,
                                            commandBuffer cb: MTLCommandBuffer)
        -> (texture: MTLTexture, avgLuminance: Float, readback: MTLBuffer?)? {
        // A cloudy sky doubles the bake resolution: the clouds ARE the backdrop's
        // content, and 1K spreads a formation over too few texels to keep its billows.
        let width = clouds == nil ? 1024 : 2048
        let height = width / 2
        let turb = min(max(turbidity, 1), 10)
        let albedo = min(max(groundAlbedo, 0), 1)
        let elevation = min(max(sunElevation, 0.001), Double.pi / 2 - 0.001)
        let (configs, radiances) = SkySun.configurations(turbidity: turb, albedo: albedo,
                                                         elevation: elevation)
        // Pack 14 float4s (see ollin_ibl_sky_gen): 9 coefficient rows (rgb = the R/G/B value of
        // coefficient i), the per-channel radiance + ground albedo, the sun direction + radius,
        // the cloudscape's two rows (zero for a clear sky; read only by the clouds twin), and
        // the sun-lit ground's row.
        var sky = [SIMD4<Float>](repeating: .zero, count: 14)
        let sun = SkySun(turbidity: turb, elevation: elevation, groundAlbedo: albedo)
        for i in 0..<9 {
            sky[i] = SIMD4<Float>(Float(configs[i]), Float(configs[9 + i]), Float(configs[18 + i]), 0)
        }
        sky[9] = SIMD4<Float>(Float(radiances[0]), Float(radiances[1]), Float(radiances[2]), Float(albedo))
        // The sun rises in a fixed compass direction (+Z), raised by its elevation; rotated(_:) spins it.
        // A radius of 0 draws no disc (a clear sky whose sun lights the scene).
        let drawsDisc = !(sunLit && clouds == nil)
        let solarRadius: Float = drawsDisc ? 0.0255 : 0   // ~1.5 deg disc, a touch wider than the sun for visible reflections
        let sunDir = SkySun.bakedDirection(elevation: elevation)
        sky[10] = SIMD4<Float>(sunDir.x, sunDir.y, sunDir.z, solarRadius)
        var noise: (base: MTLTexture, detail: MTLTexture)?
        if let clouds {
            sky[11] = SIMD4<Float>(Float(clouds.coverage), Float(clouds.density),
                                   Float(clouds.scale), Float(clouds.phase))
            sky[12] = SIMD4<Float>(Float(clouds.tallness), 0, 0, 0)
            noise = ensureCloudNoise(commandBuffer: cb)
        }
        if sunLit {
            // The beam on level ground, the clouds' expected share of it: what the ground
            // kernel adds to the sky's irradiance. The flag turns the generators' mirror off.
            let level = sun.levelBeam(coverage: clouds?.coverage)
            sky[13] = SIMD4<Float>(Float(level.x), Float(level.y), Float(level.z), 1)
        }

        // Render the sky equirect on the frame's command buffer (no read-back), mipmapped so the
        // cube bake and the skybox blur sample valid levels (makeEnvCube generates the mips).
        let desc = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rgba16Float,
                                                            width: width, height: height, mipmapped: true)
        desc.usage = [.renderTarget, .shaderRead, .shaderWrite]   // the ground kernel writes the lower half
        desc.storageMode = .private
        let fragment = (clouds != nil && noise != nil) ? "ollin_ibl_sky_gen_clouds"
                                                       : "ollin_ibl_sky_gen"
        guard let tex = device.makeTexture(descriptor: desc),
              let pipe = try? pipeline(.ibl(fragment)) else { return nil }
        let rp = MTLRenderPassDescriptor()
        rp.colorAttachments[0].texture = tex
        rp.colorAttachments[0].loadAction = .dontCare
        rp.colorAttachments[0].storeAction = .store
        guard let enc = countedEncoder(cb, rp) else { return nil }
        enc.setRenderPipelineState(pipe)
        enc.setFragmentBytes(&sky, length: sky.count * MemoryLayout<SIMD4<Float>>.stride, index: 0)
        if let noise {
            enc.setFragmentTexture(noise.base, index: 0)
            enc.setFragmentTexture(noise.detail, index: 1)
        }
        enc.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        enc.endEncoding()
        var avg = SkySun.averageLuminance(configs: configs, radiances: radiances,
                                          albedo: albedo, sunDir: sunDir)
        var readback: MTLBuffer? = nil
        if sunLit {
            // The beam's share, the same sum `SkySun.exposure(sunLit:coverage:)` makes, so
            // the drawer's light and this bake agree on one exposure to the last bit.
            avg = sun.litAverage(coverage: clouds?.coverage)
            // The ground, then the cloud before the sun, into 32 bytes of shared memory.
            // A clear sky's share is 1 and is written here, since no kernel writes it.
            guard let buffer = device.makeBuffer(length: 2 * MemoryLayout<SIMD4<Float>>.stride,
                                                 options: .storageModeShared),
                  let reduce = try? libraryComputePipeline("ollin_ibl_sky_ground_reduce"),
                  let fill = try? libraryComputePipeline("ollin_ibl_sky_ground_fill"),
                  let compute = cb.makeComputeCommandEncoder() else { return nil }
            buffer.contents().storeBytes(of: SIMD4<Float>(0, 0, 0, 0), as: SIMD4<Float>.self)
            buffer.contents().storeBytes(of: SIMD4<Float>(1, 1, 0, 0), toByteOffset: 16, as: SIMD4<Float>.self)
            compute.setComputePipelineState(reduce)
            compute.setTexture(tex, index: 0)
            compute.setBytes(&sky, length: sky.count * MemoryLayout<SIMD4<Float>>.stride, index: 0)
            compute.setBuffer(buffer, offset: 0, index: 1)
            compute.dispatchThreadgroups(MTLSize(width: 1, height: 1, depth: 1),
                                         threadsPerThreadgroup: MTLSize(width: 256, height: 1, depth: 1))
            compute.setComputePipelineState(fill)
            compute.setTexture(tex, index: 0)
            compute.setBuffer(buffer, offset: 0, index: 0)
            compute.dispatchThreads(MTLSize(width: width, height: height / 2, depth: 1),
                                    threadsPerThreadgroup: MTLSize(width: 16, height: 16, depth: 1))
            if let noise, let transmittance = try? libraryComputePipeline("ollin_ibl_sky_sun_transmittance") {
                compute.setComputePipelineState(transmittance)
                compute.setBytes(&sky, length: sky.count * MemoryLayout<SIMD4<Float>>.stride, index: 0)
                compute.setBuffer(buffer, offset: 0, index: 1)
                compute.setTexture(noise.base, index: 0)
                compute.setTexture(noise.detail, index: 1)
                compute.dispatchThreads(MTLSize(width: 1, height: 1, depth: 1),
                                        threadsPerThreadgroup: MTLSize(width: 1, height: 1, depth: 1))
            }
            compute.endEncoding()
            readback = buffer
        }
        return (tex, avg, readback)
    }

    /// Hand the drawer the share of the sun's beam the frame's cloudscape passes toward
    /// the sun, before anything packs the frame's lights: the value the bake of this
    /// frame's sky wrote back. A window reads what the last completed bake landed (a
    /// frame late, nil on the first frame, when the drawer keeps the clouds' expected
    /// share); a headless frame bakes the sky on a command buffer of its own and waits,
    /// so an export's first frame and a single image read the exact share. The bake is
    /// cached by its key, so the frame's own resolve afterwards is free. A clear sky, a
    /// sky whose sun is not a light, and every other environment set nothing.
    func syncSkySunTransmittance(_ drawer: Drawer, blocking: Bool) {
        drawer.skySunTransmittance = nil
        guard drawer.skySunLit, let env = drawer.environment, case .sky = env.source,
              env.clouds != nil else { return }
        let key = IBLKey(source: env.source, clouds: env.clouds, sunLit: true)
        if let entry = iblCache[key] {
            if let share = entry.maps.sunTransmittance.withLock({ $0 }) {
                drawer.skySunTransmittance = Double(share)
                return
            }
            guard blocking else { return }
            // Baked on an earlier headless frame, which waited for it: the completion
            // may not have run yet, so read the buffer itself.
            entry.maps.readSunTransmittance()
            drawer.skySunTransmittance = entry.maps.sunTransmittance.withLock { $0 }.map { Double($0) }
            return
        }
        guard blocking, let cb = commandQueue.makeCommandBuffer(),
              let maps = bakeReady(env, sunLit: true, blocking: true, commandBuffer: cb) else { return }
        cb.commit()
        cb.waitUntilCompleted()
        maps.readSunTransmittance()
        drawer.skySunTransmittance = maps.sunTransmittance.withLock { $0 }.map { Double($0) }
    }

    /// The two tiling 3D noise fields the cloud march samples, baked once per process by
    /// two compute dispatches on the frame's command buffer and kept for its lifetime
    /// (the sheen-LUT discipline): a 128-cube base whose red is the billow-carved fog
    /// (the low-frequency lattice noise remapped by the cellular field) with three rising
    /// cellular octaves in gba, and a 32-cube of three cellular octaves that erode edges.
    /// Both are pure functions of a fixed internal lattice (no seed, no clock), so every
    /// bake on every machine samples identical fields and exports reproduce.
    private func ensureCloudNoise(commandBuffer cb: MTLCommandBuffer)
        -> (base: MTLTexture, detail: MTLTexture)? {
        if let t = cloudNoiseTextures { return t }
        guard let baseFn = library.makeFunction(name: "ollin_cloud_noise_base"),
              let detailFn = library.makeFunction(name: "ollin_cloud_noise_detail"),
              let basePipe = try? device.makeComputePipelineState(function: baseFn),
              let detailPipe = try? device.makeComputePipelineState(function: detailFn)
        else { return nil }
        func volume(_ edge: Int) -> MTLTexture? {
            let d = MTLTextureDescriptor()
            d.textureType = .type3D
            d.pixelFormat = .rgba8Unorm    // 0…1 noise; 8 bits is the field's own precision
            d.width = edge; d.height = edge; d.depth = edge
            d.usage = [.shaderRead, .shaderWrite]
            d.storageMode = .private
            return device.makeTexture(descriptor: d)
        }
        guard let base = volume(128), let detail = volume(32),
              let enc = cb.makeComputeCommandEncoder() else { return nil }
        let tg = MTLSize(width: 4, height: 4, depth: 4)
        enc.setComputePipelineState(basePipe)
        enc.setTexture(base, index: 0)
        enc.dispatchThreads(MTLSize(width: 128, height: 128, depth: 128), threadsPerThreadgroup: tg)
        enc.setComputePipelineState(detailPipe)
        enc.setTexture(detail, index: 0)
        enc.dispatchThreads(MTLSize(width: 32, height: 32, depth: 32), threadsPerThreadgroup: tg)
        enc.endEncoding()
        cloudNoiseTextures = (base, detail)
        return (base, detail)
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
        guard let enc = countedEncoder(cb, rp) else { return }
        enc.setRenderPipelineState(pipeline)
        for (i, t) in inputs.enumerated() { enc.setFragmentTexture(t, index: i) }
        var p = params
        enc.setFragmentBytes(&p, length: MemoryLayout<SIMD4<Float>>.stride, index: 0)
        enc.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        enc.endEncoding()
    }

    /// Bake the environment-independent BRDF integration LUT once (the split-sum scale/bias).
    func ensureBRDFLUT(commandBuffer cb: MTLCommandBuffer) {
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
        guard let enc = countedEncoder(cb, rp) else { return }
        enc.setRenderPipelineState(pipe)
        enc.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        enc.endEncoding()
        iblBRDFLUT = lut
    }

    /// Bake the BRDF LUT the first frame whose batches carry a physically-based finish,
    /// environment or not: the microfacet shading reads it for its multiple-scattering
    /// energy compensation (`ollin_pbr_ess`) under plain and area lights too, so a
    /// physically-based fragment must never sample the stand-in strip bound at texture 6.
    /// Same trigger shape as `ensureSheenLUT`; a frame with no such finish (or one
    /// already baked) is a no-op, so 2D frames stay untouched.
    func ensureBRDFLUT(for drawer: Drawer, commandBuffer cb: MTLCommandBuffer) {
        guard iblBRDFLUT == nil,
              drawer.batches.contains(where: { $0.finish.shadingModel == 3 }) else { return }
        ensureBRDFLUT(commandBuffer: cb)
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
        guard let enc = countedEncoder(cb, rp) else { return }
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

    /// Decode a linear-HDR equirectangular `CGImage` into `rgba16Float` pixels. The draw
    /// goes through a single-precision context: a half-float context clamps every
    /// texel past the largest half, 65,504, at the draw, and a sun in a photographed
    /// sky can sit far above that (a sun of 200,000 arrived at a third of its light).
    /// `packEquirect` then brings the map into half range by one factor the renderer
    /// divides back out, and takes the solid-angle-weighted average luminance (for
    /// auto-exposure: the environments range ~800× in brightness).
    nonisolated private static func processEquirect(_ cg: CGImage) -> EquirectBytes? {
        let w = cg.width, h = cg.height
        guard w > 0, h > 0, let cs = CGColorSpace(name: CGColorSpace.extendedLinearSRGB) else { return nil }
        let bpr = w * 16
        let info = CGBitmapInfo.floatComponents.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
                 | CGImageAlphaInfo.premultipliedLast.rawValue
        guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 32,
                                  bytesPerRow: bpr, space: cs, bitmapInfo: info) else { return nil }
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))
        guard let raw = ctx.data else { return nil }
        let floats = raw.bindMemory(to: Float.self, capacity: w * h * 4)
        return packEquirect(floats, width: w, height: h)
    }

    /// Pack single-precision equirect pixels into `rgba16Float` bytes. A component past
    /// the largest half float cannot be stored as it is, so when the brightest finite
    /// one is above that, the whole map is scaled down by one factor, `prescale`, that
    /// brings it exactly to the largest half, and the renderer divides the factor back
    /// out of the map's exposure normalization (`IBLMaps.normalization`); the bake and
    /// the skybox read the scaled texels, and both are linear in them, so the picture
    /// is the one the file holds. A map that fits keeps prescale 1 and its bytes as
    /// before. An infinite or NaN component is clamped to the largest finite half with
    /// its sign (so a sun never pushes inf through the convolutions), and the average
    /// luminance is taken from the true values, weighted by each row's share of the
    /// sphere (rows near the poles cover less sky).
    nonisolated static func packEquirect(_ floats: UnsafePointer<Float>,
                                         width w: Int, height h: Int) -> EquirectBytes {
        let halfMax: Float = 65_504
        var brightest: Float = 0
        for i in 0..<(w * h * 4) where i % 4 != 3 {
            let v = floats[i]
            if v.isFinite { brightest = max(brightest, abs(v)) }
        }
        let prescale: Float = brightest > halfMax ? halfMax / brightest : 1
        var halfs = [UInt16](repeating: 0, count: w * h * 4)
        var lumSum = 0.0, weightSum = 0.0
        func half(_ v: Float) -> UInt16 {
            guard v.isFinite else { return (v.sign == .minus ? 0x8000 : 0) | 0x7BFF }
            return Float16(v * prescale).bitPattern
        }
        for y in 0..<h {
            let rowWeight = Double(sin((Double(y) + 0.5) / Double(h) * Double.pi))
            var rowLum = 0.0
            let row = y * w * 4
            for x in 0..<w {
                let i = row + x * 4
                let r = floats[i], g = floats[i + 1], b = floats[i + 2]
                if r.isFinite, g.isFinite, b.isFinite {
                    rowLum += Double(0.2126 * r + 0.7152 * g + 0.0722 * b)
                } else {
                    rowLum += Double(halfMax)
                }
                halfs[i] = half(r)
                halfs[i + 1] = half(g)
                halfs[i + 2] = half(b)
                halfs[i + 3] = Float16(min(max(floats[i + 3], 0), 1)).bitPattern
            }
            lumSum += rowLum / Double(w) * rowWeight
            weightSum += rowWeight
        }
        let avg = weightSum > 0 ? Float(lumSum / weightSum) : 1
        return EquirectBytes(data: halfs.withUnsafeBytes { Data($0) }, width: w, height: h,
                             avg: avg, prescale: prescale)
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
        var header: [UInt32] = [equirectBlobMagic, 3, UInt32(bytes.width), UInt32(bytes.height),
                                bytes.avg.bitPattern,
                                UInt32(truncatingIfNeeded: stamp.size),
                                UInt32(truncatingIfNeeded: stamp.size >> 32),
                                stamp.mtime, bytes.prescale.bitPattern]
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
    /// fresh decode). Older blobs (version 1 with no source stamp, version 2 with no
    /// prescale, whose pixels were clamped at the largest half) are rejected and
    /// re-created once.
    nonisolated private static func readEquirectBlob(_ url: URL, source: URL) -> EquirectBytes? {
        let headerSize = 36
        guard let data = try? Data(contentsOf: url, options: .mappedIfSafe), data.count >= headerSize
        else { return nil }
        let header = data.prefix(headerSize).withUnsafeBytes { Array($0.bindMemory(to: UInt32.self)) }
        guard header[0] == equirectBlobMagic, header[1] == 3 else { return nil }
        let w = Int(header[2]), h = Int(header[3]), avg = Float(bitPattern: header[4])
        guard w > 0, h > 0, data.count == headerSize + w * h * 8 else { return nil }
        let stamp = equirectSourceStamp(source)
        let size = UInt64(header[5]) | (UInt64(header[6]) << 32)
        guard size == stamp.size, header[7] == stamp.mtime else { return nil }
        let prescale = Float(bitPattern: header[8])
        guard prescale.isFinite, prescale > 0, prescale <= 1 else { return nil }
        return EquirectBytes(data: data.subdata(in: headerSize..<data.count), width: w, height: h,
                             avg: avg, prescale: prescale)
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
/// solid-angle-weighted average luminance and the factor the pixels were scaled down by to
/// fit half range (1 for a map that fit; see `packEquirect`), handed from the decode
/// (possibly off-thread) to the bake. `Sendable` so the off-thread load can return it
/// across the task boundary.
struct EquirectBytes: Sendable {
    let data: Data
    let width: Int
    let height: Int
    let avg: Float
    let prescale: Float
}
