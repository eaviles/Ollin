import Testing
import CoreGraphics
import Foundation
import simd
import Ollin
@testable import OllinPhone

/// Plays a recording the way a sketch does: the picture, the camera that took
/// it, and then whatever a test draws in the room it shows.
private final class SurfaceProbe: Sketch {
    var device: PhoneDevice?
    var canvas = (width: 640, height: 480)
    /// Points of the room whose places on the canvas the frame writes down.
    var points: [Vector3] = []
    var projected: [Vector2?] = []
    var seenFrame: Int?
    /// What a test draws, handed the frame's camera and the wall the phone found.
    var scene: (SurfaceProbe, PhoneCamera, PhonePlane) -> Void = { _, _, _ in }

    convenience init(playing recording: PhoneRecording, width: Int, height: Int) {
        self.init()
        device = PhoneDevice(playing: recording)
        canvas = (width, height)
    }

    override var canvasSize: CanvasSize { .size(canvas.width, canvas.height) }

    override func setup() { device?.start() }

    override func draw() {
        background(.black)
        guard let device, let view = device.latestCamera else {
            seenFrame = nil
            return
        }
        drawPhonePicture(view)
        camera(view)
        seenFrame = view.frameIndex
        projected = points.map { project($0) }
        guard let wall = device.planes.largest(of: .wall) else { return }
        noStroke()
        fill(.white)
        scene(self, view, wall)
    }
}

/// How two frames differ: the largest step on any channel, and how many pixels
/// differ at all.
private func difference(_ a: CGImage, _ b: CGImage) -> (largest: Int, pixels: Int) {
    func bytes(_ image: CGImage) -> [UInt8] {
        var buffer = [UInt8](repeating: 0, count: image.width * image.height * 4)
        let context = CGContext(data: &buffer, width: image.width, height: image.height,
                                bitsPerComponent: 8, bytesPerRow: image.width * 4,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        context?.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        return buffer
    }
    let pa = bytes(a), pb = bytes(b)
    var largest = 0, count = 0
    for i in stride(from: 0, to: min(pa.count, pb.count), by: 4) {
        var here = 0
        for c in 0..<3 { here = max(here, abs(Int(pa[i + c]) - Int(pb[i + c]))) }
        if here > 0 { count += 1 }
        largest = max(largest, here)
    }
    return (largest, count)
}

/// Drawing on a surface a recording shows, proved on the synthetic room: its
/// back wall is tiled and carries a poster with a mark on each corner, the
/// camera passes close along it, and the recording carries the wall as the
/// surface a phone in Room mode would have found.
///
/// It renders and decodes video, so it sits inside `PhoneMediaTests` with the
/// recording's own suite.
extension PhoneMediaTests {
@MainActor
@Suite struct PhoneSurfaceTests {

    /// A recording of the walk along the tiled wall, with the room's surfaces
    /// beside its first frame.
    private static func wallRecording(named name: String, width: Int = 640, height: Int = 480,
                                      frames: Int = 10, turns: UInt8 = 0) async throws -> SyntheticRecording {
        try await SyntheticRecording.write(
            named: name, width: width, height: height, frames: frames, quarterTurnsCW: turns,
            mode: .room, wallDetail: true, facesWall: true
        ) { frame, time in
            frame == 0 ? SyntheticRecording.surfaces(at: time) : []
        }
    }

    // MARK: Pinned points

    /// Four corners clicked on one frame stay on the poster for the whole
    /// recording: each click becomes a point of the wall (the ray through the
    /// click met with the surface the recording carries), and that point lands
    /// on its corner's own picture within a pixel on every frame.
    @Test(arguments: [
        (UInt8(0), 640, 480),     // level, the picture's own proportion
        (UInt8(0), 420, 480),     // level, a canvas that crops the sides
        (UInt8(1), 480, 640),     // portrait
    ])
    func fourClickedCornersStayOnThePoster(turns: UInt8, canvasWidth: Int, canvasHeight: Int) async throws {
        let sideways = turns % 2 == 1
        let made = try await Self.wallRecording(named: "corners", width: sideways ? 480 : 640,
                                                height: sideways ? 640 : 480, turns: turns)
        defer { made.remove() }
        let recording = try PhoneRecording(path: made.folder.path)
        let probe = SurfaceProbe(playing: recording, width: canvasWidth, height: canvasHeight)
        let canvas = Vector2(Double(canvasWidth), Double(canvasHeight))
        recording.pause()

        // The frame the corners are clicked on: the middle of the walk's first
        // half, where the whole poster is in view at every canvas here.
        let clickedOn = 1
        recording.seek(toFrame: clickedOn)
        let first = try #require(RecordingPixels(try OllinApp.image(of: probe, frame: 0)))
        let view = try recording.camera(at: clickedOn)
        let wall = try #require(probe.device?.planes.largest(of: .wall)).plane
        #expect(wall.normal.distance(to: .unitZ) < 1e-6, "the recording's wall faces the room")
        #expect(abs(wall.origin.z - SyntheticRoom.wallZ) < 1e-6)
        #expect(wall.up.distance(to: .unitY) < 1e-6 && wall.right.distance(to: .unitX) < 1e-6)

        // The marks lie on the poster, a centimeter proud of the wall's face,
        // so that is the surface a click on one is met with.
        let poster = wall.moved(by: .zero, lift: SyntheticRoom.posterMarkLift)
        var pins: [Vector3] = []
        for mark in SyntheticRoom.posterMarks {
            let click = first.center(of: mark)
            try #require(click.count > 40, "a corner's mark is not in the frame that is clicked on")
            let pin = try #require(poster.intersection(with: view.ray(through: click.point, covering: canvas)))
            #expect(pin.distance(to: mark.point) < 0.005,
                    "a click on a corner lands \(pin.distance(to: mark.point)) m from it")
            let back = try #require(view.canvasPoint(of: pin, covering: canvas))
            #expect(back.distance(to: click.point) < 1e-3,
                    "the point goes back to the pixel it was clicked on")
            pins.append(pin)
        }

        probe.points = pins
        var checked = 0
        for frame in 0..<made.frames {
            recording.seek(toFrame: frame)
            let pixels = try #require(RecordingPixels(try OllinApp.image(of: probe, frame: 0)))
            #expect(probe.seenFrame == frame)
            for (index, mark) in SyntheticRoom.posterMarks.enumerated() {
                let pin = try #require(probe.projected[index])
                guard pin.x > 16, pin.y > 16, pin.x < canvas.x - 16, pin.y < canvas.y - 16 else { continue }
                let seen = pixels.center(of: mark)
                #expect(seen.count > 40, "frame \(frame) corner \(index) is not in the picture")
                #expect(seen.point.distance(to: pin) < 1.0,
                        "frame \(frame) corner \(index): drawn at \(seen.point), pinned at \(pin)")
                checked += 1
            }
        }
        #expect(checked > made.frames * 2, "the walk keeps the poster in view (\(checked) checks)")
    }

    /// The plant: a corner pinned on the wrong surface slides off its mark. The
    /// walk has to move enough for the test above to tell a point of the wall
    /// from one half a meter behind it.
    @Test func aCornerPinnedBehindTheWallSlidesOffIt() async throws {
        let made = try await Self.wallRecording(named: "behind")
        defer { made.remove() }
        let recording = try PhoneRecording(path: made.folder.path)
        let probe = SurfaceProbe(playing: recording, width: 640, height: 480)
        let canvas = Vector2(640, 480)
        recording.pause()
        recording.seek(toFrame: 1)
        let first = try #require(RecordingPixels(try OllinApp.image(of: probe, frame: 0)))
        let view = try recording.camera(at: 1)
        let wall = try #require(probe.device?.planes.largest(of: .wall)).plane
        let behind = wall.moved(by: .zero, lift: SyntheticRoom.posterMarkLift - 0.5)
        let mark = SyntheticRoom.posterMarks[0]
        let click = first.center(of: mark)
        probe.points = [try #require(behind.intersection(with: view.ray(through: click.point, covering: canvas)))]
        var worst = 0.0
        for frame in 0..<made.frames {
            recording.seek(toFrame: frame)
            let pixels = try #require(RecordingPixels(try OllinApp.image(of: probe, frame: 0)))
            guard let pin = probe.projected[0] else { continue }
            let seen = pixels.center(of: mark)
            if seen.count > 40 { worst = max(worst, seen.point.distance(to: pin)) }
        }
        #expect(worst > 8, "a point half a meter behind the wall drifts \(worst) pixels off the corner")
    }

    // MARK: The picture as paint

    /// What stands on the wall for the paint tests: a block of flat boxes,
    /// each placed and then drawn through `look`.
    private static func boxes(_ s: SurfaceProbe, on wall: PhonePlane, look: (() -> Void) -> Void) {
        s.withPlane(wall) {
            for row in -1...1 {
                for column in -2...2 {
                    s.withState {
                        s.translate(Double(column) * 0.3, Double(row) * 0.3 - 0.2, 0.02)
                        look { s.drawBox(width: 0.26, height: 0.26, depth: 0.04) }
                    }
                }
            }
        }
    }

    /// A mesh painted with the camera's picture and left where it is leaves
    /// the frame as it was, on every frame of the walk: no pixel moves by more
    /// than one level, and few move at all. A triangle's corners are snapped
    /// to 1/256 of a pixel when it is drawn, which shifts where the picture is
    /// read by that much and now and then tips a rounding. Measured on this
    /// recording: with the canvas the picture's own size, 1 to 3 pixels of
    /// 307,200; with a canvas that enlarges the picture by a quarter, where a
    /// read falls between the picture's pixels, 357 to 491 of 420,000.
    @Test(arguments: [(640, 480, 16), (700, 600, 1500)])
    func aMeshPaintedAndLeftInPlaceChangesNoPixel(canvasWidth: Int, canvasHeight: Int,
                                                  most: Int) async throws {
        let made = try await Self.wallRecording(named: "inplace", frames: 6)
        defer { made.remove() }
        let recording = try PhoneRecording(path: made.folder.path)
        let probe = SurfaceProbe(playing: recording, width: canvasWidth, height: canvasHeight)
        recording.pause()
        for frame in 0..<made.frames {
            recording.seek(toFrame: frame)
            probe.scene = { _, _, _ in }
            let plain = try OllinApp.image(of: probe, frame: 0)
            probe.scene = { s, _, wall in
                s.noLights()
                Self.boxes(s, on: wall) { $0() }
            }
            let solid = try OllinApp.image(of: probe, frame: 0)
            #expect(difference(plain, solid).pixels > canvasWidth * canvasHeight / 12,
                    "frame \(frame): the control, the boxes cover part of the canvas")
            probe.scene = { s, view, wall in
                Self.boxes(s, on: wall) { body in s.painted(with: view, body) }
            }
            let painted = try OllinApp.image(of: probe, frame: 0)
            let moved = difference(plain, painted)
            #expect(moved.largest <= 1 && moved.pixels <= most,
                    "frame \(frame): \(moved.pixels) pixels moved, by up to \(moved.largest) levels")
        }
    }

    /// A tile lifted off the wall carries the pixels it left. Each corner of
    /// the poster sits in the middle of a tile, the tiles are pushed out by
    /// different amounts, and each corner's mark is found where the lifted
    /// face should show it: on the corner moved out along the wall's normal.
    @Test func aLiftedTileCarriesThePixelsItLeft() async throws {
        let made = try await Self.wallRecording(named: "lifted")
        defer { made.remove() }
        let recording = try PhoneRecording(path: made.folder.path)
        let probe = SurfaceProbe(playing: recording, width: 640, height: 480)
        let lifts = [0.12, 0.2, 0.3, 0.4]
        let side = 0.24
        let corners = SyntheticRoom.posterMarks.map(\.point)
        // Where each mark should show (lifted), and where it was (at rest).
        probe.points = zip(corners, lifts).map { $0 + Vector3(0, 0, $1) } + corners
        probe.scene = { s, view, wall in
            s.withPlane(wall) {
                for (corner, lift) in zip(corners, lifts) {
                    let at = wall.plane.coordinates(of: corner)
                    // The place the tile left, covered: the picture behind
                    // still shows the tile flat on the wall.
                    // Each box's front face lies on the marks' own surface, a
                    // centimeter proud of the wall, so a lifted face shows a
                    // mark exactly where its middle went.
                    let proud = SyntheticRoom.posterMarkLift
                    s.withState {
                        s.noLights()
                        s.fill(Color(hex: 0x15171A))
                        s.translate(at.x, at.y, proud)
                        s.drawBox(width: side, height: side, depth: 0.002)
                    }
                    s.withState {
                        s.fill(.white)
                        s.translate(at.x, at.y, proud - 0.001)
                        s.painted(with: view) {
                            s.translate(0, 0, lift)
                            s.drawBox(width: side, height: side, depth: 0.002)
                        }
                    }
                }
            }
        }
        recording.pause()
        var checked = 0, apart = 0.0
        for frame in 0..<made.frames {
            recording.seek(toFrame: frame)
            let pixels = try #require(RecordingPixels(try OllinApp.image(of: probe, frame: 0)))
            for (index, mark) in SyntheticRoom.posterMarks.enumerated() {
                guard let lifted = probe.projected[index], let rest = probe.projected[index + 4],
                      lifted.x > 24, lifted.y > 24, lifted.x < 616, lifted.y < 456,
                      rest.x > 24, rest.y > 24, rest.x < 616, rest.y < 456 else { continue }
                let seen = pixels.center(of: mark)
                #expect(seen.count > 40, "frame \(frame) corner \(index): the mark is not on the canvas")
                #expect(seen.point.distance(to: lifted) < 1.0,
                        "frame \(frame) corner \(index): the mark shows at \(seen.point), the lifted face puts it at \(lifted)")
                apart = max(apart, lifted.distance(to: rest))
                checked += 1
            }
        }
        #expect(checked > made.frames * 2, "the walk keeps the tiles in view (\(checked) checks)")
        #expect(apart > 12, "a lifted mark shows up to \(apart) pixels from where it was on the wall")
    }

    // MARK: A real thing hides a drawn one

    /// A ball drawn behind the real wall is hidden by it once the wall's
    /// surface is drawn as depth alone, and the frame is the plain picture
    /// again. In front of the wall the ball is whole.
    @Test func theWallHidesABallBehindIt() async throws {
        let made = try await Self.wallRecording(named: "hidden", frames: 4)
        defer { made.remove() }
        let recording = try PhoneRecording(path: made.folder.path)
        let probe = SurfaceProbe(playing: recording, width: 640, height: 480)
        func ball(_ s: SurfaceProbe, out: Double) {
            s.noLights()
            s.fill(Color(red: 0.9, green: 0.9, blue: 0.9))
            s.withState {
                s.translate(0.1, 1.5, SyntheticRoom.wallZ + out)
                s.drawSphere(radius: 0.3)
            }
        }
        recording.pause()
        for frame in 0..<made.frames {
            recording.seek(toFrame: frame)
            func render(_ scene: @escaping (SurfaceProbe, PhoneCamera, PhonePlane) -> Void) throws -> CGImage {
                probe.scene = scene
                return try OllinApp.image(of: probe, frame: 0)
            }
            let plain = try render { _, _, _ in }
            let shown = try render { s, _, _ in ball(s, out: -0.6) }
            #expect(difference(plain, shown).pixels > 2000,
                    "frame \(frame): the control, the ball shows with nothing to hide it")
            let hidden = try render { s, _, wall in
                s.occluding { s.drawMesh(wall.mesh) }
                ball(s, out: -0.6)
            }
            #expect(difference(plain, hidden).pixels == 0,
                    "frame \(frame): behind the wall the ball is hidden and the picture is untouched")
            let inFront = try render { s, _, wall in
                s.occluding { s.drawMesh(wall.mesh) }
                ball(s, out: 0.5)
            }
            let free = try render { s, _, _ in ball(s, out: 0.5) }
            #expect(difference(inFront, free).pixels == 0, "frame \(frame): in front of the wall it is whole")
        }
    }

    // MARK: The camera's own questions

    /// A ray through a canvas point and the canvas point of a place in the
    /// room undo each other, for every hold and crop, with no frame drawing.
    @Test func aRayAndACanvasPointUndoEachOther() {
        for turns in UInt8(0)..<4 {
            let sideways = turns % 2 == 1
            let room = SyntheticRoom(width: sideways ? 240 : 320, height: sideways ? 320 : 240, frames: 8)
            room.facesWall = true
            let made = SyntheticRecording(folder: URL(fileURLWithPath: "/dev/null"), room: room, frames: 8,
                                          framesPerSecond: 30, quarterTurnsCW: turns, firstTime: 0)
            let view = PhoneCamera(made.sensorCamera(at: 3))
            for canvas in [Vector2(320, 240), Vector2(240, 320), Vector2(300, 300), Vector2(640, 200)] {
                for point in SyntheticRoom.posterCorners + SyntheticRoom.marks.map(\.point) {
                    guard let onCanvas = view.canvasPoint(of: point, covering: canvas) else { continue }
                    let ray = view.ray(through: onCanvas, covering: canvas)
                    #expect(ray.distance(to: point) < 1e-6,
                            "turns \(turns), canvas \(canvas): the ray misses by \(ray.distance(to: point))")
                    // The picture's own pinhole rule, written in the room, agrees.
                    let placed = view.pictureRectangle(covering: canvas)
                    let scale = placed.width / Double(room.pictureWidth)
                    let inPicture = room.pixel(of: point, at: 3)
                    let expected = Vector2(placed.x + inPicture.x * scale, placed.y + inPicture.y * scale)
                    #expect(onCanvas.distance(to: expected) < 1e-3)
                }
            }
            #expect(view.canvasPoint(of: view.position - view.forward, covering: Vector2(320, 240)) == nil,
                    "a point behind the camera has no place on the canvas")
        }
    }

    // MARK: The example's recording

    /// Writes the recording the drawing-on-a-wall examples play: the synthetic
    /// room with its tiled wall and poster, without the marks, walked once
    /// round the loop that passes close along the wall by a phone held in
    /// portrait, with the room's surfaces and its light beside the frames. Run
    /// it with `OLLIN_WRITE_WALL_RECORDING` naming the folder to write. Like
    /// the first sample, it is written once and committed.
    @Test(.enabled(if: ProcessInfo.processInfo.environment["OLLIN_WRITE_WALL_RECORDING"] != nil,
                   "writes the examples' recording only when asked to"))
    func writesTheWallRecording() async throws {
        let path = try #require(ProcessInfo.processInfo.environment["OLLIN_WRITE_WALL_RECORDING"])
        let folder = URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
        try? FileManager.default.removeItem(at: folder)
        let made = try await SyntheticRecording.write(
            named: "wall", width: 540, height: 720, frames: 180, quarterTurnsCW: 1, mode: .room,
            to: folder, isLoop: true, showsMarks: false, bitRate: 1_000_000,
            wallDetail: true, facesWall: true
        ) { frame, time in
            var messages: [PhoneMessage] = []
            if frame == 0 {
                messages.append(.state(PhoneStateSample(
                    timestamp: time, mode: .room, isSupported: true, referenceCount: 0,
                    referencesAreDeclared: false, status: "A recording of a synthetic room", notes: [])))
                messages += SyntheticRecording.surfaces(at: time)
            }
            if frame % 6 == 0 {
                messages.append(.light(PhoneLightSample(timestamp: time, ambientIntensity: 1000,
                                                        colorTemperature: 5600)))
            }
            return messages
        }
        let recording = try PhoneRecording(path: made.folder.path)
        #expect(recording.frameCount == 180)
        #expect(recording.pictureSize == Vector2(540, 720))
    }
}
}
