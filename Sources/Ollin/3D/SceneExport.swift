import Foundation

/// The file formats a `Scene` can be written as.
///
/// Both are USD, the format Apple's platforms read directly: a model in one of
/// these opens in Quick Look from the Finder or a message, stands on a table
/// through AR, and drops straight into a visionOS app.
public enum SceneFileFormat: Sendable, CaseIterable {

    /// A `.usda` layer: the scene as readable text, one file. Good for looking
    /// at what was written, diffing two exports, or handing to a tool. It has
    /// nowhere to keep an image, so textures are left out with a note.
    case usda

    /// A `.usdz` package: the layer and its textures in one file. This is the
    /// one to send someone, and the only one AR Quick Look opens.
    case usdz

    /// The lowercase file extension this format is written with.
    public var fileExtension: String {
        switch self {
        case .usda: "usda"
        case .usdz: "usdz"
        }
    }

    /// The format a file extension names, or `nil` for one neither uses.
    /// Case-insensitive, and a leading dot is fine.
    public init?(fileExtension: String) {
        let ext = fileExtension.hasPrefix(".")
            ? String(fileExtension.dropFirst()).lowercased()
            : fileExtension.lowercased()
        switch ext {
        case "usda", "usd": self = .usda
        case "usdz": self = .usdz
        default: return nil
        }
    }
}

// MARK: - Writing

public extension Scene {

    /// This scene encoded in `format`, ready to write or hand on.
    ///
    /// `metersPerUnit` says how big one scene unit is, and it is a declaration
    /// rather than a scaling: the numbers are written as they stand, and this
    /// tells a viewer how to read them. The default of 1 makes a sphere of
    /// radius 1 a two-meter ball, which is right for a sculpture and much too
    /// big for something meant to sit on a desk. Pass `0.01` and the same
    /// sphere is two centimeters across.
    ///
    /// ```swift
    /// let data = scene.data(as: .usdz, metersPerUnit: 0.01)
    /// ```
    func data(as format: SceneFileFormat, metersPerUnit: Double = 1) -> Data {
        var writer = USDSceneWriter(metersPerUnit: metersPerUnit,
                                    carriesTextures: format == .usdz)
        let layer = writer.layer(for: self)
        for note in writer.notes { print("Ollin: \(note)") }
        switch format {
        case .usda:
            return Data(layer.utf8)
        case .usdz:
            // The layer goes in first: a package is presented as whichever usd
            // file it holds first, and everything else hangs off that one.
            var entries: [(name: String, data: Data)] = [("scene.usda", Data(layer.utf8))]
            entries += writer.textures
            // A package is read in place rather than unpacked, which is why the
            // spec asks for no compression and 64-byte boundaries.
            return ZipWriter.package(entries, stored: true, alignment: 64)
        }
    }

    /// Write this scene to `url` as a spatial model, in the format its
    /// extension names (`.usda`, `.usdz`) or the one you pass. Returns whether
    /// it was written; a failure prints what went wrong rather than trapping,
    /// like the loaders.
    ///
    /// The writing counterpart of `Scene(contentsOf:)`, and the way a 3D sketch
    /// leaves as something spatial instead of a flat frame: a `.usdz` opens in
    /// Quick Look, stands in the room through AR, and can be sent in a message.
    ///
    /// ```swift
    /// scene.write(to: "piece.usdz", metersPerUnit: 0.01)
    /// ```
    ///
    /// What travels: the node tree with its transforms, each node's geometry
    /// with its normals, texture coordinates, and per-vertex colors, the
    /// surfaces as preview-surface materials, and the scene's cameras and
    /// lights. What does not: animation and skinning (one pose is written, the
    /// one the scene is holding), and the parts of an Ollin finish the format
    /// has no slot for. Anything left behind says so once.
    @discardableResult
    func write(to url: URL, as format: SceneFileFormat? = nil,
               metersPerUnit: Double = 1) -> Bool {
        guard let format = format ?? SceneFileFormat(fileExtension: url.pathExtension) else {
            print("Ollin: don't know what format to write '\(url.lastPathComponent)' as. Use .usdz or .usda, or pass one explicitly.")
            return false
        }
        do {
            try data(as: format, metersPerUnit: metersPerUnit).write(to: url)
            return true
        } catch {
            print("Ollin: couldn't write '\(url.path)': \(error.localizedDescription)")
            return false
        }
    }

    /// Write this scene to a file `path`. Sugar over `write(to:)`.
    @discardableResult
    func write(to path: String, as format: SceneFileFormat? = nil,
               metersPerUnit: Double = 1) -> Bool {
        write(to: URL(fileURLWithPath: path), as: format, metersPerUnit: metersPerUnit)
    }
}

public extension Sketch {

    /// Write `scene` to a file as a spatial model, in the format the extension
    /// names (`.usdz`, `.usda`). Sugar over `Scene.write(to:)`, the writing
    /// counterpart of `loadScene` and the spatial sibling of `saveMesh`.
    ///
    /// ```swift
    /// saveScene(scene, to: "piece.usdz", metersPerUnit: 0.01)
    /// ```
    @discardableResult
    func saveScene(_ scene: Scene, to path: String, as format: SceneFileFormat? = nil,
                   metersPerUnit: Double = 1) -> Bool {
        scene.write(to: path, as: format, metersPerUnit: metersPerUnit)
    }
}
