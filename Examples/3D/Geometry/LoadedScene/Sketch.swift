import Ollin
import Foundation

/// Load a whole authored scene and draw it in place, opening on its own camera
/// and lights. One loader covers both major formats: press **F** to swap the
/// bundled glTF stage for its USD twin, through the very same `loadScene` call.
///
/// `loadMesh` merges a file to one mesh; `loadScene` keeps its *structure*: a tree
/// of named nodes with their authored transforms, plus the cameras and lights the
/// file was authored with, all as the ordinary core types (`Camera3D`, `Light`,
/// `Mesh`). So a scene composed in a 3D design tool comes in as a layout the
/// sketch can draw whole (`drawScene`), while still reaching one node by name to
/// drive it from `draw()`. The view opens on the file's own camera and hands it
/// to you (`cameraControl(from:)`): drag to orbit, scroll to dolly, right-drag
/// to pan. Lights ride their nodes, so a light's carrier moved from `draw()`
/// (or by a scene animation) carries its light along.
///
/// The bundled `scene.gltf` is a small stage authored by the project itself
/// (regenerate it with `Scripts/make-sample-scene.swift`). Its pedestal is one
/// mesh of two primitives with different materials (a body and a darker cap
/// lip), which `drawScene` renders as authored, each slice in its own material,
/// and its sculpture spins about its own pivot, the authored transform
/// composing underneath. The bundled `stage.usda` is a small sculpture court
/// (regenerate it with `Scripts/make-usd-scene.swift`), read like the whole USD
/// family (`.usdz`, `.usdc`, `.usda`, `.usd`) by Ollin's own parser: it is lit
/// by one UsdLux light of every mapped kind (a distant sunset key, a sphere
/// fill, a cone-shaped sphere beam on the gem, a rect backlight panel, an
/// overhead disk pool, and a cylinder floor glow), and its gem is two-tone: a
/// material-binding GeomSubset gives its lower facets a garnet material while
/// the crown keeps the mesh's own amber binding. The gem turns on its plinth
/// through the same name subscript.
///
/// Point this at any scene of your own by setting `OLLIN_SCENE` to its path; an
/// exported `.usdz` or `.gltf` from a 3D design tool drops straight in. Files
/// from mesh-only formats (`.obj`, `.stl`, …) load too, as a single-node scene
/// with no cameras or lights.
@main
final class LoadedScene: Sketch {
    private var stage: Scene!
    /// True while the USD court is on stage; **F** flips between the bundled files.
    private var showingUSD = false
    /// A scene of the user's own, from `OLLIN_SCENE`; the toggle stays out of its way.
    private var overridden = false

    override func setup() {
        if let path = ProcessInfo.processInfo.environment["OLLIN_SCENE"],
           let s = loadScene(path) {
            stage = s
            overridden = true
        } else {
            loadStage()
        }
    }

    /// Both formats come through the same call: only the file name changes.
    private func loadStage() {
        stage = showingUSD
            ? Scene(resource: "stage", withExtension: "usda", in: Bundle.module)
            : Scene(resource: "scene", withExtension: "gltf", in: Bundle.module)
    }

    override func keyPressed() {
        guard !overridden, key == "f" || key == "F" else { return }
        showingUSD.toggle()
        loadStage()
    }

    override func draw() {
        background(Color(hex: 0x0E1117))

        // The authored view and lighting: open on the file's camera, then hand
        // the viewer the orbit. Fall back to a framing and a plain key for a
        // file with no camera or lights of its own.
        cameraControl(from: stage.camera ?? .orbiting(target: Vector3(0, 0.8, 0),
                                                      radius: 6, elevation: 0.3))
        ambientLight(Color(white: 0.22))
        if stage.lights.isEmpty {
            directionalLight(Color(hex: 0xFFF2DC), direction: Vector3(-0.55, -0.75, -0.35),
                             intensity: 0.95)
        } else {
            for l in stage.lights { light(l) }
        }
        castShadows()

        // Reach a node by name and drive it: the glTF stage's sculpture spins
        // about its own pivot, and the USD court's gem turns on its plinth (the
        // authored transform composes underneath either way). The subscript is
        // addressed directly both times so the mutation writes back through it.
        let spinning = stage["sculpture"] != nil ? "sculpture" : "gem"
        stage[spinning]?.rotate(deltaTime * 0.7, axis: .unitY)

        fill(.white)   // white fill shows each node's authored material color untouched
        drawScene(stage)

        let inventory = "\(stage.nodes.count) root nodes · \(stage.cameras.count) camera · \(stage.lights.count) lights"
        drawCaption("\(stage.name ?? "scene") · \(inventory)"
                    + (overridden ? "" : " · F for the \(showingUSD ? "glTF" : "USD") twin"))
    }
}
