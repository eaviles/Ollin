import Ollin
import Foundation

/// Load a USD scene with its structure kept and draw it under its own authored
/// camera and lights.
///
/// The USD family (`.usdz`, `.usdc`, `.usda`, `.usd`) loads through `loadScene`
/// the way glTF does: a tree of named nodes with their authored transforms in
/// authored order, node-local meshes wearing their authored materials, the
/// file's cameras, and its UsdLux lights, all read by Ollin's own parser into
/// the ordinary core types. The bundled `stage.usda` is a
/// small sculpture court authored by the project itself, lit by one light of
/// every mapped kind: a distant sunset key, a sphere fill, a cone-shaped sphere
/// beam on the gem, a rect backlight panel, an overhead disk pool, and a
/// cylinder floor glow (regenerate it with `Scripts/make-usd-scene.swift`). The
/// gem turns about its own pivot through the name subscript, its authored
/// plinth transform composing underneath.
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

        // The authored view and the authored lighting rig; a scene with no
        // lights of its own falls back to a plain sketch key.
        camera(court.camera ?? .orbiting(target: Vector3(0, 1, 0), radius: 7, elevation: 0.25))
        ambientLight(Color(white: 0.22))
        if court.lights.isEmpty {
            directionalLight(Color(hex: 0xFFF2DC), direction: Vector3(-0.55, -0.75, -0.35),
                             intensity: 0.95)
        } else {
            for l in court.lights { light(l) }
        }
        castShadows()

        // Reach a node by name and drive it: the gem turns on its plinth.
        court["gem"]?.rotate(deltaTime * 0.6, axis: .unitY)

        fill(.white)   // white fill shows each node's authored material color untouched
        drawScene(court)

        let inventory = "\(court.nodes.count) root node · \(court.cameras.count) camera · \(court.lights.count) lights"
        drawCaption("\(court.name ?? "stage.usda") · \(inventory)")
    }
}
