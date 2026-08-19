import Ollin
import OllinPhysics

/// A washing line in the wind. Three soft bodies share the scene: a banner
/// pegged along its top edge that flaps, a sheet thrown over a rail and a crate
/// so it has to find their shape, and a beach ball you can let the air out of.
/// **Drag** any of them to take hold of it; **space** tosses the ball back up.
///
/// The soft-body showcase for `World3D`. Everything here is one call:
/// `world.addSoftBody(from:)` turns a mesh into simulated particles, `pinned:`
/// decides which of them are held, `pressure` is the air inside the ball, and
/// `drawSoftBody` draws whatever shape the simulation arrived at.
@main
final class Drape: Sketch {
    let world = World3D()
    var banner: SoftBody3D?
    var sheet: SoftBody3D?
    var ball: SoftBody3D?
    var grip: SoftGrip?

    /// How hard the wind blows along the line, in newtons.
    @Param(0 ... 12, icon: "wind") var wind = 3.2
    /// The air in the beach ball, in gravities of outward push. (Named `air`
    /// rather than `pressure`, which the sketch already uses for the pointer.)
    @Param(0 ... 5, icon: "circle.circle") var air = 3.0

    let lineY = 3.4, lineSpan = 5.2
    let bannerColor = Color(hex: 0xE05B4B)
    let sheetColor = Color(hex: 0xEDE6D8)
    let ballColor = Color(hex: 0x3FA9A0)

    /// One piece of the scenery, kept so the same numbers build the collider
    /// and draw the shape.
    struct Prop {
        var size: Vector3
        var at: Vector3
    }
    var props: [Prop] = []

    override func setup() {
        world.ground = 0
        buildStage()
        buildCloth()
    }

    /// The scenery the cloth has to answer to: two posts carrying the line, and
    /// a crate for the sheet to be thrown over.
    func buildStage() {
        for side in [-1.0, 1.0] {
            props.append(Prop(size: Vector3(0.16, lineY, 0.16),
                              at: Vector3(side * lineSpan / 2, lineY / 2, -1.4)))
        }
        props.append(Prop(size: Vector3(1.0, 1.0, 1.0), at: Vector3(1.5, 0.5, 1.6)))

        for prop in props {
            world.addBody(.box(width: prop.size.x, height: prop.size.y,
                               depth: prop.size.z),
                          at: prop.at, kind: .static, friction: 0.9)
        }
        // The line the banner is pegged to. Nothing hangs off it in the
        // simulation (the pegs hold the cloth directly), so it is a thin static
        // rod there only to be seen and bumped into.
        world.addBody(.cylinder(height: lineSpan, radius: 0.02),
                      at: Vector3(0, lineY, -1.4), kind: .static,
                      rotated: .pi / 2, axis: Vector3(0, 0, 1))
    }

    func buildCloth() {
        // A banner pegged along its top edge. The mesh is authored flat in the
        // ground plane, so it is stood upright on its way into the world and
        // the `pinned` test still reads the mesh's own coordinates: its far
        // edge in z becomes the top edge once it is up.
        // `at:` places the mesh's own origin, and this plane's origin is its
        // center, so the body is dropped half its depth below the line for its
        // pegged edge to land on it.
        banner = world.addSoftBody(from: .plane(width: 3.2, depth: 2.2, segments: 20),
                                   at: Vector3(-1.0, lineY - 1.1, -1.4),
                                   rotation: -.pi / 2, axis: Vector3(1, 0, 0),
                                   mass: 0.4, stiffness: 0.9, bend: 0.06,
                                   damping: 0.25, friction: 0.4, vertexRadius: 0.01,
                                   pinned: { $0.z > 1.0 })

        // A sheet dropped over the rail and the crate: nothing pins it, so the
        // shape it takes is the shape of what is under it.
        sheet = world.addSoftBody(from: .plane(width: 2.6, depth: 2.6, segments: 20),
                                  at: Vector3(1.5, 2.6, 1.2),
                                  mass: 0.6, stiffness: 0.95, bend: 0.25,
                                  friction: 0.9, vertexRadius: 0.015)

        // A closed surface, so the air inside it is what holds its shape.
        ball = world.addSoftBody(from: .icosphere(radius: 0.55, subdivisions: 3),
                                 at: Vector3(-1.7, 2.2, 1.9),
                                 mass: 0.5, bend: 0.4, pressure: air,
                                 damping: 0.05, friction: 0.4, bounce: 0.3,
                                 vertexRadius: 0.01)
    }

    override func mousePressed() {
        grip = grabSoftBody(at: Vector2(mouseX, mouseY), in: world)
    }

    override func mouseReleased() {
        if let grip { releaseSoftGrab(grip) }
        grip = nil
    }

    override func keyPressed() {
        if key == " " { tossBall() }
    }

    func tossBall() {
        ball?.wake()
        ball?.applyForce(Vector3(random(-60, 60), 900, random(-60, 60)))
    }

    override func draw() {
        background(Color(hex: 0x101722))
        environment(.courtyard.lightingOnly())
        lightingPreset(.studio)
        castShadows()
        cameraShowcase(.autoOrbit(period: 34), from: Camera3D
            .perspective(eye: Vector3(0.4, 3.4, 8.4), target: Vector3(0, 1.9, 0)))

        // Both knobs reach the solver between steps, which is the point of
        // them being live: the ball deflates under your hand.
        ball?.pressure = air
        blow()
        if let grip { dragSoftGrab(grip, to: Vector2(mouseX, mouseY)) }
        world.step(dt: deltaTime)

        drawStage()
        drawCloth()
        drawCaption("drag the cloth      space tosses the ball")
    }

    /// A gusting wind along the line. The banner catches most of it and the
    /// sheet a little: a force is spread over a body's whole surface, so what
    /// matters is how much of that surface is free to move.
    func blow() {
        let gust = wind * (0.55 + 0.45 * signedNoise(time * 0.55))
        let sway = signedNoise(time * 0.31 + 40) * 0.4
        banner?.applyForce(Vector3(sway * gust, 0, gust))
        sheet?.applyForce(Vector3(sway * gust * 0.2, 0, gust * 0.15))
    }

    func drawStage() {
        fill(Color(hex: 0x1A2230))
        material(.dielectric(roughness: 0.92))
        withState {
            translate(0, -0.06, 0)
            drawBox(width: 40, height: 0.12, depth: 40)
        }

        fill(Color(hex: 0x6B5138))
        material(.dielectric(roughness: 0.7))
        for prop in props {
            withState {
                translate(prop.at)
                drawBox(width: prop.size.x, height: prop.size.y, depth: prop.size.z)
            }
        }
        withState {
            translate(0, lineY, -1.4)
            rotate(.pi / 2, axis: Vector3(0, 0, 1))
            drawCylinder(radius: 0.02, height: lineSpan)
        }
    }

    /// Drawing a soft body is one call: the simulation hands back the mesh it
    /// arrived at, already in world space.
    func drawCloth() {
        material(.dielectric(roughness: 0.55))
        if let banner {
            fill(bannerColor)
            drawSoftBody(banner)
        }
        if let sheet {
            fill(sheetColor)
            drawSoftBody(sheet)
        }
        if let ball {
            // A deflating ball reads duller as well as flatter.
            fill(Color.mix(ballColor, Color(hex: 0x9AA6A4), t: 1 - min(1, air / 3)))
            material(.dielectric(roughness: 0.35))
            drawSoftBody(ball)
        }
    }
}
