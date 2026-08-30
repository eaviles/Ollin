#if targetEnvironment(simulator)

import Metal
import MetalKit
import simd

// The simulator carries no MetalFX at all: the module cannot even be imported
// there, so the two files that build on it (`MetalRenderer+Upscaling`,
// `MetalRenderer+Interpolation`) are compiled out and this stands in for them.
//
// Both features are answers to a load the simulator does not have, and both
// already report themselves as unsupported on a GPU that cannot run them, so
// the honest stand-in is the same answer: no. A sketch there draws every frame
// at its full size, which is what any GPU without the two features does.
//
// The slots below are never built, because nothing asks for one once the two
// `...Active` questions answer false. They exist so the renderer's stored
// properties still name a type.
//
// This file makes the framework *build* for the simulator. It does not make it
// *run* there: the simulated GPU is an Apple family 2 device, which has no
// cube-array textures, and every encode binds one for the point-shadow slot the
// mesh fragment declares (`ensureDummyPointShadowMap`). The first frame aborts
// inside Metal. Running on the simulator would need that slot to become
// optional and a mesh fragment compiled without it, which is a feature tier of
// its own. The device carries both features and needs none of this.

final class FXInterpolatorSlot {
    var hasPrevious = false
    var needsReset = true
}

final class FXScalerSlot {
    var motion: MTLTexture?
    var lastMover: MTLTexture?
    var needsReset = true
}

extension MetalRenderer {

    // MARK: Frames between the drawn ones

    func frameInterpolationActive(_ drawer: Drawer) -> Bool {
        guard drawer.frameInterpolationEnabled else { return false }
        drawer.noteOnce("frameInterpolation() needs a GPU with frame-interpolation support; every frame is drawn instead.")
        return false
    }

    static func frameInterpolationSupported(on device: MTLDevice) -> Bool { false }

    /// The vertical field of view a camera frames the scene with, in degrees, or
    /// `nil` for a projection that has none. Plain geometry, so it answers here
    /// as it does anywhere.
    static func verticalFieldOfView(_ camera: Camera3D, aspect: Double) -> Double? {
        switch camera.projection {
        case .perspective(let fieldOfView):
            return fieldOfView * 180 / .pi
        case .intrinsic(let intrinsics):
            guard intrinsics.fy > 0, intrinsics.height > 0 else { return nil }
            return 2 * atan(Double(intrinsics.height) / (2 * intrinsics.fy)) * 180 / .pi
        case .orthographic:
            return nil
        }
    }

    var hasHeldFrame: Bool { false }

    func presentHeldFrame(_ drawer: Drawer, in view: MTKView) {}

    func dropHeldFrame() {}

    func applyFrameInterpolation(_ drawer: Drawer, drawn: MTLTexture, depth: MTLTexture?,
                                 upscalerMotion: MTLTexture?, meshBuffer: MTLBuffer?,
                                 into cb: MTLCommandBuffer,
                                 inputWidth: Int, inputHeight: Int,
                                 outputWidth: Int, outputHeight: Int) -> MTLTexture? { nil }

    func debugFrameInterpolationReadback(width: Int, height: Int,
                                         frames: [[Float]], motion: [[SIMD2<Float>]],
                                         depth: Float = 0.5,
                                         deltaTime: Double = 1.0 / 30) -> [[Float]]? { nil }

    // MARK: The same frames, off the clock

    func madeFrameRefusal(_ drawer: Drawer) -> String? {
        "made frames need a GPU with frame-interpolation support, and this one has none"
    }

    func keepForMadeFrame(_ drawer: Drawer, presented: MTLTexture, depth: MTLTexture?,
                          meshBuffer: MTLBuffer?, into cb: MTLCommandBuffer,
                          inputWidth: Int, inputHeight: Int,
                          outputWidth: Int, outputHeight: Int) {}

    func exportMadeFrame(_ drawer: Drawer, deltaTime: Double,
                         width: Int, height: Int) -> (buffer: MTLBuffer, bytesPerRow: Int)? { nil }

    func endExportMadeFrames() { exportMadeFrames = false }

    // MARK: Drawing smaller and upscaling

    func temporalUpscalingActive(_ drawer: Drawer) -> Bool { false }

    static func temporalScalerSupported(on device: MTLDevice) -> Bool { false }

    func headlessTemporalAAActive(_ drawer: Drawer) -> Bool { false }

    /// One, so the render size is the canvas size and nothing is scaled.
    func upscaleFactor(for quality: RenderQuality) -> Double { 1 }

    func upscaleInputSize(width: Int, height: Int, quality: RenderQuality) -> (Int, Int) {
        (width, height)
    }

    /// One phase, so the jitter sequence never moves the camera off the pixel
    /// center: there is no upscaler to feed it to.
    func fxJitterPhaseCount(inputWidth: Int, outputWidth: Int) -> Int { 1 }

    func applyTemporalUpscaling(_ drawer: Drawer, resolved: MTLTexture, depth: MTLTexture?,
                                meshBuffer: MTLBuffer?, into cb: MTLCommandBuffer,
                                inputWidth: Int, inputHeight: Int,
                                outputWidth: Int, outputHeight: Int,
                                jitterIndex: Int) -> (output: MTLTexture, mover: MTLTexture?)? {
        nil
    }
}

#endif
