import Ollin

/// Ray-traced reflections: a metal mirrors the *actual scene around it*, cleanly, with
/// none of screen-space reflection's artifacts.
///
/// Screen-space reflections (the `ScreenSpaceReflections` example) can only reflect what's
/// already on screen, and they streak where a curved object meets its contact shadow on a
/// near-mirror floor. Ray-traced reflections trace the real geometry instead, so the mirror
/// image is exact: geometry off the edge of the screen still reflects, and a sphere's
/// reflection on the floor is a clean foreshortened ellipse rather than a smeared band. It
/// plugs straight into the physically-based lighting: a metal's *environment* reflection
/// becomes a reflection of the *scene*, falling back to the environment where a ray flies off
/// into the open sky:
///
/// ```swift
/// camera(...); environment(.studio)
/// material(.polishedMetal); rayTracedReflections()
/// drawSphere(radius: 1)   // now mirrors the room around it, not just the sky
/// ```
///
/// A near-mirror metal floor reflects a ring of metal spheres orbiting a polished monolith;
/// each sphere also catches its neighbors and the floor. An outer ring of posts is drawn as
/// instanced *copies*, one call for all of them, and they mirror like everything else. The camera orbits on its own, and
/// the mouse takes it over (drag to orbit, scroll to dolly). **Hold the space bar** to drop
/// ray-traced reflections and compare: the metals fall back to reflecting only the studio
/// *environment*, so the scene's mirror images vanish. Needs an Apple-silicon (ray-tracing)
/// GPU; on other GPUs the environment reflection is all you get.
@main
final class RayTracedReflections: Sketch {

    override func draw() {
        background(Color(hex: 0x14171d))
        cameraShowcase(.autoOrbit(period: .tau / 0.12),
                       target: Vector3(0, 0.8, 0), radius: 8.5, elevation: 0.34,
                       fieldOfView: .pi / 4, near: 1, far: 30)
        // The studio environment lights the metals and is the reflection's miss fallback (a ray
        // that leaves the scene shows the room). Its softly-blurred backdrop fills the frame.
        environment(.studio.intensity(1.1).backgroundBlur(0.5))
        directionalLight(.white, direction: Vector3(-0.4, -1, -0.25), intensity: 0.7)
        castShadows()

        // Ray-trace reflections off every metal in the scene (hold the space bar to compare).
        if !isKeyDown(" ") { rayTracedReflections() }

        // A near-mirror metal floor, the broad flat reflector RT reflections handle cleanly.
        withState {
            material(.metal(roughness: 0.06))
            fill(Color(hex: 0x8a8f9c))
            translate(0, -0.5, 0)
            drawBox(width: 26, height: 1.0, depth: 26)
        }

        // A polished monolith at the center.
        withState {
            material(.polishedMetal)
            fill(Color(hex: 0xe8ebf2))
            translate(0, 1.1, 0)
            drawBox(width: 0.9, height: 2.6, depth: 0.9)
        }

        // A ring of metal spheres, each a different finish; they reflect the monolith, the
        // floor, and each other.
        let spheres: [(color: Color, finish: Material)] = [
            (Color(hex: 0xf3f4f8), .polishedMetal),           // chrome
            (Color(hex: 0xffc94a), .metal(roughness: 0.12)),  // gold
            (Color(hex: 0x6f9be8), .brushedMetal),            // steel-blue
            (Color(hex: 0xe07a3a), .metal(roughness: 0.1)),   // copper
            (Color(hex: 0x49cf86), .polishedMetal),           // emerald
            (Color(hex: 0xd158b4), .metal(roughness: 0.2)),   // magenta
        ]
        for (i, s) in spheres.enumerated() {
            let a = Double(i) / Double(spheres.count) * .tau
            withState {
                material(s.finish)
                fill(s.color)
                translate(cos(a) * 3.6, 0.9, sin(a) * 3.6)
                drawSphere(radius: 0.9)
            }
        }

        // A ring of small posts drawn as *copies* (one `drawMesh` call, one placement each).
        // Copies reach the traced scene like any other mesh, so they stand in the floor's
        // reflection and in the spheres' too, each carrying its own color.
        var posts: [MeshInstance] = []
        for i in 0 ..< 24 {
            let a = Double(i) / 24 * .tau + 0.13
            posts.append(MeshInstance(position: Vector3(cos(a) * 6.2, 0.45, sin(a) * 6.2),
                                      rotation: Vector3(0, -a, 0),
                                      color: Color(hue: Double(i) / 24, saturation: 0.5, brightness: 1)))
        }
        withState {
            material(.metal(roughness: 0.18))
            fill(.white)
            drawMesh(Mesh.box(width: 0.34, height: 1.9, depth: 0.34), instances: posts)
        }

        drawCaption(isKeyDown(" ")
            ? "Ray-traced reflections: OFF (release space to compare)"
            : "Ray-traced reflections: ON (hold space to compare)")
    }
}
