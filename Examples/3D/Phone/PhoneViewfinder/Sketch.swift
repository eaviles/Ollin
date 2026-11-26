import Foundation
import Ollin
import OllinPhone

/// The phone in the hand as the viewfinder of a sketch that runs on the Mac.
///
/// Setup: install **Ollin Capture** on an iPhone, launch it, and connect the
/// cable. The sketch asks the phone for **Room** mode, which follows the room
/// and finds its flat surfaces, and puts itself on the phone's screen. From
/// there the loop runs both ways down one cable. The camera's picture comes up
/// to the Mac as video, with where the camera stood for each frame. The sketch
/// draws that picture, looks through a 3D camera that matches the phone's, and
/// stands things in the room. What it drew goes back to the phone's screen.
///
/// Tap the phone's screen on a floor, a table, or a wall, and a small stack of
/// blocks grows out of the surface there. The first finger on the phone is the
/// sketch's pointer, so the tap arrives as `mousePressed()`; the line of sight
/// through it (`view.ray(through:covering:)`) is met with the surfaces the
/// phone has found, and the place they meet is kept in the sketch. Walk
/// around: each stack stays where it was put, and a real table hides a stack
/// behind it, because the surfaces are also drawn as depth alone
/// (`occluding { }`).
///
/// Nothing is built for the phone or installed on it. Save this file under the
/// live window and the phone shows the edit as soon as the Mac has compiled
/// it, with the stacks still standing.
///
/// With no phone on the cable the same `draw()` plays a recording instead: a
/// small room drawn on the Mac and written with the writer the phone runs. A
/// click in the window plants a stack on its floor the way a tap does. That is
/// the point of reading the phone through one object: a piece worked out on a
/// recording at the desk is the piece the phone shows live. An export always
/// plays the recording, so it shows the same frames every time and never
/// films the room the phone happens to be in.
///
/// Keys: **R** clears the stacks.
@main
final class PhoneViewfinder: Sketch {

    /// The camera's own proportion, held upright: three across, four down.
    override var canvasSize: CanvasSize { .size(1080, 1440) }

    /// One lap of the recording, so an export with no phone attached loops.
    override var loopDuration: Double? {
        guard !isLive, let recording = recorded.recording, recording.frameRate > 0 else { return nil }
        return recording.duration + 1 / recording.frameRate
    }

    /// The phone on the cable.
    let phone = PhoneDevice()

    /// A recording of a room, played while no phone is on the cable. Both are
    /// properties of the sketch, so the sketch's clock reaches the recording.
    let recorded = PhoneDevice(playing: try! PhoneRecording(resource: "Room", withExtension: "ollinrecording",
                                                            in: .module))

    /// Whether the phone is on the cable and this is not an export.
    var isLive: Bool { phone.isLive && !isExporting }

    /// Whichever has a room to show: the phone when it is there.
    var device: PhoneDevice { isLive ? phone : recorded }

    /// One stack: the place it grows from, as a plane of its own whose origin
    /// is the spot and whose z points out of the surface, and when it was put.
    struct Stack {
        var place: Plane3
        var planted: Double
        var hue: Double
    }

    /// The stacks in the phone's room, and the ones in the recorded room. The
    /// two rooms are different places, so each keeps its own.
    var liveStacks: [Stack] = []
    var recordedStacks: [Stack] = PhoneViewfinder.roomStacks

    /// Three stacks that stand in the bundled room from the start: on its
    /// floor, on its cube, and on its block.
    static let roomStacks: [Stack] = [
        Vector3(-0.1, 0, 0.9), Vector3(-1.2, 0.7, -0.6), Vector3(0.9, 0.4, 0.7),
    ].enumerated().map { index, spot in
        Stack(place: Plane3(origin: spot, normal: .unitY, up: Vector3(0, 0, -1)),
              planted: -10, hue: 0.07 + Double(index) * 0.27)
    }

    static let inks = [Color(hex: 0xF25C3B), Color(hex: 0xF2B63B), Color(hex: 0x7DE0A6), Color(hex: 0x8FB3FF)]

    override func setup() {
        textFont(OutlineFont.system)
        // The phone follows the room, and its screen shows this sketch. An
        // export leaves the phone alone.
        if !isExporting {
            phone.use(.room)
            phone.show(self)
        }
        recorded.start()
    }

    override func draw() {
        background(.black)
        guard let view = device.latestCamera else {
            return drawStatus(device.waitingMessage, style: .info)
        }

        // The camera's picture, filling the canvas, and the camera that took
        // it. On the cable, reading the picture is what asks the phone for it.
        drawPhonePicture(view)
        camera(view)

        // The surfaces the phone found, as depth alone: a real table hides
        // what is drawn behind it.
        let surfaces = device.planes.planes
        occluding { for surface in surfaces { drawMesh(surface.mesh) } }

        // Lit the way the room is lit.
        if let light = device.latestLight { ambientLight(light.ambient) }
        directionalLight(.white, direction: Vector3(-0.45, -1, -0.55))
        noStroke()
        material(.dielectric(roughness: 0.4))
        for stack in isLive ? liveStacks : recordedStacks { draw(stack) }

        drawCaption(caption(view, surfaces: surfaces.count))
    }

    /// A stack: four blocks, each smaller than the one under it, growing out
    /// of the surface one after another and turning a little as they settle.
    private func draw(_ stack: Stack) {
        withPlane(stack.place) {
            var base = 0.0
            for level in 0..<4 {
                // Each block arrives a tenth of a second after the one below.
                let age = (time - stack.planted - Double(level) * 0.1) / 0.35
                let grown = age <= 0 ? 0 : age >= 1 ? 1 : age * age * (3 - 2 * age)
                guard grown > 0 else { break }
                let side = 0.16 - Double(level) * 0.03
                let tall = 0.07 * grown
                withState {
                    fill(Self.inks[(level + Int(stack.hue * 10)) % Self.inks.count])
                    translate(0, 0, base + tall / 2)
                    rotateZ((1 - grown) * 0.8 + Double(level) * 0.35 + stack.hue * 6)
                    drawBox(width: side, height: side, depth: tall)
                }
                base += tall
            }
        }
    }

    private func caption(_ view: PhoneCamera, surfaces: Int) -> String {
        if isLive {
            if view.picture == nil { return "Waiting for the camera's picture" }
            if surfaces == 0 { return "Move the phone slowly so it can find a floor or a table" }
            return "Tap the phone's screen on a surface to stand something there"
        }
        return "A recording. Connect an iPhone running Ollin Capture and the phone is the viewfinder"
    }

    // MARK: Planting

    /// A tap on the phone, or a click in the window: the line of sight through
    /// it, met with the nearest surface it passes through.
    override func mousePressed() {
        guard let view = device.latestCamera else { return }
        let ray = view.ray(through: mouse, covering: Vector2(width, height))
        var nearest: (distance: Double, place: Plane3)?
        for surface in device.planes.planes {
            let plane = surface.plane
            guard let spot = plane.intersection(with: ray) else { continue }
            // On the surface itself, not on the endless plane it lies in.
            let onSurface = plane.coordinates(of: spot)
            guard abs(onSurface.x) <= surface.width / 2, abs(onSurface.y) <= surface.height / 2 else { continue }
            let distance = (spot - view.position).length
            if nearest == nil || distance < nearest!.distance {
                nearest = (distance, plane.moved(by: onSurface))
            }
        }
        guard let nearest else { return }
        let stack = Stack(place: nearest.place, planted: time, hue: random(0, 1))
        if isLive { liveStacks.append(stack) } else { recordedStacks.append(stack) }
    }

    override func keyPressed() {
        guard key == "r" else { return }
        if isLive { liveStacks = [] } else { recordedStacks = Self.roomStacks }
    }
}
