import Foundation
import Ollin
import OllinPhone

/// A recording the phone made, played back as if the phone were plugged in,
/// with things pinned in the room it shows.
///
/// Press **Record** in Ollin Capture, with no cable, and the phone writes the
/// camera's video with where the camera stood beside every frame. Here a sketch
/// plays one back through the same `PhoneDevice` the cable feeds, draws the
/// camera's picture to fill the canvas, sets a 3D camera that matches the
/// phone's, and stands a few things in the room in meters. They hold their
/// places as the camera moves, because the camera drawing them is the one that
/// filmed the room.
///
/// The recording bundled here is a stand-in: a small room drawn on the Mac and
/// written with the writer the phone runs, held in portrait, so the sketch
/// runs with no phone at all. To play one of your own, bring its folder over
/// from the phone (the Files app and Finder both show Ollin Capture's
/// documents) and set `OLLIN_PHONE_RECORDING` to its path. The pins then stand
/// in a row two meters in front of where your recording began.
///
/// Nothing drawn here hides behind a real thing yet: a pin placed behind a
/// table draws over the table.
///
/// Keys: **space** holds the recording and carries on, and while it is held
/// the **left** and **right** arrows step a frame at a time.
@main
final class PhoneRecordingPins: Sketch {

    override var canvasSize: CanvasSize { .size(1080, 1440) }

    /// One lap of the recording, so an export of this sketch loops.
    override var loopDuration: Double? {
        let recording = device.recording
        guard let recording, recording.frameRate > 0 else { return nil }
        return recording.duration + 1 / recording.frameRate
    }

    /// The recording, played through the device object the cable feeds. It is
    /// a property of the sketch so the sketch's clock reaches it.
    let device = PhoneDevice(playing: PhoneRecordingPins.open())

    /// One thing standing in the room: where, what it is called, and its color.
    struct Pin {
        var point: Vector3
        var name: String
        var color: Color
    }

    /// The bundled room's own points, in meters: the top of each solid, and a
    /// spot on the floor in front of them.
    static let roomPins: [Pin] = [
        Pin(point: Vector3(-1.2, 0.7, -0.6), name: "cube", color: Color(hex: 0xFF7A59)),
        Pin(point: Vector3(-0.9, 1.2, -1.2), name: "post", color: Color(hex: 0x8FB3FF)),
        Pin(point: Vector3(1.1, 1.0, -0.9), name: "column", color: Color(hex: 0x7DE0A6)),
        Pin(point: Vector3(0.9, 0.4, 0.7), name: "block", color: Color(hex: 0xFFD166)),
        Pin(point: Vector3(-0.1, 0, 0.9), name: "floor", color: Color(hex: 0xF2F0EA)),
    ]

    var pins: [Pin] = []
    var note: String?

    /// The recording to play: your own when `OLLIN_PHONE_RECORDING` names one
    /// that opens, the bundled room otherwise.
    static func open() -> PhoneRecording {
        if let path = ProcessInfo.processInfo.environment["OLLIN_PHONE_RECORDING"],
           let own = try? PhoneRecording(path: path) {
            return own
        }
        return try! PhoneRecording(resource: "Room", withExtension: "ollinrecording", in: .module)
    }

    override func setup() {
        textFont(OutlineFont.system)
        device.start()
        guard let recording = device.recording else { return }

        if let path = ProcessInfo.processInfo.environment["OLLIN_PHONE_RECORDING"] {
            if recording.path == (path as NSString).expandingTildeInPath {
                pins = Self.row(inFrontOf: recording)
            } else {
                // The path was given and did not open: say why, and play the room.
                do { _ = try PhoneRecording(path: path) } catch { note = "\(error)" }
                pins = Self.roomPins
            }
        } else {
            pins = Self.roomPins
        }
    }

    /// Five pins in a row, two meters in front of where a recording began and
    /// about where its floor is: a place that exists in any recording.
    static func row(inFrontOf recording: PhoneRecording) -> [Pin] {
        guard let start = try? recording.camera(at: 0) else { return [] }
        var ahead = Vector3(start.forward.x, 0, start.forward.z)
        ahead = ahead.length > 1e-6 ? ahead.normalized : Vector3(0, 0, -1)
        let side = ahead.cross(.unitY)
        let floor = start.position.y - 1.3
        return roomPins.enumerated().map { index, pin in
            let offset = side * (Double(index - 2) * 0.5)
            let base = start.position + ahead * 2 + offset
            return Pin(point: Vector3(base.x, floor, base.z), name: pin.name, color: pin.color)
        }
    }

    override func draw() {
        background(.black)
        guard let view = device.latestCamera else {
            return drawStatus(device.waitingMessage, style: .info)
        }

        // The camera's picture, filling the canvas, and the camera that took it.
        drawPhonePicture(view)
        camera(view)

        // Lit the way the room was lit: the phone measured its light, and the
        // recording kept the readings.
        if let light = device.latestLight { ambientLight(light.ambient) }
        directionalLight(.white, direction: Vector3(-0.45, -1, -0.55))

        noStroke()
        for (index, pin) in pins.enumerated() { draw(pin, index: index) }

        drawCaption(caption(view))
    }

    /// A pin: a ring on its spot, a post up from it, a ball that bobs at the
    /// top, and its name.
    private func draw(_ pin: Pin, index: Int) {
        // Two bobs to the lap, so the last frame of a lap meets the first.
        let lap = loopDuration ?? 5
        let rise = 0.32 + 0.05 * sin(.tau * 2 * time / lap + Double(index) * 1.3)
        let top = pin.point + Vector3(0, rise, 0)

        withoutLights {
            fill(pin.color)
            let ring = (0..<40).map { step -> Vector3 in
                let a = Double(step) / 40 * .tau
                return pin.point + Vector3(cos(a) * 0.12, 0.004, sin(a) * 0.12)
            }
            drawTube(ring, radius: 0.006, sides: 5, closed: true)
            drawTube([pin.point, top], radius: 0.005, sides: 5)
        }

        withState {
            material(.dielectric(roughness: 0.35))
            fill(pin.color)
            translate(top)
            drawSphere(radius: 0.07)
        }

        drawText(pin.name, at: top + Vector3(0, 0.12, 0), size: 26,
                 color: .white, align: .center, .bottom)
    }

    private func caption(_ view: PhoneCamera) -> String {
        guard let recording = device.recording else { return "" }
        if let note { return note }
        let held = recording.isPlaying ? "" : "  held"
        return "\(recording.name)  frame \(view.frameIndex + 1) of \(recording.frameCount)\(held)"
    }

    override func keyPressed() {
        guard let recording = device.recording else { return }
        if key == " " {
            if recording.isPlaying { recording.pause() } else { recording.play() }
        } else if !recording.isPlaying {
            if keyCode == .leftArrow { recording.seek(toFrame: recording.frameIndex - 1) }
            if keyCode == .rightArrow { recording.seek(toFrame: recording.frameIndex + 1) }
        }
    }
}
