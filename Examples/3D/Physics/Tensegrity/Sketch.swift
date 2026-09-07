import Foundation
import Ollin
import OllinPhysics

/// Three tensegrities dropped onto a floor: a three-strut prism, the six-strut
/// icosahedron, and a mast of stacked prisms. Each one lands, bounces on its
/// own cables, and stands, because every strut pushes exactly as hard as the
/// cables around it pull. Not one strut touches another in the first two; the
/// mast shares a node where its levels meet.
///
/// **Drag** any strut and let go: the whole form follows, stretches, and
/// rights itself. **Space** drops them again. `prestress` is how much shorter
/// than drawn each cable is made, which is what tightens a real one; take it
/// to zero and a landing can leave a cable loose.
@main
final class TensegritySketch: Sketch {
    let world = World3D()
    var forms: [Tensegrity3D] = []

    /// How much shorter than its drawn length each cable is cut, as a fraction.
    @Param(0 ... 0.08, icon: "arrow.left.and.right") var prestress = 0.02

    let strutColors = [Color(hex: 0xE8632F), Color(hex: 0xF2B84B), Color(hex: 0x72BFB2)]
    let cableColor = Color(hex: 0xE6E9EE)

    override func setup() {
        world.ground = 0
        world.restitution = 0.15
        drop()
    }

    /// Build the three forms a little above the floor and tipped, so each one
    /// lands on an edge and has to find its feet.
    func drop() {
        for form in forms { world.remove(form) }
        forms.removeAll()
        // The prism and the ball are tipped so they land on an edge and have
        // to find their feet; the mast is set down straight, since a tall thin
        // thing dropped on a lean falls over, tensegrity or not.
        let tip = Rotation3D(angle: 0.3, axis: Vector3(0.4, 0, 1).normalized)
        let shapes: [(Tensegrity, Double, Double)] = [
            (Tensegrity.prism(struts: 3, radius: 0.62, height: 1.15).rotated(by: tip), -2.25, 0.9),
            (Tensegrity.icosahedron(strutLength: 1.75).rotated(by: tip), 0, 0.9),
            (Tensegrity.tower(levels: 3, struts: 3, radius: 0.46, levelHeight: 0.95), 2.25, 0.4),
        ]
        for (index, (shape, x, lift)) in shapes.enumerated() {
            guard let built = world.addTensegrity(shape,
                                                  at: Vector3(x, lift - shape.bottom, 0),
                                                  strutRadius: 0.038,
                                                  prestress: prestress,
                                                  friction: 0.7)
            else { continue }
            for strut in built.struts { strut.userData = strutColors[index] }
            forms.append(built)
        }
    }

    override func keyPressed() {
        if key == " " { drop() }
    }

    override func draw() {
        background(Color(hex: 0x10141B))
        environment(.sky(turbidity: 3, sunElevation: 0.55).lightingOnly())
        lightingPreset(.studio)
        castShadows()
        perspective(eye: Vector3(0.5, 2.0, 6.4), target: Vector3(0, 1.15, 0), fieldOfView: .pi / 3.4)

        dragBodies(in: world)
        world.advance(by: deltaTime)

        fill(Color(hex: 0x1C2230))
        material(.dielectric(roughness: 0.9))
        drawGround(size: 30)

        // Struts in their own color, cables in pale steel, so the two kinds of
        // member read apart: the struts never meet, the cables meet everywhere.
        for form in forms {
            material(.dielectric(roughness: 0.5))
            for strut in form.struts {
                fill(strut.userData as? Color ?? .white)
                drawBody(strut)
            }
            fill(cableColor)
            material(.metal(roughness: 0.3))
            let nodes = form.nodes
            for cable in form.source.cables {
                drawCapsule(from: nodes[cable.a], to: nodes[cable.b], radius: 0.009,
                            segments: 8, rings: 3)
            }
        }

        drawCaption("struts push, cables pull, nothing touches      drag a strut, space to drop them again")
    }
}
