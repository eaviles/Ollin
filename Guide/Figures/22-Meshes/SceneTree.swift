// figure: frame=0 themed
//
// Guide diagram (Chapter 22): what loadScene keeps. Left, the file's own node
// tree, read from the scene the chapter has been using: every node by name,
// nested as the file nests them, tagged with what it carries. Middle, the
// scene drawn whole through its own camera and lights. Right, one node moved
// by name: the lamp brought to the front, and the light it carries goes with
// it, so the orb and the pedestal are lit from a new side.
import Foundation
import Ollin
import OllinDiagram

final class SceneTree: Sketch {
    override var canvasSize: CanvasSize { .size(880, 440) }

    @Param var darkTheme = false
    var theme: DiagramTheme { DiagramTheme(dark: darkTheme) }

    /// The scene file the chapter has been using all along, found by walking
    /// up from the working directory (a figure is compiled from a copy in a
    /// work directory, so its own path leads nowhere near the repository).
    var sceneURL: URL {
        let tail = "Examples/3D/Geometry/LoadedScene/scene.gltf"
        var directory = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        while true {
            let candidate = directory.appendingPathComponent(tail)
            if FileManager.default.fileExists(atPath: candidate.path) { return candidate }
            let parent = directory.deletingLastPathComponent()
            if parent == directory { return candidate }
            directory = parent
        }
    }

    struct Row {
        let depth: Int
        let name: String
        let carries: String
    }

    var stage: Scene?
    var rows: [Row] = []

    let treeBox = Rectangle(x: 44, y: 66, width: 236, height: 280)
    let panels = [Rectangle(x: 316, y: 66, width: 262, height: 280),
                  Rectangle(x: 604, y: 66, width: 262, height: 280)]

    override func setup() {
        stage = try? Scene(contentsOf: sceneURL)
        rows = Self.readTree(sceneURL)
    }

    /// The node list as the file writes it, so the tags come from the file
    /// rather than from a guess at the names.
    static func readTree(_ url: URL) -> [Row] {
        guard let data = try? Data(contentsOf: url),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let nodes = root["nodes"] as? [[String: Any]] else { return [] }
        let lights = ((root["extensions"] as? [String: Any])?["KHR_lights_punctual"] as? [String: Any])?["lights"]
            as? [[String: Any]] ?? []
        let roots = ((root["scenes"] as? [[String: Any]])?.first?["nodes"] as? [Int]) ?? []
        var rows: [Row] = []
        func visit(_ index: Int, depth: Int) {
            let node = nodes[index]
            var carries = "a group"
            if node["mesh"] != nil { carries = "a mesh" }
            if node["camera"] != nil { carries = "the camera" }
            if let ext = node["extensions"] as? [String: Any],
               let punctual = ext["KHR_lights_punctual"] as? [String: Any],
               let light = punctual["light"] as? Int, light < lights.count {
                carries = "a \(lights[light]["type"] as? String ?? "") light"
            }
            rows.append(Row(depth: depth, name: node["name"] as? String ?? "node \(index)", carries: carries))
            for child in node["children"] as? [Int] ?? [] { visit(child, depth: depth + 1) }
        }
        for index in roots { visit(index, depth: 0) }
        return rows
    }

    override func draw() {
        background(theme.paper)
        textFont(.system)

        drawTree()
        if let stage {
            drawView(of: stage, in: panels[0])
            var moved = stage
            if var lamp = moved["lamp"] {
                lamp.position = lamp.position + Vector3(2.35, 0, 0.75)
                moved["lamp"] = lamp
            }
            drawView(of: moved, in: panels[1])
        }

        let titles = ["what the file holds", "drawn whole, through its own camera", "the lamp moved by name"]
        let notes = ["nested as the file nests it",
                     "its camera, its lights, drawScene",
                     "the light it carries rides along"]
        for (i, box) in ([treeBox] + panels).enumerated() {
            noFill()
            stroke(theme.border)
            strokeWeight(1.5)
            drawRect(box)
            noStroke()
            drawText(titles[i], box.center.x, box.y - 22, size: 16, color: theme.ink, align: .center, .middle)
            drawText(notes[i], box.center.x, box.y + box.height + 12, size: 12,
                     color: theme.muted, align: .center, .top)
        }

        diagramCaption("loadScene keeps the file's structure; the sketch decides what moves",
                       at: 392, theme: theme)
    }

    private func drawTree() {
        noStroke()
        let step = 22.0
        let x0 = treeBox.x + 16, y0 = treeBox.y + 24
        for (i, row) in rows.enumerated() {
            let x = x0 + Double(row.depth) * 20
            let y = y0 + Double(i) * step
            if row.depth > 0 {
                stroke(theme.border)
                strokeWeight(1)
                drawLine(x - 12, y - step + 8, x - 12, y)
                drawLine(x - 12, y, x - 4, y)
                noStroke()
            }
            drawText(row.name, x, y, size: 15, color: theme.ink, align: .left, .middle)
            drawText(row.carries, treeBox.x + treeBox.width - 14, y, size: 12, color: theme.muted, align: .right, .middle)
        }
    }

    /// The scene goes into a layer the size of the panel, since a 3D camera
    /// frames whatever surface it draws into.
    private func drawView(of scene: Scene, in box: Rectangle) {
        let view = makeRenderTarget(width: Int(box.width), height: Int(box.height))
        withTarget(view) {
            background(Color(hex: 0x0E1117))
            camera(scene.camera ?? .orbiting(target: Vector3(0, 0.8, 0), radius: 6, elevation: 0.3))
            ambientLight(Color(white: 0.22))
            for l in scene.lights { light(l) }
            castShadows()
            fill(.white)
            drawScene(scene)
        }
        drawImage(view.image, in: box)
    }
}
