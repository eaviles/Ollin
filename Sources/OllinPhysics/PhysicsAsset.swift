import Foundation
import Ollin

/// A piece of geometry a snapshot names rather than holds.
///
/// Most of what a world is made of is small: a box is three numbers, a joint is
/// a point and an axis. Two things are not. A `.mesh` or `.heightfield`
/// collider carries every vertex of whatever it was cut from, and a soft body
/// carries the mesh it was built out of. A world that colliders a loaded set
/// piece writes that whole set piece into every snapshot of it.
///
/// So give the geometry a name and hand the snapshot that instead:
///
/// ```swift
/// let island = world.addBody(.heightfield(terrain, width: 60, depth: 60,
///                                         height: 8), at: .zero, kind: .static)
/// island.assetName = "island"
/// ```
///
/// and say what the names mean when the world comes back:
///
/// ```swift
/// world.restore(saved) { name in
///     name == "island" ? .heightfield(terrain) : nil
/// }
/// ```
///
/// The sketch stays the source of truth about where its assets live, which is
/// the same reason `resource:in:` will not guess a bundle for you. Naming is
/// opt-in for the same reason it is worth having: a snapshot that names nothing
/// is a file you can commit beside a sketch and open anywhere, and that is the
/// right default.
public enum PhysicsAsset: Sendable {
    /// The triangles of a `.mesh` collider, or a soft body's source surface.
    case mesh(Mesh)
    /// The samples of a `.heightfield` collider. How the field is sized in the
    /// world travels in the snapshot, since that is three numbers rather than
    /// geometry.
    case heightfield(Heightfield)

    var mesh: Mesh? {
        if case .mesh(let mesh) = self { return mesh }
        return nil
    }

    var heightfield: Heightfield? {
        if case .heightfield(let field) = self { return field }
        return nil
    }
}

/// What a snapshot says a name it declines to hold *was*, so a name that now
/// resolves to something else can be spotted rather than quietly restored into
/// a pose that no longer fits it.
///
/// It is deliberately cheap: how many pieces the geometry had, and a hash of
/// the numbers themselves. That catches a file swapped, re-exported, or edited
/// under a saved pose, which is the mistake worth catching.
///
/// Counts and bounds alone were the first draft and are *blind* to the case
/// that matters most: `Heightfield.diamondSquare` normalizes to 0…1, so two
/// terrains grown from different seeds have identical counts and identical
/// bounds and are not remotely the same ground. Hashing the samples costs the
/// same walk and actually answers the question.
struct AssetFingerprint: Equatable {
    var pieces: Int
    var parts: Int
    var hash: UInt64

    init(pieces: Int, parts: Int, hash: UInt64) {
        self.pieces = pieces
        self.parts = parts
        self.hash = hash
    }

    init(of asset: PhysicsAsset) {
        switch asset {
        case .mesh(let mesh):
            self.init(of: mesh)
        case .heightfield(let field):
            var hash = Hash()
            for value in field.values { hash.add(value) }
            self.init(pieces: field.columns * field.rows, parts: field.columns,
                      hash: hash.value)
        }
    }

    init(of mesh: Mesh) {
        var hash = Hash()
        for point in mesh.positions {
            hash.add(point.x)
            hash.add(point.y)
            hash.add(point.z)
        }
        for index in mesh.indices { hash.add(UInt64(index)) }
        self.init(pieces: mesh.positions.count, parts: mesh.indices.count,
                  hash: hash.value)
    }

    /// Whether two fingerprints describe the same geometry.
    func matches(_ other: AssetFingerprint) -> Bool {
        pieces == other.pieces && parts == other.parts && hash == other.hash
    }

    /// FNV-1a over the geometry's own numbers, the same hash the snapshot's
    /// own checksum uses.
    private struct Hash {
        var value: UInt64 = 0xcbf2_9ce4_8422_2325

        mutating func add(_ number: Double) { add(number.bitPattern) }

        mutating func add(_ bits: UInt64) {
            var remaining = bits
            for _ in 0 ..< 8 {
                value ^= remaining & 0xFF
                value &*= 0x1000_0000_01b3
                remaining >>= 8
            }
        }
    }
}

/// Says what a name means when a world comes back. Return `nil` for a name you
/// do not recognise, and whatever it named is left out of the restored world
/// with a note rather than failing the whole restore.
public typealias PhysicsAssetResolver = (String) -> PhysicsAsset?
