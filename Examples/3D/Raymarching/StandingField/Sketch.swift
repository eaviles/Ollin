import Ollin
import Foundation

/// A flat field stood up as a slab: a 2D composition of `SDF` shapes and
/// combinators, the same one `drawSDF` would fill on the canvas, extruded into
/// a solid with `extruded(depth:)` and marched in 3D. Three forms on a picker:
///
/// - **slab**: a badge melted out of a disc, a bar, and a star, with a ring
///   carved through it, standing a set depth thick and turning on the table.
/// - **pixel art**: the same badge one block thick and `voxelized`, which from
///   the front is pixel art and from the side a row of bricks.
/// - **bricks**: the badge deep and voxelized with a gap, so every block stands
///   alone and the melt lands a brick at a time.
///
/// The flat program runs as the 3D walk's own instructions, so a smooth union
/// melts in the plane and the slab's faces stay flat: the 2D field drawn below
/// the solid is the one standing on it. `depth` and `size` rebuild it live.
@main
final class StandingField: Sketch {
    enum Form: String, CaseIterable, ParamOption { case slab, pixelArt, bricks }

    @Param(style: .segmented, icon: "square.stack.3d.up") var form = Form.slab
    @Param(0.1 ... 1.2, icon: "arrow.up.and.down") var depth = 0.45
    @Param(0.08 ... 0.4, icon: "square.grid.3x3") var size = 0.16
    @Param(0 ... 1, icon: "circle.lefthalf.filled") var melt = 0.5
    @Param(icon: "square.on.square") var showsFlat = true

    override var loopDuration: Double? { 16 }

    let plum = Color(hex: 0x5B2A86)
    let coral = Color(hex: 0xE8603C)
    let gold = Color(hex: 0xF2B134)
    let mint = Color(hex: 0x8ED3C0)

    override func draw() {
        background(Color(hex: 0xF4EFE6))
        let turn = time / 16 * 2 * .pi

        camera(.orbiting(target: Vector3(0, 0.35, 0), radius: 7.5, azimuth: 0.5 + 0.5 * sin(turn), elevation: 0.5,
                         fieldOfView: .pi / 4.2, near: 0.1, far: 50))
        directionalLight(Color(hex: 0xFFF4E0), direction: Vector3(-0.5, -0.8, -0.3), intensity: 1.1,
                         softness: 0.25)
        ambientLight(Color(hex: 0xB9C4D6))
        castShadows(true)
        material(.matte)

        // The table, so the slab throws a shadow and the camera has a floor.
        fill(Color(hex: 0xDED4C4))
        withState { translate(0, -0.9, 0); drawBox(width: 9, height: 0.2, depth: 9) }

        let standing: SDF3D
        switch form {
        case .slab:
            standing = badge().extruded(depth: depth)
        case .pixelArt:
            // One block thick: the slab sits half a block off the grid so it holds
            // a row of cell centers (the blocks' rule).
            standing = badge().extruded(depth: size).at(0, 0, size / 2).voxelized(size: size, seed: 5)
        case .bricks:
            standing = badge().extruded(depth: max(depth, 2.5 * size)).voxelized(size: size, gap: 0.2, seed: 5)
        }
        drawSDF3D(standing.rotatedX(-1.15).at(0, 0.35, 0))

        // The flat field, as drawSDF fills it on the canvas, inset at the foot.
        if showsFlat {
            noStroke()
            withState {
                translate(150, height - 150)
                scale(38)
                drawSDF(badge())
            }
        }
    }

    /// The badge as a flat field: a disc melted into a bar and a star, a ring
    /// carved through, each leaf its own color, in field units a few across.
    private func badge() -> SDF {
        let k = 0.1 + 0.6 * melt
        let disc = SDF.circle(radius: 1.15).colored(plum)
        let bar = SDF.rect(width: 2.6, height: 0.55, cornerRadius: 0.2).at(0.9, -0.5).colored(coral)
        let star = SDF.star(outerRadius: 0.85, innerRadius: 0.4, points: 5).at(-1.25, 0.75).colored(gold)
        let ring = SDF.ring(innerRadius: 0.32, outerRadius: 0.5).at(0.35, 0.45).colored(mint)
        return disc.smoothUnion(bar, k: k).smoothUnion(star, k: k * 0.8).subtract(ring)
    }
}
