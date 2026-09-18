// figure: frame=0
//
// Guide figure (Chapter 21): one frame carrying three lighting rigs. Three rooms
// side by side, each drawn inside its own `withLights` block, so the lamps in
// force when a wall is drawn are the lamps that shade it and nothing crosses a
// divider. Unlike the LampsAtNight figure beside it, this one is a single frame
// rather than three renders read back: carrying several rigs at once is the
// thing being shown, so composing it out of separate frames would prove nothing.
//
// The white plate on every back wall is the control. It is drawn in one
// `withoutLights` block, in one fill color, so the three walls come out warm,
// cold and green while the three plates come out identical: that difference is
// the whole of what an unlit scope does.
import Ollin

final class LightSets: Sketch {
    override var canvasSize: CanvasSize { .size(880, 370) }

    private let roomWidth = 4.1
    private let roomDepth = 5.0
    private let wallHeight = 3.5

    private struct Room {
        let x: Double
        let wall: Color
        let lamps: [Light]
        /// Where the fixture sits, and the color it reads as.
        let fixture: (Vector3, Color)
        let caption: String
    }

    private var rooms: [Room] {
        [
            Room(x: -4.25, wall: Color(hue: 0.07, saturation: 0.14, brightness: 0.82),
                 lamps: [.point(Color(kelvin: 2700), at: Vector3(-4.25, 2.1, 0),
                                intensity: 7, reach: 7)],
                 fixture: (Vector3(-4.25, 2.1, 0), Color(kelvin: 2700)),
                 caption: "a warm bulb"),
            Room(x: 0, wall: Color(hue: 0.58, saturation: 0.08, brightness: 0.85),
                 lamps: [.tube(Color(kelvin: 6800), from: Vector3(-1.7, 3.05, 0),
                               to: Vector3(1.7, 3.05, 0), radius: 0.07,
                               intensity: 34, reach: 9)],
                 fixture: (Vector3(0, 3.05, 0), Color(kelvin: 6800)),
                 caption: "a cold strip"),
            Room(x: 4.25, wall: Color(hue: 0.33, saturation: 0.1, brightness: 0.8),
                 lamps: [.point(Color(hue: 0.33, saturation: 0.5, brightness: 0.95),
                                at: Vector3(4.25, 0.45, 0), intensity: 4.2, reach: 5.5)],
                 fixture: (Vector3(4.25, 0.45, 0), Color(hue: 0.33, saturation: 0.5, brightness: 0.8)),
                 caption: "a glow in the floor"),
        ]
    }

    override func draw() {
        background(Color(hex: 0x0A0B0D))
        camera(.perspective(eye: Vector3(0, 4.6, 11.0), target: Vector3(0, 2.35, 0),
                            fieldOfView: .pi / 3.3))

        // The frame's own rig: what lights the ground, and the set that casts.
        noLights()
        ambientLight(Color(white: 0.02))
        directionalLight(Color(kelvin: 5200), direction: Vector3(0.15, -1, -0.25), intensity: 0.55)
        castShadows()
        withState {
            fill(Color(white: 0.26))
            specular(0.04)
            drawPlane(width: 70, depth: 44)
        }

        // Each room under its own lamps, and nothing else.
        for room in rooms {
            withLights(room.lamps, ambient: Color(white: 0.015)) { drawRoom(room) }
        }

        // The fixtures, and the same plate on every back wall: one unlit block.
        withoutLights {
            for room in rooms {
                withState {
                    translate(room.fixture.0)
                    fill(room.fixture.1)
                    drawSphere(radius: 0.17)
                }
            }
            fill(Color(white: 0.88))
            for room in rooms {
                withState {
                    translate(room.x, 2.15, -roomDepth / 2 + 0.11)
                    drawBox(width: 1.5, height: 0.95, depth: 0.06)
                }
            }
        }

        // The captions, on billboards above each room so they face the eye and
        // nothing occludes them.
        withoutLights {
            textAlign(.center, .middle)
            textSize(19)
            for room in rooms {
                fill(Color(white: 0.84))
                withBillboard(at: Vector3(room.x, 4.35, roomDepth / 2 - 0.4)) {
                    drawText(room.caption, 0, 0)
                }
            }
            fill(Color(white: 0.52))
            textSize(18)
            withBillboard(at: Vector3(0, 5.3, roomDepth / 2 - 0.4)) {
                drawText("three rigs in one frame; the plate on every back wall is lit by none of them", 0, 0)
            }
        }
    }

    private func drawRoom(_ room: Room) {
        let half = roomWidth / 2
        fill(room.wall)
        specular(0.05)
        withState {
            translate(room.x, wallHeight / 2, -roomDepth / 2)
            drawBox(width: roomWidth, height: wallHeight, depth: 0.12)
        }
        for side in [-1.0, 1.0] {
            withState {
                translate(room.x + side * half, wallHeight / 2, 0)
                drawBox(width: 0.12, height: wallHeight, depth: roomDepth)
            }
        }
        withState {
            translate(room.x, 0.03, 0)
            fill(Color(white: 0.5))
            drawBox(width: roomWidth, height: 0.06, depth: roomDepth)
        }
        withState {
            translate(room.x - 1.05, 0.62, 0.9)
            fill(Color(white: 0.86)); specular(0.65); specularSharpness(110)
            drawSphere(radius: 0.55)
        }
        withState {
            translate(room.x + 1.0, 0.55, -0.4)
            rotateY(0.5)
            fill(Color(white: 0.78)); specular(0.25); specularSharpness(40)
            drawBox(size: 1.0)
        }
        withState {
            translate(room.x + 0.1, 0.34, 1.7)
            rotateX(1.1)
            fill(Color(white: 0.8)); specular(0.4); specularSharpness(64)
            drawTorus(radius: 0.36, tube: 0.13)
        }
    }
}
