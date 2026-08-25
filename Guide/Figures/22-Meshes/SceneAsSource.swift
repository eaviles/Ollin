// figure: frame=0 probe themed
//
// Guide diagram (Chapter 22): a scene taken apart. Left, part of the draw() the
// generator writes from a scene file. Right, the scene those very placements
// draw. One read of the file feeds both panels: the text is the generator's own
// output, and the picture is drawn by walking the same description, so neither
// panel is a hand-made stand-in for the other.
import Foundation
import Ollin
import OllinDiagram
import OllinProjects
import OllinSceneImport

final class SceneAsSource: Sketch {
    override var canvasSize: CanvasSize { .size(920, 460) }

    @Param var darkTheme = false
    var theme: DiagramTheme { DiagramTheme(dark: darkTheme) }

    var paper: Color { theme.paper }
    var ink: Color { theme.ink }
    var faint: Color { theme.ink(0.45) }

    /// The scene file the chapter has been using all along.
    ///
    /// Found by walking up from the working directory rather than from
    /// `#filePath`: a figure is compiled from a copy in a work directory, so its
    /// own path leads nowhere near the repository.
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

    /// What `--from-scene` read out of the file.
    var described: ImportedScene?
    /// The lines the generator wrote, trimmed to what fits beside the picture.
    var listing: [String] = []
    /// The meshes, looked up the way the generated sketch looks them up.
    var parts: [String: Mesh] = [:]

    let codeBox = Rectangle(x: 44, y: 96, width: 430, height: 320)
    let viewBox = Rectangle(x: 576, y: 76, width: 300, height: 320)

    override func setup() {
        described = SceneImport.read(sceneURL)
        listing = Self.excerpt(from: generatedSource())
        loadParts()
    }

    /// The real thing: the source the command would write for this file.
    private func generatedSource() -> String {
        guard let described else { return "" }
        let request = ProjectRequest(name: "Yard", importedScene: described,
                                     destination: sceneURL, framework: .remote(url: "", branch: ""))
        return ProjectGenerator.sketchSource(request)
    }

    /// The same walk the generated sketch performs, so the names in the
    /// description reach the same meshes.
    private func loadParts() {
        guard let described, let scene = Scene(contentsOf: sceneURL) else { return }
        var found: [Mesh] = []
        func visit(_ nodes: [SceneNode]) {
            for node in nodes {
                if let mesh = node.mesh { found.append(mesh) }
                visit(node.children)
            }
        }
        visit(scene.nodes)
        for (name, mesh) in zip(described.partNames, found) { parts[name] = mesh }
    }

    override func draw() {
        background(paper)
        drawListing()
        drawArrow()
        drawScenePanel()
    }

    // MARK: - The written sketch

    /// The generated `draw()`, from its camera down to the first nested block.
    /// A figure has room for a window, not a file, and this is the part that
    /// shows every shape at once.
    static func excerpt(from source: String) -> [String] {
        let all = source.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)

        /// Everything from the line matching `opens` until the first line whose
        /// brackets balance again.
        func block(from index: Int) -> [String] {
            var lines: [String] = []
            var depth = 0
            for line in all[index...] {
                lines.append(line)
                depth += line.filter { $0 == "(" || $0 == "{" }.count
                depth -= line.filter { $0 == ")" || $0 == "}" }.count
                if depth <= 0 && lines.count > 1 { break }
            }
            return lines
        }

        var lines: [String] = []
        if let camera = all.firstIndex(where: { $0.contains("camera(Camera3D(") }) {
            lines += block(from: camera)
        }
        // One light stands for all of them; the rest would fill the panel.
        if let light = all.firstIndex(where: { $0.contains("light(.") }) {
            lines.append("")
            lines += block(from: light)
            lines.append("        // ... and the rest of the file's lights")
        }
        // The nested pair, which is what shows a group holding its children.
        if let nested = all.firstIndex(where: { $0.contains("// pedestal") }) {
            lines.append("")
            lines += all[nested..<Swift.min(nested + 2, all.count)]
            if nested + 2 < all.count { lines += block(from: nested + 2) }
        }

        // The lines carry the sketch's own indentation, which only wastes width here.
        let common = lines.filter { !$0.isEmpty }
            .map { $0.prefix { $0 == " " }.count }.min() ?? 0
        return lines.map { $0.count < common ? $0 : String($0.dropFirst(common)) }
    }

    private func drawListing() {
        noStroke()
        label("what the command writes", at: Vector2(codeBox.x, 62))
        guard !listing.isEmpty else { return }

        let longest = listing.max { textWidth($0) < textWidth($1) } ?? ""
        textFont(BitmapFont.builtin)
        var size = 16.0
        textSize(size)
        while size > 6, textWidth(longest) > codeBox.width {
            size -= 1
            textSize(size)
        }

        let step = size * 1.45
        textAlign(.left, .baseline)
        for (index, line) in listing.enumerated() {
            // The calls that carry a number the file decided.
            let notable = line.contains("translate(") || line.contains("rotate")
                || line.contains("camera(") || line.contains("light(")
            fill(notable ? ink : faint)
            drawText(line, codeBox.x, codeBox.y + Double(index) * step)
        }
        label("Swift, in a project of your own", at: Vector2(codeBox.x, 436))
    }

    // MARK: - The scene those calls draw

    private func drawScenePanel() {
        noStroke()
        label("what those lines draw", at: Vector2(viewBox.x, 62))

        // The scene goes into a layer the size of the panel, not into a clipped
        // corner of the canvas: a 3D camera frames whatever surface it draws
        // into, so only its own layer gives it the panel's shape.
        if let described {
            let panel = renderTarget(width: Int(viewBox.width), height: Int(viewBox.height))
            withTarget(panel) {
                background(Color(hex: 0x14161C))
                drawPanelContents(described)
            }
            drawImage(panel.image, in: viewBox)
        }

        noFill()
        stroke(faint)
        strokeWeight(1)
        drawRect(corner: Vector2(viewBox.x, viewBox.y), width: viewBox.width, height: viewBox.height)

        noStroke()
        label("the file, placed by those calls", at: Vector2(viewBox.x, 436))
    }

    /// Walks the description exactly as the emitted blocks would run, so the
    /// picture is the placements rather than a second drawing of the file.
    private func drawPanelContents(_ scene: ImportedScene) {
        if let c = scene.camera {
            camera(Camera3D(eye: Vector3(c.eye.x, c.eye.y, c.eye.z),
                            target: Vector3(c.target.x, c.target.y, c.target.z),
                            up: Vector3(c.up.x, c.up.y, c.up.z),
                            near: c.near, far: c.far,
                            projection: .perspective(fieldOfView: fieldOfView(c))))
        }
        for l in scene.lights { light(resolved(l)) }
        for node in scene.roots { place(node) }
    }

    private func place(_ node: ImportedSceneNode) {
        withState {
            if let t = node.translation { translate(t.x, t.y, t.z) }
            if let r = node.rotation { rotate(r.angle, axis: Vector3(r.axis.x, r.axis.y, r.axis.z)) }
            if let s = node.scale { scale(s.x, s.y, s.z) }
            if let part = node.part, let mesh = parts[part] { drawMesh(mesh) }
            for child in node.children { place(child) }
        }
    }

    private func fieldOfView(_ c: ImportedCamera) -> Double {
        if case .perspective(let fov) = c.projection { return fov }
        return .pi / 3
    }

    private func resolved(_ l: ImportedLight) -> Light {
        let color = Color(hex: UInt32(l.colorHex & 0xFFFFFF))
        let at = Vector3(l.position.x, l.position.y, l.position.z)
        let toward = Vector3(l.direction.x, l.direction.y, l.direction.z)
        switch l.kind {
        case .directional: return .directional(color, direction: toward, intensity: l.intensity)
        case .point:       return .point(color, at: at, intensity: l.intensity)
        case .spot:        return .spot(color, at: at, direction: toward, angle: l.coneAngle,
                                        penumbra: l.penumbra, intensity: l.intensity)
        case .rect:        return .rect(color, at: at, direction: toward, width: l.width,
                                        height: l.height, intensity: l.intensity)
        case .disk:        return .disk(color, at: at, direction: toward, radius: l.radius,
                                        intensity: l.intensity)
        case .tube:        return .tube(color, from: Vector3(l.endA.x, l.endA.y, l.endA.z),
                                        to: Vector3(l.endB.x, l.endB.y, l.endB.z),
                                        radius: l.radius, intensity: l.intensity)
        }
    }

    // MARK: - Chrome

    private func drawArrow() {
        let y = viewBox.y + viewBox.height / 2
        stroke(faint)
        strokeWeight(1.5)
        drawLine(494, y, 554, y)
        drawLine(546, y - 6, 554, y)
        drawLine(546, y + 6, 554, y)

        noStroke()
        fill(faint)
        textFont(OutlineFont.systemMedium)
        textSize(12)
        textAlign(.center, .baseline)
        drawText("--from-scene", 524, y - 12)
    }

    private func label(_ text: String, at position: Vector2) {
        fill(faint)
        textFont(OutlineFont.systemMedium)
        textSize(13)
        textAlign(.left, .baseline)
        drawText(text, position.x, position.y)
    }
}
