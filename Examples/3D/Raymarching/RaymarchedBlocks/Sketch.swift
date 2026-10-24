import Ollin
import Foundation

/// Any raymarched field rebuilt out of cubes with `voxelized(size:)`: every cell of
/// a grid whose center lies inside the field becomes a block, colored the way the
/// field is colored at that center. Three forms on a picker:
///
/// - **model**: a sphere melted into a ring, the melt's blended colors landing a
///   block at a time, the voxel model of a smooth thing.
/// - **island**: a slab of grass with two hills, a beach, three trees, and a strip of
///   water, all ordinary fields, as one blocky landscape.
/// - **pixel art**: a heart made of two discs and a square, as thin as one block, so
///   from the front it is pixel art and from the side a slab of bricks.
///
/// Each face is flat and square to the grid; the creases between stacked blocks
/// darken, a thin seam runs along every face's edge, and each block's tone moves a
/// little by its own seeded amount. The `size` slider rebuilds the blocks live.
/// Blocks cost about three times the field they are built from; `shadows` lets
/// them shade each other, and doubles that again.
///
/// Try it: drag `size` down until the model turns smooth again, or open `gap` to
/// see each block stand alone.
@main
final class RaymarchedBlocks: Sketch {
    enum Form: String, CaseIterable, ParamOption { case model, island, pixelArt }

    @Param(style: .segmented, icon: "cube") var form = Form.model
    @Param(0.05 ... 0.5, icon: "square.grid.3x3") var size = 0.16
    @Param(0 ... 0.5, icon: "square.split.2x2") var gap = 0.0
    @Param(0 ... 1, icon: "circle.lefthalf.filled") var occlusion = 0.55
    @Param(0 ... 1, icon: "line.3.horizontal") var seams = 0.3
    @Param(0 ... 0.3, icon: "dice") var jitter = 0.08
    @Param(icon: "shadow") var shadows = false

    override var loopDuration: Double? { 24 }

    override func draw() {
        background(Color(hex: 0x9CC3E0))
        let turn = time / 24 * 2 * .pi
        camera(.orbiting(target: Vector3(0, 0.1, 0), radius: form == .pixelArt ? 7.5 : 8.5, azimuth: turn,
                         elevation: form == .pixelArt ? 0.15 : 0.55, fieldOfView: .pi / 4, near: 0.1, far: 60))
        directionalLight(Color(hex: 0xFFF4E0), direction: Vector3(-0.45, -0.8, -0.35), intensity: 1.15,
                         softness: 0.3)
        ambientLight(Color(hex: 0x6E8AA8))
        castShadows(shadows)
        material(.matte)

        let field: SDF3D
        switch form {
        case .model: field = model()
        case .island: field = island()
        case .pixelArt: field = heart()
        }
        drawSDF3D(field.voxelized(size: size, gap: gap, jitter: jitter, seams: seams,
                                  occlusion: occlusion, seed: 3))
    }

    /// A sphere melted into a ring around it, the seam blending their colors.
    private func model() -> SDF3D {
        SDF3D.sphere(radius: 1.25).colored(Color(hex: 0xE8A24A))
            .smoothUnion(SDF3D.torus(radius: 1.75, tube: 0.38).rotatedX(0.35).colored(Color(hex: 0x3E8FB0)), k: 0.45)
            .smoothUnion(SDF3D.sphere(radius: 0.45).at(0, 1.45, 0).colored(Color(hex: 0xD9534F)), k: 0.3)
    }

    /// Grass on a slab of earth, two hills, a beach, three trees, and the sea.
    private func island() -> SDF3D {
        let earth = SDF3D.box(width: 5, height: 0.5, depth: 4).at(0, -0.6, 0).colored(Color(hex: 0x8A6A44))
        let grass = SDF3D.box(width: 4.4, height: 0.3, depth: 3.4).at(0, -0.25, 0).colored(Color(hex: 0x6AB04C))
            .smoothUnion(SDF3D.sphere(radius: 1.1).at(-1.1, -0.4, 0.4).colored(Color(hex: 0x5C9E40)), k: 0.4)
            .smoothUnion(SDF3D.sphere(radius: 0.8).at(1.1, -0.4, 0.5).colored(Color(hex: 0x6AB04C)), k: 0.4)
        let beach = SDF3D.box(width: 5, height: 0.25, depth: 0.6).at(0, -0.4, 1.9).colored(Color(hex: 0xE9D8A6))
        let sea = SDF3D.box(width: 6.5, height: 0.2, depth: 1.4).at(0, -0.65, 2.7).colored(Color(hex: 0x3A7CA5))
        // One tree, repeated along the back of the island.
        let tree = SDF3D.cylinder(radius: 0.12, height: 1.0).at(0, 0.4, 0).colored(Color(hex: 0x6B4A2B))
            .union(SDF3D.sphere(radius: 0.45).at(0, 1.1, 0).colored(Color(hex: 0x2F6B3A)))
            .repeated(spacing: Vector3(1.5, 0, 0), count: 1)
            .at(0, -0.1, -1.0)
        return earth.union(grass).union(beach).union(sea).union(tree)
    }

    /// A heart one block thick: two discs and a square turned on its corner. A
    /// block is decided by its center, and the centers of the row nearest the
    /// origin sit half a block in front of it, so the slab is moved onto them.
    private func heart() -> SDF3D {
        let thin = size
        let lobe = SDF3D.cylinder(radius: 0.9, height: thin).rotatedX(.pi / 2)
        let red = Color(hex: 0xD62839)
        return lobe.at(-0.75, 0.5, 0).colored(red)
            .union(lobe.at(0.75, 0.5, 0).colored(red))
            .union(SDF3D.box(width: 1.8, height: 1.8, depth: thin).rotatedZ(.pi / 4).at(0, -0.15, 0).colored(red))
            .union(SDF3D.cylinder(radius: 0.28, height: thin * 1.2).rotatedX(.pi / 2).at(-0.75, 0.75, 0)
                .colored(Color(hex: 0xF8D7DA)))
            .at(0, 0, size / 2)
    }
}
