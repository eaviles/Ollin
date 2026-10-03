import Foundation
import Metal
import simd

// The canvas depth of field (`depthOfField()`): the finished 3D frame blurred by
// its own depth through the camera's thin lens, after the temporal resolve and
// before the motion blur. The shaders are in ShaderCombine.metal beside the
// layer `.defocus`, whose iris shape the gather shares.

extension MetalRenderer {

    /// Whether the canvas depth of field runs this frame: the sketch asked, a
    /// perspective camera is active, and its lens has an opening. Notes once
    /// for each of the last two when they are why nothing happens.
    func depthOfFieldActive(_ drawer: Drawer) -> Bool {
        guard drawer.depthOfFieldSetting != nil, let camera = drawer.camera3D else { return false }
        if case .orthographic = camera.projection {
            drawer.noteOnce("depthOfField() needs a perspective camera: an orthographic one has no distance for a lens to focus on, so the frame stays sharp.")
            return false
        }
        guard camera.aperture > 0 else {
            drawer.noteOnce("depthOfField() renders the camera's lens, and this camera's aperture is 0 (a pinhole, sharp everywhere); set Camera3D.aperture to a radius in world units, such as 0.05.")
            return false
        }
        return true
    }

    /// Blur `resolved` by the canvas depth through the camera's lens, or hand
    /// it back untouched when the pass does not run. `depth` is the frame's
    /// resolved depth (sampled by normalized coordinates, so it may be a
    /// different size than the color); `pointScale` turns canvas points into
    /// this texture's pixels, for the `maxBlur` cap. The blur's own size needs
    /// no scale: the focal length is measured in this texture's pixels.
    func applyDepthOfField(_ drawer: Drawer, resolved: MTLTexture, depth: MTLTexture?,
                           into cb: MTLCommandBuffer, width: Int, height: Int,
                           pointScale: Float, pooled: Bool) -> MTLTexture {
        guard depthOfFieldActive(drawer), let setting = drawer.depthOfFieldSetting,
              let camera = drawer.camera3D, let depth, width > 0, height > 0 else { return resolved }
        let aspect = Double(width) / Double(height)
        let focalPixels = Double(camera.projectionMatrix(aspect: aspect).columns.1.y) * Double(height) / 2
        let focus = camera.focusDistance ?? camera.eye.distance(to: camera.target)
        let maxBlur = Float(setting.maxBlur) * pointScale
        guard maxBlur >= 0.5 else { return resolved }
        // A tile is as wide as the gather's widest reach (the widest blur and a
        // pixel, stretched to the corners of a bladed iris), so the 3x3
        // neighborhood of tiles holds every pixel a tap can read.
        let blades = Double(max(0, camera.apertureBlades))
        let irisReach = blades >= 3 ? (Double.pi / (blades * sin(.pi / blades) * cos(.pi / blades))).squareRoot() : 1
        let k = max(8, Int((Double(maxBlur + 1) * irisReach).rounded(.up)) + 1)
        let tilesW = (width + k - 1) / k, tilesH = (height + k - 1) / k
        let taps = Float(resolveDofTaps(setting.quality))
        let lens = SIMD4<Float>(Float(camera.near), Float(camera.far), Float(focalPixels), Float(camera.aperture))
        let band = SIMD4<Float>(Float(focus), Float(setting.focusRange), maxBlur, Float(k))
        let shape = SIMD4<Float>(1 / Float(width), 1 / Float(height), taps, Float(max(0, camera.apertureBlades)))
        guard let coc = acquireFilterTexture(width: width, height: height, pooled: pooled),
              let tileMax = acquireFilterTexture(width: tilesW, height: tilesH, pooled: pooled),
              let reach = acquireFilterTexture(width: tilesW, height: tilesH, pooled: pooled),
              let gathered = acquireFilterTexture(width: width, height: height, pooled: pooled),
              let output = acquireFilterTexture(width: width, height: height, pooled: pooled)
        else { return resolved }
        encodeEffectFragment("ollin_fx_lens_dof_prepass", inputs: [depth], output: coc,
                             params: [lens, band, shape], into: cb)
        encodeEffectFragment("ollin_fx_lens_dof_tilemax", inputs: [coc, resolved], output: tileMax,
                             params: [lens, band], into: cb)
        encodeEffectFragment("ollin_fx_lens_dof_neighbormax", inputs: [tileMax], output: reach,
                             params: [band], into: cb)
        encodeEffectFragment("ollin_fx_lens_depth_of_field", inputs: [resolved, coc, reach], output: gathered,
                             params: [lens, band, shape], into: cb)
        encodeEffectFragment("ollin_fx_lens_dof_median", inputs: [gathered, coc], output: output,
                             params: [lens, band, shape], into: cb)
        return output
    }
}
