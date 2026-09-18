import Foundation
import Metal
import simd
import COllinShaders

// Many lights: the per-tile light grid.
//
// Lighting is forward, which is what keeps the 2D and 3D batches interleaving in
// call order under their own blend modes and what keeps the float-MSAA path whole.
// Forward's cost, though, is that every lit pixel pays for every light in the frame,
// which is why the inline set stops at `OLLIN_MAX_LIGHTS`. Past that count this pass
// divides the render target into `OLLIN_LIGHT_TILE_SIZE` squares and works out, once
// per tile, which lights can reach it. A lit fragment then walks its own tile's list,
// so the cost tracks the lights that actually arrive rather than the lights that
// exist, and nothing about *how* a light shades changes: the grid only decides which
// lights a tile lists.
//
// A frame of eight lights or fewer never runs this (`lighting.sceneLightCount` is 0),
// reads the inline array exactly as it always did, and is byte-identical.
extension MetalRenderer {

    /// What one frame's tiled lighting needs bound: the frame's whole light set and
    /// the per-tile lists the cull wrote, plus the grid the fragments read them by.
    struct LightGrid {
        let lights: MTLBuffer
        let tiles: MTLBuffer
        let count: Int
        let tilesX: Int
        let tilesY: Int
        /// uints per tile: one count word followed by the index capacity.
        let stride: Int
        /// The render target the grid was built over. A pass of another size sees a
        /// different camera view, so it leaves the grid alone and shades inline.
        let width: Int
        let height: Int
    }

    /// The ring/export key for one (frame slot, light set) pair. Negative keys are
    /// the export path's, which has no ring.
    static func gridKey(frame index: Int?, set: Int) -> Int {
        guard let index else { return -1 - set }
        return index * (Drawer.maxScopedLightSets + 1) + set
    }

    /// A never-read one-element buffer for the two light-grid bindings, so the
    /// fragments' declared arguments are always satisfied on an untiled frame (the
    /// `ltcEnabled` stand-in discipline, for buffers).
    func lightStandIn() -> MTLBuffer? {
        if let existing = lightGridStandIn { return existing }
        lightGridStandIn = device.makeBuffer(length: MemoryLayout<OllinLight>.stride,
                                             options: .storageModeShared)
        return lightGridStandIn
    }

    /// Cull the frame's lights into the screen tile grid, ahead of the geometry pass
    /// in the same command buffer. Returns nil for a frame on the inline path (eight
    /// lights or fewer), which is what leaves every binding on the stand-in.
    ///
    /// `frameIndex` selects the ring slot for the live path; nil takes the export
    /// buffers, exactly as the geometry rings do, so a headless render and a window
    /// frame cull the same way.
    func encodeLightCull(_ drawer: Drawer, into commandBuffer: MTLCommandBuffer,
                         renderWidth: Int, renderHeight: Int,
                         frameIndex: Int?) -> LightGrid? {
        currentLightGrids.removeAll(keepingCapacity: true)
        // One cull per light set that outruns the inline array: a set is its own
        // light list, so it is its own cull and its own pair of buffers (the cost
        // the per-set lighting note predicted). A frame with one set runs exactly
        // the one cull it always ran, over the same buffers.
        for set in 0 ... drawer.lightSets.count {
            if let grid = encodeLightCull(drawer, set: set, into: commandBuffer,
                                          renderWidth: renderWidth, renderHeight: renderHeight,
                                          frameIndex: frameIndex) {
                currentLightGrids[set] = grid
            }
        }
        return currentLightGrids[0]
    }

    /// Cull one light set. Returns nil when that set is on the inline path.
    private func encodeLightCull(_ drawer: Drawer, set: Int,
                                 into commandBuffer: MTLCommandBuffer,
                                 renderWidth: Int, renderHeight: Int,
                                 frameIndex: Int?) -> LightGrid? {
        let state = drawer.lightState(forSet: set)
        // The count first, so an ordinary 3D frame does not pack its lights a second
        // time to be told it has few of them.
        guard renderWidth > 0, renderHeight > 0, let camera = drawer.camera3D,
              drawer.activeLights(in: state).count > Int(OLLIN_MAX_LIGHTS) else { return nil }
        let packed = drawer.packedLights(in: state)
        guard packed.count > Int(OLLIN_MAX_LIGHTS) else { return nil }
        guard let cull = try? libraryComputePipeline("ollin_light_cull") else { return nil }

        let tile = Int(OLLIN_LIGHT_TILE_SIZE)
        let tilesX = (renderWidth + tile - 1) / tile
        let tilesY = (renderHeight + tile - 1) / tile
        // Nothing is ever dropped from a tile: the capacity is the whole light set,
        // so a pixel that really does stand under every lamp still shades against
        // every lamp. That is what makes the culled frame provably the same picture
        // as the unculled one.
        let stride = packed.count + 1

        let key = MetalRenderer.gridKey(frame: frameIndex, set: set)
        guard let lights = lightBuffer(at: key, for: packed.count),
              let tiles = lightTileBuffer(at: key, for: tilesX * tilesY * stride) else { return nil }
        packed.withUnsafeBytes { raw in
            lights.contents().copyMemory(from: raw.baseAddress!, byteCount: raw.count)
        }

        // The unjittered view-projection: a sub-pixel jitter is inside the one-pixel
        // margin the kernel grows each tile by.
        let aspect = Double(renderWidth) / Double(renderHeight)
        let vp = camera.viewProjectionMatrix(aspect: aspect)
        var params = OllinLightCullParams()
        params.rowX = SIMD4<Float>(vp.columns.0.x, vp.columns.1.x, vp.columns.2.x, vp.columns.3.x)
        params.rowY = SIMD4<Float>(vp.columns.0.y, vp.columns.1.y, vp.columns.2.y, vp.columns.3.y)
        params.rowZ = SIMD4<Float>(vp.columns.0.z, vp.columns.1.z, vp.columns.2.z, vp.columns.3.z)
        params.rowW = SIMD4<Float>(vp.columns.0.w, vp.columns.1.w, vp.columns.2.w, vp.columns.3.w)
        params.renderSize = SIMD2<Float>(Float(renderWidth), Float(renderHeight))
        params.tilesX = UInt32(tilesX)
        params.tilesY = UInt32(tilesY)
        params.tileSize = UInt32(tile)
        params.lightCount = UInt32(packed.count)
        params.tileStride = UInt32(stride)
        params.culls = drawer.cullsLightTiles ? 1 : 0

        guard let compute = commandBuffer.makeComputeCommandEncoder() else { return nil }
        compute.setComputePipelineState(cull)
        compute.setBuffer(lights, offset: 0, index: 0)
        compute.setBuffer(tiles, offset: 0, index: 1)
        compute.setBytes(&params, length: MemoryLayout<OllinLightCullParams>.stride, index: 2)
        let width = min(cull.threadExecutionWidth, tilesX)
        let height = max(1, min(cull.maxTotalThreadsPerThreadgroup / max(width, 1), tilesY))
        compute.dispatchThreads(MTLSize(width: tilesX, height: tilesY, depth: 1),
                                threadsPerThreadgroup: MTLSize(width: max(width, 1), height: height, depth: 1))
        compute.endEncoding()
        profile.computeDispatches += 1

        return LightGrid(lights: lights, tiles: tiles, count: packed.count,
                         tilesX: tilesX, tilesY: tilesY, stride: stride,
                         width: renderWidth, height: renderHeight)
    }

    /// Turn the tiled path on in a lighting uniform for a pass of this size: which
    /// tile a fragment falls in, how long each tile's list is, and the gate itself.
    /// The renderer owns these rather than the drawer, because the tiles are the
    /// *render target*'s (a temporal upscale renders smaller than the canvas) and the
    /// grid is only valid for the size it was culled over. A pass of another size,
    /// which is a render target with its own proportions and so its own camera view,
    /// falls through to the frame's first `OLLIN_MAX_LIGHTS` rather than reading a
    /// grid built for a picture it isn't drawing.
    func applyLightGrid(to lighting: inout OllinLighting, width: Int, height: Int,
                        set: Int = 0) {
        guard let grid = currentLightGrids[set], grid.width == width, grid.height == height else {
            lighting.sceneLightCount = 0   // nothing bound: every fragment stays inline
            return
        }
        lighting.sceneLightCount = Int32(grid.count)
        lighting.lightTileGrid = SIMD4<Float>(Float(grid.tilesX), Float(grid.tilesY),
                                              1 / Float(max(width, 1)),
                                              1 / Float(max(height, 1)))
        lighting.lightTileStride = Int32(grid.stride)
    }

    /// Bind the grid's two buffers (fragment 8/9) for any pass that shades through the
    /// lit mesh tail. Always bound, real or stand-in, so the fragments' declared
    /// arguments are satisfied whether or not the frame went tiled; the uniform's
    /// `sceneLightCount` is what decides whether they are ever read.
    func bindLightGrid(_ encoder: MTLRenderCommandEncoder, set: Int = 0) {
        let stand = lightStandIn()
        let grid = currentLightGrids[set]
        encoder.setFragmentBuffer(grid?.lights ?? stand, offset: 0, index: 8)
        encoder.setFragmentBuffer(grid?.tiles ?? stand, offset: 0, index: 9)
    }

    /// What the cull decided, tile by tile: each tile's list of light indices, read
    /// back out of the buffer the last `encodeLightCull` filled (so it says anything
    /// only once that command buffer has completed). Nothing in a render reads this;
    /// it is how the tests check that the grid culls, and culls the right lights.
    func lightTileLists(set: Int = 0) -> [[Int]] {
        guard let grid = currentLightGrids[set] else { return [] }
        let words = grid.tiles.contents().bindMemory(to: UInt32.self,
                                                     capacity: grid.tilesX * grid.tilesY * grid.stride)
        return (0 ..< grid.tilesX * grid.tilesY).map { tile in
            let base = tile * grid.stride
            let n = min(Int(words[base]), grid.stride - 1)
            return (0 ..< n).map { Int(words[base + 1 + $0]) }
        }
    }

    /// One set's light buffer at a ring/export key (see `gridKey`).
    private func lightBuffer(at key: Int, for count: Int) -> MTLBuffer? {
        let needed = max(count, 1) * MemoryLayout<OllinLight>.stride
        if let buffer = lightBuffers[key], buffer.length >= needed { return buffer }
        lightBuffers[key] = device.makeBuffer(length: needed + needed / 2, options: .storageModeShared)
        return lightBuffers[key]
    }

    /// The frame's tile-list buffer, sized in uints. Shared storage: the GPU writes it
    /// and the fragments read it in the same frame, and nothing on the CPU reads it
    /// outside the tests that check what the cull decided.
    private func lightTileBuffer(at key: Int, for words: Int) -> MTLBuffer? {
        let needed = max(words, 1) * MemoryLayout<UInt32>.stride
        if let buffer = lightTileBuffers[key], buffer.length >= needed { return buffer }
        lightTileBuffers[key] = device.makeBuffer(length: needed + needed / 2, options: .storageModeShared)
        return lightTileBuffers[key]
    }
}
