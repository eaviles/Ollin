// The names Chapter 33's prose establishes around its fragments.
// See Guide/AUTHORING.md, "The code in the prose".
import OllinPhone
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

// The phone, and the rectangle a frame landed in.
@MainActor let device = PhoneDevice()
let rect = Rectangle(x: 0, y: 0, width: 1080, height: 810)
var dust: [Vector2] = []

// The wand's balls, what it aimed at and holds, and its last press count.
@MainActor let wand = device.latestWand!
let balls = [Vector3(-0.5, 1.46, -1.42), Vector3(0.02, 1.3, -1.5)]
var aimed: (index: Int, distance: Double)? = nil
var held: Int?
var lastPressCount = 0

// The marks the sounds and taps leave, the glass on the canvas, and the lift.
struct Ring { var at: Vector2; var born: Double }
var rings: [Ring] = []
func place(for label: String) -> Vector2 { .zero }
let pad = Rectangle(x: 48, y: 44, width: 210, height: 396)
var lift = 0.0
