// figure: frame=0
//
// Guide figure (Chapter 33): a flat field stood up. One badge, a disc melted into a
// bar and a star with a ring carved through, three times: filled flat on the canvas,
// standing as a slab with its faces flat, and one block thick as pixel art.
import Ollin

final class StandingSlab: Sketch {
    override var canvasSize: CanvasSize { .size(1200, 480) }

    let plum = Color(hex: 0x5B2A86)
    let coral = Color(hex: 0xE8603C)
    let gold = Color(hex: 0xF2B134)
    let mint = Color(hex: 0x8ED3C0)

    override func draw() {
        background(Color(hex: 0xF4EFE6))

        // The flat field, as drawSDF fills it, on the left third of the sheet.
        noStroke()
        withState {
            translate(165, 250)
            scale(50)
            drawSDF(badge())
        }

        camera(.perspective(eye: Vector3(2.6, 2.4, 6.4), target: Vector3(2.6, 0.1, 0),
                            fieldOfView: .pi / 4.6))
        directionalLight(Color(hex: 0xFFF4E0), direction: Vector3(-0.5, -0.8, -0.3), intensity: 1.1)
        ambientLight(Color(hex: 0xB9C4D6))
        material(.matte)
        fill(Color(hex: 0xDED4C4))
        withState { translate(2.6, -1.05, 0); drawBox(width: 7, height: 0.2, depth: 6) }

        drawSDF3D(badge().extruded(depth: 0.5).rotatedX(-0.4).at(1.1, 0.15, 0))
        drawSDF3D(badge().extruded(depth: 0.16).at(0, 0, 0.08).voxelized(size: 0.16, seed: 5).rotatedX(-0.4).at(4.1, 0.15, 0))
    }

    private func badge() -> SDF {
        let disc = SDF.circle(radius: 1.15).colored(plum)
        let bar = SDF.rect(width: 2.6, height: 0.55, cornerRadius: 0.2).at(0.9, -0.5).colored(coral)
        let star = SDF.star(outerRadius: 0.85, innerRadius: 0.4, points: 5).at(-1.25, 0.75).colored(gold)
        let ring = SDF.ring(innerRadius: 0.32, outerRadius: 0.5).at(0.35, 0.45).colored(mint)
        return disc.smoothUnion(bar, k: 0.4).smoothUnion(star, k: 0.3).subtract(ring)
    }
}
