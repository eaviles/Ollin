// figure: gif duration=4 fps=12 width=480
//
// Guide figure (Chapter 21): the cartoon look, and the light that rides the
// camera. Three toon solids with an ink line, the view swaying to and fro
// under a three-point rig read relativeTo(.camera): the cel bands stay put
// on each shape as the view moves, and the line keeps its width like a pen.
import Ollin

final class Inked: Sketch {
    override var canvasSize: CanvasSize { .size(880, 550) }

    override func draw() {
        background(Color(hex: 0xF2EBDD))
        let azimuth = 0.9 * sin(time * .tau / 4)
        camera(.orbiting(target: Vector3(0, -0.2, 0), radius: 8.5,
                         azimuth: azimuth, elevation: 0.3, fieldOfView: .pi / 4))
        lightingPreset(.threePoint.relativeTo(.camera))

        var toon = Material.toon
        toon.toonBands = 3
        material(toon)
        outline(width: 3, color: Color(white: 0.08))

        withState {
            translate(-2.4, -0.3, 0.3)
            fill(Color(hex: 0xE8553F))
            drawSphere(radius: 1.05, segments: 64, rings: 40)
        }
        withState {
            translate(0.1, 0, -0.4)
            rotateY(0.6); rotateX(0.4)
            fill(Color(hex: 0x3F9BD9))
            drawBox(size: 1.5)
        }
        withState {
            translate(2.5, -0.4, 0.5)
            rotateX(1.05); rotateY(0.4)
            fill(Color(hex: 0xC85BB5))
            drawTorus(radius: 0.75, tube: 0.32, segments: 64, sides: 32)
        }
        withState {
            // The floor takes a matte finish and no line: a toon floor would
            // band, and the rig's highlight would land on it between the shapes.
            translate(0, -1.75, 0)
            material(.matte)
            noOutline()
            fill(Color(hex: 0xD9D0BC))
            drawPlane(width: 16, depth: 16)
        }
    }
}
