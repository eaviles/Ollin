// figure: frame=62
//
// Guide figure (Chapter 21): the two most spatial joints. Left, a cart
// threaded onto a looping .path track, banked into the bend it is riding.
// Right, a .pulley: a loaded tray sinking on one side of the rope while the
// counterweight rises on the other. No random anywhere, so it replays
// identically.
import Ollin
import OllinPhysics

final class TrackAndPulley: Sketch {
    override var canvasSize: CanvasSize { .size(880, 550) }

    let world = World3D()
    var track: [Vector3] = []
    var tray: Body3D?
    var counterweight: Body3D?
    let leftHook = Vector3(1.85, 3.15, 0)
    let rightHook = Vector3(3.35, 3.15, 0)

    let timber = Color(hex: 0x7C6142)
    let brass = Color(hex: 0xD9A441)
    let steel = Color(hex: 0xB9C2CE)
    let clay = Color(hex: 0xC96F4A)

    override func setup() {
        world.ground = -0.8

        // The looping track: an oval that climbs at the back and dips in front.
        track = (0 ..< 16).map { i in
            let a = Double(i) / 16 * .tau
            return Vector3(-3.1 + 2.3 * cos(a), 1.0 - 0.55 * sin(a), 1.3 * sin(a))
        }
        let rails = world.addBody(.box(width: 0.2, height: 0.2, depth: 0.2),
                                  at: Vector3(0, -2, 0), kind: .static)
        let cart = world.addBody(.box(width: 0.8, height: 0.4, depth: 0.5),
                                 at: track[0], density: 1.5)
        cart.userData = clay
        world.connect(rails, cart,
                      .path(through: track, looping: true,
                            alignment: .followsPath))
            .drive(at: 3.9, strength: 400)

        // The pulley: a tray with a load, a rope over two hooks, a weight.
        var walls: [Collider3D.Part] = [.part(.box(width: 1.0, height: 0.12, depth: 1.0))]
        for (dx, dz) in [(0.5, 0.0), (-0.5, 0.0), (0.0, 0.5), (0.0, -0.5)] {
            walls.append(.part(.box(width: dx == 0 ? 1.0 : 0.12, height: 0.45,
                                    depth: dz == 0 ? 1.0 : 0.12),
                               at: Vector3(dx, 0.22, dz)))
        }
        let basket = world.addBody(.compound(walls), at: Vector3(1.85, 2.1, 0),
                                   density: 0.5, friction: 0.6)
        basket.userData = steel
        tray = basket
        let load = world.addBody(.sphere(radius: 0.24), at: Vector3(1.85, 2.7, 0),
                                 density: 3.5, friction: 0.6)
        load.userData = brass
        let weight = world.addBody(.box(width: 0.55, height: 0.55, depth: 0.55),
                                   at: Vector3(3.35, 0.75, 0), density: 1.5)
        weight.userData = clay
        counterweight = weight
        world.connect(basket, weight,
                      .pulley(from: Vector3(1.85, 2.35, 0), over: leftHook,
                              and: rightHook, to: Vector3(3.35, 1.05, 0)))
    }

    override func draw() {
        background(Color(hex: 0x0D111A))
        environment(.night.lightingOnly())
        lightingPreset(.studio)
        castShadows()
        camera(.perspective(eye: Vector3(-0.2, 3.0, 10.6),
                            target: Vector3(-0.3, 1.2, 0),
                            fieldOfView: .pi / 4.4))

        world.step(dt: 1.0 / 60)

        fill(Color(hex: 0x11151F))
        material(.dielectric(roughness: 0.94))
        withState {
            translate(0, -0.87, 0)
            drawBox(width: 30, height: 0.14, depth: 30)
        }

        // The track itself, and a few posts holding it up (drawing only).
        fill(steel)
        material(.metal(roughness: 0.5))
        drawTube(track, radius: 0.06, sides: 8, closed: true)
        for i in [1, 5, 9, 13] {
            let p = track[i]
            withState {
                translate(p.x, (p.y - 0.8) / 2, p.z)
                drawCylinder(radius: 0.05, height: p.y + 0.8)
            }
        }

        // The pulley frame and its rope (drawing only; the joint does the work).
        fill(timber)
        material(.dielectric(roughness: 0.7))
        for x in [1.45, 3.75] {
            withState {
                translate(x, 1.28, -0.0)
                drawCylinder(radius: 0.09, height: 4.3)
            }
        }
        withState {
            translate(2.6, 3.32, 0)
            rotateZ(.pi / 2)
            drawCylinder(radius: 0.09, height: 2.9)
        }
        if let tray, let counterweight {
            fill(Color(hex: 0xF2E9D4))
            material(.dielectric(roughness: 0.6))
            drawTube([tray.position + Vector3(0, 0.25, 0), leftHook, rightHook,
                      counterweight.position + Vector3(0, 0.3, 0)],
                     radius: 0.055, sides: 6)
        }

        for body in world.bodies {
            withBody(body) { draw(body.collider, tint: body.userData as? Color) }
        }
    }

    func draw(_ collider: Collider3D, tint: Color?) {
        switch collider {
        case .box(let w, let h, let d):
            fill(tint ?? .white)
            material(.dielectric(roughness: 0.65))
            drawBox(width: w, height: h, depth: d)
        case .sphere(let r):
            fill(tint ?? brass)
            material(.metal(roughness: 0.35))
            drawSphere(radius: r)
        case .compound(let parts):
            for part in parts {
                withState {
                    translate(part.position)
                    if part.angle != 0 { rotate(part.angle, axis: part.axis) }
                    draw(part.collider, tint: tint)
                }
            }
        default:
            break
        }
    }
}
