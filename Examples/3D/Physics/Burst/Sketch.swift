import Ollin
import OllinPhysics

/// Solids thrown up through the view, each breaking at the top of its arc into
/// pieces that tumble back down. Nobody hits them: every one comes apart on its
/// own, and what falls is exactly what went up, in `Mesh.fractured` pieces that
/// fit back together with no gap and no overlap.
///
/// The break is one call. `fractured(into:around:seed:)` cuts the solid into
/// convex cells around the point where it gave way, so the chips are small
/// there and the wedges long away from it. A convex cell is also what a rigid
/// body wants, so each piece goes straight into the world: the body sits at the
/// piece's `centroid`, the solver gets the piece's points as a hull, and the
/// piece keeps the parent's motion plus a push out of the break.
///
/// Every solid here is drawn from the same mesh the solver was handed, whole or
/// broken, so the picture and the physics cannot drift apart.
///
/// **Click** a solid to break it early. **Space** clears the view.
@main
final class Burst3D: Sketch {
    let world = World3D()

    /// What a body draws as, hung off `Body3D.userData`: its mesh in its own
    /// coordinates, its color, and (for a whole solid) the upward speed at
    /// which it lets go. A piece carries no such speed and never breaks again.
    final class Look {
        let mesh: Mesh
        let color: Color
        let breaksAt: Double?
        init(mesh: Mesh, color: Color, breaksAt: Double? = nil) {
            self.mesh = mesh
            self.color = color
            self.breaksAt = breaksAt
        }
    }

    let palette: [Color] = [
        Color(hex: 0xE8632F), Color(hex: 0xF2A93B), Color(hex: 0x72BFB2),
        Color(hex: 0x8D92E0), Color(hex: 0xDE87B2), Color(hex: 0x9CCB6B),
    ]

    override func setup() {
        world.gravity = Vector3(0, -16, 0)
        world.restitution = 0.1
    }

    /// Throw one solid up from under the bottom of the view.
    func throwOne() {
        guard world.bodies.count < 200 else { return }
        let size = random(0.55, 0.95)
        // Five convex solids. The collider is the hull of the very mesh that
        // gets drawn, so there is one shape here, not a drawn one and a
        // simulated one.
        let mesh: Mesh
        switch Int(random(5)) {
        case 0: mesh = .box(size: size * 1.6)
        case 1: mesh = .icosphere(radius: size, subdivisions: 1)
        case 2: mesh = .icosahedron(radius: size)
        case 3: mesh = .dodecahedron(radius: size)
        default: mesh = .cone(radius: size, height: size * 2, segments: 18)
        }

        let solid = world.addBody(.hull(mesh.positions),
                                  at: Vector3(random(-3.4, 3.4), -6, random(-1.2, 1.2)),
                                  rotated: random(.tau),
                                  axis: Vector3(random(-1, 1), random(-1, 1), random(-1, 1)),
                                  friction: 0.5, restitution: 0.1)
        solid.velocity = Vector3(random(-1.1, 1.1), random(15.2, 16.6), random(-0.5, 0.5))
        solid.angularVelocity = Vector3(random(-3, 3), random(-3, 3), random(-3, 3))
        solid.userData = Look(mesh: mesh, color: randomChoice(palette),
                              breaksAt: random(-1.2, 1.2))
    }

    /// Break one solid into pieces, each with the parent's motion and a push
    /// out of the break.
    func burst(_ solid: Body3D, look: Look) {
        let turn = solid.rotation
        let here = solid.position
        let motion = solid.velocity
        let spin = solid.angularVelocity
        // Where it gives way: off-center, so the cut is not the same twice.
        let reach = look.mesh.size.length * 0.22
        let impact = look.mesh.centroid
            + Vector3(random(-1, 1), random(-1, 1), random(-1, 1)).normalized * reach
        let pieces = look.mesh.fractured(into: Int(random(9, 15)), around: impact,
                                         seed: Int(random(10_000)))
        world.remove(solid)

        for piece in pieces {
            let middle = piece.centroid
            let local = piece.mapPositions { $0 - middle }
            let shard = world.addBody(.hull(local.positions),
                                      at: here + middle.rotated(by: turn),
                                      rotated: turn.angle, axis: turn.axis,
                                      friction: 0.5, restitution: 0.15)
            let push = (middle - impact).normalized.rotated(by: turn) * random(1.2, 3.4)
            shard.velocity = motion + push
            shard.angularVelocity = spin + Vector3(random(-6, 6), random(-6, 6), random(-6, 6))
            shard.userData = Look(mesh: local,
                                  color: look.color.mixed(with: .white, random(0, 0.22)))
        }
    }

    override func mousePressed() {
        guard let hit = body(under: mouse, in: world),
              let look = hit.body.userData as? Look, look.breaksAt != nil else { return }
        burst(hit.body, look: look)
    }

    override func keyPressed() {
        if key == " " { world.removeAll() }
    }

    override func draw() {
        background(Color(hex: 0x0E1116))
        lightingPreset(.studio)
        perspective(eye: Vector3(0, 1.4, 9.5), target: Vector3(0, 0.6, 0))

        if frameCount % 22 == 0 { throwOne() }
        world.advance(by: deltaTime)

        // Past the top of the arc it lets go: the solid is on its way down, and
        // still high enough that the break happens inside the view.
        for body in world.bodies {
            guard let look = body.userData as? Look, let breaksAt = look.breaksAt else { continue }
            if body.velocity.y <= breaksAt && body.position.y > -1.5 {
                burst(body, look: look)
            }
        }

        // Anything below the view has had its fall.
        for body in world.bodies where body.position.y < -9 {
            world.remove(body)
        }

        material(.dielectric(roughness: 0.45))
        for body in world.bodies {
            guard let look = body.userData as? Look else { continue }
            fill(look.color)
            withBody(body) {
                drawMesh(look.mesh)
            }
        }
    }
}
