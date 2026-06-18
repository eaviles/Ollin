import CoreGraphics
import Ollin
import Testing

/// Render-correctness snapshot tests: each renders a small, deterministic sketch
/// off-screen and checks it against a committed reference image. They exercise
/// both render pipelines (the instanced SDF path and the tessellated-triangle
/// path) and the front-to-back batch ordering between them.
///
/// Serialized because they share the GPU and the reference directory; gated on a
/// Metal device so they skip on a GPU-less machine instead of failing.
@Suite(.serialized)
@MainActor
struct SnapshotTests {

    @Test(.enabled(if: Snapshot.hasMetal))
    func solidShapesMatchReference() throws {
        let diff = try Snapshot.meanDifference(of: SolidShapes(), against: "solid-shapes")
        #expect(diff < Snapshot.tolerance, "mean per-channel difference \(diff)")
    }

    @Test(.enabled(if: Snapshot.hasMetal))
    func mixedPipelinesMatchReference() throws {
        let diff = try Snapshot.meanDifference(of: MixedPipelines(), against: "mixed-pipelines")
        #expect(diff < Snapshot.tolerance, "mean per-channel difference \(diff)")
    }

    @Test(.enabled(if: Snapshot.hasMetal))
    func easedValuesMatchReference() throws {
        // Rendered mid-tween (frame 30), so the per-frame auto-advance has run and
        // the three curves have pulled the dots to different positions.
        let diff = try Snapshot.meanDifference(of: EasedDots(), against: "eased-dots", frame: 30)
        #expect(diff < Snapshot.tolerance, "mean per-channel difference \(diff)")
    }

    @Test(.enabled(if: Snapshot.hasMetal))
    func strokeAlignmentMatchesReference() throws {
        let diff = try Snapshot.meanDifference(of: StrokeAligned(), against: "stroke-aligned")
        #expect(diff < Snapshot.tolerance, "mean per-channel difference \(diff)")
    }

    @Test(.enabled(if: Snapshot.hasMetal))
    func threePointShapesMatchReference() throws {
        let diff = try Snapshot.meanDifference(of: ThreePointShapes(), against: "three-point-shapes")
        #expect(diff < Snapshot.tolerance, "mean per-channel difference \(diff)")
    }

    @Test(.enabled(if: Snapshot.hasMetal))
    func orientedBoxesMatchReference() throws {
        let diff = try Snapshot.meanDifference(of: OrientedBoxes(), against: "oriented-boxes")
        #expect(diff < Snapshot.tolerance, "mean per-channel difference \(diff)")
    }

    @Test(.enabled(if: Snapshot.hasMetal))
    func orientedVesicasMatchReference() throws {
        let diff = try Snapshot.meanDifference(of: OrientedVesicas(), against: "oriented-vesicas")
        #expect(diff < Snapshot.tolerance, "mean per-channel difference \(diff)")
    }

    @Test(.enabled(if: Snapshot.hasMetal))
    func curvedPathsMatchReference() throws {
        let diff = try Snapshot.meanDifference(of: CurvedPaths(), against: "curved-paths")
        #expect(diff < Snapshot.tolerance, "mean per-channel difference \(diff)")
    }

    @Test(.enabled(if: Snapshot.hasMetal))
    func strokeJoinsAndCapsMatchReference() throws {
        let diff = try Snapshot.meanDifference(of: StrokeJoinsCaps(), against: "stroke-joins-caps")
        #expect(diff < Snapshot.tolerance, "mean per-channel difference \(diff)")
    }

    @Test(.enabled(if: Snapshot.hasMetal))
    func bitmapTextMatchesReference() throws {
        let diff = try Snapshot.meanDifference(of: TextSpecimen(), against: "bitmap-text")
        #expect(diff < Snapshot.tolerance, "mean per-channel difference \(diff)")
    }

    @Test(.enabled(if: Snapshot.hasMetal))
    func tintedImageMatchesReference() throws {
        let diff = try Snapshot.meanDifference(of: TintedImage(), against: "tinted-image")
        #expect(diff < Snapshot.tolerance, "mean per-channel difference \(diff)")
    }

    @Test(.enabled(if: Snapshot.hasMetal))
    func gradientPaintsMatchReference() throws {
        let diff = try Snapshot.meanDifference(of: GradientShapes(), against: "gradient-shapes")
        #expect(diff < Snapshot.tolerance, "mean per-channel difference \(diff)")
    }

    @Test(.enabled(if: Snapshot.hasMetal))
    func statusAndCaptionMatchReference() throws {
        let diff = try Snapshot.meanDifference(of: StatusNotices(), against: "status-notices")
        #expect(diff < Snapshot.tolerance, "mean per-channel difference \(diff)")
    }

    @Test(.enabled(if: Snapshot.hasMetal))
    func additiveBlendMatchesReference() throws {
        let diff = try Snapshot.meanDifference(of: AdditiveBlend(), against: "additive-blend")
        #expect(diff < Snapshot.tolerance, "mean per-channel difference \(diff)")
    }

    @Test(.enabled(if: Snapshot.hasMetal))
    func accumulationMatchesReference() throws {
        // Captured at frame 12, so the reference can only match if the canvas
        // accumulated across the prior frames (a single frame is a sparse scatter).
        let diff = try Snapshot.meanDifference(of: AccumulationField(), against: "accumulation", frame: 12)
        #expect(diff < Snapshot.tolerance, "mean per-channel difference \(diff)")
    }

    @Test(.enabled(if: Snapshot.hasMetal))
    func toneMappedBloomMatchesReference() throws {
        // Additive light pushes the overlaps well past 1.0; `.aces` rolls them off
        // instead of clipping. Pins the float intermediate + the present pass's
        // tone-map (a `.clamp` render would flatten the cores to white).
        let diff = try Snapshot.meanDifference(of: ToneMappedBloom(), against: "tone-mapped-bloom")
        #expect(diff < Snapshot.tolerance, "mean per-channel difference \(diff)")
    }

    @Test(.enabled(if: Snapshot.hasMetal))
    func pointCloud3DMatchesReference() throws {
        // A static 3D heightfield through a fixed camera — pins the 3D camera, the
        // depth-tested point pipeline, and the instanced disc splats.
        let diff = try Snapshot.meanDifference(of: PointCloud3DScene(), against: "point-cloud-3d")
        #expect(diff < Snapshot.tolerance, "mean per-channel difference \(diff)")
    }

    @Test(.enabled(if: Snapshot.hasMetal))
    func solidPrimitives3DMatchesReference() throws {
        // The five solid primitives through a fixed camera — pins the depth-tested
        // mesh pipeline, the auto-lit default material (each fill shaded by the
        // default rig), and the model-matrix + normal baking (each shape is
        // placed/rotated by the 3D transform stack).
        let diff = try Snapshot.meanDifference(of: SolidPrimitives3DScene(), against: "solid-primitives-3d")
        #expect(diff < Snapshot.tolerance, "mean per-channel difference \(diff)")
    }

    @Test(.enabled(if: Snapshot.hasMetal))
    func meshLightingMatchesReference() throws {
        // Custom lighting on solids — pins the directional/point/spot light kinds,
        // ambient, the spot cone, and the specular highlight (the Blinn-Phong material
        // the auto-lit default scene doesn't exercise).
        let diff = try Snapshot.meanDifference(of: MeshLightingScene(), against: "mesh-lighting")
        #expect(diff < Snapshot.tolerance, "mean per-channel difference \(diff)")
    }

    @Test(.enabled(if: Snapshot.hasMetal))
    func texturedMeshMatchesReference() throws {
        // A UV-gridded sphere through a fixed camera — pins the textured-mesh pipeline:
        // UVs on the sphere generator, the base-color texture sampled per fragment, and
        // the shared Blinn-Phong tail (textured surface, auto-lit default rig).
        let diff = try Snapshot.meanDifference(of: TexturedMesh3DScene(), against: "textured-mesh")
        #expect(diff < Snapshot.tolerance, "mean per-channel difference \(diff)")
    }

    @Test(.enabled(if: Snapshot.hasMetal))
    func wireframeMeshMatchesReference() throws {
        // A wireframe icosphere through a fixed camera — pins the wireframe mesh pipeline:
        // barycentric edge-shading from vid%3, the stroke-colored edges, and the line
        // width from strokeWeight, with the faces see-through.
        let diff = try Snapshot.meanDifference(of: WireframeMesh3DScene(), against: "mesh-wireframe")
        #expect(diff < Snapshot.tolerance, "mean per-channel difference \(diff)")
    }

    @Test(.enabled(if: Snapshot.hasMetal))
    func meshShadowsMatchesReference() throws {
        // A box and a sphere above a floor, lit by a directional key with castShadows()
        // on — pins the shadow pass (the depth render from the light) and the shadow
        // sample in the lit fragment (the cast shadows on the floor and between solids).
        let diff = try Snapshot.meanDifference(of: MeshShadowsScene(), against: "mesh-shadows")
        #expect(diff < Snapshot.tolerance, "mean per-channel difference \(diff)")
    }

    @Test(.enabled(if: Snapshot.hasMetal))
    func spotShadowsMatchesReference() throws {
        // A box and a sphere above a floor under a spot light (no directional, so the
        // spot is the caster) with castShadows() on — pins the spot path: a perspective
        // shadow map fit to the cone, sampled by the same shadowFactor as the
        // directional map, dropping shadows inside the lit pool.
        let diff = try Snapshot.meanDifference(of: SpotShadowsScene(), against: "spot-shadows")
        #expect(diff < Snapshot.tolerance, "mean per-channel difference \(diff)")
    }

    @Test(.enabled(if: Snapshot.hasMetal))
    func lightingPresetMatchesReference() throws {
        // A still life lit by the .goldenHour LightingPreset — pins the preset path
        // (ambient + warm/cool directionals, the light colors from Color(kelvin:))
        // through the lit-mesh pipeline.
        let diff = try Snapshot.meanDifference(of: LightingPresetScene(), against: "lighting-presets")
        #expect(diff < Snapshot.tolerance, "mean per-channel difference \(diff)")
    }

    @Test(.enabled(if: Snapshot.hasMetal))
    func meshMaterialsMatchReference() throws {
        // A row of spheres in the stylized materials — pins the per-batch OllinMaterial
        // uniform and each new shader branch: a Fresnel iridescent sheen, the rim glow
        // (velvet), fake subsurface (jade), toon cel bands, and Gooch warm–cool. No `time`.
        let diff = try Snapshot.meanDifference(of: MeshMaterialsScene(), against: "mesh-materials")
        #expect(diff < Snapshot.tolerance, "mean per-channel difference \(diff)")
    }

    @Test(.enabled(if: Snapshot.hasMetal))
    func matcapMeshMatchesReference() throws {
        // Three spheres wearing built-in matcaps (chrome/clay/toon) — pins the matcap
        // pipeline: the view-space normal sampled into the sphere texture, bypassing the
        // scene lights and material model, tinted by fill(.white). No `time`.
        let diff = try Snapshot.meanDifference(of: MatcapMeshScene(), against: "matcap-mesh")
        #expect(diff < Snapshot.tolerance, "mean per-channel difference \(diff)")
    }

    @Test(.enabled(if: Snapshot.hasMetal))
    func transformed3DMatchesReference() throws {
        // Point-cloud blobs placed entirely by the 3D transform stack — a center blob
        // plus four satellites positioned by rotateY + translate and sized by scale.
        // Pins the model-matrix bake (translate/rotate/scale composing) into the point
        // pipeline; if the stack were ignored every blob would pile at the origin.
        // Seeded, no `time`.
        let diff = try Snapshot.meanDifference(of: Transformed3DScene(), against: "transformed-3d")
        #expect(diff < Snapshot.tolerance, "mean per-channel difference \(diff)")
    }

    @Test(.enabled(if: Snapshot.hasMetal))
    func voronoiCellsMatchReference() throws {
        // A Lloyd-relaxed Voronoi diagram — pins the Bowyer–Watson triangulation,
        // the bisector cell clipping, and the relaxation. Seeded, no `time`.
        let diff = try Snapshot.meanDifference(of: VoronoiCells(), against: "voronoi-cells")
        #expect(diff < Snapshot.tolerance, "mean per-channel difference \(diff)")
    }

    @Test(.enabled(if: Snapshot.hasMetal))
    func depthCompositing2DMatchesReference() throws {
        // A 2D card standing at a world depth between two point-cloud balls — pins
        // depth-aware compositing: the near ball draws over the card, the far ball
        // is hidden by it. If 2D ignored depth (always over), the card would cover
        // both, so this fails if the depth-participation path breaks. No `time`.
        let diff = try Snapshot.meanDifference(of: DepthComposited2D(), against: "depth-compositing-2d")
        #expect(diff < Snapshot.tolerance, "mean per-channel difference \(diff)")
    }

    @Test(.enabled(if: Snapshot.hasMetal))
    func depthSceneMatchesReference() throws {
        // A depth-map scene (a near left half, a far right half) with a 2D bar at
        // mid-depth — pins drawDepthScene + the normalized depth(_:): the bar is
        // hidden on the near half and drawn over the backdrop on the far half. Pins
        // the depth-scene pre-pass writing per-pixel SV_Depth. Synthetic, no `time`.
        let diff = try Snapshot.meanDifference(of: DepthSceneScene(), against: "depth-scene")
        #expect(diff < Snapshot.tolerance, "mean per-channel difference \(diff)")
    }

    @Test(.enabled(if: Snapshot.hasMetal))
    func metricDepthSceneMatchesReference() throws {
        // The same near-left / far-right split, but the depth is real meters and the
        // camera is built from the frame's intrinsics, so the bar sits at a true
        // 1.5 m depth — hidden over the near (0.5 m) half, drawn over the far (3 m)
        // half. Pins Camera3D.fromIntrinsics + the metric drawDepthScene(RGBDFrame)
        // float-depth path + depth(at: Vector3). Synthetic, no `time`.
        let diff = try Snapshot.meanDifference(of: MetricDepthSceneScene(), against: "metric-depth-scene")
        #expect(diff < Snapshot.tolerance, "mean per-channel difference \(diff)")
    }
}

// MARK: - Fixtures

/// A static 3D heightfield drawn as a point cloud from a fixed camera — exercises
/// the 3D camera, the depth-tested point pipeline, and the instanced disc splats.
/// No `time`, so it's deterministic at any frame.
private final class PointCloud3DScene: Sketch {
    override var canvasSize: CanvasSize { .square(256) }

    override func draw() {
        background(Color(white: 0.04))
        camera(.orbiting(target: Vector3(0, -0.1, 0), radius: 5,
                         azimuth: 0.6, elevation: 0.5, fieldOfView: .pi / 3.4))
        let n = 64, span = 3.0
        var cloud = PointCloud()
        let step = span / Double(n - 1)
        for i in 0..<n {
            let x = -span / 2 + Double(i) * step
            for j in 0..<n {
                let z = -span / 2 + Double(j) * step
                let rr = (x * x + z * z).squareRoot()
                let h = sin(rr * 3.0) * 0.34 * exp(-rr * 0.35)
                let t = max(0, min(1, h + 0.5))
                cloud.add(Vector3(x, h, z),
                          color: Color(hue: 0.62 - t * 0.52, saturation: 0.85, brightness: 0.42 + t * 0.58),
                          size: 0.07)
            }
        }
        drawPointCloud(cloud)
    }
}

/// The five solid primitives through a fixed camera, each placed and rotated by the
/// 3D transform stack — exercises the depth-tested mesh pipeline, the auto-lit default
/// material (no lights set, so the default rig shades each fill), and the model-matrix
/// + normal-matrix baking. No `time`, so deterministic.
private final class SolidPrimitives3DScene: Sketch {
    override var canvasSize: CanvasSize { .square(256) }

    override func draw() {
        background(Color(white: 0.04))
        camera(.orbiting(target: .zero, radius: 6,
                         azimuth: 0.5, elevation: 0.4, fieldOfView: .pi / 3.4))
        withState { fill(Color(hue: 0.0, saturation: 0.6, brightness: 0.9)); translate(-2.2, 0, 0); rotateY(0.6); rotateX(0.3); drawBox(size: 1.4) }
        withState { fill(Color(hue: 0.3, saturation: 0.6, brightness: 0.9)); drawSphere(radius: 0.85) }
        withState { fill(Color(hue: 0.55, saturation: 0.6, brightness: 0.9)); translate(2.2, 0, 0); rotateZ(0.4); drawCylinder(radius: 0.6, height: 1.5) }
        withState { fill(Color(hue: 0.75, saturation: 0.6, brightness: 0.9)); translate(-1.1, 0, 2.0); rotateX(0.5); drawTorus(radius: 0.6, tube: 0.26) }
        withState { fill(Color(hue: 0.12, saturation: 0.6, brightness: 0.9)); translate(1.1, -0.9, 2.0); drawPlane(width: 1.8, depth: 1.8) }
    }
}

/// Custom lighting on solids: ambient + a directional key + a point light + a spot,
/// with a specular material — pins the three light kinds, the spot cone, ambient, and
/// the specular highlight (the parts the auto-lit default doesn't exercise). No `time`.
private final class MeshLightingScene: Sketch {
    override var canvasSize: CanvasSize { .square(256) }

    override func draw() {
        background(Color(white: 0.03))
        camera(.orbiting(target: .zero, radius: 6.5,
                         azimuth: 0.4, elevation: 0.35, fieldOfView: .pi / 3.4))
        ambientLight(Color(white: 0.1))
        directionalLight(Color(hue: 0.09, saturation: 0.3, brightness: 1), direction: Vector3(-0.5, -0.8, -0.4), intensity: 0.7)
        pointLight(Color(hue: 0.5, saturation: 0.8, brightness: 1), at: Vector3(3, 2.5, 2.5), intensity: 1.2)
        spotLight(Color(hue: 0.85, saturation: 0.7, brightness: 1), at: Vector3(-2, 4, 1),
                  direction: Vector3(0.4, -1, -0.2), angle: .pi / 4, penumbra: 0.5, intensity: 1.6)
        withState {
            fill(Color(white: 0.85)); specular(0.7); shininess(80)
            translate(-1.6, 0, 0); drawSphere(radius: 1.0)
        }
        withState {
            fill(Color(hue: 0.05, saturation: 0.5, brightness: 0.9)); specular(0.4); shininess(40)
            translate(1.6, 0, 0); rotateY(0.5); rotateX(0.3); drawBox(size: 1.5)
        }
        withState { fill(Color(white: 0.4)); translate(0, -1.4, 0); drawPlane(width: 6, depth: 6) }
    }
}

/// A UV-gridded sphere through a fixed camera, lit by the default rig — pins the
/// textured-mesh pipeline (sphere UVs, the per-fragment base-color texture sample, the
/// shared lit tail). The texture is built from a pure function of pixel coordinates, so
/// the scene is deterministic. No `time`.
private final class TexturedMesh3DScene: Sketch {
    override var canvasSize: CanvasSize { .square(256) }
    private lazy var globe = Mesh.sphere(radius: 1.5, segments: 48, rings: 24)
        .textured(TexturedMesh3DScene.grid)

    override func draw() {
        background(Color(white: 0.05))
        camera(.orbiting(target: .zero, radius: 5,
                         azimuth: 0.6, elevation: 0.3, fieldOfView: .pi / 3.4))
        drawMesh(globe)
    }

    /// A deterministic UV grid: hue by u, a brightness checker, dark gridlines.
    static let grid: Image = {
        let n = 64, cell = 4
        let img = Image(width: n, height: n)
        for y in 0..<n {
            for x in 0..<n {
                if x % cell == 0 || y % cell == 0 {
                    img[x, y] = Color(white: 0.12)
                } else {
                    let checker = ((x / cell) + (y / cell)) % 2 == 0
                    img[x, y] = Color(hue: Double(x) / Double(n - 1),
                                      saturation: 0.7, brightness: checker ? 0.95 : 0.55)
                }
            }
        }
        return img
    }()
}

/// A box and a sphere above a floor, lit by a directional key with `castShadows()` on,
/// through a fixed camera — pins the shadow pass (the depth render from the light) and
/// the shadow sample in the lit mesh fragment (the cast shadows on the floor and the
/// sphere's shadow reaching toward the box). No `time`, so it's deterministic.
private final class MeshShadowsScene: Sketch {
    override var canvasSize: CanvasSize { .square(256) }

    override func draw() {
        background(Color(white: 0.05))
        camera(.orbiting(target: Vector3(0, 0.6, 0), radius: 7,
                         azimuth: 0.5, elevation: 0.45, fieldOfView: .pi / 3.6))
        ambientLight(Color(white: 0.15))
        directionalLight(.white, direction: Vector3(-0.5, -0.85, -0.35), intensity: 1.0)
        castShadows()
        withState { fill(Color(white: 0.8)); specular(0.05); drawPlane(width: 10, depth: 10) }
        withState {
            fill(Color(hue: 0.03, saturation: 0.6, brightness: 0.95)); specular(0.3); shininess(40)
            translate(-1.1, 1.0, 0); rotateY(0.5); drawBox(size: 1.6)
        }
        withState {
            fill(Color(hue: 0.55, saturation: 0.55, brightness: 0.95)); specular(0.3); shininess(40)
            translate(1.3, 1.3, 0.3); drawSphere(radius: 1.1)
        }
    }
}

/// A box and a sphere above a floor under a single spot light with `castShadows()` on,
/// through a fixed camera — pins the spot caster (a perspective shadow map fit to the
/// cone). The scene has no directional light, so the spot is the chosen caster; the
/// solids drop shadows inside its lit pool and the rest falls to ambient + a point
/// fill. No `time`, so it's deterministic.
private final class SpotShadowsScene: Sketch {
    override var canvasSize: CanvasSize { .square(256) }

    override func draw() {
        background(Color(white: 0.04))
        camera(.orbiting(target: Vector3(0, 0.6, 0), radius: 7,
                         azimuth: 0.5, elevation: 0.5, fieldOfView: .pi / 3.6))
        ambientLight(Color(white: 0.12))
        pointLight(Color(white: 0.4), at: Vector3(-4, 3, 4), intensity: 0.4)
        spotLight(.white, at: Vector3(-1.5, 6, 3),
                  direction: (Vector3(0, 0.6, 0) - Vector3(-1.5, 6, 3)).normalized,
                  angle: .pi / 4, penumbra: 0.4, intensity: 1.3)
        castShadows()
        withState { fill(Color(white: 0.82)); specular(0.05); drawPlane(width: 10, depth: 10) }
        withState {
            fill(Color(hue: 0.03, saturation: 0.6, brightness: 0.95)); specular(0.3); shininess(40)
            translate(-1.1, 1.0, 0); rotateY(0.5); drawBox(size: 1.6)
        }
        withState {
            fill(Color(hue: 0.55, saturation: 0.55, brightness: 0.95)); specular(0.3); shininess(40)
            translate(1.3, 1.1, 0.3); drawSphere(radius: 1.1)
        }
    }
}

/// The same still life lit by the `.goldenHour` `LightingPreset` through a fixed
/// camera — pins the preset path (one call setting the ambient + a warm low
/// directional + a cool sky fill, the lights' colors from `Color(kelvin:)`) feeding
/// the same lit-mesh pipeline. If the preset's lights or the kelvin math regressed,
/// the warm/cool balance would shift. No `time`, so it's deterministic.
private final class LightingPresetScene: Sketch {
    override var canvasSize: CanvasSize { .square(256) }

    override func draw() {
        background(Color(white: 0.04))
        camera(.orbiting(target: Vector3(0, -0.1, 0), radius: 6.5,
                         azimuth: 0.4, elevation: 0.32, fieldOfView: .pi / 3.4))
        lightingPreset(.goldenHour)
        withState { translate(0, -1.2, 0); fill(Color(white: 0.55)); specular(0.05); drawPlane(width: 12, depth: 12) }
        withState {
            fill(Color(white: 0.85)); specular(0.6); shininess(100)
            translate(-1.6, -0.3, 0); drawSphere(radius: 1.0)
        }
        withState {
            fill(Color(hue: 0.04, saturation: 0.5, brightness: 0.9)); specular(0.4); shininess(48)
            translate(1.4, -0.1, -0.2); rotateY(0.5); rotateX(0.3); drawBox(size: 1.4)
        }
    }
}

/// A wireframe icosphere through a fixed camera, stroke-colored — pins the wireframe
/// mesh pipeline (barycentric edges from vid%3, the stroke edge color, the line width
/// from strokeWeight). The faces are see-through, so the back edges show through. No
/// `time`.
private final class WireframeMesh3DScene: Sketch {
    override var canvasSize: CanvasSize { .square(256) }

    override func draw() {
        background(Color(white: 0.04))
        camera(.orbiting(target: .zero, radius: 4,
                         azimuth: 0.5, elevation: 0.4, fieldOfView: .pi / 3.4))
        wireframe()
        strokeWeight(1.5)
        stroke(Color(hue: 0.55, saturation: 0.6, brightness: 1))
        withState { rotateY(0.6); rotateX(0.3); drawMesh(.icosphere(radius: 1.4, subdivisions: 2)) }
    }
}

/// A row of spheres in the stylized materials under a fixed camera and custom lights —
/// pins the per-batch material uniform and the new shader branches (iridescence, rim,
/// subsurface, toon, Gooch). No `time`, so it's deterministic.
private final class MeshMaterialsScene: Sketch {
    override var canvasSize: CanvasSize { .square(256) }

    override func draw() {
        background(Color(white: 0.05))
        camera(.orbiting(target: .zero, radius: 7,
                         azimuth: 0.35, elevation: 0.28, fieldOfView: .pi / 3.2))
        ambientLight(Color(white: 0.14))
        directionalLight(Color(kelvin: 5600), direction: Vector3(-0.4, -0.6, -0.5), intensity: 0.8)
        pointLight(.white, at: Vector3(3, 4, 4), intensity: 1.0)
        let mats: [(Material, Color)] = [
            (.iridescent, Color(white: 0.18)),
            (.velvet,     Color(hue: 0.93, saturation: 0.6, brightness: 0.4)),
            (.jade,       Color(hue: 0.42, saturation: 0.55, brightness: 0.55)),
            (.toon,       Color(hue: 0.07, saturation: 0.8, brightness: 0.95)),
            (.gooch,      Color(white: 0.55)),
        ]
        for (i, m) in mats.enumerated() {
            withState {
                translate(-3.2 + Double(i) * 1.6, 0, 0)
                fill(m.1)
                material(m.0)
                drawSphere(radius: 0.7)
            }
        }
    }
}

/// Three spheres each wearing a built-in matcap (chrome, clay, toon) under a fixed
/// camera — pins the matcap pipeline: the view-space normal → sphere-texture lookup,
/// independent of the scene lights, tinted by fill(.white). No `time`, so deterministic.
private final class MatcapMeshScene: Sketch {
    override var canvasSize: CanvasSize { .square(256) }

    override func draw() {
        background(Color(white: 0.05))
        camera(.orbiting(target: .zero, radius: 5,
                         azimuth: 0.3, elevation: 0.25, fieldOfView: .pi / 3.2))
        fill(.white)
        let caps: [Matcap] = [.chrome, .clay, .toon]
        for (i, cap) in caps.enumerated() {
            withState {
                translate(-2.0 + Double(i) * 2.0, 0, 0)
                matcap(cap)
                drawSphere(radius: 0.8)
            }
        }
    }
}

/// Point-cloud blobs placed entirely by the 3D transform stack: a central blob and
/// four satellites positioned with `rotateY` + `translate` and sized with `scale`,
/// under a fixed camera. Exercises the model matrix baking into the point pipeline.
/// Seeded and `time`-free, so it's deterministic.
private final class Transformed3DScene: Sketch {
    override var canvasSize: CanvasSize { .square(256) }

    override func draw() {
        background(Color(white: 0.04))
        seed(3)
        camera(.orbiting(target: .zero, radius: 6.5, azimuth: 0.5, elevation: 0.4,
                         fieldOfView: .pi / 3.2))
        let center = makeBlob(count: 1400, dot: 0.06,
                              color: Color(hue: 0.09, saturation: 0.85, brightness: 1))
        let satellite = makeBlob(count: 900, dot: 0.09,
                                 color: Color(hue: 0.58, saturation: 0.7, brightness: 0.95))

        withState {
            scale(Vector3(0.9, 0.9, 0.9))
            drawPointCloud(center)
        }
        for i in 0..<4 {
            withState {
                rotateY(Double(i) * .pi / 2 + 0.3)
                translate(2.6, 0, 0)
                scale(Vector3(0.4, 0.4, 0.4))
                drawPointCloud(satellite)
            }
        }
    }

    private func makeBlob(count: Int, dot: Double, color: Color) -> PointCloud {
        var cloud = PointCloud()
        for _ in 0..<count {
            let dir = Vector3(randomGaussian(), randomGaussian(), randomGaussian()).normalized
            cloud.add(dir * (0.9 + random(0.2)), color: color, size: dot)
        }
        return cloud
    }
}

/// A Lloyd-relaxed Voronoi diagram of seeded sites, each cell filled from a
/// colormap and outlined — exercises the Bowyer–Watson triangulation, the
/// bisector cell clipping (incl. the boundary cells clamped to the canvas), and
/// the relaxation. Seeded and `time`-free, so it's deterministic.
private final class VoronoiCells: Sketch {
    override var canvasSize: CanvasSize { .square(256) }

    override func draw() {
        background(Color(white: 0.1))
        seed(11)
        let scattered = (0..<40).map { _ in randomVector(in: canvasRectangle) }
        let sites = lloyd(scattered, iterations: 4)
        let cells = voronoi(sites).cells
        stroke(Color(white: 0.1)); strokeWeight(1.5)
        for (i, cell) in cells.enumerated() {
            fill(Colormap.viridis.color(at: Double(i) / Double(max(cells.count - 1, 1))))
            drawShape(cell)
        }
    }
}

/// A 2D card placed at a world depth between two point-cloud balls — exercises
/// depth-aware compositing (`withBillboard`/`depth(at:)`): the near ball composites
/// over the card, the far ball is hidden by it. The camera looks down −z from +z,
/// so the +z ball is in front of the origin (over the card) and the −z ball behind
/// it (occluded). No `time`, deterministic blob.
private final class DepthComposited2D: Sketch {
    override var canvasSize: CanvasSize { .square(256) }

    // A small fixed cloud of offsets (deterministic hash), so the balls hold still.
    private let blob: [Vector3] = {
        func h(_ n: Int) -> Double {
            let x = sin(Double(n) * 12.9898) * 43758.5453
            return (x - floor(x)) * 2 - 1
        }
        return (0..<120).map { i in
            Vector3(h(i * 4), h(i * 4 + 1), h(i * 4 + 2)) * (abs(h(i * 4 + 3)) * 0.22 + 0.05)
        }
    }()

    override func draw() {
        background(Color(white: 0.04))
        camera(.perspective(eye: Vector3(0, 0, 4.2), target: .zero, fieldOfView: .pi / 3))
        var cloud = PointCloud()
        for off in blob {
            cloud.add(Vector3(-0.85, 0, 1.25) + off, color: Color(hue: 0.5, saturation: 0.7, brightness: 1.0), size: 0.07)
            cloud.add(Vector3(0.85, 0, -1.25) + off, color: Color(hue: 0.07, saturation: 0.8, brightness: 1.0), size: 0.07)
        }
        drawPointCloud(cloud)
        withBillboard(at: .zero) {
            noStroke()
            fill(Color(white: 0.95))
            drawRect(center: .zero, width: 150, height: 92, cornerRadius: 12)
        }
    }
}

/// A depth-map scene with a 2D bar at mid-depth — exercises `drawDepthScene` (the
/// pre-pass that writes per-pixel SV_Depth from a depth map) and the normalized
/// `depth(_:)`. The depth map's left half is near (white), the right half far
/// (black); a white bar at depth 0.5 is hidden on the near half and drawn over the
/// backdrop on the far half. Synthetic Images, no `time`, so it's deterministic.
private final class DepthSceneScene: Sketch {
    override var canvasSize: CanvasSize { .square(256) }
    private let n = 64
    private lazy var backdrop = makeBackdrop()
    private lazy var depthMap = makeDepthMap()

    private func makeBackdrop() -> Image {
        var px = [UInt8](repeating: 255, count: n * n * 4)
        for y in 0..<n {
            for x in 0..<n {
                let t = Double(x) / Double(n - 1)
                let i = (y * n + x) * 4
                px[i] = UInt8(40 + t * 200); px[i + 1] = 60; px[i + 2] = UInt8(220 - t * 180)
            }
        }
        return Image(width: n, height: n, premultipliedRGBA: px)!
    }

    private func makeDepthMap() -> Image {
        var px = [UInt8](repeating: 255, count: n * n * 4)
        for y in 0..<n {
            for x in 0..<n {
                let v: UInt8 = x < n / 2 ? 255 : 0   // left near (white), right far (black)
                let i = (y * n + x) * 4
                px[i] = v; px[i + 1] = v; px[i + 2] = v
            }
        }
        return Image(width: n, height: n, premultipliedRGBA: px)!
    }

    override func draw() {
        background(.black)
        drawDepthScene(color: backdrop, depth: depthMap)
        depth(0.5)
        noStroke()
        fill(.white)
        drawRect(center: Vector2(width / 2, height / 2), width: width * 0.7, height: height * 0.26)
    }
}

/// A *metric* depth scene: the same left-near / right-far split, but the depth is
/// real meters and the camera is built from the frame's intrinsics, so the 2D bar is
/// placed at a true 1.5 m depth. The left half (0.5 m, nearer) hides the bar; the
/// right half (3 m, farther) shows it. Pins `Camera3D.fromIntrinsics`, the metric
/// `drawDepthScene(_ frame:)` float-depth path, and a metric `depth(at: Vector3)`.
private final class MetricDepthSceneScene: Sketch {
    override var canvasSize: CanvasSize { .square(256) }
    private let n = 64
    private lazy var frame = makeFrame()

    private func makeFrame() -> RGBDFrame {
        var px = [UInt8](repeating: 255, count: n * n * 4)
        var depth = [Float](repeating: 0, count: n * n)
        for y in 0..<n {
            for x in 0..<n {
                let t = Double(x) / Double(n - 1)
                let i = (y * n + x) * 4
                px[i] = UInt8(40 + t * 200); px[i + 1] = 60; px[i + 2] = UInt8(220 - t * 180)
                depth[y * n + x] = x < n / 2 ? 0.5 : 3.0   // left near, right far (meters)
            }
        }
        let color = Image(width: n, height: n, premultipliedRGBA: px)!
        let k = CameraIntrinsics(fx: 60, fy: 60, cx: Double(n) / 2, cy: Double(n) / 2,
                                 width: n, height: n)
        return RGBDFrame(color: color, depth: depth, confidence: nil,
                         depthWidth: n, depthHeight: n, intrinsics: k)
    }

    override func draw() {
        background(.black)
        camera(.fromIntrinsics(frame.intrinsics, near: 0.1, far: 10))
        drawDepthScene(frame)
        depth(at: Vector3(0, 0, -1.5))   // a true 1.5 m depth, between the halves
        noStroke()
        fill(.white)
        drawRect(center: Vector2(width / 2, height / 2), width: width * 0.7, height: height * 0.26)
    }
}

/// A few solid SDF fills on white — large flat regions, so anti-aliased edges
/// are a small fraction of the frame. Pure SDF pipeline.
private final class SolidShapes: Sketch {
    override var canvasSize: CanvasSize { .square(256) }

    override func draw() {
        background(.white)
        noStroke()
        fill(.black)
        drawRect(center: Vector2(width / 2, height / 2), width: width * 0.6, height: height * 0.6)
        fill(Color(red: 0.9, green: 0.2, blue: 0.2))
        drawCircle(width * 0.28, height * 0.28, width * 0.16)
        fill(Color(red: 0.2, green: 0.5, blue: 0.95))
        drawRect(corner: Vector2(width * 0.6, height * 0.6), width: width * 0.28, height: height * 0.28)
    }
}

/// A tessellated triangle (the triangle pipeline) with an SDF star drawn over it
/// (the SDF pipeline), so the test covers both paths and that they composite in
/// draw order.
private final class MixedPipelines: Sketch {
    override var canvasSize: CanvasSize { .square(256) }

    override func draw() {
        background(Color(white: 0.1))
        noStroke()
        fill(Color(red: 0.2, green: 0.6, blue: 0.9))
        drawPolygon([Vector2(40, 40), Vector2(220, 70), Vector2(120, 220)])
        fill(Color(red: 1.0, green: 0.85, blue: 0.2))
        drawStar(width * 0.5, height * 0.46, width * 0.22, width * 0.1, points: 5)
    }
}

/// Three `@Eased` values easing toward the same target (set in `setup`) on
/// different curves, so mid-tween the dots sit at different positions. Exercises
/// the sketch's per-frame auto-advance and that each curve shapes motion its own
/// way. Large flat white field, so edge pixels stay a small fraction.
private final class EasedDots: Sketch {
    override var canvasSize: CanvasSize { .square(256) }

    @Eased(duration: 1, curve: .linear)  var a = 0.0
    @Eased(duration: 1, curve: .easeIn)  var b = 0.0
    @Eased(duration: 1, curve: .easeOut) var c = 0.0

    override func setup() { a = 1; b = 1; c = 1 }

    override func draw() {
        background(.white)
        noStroke()
        fill(.black)
        let left = width * 0.18, right = width * 0.82
        for (i, t) in [a, b, c].enumerated() {
            let y = height * (0.3 + Double(i) * 0.2)
            drawCircle(left + (right - left) * t, y, width * 0.06)
        }
    }
}

/// A disk and a region shape (rect) stroked under each `StrokeAlign` — one row
/// per alignment — so the test pins the stroke-band bias on both coverage ramps
/// (`diskCoverage` and `regionCoverage`). Static, so it's deterministic at frame 0.
private final class StrokeAligned: Sketch {
    override var canvasSize: CanvasSize { .square(256) }

    override func draw() {
        background(.white)
        fill(Color(white: 0.6))
        stroke(.black)
        strokeWeight(12)
        let aligns: [StrokeAlign] = [.inside, .center, .outside]
        for (i, align) in aligns.enumerated() {
            strokeAlign(align)
            let y = height * (0.22 + Double(i) * 0.28)
            drawCircle(width * 0.3, y, width * 0.09)
            drawRect(center: Vector2(width * 0.7, y), width: width * 0.18, height: width * 0.18)
        }
    }
}

/// The two three-point shapes that drove the `SDFInstance` widening (the `param2`
/// slot): a general scalene `drawTriangle(a, b, c)` — filled+stroked, then drawn
/// hollow (it honors both) — and a quadratic `drawBezier` stroke, plus a Bézier
/// with collinear control points that exercises the straight-line fallback.
/// Static, so it's deterministic at frame 0.
private final class ThreePointShapes: Sketch {
    override var canvasSize: CanvasSize { .square(256) }

    override func draw() {
        background(.white)
        // Filled + stroked scalene triangle (top-left).
        fill(Color(red: 0.2, green: 0.6, blue: 0.9))
        stroke(.black); strokeWeight(6)
        drawTriangle(Vector2(30, 95), Vector2(115, 35), Vector2(90, 135))
        // Hollow triangle — a constant-width band (top-right).
        noStroke(); fill(Color(red: 0.9, green: 0.4, blue: 0.2))
        hollow(10)
        drawTriangle(Vector2(145, 45), Vector2(228, 75), Vector2(165, 125))
        solid()
        // Quadratic Bézier curve (a smile across the middle).
        stroke(Color(red: 0.1, green: 0.5, blue: 0.2)); strokeWeight(10)
        drawBezier(Vector2(25, 205), Vector2(128, 145), Vector2(231, 205))
        // Collinear control points → the straight-line fallback (bottom).
        stroke(.black); strokeWeight(6)
        drawBezier(Vector2(25, 240), Vector2(128, 240), Vector2(231, 240))
    }
}

/// `drawOrientedBox` — a box placed by its two centerline endpoints plus a
/// thickness. Exercises the region features it inherits: a filled + stroked bar
/// (diagonal), a hollow bar (a constant-width band, top), and an outside-aligned
/// stroke (bottom). Static, so it's deterministic at frame 0.
private final class OrientedBoxes: Sketch {
    override var canvasSize: CanvasSize { .square(256) }

    override func draw() {
        background(.white)
        // Filled + stroked diagonal bar.
        fill(Color(red: 0.2, green: 0.6, blue: 0.9))
        stroke(.black); strokeWeight(6)
        drawOrientedBox(Vector2(40, 60), Vector2(216, 130), thickness: 34)
        // Hollow bar — a constant-width band hugging the outline (top).
        noStroke(); fill(Color(red: 0.9, green: 0.4, blue: 0.2))
        hollow(8)
        drawOrientedBox(Vector2(40, 30), Vector2(216, 30), thickness: 28)
        solid()
        // Outside-aligned stroke — the outline sits fully outside the fill (bottom).
        fill(Color(red: 0.1, green: 0.5, blue: 0.2))
        stroke(.black); strokeWeight(6); strokeAlign(.outside)
        drawOrientedBox(Vector2(50, 210), Vector2(206, 226), thickness: 30)
        strokeAlign(.center)
    }
}

/// `drawOrientedVesica` — a pointed lens placed by its two tip points plus a
/// waist width. Exercises the region features it inherits: a filled + stroked lens
/// (diagonal), a hollow lens (a constant-width band, top), and an outside-aligned
/// stroke (bottom). Static, so it's deterministic at frame 0.
private final class OrientedVesicas: Sketch {
    override var canvasSize: CanvasSize { .square(256) }

    override func draw() {
        background(.white)
        // Filled + stroked diagonal lens.
        fill(Color(red: 0.2, green: 0.6, blue: 0.9))
        stroke(.black); strokeWeight(6)
        drawOrientedVesica(Vector2(40, 70), Vector2(216, 140), width: 70)
        // Hollow lens — a constant-width band hugging the outline (top).
        noStroke(); fill(Color(red: 0.9, green: 0.4, blue: 0.2))
        hollow(8)
        drawOrientedVesica(Vector2(40, 32), Vector2(216, 32), width: 44)
        solid()
        // Outside-aligned stroke — the outline sits fully outside the fill (bottom).
        fill(Color(red: 0.1, green: 0.5, blue: 0.2))
        stroke(.black); strokeWeight(5); strokeAlign(.outside)
        drawOrientedVesica(Vector2(50, 224), Vector2(206, 224), width: 40)
        strokeAlign(.center)
    }
}

/// The `Path` builder and `drawCurve` (sample-to-points curved contours): a
/// closed, filled blob whose outline is a smooth Catmull-Rom `curve` run; an open
/// outline built from an explicit `quadCurve` + `cubicCurve`; and an open
/// `drawCurve` wiggle straight from points. Static, so it's deterministic at
/// frame 0.
private final class CurvedPaths: Sketch {
    override var canvasSize: CanvasSize { .square(256) }

    override func draw() {
        background(.white)
        // Closed filled blob through points (curve = Catmull-Rom) + stroked outline.
        fill(Color(red: 0.2, green: 0.6, blue: 0.9)); stroke(.black); strokeWeight(4)
        drawShape { p in
            p.move(to: Vector2(55, 45))
            p.curve(to: Vector2(150, 55))
            p.curve(to: Vector2(165, 120))
            p.curve(to: Vector2(85, 110))
            p.close()
        }
        // Open outline from an explicit quadratic + cubic Bézier, stroke-only.
        noFill(); stroke(Color(red: 0.9, green: 0.3, blue: 0.2)); strokeWeight(6)
        drawShape { p in
            p.move(to: Vector2(28, 158))
            p.quadCurve(to: Vector2(128, 150), control: Vector2(78, 100))
            p.cubicCurve(to: Vector2(230, 165), control1: Vector2(168, 120), control2: Vector2(188, 205))
        }
        // A smooth open wiggle straight from a list of points.
        stroke(.black); strokeWeight(4)
        drawCurve([Vector2(25, 228), Vector2(80, 200), Vector2(130, 236),
                   Vector2(180, 200), Vector2(232, 230)])
    }
}

/// Each `strokeJoin` on a sharp chevron (top three) and each `strokeCap` on an
/// open segment (bottom three), so the corner and end geometry are exercised on
/// the tessellated stroke path. Static, so it's deterministic at frame 0.
private final class StrokeJoinsCaps: Sketch {
    override var canvasSize: CanvasSize { .square(256) }

    override func draw() {
        background(.white)
        stroke(.black); strokeWeight(22)

        let joins: [StrokeJoin] = [.miter, .bevel, .round]
        for (i, join) in joins.enumerated() {
            let cy = 32.0 + Double(i) * 36
            strokeJoin(join)
            drawPolyline([Vector2(40, cy + 14), Vector2(128, cy - 14), Vector2(216, cy + 14)])
        }

        let caps: [StrokeCap] = [.butt, .round, .square]
        strokeJoin(.miter)
        for (i, cap) in caps.enumerated() {
            let cy = 160.0 + Double(i) * 32
            strokeCap(cap)
            drawPolyline([Vector2(70, cy), Vector2(186, cy)])
        }
    }
}

/// The bitmap-font `drawText` with the bundled Cozette font: capitals, lowercase,
/// digits, the Spanish set (accented vowels, ñ/ü, inverted punctuation), Japanese
/// kana (hiragana + katakana), descenders (`g j p q y`), the alignments, and a
/// rotated line that exercises text on the transform stack. Black on white, static.
private final class TextSpecimen: Sketch {
    override var canvasSize: CanvasSize { .square(256) }

    override func draw() {
        background(.white)
        fill(.black)
        textFont(BitmapFont.builtin)   // the fixture is about Cozette, not the default font
        textAlign(.left, .top)
        textSize(24)
        drawText("¡Hola! Ñ", 14, 12)
        textSize(22)
        drawText("ABCxyz 0123", 14, 42)
        drawText("áéíóú ñ ü ¿?", 14, 70)
        textSize(20)
        drawText("こんにちは", 14, 98)        // hiragana
        drawText("ハロー gjpqy", 14, 126)      // katakana + descenders
        // Centered + rotated, through the transform stack.
        textAlign(.center, .middle)
        drawText("centered", width / 2, 172)
        withState {
            translate(width / 2, 212)
            rotate(0.16)
            drawText("rotated", 0, 0)
        }
    }
}

/// An image authored from scratch (`Image(width:height:)` + pixel `set`), drawn
/// once untinted and once under `tint(_:)`, with a row of `get`-sampled swatches
/// below. Pins the whole image-extras path: the texture upload from edited pixels,
/// the tint multiply, top-left pixel orientation (the black corner marker), and
/// that `get` reads the authored colors regardless of tint. Static at frame 0.
private final class TintedImage: Sketch {
    override var canvasSize: CanvasSize { .square(256) }
    var img: Image?

    override func setup() {
        let n = 16
        let image = Image(width: n, height: n)
        for y in 0..<n {
            for x in 0..<n {
                image[x, y] = (x + y) % 2 == 0
                    ? Color(red: 0.9, green: 0.35, blue: 0.2)
                    : Color(red: 0.2, green: 0.45, blue: 0.9)
            }
        }
        image[0, 0] = .black   // top-left marker — must land at the drawn top-left
        img = image
    }

    override func draw() {
        background(.white)
        guard let img else { return }
        noTint()
        drawImage(img, 18, 18, 100, 100)
        tint(Color(red: 1, green: 0.7, blue: 0.3, alpha: 0.85))
        drawImage(img, 138, 18, 100, 100)
        // get-sampled swatches of the top row, in true (untinted) color.
        noTint()
        noStroke()
        for i in 0..<8 {
            fill(img[i * 2, 0])
            drawRect(18 + Double(i) * 28, 150, 24, 80)
        }
    }
}

/// Gradient paint across both pipelines: linear and radial SDF fills, a conic
/// (along-path) stroke sweeping a circle outline, a per-vertex linear fill on a
/// tessellated polygon, and along-path ramps on a line capsule and a Bézier.
/// Gradients are smooth fields, so the mean-difference metric stays tight.
private final class GradientShapes: Sketch {
    override var canvasSize: CanvasSize { .square(256) }

    override func draw() {
        background(Color(white: 0.1))
        noStroke()
        // Linear fill on the SDF box path.
        fill(.linear(from: Vector2(20, 20), to: Vector2(236, 20),
                     [Color(hex: 0xFF8A3D), Color(hex: 0x2BB3A3)]))
        drawRect(20, 20, 216, 60)
        // Radial fill plus a conic (along-path) stroke on the same circle.
        fill(.radial(center: Vector2(70, 160), radius: 40,
                     [.white, Color(hex: 0xD03060)]))
        stroke(.alongPath([Color(hex: 0xFFF3C4), Color(hex: 0x3C6DD0)]))
        strokeWeight(6)
        drawCircle(70, 160, 40)
        noStroke()
        // Per-vertex linear fill on the tessellated path.
        fill(.linear(from: Vector2(130, 120), to: Vector2(230, 210),
                     [Color(hex: 0x0B1A40), Color(hex: 0xFFB36B)]))
        drawPolygon([Vector2(180, 120), Vector2(230, 210), Vector2(130, 210)])
        // Along-path ramps on a line capsule and a quadratic Bézier.
        stroke(.alongPath([Color(hex: 0xFFF3C4), Color(hex: 0xD03060)]))
        strokeWeight(8)
        drawLine(Vector2(20, 234), Vector2(236, 234))
        drawBezier(Vector2(20, 108), Vector2(128, 86), Vector2(118, 108))
        noStroke()
    }
}

/// The standard notices and caption helpers, plus a closed polyline: an `.info`
/// status filling the canvas, a `.warning` status scoped to a sub-rectangle,
/// captions on both edges, and `drawPolyline(closed:)` joining its seam. Pins
/// the helpers' look and that they leave the drawing state untouched (the
/// rectangle after them still draws with the sketch's own fill).
private final class StatusNotices: Sketch {
    override var canvasSize: CanvasSize { .square(256) }

    override func draw() {
        background(Color(white: 0.06))
        drawStatus("Waiting for camera…")
        drawStatus("Model unavailable", style: .warning,
                   in: Rectangle(x: 0, y: 150, width: width, height: 90))
        drawCaption("StatusNotices — a caption")
        drawCaption("top caption", edge: .top)
        // State untouched by the helpers: this still draws white, stroke-free.
        fill(.white)
        noStroke()
        drawRect(10, 118, 20, 20)
        // A closed polyline turns its seam with the join (vs. an open V).
        stroke(.white)
        strokeWeight(6)
        drawPolyline([Vector2(200, 110), Vector2(236, 140), Vector2(200, 140)], closed: true)
    }
}

/// Three translucent primary-color disks on black, drawn with `blendMode(.add)`
/// so they sum as light: each pair overlaps in a secondary and all three meet in
/// a white core. Pins the additive blend factors (and that `.add` rides the SDF
/// path). Deterministic — no time dependence.
private final class AdditiveBlend: Sketch {
    override var canvasSize: CanvasSize { .square(256) }

    override func draw() {
        background(.black)
        blendMode(.add)
        noStroke()
        let r = width * 0.3
        let cx = width * 0.5, cy = height * 0.52, off = width * 0.17
        fill(Color(red: 1, green: 0, blue: 0, alpha: 0.85))
        drawCircle(cx, cy - off, r)
        fill(Color(red: 0, green: 1, blue: 0, alpha: 0.85))
        drawCircle(cx - off * 0.92, cy + off * 0.6, r)
        fill(Color(red: 0, green: 0, blue: 1, alpha: 0.85))
        drawCircle(cx + off * 0.92, cy + off * 0.6, r)
    }
}

/// A persistent (`noClear`) canvas: each frame scatters a seeded ring of faint
/// additive dots that rotates slowly, so by the captured frame the canvas holds
/// the accumulated, overlapping trails — not a single frame's sparse scatter.
/// Pins the accumulation surface (don't-clear + the persistent-target read-back),
/// and that it builds up across frames. Deterministic via the seed + fixed timestep.
private final class AccumulationField: Sketch {
    override var canvasSize: CanvasSize { .square(256) }
    private var seeds: [(angle: Double, radius: Double)] = []

    override func setup() {
        seed(3)
        background(Color(white: 0.02))     // the one base wipe; then accumulate
        noClear()
        for _ in 0 ..< 200 {
            seeds.append((random(.tau), random(40, 110)))
        }
    }

    override func draw() {
        blendMode(.add)
        noStroke()
        fill(Color(red: 0.5, green: 0.72, blue: 1, alpha: 0.12))
        let cx = width / 2, cy = height / 2
        let spin = time * 0.6
        for s in seeds {
            let a = s.angle + spin
            drawCircle(cx + cos(a) * s.radius, cy + sin(a) * s.radius, 2.2)
        }
    }
}

/// Bright additive disks overlapping past full brightness, mapped down by ACES.
/// The center stacks three saturated colors into a high-dynamic-range core that a
/// clamp would flatten to white; this pins that the linear-float frame is
/// tone-mapped in the present pass (not clipped). Deterministic (no time/random).
private final class ToneMappedBloom: Sketch {
    override var canvasSize: CanvasSize { .square(256) }

    override func draw() {
        background(Color(hex: 0x05060A))
        toneMap(.aces, exposure: 1.6)
        blendMode(.add)
        noStroke()
        let r = width * 0.32
        let cx = width * 0.5, cy = height * 0.5, off = width * 0.14
        fill(Color(red: 1, green: 0.2, blue: 0.1, alpha: 0.95))
        drawCircle(cx, cy - off, r)
        fill(Color(red: 0.1, green: 1, blue: 0.3, alpha: 0.95))
        drawCircle(cx - off, cy + off * 0.7, r)
        fill(Color(red: 0.2, green: 0.4, blue: 1, alpha: 0.95))
        drawCircle(cx + off, cy + off * 0.7, r)
    }
}
