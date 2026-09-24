import Foundation

/// A JSON value, read for drawing rather than decoded into a type.
///
/// Reach through it by name and by index, then ask for the kind you want. A key
/// that isn't there reads as null rather than stopping you, so a path can be
/// followed as far as it goes and answered at the end:
///
/// ```swift
/// let json = try! loadJSON(resource: "cities", withExtension: "json", in: .module)
/// for city in json["cities"].array {
///     let x = city["lon"].number ?? 0
///     let y = city["lat"].number ?? 0
///     drawCircle(x, y, city["size"].number ?? 4)
/// }
/// ```
///
/// Dynamic member lookup makes the dotted form work too, which reads well when
/// the keys are plain names: `json.city.name.string`.
///
/// This is the load-once material for data-driven drawing, deliberately small.
/// When a document has a shape worth naming, Foundation's `Codable` is still
/// there and is the better tool.
@dynamicMemberLookup
public enum JSON: Sendable, Equatable {
    case null
    case bool(Bool)
    case number(Double)
    case string(String)
    case array([JSON])
    case object([String: JSON])
}

// MARK: - Reaching in

public extension JSON {
    /// The value under `key`, or null when this isn't an object or holds no
    /// such key.
    subscript(key: String) -> JSON {
        guard case .object(let members) = self else { return .null }
        return members[key] ?? .null
    }

    /// The value under `key`, written as a property: `json.city.name`.
    subscript(dynamicMember key: String) -> JSON { self[key] }

    /// The element at `index`, or null when this isn't an array or is shorter
    /// than that.
    subscript(index: Int) -> JSON {
        guard case .array(let elements) = self, elements.indices.contains(index) else { return .null }
        return elements[index]
    }
}

// MARK: - Reading out

public extension JSON {
    /// The text, when this is a string.
    var text: String? {
        guard case .string(let value) = self else { return nil }
        return value
    }

    /// The number, when this is one.
    ///
    /// A string holding a number reads as that number too, since plenty of
    /// documents quote their figures.
    var number: Double? {
        switch self {
        case .number(let value): return value
        case .string(let value): return Double(value.trimmingCharacters(in: .whitespaces))
        default: return nil
        }
    }

    /// The number as a whole one, rounding a decimal; `nil` for one past what
    /// an `Int` holds.
    var int: Int? {
        number?.int(rounded: .toNearestOrAwayFromZero)
    }

    /// The flag, when this is one. A number reads as a flag the way a condition
    /// does: zero is false, anything else true.
    var bool: Bool? {
        switch self {
        case .bool(let value): return value
        case .number(let value): return value != 0
        default: return nil
        }
    }

    /// A hex color (`#ff8800`, `f80`), when this is a string holding one.
    var color: Color? {
        guard let text = text?.trimmingCharacters(in: .whitespaces), !text.isEmpty else { return nil }
        return Color(hex: text)
    }

    /// The elements, or an empty array when this isn't one, so a `for` loop over
    /// a key that isn't there runs zero times instead of needing a check.
    var array: [JSON] {
        guard case .array(let elements) = self else { return [] }
        return elements
    }

    /// The members, or an empty dictionary when this isn't an object.
    var object: [String: JSON] {
        guard case .object(let members) = self else { return [:] }
        return members
    }

    /// The keys of an object, sorted, so walking one is reproducible.
    var keys: [String] { object.keys.sorted() }

    /// How many elements an array holds, or members an object has. Zero for
    /// everything else.
    var count: Int {
        switch self {
        case .array(let elements): return elements.count
        case .object(let members): return members.count
        default: return 0
        }
    }

    /// Whether this is null. A key that isn't there answers `true` here too:
    /// a missing value and a null one are the same thing to a sketch.
    var isNull: Bool { self == .null }
}

// MARK: - Loading

public extension JSON {
    /// Read JSON from a file. Throws a `FileError`: `missing` when no file is
    /// there, `unreadable` when it is not JSON.
    ///
    /// ```swift
    /// let json = try JSON(contentsOf: "cities.json")
    /// ```
    init(contentsOf path: String) throws {
        try self.init(url: URL(fileURLWithPath: path))
    }

    /// Read JSON from a URL. A network URL blocks until it arrives, so call this
    /// in `setup()` rather than `draw()`.
    init(url: URL) throws {
        let data = try FileError.contents(of: url)
        do {
            try self.init(data: data)
        } catch let error as FileError {
            throw FileError.unreadable(url, error.problem)
        }
    }

    /// Read JSON from bytes. Throws an `unreadable` `FileError` naming where
    /// the bytes stop being JSON.
    init(data: Data) throws {
        let object: Any
        do {
            object = try JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
        } catch {
            let reason = (error as NSError).userInfo[NSDebugDescriptionErrorKey] as? String
            throw FileError.unreadable(nil, "is not JSON" + (reason.map { ": \($0)" } ?? ""))
        }
        self.init(any: object)
    }

    /// Read JSON from text already in hand.
    init(text: String) throws {
        try self.init(data: Data(text.utf8))
    }

    /// Read JSON bundled as a resource.
    ///
    /// `in:` has no default on purpose: a default would resolve to Ollin's own
    /// bundle rather than the caller's. Pass `.module` from your sketch.
    init(resource: String, withExtension ext: String? = "json", in bundle: Bundle) throws {
        try self.init(url: FileError.resource(resource, withExtension: ext, in: bundle))
    }

    /// Wrap what the system's JSON reader hands back.
    private init(any: Any) {
        switch any {
        case let number as NSNumber:
            // A JSON true arrives as an NSNumber holding 1, indistinguishable
            // from the number 1 by value; only its type tells them apart.
            if CFGetTypeID(number) == CFBooleanGetTypeID() {
                self = .bool(number.boolValue)
            } else {
                self = .number(number.doubleValue)
            }
        case let text as String:
            self = .string(text)
        case let elements as [Any]:
            self = .array(elements.map(JSON.init(any:)))
        case let members as [String: Any]:
            self = .object(members.mapValues(JSON.init(any:)))
        default:
            self = .null
        }
    }
}

// MARK: - Sketch sugar

public extension Sketch {
    /// Read a JSON file by path: `try loadJSON("cities.json")`. Throws a
    /// `FileError` when the file is not there or is not JSON. Call it in
    /// `setup()` and keep the result in a property.
    func loadJSON(_ path: String) throws -> JSON { try JSON(contentsOf: path) }

    /// Read JSON from a URL. A network URL blocks until it arrives.
    func loadJSON(_ url: URL) throws -> JSON { try JSON(url: url) }

    /// Read a JSON file bundled as a resource. Pass `.module` for the sketch's
    /// own bundle; a default here would resolve to Ollin's.
    func loadJSON(resource: String, withExtension ext: String? = "json", in bundle: Bundle) throws -> JSON {
        try JSON(resource: resource, withExtension: ext, in: bundle)
    }
}
