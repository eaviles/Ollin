import Foundation
import Ollin
import OllinPhone

/// A new picture over a poster on a real wall.
///
/// A recording the phone made plays back, and the poster on its wall is
/// replaced: a layer the sketch draws every frame is laid on the poster's four
/// corners and stays on them as the camera moves. The shapes of the new
/// poster then leave it. Three balls circle out into the room and back in
/// through the wall, and the wall hides the half of each that is behind it.
///
/// A corner is a point of the room kept in the sketch. It comes from a click:
/// the line of sight through the click (`view.ray(through:covering:)`) is met
/// with the wall the phone found, and the place they meet is on the wall for
/// good. `drawImage(_:topLeft:topRight:bottomRight:bottomLeft:)` lays the
/// layer on four of them exactly, however the wall is turned to the camera.
/// And `occluding { }` draws the wall's surface as depth alone, which is what
/// lets a real wall hide a drawn ball.
///
/// The recording bundled here is a stand-in: a small room drawn on the Mac
/// and written with the writer the phone runs, with its poster's corners
/// already pinned below. To pin your own, hold the recording with **space**
/// and click the poster's four corners, top left first and round to the
/// right. To play a recording of your own, make it in **Room** mode, which is
/// the mode that finds surfaces, and set `OLLIN_PHONE_RECORDING` to its path.
///
/// Keys: **space** holds the recording and carries on, **R** forgets the
/// corners.
@main
final class PhonePoster: Sketch {

    override var canvasSize: CanvasSize { .size(1080, 1440) }

    /// One lap of the recording, so an export of this sketch loops.
    override var loopDuration: Double? {
        guard let recording = device.recording, recording.frameRate > 0 else { return nil }
        return recording.duration + 1 / recording.frameRate
    }

    let device = PhoneDevice(playing: PhonePoster.open())

    /// The poster's corners in the room, in meters: top left, top right,
    /// bottom right, bottom left. These are the bundled room's.
    var corners: [Vector3] = PhonePoster.roomCorners
    static let roomCorners = [
        Vector3(0.2, 2.225, -1.54), Vector3(0.9, 2.225, -1.54),
        Vector3(0.9, 1.275, -1.54), Vector3(0.2, 1.275, -1.54),
    ]

    /// The new poster, drawn flat every frame.
    var layer: RenderTarget!
    static let sheet = (width: 700.0, height: 950.0)

    /// The three colors of the new poster, and of the balls that leave it.
    static let inks = [Color(hex: 0xF25C3B), Color(hex: 0x2F7DD1), Color(hex: 0xF2B63B)]

    static func open() -> PhoneRecording {
        if let path = ProcessInfo.processInfo.environment["OLLIN_PHONE_RECORDING"],
           let own = try? PhoneRecording(path: path) {
            return own
        }
        return try! PhoneRecording(resource: "Wall", withExtension: "ollinrecording", in: .module)
    }

    override func setup() {
        textFont(OutlineFont.system)
        layer = makeRenderTarget(width: Int(Self.sheet.width), height: Int(Self.sheet.height))
        device.start()
        // Another recording has another wall, and its poster is yours to pin.
        if let path = ProcessInfo.processInfo.environment["OLLIN_PHONE_RECORDING"],
           device.recording?.path == (path as NSString).expandingTildeInPath {
            corners = []
        }
    }

    /// The lap's phase, 0 to 1, so everything that moves comes back round.
    private var lap: Double {
        let length = loopDuration ?? 6
        return (time / length).truncatingRemainder(dividingBy: 1)
    }

    override func draw() {
        background(.black)
        drawSheet()

        guard let view = device.latestCamera else {
            return drawStatus(device.waitingMessage, style: .info)
        }
        drawPhonePicture(view)
        camera(view)
        guard let wall = device.planes.largest(of: .wall) ?? device.planes.largest else {
            return drawCaption("This recording carries no surface. Record in Room mode to get one.")
        }

        // Lit the way the room was lit, for the balls.
        if let light = device.latestLight { ambientLight(light.ambient) }
        directionalLight(.white, direction: Vector3(-0.45, -1, -0.55))
        noStroke()

        guard corners.count == 4 else {
            // Mark what has been pinned so far.
            for corner in corners {
                withState {
                    noLights()
                    fill(Self.inks[0])
                    translate(corner)
                    drawSphere(radius: 0.02)
                }
            }
            return drawCaption("Hold with space, then click the poster's corners: \(corners.count) of 4")
        }

        // The layer, on the four corners.
        drawImage(layer.image, topLeft: corners[0], topRight: corners[1],
                  bottomRight: corners[2], bottomLeft: corners[3])

        // The wall as depth alone: from here on it hides what goes behind it.
        occluding { drawMesh(wall.mesh) }

        // Three balls on a circle that stands square to the wall, half of it
        // in the room and half behind the plaster.
        let middle = (corners[0] + corners[2]) / 2
        let surface = wall.plane
        material(.dielectric(roughness: 0.3))
        for (index, ink) in Self.inks.enumerated() {
            let turn = .tau * (lap + Double(index) / 3)
            let along = [Vector2(0, 1), Vector2(0.87, -0.5), Vector2(-0.87, -0.5)][index]
            let reach = 0.42
            let onWall = surface.coordinates(of: middle) + along * (reach * cos(turn))
            withState {
                fill(ink)
                translate(surface.point(at: onWall, lift: reach * sin(turn)))
                drawSphere(radius: 0.09)
            }
        }
        drawCaption("A new picture on the poster, and its shapes passing through the wall")
    }

    /// The new poster: three discs that swell in turn over a dark sheet, in
    /// the layer's own pixels.
    private func drawSheet() {
        withTarget(layer) {
            let w = Self.sheet.width, h = Self.sheet.height
            background(Color(hex: 0x14161B))
            noStroke()
            for (index, ink) in Self.inks.enumerated() {
                let beat = 0.5 + 0.5 * sin(.tau * (lap * 3 + Double(index) / 3))
                let center = Vector2(w * (0.3 + 0.2 * Double(index)), h * (0.3 + 0.2 * Double(index)))
                fill(ink.withAlpha(0.3))
                drawCircle(center.x, center.y, w * (0.2 + 0.1 * beat))
                fill(ink)
                drawCircle(center.x, center.y, w * (0.09 + 0.07 * beat))
            }
            noFill()
            stroke(Color(hex: 0xECE7DC))
            strokeWeight(14)
            drawRect(7, 7, w - 14, h - 14)
        }
    }

    // MARK: Pinning

    override func mousePressed() {
        // A click is a corner while the recording is held and corners are owed.
        guard corners.count < 4, let recording = device.recording, !recording.isPlaying,
              let view = device.latestCamera,
              let wall = device.planes.largest(of: .wall) ?? device.planes.largest else { return }
        let ray = view.ray(through: mouse, covering: Vector2(width, height))
        // A centimeter proud of the wall, as a sheet of paper is.
        if let spot = wall.plane.moved(by: .zero, lift: 0.01).intersection(with: ray) {
            corners.append(spot)
        }
    }

    override func keyPressed() {
        guard let recording = device.recording else { return }
        if key == " " {
            if recording.isPlaying { recording.pause() } else { recording.play() }
        } else if key == "r" {
            corners = []
        }
    }
}
