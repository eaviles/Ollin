// figure: frame=0 probe
//
// Guide figure (Chapter 27): the other half of what the phone hands over about a
// room. Left, the flat surfaces it finds, each as its real outline and painted by
// what it thinks it is. Right, the reason to want them: something standing on the
// biggest flat one. Underneath, what the phone measures of the light in the room,
// as the color a sketch would light itself with.
//
// The surfaces here are staged rather than found, the way this chapter's other
// figures stage a depth camera: the same PhonePlanes a phone fills in, filled in by
// hand so the figure renders anywhere.
import Foundation
import Ollin
import OllinPhone

final class RoomAsPlanes: Sketch {
    override var canvasSize: CanvasSize { .size(880, 440) }

    static let palette: [(PhoneSurface, Color)] = [
        (.floor, Color(hex: 0x5FB681)), (.wall, Color(hex: 0x9AA4BC)),
        (.table, Color(hex: 0xE8B25A)), (.seat, Color(hex: 0xDD7A66)),
    ]

    /// The light a lamp, a working room, and a window each measure as.
    static let readings: [(String, PhoneLight)] = [
        ("lamp · 480 lm, 2700 K", PhoneLight(lumens: 480, kelvin: 2700)),
        ("room · 1000 lm, 5000 K", PhoneLight(lumens: 1000, kelvin: 5000)),
        ("window · 900 lm, 9000 K", PhoneLight(lumens: 900, kelvin: 9000)),
    ]

    lazy var room = stagedRoom()

    override func draw() {
        background(Color(hex: 0x0D1017))
        // The target sits below the rooms, which lifts them into the top of the frame
        // and leaves the bottom for the light strip.
        camera(.orbiting(target: Vector3(0, -0.75, 0), radius: 4.2,
                         azimuth: 0, elevation: 0.4, fieldOfView: .pi / 4))
        environment(.studio.intensity(1.1).lightingOnly())

        let xs: [Double] = [-1.35, 1.35]
        for (i, x) in xs.enumerated() {
            withState {
                translate(x, -0.15, 0)
                rotateY(0.7)
                material(.dielectric(roughness: 0.75))
                for plane in room.planes {
                    fill(i == 0 ? color(of: plane.surface) : Color(hex: 0x8E8E94))
                    drawMesh(plane.mesh)
                }
                // The outline is what makes a surface read as a found surface rather
                // than as a wall of the room.
                material(Material())
                fill(Color(white: 0.95, alpha: 0.85))
                for plane in room.planes {
                    drawTube(plane.outline, radius: 0.014, sides: 6, closed: true)
                }
                if i == 1, let table = room.largest(of: .table) {
                    material(.metal(roughness: 0.25))
                    fill(Color(hex: 0xF0E9DA))
                    withState {
                        translate(table.center + table.normal * 0.15)
                        drawSphere(radius: 0.15)
                    }
                }
            }
        }

        drawPanelLabels(at: xs)
        drawLightStrip()
    }

    private func color(of surface: PhoneSurface) -> Color {
        Self.palette.first { $0.0 == surface }?.1 ?? Color(white: 0.5)
    }

    private func drawPanelLabels(at xs: [Double]) {
        let captions = ["the surfaces it finds", "somewhere to stand"]
        withState {
            noStroke()
            textFont(OutlineFont.system)
            textSize(19)
            textAlign(.center)
            fill(Color(white: 0.62))
            for (i, caption) in captions.enumerated() {
                drawText(caption, at: Vector2(width * (i == 0 ? 0.27 : 0.73), 298))
            }
        }
    }

    /// What a light reading looks like as a color: the room's white, turned down by
    /// how bright the room is. This is what `ambientLight(light.ambient)` puts on a
    /// sketch.
    private func drawLightStrip() {
        withState {
            noStroke()
            textFont(OutlineFont.system)
            textAlign(.center)
            let y = 348.0, swatch = 200.0, gap = 40.0
            let total = Double(Self.readings.count) * swatch + Double(Self.readings.count - 1) * gap
            var x = (width - total) * 0.5
            for (label, light) in Self.readings {
                fill(light.ambient)
                drawRect(x, y, swatch, 30)
                fill(Color(white: 0.62))
                textSize(17)
                drawText(label, at: Vector2(x + swatch * 0.5, y + 54))
                x += swatch + gap
            }
            fill(Color(white: 0.45))
            textSize(16)
            drawText("the light the phone measures, as a sketch would use it",
                     at: Vector2(width * 0.5, y - 14))
        }
    }

    // MARK: The staged room

    /// A small corner: a floor, a wall behind it, and a table top standing off the
    /// floor, each its own surface the way ARKit reports one.
    private func stagedRoom() -> PhonePlanes {
        var room = PhonePlanes()
        room.apply(surface(center: Vector3(0, -0.6, 0), across: Vector3(1.5, 0, 0),
                           down: Vector3(0, 0, 1.2), label: .floor, facing: .horizontal))
        room.apply(surface(center: Vector3(0, -0.05, -0.62), across: Vector3(1.5, 0, 0),
                           down: Vector3(0, 1.1, 0), label: .wall, facing: .vertical))
        room.apply(surface(center: Vector3(0.12, -0.16, 0.1), across: Vector3(0.78, 0, 0),
                           down: Vector3(0, 0, 0.56), label: .table, facing: .horizontal))
        return room
    }

    /// One found surface, as a rectangle with its corners cut off. A real outline is
    /// the convex polygon around everything the phone has seen, so it is rarely a
    /// clean rectangle.
    private func surface(center: Vector3, across: Vector3, down: Vector3,
                         label: PhoneSurface, facing: PhonePlaneAlignment) -> PhonePlane {
        let normal = down.cross(across).normalized
        let u = across * 0.5, v = down * 0.5
        // The corners, each pulled in a little along one edge so the shape reads as
        // something measured.
        let boundary = [
            center - u * 0.82 - v, center + u * 0.9 - v,
            center + u + v * 0.55, center + u * 0.55 + v,
            center - u * 0.94 + v * 0.88, center - u - v * 0.4,
        ]
        return PhonePlane(id: UUID(), surface: label, alignment: facing,
                          center: center, normal: normal,
                          width: across.length, height: down.length, boundary: boundary)
    }
}
