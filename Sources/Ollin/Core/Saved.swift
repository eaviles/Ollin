import Foundation

/// A property that survives a relaunch: mark the state a piece would hate to
/// lose, and a checkpoint writes it down and puts it back.
///
/// ```swift
/// final class Reef: Sketch {
///     @Saved var polyps: [Vector2] = []
///     @Saved var generation = 0
///
///     override var installation: Installation { Installation(checkpoint: .every(60)) }
/// }
/// ```
///
/// A piece that has been growing for three days is not reproducible from its
/// seed in any practical sense: getting back there means running the three days
/// again. So the state itself is written to a file, and a relaunch picks the
/// piece up where it was rather than starting it over.
///
/// Anything `Codable` can be saved, which covers the ordinary shapes a sketch
/// keeps: numbers, strings, arrays, dictionaries, and your own structs and enums
/// once you mark them `Codable`. Ollin's small value types (``Vector2``,
/// ``Vector3``, ``Color``, ``Rectangle``, ``Insets``) already are.
///
/// What cannot be saved this way is anything living on the GPU: an accumulated
/// canvas, a feedback layer, a simulation field, a compute buffer. Those are
/// textures the framework owns, and a checkpoint does not reach them.
///
/// Values are matched by property name. Rename a property and its old value is
/// left behind; change its type and the stale value is dropped, so the fresh
/// default wins rather than a decode failure taking the whole checkpoint with
/// it. See `Docs/Output/Installation.md`.
@propertyWrapper
public final class Saved<Value: Codable>: SavedProperty {
    public var wrappedValue: Value

    public init(wrappedValue: Value) {
        self.wrappedValue = wrappedValue
    }

    /// The property itself, via `$polyps`.
    public var projectedValue: Saved<Value> { self }

    public func encodedValue() throws -> Data {
        try JSONEncoder().encode(wrappedValue)
    }

    public func decodeValue(from data: Data) throws {
        wrappedValue = try JSONDecoder().decode(Value.self, from: data)
    }
}

/// The type-erased face of a ``Saved`` property, so a checkpoint can walk a
/// sketch's saved state without knowing any of its types.
///
/// Each property carries its own value across as JSON rather than handing out an
/// `Encoder`, which keeps every property's success or failure its own: one that
/// will not decode is named and skipped, and the rest of the state still lands.
public protocol SavedProperty: AnyObject {
    func encodedValue() throws -> Data
    func decodeValue(from data: Data) throws
}

/// One discovered `@Saved` property: the name it is stored under, and the
/// property itself.
public struct SavedHandle {
    /// The property name, which is the key it is written under. Stable across
    /// runs, which is what lets a value find its way back.
    public let name: String
    public let property: any SavedProperty
}

public extension Sketch {
    /// The `@Saved` properties declared on this sketch, found by reflection, the
    /// same walk `parameters()` makes. A checkpoint uses this; a sketch rarely
    /// calls it.
    func savedProperties() -> [SavedHandle] {
        var handles: [SavedHandle] = []
        var mirror: Mirror? = Mirror(reflecting: self)
        while let current = mirror {
            for child in current.children {
                guard let property = child.value as? any SavedProperty,
                      let storageName = child.label else { continue }
                // Property-wrapper storage is named `_polyps`; strip the underscore.
                let name = storageName.hasPrefix("_") ? String(storageName.dropFirst()) : storageName
                handles.append(SavedHandle(name: name, property: property))
            }
            mirror = current.superclassMirror
        }
        return handles
    }
}
