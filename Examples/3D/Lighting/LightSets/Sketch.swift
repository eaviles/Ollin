import Ollin

/// Light sets: one frame, several lighting rigs.
///
/// Lamps are drawing state, saved by `withState` like a fill or a blend, so the
/// lights in force when a mesh is drawn are the lights that shade it. Three rooms
/// stand side by side along a corridor with no lamp of its own, and each is lit by
/// `withLights` from its own fixture: a warm bulb swinging on its flex, a cold strip
/// overhead, a green glow that pulses out of the floor. A surface in one room reads
/// its own room's lamps and nothing from next door, which is why the light stops at
/// the dividing wall without a wall thick enough to stop it.
///
/// The floor is lit by the frame's own rig, the lamps set the ordinary way before
/// anything is drawn, and that set is the one that casts: a scoped set lights what it
/// draws and throws nothing. Each room carries the same white plate on its back wall,
/// drawn `withoutLights` so no lamp reaches it: the three walls come out warm, cold
/// and green, and the three plates come out identical, which is the difference
/// between a lit surface and an unlit one in one glance.
///
/// Drag to orbit, scroll to dolly.
@main
final class LightSets: Sketch {

    private struct Room {
        let x: Double
        let wall: Color
        /// The lamps of this room, worked out fresh each frame so they can move.
        let lamps: (Double) -> [Light]
        /// Where to draw the fixture itself, and how bright it reads.
        let fixture: (Double) -> (Vector3, Color)
    }

    override var canvasSize: CanvasSize { .size(1280, 720) }

    private let roomWidth = 4.1
    private let roomDepth = 5.0
    private let wallHeight = 3.5
    private let spacing = 4.25

    private var rooms: [Room] {
        [
            // A warm bulb on a flex, swinging. Its light sweeps its own room only.
            Room(x: -4.25, wall: Color(hue: 0.07, saturation: 0.14, brightness: 0.82),
                 lamps: { t in
                     let swing = sin(t * 0.9) * 1.3
                     return [.point(Color(kelvin: 2700), at: Vector3(-4.25 + swing, 2.1, 0),
                                    intensity: 7, reach: 7)]
                 },
                 fixture: { t in (Vector3(-4.25 + sin(t * 0.9) * 1.3, 2.1, 0), Color(kelvin: 2700)) }),
            // A cold strip overhead: a tube source, steady.
            Room(x: 0, wall: Color(hue: 0.58, saturation: 0.08, brightness: 0.85),
                 lamps: { _ in
                     // A thin tube is a very bright *surface*: its radiance carries the
                     // whole room, so the number is nothing like a bulb's.
                     [.tube(Color(kelvin: 6800), from: Vector3(-1.7, 3.05, 0),
                            to: Vector3(1.7, 3.05, 0), radius: 0.07, intensity: 34, reach: 9)]
                 },
                 fixture: { _ in (Vector3(0, 3.05, 0), Color(kelvin: 6800)) }),
            // A green glow rising out of the floor, breathing.
            Room(x: 4.25, wall: Color(hue: 0.33, saturation: 0.1, brightness: 0.8),
                 lamps: { t in
                     let pulse = 3.4 + sin(t * 1.7) * 1.6
                     return [.point(Color(hue: 0.33, saturation: 0.5, brightness: 0.95),
                                    at: Vector3(4.25, 0.45, 0), intensity: pulse, reach: 5.5)]
                 },
                 fixture: { t in
                     (Vector3(4.25, 0.45, 0),
                      Color(hue: 0.33, saturation: 0.5,
                            brightness: 0.4 + (sin(t * 1.7) * 0.5 + 0.5) * 0.55))
                 }),
        ]
    }

    override func draw() {
        background(Color(white: 0.02))
        cameraShowcase(.sway(amplitude: 0.3, period: .tau / 0.08), target: Vector3(0, 1.05, 0),
                       radius: 12.4, elevation: 0.36, fieldOfView: .pi / 3.2)

        // The frame's own rig: a dim overhead wash down the corridor, and the set
        // that casts. Set the ordinary way, before anything is drawn.
        noLights()
        ambientLight(Color(white: 0.02))
        directionalLight(Color(kelvin: 5200), direction: Vector3(0.15, -1, -0.25), intensity: 0.55)
        castShadows()

        // The corridor floor, under the frame's rig.
        withState {
            fill(Color(white: 0.26))
            specular(0.04)
            drawPlane(width: 70, depth: 44)
        }

        // Each room under its own lamps. Nothing inside the block can see the
        // corridor's rig, and nothing outside can see the room's.
        for room in rooms {
            withLights(room.lamps(time), ambient: Color(white: 0.015)) {
                drawRoom(room)
            }
        }

        // The fixtures themselves, drawn flat so a bulb reads as a source rather
        // than as one more shaded object: an unlit body standing in a lit scene.
        for room in rooms {
            let (place, glow) = room.fixture(time)
            withoutLights {
                withState {
                    translate(place)
                    fill(glow)
                    drawSphere(radius: 0.17)
                }
            }
        }

        // The same plate on every back wall, unlit. The walls behind them are lit by
        // three different lamps and read as three different colors; the plates are
        // reached by no lamp at all and read the same in every room.
        withoutLights {
            fill(Color(white: 0.88))
            for room in rooms {
                withState {
                    translate(room.x, 2.15, -roomDepth / 2 + 0.11)
                    drawBox(width: 1.5, height: 0.95, depth: 0.06)
                }
            }
        }

        drawCaption("three rooms, three light sets, one frame")
    }

    /// One room: three walls, a floor panel, and a few solids to catch the light.
    private func drawRoom(_ room: Room) {
        let half = roomWidth / 2
        fill(room.wall)
        specular(0.05)
        // The back wall and the two dividers. Thin, because it is the light sets and
        // not the geometry that keeps each room's lamps to itself.
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
        // Three solids per room, each a different finish, so the room's own lamp has
        // something to shade and something to glint off.
        withState {
            translate(room.x - 1.05, 0.62, 0.9)
            fill(Color(white: 0.86)); specular(0.65); specularSharpness(110)
            drawSphere(radius: 0.55)
        }
        withState {
            translate(room.x + 1.0, 0.55, -0.4)
            rotateY(time * 0.4)
            fill(Color(white: 0.78)); specular(0.25); specularSharpness(40)
            drawBox(size: 1.0)
        }
        withState {
            translate(room.x + 0.1, 0.34, 1.7)
            rotateX(1.1); rotateY(time * 0.6)
            fill(Color(white: 0.8)); specular(0.4); specularSharpness(64)
            drawTorus(radius: 0.36, tube: 0.13)
        }
    }
}
