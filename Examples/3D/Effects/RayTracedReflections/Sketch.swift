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
/// instanced *copies*, one call for all of them, and a retained `MeshField` scatters a drift
/// of pebbles past them. All three ways of placing a mesh mirror alike. A cel-shaded torus
/// and a Gooch-shaded cone stand among them to show the other half of that: a traced hit is
/// shaded in the finish its surface wears, so the torus keeps its hard bands in the floor,
/// the cone its warm-to-cool ramp, and the lacquered sphere in the ring its clear coat. The camera orbits on its own, and
/// the mouse takes it over (drag to orbit, scroll to dolly). **Hold the space bar** to drop
/// ray-traced reflections and compare: the metals fall back to reflecting only the studio
/// *environment*, so the scene's mirror images vanish. Needs an Apple-silicon (ray-tracing)
/// GPU; on other GPUs the environment reflection is all you get.
///
/// A traced ray is the *mirror* ray, so on its own a satin or brushed surface answers
/// roughness by fading that one ray into the blurred environment, and a satin floor in a
/// red room reflects a gray sky. `glossyReflections()` spreads each ray by the surface's
/// own roughness instead, and every pixel also borrows the rays its neighbors sent, which
/// is what turns a handful of rays into a smooth reflection rather than glitter. The row
/// of satin spheres standing out among the pebbles carries the point: mirror on the left
/// to nearly matte on the right, each showing the room softened by exactly as much as it
/// is rough. **Hold G** to drop back to the mirror ray and watch the room drain out of
/// them, the mirror ball staying where it is because a mirror was never the problem.
///
/// `reflectionBounces(_:)` sets how far a reflection is allowed to travel. The default
/// pair (the ray finds a surface, and that surface's own reflection is the environment)
/// keeps a polished corner honest; mirrors facing mirrors are the case that needs more,
/// or their tunnel of images stops early and shows the sky in the last door. Each step
/// costs one more traced ray for every reflected pixel, and each mirror passes on only
/// the fraction it reflects, so the images dim fast: three or four is usually the end of
/// what reads. The **Bounces** stepper drives it here; watch the chrome spheres' images
/// of the monolith and of each other deepen a step at a time.
@main
final class RayTracedReflections: Sketch {

    @Param(2 ... 8, icon: "arrow.triangle.2.circlepath", group: "Reflection")
    var bounces = 4

    /// The pebble drift, built once and held: a field places its copies on the GPU
    /// and still stands in the traced scene, up to its `tracedCopyBudget`.
    private let pebbles = MeshField()

    override func setup() {
        seed(11)
        var drift: [MeshInstance] = []
        for _ in 0 ..< 700 {
            let a = random(.tau), r = random(7.6, 12.6)
            drift.append(MeshInstance(position: Vector3(cos(a) * r, 0.08, sin(a) * r),
                                      rotation: Vector3(0, random(.tau), 0),
                                      scale: Vector3(random(0.5, 1.1), random(0.3, 0.7),
                                                     random(0.5, 1.1)),
                                      color: Color(hue: random(1), saturation: 0.16, brightness: 0.72)))
        }
        pebbles.place(Mesh.box(width: 0.46, height: 0.3, depth: 0.46), at: drift)
    }

    override func draw() {
        background(Color(hex: 0x14171d))
        cameraShowcase(.autoOrbit(period: .tau / 0.12),
                       target: Vector3(0, 0.8, 0), radius: 8.5, elevation: 0.34,
                       fieldOfView: .pi / 4, near: 1, far: 30)
        // The live window renders at two-thirds size and reconstructs the full
        // canvas; exports and snapshots still render every pixel.
        temporalUpscaling()
        // The studio environment lights the metals and is the reflection's miss fallback (a ray
        // that leaves the scene shows the room). Its softly-blurred backdrop fills the frame.
        environment(.studio.intensified(to: 1.1).backgroundBlurred(0.5))
        directionalLight(.white, direction: Vector3(-0.4, -1, -0.25), intensity: 0.7)
        castShadows()

        // Ray-trace reflections off every metal in the scene (hold the space bar to compare),
        // spreading each ray by its surface's roughness (hold G for the bare mirror ray).
        if !isKeyDown(" ") {
            rayTracedReflections()
            if !isKeyDown("g") { glossyReflections() }
        }
        reflectionBounces(bounces)

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

        // A ring of spheres, each a different finish; they reflect the monolith, the
        // floor, and each other. Five are metals. The last wears a clear coat instead, a
        // dielectric under a polished film, and the film travels: the lacquered sphere
        // carries its coat into the floor's image of it and into its neighbors' too.
        let spheres: [(color: Color, finish: Material)] = [
            (Color(hex: 0xf3f4f8), .polishedMetal),           // chrome
            (Color(hex: 0xffc94a), .metal(roughness: 0.12)),  // gold
            (Color(hex: 0x6f9be8), .brushedMetal),            // steel-blue
            (Color(hex: 0xe07a3a), .metal(roughness: 0.1)),   // copper
            (Color(hex: 0x49cf86), .polishedMetal),           // emerald
            (Color(hex: 0xd158b4), .lacquer),                 // magenta, under a clear coat
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

        // Two stylized props: a cel-shaded torus and a Gooch-shaded cone. Neither is a
        // metal, so neither mirrors anything itself, but both are *seen* in the mirrors
        // around them, and a traced hit shades a surface in the finish it wears. The torus
        // keeps its hard cel bands in the floor, and the cone its warm-to-cool ramp,
        // instead of flattening into the plain diffuse body underneath.
        withState {
            material(.toon)
            fill(Color(hex: 0xff8a3d))
            translate(cos(0.5) * 2.2, 0.75, sin(0.5) * 2.2)
            rotateX(.pi / 2.4)
            drawTorus(radius: 0.62, tube: 0.24)
        }
        withState {
            material(.gooch)
            fill(Color(hex: 0xc9ccd6))
            translate(cos(3.9) * 2.2, 0.6, sin(3.9) * 2.2)
            drawCone(radius: 0.62, height: 1.3)
        }

        // A drift of pebbles held in a retained field. The GPU places every copy and
        // decides per copy what the camera can see, and they still mirror in the floor.
        withState {
            material(.metal(roughness: 0.3))
            fill(.white)
            drawMeshField(pebbles)
        }

        // The satin row, standing out among the pebbles: one finish per ball, mirror on
        // the left to nearly matte on the right. The ends make the glossy rule visible.
        // The left ball looks the same with or without the spread, because its lobe is a
        // single direction already; the right one is so wide that the environment is the
        // honest answer and Ollin hands back to it.
        let roughness = [0.02, 0.14, 0.28, 0.44, 0.62]
        for (i, r) in roughness.enumerated() {
            withState {
                material(.metal(roughness: r))
                fill(Color(hex: 0xcfd4dc))
                translate(-3.6 + Double(i) * 1.8, 0.85, 7.4)
                drawSphere(radius: 0.85)
            }
        }

        drawCaption(isKeyDown(" ")
            ? "Ray-traced reflections: OFF (release space to compare)"
            : "Ray-traced reflections: ON (space: off, G: mirror-ray only)")
    }
}
