// figure: frame=200
//
// Guide figure (Chapter 24): three tensegrities that have landed and stand. A
// three-strut prism, the six-strut icosahedron, and a three-level mast, each
// one built from capsule struts on .cable joints and dropped from a little
// height. No random anywhere, so it replays identically.
import Ollin
import OllinPhysics

final class TensegrityFigure: Sketch {
    override var canvasSize: CanvasSize { .size(880, 550) }

    let world = World3D()
    var forms: [Tensegrity3D] = []
    let strutColors = [Color(hex: 0xE8632F), Color(hex: 0xF2B84B), Color(hex: 0x72BFB2)]

    override func setup() {
        world.ground = 0
        world.restitution = 0.15
        // The prism and the ball are tipped so they land on an edge and have
        // to find their feet; the mast is set down straight, since a tall thin
        // thing dropped on a lean falls over, tensegrity or not.
        let tip = Rotation3D(angle: 0.3, axis: Vector3(0.4, 0, 1).normalized)
        let shapes: [(Tensegrity, Double, Double)] = [
            (Tensegrity.prism(struts: 3, radius: 0.62, height: 1.15).rotated(by: tip), -2.25, 0.7),
            (Tensegrity.icosahedron(strutLength: 1.75).rotated(by: tip), 0, 0.7),
            (Tensegrity.tower(levels: 3, struts: 3, radius: 0.46, levelHeight: 0.95), 2.25, 0.35),
        ]
        for (index, (shape, x, lift)) in shapes.enumerated() {
            guard let built = world.addTensegrity(shape, at: Vector3(x, lift - shape.bottom, 0),
                                                  strutRadius: 0.038, friction: 0.7)
            else { continue }
            for strut in built.struts { strut.userData = strutColors[index] }
            forms.append(built)
        }
    }

    override func draw() {
        background(Color(hex: 0x10141B))
        environment(.sky(turbidity: 3, sunElevation: 0.55).lightingOnly())
        lightingPreset(.studio)
        castShadows()
        perspective(eye: Vector3(0.5, 1.9, 6.0), target: Vector3(0, 1.15, 0), fieldOfView: .pi / 3.6)

        world.advance(by: 1.0 / 60)

        fill(Color(hex: 0x1C2230))
        material(.dielectric(roughness: 0.9))
        drawGround(size: 30)

        for form in forms {
            material(.dielectric(roughness: 0.5))
            for strut in form.struts {
                fill(strut.userData as? Color ?? .white)
                drawBody(strut)
            }
            fill(Color(hex: 0xE6E9EE))
            material(.metal(roughness: 0.3))
            let nodes = form.nodes
            for cable in form.source.cables {
                drawCapsule(from: nodes[cable.a], to: nodes[cable.b], radius: 0.009,
                            segments: 8, rings: 3)
            }
        }
    }
}
