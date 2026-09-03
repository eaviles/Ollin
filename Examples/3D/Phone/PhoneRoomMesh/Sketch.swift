import Foundation
import Ollin
import OllinPhone

/// Walk a tethered iPhone around a room and watch the room itself arrive as a solid
/// surface, painted by what the phone thinks each part is: floor, wall, ceiling,
/// table, seat.
///
/// `PhoneWorldScan` fuses depth frames into points on the Mac. This is the other
/// half of the same idea, and the phone does the work: ARKit reconstructs the space
/// as real triangles on the device and streams the room block by block, so what
/// arrives already has normals and already carries a label per triangle.
///
/// Setup: install **Ollin Capture** on a LiDAR iPhone (a Pro model), launch it, tap
/// the **Mesh** segment, and connect the cable. Then walk slowly and look around.
/// Blocks fill in as you go, and a block you look at twice sharpens.
///
/// Keys: **space** switches between the painted room and a plain surface, **F**
/// keeps only the flat things you could put something on (the floor, tables, seats),
/// and **R** starts a fresh room.
///
/// The one rule worth copying: the room mesh is large, so rebuild it when
/// `sceneMeshVersion` changes, never once per frame.
@main
final class PhoneRoomMesh: Sketch {

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
        (.unclassified, Color(white: 0.42)),
    ]

    /// The flat things you could set something down on.
    static let flat: Set<PhoneSurface> = [.floor, .table, .seat]

    /// The room as one mesh, rebuilt only when a block actually changed.
    var room = Mesh(positions: [], indices: [])
    var built: Int?
    var painted = true
    var flatOnly = false

    /// The framing, eased frame to frame so the view glides as the room grows.
    var orbitCenter = Vector3.zero
    var orbitRadius = 3.0
    var framed = false

    override func setup() {
        device.start()
    }

    override func draw() {
        background(Color(hex: 0x0B0D12))

        // Rebuild on a change, not on a frame. A scanned room runs to hundreds of
        // thousands of triangles, and draw() runs far faster than blocks arrive.
        let scan = device.sceneMesh
        if device.sceneMeshVersion != built {
            built = device.sceneMeshVersion
            room = rebuild(scan)
        }

        guard !scan.isEmpty else {
            return drawStatus(device.waitingMessage + "\n\n" +
                              "Open Ollin Capture on a LiDAR iPhone, tap the Mesh tab,\n" +
                              "connect the cable, then walk slowly and look around.",
                              style: .info)
        }

        frame(on: scan)
        cameraShowcase(.turntable(period: .tau / 0.16), target: orbitCenter,
                       radius: orbitRadius, elevation: 0.3, fieldOfView: .pi / 3)
        environment(.studio.intensified(to: 0.9))
        material(.dielectric(roughness: 0.85))
        fill(.white)
        drawMesh(room)

        material(Material())
        if painted && !flatOnly { drawLegend(scan) }
        drawCaption(caption(scan))
    }

    override func keyPressed() {
        switch key {
        case " ":       painted.toggle();  built = nil
        case "f", "F":  flatOnly.toggle(); built = nil
        case "r", "R":
            device.resetSceneMesh()
            room = Mesh(positions: [], indices: [])
            built = nil
            framed = false
        default: break
        }
    }

    /// The room in the shape the current view wants: the flat things alone, the whole
    /// room painted by label, or the whole room plain.
    private func rebuild(_ scan: PhoneSceneMesh) -> Mesh {
        if flatOnly { return scan.mesh(of: Self.flat) }
        guard painted else { return scan.mesh }
        return scan.mesh { surface in
            Self.palette.first { $0.0 == surface }?.1 ?? Color(white: 0.42)
        }
    }

    /// Orbit the middle of the room at a distance set by how big it has grown, easing
    /// toward the target so the view does not jump each time a block lands.
    private func frame(on scan: PhoneSceneMesh) {
        let bounds = scan.bounds
        let center = bounds.center
        let radius = max(1.5, bounds.longestSide * 0.9)
        if framed {
            orbitCenter = orbitCenter.lerp(to: center, 0.05)
            orbitRadius += (radius - orbitRadius) * 0.05
        } else {
            orbitCenter = center
            orbitRadius = radius
            framed = true
        }
    }

    /// A swatch and a name for each label the scan has actually produced. Early in a
    /// scan that is only `unclassified`, which is the honest picture: ARKit labels a
    /// surface once it has seen enough of it.
    private func drawLegend(_ scan: PhoneSceneMesh) {
        let found = scan.foundSurfaces
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

    private func caption(_ scan: PhoneSceneMesh) -> String {
        let view = flatOnly ? "flat surfaces only" : (painted ? "painted by label" : "plain")
        return "PhoneRoomMesh · \(scan.chunkCount) blocks, \(scan.triangleCount) triangles, "
            + "\(view); space, F, R"
    }
}
