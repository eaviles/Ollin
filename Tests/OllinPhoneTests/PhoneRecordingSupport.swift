import CoreGraphics
import CoreVideo
import Foundation
import simd
import Ollin
@testable import OllinPhone

/// A small room with marked points in it, drawn through a camera whose place
/// and lens are stated for every frame: the known scene a recording is made of
/// on the Mac, so what is read back can be held to numbers.
///
/// The marks are spheres of flat, saturated color at known places in meters.
/// Everything else in the room is muted, so a mark is found in a picture by its
/// color alone.
@MainActor
final class SyntheticRoom: Sketch {

    /// A marked point of the room and the color it is drawn in.
    struct Mark {
        var point: Vector3
        var color: Color
        /// Whether an eight-bit pixel is this mark's color, loosely enough to
        /// survive a video codec.
        var matches: @Sendable (_ r: Int, _ g: Int, _ b: Int) -> Bool
    }

    static let marks: [Mark] = [
        Mark(point: Vector3(-0.6, 0.9, -0.3), color: Color(red: 1, green: 0, blue: 1)) { r, g, b in
            r > 170 && b > 170 && g < 100
        },
        Mark(point: Vector3(0.5, 1.3, 0.2), color: Color(red: 0, green: 1, blue: 1)) { r, g, b in
            g > 170 && b > 170 && r < 100
        },
        Mark(point: Vector3(0.1, 0.4, 0.6), color: Color(red: 1, green: 1, blue: 0)) { r, g, b in
            r > 170 && g > 170 && b < 100
        },
        Mark(point: Vector3(-0.2, 1.7, -0.8), color: Color(red: 0, green: 1, blue: 0)) { r, g, b in
            g > 170 && r < 100 && b < 100
        },
    ]

    static let markRadius = 0.05

    /// The solids standing in the room: each one's middle, its size, and its
    /// color, muted so none is mistaken for a mark.
    static let solids: [(center: Vector3, size: Vector3, color: Color)] = [
        (Vector3(-1.2, 0.35, -0.6), Vector3(0.7, 0.7, 0.7), Color(hex: 0xA9785F)),
        (Vector3(1.1, 0.5, -0.9), Vector3(0.5, 1.0, 0.5), Color(hex: 0x7F9685)),
        (Vector3(0.9, 0.2, 0.7), Vector3(0.6, 0.4, 0.6), Color(hex: 0xB9A684)),
        (Vector3(-0.9, 0.6, -1.2), Vector3(0.3, 1.2, 0.3), Color(hex: 0x74809A)),
    ]

    /// The upright picture's size, and how many frames the walk takes.
    var pictureWidth = 320
    var pictureHeight = 240
    var frameTotal = 16
    /// The frame of the walk to draw.
    var walkFrame = 0
    /// Whether the walk ends where it began, so a recording of it loops.
    var isLoop = false
    /// Whether the marks are drawn. A recording made to be looked at leaves
    /// them out; one made to be measured keeps them.
    var showsMarks = true

    /// The lens the room is drawn through. The point it looks through sits off
    /// the middle on purpose, and its two focal lengths differ.
    var lens: CameraIntrinsics {
        let focal = 0.92 * Double(min(pictureWidth, pictureHeight))
        return CameraIntrinsics(fx: focal, fy: focal * 1.01,
                                cx: Double(pictureWidth) / 2 + 3.5,
                                cy: Double(pictureHeight) / 2 - 2.25,
                                width: pictureWidth, height: pictureHeight)
    }

    convenience init(width: Int, height: Int, frames: Int) {
        self.init()
        pictureWidth = width
        pictureHeight = height
        frameTotal = frames
    }

    override var canvasSize: CanvasSize { .size(pictureWidth, pictureHeight) }

    /// Where the camera stands on a frame of the walk: it moves about a meter
    /// across the room, looks at a point that sways, and rolls a little.
    static func walk(at frame: Int, of total: Int,
                     loop: Bool = false) -> (eye: Vector3, target: Vector3, up: Vector3) {
        if loop {
            // Once round a flattened circle in front of the room, swaying as it
            // goes, the last frame one step short of the first.
            let a = 2 * Double.pi * Double(frame) / Double(max(1, total))
            let eye = Vector3(0.75 * sin(a), 1.35 + 0.12 * sin(2 * a), 2.9 + 0.35 * cos(a))
            let target = Vector3(0.25 * sin(a + 0.6), 0.85 + 0.1 * cos(a), -0.3)
            let roll = 0.05 * sin(a)
            return (eye, target, Vector3(sin(roll), cos(roll), 0))
        }
        let a = Double(frame) / Double(max(1, total - 1))
        let eye = Vector3(-0.5 + 1.0 * a, 1.35 + 0.1 * sin(a * .pi), 3.0 - 0.4 * a)
        let target = Vector3(0.1 * sin(a * 2 * .pi), 1.0, 0)
        let roll = 0.08 * sin(a * 2 * .pi)
        return (eye, target, Vector3(sin(roll), cos(roll), 0))
    }

    /// The camera's place on a frame as a camera-to-world matrix: x to the
    /// picture's right, y to its top, looking along -z.
    static func pose(at frame: Int, of total: Int, loop: Bool = false) -> simd_float4x4 {
        let (eye, target, up) = walk(at: frame, of: total, loop: loop)
        let e = SIMD3<Double>(eye.x, eye.y, eye.z)
        let z = simd_normalize(e - SIMD3<Double>(target.x, target.y, target.z))
        let x = simd_normalize(simd_cross(SIMD3<Double>(up.x, up.y, up.z), z))
        let y = simd_cross(z, x)
        func column(_ v: SIMD3<Double>, _ w: Float) -> SIMD4<Float> {
            SIMD4<Float>(Float(v.x), Float(v.y), Float(v.z), w)
        }
        return simd_float4x4(column(x, 0), column(y, 0), column(z, 0), column(e, 1))
    }

    /// Where a point of the room falls in the upright picture, in pixels, by
    /// the pinhole rule written out here on its own: nothing of the framework's
    /// projection is asked.
    func pixel(of point: Vector3, at frame: Int) -> Vector2 {
        let pose = Self.pose(at: frame, of: frameTotal, loop: isLoop)
        let d = SIMD3<Double>(point.x, point.y, point.z)
            - SIMD3<Double>(Double(pose.columns.3.x), Double(pose.columns.3.y), Double(pose.columns.3.z))
        func axis(_ c: SIMD4<Float>) -> SIMD3<Double> { SIMD3<Double>(Double(c.x), Double(c.y), Double(c.z)) }
        let right = simd_dot(d, axis(pose.columns.0))
        let above = simd_dot(d, axis(pose.columns.1))
        let ahead = -simd_dot(d, axis(pose.columns.2))
        return Vector2(lens.fx * right / ahead + lens.cx, lens.cy - lens.fy * above / ahead)
    }

    override func draw() {
        let (eye, target, up) = Self.walk(at: walkFrame, of: frameTotal, loop: isLoop)
        background(Color(hex: 0x1B1D21))
        camera(Camera3D(eye: eye, target: target, up: up, near: 0.01, far: 100,
                        projection: .intrinsic(lens)))
        ambientLight(Color(white: 0.42))
        directionalLight(Color(white: 1), direction: Vector3(-0.45, -1, -0.55), castsShadow: true)
        castShadows()
        noStroke()

        // The room: a floor with a grid on it, a back wall, and a few muted
        // solids that cast shadows, so it reads as a place a camera moves in.
        fill(Color(hex: 0x77726A))
        drawPlane(width: 7, depth: 7)
        withState {
            translate(0, 2.25, -1.6)
            fill(Color(hex: 0x4E5661))
            drawBox(width: 7, height: 4.5, depth: 0.1)
        }
        withState {
            noLights()
            stroke(Color(hex: 0x8D887F))
            strokeWeight(1)
            for step in -7...7 {
                let at = Double(step) * 0.5
                drawLine(Vector3(at, 0.002, -1.55), Vector3(at, 0.002, 3.5))
                if at > -1.55 { drawLine(Vector3(-3.5, 0.002, at), Vector3(3.5, 0.002, at)) }
            }
        }
        noStroke()
        for solid in Self.solids {
            withState {
                translate(solid.center)
                fill(solid.color)
                drawBox(width: solid.size.x, height: solid.size.y, depth: solid.size.z)
            }
        }

        // The marks, flat and saturated.
        for mark in Self.marks where showsMarks {
            withState {
                noLights()
                translate(mark.point)
                fill(mark.color)
                drawSphere(radius: Self.markRadius, segments: 32, rings: 16)
            }
        }
    }
}

/// What a recording of the synthetic room was made with, kept so a test can
/// say where everything should be.
@MainActor
struct SyntheticRecording {
    let folder: URL
    let room: SyntheticRoom
    let frames: Int
    let framesPerSecond: Double
    let quarterTurnsCW: UInt8
    let firstTime: Double

    /// The capture time of a frame.
    func time(of frame: Int) -> Double { firstTime + Double(frame) / framesPerSecond }

    /// Render the room's walk and write it as a recording with the writer the
    /// phone runs, turned into the sensor's frame the way a phone held at
    /// `quarterTurnsCW` would deliver it.
    ///
    /// `skipping` never hands a frame of the walk to the writer. `stuck` hands
    /// a frame over stamped with the time of the one before it, which the video
    /// refuses, so the writer itself has to drop it from both files. `also`
    /// hands extra messages over after a frame's picture, as a streamer would.
    static func write(named name: String, width: Int = 320, height: Int = 240, frames: Int = 16,
                      framesPerSecond: Double = 30, quarterTurnsCW: UInt8 = 0,
                      mode: PhoneCaptureMode = .world, skipping: Set<Int> = [],
                      repeatingTimeAt stuck: Set<Int> = [],
                      finish: Bool = true, to destination: URL? = nil,
                      isLoop: Bool = false, showsMarks: Bool = true, bitRate: Int? = nil,
                      also: (_ frame: Int, _ time: Double) -> [PhoneMessage] = { _, _ in [] })
        async throws -> SyntheticRecording {
        let folder = destination ?? FileManager.default.temporaryDirectory
            .appendingPathComponent("ollin-recording-\(name)-\(UUID().uuidString)")
            .appendingPathExtension(PhoneRecordingFile.folderExtension)
        let room = SyntheticRoom(width: width, height: height, frames: frames)
        room.isLoop = isLoop
        room.showsMarks = showsMarks
        let writer = try PhoneRecordingWriter(folder: folder, mode: mode, quarterTurnsCW: quarterTurnsCW,
                                              device: "Synthetic", started: Date(timeIntervalSince1970: 1_794_614_400),
                                              framesPerSecond: framesPerSecond,
                                              isRealTime: false, bitRate: bitRate)
        let made = SyntheticRecording(folder: folder, room: room, frames: frames,
                                      framesPerSecond: framesPerSecond,
                                      quarterTurnsCW: quarterTurnsCW, firstTime: 1000)
        for frame in 0..<frames where !skipping.contains(frame) {
            room.walkFrame = frame
            let upright = try OllinApp.image(of: room, frame: 0)
            // The sensor's picture is the upright one turned back: a phone held
            // at one clockwise quarter turn delivers a picture that needs that
            // turn to stand up, so it is three turns from upright.
            guard let sensor = rotatedCGImage(upright, quarterTurnsCW: (4 - Int(quarterTurnsCW)) % 4),
                  let buffer = pixelBuffer(from: sensor) else {
                throw PhoneRecordingError.unreadable("the synthetic frame would not build")
            }
            let time = made.time(of: frame)
            var camera = made.sensorCamera(at: frame)
            if stuck.contains(frame) { camera.timestamp = made.time(of: frame - 1) }
            writer.append(picture: buffer, camera: camera)
            for message in also(frame, time) { writer.append(message, at: time) }
        }
        if finish {
            _ = try await writer.finish()
        } else {
            await writer.drain()
        }
        return made
    }

    /// The camera record a phone would send for a frame of the walk: the lens
    /// and the axes in the sensor's own frame.
    ///
    /// The turn is written out here from what a quarter turn does to a
    /// picture, rather than by running the framework's own turn backward. A
    /// picture turned a quarter clockwise puts the sensor's top edge on the
    /// right. So the upright picture's right is the sensor's up, and the
    /// upright picture's up is the sensor's left: sensor x = -upright y,
    /// sensor y = upright x. A pixel `(u, v)` of the upright picture was the
    /// sensor's `(v, W - u)`, `W` the upright width.
    func sensorCamera(at frame: Int) -> PhoneCameraSample {
        let upright = SyntheticRoom.pose(at: frame, of: frames, loop: room.isLoop)
        let k = room.lens
        let w = Double(k.width), h = Double(k.height)
        var transform = upright
        var lens = (fx: k.fx, fy: k.fy, cx: k.cx, cy: k.cy, width: k.width, height: k.height)
        switch quarterTurnsCW % 4 {
        case 1:
            transform = simd_float4x4(-upright.columns.1, upright.columns.0,
                                      upright.columns.2, upright.columns.3)
            lens = (k.fy, k.fx, k.cy, w - k.cx, k.height, k.width)
        case 2:
            transform = simd_float4x4(-upright.columns.0, -upright.columns.1,
                                      upright.columns.2, upright.columns.3)
            lens = (k.fx, k.fy, w - k.cx, h - k.cy, k.width, k.height)
        case 3:
            transform = simd_float4x4(upright.columns.1, -upright.columns.0,
                                      upright.columns.2, upright.columns.3)
            lens = (k.fy, k.fx, h - k.cy, k.cx, k.height, k.width)
        default:
            break
        }
        return PhoneCameraSample(isTracked: true, timestamp: time(of: frame), frameIndex: 0,
                                 imageWidth: lens.width, imageHeight: lens.height,
                                 fx: Float(lens.fx), fy: Float(lens.fy),
                                 cx: Float(lens.cx), cy: Float(lens.cy),
                                 transform: transform, quarterTurnsCW: quarterTurnsCW)
    }

    func remove() { try? FileManager.default.removeItem(at: folder) }
}

/// A `CGImage` as the BGRA pixel buffer a video writer takes.
func pixelBuffer(from image: CGImage) -> CVPixelBuffer? {
    let attributes: [String: Any] = [
        kCVPixelBufferIOSurfacePropertiesKey as String: [String: Any](),
        kCVPixelBufferCGImageCompatibilityKey as String: true,
        kCVPixelBufferCGBitmapContextCompatibilityKey as String: true,
    ]
    var made: CVPixelBuffer?
    guard CVPixelBufferCreate(nil, image.width, image.height, kCVPixelFormatType_32BGRA,
                              attributes as CFDictionary, &made) == kCVReturnSuccess,
          let buffer = made else { return nil }
    CVPixelBufferLockBaseAddress(buffer, [])
    defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
    let info = CGImageAlphaInfo.noneSkipFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
    guard let space = CGColorSpace(name: CGColorSpace.sRGB),
          let context = CGContext(data: CVPixelBufferGetBaseAddress(buffer),
                                  width: image.width, height: image.height, bitsPerComponent: 8,
                                  bytesPerRow: CVPixelBufferGetBytesPerRow(buffer),
                                  space: space, bitmapInfo: info) else { return nil }
    context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
    return buffer
}

/// A picture's pixels as eight-bit RGB, top row first, for finding a mark.
struct RecordingPixels {
    let width: Int
    let height: Int
    private let bytes: [UInt8]

    init?(_ image: CGImage) {
        width = image.width
        height = image.height
        var buffer = [UInt8](repeating: 0, count: width * height * 4)
        let info = CGImageAlphaInfo.premultipliedLast.rawValue
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(data: &buffer, width: width, height: height, bitsPerComponent: 8,
                                      bytesPerRow: width * 4, space: space, bitmapInfo: info)
        else { return nil }
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        bytes = buffer
    }

    /// The middle of the pixels a mark's color covers, in pixels from the top
    /// left with a pixel's own middle at its half, and how many there were.
    func center(of mark: SyntheticRoom.Mark) -> (point: Vector2, count: Int) {
        var sumX = 0.0, sumY = 0.0, count = 0
        for y in 0..<height {
            for x in 0..<width {
                let i = (y * width + x) * 4
                if mark.matches(Int(bytes[i]), Int(bytes[i + 1]), Int(bytes[i + 2])) {
                    sumX += Double(x) + 0.5
                    sumY += Double(y) + 0.5
                    count += 1
                }
            }
        }
        guard count > 0 else { return (.zero, 0) }
        return (Vector2(sumX / Double(count), sumY / Double(count)), count)
    }
}
