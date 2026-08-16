import Foundation
import Ollin
import OllinPhone

/// Point a tethered iPhone around a room and watch the flat surfaces in it arrive:
/// the floor, the walls, a table top, a seat. Each one is drawn as its real outline,
/// painted by what the phone thinks it is, and a ball stands on the biggest flat one.
///
/// `PhoneRoomMesh` draws the whole shape of the room, down to the clutter. This is
/// the short summary of the same room, and the useful one when you want somewhere to
/// put something. It also needs no LiDAR: a phone with an ordinary camera finds flat
/// surfaces perfectly well.
///
/// The scene is lit by the room itself. The phone measures how bright and how warm
/// the light around it is, in every capture mode, so a sketch can match the room it
/// is standing in. Turn a lamp on or walk toward a window and the ball changes color.
///
/// Setup: install **Ollin Capture** on the iPhone, launch it, tap the **Room**
/// segment, and connect the cable. Then look slowly around the room.
///
/// Keys: **space** switches between the painted surfaces and plain ones, **F** keeps
/// only the flat ones, **M** shows the reconstructed surface behind them (LiDAR
/// phones), **L** switches between the room's light and a studio rig, and **R**
/// starts again.
@main
final class PhoneRoomPlanes: Sketch {

    let device = PhoneDevice()

    /// What each label is painted, and the order a legend reads them in.
    static let palette: [(PhoneSurface, Color)] = [
        (.floor,        Color(hex: 0x4C9A6B)),
        (.wall,         Color(hex: 0x8891A6)),
        (.ceiling,      Color(hex: 0x6F7FA8)),
        (.table,        Color(hex: 0xD8A24A)),
        (.seat,         Color(hex: 0xC96A5A)),
        (.window,       Color(hex: 0x6FC6D8)),
        (.door,         Color(hex: 0xB07AC4)),
        (.unclassified, Color(white: 0.55)),
    ]

    var painted = true
    var flatOnly = false
    var showSurface = false
    var roomLight = true

    /// The reconstructed surface, rebuilt only when a block actually changed.
    var surface = Mesh(positions: [], indices: [])
    var built: Int?

    /// The framing, eased frame to frame so the view glides as the room fills in.
    var orbitCenter = Vector3.zero
    var orbitRadius = 3.0
    var framed = false

    override func setup() {
        device.start()
    }

    override func draw() {
        background(Color(hex: 0x0B0D12))

        let room = device.planes
        guard !room.isEmpty else {
            return drawStatus(device.waitingMessage + "\n\n" +
                              "Open Ollin Capture on the iPhone, tap the Room tab,\n" +
                              "connect the cable, then look slowly around the room.",
                              style: .info)
        }

        frame(on: room)
        cameraShowcase(.turntable(period: .tau / 0.14), target: orbitCenter,
                       radius: orbitRadius, elevation: 0.35, fieldOfView: .pi / 3)
        applyLight()

        // A surface is a few dozen points, so these are built fresh each frame. The
        // reconstructed surface below is hundreds of thousands of triangles, which is
        // why that one waits for `sceneMeshVersion` to change.
        let shown = flatOnly ? room.flat : room.planes
        material(.dielectric(roughness: 0.8))
        for plane in shown {
            fill(painted ? color(of: plane.surface) : Color(white: 0.7))
            drawMesh(plane.mesh)
        }

        // The outlines, so a surface reads as a surface even edge on.
        material(Material())
        fill(Color(white: 0.9, alpha: 0.55))
        for plane in shown { drawTube(plane.outline, radius: 0.008, sides: 5, closed: true) }

        if showSurface { drawReconstruction() }
        standSomethingOnTheFloor(room)

        material(Material())
        if painted { drawLegend(room) }
        drawCaption(caption(room))
    }

    override func keyPressed() {
        switch key {
        case " ":       painted.toggle()
        case "f", "F":  flatOnly.toggle()
        case "m", "M":  showSurface.toggle()
        case "l", "L":  roomLight.toggle()
        case "r", "R":
            device.resetPlanes()
            device.resetSceneMesh()
            surface = Mesh(positions: [], indices: [])
            built = nil
            framed = false
        default: break
        }
    }

    /// Light the scene the way the room is lit, or fall back to a studio rig so the
    /// difference is easy to see. In Room mode the phone reports brightness and
    /// warmth; only Face mode knows a direction, so a key light is added here at a
    /// fixed angle in the room's own color.
    private func applyLight() {
        guard roomLight, let measured = device.latestLight else {
            return environment(.studio.intensity(0.9))
        }
        ambientLight(measured.ambient)
        if let key = measured.key {
            light(key)
        } else {
            light(.directional(measured.color, direction: Vector3(-0.35, -1, -0.25),
                               intensity: min(2, max(0.15, measured.intensity))))
        }
    }

    /// A ball resting on the biggest flat surface, which is the whole point of
    /// knowing where the flat surfaces are.
    private func standSomethingOnTheFloor(_ room: PhonePlanes) {
        guard let ground = room.largest(of: .table, .seat) ?? room.floor else { return }
        let radius = min(0.18, max(0.05, ground.area.squareRoot() * 0.12))
        withState {
            material(.metal(roughness: 0.25))
            fill(Color(hex: 0xE8E2D6))
            translate(ground.center + ground.normal * radius)
            drawSphere(radius: radius)
        }
    }

    /// The reconstructed surface behind the flat ones, as a wireframe. It comes from
    /// the same session, so the two agree about where everything is.
    private func drawReconstruction() {
        if device.sceneMeshVersion != built {
            built = device.sceneMeshVersion
            surface = device.sceneMesh.mesh
        }
        guard !surface.isEmpty else { return }
        withState {
            material(Material())
            wireframe()
            fill(Color(white: 0.35, alpha: 0.5))
            drawMesh(surface)
        }
    }

    /// Orbit the middle of the room at a distance set by how big it has grown, easing
    /// toward the target so the view does not jump each time a surface lands.
    private func frame(on room: PhonePlanes) {
        let bounds = room.bounds
        let center = (bounds.min + bounds.max) * 0.5
        let size = bounds.max - bounds.min
        let radius = max(1.5, max(size.x, max(size.y, size.z)) * 1.1)
        if framed {
            orbitCenter = orbitCenter.lerp(to: center, 0.05)
            orbitRadius += (radius - orbitRadius) * 0.05
        } else {
            orbitCenter = center
            orbitRadius = radius
            framed = true
        }
    }

    private func color(of surface: PhoneSurface) -> Color {
        Self.palette.first { $0.0 == surface }?.1 ?? Color(white: 0.55)
    }

    /// A swatch and a name for each label the room has actually produced. Early on
    /// that is only `unclassified`, which is the honest picture: the phone finds a
    /// surface first and decides what it is later.
    private func drawLegend(_ room: PhonePlanes) {
        let found = room.foundSurfaces
        var y = 40.0
        withState {
            noStroke()
            textFont(OutlineFont.system)
            textSize(20)
            textAlign(.left)
            for (surface, color) in Self.palette where found.contains(surface) {
                fill(color)
                drawRect(40, y - 14, 18, 18)
                fill(Color(white: 0.75))
                drawText("\(surface)", at: Vector2(68, y))
                y += 28
            }
        }
    }

    private func caption(_ room: PhonePlanes) -> String {
        var text = "PhoneRoomPlanes · \(room.count) surfaces, \(room.flat.count) flat"
        if let light = device.latestLight {
            text += String(format: " · %.0f lm, %.0f K", light.lumens, light.kelvin)
        }
        if flatOnly { text += " · flat only" }
        return text + "; space, F, M, L, R"
    }
}
