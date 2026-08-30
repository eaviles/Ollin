import Ollin
import Foundation

/// The scene explorer: a read-only lens on a scene file.
///
/// Point it at a glTF or USD scene dropped beside the sketch and look around it
/// the way the material explorer looks at a finish: orbit it or adopt the file's
/// own camera, switch the lighting preset, backdrop, fog, and shadows around it,
/// and toggle the file's authored lights one by one. Step through the parts with
/// the arrow keys (or the Part stepper) to highlight or isolate one: the caption
/// names it, a wireframe box shows its bounds, and anything the import can't
/// carry exactly (a mesh wearing several materials, a transform with a shear in
/// it) is said on the part that carries it, right where the eye is.
///
/// The explorer never moves a node and never writes a file. To take a scene
/// apart as code, `ollin new --from-scene <file>` writes it out as a sketch
/// whose source is yours to edit.
///
/// Point it at any scene of your own by setting `OLLIN_SCENE` to the file's
/// path; the File knob then switches back to the bundled stages.
@main
final class SceneExplorer: Sketch {

    enum SceneFile: CaseIterable, ParamOption {
        case gltfStage, usdStage

        var resource: (name: String, ext: String) {
            switch self {
            case .gltfStage: ("scene", "gltf")
            case .usdStage: ("stage", "usda")
            }
        }
    }

    enum PartMode: CaseIterable, ParamOption {
        case all, highlight, isolate
    }

    enum CameraMode: CaseIterable, ParamOption {
        case orbit, file
    }

    enum Backdrop: CaseIterable, ParamOption {
        case none, studio, city, courtyard, forest, interior, night, sunrise, sunset, sky

        var environment: Environment? {
            switch self {
            case .none: nil
            case .studio: .studio
            case .city: .city
            case .courtyard: .courtyard
            case .forest: .forest
            case .interior: .interior
            case .night: .night
            case .sunrise: .sunrise
            case .sunset: .sunset
            case .sky: .sky()
            }
        }
    }

    // The file, and how to look at it.
    @Param(group: "Scene") var file: SceneFile = .gltfStage
    @Param(group: "Scene") var view: CameraMode = .orbit

    // The part under the eye: 0 is the whole scene, 1... steps the named parts.
    @Param(0...200, group: "Part") var part = 0
    @Param(group: "Part") var mode: PartMode = .highlight
    @Param(group: "Part") var showBounds = true

    // The file's own lights, one switch each (switches past the file's count are inert).
    @Param(group: "Lights") var light1 = true
    @Param(group: "Lights") var light2 = true
    @Param(group: "Lights") var light3 = true
    @Param(group: "Lights") var light4 = true

    // The stage around it, the material explorer's block.
    @Param(group: "Stage") var mood: LightingPreset = .studio
    @Param(group: "Stage") var backdrop: Backdrop = .none
    @Param(group: "Stage") var shadows = true
    @Param(group: "Stage") var haze = false

    private var scene: Scene?
    private var loadedFile: SceneFile?
    private var ownSceneShown = false

    /// Every node with a mesh, flattened depth-first, each with the chain of
    /// nodes from the root down to it. The chain is what places the part in
    /// world space when it draws alone.
    private var parts: [(name: String, chain: [SceneNode])] = []

    override func setup() {
        reload()
    }

    private func reload() {
        if let path = ProcessInfo.processInfo.environment["OLLIN_SCENE"], !ownSceneShown {
            scene = Scene(path: path)
            ownSceneShown = true
        } else {
            let r = file.resource
            scene = Scene(resource: r.name, withExtension: r.ext, in: .module)
        }
        loadedFile = file
        parts = []
        guard let scene else { return }
        var flat: [(String, [SceneNode])] = []
        func walk(_ node: SceneNode, _ path: [SceneNode]) {
            let chain = path + [node]
            if node.mesh != nil {
                let label = node.name.isEmpty ? "part \(flat.count + 1)" : node.name
                flat.append((label, chain))
            }
            for child in node.children { walk(child, chain) }
        }
        for node in scene.nodes { walk(node, []) }
        parts = flat
    }

    /// A scene holding just this chain: meshes stripped above the leaf, other
    /// children pruned, so the leaf draws exactly where the full walk puts it.
    private func isolated(_ chain: [SceneNode]) -> Scene {
        var wrapped = chain[chain.count - 1]
        wrapped.children = []
        for i in stride(from: chain.count - 2, through: 0, by: -1) {
            var parent = chain[i]
            parent.mesh = nil
            parent.children = [wrapped]
            wrapped = parent
        }
        return Scene(nodes: [wrapped])
    }

    /// The whole scene with one part's mesh removed, the backdrop of a highlight.
    private func without(_ chain: [SceneNode]) -> Scene {
        guard var scene else { return Scene() }
        func strip(_ nodes: inout [SceneNode], _ depth: Int) {
            for i in nodes.indices {
                if depth < chain.count, nodes[i].name == chain[depth].name {
                    if depth == chain.count - 1 {
                        nodes[i].mesh = nil
                    } else {
                        strip(&nodes[i].children, depth + 1)
                    }
                }
            }
        }
        strip(&scene.nodes, 0)
        return scene
    }

    override func keyPressed() {
        let count = parts.count
        guard count > 0 else { return }
        if keyCode == .rightArrow { part = (part + 1) % (count + 1) }
        if keyCode == .leftArrow { part = (part + count) % (count + 1) }
    }

    override func draw() {
        if loadedFile != file { reload(); part = 0 }
        background(Color(white: 0.05))
        guard let scene else {
            drawCaption("no scene file: drop one beside the sketch (scene.gltf / stage.usda)")
            return
        }

        // The camera: the file's own, or a free orbit sized to the scene.
        let (lo, hi) = scene.bounds
        let center = (lo + hi) / 2
        let radius = max((hi - lo).length, 0.001)
        if view == .file, let fileCamera = scene.camera {
            camera(fileCamera)
        } else {
            cameraShowcase(.autoOrbit(), target: center, radius: radius * 1.6,
                           elevation: 0.22, fieldOfView: .pi / 4)
        }

        lightingPreset(mood)
        if let environment = backdrop.environment { self.environment(environment) }
        castShadows(shadows)
        if haze { fog(Color(white: 0.55), density: 0.4 / radius) }

        // The file's own lights, toggled one by one.
        let switches = [light1, light2, light3, light4]
        for (i, l) in scene.lights.enumerated() where i < switches.count && switches[i] {
            light(l)
        }

        let picked = part >= 1 && part <= parts.count ? parts[part - 1] : nil

        switch (mode, picked) {
        case (.isolate, .some(let p)):
            fill(.white)
            drawScene(isolated(p.chain))
        case (.highlight, .some(let p)):
            fill(Color(white: 0.78))
            drawScene(without(p.chain))
            fill(.white)
            drawScene(isolated(p.chain))
        default:
            fill(.white)
            drawScene(scene)
        }

        // The picked part's bounds, and what the import wants said about it.
        if let p = picked {
            if showBounds {
                var (plo, phi) = isolated(p.chain).bounds
                let breathe = radius * 0.015
                plo = plo - Vector3(breathe, breathe, breathe)
                phi = phi + Vector3(breathe, breathe, breathe)
                // The light rig is frame state, not stack state, so the cage is
                // drawn lit; a bright fill keeps it reading as a marker.
                withState {
                    // Brighter than any lit surface, so the bloom threshold
                    // below catches the cage and nothing else.
                    fill(Color(red: 2.9, green: 2.3, blue: 3.5))
                    let edge = radius * 0.0024
                    let xs = [plo.x, phi.x], ys = [plo.y, phi.y], zs = [plo.z, phi.z]
                    for y in ys { for z in zs {
                        drawCapsule(from: Vector3(plo.x, y, z), to: Vector3(phi.x, y, z), radius: edge)
                    } }
                    for x in xs { for z in zs {
                        drawCapsule(from: Vector3(x, plo.y, z), to: Vector3(x, phi.y, z), radius: edge)
                    } }
                    for x in xs { for y in ys {
                        drawCapsule(from: Vector3(x, y, plo.z), to: Vector3(x, y, phi.z), radius: edge)
                    } }
                }
                postProcess(.bloom(threshold: 1.15, amount: 0.9, radius: 0.04))
            }
            let leaf = p.chain[p.chain.count - 1]
            var notes: [String] = []
            if leaf.wearsSeveralMaterials { notes.append("wears several materials, draws in its first") }
            if !leaf.placementIsExact { notes.append("transform carries a shear") }
            let suffix = notes.isEmpty ? "" : "   ·   " + notes.joined(separator: "; ")
            drawCaption("part \(part)/\(parts.count): \(p.name)\(suffix)")
        } else {
            let counts = "\(parts.count) parts · \(scene.lights.count) lights"
            drawCaption("\(scene.name ?? file.resource.name)   ·   \(counts)   ·   arrows pick a part")
        }
    }
}
