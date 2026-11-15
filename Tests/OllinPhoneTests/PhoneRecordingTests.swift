import Testing
import CoreGraphics
import Foundation
import simd
import Ollin
@testable import OllinPhone

/// Plays a recording the way a sketch does and writes down where each marked
/// point of the room falls on the canvas, through the public calls alone.
private final class PinProbe: Sketch {
    var device: PhoneDevice?
    var canvas = (width: 320, height: 240)
    /// What the last drawn frame saw: the recording's frame, and each mark's
    /// place on the canvas.
    var seenFrame: Int?
    var pins: [Vector2?] = []

    convenience init(playing recording: PhoneRecording, width: Int, height: Int) {
        self.init()
        device = PhoneDevice(playing: recording)
        canvas = (width, height)
    }

    override var canvasSize: CanvasSize { .size(canvas.width, canvas.height) }

    override func setup() { device?.start() }

    override func draw() {
        background(.black)
        guard let view = device?.latestCamera else {
            seenFrame = nil
            return
        }
        drawPhonePicture(view)
        camera(view)
        seenFrame = view.frameIndex
        pins = SyntheticRoom.marks.map { project($0.point) }
    }
}

/// A recording of the phone's stream, proved on one the Mac writes itself: a
/// known room drawn through a moving camera, written by the writer the phone
/// runs, and read back.
///
/// It renders and it decodes video with the media engine, so it runs in the
/// device phase (`Scripts/test.sh`), beside the other suites that read video,
/// and inside `PhoneMediaTests`, which keeps it from running beside the
/// phone-screen suite.
extension PhoneMediaTests {
@MainActor
@Suite struct PhoneRecordingTests {

    // MARK: A pin lands on its picture

    /// A point drawn at a known place in the room lands on its own picture
    /// within a pixel, on every frame, held three ways: the phone held level
    /// and turned, and a canvas that crops the picture each way.
    @Test(arguments: [
        (UInt8(0), 320, 240),     // level, the picture's own proportion
        (UInt8(0), 240, 240),     // level, a square canvas crops the sides
        (UInt8(1), 240, 320),     // portrait, the picture's own proportion
        (UInt8(1), 300, 200),     // portrait, a wide canvas crops top and bottom
        (UInt8(3), 240, 320),     // the other portrait
        (UInt8(2), 320, 240),     // upside down
    ])
    func aPinLandsOnItsPicture(turns: UInt8, canvasWidth: Int, canvasHeight: Int) async throws {
        let sideways = turns % 2 == 1
        let made = try await SyntheticRecording.write(
            named: "pins", width: sideways ? 240 : 320, height: sideways ? 320 : 240,
            frames: 12, quarterTurnsCW: turns)
        defer { made.remove() }
        let recording = try PhoneRecording(path: made.folder.path)
        #expect(recording.frameCount == 12)
        #expect(recording.pictureSize == Vector2(Double(made.room.pictureWidth), Double(made.room.pictureHeight)))

        let probe = PinProbe(playing: recording, width: canvasWidth, height: canvasHeight)
        let canvas = Vector2(Double(canvasWidth), Double(canvasHeight))
        var checked = 0
        // Each frame is reached by its number with the recording held, so a
        // frame costs one render; following the clock has a test of its own.
        recording.pause()
        for frame in 0..<made.frames {
            recording.seek(toFrame: frame)
            let image = try OllinApp.image(of: probe, frame: 0)
            #expect(probe.seenFrame == frame)
            let pixels = try #require(RecordingPixels(image))
            let view = try recording.camera(at: frame)
            let placed = view.pictureRectangle(covering: canvas)
            let scale = placed.width / Double(made.room.pictureWidth)
            for (index, mark) in SyntheticRoom.marks.enumerated() {
                // Where the mark should be: the pinhole rule on the room's own
                // numbers, then the crop.
                let inPicture = made.room.pixel(of: mark.point, at: frame)
                let expected = Vector2(placed.x + inPicture.x * scale, placed.y + inPicture.y * scale)
                let margin = SyntheticRoom.markRadius * made.room.lens.fx * scale / 2 + 4
                guard expected.x > margin, expected.y > margin,
                      expected.x < canvas.x - margin, expected.y < canvas.y - margin else { continue }
                // Where the sketch puts it, through the recorded camera.
                let pin = try #require(probe.pins[index])
                #expect(pin.distance(to: expected) < 0.5,
                        "frame \(frame) mark \(index): the pin is \(pin), the room says \(expected)")
                // Where the picture shows it.
                let seen = pixels.center(of: mark)
                #expect(seen.count > 20, "frame \(frame) mark \(index) is not in the picture")
                #expect(seen.point.distance(to: pin) < 1.0,
                        "frame \(frame) mark \(index): drawn at \(seen.point), pinned at \(pin)")
                checked += 1
            }
        }
        // The walk keeps most marks in view; a crop may lose a few.
        #expect(checked > made.frames * 2)
    }

    /// The plant: a pin read one frame late misses its picture. Without this
    /// the walk could be too slow for the test above to tell frames apart.
    @Test func aPinFromTheWrongFrameMisses() async throws {
        let made = try await SyntheticRecording.write(named: "late", frames: 12)
        defer { made.remove() }
        let recording = try PhoneRecording(path: made.folder.path)
        let canvas = Vector2(320, 240)
        var worst = 0.0
        for frame in 1..<made.frames {
            let late = try recording.camera(at: frame - 1).camera3D(covering: canvas)
            let image = try #require(recording.uprightCGImage(at: frame))
            let pixels = try #require(RecordingPixels(image))
            for mark in SyntheticRoom.marks {
                let seen = pixels.center(of: mark)
                guard seen.count > 20, let pin = Self.project(mark.point, through: late, canvas: canvas)
                else { continue }
                worst = max(worst, seen.point.distance(to: pin))
            }
        }
        #expect(worst > 3)
    }

    /// The picture a recording hands back is the upright one, and the turn it
    /// took to stand it up is the turn the phone's other pictures take.
    @Test func thePictureComesBackUpright() async throws {
        let made = try await SyntheticRecording.write(named: "upright", width: 240, height: 320,
                                                      frames: 4, quarterTurnsCW: 1)
        defer { made.remove() }
        let recording = try PhoneRecording(path: made.folder.path)
        made.room.walkFrame = 2
        let original = try OllinApp.image(of: made.room, frame: 0)
        let drawn = try #require(RecordingPixels(original))
        let turned = try #require(recording.uprightCGImage(at: 2))
        let read = try #require(RecordingPixels(turned))
        #expect(read.width == 240 && read.height == 320)
        for mark in SyntheticRoom.marks {
            let before = drawn.center(of: mark), after = read.center(of: mark)
            guard before.count > 20 else { continue }
            #expect(after.count > 20)
            #expect(before.point.distance(to: after.point) < 1.0)
        }
    }

    // MARK: The two files hold the same frames

    /// A frame the writer dropped is gone from both files, and what is left
    /// still reads frame for frame.
    @Test func aDroppedFrameLeavesBothFiles() async throws {
        let made = try await SyntheticRecording.write(named: "dropped", frames: 10, skipping: [4, 7])
        defer { made.remove() }
        let recording = try PhoneRecording(path: made.folder.path)
        #expect(recording.frameCount == 8)
        // Frame 4 of the recording is frame 5 of the walk, and its time says so.
        let time = try recording.time(at: 4)
        #expect(abs(time - 5.0 / 30) < 0.001)
        let view = try recording.camera(at: 4)
        #expect(simd_distance(view.pose.columns.3, SyntheticRoom.pose(at: 5, of: 10).columns.3) < 1e-5)
    }

    /// A frame the video refuses is dropped by the writer from both files,
    /// counted, and the recording still reads frame for frame.
    @Test func theWriterDropsARefusedFrameFromBoth() async throws {
        let made = try await SyntheticRecording.write(named: "refused", frames: 10, repeatingTimeAt: [5])
        defer { made.remove() }
        let description = try PhoneRecordingDescription.read(
            from: made.folder.appendingPathComponent(PhoneRecordingFile.descriptionName))
        #expect(description.frameCount == 9)
        #expect(description.droppedFrames == 1)
        #expect(description.isFinished)
        let recording = try PhoneRecording(path: made.folder.path)
        #expect(recording.frameCount == 9)
        // Frame 5 of the recording is frame 6 of the walk.
        let view = try recording.camera(at: 5)
        #expect(simd_distance(view.pose.columns.3, SyntheticRoom.pose(at: 6, of: 10).columns.3) < 1e-5)
    }

    /// The plant the format exists to catch: a picture with no record, and a
    /// record with no picture. Each is two recordings' files crossed, so one
    /// file holds a frame the other lost.
    @Test func aFrameInOnlyOneFileIsCaught() async throws {
        let whole = try await SyntheticRecording.write(named: "whole", frames: 10)
        let short = try await SyntheticRecording.write(named: "short", frames: 10, skipping: [6])
        defer { whole.remove(); short.remove() }
        let manager = FileManager.default

        // The video kept frame 6 and the stream lost it.
        let crossed = whole.folder.deletingLastPathComponent()
            .appendingPathComponent("ollin-recording-crossed-\(UUID().uuidString).ollinrecording")
        defer { try? manager.removeItem(at: crossed) }
        try manager.copyItem(at: whole.folder, to: crossed)
        let stream = crossed.appendingPathComponent(PhoneRecordingFile.streamName)
        try manager.removeItem(at: stream)
        try manager.copyItem(at: short.folder.appendingPathComponent(PhoneRecordingFile.streamName), to: stream)
        #expect(throws: PhoneRecordingError.self) { try PhoneRecording(path: crossed.path) }

        // The same count in both, one frame apart from frame 6 on: the video
        // of the walk without frame 6 beside the records of its first nine.
        let shifted = whole.folder.deletingLastPathComponent()
            .appendingPathComponent("ollin-recording-shifted-\(UUID().uuidString).ollinrecording")
        defer { try? manager.removeItem(at: shifted) }
        let nine = try await SyntheticRecording.write(named: "nine", frames: 9)
        defer { nine.remove() }
        try manager.copyItem(at: nine.folder, to: shifted)
        let video = shifted.appendingPathComponent(PhoneRecordingFile.videoName)
        try manager.removeItem(at: video)
        try manager.copyItem(at: short.folder.appendingPathComponent(PhoneRecordingFile.videoName), to: video)
        do {
            _ = try PhoneRecording(path: shifted.path)
            Issue.record("a recording whose files are a frame apart opened")
        } catch PhoneRecordingError.framesDisagree(let frame) {
            #expect(frame == 6)
        }
    }

    // MARK: The stream reads back as the cable's

    /// Every message handed to the writer comes back from the file equal to
    /// what the cable would have delivered, a depth frame without its JPEG,
    /// and a big one stored smaller than it is.
    @Test func theFilesMessagesDecodeAsTheCables() async throws {
        let depth = PhoneDepthSample(
            isTracked: true, timestamp: 1000, depthWidth: 64, depthHeight: 48,
            fx: 50, fy: 50, cx: 32, cy: 24, cameraTransform: matrix_identity_float4x4,
            colorJPEG: Data([0xFF, 0xD8, 0xFF, 0xD9]),
            depth: (0..<64 * 48).map { 1 + Float($0 % 64) * 0.01 }, confidence: [UInt8](repeating: 2, count: 64 * 48))
        let light = PhoneLightSample(timestamp: 1000, ambientIntensity: 900, colorTemperature: 5200)
        let motion = PhoneMotionSample(attitude: SIMD4<Float>(0, 0, 0, 1), gravity: SIMD3<Float>(0, -1, 0),
                                       rotationRate: .zero, userAcceleration: .zero, timestamp: 1000)
        let sent: [PhoneMessage] = [.depth(depth), .light(light), .motion(motion)]

        let made = try await SyntheticRecording.write(named: "messages", frames: 3) { frame, _ in
            frame == 1 ? sent : []
        }
        defer { made.remove() }

        // Read the stream file with nothing but the format's own framing.
        let data = try Data(contentsOf: made.folder.appendingPathComponent(PhoneRecordingFile.streamName))
        #expect(PhoneRecordingStream.version(ofFileHeader: data) == PhoneRecordingFile.formatVersion)
        var offset = PhoneRecordingFile.streamHeaderByteCount
        var read: [PhoneMessage] = []
        var times: [Double] = []
        var depthStored = 0, depthFull = 0
        while let header = PhoneRecordingStream.recordHeader(in: data, at: offset) {
            let message = try #require(PhoneRecordingStream.message(of: header, in: data, at: offset))
            read.append(message)
            times.append(header.time)
            if header.kind == PhoneMessageKind.depth.rawValue {
                depthStored = header.storedLength
                depthFull = header.fullLength
                #expect(header.isCompressed)
            }
            offset += PhoneRecordingFile.recordHeaderByteCount + header.storedLength
        }
        #expect(offset == data.count)

        // Three camera records, numbered by the writer, and the three messages
        // after the second.
        var stripped = depth
        stripped.colorJPEG = Data()
        var expected: [PhoneMessage] = []
        for frame in 0..<3 {
            var camera = made.sensorCamera(at: frame)
            camera.frameIndex = UInt32(frame)
            expected.append(.camera(camera))
            if frame == 1 { expected += [.depth(stripped), .light(light), .motion(motion)] }
        }
        #expect(read == expected)
        #expect(times == times.sorted())
        #expect(depthStored < depthFull / 2)
        // And each is what the cable's own round trip gives.
        for message in expected { #expect(roundTrip(message) == message) }
    }

    /// A depth frame out of a recording takes its color from the video, as the
    /// sensor delivered it, and the rest of the device reads as it does on the
    /// cable.
    @Test func aDepthFrameTakesItsColorFromTheVideo() async throws {
        let made = try await SyntheticRecording.write(named: "depth", width: 240, height: 320, frames: 6,
                                                      quarterTurnsCW: 1) { frame, time in
            [.depth(PhoneDepthSample(
                isTracked: true, timestamp: time, depthWidth: 8, depthHeight: 6,
                fx: 6, fy: 6, cx: 4, cy: 3, cameraTransform: matrix_identity_float4x4,
                colorJPEG: Data([1, 2, 3]),
                depth: [Float](repeating: Float(frame) + 1, count: 48), confidence: nil)),
             .light(PhoneLightSample(timestamp: time, ambientIntensity: Float(100 * frame),
                                     colorTemperature: 5000))]
        }
        defer { made.remove() }
        let recording = try PhoneRecording(path: made.folder.path)
        let probe = PinProbe(playing: recording, width: 240, height: 320)
        _ = try OllinApp.image(of: probe, frame: 6)      // the recording's frame 3
        #expect(probe.seenFrame == 3)
        let frame = try #require(probe.device?.latestFrame)
        #expect(frame.depth.first == 4)
        // The sensor's picture, not the upright one: 320 wide, 240 tall.
        #expect(probe.device?.frameSize == Vector2(320, 240))
        #expect(probe.device?.latestLight?.lumens == 300)
        #expect(probe.device?.isRunning == true)
    }

    // MARK: The sketch's clock

    /// The recording stands where the sketch's clock says, the same in two
    /// runs, and a loop starts it over.
    @Test func itFollowsTheSketchsClock() async throws {
        let made = try await SyntheticRecording.write(named: "clock", frames: 8)
        defer { made.remove() }

        func run(_ frames: [Int]) throws -> [Int?] {
            let probe = PinProbe(playing: try PhoneRecording(path: made.folder.path), width: 160, height: 120)
            return try frames.map { frame in
                _ = try OllinApp.image(of: probe, frame: frame)
                return probe.seenFrame
            }
        }
        // Eight frames at 30 a second under a sketch at 60: each shows twice,
        // and the ninth frame's time is the first frame again.
        let asked = [0, 1, 2, 3, 9, 15, 16, 17]
        let expected: [Int?] = [0, 0, 1, 1, 4, 7, 0, 0]
        let first = try run(asked)
        #expect(first == expected)
        #expect(try run(asked) == first)

        // A sketch at the recording's own rate shows every frame once, in
        // order, twice round the loop: no frame repeated, none skipped.
        let recording = try PhoneRecording(path: made.folder.path)
        var shown: [Int] = []
        for tick in 0..<16 {
            recording.follow(clock: Double(tick) / 30)
            shown.append(recording.frameIndex)
        }
        #expect(shown == Array(0..<8) + Array(0..<8))
    }

    /// Two exports of one recording are the same pixels.
    @Test func twoRunsDrawTheSamePixels() async throws {
        let made = try await SyntheticRecording.write(named: "same", frames: 6)
        defer { made.remove() }
        func render() throws -> [Data] {
            let probe = PinProbe(playing: try PhoneRecording(path: made.folder.path), width: 160, height: 120)
            return try [0, 4, 9].map { frame in
                let image = try OllinApp.image(of: probe, frame: frame)
                return try #require(image.dataProvider?.data as Data?)
            }
        }
        #expect(try render() == render())
    }

    /// Held, moved by hand, and left to hold its last frame.
    @Test func itHoldsAndSeeks() async throws {
        let made = try await SyntheticRecording.write(named: "seek", frames: 8)
        defer { made.remove() }
        let recording = try PhoneRecording(path: made.folder.path)

        recording.follow(clock: 0)
        recording.follow(clock: 0.1)
        #expect(recording.frameIndex == 3)
        recording.pause()
        recording.follow(clock: 5)
        #expect(recording.frameIndex == 3)
        recording.seek(toFrame: 6)
        #expect(recording.frameIndex == 6)
        recording.play()
        recording.follow(clock: 5.2)            // the first look after play anchors
        recording.follow(clock: 5.2 + 1.0 / 30)
        #expect(recording.frameIndex == 7)
        recording.seek(to: 100)
        #expect(recording.frameIndex == 7)
        recording.seek(toFrame: -3)
        #expect(recording.frameIndex == 0)

        recording.loops = false
        recording.follow(clock: 10)
        recording.follow(clock: 20)
        #expect(recording.frameIndex == 7)
        #expect(recording.currentTime == recording.duration)
    }

    /// What adds up over a recording is, on any frame, what it was on that
    /// frame: a seek backward builds it again from the top.
    @Test func aSeekBackwardRebuildsWhatAddsUp() async throws {
        let ids = (0..<6).map { _ in UUID() }
        let made = try await SyntheticRecording.write(named: "planes", frames: 6, mode: .room) { frame, time in
            [.plane(PhonePlaneSample(
                isTracked: true, timestamp: time, id: ids[frame], scan: 1,
                transform: matrix_identity_float4x4, width: 1, height: 1,
                alignment: .horizontal, surface: .floor,
                boundary: [SIMD3<Float>(0, 0, 0), SIMD3<Float>(1, 0, 0), SIMD3<Float>(1, 0, 1)]))]
        }
        defer { made.remove() }
        let recording = try PhoneRecording(path: made.folder.path)
        #expect(recording.mode == .room)
        let probe = PinProbe(playing: recording, width: 160, height: 120)

        _ = try OllinApp.image(of: probe, frame: 10)     // the recording's frame 5
        #expect(probe.device?.planes.count == 6)
        _ = try OllinApp.image(of: probe, frame: 4)      // back to frame 2
        #expect(probe.seenFrame == 2)
        #expect(probe.device?.planes.count == 3)

        // The same by hand, in jumps: a jump takes several frames' records in
        // one go, and every surface among them has to arrive, not the newest
        // alone.
        let held = try PhoneRecording(path: made.folder.path)
        let device = PhoneDevice(playing: held)
        device.start()
        held.pause()
        device.advance(to: 0)
        #expect(device.planes.count == 1)
        held.seek(toFrame: 5)
        device.advance(to: 1)
        #expect(device.planes.count == 6)
        held.seek(toFrame: 2)
        device.advance(to: 2)
        #expect(device.planes.count == 3)
        #expect(device.latestCamera?.frameIndex == 2)
    }

    // MARK: What does not open

    @Test func aMissingOrBrokenFolderThrows() async throws {
        #expect(throws: PhoneRecordingError.self) { try PhoneRecording(path: "/nowhere/at/all.ollinrecording") }

        let made = try await SyntheticRecording.write(named: "broken", frames: 4)
        defer { made.remove() }
        let manager = FileManager.default
        let description = made.folder.appendingPathComponent(PhoneRecordingFile.descriptionName)

        // A newer format than this reader knows.
        var newer = try PhoneRecordingDescription.read(from: description)
        let good = newer
        newer.format = PhoneRecordingFile.formatVersion + 1
        try newer.write(to: description)
        do {
            _ = try PhoneRecording(path: made.folder.path)
            Issue.record("a newer format opened")
        } catch PhoneRecordingError.newerFormat(let version) {
            #expect(version == PhoneRecordingFile.formatVersion + 1)
        }
        try good.write(to: description)
        #expect(try PhoneRecording(path: made.folder.path).isComplete)

        // A stream cut off inside a record, in a recording that says it was
        // closed properly.
        let stream = made.folder.appendingPathComponent(PhoneRecordingFile.streamName)
        let bytes = try Data(contentsOf: stream)
        try bytes.dropLast(7).write(to: stream)
        #expect(throws: PhoneRecordingError.self) { try PhoneRecording(path: made.folder.path) }

        // One of the three files gone.
        try manager.removeItem(at: stream)
        #expect(throws: PhoneRecordingError.self) { try PhoneRecording(path: made.folder.path) }
    }

    /// A frame number outside the recording is refused by name.
    @Test func aFrameOutsideTheRecordingThrows() async throws {
        let made = try await SyntheticRecording.write(named: "range", frames: 4)
        defer { made.remove() }
        let recording = try PhoneRecording(path: made.folder.path)
        #expect(throws: PhoneRecordingError.self) { try recording.camera(at: 4) }
        #expect(throws: PhoneRecordingError.self) { try recording.picture(at: -1) }
    }

    /// A recording whose app was stopped mid-way never traps a reader: it
    /// opens as far as both files go and says it is not complete, or it
    /// throws.
    @Test func anUnfinishedRecordingNeverTraps() async throws {
        let made = try await SyntheticRecording.write(named: "unfinished", frames: 40, finish: false)
        defer { made.remove() }
        // The writer is still open, as the app's would be when it is stopped.
        let copy = made.folder.deletingLastPathComponent()
            .appendingPathComponent("ollin-recording-stopped-\(UUID().uuidString).ollinrecording")
        defer { try? FileManager.default.removeItem(at: copy) }
        try FileManager.default.copyItem(at: made.folder, to: copy)
        do {
            let recording = try PhoneRecording(path: copy.path)
            #expect(!recording.isComplete)
            #expect(recording.frameCount <= 40)
            _ = try recording.picture(at: recording.frameCount - 1)
        } catch is PhoneRecordingError {
            // Nothing playable had reached the disk yet.
        }
    }

    /// The newest recording in a folder comes first.
    @Test func itListsAFoldersRecordings() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("ollin-recordings-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        for (name, age) in [("old", -200.0), ("new", -10.0), ("middle", -100.0)] {
            let folder = root.appendingPathComponent("\(name).ollinrecording")
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSinceNow: age)],
                                                  ofItemAtPath: folder.path)
        }
        try FileManager.default.createDirectory(at: root.appendingPathComponent("not-one"),
                                                withIntermediateDirectories: true)
        let found = PhoneRecording.availableRecordings(in: root.path).map {
            URL(fileURLWithPath: $0).deletingPathExtension().lastPathComponent
        }
        #expect(found == ["new", "middle", "old"])
        #expect(PhoneRecording.availableRecordings(in: "/nowhere/at/all").isEmpty)
    }

    // MARK: The camera's own arithmetic

    /// The camera record crosses the wire whole.
    @Test func theCameraRecordRoundTrips() {
        var transform = matrix_identity_float4x4
        transform.columns.3 = SIMD4<Float>(0.5, 1.4, -2, 1)
        let sample = PhoneCameraSample(isTracked: true, timestamp: 4321.5, frameIndex: 77,
                                       imageWidth: 1920, imageHeight: 1440,
                                       fx: 1450.5, fy: 1451.25, cx: 958, cy: 722.5,
                                       transform: transform, quarterTurnsCW: 1)
        #expect(roundTrip(.camera(sample)) == .camera(sample))
    }

    /// Four quarter turns of a lens are the lens it started as, and one turn
    /// moves the point the lens looks through with the pixels.
    @Test func aLensTurnsWithItsPicture() {
        let start = (fx: Float(1000), fy: Float(1010), cx: Float(700), cy: Float(400), width: 1920, height: 1080)
        var lens = start
        for _ in 0..<4 {
            lens = PhoneWire.uprightLens(fx: lens.fx, fy: lens.fy, cx: lens.cx, cy: lens.cy,
                                         width: lens.width, height: lens.height, quarterTurnsCW: 1)
        }
        #expect(lens == start)
        // A quarter turn clockwise: a pixel (u, v) lands at (height - v, u).
        let once = PhoneWire.uprightLens(fx: 1000, fy: 1010, cx: 700, cy: 400,
                                         width: 1920, height: 1080, quarterTurnsCW: 1)
        #expect(once.cx == 1080 - 400 && once.cy == 700)
        #expect(once.fx == 1010 && once.fy == 1000)
        #expect(once.width == 1080 && once.height == 1920)
    }

    // MARK: The recording the example plays

    /// Writes the small recording `Examples/3D/Phone/PhoneRecordingPins` plays:
    /// the synthetic room without its marks, walked once round a loop by a
    /// phone held in portrait, with the room's surfaces and its light beside
    /// the frames. Run it with `OLLIN_WRITE_SAMPLE_RECORDING` naming the folder
    /// to write; an encoder's bytes differ from one system to the next, so the
    /// recording is written once and committed, never rebuilt by a test run.
    @Test(.enabled(if: ProcessInfo.processInfo.environment["OLLIN_WRITE_SAMPLE_RECORDING"] != nil,
                   "writes the example's recording only when asked to"))
    func writesTheSampleRecording() async throws {
        let path = try #require(ProcessInfo.processInfo.environment["OLLIN_WRITE_SAMPLE_RECORDING"])
        let folder = URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
        try? FileManager.default.removeItem(at: folder)

        func plane(_ index: UInt8, _ surface: PhoneSurface, _ alignment: PhonePlaneAlignment,
                   _ transform: simd_float4x4, width: Float, height: Float, at time: Double) -> PhoneMessage {
            let id = UUID(uuid: (0x0A, 0x11, 0x1E, 0x50, 0, 0, 0x40, 0, 0x80, 0, 0, 0, 0, 0, 0, index))
            return .plane(PhonePlaneSample(isTracked: true, timestamp: time, id: id, scan: 1,
                                           transform: transform, width: width, height: height,
                                           alignment: alignment, surface: surface))
        }
        func placed(_ x: SIMD3<Float>, _ y: SIMD3<Float>, _ z: SIMD3<Float>, _ t: SIMD3<Float>) -> simd_float4x4 {
            simd_float4x4(SIMD4<Float>(x, 0), SIMD4<Float>(y, 0), SIMD4<Float>(z, 0), SIMD4<Float>(t, 1))
        }
        let level = (SIMD3<Float>(1, 0, 0), SIMD3<Float>(0, 1, 0), SIMD3<Float>(0, 0, 1))
        let table = SyntheticRoom.solids[0]

        let made = try await SyntheticRecording.write(
            named: "sample", width: 540, height: 720, frames: 150, quarterTurnsCW: 1, mode: .room,
            to: folder, isLoop: true, showsMarks: false, bitRate: 1_100_000
        ) { frame, time in
            var messages: [PhoneMessage] = []
            if frame == 0 {
                messages.append(.state(PhoneStateSample(
                    timestamp: time, mode: .room, isSupported: true, referenceCount: 0,
                    referencesAreDeclared: false, status: "A recording of a synthetic room", notes: [])))
                // The floor, the back wall's face, and the top of the first solid.
                messages.append(plane(1, .floor, .horizontal,
                                      placed(level.0, level.1, level.2, .zero),
                                      width: 7, height: 7, at: time))
                messages.append(plane(2, .wall, .vertical,
                                      placed(SIMD3<Float>(1, 0, 0), SIMD3<Float>(0, 0, 1), SIMD3<Float>(0, -1, 0),
                                             SIMD3<Float>(0, 1.5, -1.55)),
                                      width: 7, height: 3, at: time))
                messages.append(plane(3, .table, .horizontal,
                                      placed(level.0, level.1, level.2,
                                             SIMD3<Float>(Float(table.center.x),
                                                          Float(table.center.y + table.size.y / 2),
                                                          Float(table.center.z))),
                                      width: Float(table.size.x), height: Float(table.size.z), at: time))
            }
            if frame % 6 == 0 {
                messages.append(.light(PhoneLightSample(timestamp: time, ambientIntensity: 1000,
                                                        colorTemperature: 5600)))
            }
            return messages
        }
        let recording = try PhoneRecording(path: made.folder.path)
        #expect(recording.frameCount == 150)
        #expect(recording.pictureSize == Vector2(540, 720))
    }

    // MARK: Support

    /// A point of the room on a canvas through a camera, by the camera's own
    /// matrices.
    private static func project(_ point: Vector3, through camera: Camera3D, canvas: Vector2) -> Vector2? {
        let clip = camera.viewProjectionMatrix(aspect: canvas.x / canvas.y)
            * SIMD4<Float>(Float(point.x), Float(point.y), Float(point.z), 1)
        guard clip.w > 0 else { return nil }
        return Vector2((Double(clip.x / clip.w) + 1) / 2 * canvas.x,
                       (1 - Double(clip.y / clip.w)) / 2 * canvas.y)
    }
}
}
