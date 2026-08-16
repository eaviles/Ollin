import Foundation
import ARKit
import simd

/// The pieces a 3D lift needs, all camera-native: the depth grid, the intrinsics
/// already scaled onto it, and the camera→world pose. Copied out of an `ARFrame`
/// by `liftContext(of:)` *inside* the ARKit delegate callback (the frame's
/// buffers are the session's own, and nothing promises they outlive the call),
/// so a Vision pass on another queue lifts from its own copies. Shared by every
/// streamer that stands a 2D observation in the world (hands, text).
struct LiftContext {
    var width: Int
    var height: Int
    var depth: [Float]
    var fx: Float
    var fy: Float
    var cx: Float
    var cy: Float
    var transform: simd_float4x4
}

/// Copy everything a lift needs out of `frame`, or `nil` when the frame carries
/// no scene depth (a non-LiDAR phone, or a session without depth semantics).
/// Call it inside the delegate callback, never later.
func liftContext(of frame: ARFrame) -> LiftContext? {
    guard let sceneDepth = frame.smoothedSceneDepth ?? frame.sceneDepth,
          let (depthW, depthH, depth) = floatPixels(sceneDepth.depthMap) else { return nil }
    // Intrinsics arrive at the captured-image resolution; bring them onto the
    // depth grid so an observation's pixel unprojects directly.
    let res = frame.camera.imageResolution
    let k = frame.camera.intrinsics
    let sx = Float(depthW) / Float(res.width)
    let sy = Float(depthH) / Float(res.height)
    return LiftContext(width: depthW, height: depthH, depth: depth,
                       fx: k.columns.0.x * sx, fy: k.columns.1.y * sy,
                       cx: k.columns.2.x * sx, cy: k.columns.2.y * sy,
                       transform: frame.camera.transform)
}

/// Lift one upright image point into ARKit world space: back onto the
/// camera-native depth grid by the shared quarter-turn arithmetic, a median
/// depth from the window around its pixel, the unprojection through the
/// depth-grid intrinsics (camera space: +x right, +y up, looking down −z), and
/// the camera pose onto the front of that. `nil` when every depth sample around
/// the pixel is a hole.
func worldPosition(ofUpright p: SIMD2<Float>, turns: UInt8, lift: LiftContext,
                   windowRadius: Int = 2) -> SIMD3<Float>? {
    let b = PhoneWire.bufferPoint(fromUpright: p, quarterTurnsCW: turns)
    let col = Int((b.x * Float(lift.width)).rounded(.down))
    let row = Int((b.y * Float(lift.height)).rounded(.down))
    guard let depth = medianDepth(atCol: col, row: row, lift: lift,
                                  radius: windowRadius) else { return nil }

    let x = (Float(col) - lift.cx) / lift.fx * depth
    let y = -(Float(row) - lift.cy) / lift.fy * depth
    let world = lift.transform * SIMD4<Float>(x, y, -depth, 1)
    return SIMD3<Float>(world.x, world.y, world.z)
}

/// The median of the valid depth samples in the window around a pixel, or `nil`
/// when every sample there is a hole: robust to the dropouts that sit exactly
/// where an observed point meets the background.
private func medianDepth(atCol col: Int, row: Int, lift: LiftContext, radius: Int) -> Float? {
    guard lift.width > 0, lift.height > 0 else { return nil }
    // Clamp first, so a point exactly on the picture's edge still reads its
    // nearest pixels rather than building an empty window.
    let c = min(max(col, 0), lift.width - 1)
    let r = min(max(row, 0), lift.height - 1)
    var samples: [Float] = []
    samples.reserveCapacity((2 * radius + 1) * (2 * radius + 1))
    for y in max(0, r - radius)...min(lift.height - 1, r + radius) {
        for x in max(0, c - radius)...min(lift.width - 1, c + radius) {
            let d = lift.depth[y * lift.width + x]
            if d > 0, d.isFinite { samples.append(d) }
        }
    }
    guard !samples.isEmpty else { return nil }
    return samples.sorted()[samples.count / 2]
}

/// The image orientation that stands the camera-native buffer upright for a
/// Vision model, from the same quarter-turn count everything else uses.
func visionOrientation(forQuarterTurnsCW turns: UInt8) -> CGImagePropertyOrientation {
    switch turns % 4 {
    case 1:  return .right
    case 2:  return .down
    case 3:  return .left
    default: return .up
    }
}
