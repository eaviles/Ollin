import Ollin

/// **A 3D scene as line work a machine can follow.**
///
/// `lineDrawing(of:)` takes meshes and the camera looking at them and gives
/// back 2D paths with everything the surfaces hide taken out: the silhouette
/// where a form turns away, the creases where faces meet at an angle, and the
/// boundary where a surface ends. Those paths are ordinary line work, so this
/// sketch draws them with `drawPolyline` and a pen plotter or a laser can have
/// them exactly as they are:
///
/// ```sh
/// ollin Sketch.swift --export-svg scene.svg
/// ollin Sketch.swift --export-gcode scene.gcode --width 180
/// ```
///
/// `Crease` is the angle two faces must meet at before the edge between them is
/// drawn, so a low one finds the ridges of the ball and a high one leaves it as
/// its outline alone; at 0 every edge is drawn, which is a wireframe rather than
/// a drawing. `Spacing` is how finely each edge is tested for whether it is
/// hidden, and `Shaded` shows the same scene lit, for the comparison.
@main
final class LineDrawing: Sketch {

    @Param("Turn", 0 ... 1, icon: "rotate.3d", group: "Camera") var turn = 0.12
    @Param("Height", 0.4 ... 4, icon: "arrow.up.and.down", group: "Camera") var eyeHeight = 1.9
    @Param("Crease", 0 ... 1.2, icon: "angle", group: "Drawing") var crease = 0.5
    @Param("Spacing", 0.5 ... 8, icon: "ruler", group: "Drawing") var spacing = 2.0
    @Param("Weight", 0.5 ... 6, icon: "pencil.tip", group: "Drawing") var weight = 2.0
    @Param(icon: "cube.transparent", group: "View") var shaded = false
    @Param("Show hidden", icon: "eye.slash", group: "View") var dashed = false

    override var canvasSize: CanvasSize { .square(900) }

    /// A line of text along the bottom, in the ink the drawing is in.
    private func note(_ text: String) {
        noStroke()
        fill(Color(hex: 0x1A1A1A))
        textSize(20)
        textAlign(.center, .bottom)
        drawText(text, width / 2, height - 28)
    }

    /// The scene: a slab with three solids standing on it, each placed where it
    /// belongs so they can all be handed over together and occlude each other.
    private var scene: [Mesh] {
        [
            Mesh.box(width: 6, height: 0.5, depth: 6)
                .transformed(by: MeshInstance(position: Vector3(0, -0.25, 0))),
            Mesh.cylinder(radius: 0.7, height: 2.2, segments: 24)
                .transformed(by: MeshInstance(position: Vector3(-1.5, 1.1, 0.6))),
            Mesh.sphere(radius: 0.95, segments: 32, rings: 16)
                .transformed(by: MeshInstance(position: Vector3(1.2, 0.95, -0.4))),
            Mesh.box(size: 1.1)
                .transformed(by: MeshInstance(position: Vector3(0.4, 0.55, 1.8),
                                              rotation: Vector3(0, 0.6, 0))),
        ]
    }

    override func draw() {
        background(Color(hex: 0xF4F1E8))
        let angle = (turn + time * 0.03) * .pi * 2
        camera(Camera3D(eye: Vector3(cos(angle) * 7.5, eyeHeight * 2.2, sin(angle) * 7.5),
                        target: Vector3(0, 0.9, 0)))

        if shaded {
            light(.directional(.white, direction: Vector3(0.5, -1, -0.4)))
            fill(Color(hex: 0xBFB6A4))
            for mesh in scene { drawMesh(mesh) }
            note("The same scene lit, for the comparison")
            return
        }

        stroke(Color(hex: 0x1A1A1A))
        strokeWeight(weight)
        strokeJoin(.round)
        strokeCap(.round)
        noFill()
        let drawing = lineDrawing(of: scene, creaseAngle: crease, spacing: spacing)
        if dashed {
            stroke(Color(hex: 0x1A1A1A, alpha: 0.28))
            strokeWeight(weight * 0.6)
            for line in drawing.hidden { drawPolyline(line.points, closed: line.isClosed) }
            stroke(Color(hex: 0x1A1A1A))
            strokeWeight(weight)
        }
        for line in drawing.paths {
            drawPolyline(line.points, closed: line.isClosed)
        }
        note("\(drawing.paths.count) paths, ready for a pen")
    }
}
