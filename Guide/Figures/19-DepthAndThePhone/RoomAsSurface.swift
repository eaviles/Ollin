// figure: frame=0
//
// Guide figure (Chapter 19): the room the phone hands over as a surface, and the
// three things you can ask it for. Left, the whole room as one mesh. Middle, the
// same room painted by what each triangle is. Right, only the flat things you
// could put something on.
//
// The blocks here are staged rather than scanned, the way this chapter's earlier
// figures stage a depth camera: the same PhoneSceneMesh a phone fills in, filled
// in by hand so the figure renders anywhere. A real scan arrives with the same
// shape and far more blocks.
import Foundation
import Ollin
import OllinPhone

final class RoomAsSurface: Sketch {
    override var canvasSize: CanvasSize { .size(880, 330) }

    static let palette: [(PhoneSurface, Color)] = [
        (.floor, Color(hex: 0x5FB681)), (.wall, Color(hex: 0x9AA4BC)),
        (.table, Color(hex: 0xE8B25A)), (.seat, Color(hex: 0xDD7A66)),
    ]

    lazy var room = stagedRoom()

    static let captions = ["the whole room", "painted by label", "floor, table, seat"]

    override func draw() {
        background(Color(hex: 0x0D1017))
        // The row runs straight across the view, and each room is turned on the
        // spot instead, so the three read side by side rather than receding.
        camera(.orbiting(target: Vector3(0, 0.3, 0), radius: 4.6,
                         azimuth: 0, elevation: 0.32, fieldOfView: .pi / 4))
        environment(.studio.intensity(1.15).lightingOnly())
        material(.dielectric(roughness: 0.7))

        let xs: [Double] = [-2.2, 0, 2.2]
        for (i, x) in xs.enumerated() {
            withState {
                translate(x, 0, 0)
                rotateY(0.72)
                switch i {
                case 0:
                    // The room as it comes: one mesh, one fill.
                    fill(Color(hex: 0xC9C2B6))
                    drawMesh(room.mesh)
                case 1:
                    // A color per triangle rides in the mesh, and the colors
                    // multiply the fill, so white shows them as painted.
                    fill(.white)
                    drawMesh(room.mesh { surface in
                        Self.palette.first { $0.0 == surface }?.1 ?? Color(white: 0.42)
                    })
                default:
                    // One label at a time, so each can take its own fill.
                    for (surface, color) in Self.palette where surface != .wall {
                        fill(color)
                        drawMesh(room.mesh(of: surface))
                    }
                }
            }
        }
        drawLabels(at: xs)
    }

    private func drawLabels(at xs: [Double]) {
        withState {
            noStroke()
            textFont(OutlineFont.system)
            textSize(19)
            textAlign(.center)
            fill(Color(white: 0.62))
            for (x, caption) in zip(xs, Self.captions) {
                if let p = project(Vector3(x, -0.62, 0.9)) { drawText(caption, at: p) }
            }
        }
    }

    // MARK: The staged room

    /// A small corner: a floor, two walls, a table top, and a seat, each its own
    /// block the way ARKit reports one.
    private func stagedRoom() -> PhoneSceneMesh {
        var room = PhoneSceneMesh()
        room.apply(patch(corner: Vector3(-0.8, 0, -0.8), across: Vector3(1.4, 0, 0),
                         down: Vector3(0, 0, 1.4), label: .floor))
        room.apply(patch(corner: Vector3(-0.8, 0, -0.8), across: Vector3(1.4, 0, 0),
                         down: Vector3(0, 1.05, 0), label: .wall))
        room.apply(patch(corner: Vector3(-0.8, 0, -0.8), across: Vector3(0, 0, 1.4),
                         down: Vector3(0, 1.05, 0), label: .wall))
        room.apply(patch(corner: Vector3(-0.16, 0.5, -0.34), across: Vector3(0.7, 0, 0),
                         down: Vector3(0, 0, 0.5), label: .table))
        room.apply(patch(corner: Vector3(-0.62, 0.3, 0.16), across: Vector3(0.46, 0, 0),
                         down: Vector3(0, 0, 0.42), label: .seat))
        return room
    }

    /// One block: a patch of surface as a grid of triangles, wobbled a little so
    /// it reads as something measured rather than something drawn.
    private func patch(corner: Vector3, across: Vector3, down: Vector3,
                       label: PhoneSurface, steps: Int = 7) -> PhoneSceneChunk {
        let normal = across.cross(down).normalized
        var positions: [Vector3] = [], normals: [Vector3] = []
        var indices: [UInt32] = [], surfaces: [PhoneSurface] = []

        for row in 0...steps {
            for col in 0...steps {
                let u = Double(col) / Double(steps), v = Double(row) / Double(steps)
                // A fixed wobble, so the figure renders the same every time.
                let wobble = sin(u * 11 + v * 7) * 0.006 + sin(v * 17) * 0.004
                positions.append(corner + across * u + down * v + normal * wobble)
                normals.append(normal)
            }
        }
        let width = steps + 1
        for row in 0..<steps {
            for col in 0..<steps {
                let a = UInt32(row * width + col)
                indices.append(contentsOf: [a, a + 1, a + UInt32(width)])
                indices.append(contentsOf: [a + 1, a + UInt32(width) + 1, a + UInt32(width)])
                surfaces.append(label)
                surfaces.append(label)
            }
        }
        return PhoneSceneChunk(id: UUID(), positions: positions, normals: normals,
                               indices: indices, surfaces: surfaces)
    }
}
