import Foundation

/// The raw prim/attribute tree parsed from a USD file: the internal substrate
/// the scene-building stages read. One `USDStage` holds a single flattened
/// layer, its layer metadata plus root prims, each prim carrying its metadata,
/// properties, and children in authored order.
///
/// This is deliberately *raw*: values keep the file's own shape (tuples as
/// component lists, arrays flat) and no USD semantics are applied, no
/// composition, no schema knowledge, no unit handling. Interpretation belongs
/// to the layers above.
struct USDStage: Equatable {
    /// Layer metadata from the header block: `defaultPrim`, `upAxis`,
    /// `metersPerUnit`, `timeCodesPerSecond`, and whatever else was authored.
    var metadata: [String: USDValue] = [:]
    /// Root prims in authored order.
    var prims: [USDPrim] = []
}

/// A prim: one `def`/`over`/`class` statement in text, one prim spec in crate.
struct USDPrim: Equatable {
    var name: String
    var specifier: USDSpecifier = .def
    /// The schema type name (`Xform`, `Mesh`, …); empty when the file declares none.
    var typeName: String = ""
    var metadata: [String: USDValue] = [:]
    /// Attributes in authored order.
    var attributes: [USDAttribute] = []
    /// Relationships in authored order.
    var relationships: [USDRelationship] = []
    /// Child prims in authored order.
    var children: [USDPrim] = []

    /// The first child named `name`, if any.
    func child(_ name: String) -> USDPrim? {
        children.first { $0.name == name }
    }

    /// The first attribute named `name`, if any.
    func attribute(_ name: String) -> USDAttribute? {
        attributes.first { $0.name == name }
    }

    /// The first relationship named `name`, if any.
    func relationship(_ name: String) -> USDRelationship? {
        relationships.first { $0.name == name }
    }
}

enum USDSpecifier: Equatable {
    case def, over, `class`
}

/// An attribute: declared type, optional default value, optional time samples.
struct USDAttribute: Equatable {
    var name: String
    /// The declared value type as written (`point3f[]`, `double3`, `token`);
    /// from crate files, the type token the spec carries.
    var typeName: String = ""
    var isUniform = false
    var isCustom = false
    /// The default (time-independent) value, if authored.
    var value: USDValue?
    /// Authored time samples, ascending by time.
    var timeSamples: [USDTimeSample] = []
    var metadata: [String: USDValue] = [:]
    /// Connection target paths (`attr.connect = </...>`), if authored.
    var connections: [String] = []
}

/// One time sample: a time code and the value at it.
struct USDTimeSample: Equatable {
    var time: Double
    var value: USDValue
}

/// A relationship: named target paths (`rel material:binding = </...>`).
struct USDRelationship: Equatable {
    var name: String
    var targets: [String] = []
    var metadata: [String: USDValue] = [:]
}

/// A parsed value, kept close to the file's own shape.
///
/// Tuples (vectors, quaternions, matrices) are component lists in file order;
/// tuple arrays are flat component arrays with their arity, so a `point3f[]`
/// of n points is `.floatTupleArray(3, …)` with 3n floats. Scalar widths
/// widen (half/float to the scalar `double`; every int width to `int`/`uint`),
/// but float-typed *arrays* stay `Float` so bulk geometry keeps its exact
/// bits for cross-checking. A type the parser doesn't decode is recorded as
/// `.unsupported(typeName)` and parsing continues, never a throw.
indirect enum USDValue: Equatable {
    case bool(Bool)
    case int(Int64)
    case uint(UInt64)
    case double(Double)
    case string(String)
    case token(String)
    case asset(String)
    case path(String)
    /// A fixed-arity tuple (vec2/3/4, quat, matrix) as components in file order.
    case tuple([Double])
    case boolArray([Bool])
    case intArray([Int64])
    case floatArray([Float])
    case doubleArray([Double])
    case stringArray([String])
    case tokenArray([String])
    case assetArray([String])
    case pathArray([String])
    /// An array of fixed-arity float tuples, flattened: (arity, components).
    case floatTupleArray(Int, [Float])
    /// An array of fixed-arity double tuples, flattened: (arity, components).
    case doubleTupleArray(Int, [Double])
    case dictionary([String: USDValue])
    /// Time-sampled data decoded at the value level (crate's TimeSamples value);
    /// attribute assembly lifts it onto `USDAttribute.timeSamples`.
    case timeSamples([USDTimeSample])
    /// An authored value block (`None`).
    case block
    /// A value of a type this parser doesn't decode; the type name is kept.
    case unsupported(String)
}

enum USDError: Error, CustomStringConvertible {
    /// The bytes match none of the three containers (usda/usdc/usdz).
    case unrecognizedFormat
    /// A structural problem in the file, with a short description.
    case malformed(String)
    /// A crate version outside the supported 0.8…0.10 range.
    case unsupportedVersion(String)

    var description: String {
        switch self {
        case .unrecognizedFormat: "not a USD file (expected usda text, usdc crate, or usdz package)"
        case .malformed(let why): "malformed USD file: \(why)"
        case .unsupportedVersion(let v): "unsupported usdc crate version \(v) (supported: 0.8-0.10)"
        }
    }
}
