// The names Chapter 35's prose establishes around its fragments.
// See Guide/AUTHORING.md, "The code in the prose".
import simd

// The pretend depth camera from the end of GhostRoom.swift, by its signatures.
enum StageCamera {
    static func capture(eye: Vector3, target: Vector3, tint: Color? = nil) -> RGBDFrame { fatalError() }
    static func pose(eye: Vector3, target: Vector3) -> simd_float4x4 { fatalError() }
}

// A frame's three parts, a frame, and where the captures stand and look.
let color = Image(width: 240, height: 180, premultipliedRGBA: [UInt8](repeating: 0, count: 240 * 180 * 4))!
let depths = [Float](repeating: 0, count: 240 * 180)
let intrinsics = CameraIntrinsics(fx: 210, fy: 210, cx: 120, cy: 90, width: 240, height: 180)
let room = Vector3(-0.1, 0.4, -1.2)
let eye = Vector3(0.2, 1.05, 1.7)
let eyes = [eye]
let frame = StageCamera.capture(eye: eye, target: room)

// The world the frames join, one more cloud, and the pose the phone reported.
var world = WorldCloud(voxelSize: 0.02)
let cloud = frame.pointCloud(pointSize: 0.016)
let reportedPose = StageCamera.pose(eye: eye, target: room)
