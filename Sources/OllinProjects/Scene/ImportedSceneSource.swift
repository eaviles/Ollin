import Foundation

/// Writes the sketch that draws an imported scene.
///
/// Every placement becomes a `withState` block holding the moves that put one
/// part where the file put it. Nesting follows the file, so a group still turns
/// as one thing. This is the same composition `drawScene` does at runtime, only
/// written down, which is the whole point: the numbers are now yours to change.
enum ImportedSceneSource {

    static func body(_ scene: ImportedScene, className: String) -> String {
        var lines: [String] = []

        lines.append("/// A 3D scene brought over from a file.")
        if let origin = scene.origin, !origin.isEmpty {
            lines.append("/// \(origin)")
        }
        lines.append("///")
        lines.append("/// Its structure is written out below as ordinary calls, so the camera, the")
        lines.append("/// lights and every placement are lines you can change. The geometry itself")
        lines.append("/// still comes from the file, since a mesh is not something source can hold.")
        for note in scene.notes {
            lines.append("///")
            lines.append("/// \(note)")
        }

        lines.append("@main")
        lines.append("final class \(className): Sketch {")
        lines.append("")

        if scene.needsResource {
            lines.append(contentsOf: partStorage(scene))
            lines.append("")
        }

        lines.append("    override func setup() {")
        if scene.needsResource {
            lines.append("        loadParts()")
        } else {
            lines.append("        // The file carried no geometry, so there is nothing to load.")
        }
        lines.append("    }")
        lines.append("")

        lines.append("    override func draw() {")
        lines.append(contentsOf: drawBody(scene))
        lines.append("    }")

        if scene.needsResource {
            lines.append("")
            lines.append(contentsOf: loader(scene, className: className))
        }

        lines.append("}")
        return lines.joined(separator: "\n")
    }

    // MARK: - Stored parts

    private static func partStorage(_ scene: ImportedScene) -> [String] {
        let names = scene.partNames.map { "\"\(escaped($0))\"" }.joined(separator: ", ")
        return [
            "    /// The meshes this sketch draws, in the order the file lists them. Written",
            "    /// out here so a part still has a name where the file repeated one or left",
            "    /// one blank.",
            "    private static let partNames = [\(names)]",
            "",
            "    private var parts: [String: Mesh] = [:]",
        ]
    }

    /// Reads the file once. The walk has to match the order the names above were
    /// written in, so it is spelled out rather than left to a library call.
    private static func loader(_ scene: ImportedScene, className: String) -> [String] {
        guard let name = scene.resourceName, let ext = scene.resourceExtension else { return [] }
        return [
            "    /// Reads the scene file and keeps every mesh it carries, walking each node",
            "    /// before its children so the meshes line up with `partNames`.",
            "    private func loadParts() {",
            "        guard let scene = Scene(resource: \"\(escaped(name))\", withExtension: \"\(escaped(ext))\", in: .module) else {",
            "            print(\"\(className): \(escaped(name)).\(escaped(ext)) did not load\")",
            "            return",
            "        }",
            "        var found: [Mesh] = []",
            "        func visit(_ nodes: [SceneNode]) {",
            "            for node in nodes {",
            "                if let mesh = node.mesh { found.append(mesh) }",
            "                visit(node.children)",
            "            }",
            "        }",
            "        visit(scene.nodes)",
            "        for (name, mesh) in zip(Self.partNames, found) { parts[name] = mesh }",
            "    }",
            "",
            "    /// Draws one part, doing nothing if the file did not carry it.",
            "    private func drawPart(_ name: String) {",
            "        if let mesh = parts[name] { drawMesh(mesh) }",
            "    }",
        ]
    }

    // MARK: - draw()

    private static func drawBody(_ scene: ImportedScene) -> [String] {
        var lines = ["        background(Color(hex: 0x14161C))"]

        if let camera = scene.camera {
            lines.append("")
            lines.append(contentsOf: cameraCall(camera).map { "        " + $0 })
        }

        if !scene.lights.isEmpty {
            lines.append("")
            for light in scene.lights {
                lines.append(contentsOf: lightLines(light).map { "        " + $0 })
            }
        }

        for node in scene.roots where node.drawsSomething {
            lines.append("")
            lines.append(contentsOf: nodeBlock(node, indent: 2))
        }
        return lines
    }

    /// One node, as the moves that put it where the file put it. A node that
    /// makes no move and only groups is flattened away, since a block holding
    /// nothing but another block reads as noise.
    static func nodeBlock(_ node: ImportedSceneNode, indent: Int) -> [String] {
        let pad = String(repeating: "    ", count: indent)
        let moves = moveCalls(node)
        let children = node.children.filter(\.drawsSomething)

        if moves.isEmpty && node.part == nil {
            return children.flatMap { nodeBlock($0, indent: indent) }
        }

        var lines: [String] = []
        if !node.name.isEmpty { lines.append("\(pad)// \(comment(node.name))") }
        if let note = node.note { lines.append("\(pad)// \(comment(note))") }

        if moves.isEmpty {
            // Nothing to scope, so the part is drawn where it stands.
            if let part = node.part { lines.append("\(pad)drawPart(\"\(escaped(part))\")") }
            lines.append(contentsOf: children.flatMap { nodeBlock($0, indent: indent) })
            return lines
        }

        lines.append("\(pad)withState {")
        for move in moves { lines.append("\(pad)    \(move)") }
        if let part = node.part { lines.append("\(pad)    drawPart(\"\(escaped(part))\")") }
        for child in children {
            lines.append(contentsOf: nodeBlock(child, indent: indent + 1))
        }
        lines.append("\(pad)}")
        return lines
    }

    private static func moveCalls(_ node: ImportedSceneNode) -> [String] {
        var moves: [String] = []
        if let t = node.translation {
            moves.append("translate(\(num(t.x)), \(num(t.y)), \(num(t.z)))")
        }
        if let r = node.rotation {
            moves.append(rotationCall(r))
        }
        if let s = node.scale {
            // Always the three-argument form: the one-argument `scale` is the 2D
            // one, and it would silently leave z alone.
            moves.append("scale(\(num(s.x)), \(num(s.y)), \(num(s.z)))")
        }
        return moves
    }

    /// A turn about a world axis reads better as the call named after that axis,
    /// which is how a person would have written it. A turn about the negative
    /// axis is the same turn the other way, so it keeps the named call and takes
    /// the sign instead.
    static func rotationCall(_ r: ImportedRotation) -> String {
        let axis = r.axis
        let square = 0.0001
        func aligned(_ value: Double, _ others: (Double, Double)) -> Bool {
            abs(abs(value) - 1) < square && abs(others.0) < square && abs(others.1) < square
        }
        if aligned(axis.x, (axis.y, axis.z)) {
            return "rotateX(\(num(axis.x > 0 ? r.angle : -r.angle)))"
        }
        if aligned(axis.y, (axis.x, axis.z)) {
            return "rotateY(\(num(axis.y > 0 ? r.angle : -r.angle)))"
        }
        if aligned(axis.z, (axis.x, axis.y)) {
            return "rotateZ(\(num(axis.z > 0 ? r.angle : -r.angle)))"
        }
        return "rotate(\(num(r.angle)), axis: \(vector(axis)))"
    }

    // MARK: - Camera and lights

    static func cameraCall(_ camera: ImportedCamera) -> [String] {
        var lines = ["camera(Camera3D("]
        lines.append("    eye: \(vector(camera.eye)),")
        lines.append("    target: \(vector(camera.target)),")
        lines.append("    up: \(vector(camera.up)),")
        lines.append("    near: \(num(camera.near)), far: \(num(camera.far)),")
        switch camera.projection {
        case .perspective(let fov):
            lines.append("    projection: .perspective(fieldOfView: \(num(fov)))))")
        case .orthographic(let height):
            lines.append("    projection: .orthographic(height: \(num(height)))))")
        }
        return lines
    }

    /// One light, over as many lines as its factory needs.
    ///
    /// A light with a place, a direction and a shape runs past any sensible line
    /// length as one call, so each argument after the first gets its own line,
    /// the way the camera above is written.
    static func lightLines(_ light: ImportedLight) -> [String] {
        let color = "Color(hex: \(hex(light.colorHex)))"
        let intensity = "intensity: \(num(light.intensity))"

        var name = ""
        var arguments: [String] = []
        switch light.kind {
        case .directional:
            name = "directional"
            arguments = ["direction: \(vector(light.direction))", intensity]
        case .point:
            name = "point"
            arguments = ["at: \(vector(light.position))", intensity]
        case .spot:
            name = "spot"
            arguments = ["at: \(vector(light.position))",
                         "direction: \(vector(light.direction))",
                         "coneAngle: \(num(light.coneAngle))",
                         "penumbra: \(num(light.penumbra))", intensity]
        case .rectangle:
            name = "rectangle"
            arguments = ["at: \(vector(light.position))",
                         "direction: \(vector(light.direction))",
                         "width: \(num(light.width))", "height: \(num(light.height))",
                         "up: \(vector(light.up))", "isTwoSided: \(light.isTwoSided)", intensity]
        case .disk:
            name = "disk"
            arguments = ["at: \(vector(light.position))",
                         "direction: \(vector(light.direction))",
                         "radius: \(num(light.radius))",
                         "isTwoSided: \(light.isTwoSided)", intensity]
        case .tube:
            name = "tube"
            arguments = ["from: \(vector(light.endA))", "to: \(vector(light.endB))",
                         "radius: \(num(light.radius))", intensity]
        }

        let head = "light(.\(name)(\(color),"
        let indent = String(repeating: " ", count: 6 + name.count + 2)
        var lines = [head]
        for (index, argument) in arguments.enumerated() {
            let last = index == arguments.count - 1
            lines.append(indent + argument + (last ? "))" : ","))
        }
        return lines
    }

    // MARK: - Spelling numbers

    static func vector(_ v: ImportedVector) -> String {
        "Vector3(\(num(v.x)), \(num(v.y)), \(num(v.z)))"
    }

    /// A number as a person would type it: no more precision than a scene needs,
    /// and no trailing zeros to read past.
    static func num(_ value: Double) -> String {
        guard value.isFinite else { return "0" }
        let rounded = (value * 10_000).rounded() / 10_000
        if rounded == 0 { return "0" }
        if rounded == rounded.rounded() && abs(rounded) < 1e15 {
            return String(Int(rounded))
        }
        var text = String(format: "%.4f", rounded)
        while text.hasSuffix("0") { text.removeLast() }
        if text.hasSuffix(".") { text.removeLast() }
        return text
    }

    static func hex(_ value: Int) -> String {
        String(format: "0x%06X", value & 0xFFFFFF)
    }

    /// A comment cannot carry a line break, and a name from a file might.
    static func comment(_ text: String) -> String {
        text.replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\r", with: " ")
    }

    static func escaped(_ text: String) -> String {
        text.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: " ")
    }
}
