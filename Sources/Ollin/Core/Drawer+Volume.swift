import simd

/// One `drawVolume` call as the renderer reads it: the grid, the medium, and
/// where the unit box `[-0.5, 0.5]^3` the grid fills sits in the world.
struct VolumeDraw {
    var volume: Volume
    var medium: Medium
    /// The draw's transform times its width, height, and depth.
    var model: simd_float4x4
    /// The layer the volume composites into, or nil for the canvas.
    var target: RenderTarget?
    /// The light set the volume scatters (0 is the frame's own).
    var lightSet: Int
}

extension Drawer {
    /// Draw a density grid as a cloud filling a `width` x `height` x `depth`
    /// box centered at the model origin (see `Volume` and `Medium`). Recorded
    /// apart from the call-ordered batches: every volume composites over the
    /// frame's finished geometry pass, marched through its resolved depth, so a
    /// solid drawn after the volume still sits inside it.
    func drawVolume(_ volume: Volume, width: Double, height: Double, depth: Double,
                    medium: Medium) {
        if isRecordingBatch {
            noteBatchRecording("drawVolume inside makeBatch { } is not recorded; draw volumes where the batch is drawn.")
            return
        }
        guard camera3D != nil else { return }   // 3D only: the march needs a camera
        if svgRecorder != nil { return }         // a cloud has no vector outline
        if let spatialRecorder { spatialRecorder.skip("a volume"); return }
        // The overlay is drawn over the finished frame in canvas units, with no
        // depth for a march to end on.
        if isDrawingOverlay {
            noteOnce("drawVolume inside withOverlay { } is not drawn; a volume needs the scene's depth.")
            return
        }
        guard width > 0, height > 0, depth > 0 else { return }
        currentTarget?.needsDepth = true
        let size = simd_float4x4(diagonal: SIMD4<Float>(Float(width), Float(height), Float(depth), 1))
        volumeDraws.append(VolumeDraw(volume: volume, medium: medium,
                                      model: modelMatrix * size,
                                      target: currentTarget,
                                      lightSet: resolveLightSet()))
    }

    /// Whether any volume composites into `target` (nil = the canvas) this frame.
    func hasVolumes(for target: RenderTarget?) -> Bool {
        volumeDraws.contains { $0.target === target }
    }
}
