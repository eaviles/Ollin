import Foundation

/// A point or a direction, in plain numbers.
///
/// This library never links the framework, so it cannot name `Vector3`. It
/// prints one instead.
public struct ImportedVector: Sendable, Hashable {
    public var x: Double
    public var y: Double
    public var z: Double

    public init(_ x: Double, _ y: Double, _ z: Double) {
        self.x = x
        self.y = y
        self.z = z
    }

    public static let zero = ImportedVector(0, 0, 0)
    public static let one = ImportedVector(1, 1, 1)
}

/// A turn of `angle` radians about `axis`, the form `rotate(_:axis:)` takes.
public struct ImportedRotation: Sendable, Hashable {
    public var angle: Double
    public var axis: ImportedVector

    public init(angle: Double, axis: ImportedVector) {
        self.angle = angle
        self.axis = axis
    }
}

/// One node of a scene, reduced to what a sketch would write to put it there.
///
/// A node keeps its children, so the emitted sketch nests the same way the file
/// does and a group still turns as one thing.
public struct ImportedSceneNode: Sendable {
    /// The node's authored name, used as the comment above its block.
    public var name: String
    /// The key its mesh is stored under, or nil for a node that only groups.
    public var part: String?
    /// Each move, left out when the node does not make it.
    public var translation: ImportedVector?
    public var rotation: ImportedRotation?
    public var scale: ImportedVector?
    public var children: [ImportedSceneNode]
    /// Something about this node the reader should know, written above its block.
    public var note: String?

    public init(name: String, part: String? = nil,
                translation: ImportedVector? = nil, rotation: ImportedRotation? = nil,
                scale: ImportedVector? = nil, children: [ImportedSceneNode] = [],
                note: String? = nil) {
        self.name = name
        self.part = part
        self.translation = translation
        self.rotation = rotation
        self.scale = scale
        self.children = children
        self.note = note
    }

    /// Whether this node puts anything on the page. A node with no geometry, no
    /// move and no drawing child is not worth a block.
    public var drawsSomething: Bool {
        part != nil || children.contains { $0.drawsSomething }
    }
}

/// A camera the file authored.
public struct ImportedCamera: Sendable {
    /// Mirrors `Camera3D.Projection`, minus the intrinsic case, which comes from
    /// a depth camera rather than from a scene file.
    public enum Projection: Sendable, Hashable {
        case perspective(fieldOfView: Double)
        case orthographic(height: Double)
    }

    public var eye: ImportedVector
    public var target: ImportedVector
    public var up: ImportedVector
    public var near: Double
    public var far: Double
    public var projection: Projection

    public init(eye: ImportedVector, target: ImportedVector, up: ImportedVector,
                near: Double, far: Double, projection: Projection) {
        self.eye = eye
        self.target = target
        self.up = up
        self.near = near
        self.far = far
        self.projection = projection
    }
}

/// A light the file authored, already resolved to world space.
public struct ImportedLight: Sendable {
    public enum Kind: Sendable, Hashable {
        case directional, point, spot, rect, disk, tube
    }

    public var kind: Kind
    /// The color as `0xRRGGBB`, which is how a sketch spells one.
    public var colorHex: Int
    public var intensity: Double
    public var position: ImportedVector
    public var direction: ImportedVector
    public var coneAngle: Double
    public var penumbra: Double
    public var width: Double
    public var height: Double
    public var radius: Double
    /// Which way is up for a rect panel, orienting its height axis.
    public var up: ImportedVector
    /// Whether both faces of a panel emit.
    public var twoSided: Bool
    /// A tube light runs between two points rather than sitting at one, so it
    /// carries the pair its factory asks for.
    public var endA: ImportedVector
    public var endB: ImportedVector

    public init(kind: Kind, colorHex: Int, intensity: Double,
                position: ImportedVector = .zero, direction: ImportedVector = ImportedVector(0, -1, 0),
                coneAngle: Double = 0.5, penumbra: Double = 0.2,
                width: Double = 1, height: Double = 1, radius: Double = 0.5,
                up: ImportedVector = ImportedVector(0, 1, 0), twoSided: Bool = false,
                endA: ImportedVector = .zero, endB: ImportedVector = .zero) {
        self.kind = kind
        self.colorHex = colorHex
        self.intensity = intensity
        self.position = position
        self.direction = direction
        self.coneAngle = coneAngle
        self.penumbra = penumbra
        self.width = width
        self.height = height
        self.radius = radius
        self.up = up
        self.twoSided = twoSided
        self.endA = endA
        self.endB = endB
    }
}

/// A 3D scene read out of a file, in the form a sketch would have been written
/// in if somebody had typed it.
///
/// The split is deliberate. Everything that is *structure* becomes source: the
/// camera, the lights, and where each part sits. The geometry stays in the
/// file, because a mesh is not something a person edits as text. So the sketch
/// loads the file for its meshes alone and places them itself.
public struct ImportedScene: Sendable {
    /// The scene file the sketch reads its geometry from, without its extension.
    /// Nil when the scene carried no mesh at all, and the sketch needs no asset.
    public var resourceName: String?
    public var resourceExtension: String?
    /// The scene file on disk, copied in beside the sketch when there is
    /// geometry to carry. Nil leaves the project self-contained.
    public var sourceFile: URL?
    /// The file the sketch's own comment names.
    public var origin: String?
    public var camera: ImportedCamera?
    public var lights: [ImportedLight]
    public var roots: [ImportedSceneNode]
    /// The keys of every mesh, in the order the file lists them. The generated
    /// sketch writes this list out, so the names in `draw()` mean something even
    /// where the file repeated a name or left one blank.
    public var partNames: [String]
    /// What could not come over. Written into the sketch as comments, never
    /// dropped in silence.
    public var notes: [String]

    public init(resourceName: String? = nil, resourceExtension: String? = nil,
                sourceFile: URL? = nil,
                origin: String? = nil, camera: ImportedCamera? = nil,
                lights: [ImportedLight] = [], roots: [ImportedSceneNode] = [],
                partNames: [String] = [], notes: [String] = []) {
        self.resourceName = resourceName
        self.resourceExtension = resourceExtension
        self.sourceFile = sourceFile
        self.origin = origin
        self.camera = camera
        self.lights = lights
        self.roots = roots
        self.partNames = partNames
        self.notes = notes
    }

    /// Whether the sketch has to carry the scene file with it.
    public var needsResource: Bool { resourceName != nil && !partNames.isEmpty }

    /// The file name as it lands beside the sketch.
    public var resourceFileName: String? {
        guard let resourceName, let resourceExtension else { return nil }
        return "\(resourceName).\(resourceExtension)"
    }
}
