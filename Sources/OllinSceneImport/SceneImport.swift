import Foundation
import Ollin
import OllinProjects

/// Reads a 3D scene file into the plain description the project generator emits
/// source from.
///
/// The split is what keeps `OllinProjects` free of the framework: this target
/// has both, does the reading, and hands over numbers. Everything it knows about
/// scenes comes from the shipped loader, so a format Ollin can open is a format
/// the generator can start a project from.
public enum SceneImport {

    /// Reads `url` and describes it. Returns nil when the file will not open,
    /// which is the caller's cue to say so rather than write an empty project.
    public static func read(_ url: URL) -> ImportedScene? {
        guard let scene = Scene(contentsOf: url) else { return nil }
        return describe(scene, from: url)
    }

    static func describe(_ scene: Scene, from url: URL) -> ImportedScene {
        var names = PartNamer()
        let roots = scene.nodes.map { node(from: $0, names: &names) }

        let hasGeometry = !names.assigned.isEmpty
        let stem = url.deletingPathExtension().lastPathComponent
        let ext = url.pathExtension

        var notes: [String] = []
        let losses = scene.importLosses
        if losses.animations > 0 {
            notes.append(count(losses.animations, "keyframe track", "keyframe tracks")
                + " came with the file and are not written out here. To play one, load the "
                + "scene whole and use drawScene(scene) with apply(_:at:).")
        }
        if losses.skinnedNodes > 0 {
            notes.append(count(losses.skinnedNodes, "part is", "parts are")
                + " posed by a skeleton in the file. Placed by hand, "
                + (losses.skinnedNodes == 1 ? "it draws" : "they draw") + " in the bind pose.")
        }
        if losses.morphedNodes > 0 {
            notes.append(count(losses.morphedNodes, "part carries", "parts carry")
                + " blend shapes, which nothing here drives.")
        }
        if losses.multiMaterialNodes > 0 {
            notes.append(count(losses.multiMaterialNodes, "part wears", "parts wear")
                + " more than one material. Drawn whole, "
                + (losses.multiMaterialNodes == 1 ? "it wears" : "they wear") + " the first.")
        }
        if names.sheared > 0 {
            notes.append(count(names.sheared, "part has a transform", "parts have transforms")
                + " that translate, rotate and scale cannot reproduce. The block below carries "
                + "the closest fit, and the part is marked.")
        }

        var described = ImportedScene(
            resourceName: hasGeometry ? stem : nil,
            resourceExtension: hasGeometry ? ext : nil,
            sourceFile: hasGeometry ? url : nil,
            origin: "Made from \(url.lastPathComponent).",
            camera: camera(of: scene, notes: &notes),
            lights: scene.lights.map(light(from:)),
            roots: roots,
            partNames: names.assigned,
            notes: notes)

        // A material rides its mesh, so writing a fill here would tint what the
        // file already colored. Said once, rather than per part.
        if hasGeometry {
            described.notes.append("Each part keeps the material the file gave it. Call fill or "
                + "material inside a block to override one.")
        }

        return described
    }

    // MARK: - Nodes

    /// Hands out one name per mesh, in the order the tree lists them, and keeps
    /// the tally the generated sketch's own walk has to agree with.
    struct PartNamer {
        var assigned: [String] = []
        var taken: Set<String> = []
        var sheared = 0

        mutating func name(for raw: String) -> String {
            let base = raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "part" : raw
            var candidate = base
            var next = 2
            while taken.contains(candidate) {
                candidate = "\(base)-\(next)"
                next += 1
            }
            taken.insert(candidate)
            assigned.append(candidate)
            return candidate
        }
    }

    static func node(from node: SceneNode, names: inout PartNamer) -> ImportedSceneNode {
        let placement = node.placement

        // A mesh is claimed before the children are walked, which is the order
        // the generated loader reads them in.
        var part: String?
        if node.mesh != nil { part = names.name(for: node.name) }

        // A note goes on the block it belongs to, so the reader meets it where it
        // matters rather than only in the header.
        var reasons: [String] = []
        if !placement.isExact {
            names.sheared += 1
            reasons.append("the file's transform for this one does not reduce to these three moves")
        }
        if node.wearsSeveralMaterials {
            reasons.append("several materials in the file; drawn whole, it wears the first")
        }
        let note = reasons.isEmpty ? nil : reasons.joined(separator: "; ")

        let children = node.children.map { child in
            self.node(from: child, names: &names)
        }

        // A move too small to see is a move nobody typed. The numbers are printed
        // to four places, so anything under half of that would print as a call
        // that does nothing.
        let quiet = 0.00005
        let movesAt = abs(placement.translation.x) > quiet || abs(placement.translation.y) > quiet
            || abs(placement.translation.z) > quiet
        let resized = abs(placement.scale.x - 1) > quiet || abs(placement.scale.y - 1) > quiet
            || abs(placement.scale.z - 1) > quiet

        return ImportedSceneNode(
            name: node.name,
            part: part,
            translation: movesAt ? vector(placement.translation) : nil,
            rotation: abs(placement.angle) > quiet
                ? ImportedRotation(angle: placement.angle, axis: vector(placement.axis))
                : nil,
            scale: resized ? vector(placement.scale) : nil,
            children: children,
            note: note)
    }

    // MARK: - Camera

    /// The file's first camera, or one worked out from the scene's own size when
    /// it carried none. A sketch that opens on nothing is no use to anybody.
    static func camera(of scene: Scene, notes: inout [String]) -> ImportedCamera? {
        if let authored = scene.camera {
            var projection = ImportedCamera.Projection.perspective(fieldOfView: .pi / 3)
            switch authored.projection {
            case .perspective(let fieldOfView):
                projection = .perspective(fieldOfView: fieldOfView)
            case .orthographic(let height):
                projection = .orthographic(height: height)
            case .intrinsic:
                notes.append("The file's camera is a measured lens, which does not carry over. "
                    + "The one below frames the scene instead.")
                return framing(scene)
            }
            return ImportedCamera(eye: vector(authored.eye), target: vector(authored.target),
                                  up: vector(authored.up), near: authored.near, far: authored.far,
                                  projection: projection)
        }
        guard let framed = framing(scene) else { return nil }
        notes.append("The file carried no camera, so the one below frames what it holds.")
        return framed
    }

    /// A camera far enough back to hold the whole scene, looking slightly down.
    static func framing(_ scene: Scene) -> ImportedCamera? {
        let bounds = scene.bounds
        let span = bounds.size
        guard span.length > 0 else { return nil }

        let center = bounds.center
        let radius = span.length / 2
        // Far enough that the bounding sphere sits inside a 60 degree view, with
        // room to spare so nothing grazes the edge.
        let distance = radius * 2.6
        let direction = Vector3(0.55, 0.42, 1).normalized
        let eye = center + direction * distance

        return ImportedCamera(eye: vector(eye), target: vector(center), up: vector(.unitY),
                              near: Swift.max(0.01, radius / 100),
                              far: Swift.max(10, distance + radius * 4),
                              projection: .perspective(fieldOfView: .pi / 3))
    }

    // MARK: - Lights

    static func light(from light: Light) -> ImportedLight {
        let kind: ImportedLight.Kind
        switch light.kind {
        case .directional: kind = .directional
        case .point: kind = .point
        case .spot: kind = .spot
        case .rectangle: kind = .rectangle
        case .disk: kind = .disk
        case .tube: kind = .tube
        }

        // A tube is stored as a midpoint, a direction along its length, and that
        // length, which is what its own factory folded the two ends into.
        let half = light.direction.normalized * (light.length / 2)
        return ImportedLight(
            kind: kind,
            colorHex: hex(light.color),
            intensity: light.intensity,
            position: vector(light.position),
            direction: vector(light.direction),
            coneAngle: light.coneAngle,
            penumbra: light.penumbra,
            width: light.width,
            height: light.height,
            radius: light.radius,
            up: vector(light.up),
            isTwoSided: light.isTwoSided,
            endA: vector(light.position - half),
            endB: vector(light.position + half))
    }

    // MARK: - Plain numbers

    static func vector(_ v: Vector3) -> ImportedVector {
        ImportedVector(v.x, v.y, v.z)
    }

    /// A color as the `0xRRGGBB` a sketch would type. Alpha is dropped, since a
    /// light has none.
    static func hex(_ color: Color) -> Int {
        func channel(_ value: Double) -> Int {
            Int((Swift.min(1, Swift.max(0, value)) * 255).rounded())
        }
        return channel(color.red) << 16 | channel(color.green) << 8 | channel(color.blue)
    }

    static func count(_ n: Int, _ one: String, _ many: String) -> String {
        n == 1 ? "One \(one)" : "\(n) \(many)"
    }
}
