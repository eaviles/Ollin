// MetalRenderer, the subsurface-scattering half: the separable screen-space
// diffusion that turns a `Material.scattering` surface into skin / wax / marble.
// Three passes, encoded between the geometry resolve and the whole-frame filters,
// only when the frame carries a scattering material (else the resolved frame is
// returned untouched, byte-identical):
//
//  1. A scatter-mask pass re-renders the frame's mesh batches (the dedicated
//     re-encode pattern the mesh-normal and reflection G-buffer passes set) into
//     a float mask: the projected blur step in uv units, a mark, the view-space
//     depth, and the material's diffusion-profile index. Every solid mesh draws
//     (depth-tested into the pass's own depth), so an occluder in front of a
//     scattering surface suppresses it; non-scattering meshes write mark 0.
//  2. Two fullscreen passes (`ollin_sss_blur`, horizontal then vertical) convolve
//     the linear pre-tonemap intermediate with a separable diffusion kernel,
//     per-pixel gated by the mask and guarded across depth gaps. Written from the
//     published separable-subsurface-scattering technique (see ATTRIBUTION.md).
//
// The kernel is built on the CPU: a pure, deterministic function of the material's
// falloff color and strength, so exports reproduce and the cache never invalidates.

import Foundation
import Metal
import simd
import COllinShaders

/// A quantized (falloff, strength) diffusion profile: the kernel-cache key, and the
/// per-frame identity that maps each scattering batch to its kernel rows.
struct ScatterProfileKey: Hashable {
    let falloff: SIMD3<UInt32>   // bit patterns of the falloff ratios
    let strength: UInt32         // bit pattern of the strength

    init(falloff: SIMD3<Float>, strength: Float) {
        self.falloff = SIMD3(falloff.x.bitPattern, falloff.y.bitPattern, falloff.z.bitPattern)
        self.strength = strength.bitPattern
    }
}

extension MetalRenderer {

    /// Taps per diffusion kernel (the 1080p-quality count). Kept in step with the
    /// literal loop bound in `ollin_sss_blur`.
    nonisolated static let scatterTapCount = 25

    /// The most distinct diffusion profiles one frame's blur carries (the kernel rows
    /// ride the pass's small params buffer); materials past the cap reuse the last.
    nonisolated static let scatterProfileCap = 8

    /// Build one separable diffusion kernel: `scatterTapCount` rows of (r, g, b
    /// weight, offset), offsets spanning ±3 profile units with the center tap first.
    ///
    /// The construction is the published one: tap offsets importance-distributed
    /// toward the center (sign-kept o² over the range), each weighted by the
    /// trapezoidal area it covers times the diffusion profile there. The profile is
    /// the measured skin reflectance as a sum of Gaussians, one channel's curve
    /// reused for all three and stretched per channel by the `falloff` ratios (which
    /// is what lets one curve serve skin, marble, or any tinted diffusion); the
    /// narrowest term of the published fit is direct bounce, which `strength`
    /// accounts for, so it is dropped. Weights normalize to unit sum per channel and
    /// the un-scattered share folds back into the center tap, so the kernel conserves
    /// energy at any strength: at strength 0 it is exactly the identity.
    nonisolated static func scatterKernel(falloff: SIMD3<Float>, strength: Float) -> [SIMD4<Float>] {
        let n = scatterTapCount
        let range: Float = 3
        var taps = [SIMD4<Float>](repeating: .zero, count: n)

        let step = 2 * range / Float(n - 1)
        for i in 0..<n {
            let o = -range + Float(i) * step
            let sign: Float = o < 0 ? -1 : 1
            taps[i].w = sign * o * o / range
        }

        func profile(_ r: Float) -> SIMD3<Float> {
            let gaussians: [(weight: Float, variance: Float)] = [
                (0.100, 0.0484), (0.118, 0.187), (0.113, 0.567),
                (0.358, 1.99), (0.078, 7.41)]
            var sum = SIMD3<Float>.zero
            for g in gaussians {
                let norm = g.weight / (2 * Float.pi * g.variance)
                for c in 0..<3 {
                    let rr = r / (0.001 + falloff[c])
                    sum[c] += norm * exp(-(rr * rr) / (2 * g.variance))
                }
            }
            return sum
        }

        for i in 0..<n {
            let below = i > 0 ? abs(taps[i].w - taps[i - 1].w) : 0
            let above = i < n - 1 ? abs(taps[i].w - taps[i + 1].w) : 0
            let area = (below + above) / 2
            let t = area * profile(taps[i].w)
            taps[i].x = t.x; taps[i].y = t.y; taps[i].z = t.z
        }

        // The center tap leads (the blur accumulates it unconditionally).
        let center = taps[n / 2]
        for i in stride(from: n / 2, to: 0, by: -1) { taps[i] = taps[i - 1] }
        taps[0] = center

        var sum = SIMD3<Float>.zero
        for t in taps { sum += SIMD3(t.x, t.y, t.z) }
        for i in 0..<n {
            taps[i].x /= sum.x; taps[i].y /= sum.y; taps[i].z /= sum.z
        }
        taps[0].x = (1 - strength) + strength * taps[0].x
        taps[0].y = (1 - strength) + strength * taps[0].y
        taps[0].z = (1 - strength) + strength * taps[0].z
        for i in 1..<n {
            taps[i].x *= strength; taps[i].y *= strength; taps[i].z *= strength
        }
        return taps
    }

    /// Whether a batch is a scattering surface the blur should diffuse: a solid or
    /// textured mesh on the main canvas whose finish asked for it (a matcap bypasses
    /// lighting and material entirely, so it only ever occludes).
    private func batchScatters(_ b: GeometryBatch) -> Bool {
        b.kind == .mesh3D && b.target == nil && !b.meshWireframe && !b.meshGrid
            && b.matcap == nil && b.finish.scatterStrength > 0 && b.finish.scatter.w > 0
    }

    /// Apply the subsurface-scattering diffusion to the resolved linear frame,
    /// returning the texture the frame filters (and then the present pass) should
    /// read: the input itself when the frame carries no scattering material.
    func applySubsurfaceScattering(_ drawer: Drawer, resolved: MTLTexture,
                                   meshBuffer: MTLBuffer?, into cb: MTLCommandBuffer,
                                   width: Int, height: Int, pooled: Bool) -> MTLTexture {
        let batches = drawer.batches
        // Honest degrades, named once: the blur reads the main canvas's mesh mask,
        // so a layer's meshes and the raymarched fields keep their plain shading.
        if batches.contains(where: {
            $0.kind == .mesh3D && $0.target != nil
                && $0.finish.scatterStrength > 0 && $0.finish.scatter.w > 0 }) {
            drawer.noteOnce("Material.scattering applies on the main canvas; a mesh drawn into a render target keeps its unscattered shading.")
        }
        if batches.contains(where: {
            $0.kind == .sdfGroup3D && $0.finish.scatterStrength > 0 && $0.finish.scatter.w > 0 }) {
            drawer.noteOnce("Material.scattering applies to solid and textured meshes; a raymarched SDF field ignores it.")
        }
        guard let camera = drawer.camera3D, let meshBuffer,
              batches.contains(where: { batchScatters($0) }) else { return resolved }

        // Collect the frame's distinct diffusion profiles, in batch order, and the
        // per-batch index into them. Kernels are pure functions of the profile, so
        // they cache across frames.
        var indexByProfile: [ScatterProfileKey: Int] = [:]
        var kernels: [[SIMD4<Float>]] = []
        var batchProfile: [Int: Int] = [:]   // batch index → profile index
        for i in batches.indices where batchScatters(batches[i]) {
            let f = batches[i].finish
            let key = ScatterProfileKey(
                falloff: SIMD3(f.scatter.x, f.scatter.y, f.scatter.z),
                strength: f.scatterStrength)
            if let existing = indexByProfile[key] {
                batchProfile[i] = existing
                continue
            }
            if kernels.count == MetalRenderer.scatterProfileCap {
                drawer.noteOnce("Material.scattering: more than \(MetalRenderer.scatterProfileCap) distinct scattering profiles in one frame; the extras reuse the last one.")
                batchProfile[i] = kernels.count - 1
                continue
            }
            let kernel: [SIMD4<Float>]
            if let cached = scatterKernels[key] {
                kernel = cached
            } else {
                kernel = MetalRenderer.scatterKernel(
                    falloff: SIMD3(f.scatter.x, f.scatter.y, f.scatter.z),
                    strength: f.scatterStrength)
                scatterKernels[key] = kernel
            }
            indexByProfile[key] = kernels.count
            batchProfile[i] = kernels.count
            kernels.append(kernel)
        }

        // The mask + its depth, cached by size (rewritten whole each frame).
        if scatterMaskCache == nil || scatterMaskCache!.w != width || scatterMaskCache!.h != height {
            guard let mask = makeFilterTexture(width: width, height: height),
                  let depth = makeDepthResolve(width: width, height: height) else { return resolved }
            scatterMaskCache = (mask, depth, width, height)
        }
        guard let cache = scatterMaskCache,
              let maskPipe = try? pipeline(.scatterMask(depth: depthPixelFormat)) else { return resolved }

        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = cache.mask
        pass.colorAttachments[0].loadAction = .clear
        pass.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)
        pass.colorAttachments[0].storeAction = .store
        pass.depthAttachment.texture = cache.depth
        pass.depthAttachment.loadAction = .clear
        pass.depthAttachment.clearDepth = 1.0
        pass.depthAttachment.storeAction = .dontCare
        guard let enc = cb.makeRenderCommandEncoder(descriptor: pass) else { return resolved }
        enc.setViewport(MTLViewport(originX: 0, originY: 0, width: Double(width),
                                    height: Double(height), znear: 0, zfar: 1))
        enc.setRenderPipelineState(maskPipe)
        enc.setDepthStencilState(depthTestState)
        var u3 = makeUniforms3D(drawer, camera: camera, viewport: SIMD2(Float(width), Float(height)))
        enc.setVertexBytes(&u3, length: MemoryLayout<Uniforms3D>.stride, index: 2)
        enc.setFragmentBytes(&u3, length: MemoryLayout<Uniforms3D>.stride, index: 2)

        let meshStride = MemoryLayout<OllinMeshVertex>.stride
        let meshCount = drawer.meshVertices.count
        for i in batches.indices {
            let batch = batches[i]
            // Every solid mesh on the canvas rasterizes (an occluder in front of a
            // scattering surface must suppress it); wireframes have no surface and
            // the grid is live chrome, matching the mesh-normal pass's walk.
            guard batch.kind == .mesh3D, batch.target == nil,
                  !batch.meshWireframe, !batch.meshGrid else { continue }
            let next = i + 1 < batches.count ? batches[i + 1] : nil
            let end = next?.meshStart ?? meshCount
            let count = end - batch.meshStart
            guard count > 0 else { continue }
            let scattering = batchProfile[i]
            var params = SIMD4<Float>(scattering != nil ? batch.finish.scatter.w : 0,
                                      scattering != nil ? 1 : 0,
                                      Float(scattering ?? 0), 0)
            enc.setFragmentBytes(&params, length: MemoryLayout<SIMD4<Float>>.stride, index: 0)
            enc.setVertexBuffer(meshBuffer, offset: batch.meshStart * meshStride, index: 0)
            enc.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: count)
        }
        enc.endEncoding()

        // The two separable passes: horizontal into a scratch layer, vertical out.
        // Row 0 carries (direction, ortho flag, aspect), row 1 the projection's
        // [1][1] (the blur un-projects the mask's step back to a world-space radius
        // for its depth-gap guard); the kernels follow, 25 rows per profile,
        // indexed per pixel by the mask.
        guard let horizontal = acquireFilterTexture(width: width, height: height, pooled: pooled),
              let output = acquireFilterTexture(width: width, height: height, pooled: pooled)
        else { return resolved }
        let ortho: Float = u3.projection.columns.3.w == 1 ? 1 : 0
        let aspect = Float(width) / Float(max(1, height))
        var rows: [SIMD4<Float>] = [SIMD4(1, 0, ortho, aspect),
                                    SIMD4(u3.projection.columns.1.y, 0, 0, 0)]
        for kernel in kernels { rows.append(contentsOf: kernel) }
        encodeEffectFragment("ollin_sss_blur", inputs: [resolved, cache.mask],
                             output: horizontal, params: rows, into: cb)
        rows[0] = SIMD4(0, 1, ortho, aspect)
        encodeEffectFragment("ollin_sss_blur", inputs: [horizontal, cache.mask],
                             output: output, params: rows, into: cb)
        return output
    }
}
