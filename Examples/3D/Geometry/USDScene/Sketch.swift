import Ollin
import Foundation

/// Load a USD scene with its structure kept, open on its authored camera, and
/// light it from the sketch.
///
/// The USD family (`.usdz`, `.usdc`, `.usda`, `.usd`) loads through `loadScene`
/// the way glTF does: a tree of named nodes with their authored transforms,
/// node-local meshes wearing their authored materials, and the file's cameras,
/// all as the ordinary core types. One honest difference: USD *lights* don't
/// survive the platform importer, so a USD scene arrives with `lights` empty and
/// the sketch sets its own, as here. The bundled `stage.usda` is a small
/// sculpture court authored by the project itself (regenerate it with
/// `Scripts/make-usd-scene.swift`); the gem turns about its own pivot through
/// the name subscript, its authored plinth transform composing underneath.
///
/// Point this at any USD scene by setting `OLLIN_SCENE` to its path, an exported
/// `.usdz` from a 3D design tool drops straight in.
@main
final class USDScene: Sketch {
    private var court: Scene!

    override func setup() {
        if let path = ProcessInfo.processInfo.environment["OLLIN_SCENE"],
           let s = loadScene(path) {
            court = s
        } else {
            court = Scene(resource: "stage", extension: "usda", in: Bundle.module)
        }
    }

    override func draw() {
        background(Color(hex: 0x101318))

        // The authored view; the lighting is the sketch's own (USD lights don't
        // carry through the importer).
        camera(court.camera ?? .orbiting(target: Vector3(0, 1, 0), radius: 7, elevation: 0.25))
        ambientLight(Color(white: 0.22))
        directionalLight(Color(hex: 0xFFF2DC), direction: Vector3(-0.55, -0.75, -0.35), intensity: 0.95)
        pointLight(Color(hex: 0x9FB8FF), at: Vector3(2.5, 3.2, 2.8), intensity: 0.5)
        castShadows()

        // Reach a node by name and drive it: the gem turns on its plinth.
        court["gem"]?.rotate(deltaTime * 0.6, axis: .unitY)

        fill(.white)   // white fill shows each node's authored material color untouched
        drawScene(court)

        let inventory = "\(court.nodes.count) root node · \(court.cameras.count) camera · \(court.lights.count) lights"
        drawCaption("\(court.name ?? "stage.usda") · \(inventory)")
    }
}
