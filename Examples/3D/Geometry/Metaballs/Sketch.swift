import Ollin

/// Metaballs: soft spheres that reach for each other and fuse.
///
/// Each ball adds a bump to one shared scalar field, and `isosurface` walks a
/// grid of cubes looking for where that field crosses `level`, stitching the
/// crossings into a `Mesh` (marching cubes). Because the bumps *add*, the
/// field between two nearby balls sits higher than either makes there alone,
/// so the surface bulges across the gap and the two run together into one
/// skin. Pull them apart and it necks down and snaps.
///
/// The `merge` knob is that crossing level: lower it and every blob fattens
/// and reaches further, raise it and they thin out and separate. `detail` is
/// how fine the cube grid is, which is where the cost lives, so it is the
/// knob to drop first if the frame rate does.
@main
final class Metaballs3D: Sketch {

    /// Where each blob rides: an orbit radius, a tilt, a speed, and a size.
    /// The orbits are wide enough that the cluster keeps opening up, so the
    /// necks between blobs stay visible instead of settling into one lump.
    private let orbits: [(radius: Double, tilt: Double, speed: Double, size: Double)] = [
        (0.55, 0.00, 0.31, 0.95),
        (2.35, 0.35, 0.62, 0.78),
        (2.70, 1.90, -0.47, 0.70),
        (2.10, 3.60, 0.81, 0.64),
        (2.95, 5.10, -0.33, 0.58),
        (2.50, 2.60, 0.55, 0.60),
    ]

    @Param(0.25 ... 0.85, icon: "drop.halffull") var merge = 0.5
    @Param(24 ... 96, icon: "square.grid.3x3") var detail = 56.0
    @Param(icon: "sparkles") var polished = true

    override func draw() {
        background(Color(hex: 0x080A0F))
        // The environment lights the surface and gives the metal something to
        // reflect, but its backdrop is left undrawn so the blobs read against
        // the dark rather than against a room.
        environment(.courtyard.rotated(time * 0.06).lightingOnly())
        lightingPreset(.studio)
        cameraShowcase(.autoOrbit(period: 26), radius: 7.6, elevation: 0.38)

        var field = Metaballs(level: merge)
        for orbit in orbits {
            // A slow vertical sway on a different period from the orbit, so the
            // cluster never repeats a formation exactly.
            let angle = time * orbit.speed + orbit.tilt
            let lift = sin(time * orbit.speed * 0.73 + orbit.tilt) * 0.75
            field.add(at: Vector3(cos(angle) * orbit.radius,
                                  lift,
                                  sin(angle) * orbit.radius),
                      radius: orbit.size)
        }

        fill(polished ? Color(hex: 0xD4DCE6) : Color(hex: 0xE8632F))
        material(polished ? .metal(roughness: 0.2) : .dielectric(roughness: 0.3))
        drawMesh(field.mesh(resolution: Int(detail)))
    }
}
