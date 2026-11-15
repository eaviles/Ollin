import Foundation
import simd
import Ollin

/// Where the phone's camera stood for one frame, what its lens was, and the
/// picture it took: what a sketch needs to draw in the room the phone saw.
///
/// ```swift
/// override func draw() {
///     guard let view = device.latestCamera else {
///         return drawStatus(device.waitingMessage, style: .info)
///     }
///     drawPhonePicture(view)      // the camera's picture, filling the canvas
///     camera(view)                // a 3D camera that matches it
///     translate(0, 0, -2)         // two meters in front of where the session began
///     drawBox(size: 0.2)          // a box that stays put as the phone moves
/// }
/// ```
///
/// Everything here stands **upright for how the phone was held**: the picture,
/// the lens, and the camera's own axes are turned together, so a recording made
/// in portrait is a portrait picture with a camera whose up is the picture's up.
///
/// The room is ARKit's world: meters, y up, the origin where the phone's
/// session began. That is the same right-handed, y-up space Ollin's 3D draws
/// in, so a point the phone reports (a plane's corner, a marker's center) is a
/// point a sketch can draw at.
public struct PhoneCamera {

    /// The camera's place in the room: its position and its axes, as a
    /// camera-to-world matrix. The camera looks along its own **-z**, with x to
    /// the picture's right and y to the picture's top.
    public var pose: simd_float4x4

    /// The lens, in pixels of the upright picture: the focal lengths, the point
    /// the lens looks through, and the picture's size.
    public var intrinsics: CameraIntrinsics

    /// Whether the phone was tracking the room normally on this frame. False
    /// while it is starting up or has lost its place, when `pose` is worth
    /// nothing and a sketch does better to hold what it last drew.
    public var isTracked: Bool

    /// The frame's capture time, in seconds on the phone's own clock.
    public var timestamp: Double

    /// The frame's number. In a recording it is the frame of the recording,
    /// counted from zero.
    public var frameIndex: Int

    /// The picture the camera took on this frame, upright, or `nil` when the
    /// source carries none. A recording always has it; the cable sends the
    /// camera's place and lens without the picture.
    ///
    /// A recording decodes the picture when this is read, so a sketch that
    /// wants only where the camera stood never pays for one.
    @MainActor public var picture: Image? { fixedPicture ?? pictureSource?() }

    private var fixedPicture: Image?
    /// Where a recording's picture comes from when it is asked for.
    var pictureSource: (@MainActor () -> Image?)?

    public init(pose: simd_float4x4, intrinsics: CameraIntrinsics, isTracked: Bool = true,
                timestamp: Double = 0, frameIndex: Int = 0, picture: Image? = nil) {
        self.pose = pose
        self.intrinsics = intrinsics
        self.isTracked = isTracked
        self.timestamp = timestamp
        self.frameIndex = frameIndex
        self.fixedPicture = picture
    }

    /// The camera as the phone sent it, turned upright.
    init(_ sample: PhoneCameraSample, picture: Image? = nil) {
        let lens = PhoneWire.uprightLens(fx: sample.fx, fy: sample.fy, cx: sample.cx, cy: sample.cy,
                                         width: sample.imageWidth, height: sample.imageHeight,
                                         quarterTurnsCW: sample.quarterTurnsCW)
        self.init(pose: PhoneWire.wandFrame(fromCamera: sample.transform,
                                            quarterTurnsCW: sample.quarterTurnsCW),
                  intrinsics: CameraIntrinsics(fx: Double(lens.fx), fy: Double(lens.fy),
                                               cx: Double(lens.cx), cy: Double(lens.cy),
                                               width: lens.width, height: lens.height),
                  isTracked: sample.isTracked, timestamp: sample.timestamp,
                  frameIndex: Int(sample.frameIndex), picture: picture)
    }

    /// Where the camera stood, in meters.
    public var position: Vector3 {
        Vector3(Double(pose.columns.3.x), Double(pose.columns.3.y), Double(pose.columns.3.z))
    }

    /// The way the camera looked, as a unit vector in the room.
    public var forward: Vector3 {
        Vector3(Double(-pose.columns.2.x), Double(-pose.columns.2.y), Double(-pose.columns.2.z))
    }

    /// The picture's upward direction, as a unit vector in the room.
    public var up: Vector3 {
        Vector3(Double(pose.columns.1.x), Double(pose.columns.1.y), Double(pose.columns.1.z))
    }

    /// The picture's size in pixels, upright.
    public var pictureSize: Vector2 {
        Vector2(Double(intrinsics.width), Double(intrinsics.height))
    }

    /// The rectangle the picture takes when it is scaled to cover a canvas of
    /// `size` with its proportion kept and its center on the canvas's center.
    /// The rectangle is at least as big as the canvas, and what falls outside
    /// is the crop.
    public func pictureRectangle(covering size: Vector2) -> Rectangle {
        let w = Double(intrinsics.width), h = Double(intrinsics.height)
        guard w > 0, h > 0, size.x > 0, size.y > 0 else {
            return Rectangle(x: 0, y: 0, width: size.x, height: size.y)
        }
        let scale = max(size.x / w, size.y / h)
        return Rectangle(x: (size.x - w * scale) / 2, y: (size.y - h * scale) / 2,
                         width: w * scale, height: h * scale)
    }

    /// A 3D camera that sees what the phone's camera saw, for a canvas of
    /// `size` covered by the picture (`pictureRectangle(covering:)`).
    ///
    /// The lens is the phone's own, cropped the way the picture is cropped, so a
    /// point in the room lands on its own pixel of the picture whatever the
    /// canvas's proportion. `near` and `far` are the clip distances in meters.
    public func camera3D(covering size: Vector2, near: Double = 0.01, far: Double = 100) -> Camera3D {
        let placed = pictureRectangle(covering: size)
        let w = Double(intrinsics.width)
        let scale = w > 0 ? placed.width / w : 1
        // The canvas's size as whole numbers, since the lens is counted in
        // pixels; a canvas is whole pixels already.
        let width = max(1, Int(size.x.rounded())), height = max(1, Int(size.y.rounded()))
        let lens = CameraIntrinsics(fx: intrinsics.fx * scale, fy: intrinsics.fy * scale,
                                    cx: intrinsics.cx * scale + placed.x,
                                    cy: intrinsics.cy * scale + placed.y,
                                    width: width, height: height)
        let eye = position
        return Camera3D(eye: eye, target: eye + forward, up: up, near: near, far: far,
                        projection: .intrinsic(lens))
    }
}

public extension Sketch {

    /// Draw the phone camera's picture so it covers the canvas: scaled with its
    /// proportion kept, centered, and cropped where it overflows. Draws nothing
    /// when the frame carries no picture.
    ///
    /// Follow it with `camera(_:)` for the same `PhoneCamera` and whatever is
    /// drawn in 3D afterwards sits in the room the picture shows.
    func drawPhonePicture(_ view: PhoneCamera) {
        guard let picture = view.picture else { return }
        let placed = view.pictureRectangle(covering: Vector2(width, height))
        drawImage(picture, placed.x, placed.y, placed.width, placed.height)
    }

    /// Look through the phone's camera: set the 3D camera to the one that
    /// matches the picture `drawPhonePicture(_:)` draws, so a point in the room
    /// lands on its own pixel. `near` and `far` are the clip distances in
    /// meters.
    func camera(_ view: PhoneCamera, near: Double = 0.01, far: Double = 100) {
        camera(view.camera3D(covering: Vector2(width, height), near: near, far: far))
    }
}
