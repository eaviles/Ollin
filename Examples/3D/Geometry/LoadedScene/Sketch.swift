import Ollin
import Foundation

/// Load a whole authored scene and draw it in place, opening on its own camera
/// and lights.
///
/// `loadMesh` merges a file to one mesh; `loadScene` keeps its *structure*: a tree
/// of named nodes with their authored transforms, plus the cameras and lights the
/// file was authored with, all as the ordinary core types (`Camera3D`, `Light`,
/// `Mesh`). So a scene composed in a 3D design tool comes in as a layout the
/// sketch can draw whole (`drawScene`), while still reaching one node by name to
/// drive it from `draw()`: here the pedestal's sculpture spins about its own
/// pivot, its authored transform composing underneath. The view opens on the
/// file's own camera and hands it to you (`cameraControl(from:)`): drag to
/// orbit, scroll to dolly, right-drag to pan. Lights ride their nodes, so a
/// light's carrier moved from `draw()` (or by a scene animation) carries its
/// light along. The bundled `scene.gltf` is a small stage authored by the
/// project itself (regenerate it with `Scripts/make-sample-scene.swift`).
///
/// Point this at any glTF scene by setting `OLLIN_SCENE` to its path. Files from
/// mesh-only formats (`.obj`, `.stl`, …) load too, as a single-node scene with no
/// cameras or lights.
@main
final class LoadedScene: Sketch {
    private var stage: Scene!

    override func setup() {
        if let path = ProcessInfo.processInfo.environment["OLLIN_SCENE"],
           let s = loadScene(path) {
            stage = s
        } else {
            stage = Scene(resource: "scene", extension: "gltf", in: Bundle.module)
        }
    }

    override func draw() {
        background(Color(hex: 0x0E1117))

        // The authored view and lighting: open on the file's camera, then hand
        // the viewer the orbit. Fall back to a framing for a camera-less file.
        cameraControl(from: stage.camera ?? .orbiting(target: Vector3(0, 0.8, 0),
                                                      radius: 6, elevation: 0.3))
        for l in stage.lights { light(l) }
        castShadows()

        // Reach a node by name and drive it: the sculpture spins about its own
        // pivot on top of the pedestal (its authored transform composes underneath).
        stage["sculpture"]?.rotate(deltaTime * 0.7, axis: .unitY)

        fill(.white)   // white fill shows each node's authored material color untouched
        drawScene(stage)

        let inventory = "\(stage.nodes.count) root nodes · \(stage.cameras.count) camera · \(stage.lights.count) lights"
        drawCaption("\(stage.name ?? "scene") · \(inventory)")
    }
}
