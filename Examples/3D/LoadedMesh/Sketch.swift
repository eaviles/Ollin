import Ollin
import Foundation

/// Load a 3D model from a file and draw it lit and spinning through a `Camera3D`.
///
/// Ollin reads a model from `.obj`, `.usdz`/`.usdc`/`.stl`/`.ply` (Apple's Model I/O),
/// or `.gltf`/`.glb` (Ollin's own reader, the format most tools export). The loaded
/// geometry rides the exact same depth-tested, auto-lit mesh path as the built-in
/// primitives: `loadMesh` returns a `Mesh`, `normalized(scale:)` fits it to the scene
/// no matter what size its author saved it at, and `drawMesh` draws it.
///
/// A glTF model also brings its own **base-color material and texture**: the bundled
/// `model.gltf` is a textured cube, drawn in its own colors (white `fill`, so the
/// texture shows true). A model with no material falls back to a chosen `fill`.
///
/// Point this at any model by setting `OLLIN_MESH` to its path, or drop a `model.usdz`
/// (or `.glb`/`.gltf`/`.obj`) beside this sketch. Until one is found it spins a
/// placeholder and shows how to add a model.
///
/// Tip: many 3D design tools export glTF or USDZ. A model you make yourself is your
/// own work, free to ship, whereas downloaded sample models often aren't.
@main
final class LoadedMesh: Sketch {
    private var mesh: Mesh?
    private var sourceName = ""

    override func setup() {
        // An explicit path wins; otherwise a model bundled beside the sketch.
        if let path = ProcessInfo.processInfo.environment["OLLIN_MESH"], let m = loadMesh(path) {
            adopt(m, named: (path as NSString).lastPathComponent)
        } else {
            for ext in ["usdz", "glb", "gltf", "obj"] {
                if let url = Bundle.module.url(forResource: "model", withExtension: ext),
                   let m = Mesh(contentsOf: url) {
                    adopt(m, named: "model.\(ext)")
                    break
                }
            }
        }
    }

    /// Fit a freshly loaded model to the scene (recenter + scale to a few units) and
    /// keep it for drawing.
    private func adopt(_ loaded: Mesh, named name: String) {
        mesh = loaded.normalized(scale: 3)
        sourceName = name
    }

    override func draw() {
        background(Color(hex: 0x0E1117))
        camera(.orbiting(radius: 7, azimuth: time * 0.3, elevation: 0.2, fieldOfView: .pi / 4))

        if let mesh {
            let textured = mesh.material != nil
            withState {
                rotateY(time * 0.4)
                if textured {
                    fill(.white)               // let the model's own material/texture show
                } else {
                    fill(Color(hex: 0xF5C542)) // rubber-duck yellow for a material-less model
                    specular(0.5)
                    shininess(40)
                }
                drawMesh(mesh)
            }
            let surface = textured ? "textured" : "\(mesh.triangleCount) triangles"
            drawCaption("\(sourceName) · \(surface)")
        } else {
            // No model yet, spin a placeholder and say how to add one.
            withState {
                rotateY(time * 0.4)
                rotateX(0.32)
                fill(Color(hue: 0.55, saturation: 0.5, brightness: 0.9))
                drawTorusKnot(radius: 1.1, tube: 0.34)
            }
            drawStatus("""
                No model loaded.

                Set OLLIN_MESH to a model file (.obj, .usdz, .gltf, or .glb)
                or drop a model.usdz (or .glb/.gltf/.obj) beside this sketch.
                """)
        }
    }
}
