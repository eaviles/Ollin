import Ollin
import OllinSampleModels
import Foundation

/// Load a 3D model from a file and draw it lit and spinning through a `Camera3D`.
///
/// Ollin reads a model from `.obj`, `.usdz`/`.usdc`/`.stl`/`.ply` (Apple's Model I/O
/// for the last two), or `.gltf`/`.glb` (Ollin's own reader, the format most tools
/// export). The loaded geometry takes the exact same depth-tested, auto-lit mesh
/// path as the built-in primitives: `loadMesh` returns a `Mesh`,
/// `normalized(scale:)` fits it to the scene no matter what size its author saved
/// it at, and `drawMesh` draws it.
///
/// Three models cycle under the space bar. The rubber duck from
/// `OllinSampleModels` is a `.glb` with one texture, its paint and its shading,
/// drawn in its own colors (white `fill`, so the texture shows true). The
/// textured cube saved beside this sketch as `model.gltf` brings a base-color
/// texture alone. The crystal in `model.obj` carries no material at all and takes
/// the `fill` and the specular the sketch sets.
///
/// Point `OLLIN_MESH` at a model of your own and it joins the ring first, or drop a
/// `model.usdz` (or `.glb`/`.gltf`/`.obj`) beside this sketch.
@main
final class LoadedMesh: Sketch {
    private struct Entry {
        let name: String
        let mesh: Mesh
        let credit: String?
    }

    private var entries: [Entry] = []
    private var index = 0

    override func setup() {
        // An explicit path wins the first slot; then the bundled duck; then any
        // model saved beside the sketch.
        if let path = ProcessInfo.processInfo.environment["OLLIN_MESH"], let m = try? loadMesh(path) {
            add(m, named: (path as NSString).lastPathComponent)
        }
        let duck = SampleModel.duck
        add(duck.load(), named: "\(duck.name).glb", credit: duck.credit.line)
        for ext in ["usdz", "glb", "gltf", "obj"] {
            if let url = Bundle.module.url(forResource: "model", withExtension: ext),
               let m = try? Mesh(contentsOf: url) {
                add(m, named: "model.\(ext)")
            }
        }
    }

    /// Fit a freshly loaded model to the scene (recenter + scale to a few units) and
    /// keep it in the ring.
    private func add(_ loaded: Mesh, named name: String, credit: String? = nil) {
        entries.append(Entry(name: name, mesh: loaded.normalized(scale: 3), credit: credit))
    }

    override func keyPressed() {
        guard !entries.isEmpty else { return }
        switch key {
        case " ", "]": index = (index + 1) % entries.count
        case "[": index = (index + entries.count - 1) % entries.count
        default: break
        }
    }

    override func draw() {
        background(Color(hex: 0x0E1117))
        cameraShowcase(.turntable(period: .tau / 0.3), radius: 7, elevation: 0.2, fieldOfView: .pi / 4)

        guard !entries.isEmpty else {
            drawStatus("No model loaded.")
            return
        }
        let entry = entries[index]
        let textured = entry.mesh.material != nil
        withState {
            rotateY(time * 0.4)
            if textured {
                fill(.white)               // let the model's own material and texture show
            } else {
                fill(Color(hex: 0xF5C542)) // a model with no material takes the fill
                specular(0.5)
                specularSharpness(40)
            }
            drawMesh(entry.mesh)
        }
        let surface = textured ? "textured" : "\(entry.mesh.triangleCount) triangles, drawn in the fill"
        var caption = "\(entry.name) · \(surface)"
        if let credit = entry.credit { caption += " · \(credit)" }
        drawCaption(caption + "   ·   space: next model")
    }
}
