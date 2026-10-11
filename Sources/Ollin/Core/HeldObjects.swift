import Foundation

extension Sketch {
    /// Everything of one kind this sketch is holding: in its stored properties,
    /// and inside what those hold.
    ///
    /// The sketch's own values are found by reflection, the way its parameters
    /// are. A sketch keeps its instruments and its eased values wherever its
    /// own structure puts them, so the reading goes into optionals, structs,
    /// enums, tuples, arrays, sets, and dictionaries, and into objects of
    /// classes the sketch's own module declares. Four rules keep that
    /// affordable and honest:
    ///
    /// - The sketch's own properties come first, in the order they are
    ///   declared, so a sketch holding two instruments directly mixes them
    ///   exactly as it always did.
    /// - An object is found once, however many places hold it, and is never
    ///   looked into twice.
    /// - A framework object is never looked into: the framework's half of the
    ///   sketch is read one level deep as it always was, and a physics world,
    ///   a mesh, or a drawer holds nothing a sketch declared.
    /// - A collection is read through its first element. When that element
    ///   holds no object anywhere inside it, the rest are taken to be alike
    ///   and skipped, which is what keeps a million points from costing a
    ///   million looks. A list whose first element is plain and a later one
    ///   is not is the one shape this does not read.
    ///
    /// The pending values sit on a list rather than the call stack, since the
    /// depth is the sketch's data, and the reading stops after `limit` values.
    func heldObjects<T>(of kind: T.Type, limit: Int = 200_000) -> [T] {
        var found: [T] = []
        var seen: Set<ObjectIdentifier> = [ObjectIdentifier(self)]
        /// A value still to look at, and whether what it holds is looked at too.
        var pending: [(value: Any, deep: Bool)] = []
        let frameworkModule = Self.moduleName(of: Sketch.self)
        let ownModule = Self.moduleName(of: type(of: self))
        var mirror: Mirror? = Mirror(reflecting: self)
        while let current = mirror {
            let deep = Self.moduleName(of: current.subjectType) != frameworkModule
            for child in current.children { pending.append((child.value, deep)) }
            mirror = current.superclassMirror
        }

        var next = 0
        while next < pending.count, next < limit {
            let (value, deep) = pending[next]
            next += 1
            if let match = value as? T {
                let id = ObjectIdentifier(match as AnyObject)
                if seen.insert(id).inserted { found.append(match) }
                continue
            }
            guard deep else { continue }
            let inside = Mirror(reflecting: value)
            switch inside.displayStyle {
            case .optional, .struct, .tuple, .enum:
                for child in inside.children { pending.append((child.value, true)) }
            case .class:
                guard seen.insert(ObjectIdentifier(value as AnyObject)).inserted,
                      Self.moduleName(of: inside.subjectType) == ownModule else { continue }
                for child in inside.children { pending.append((child.value, true)) }
            case .collection, .set, .dictionary:
                guard let first = inside.children.first?.value, Self.mayHoldAnObject(first) else { continue }
                for child in inside.children { pending.append((child.value, true)) }
            default:
                continue
            }
        }
        return found
    }

    /// Whether a value holds an object anywhere inside it, read through its
    /// structs, optionals, enums, tuples, and collections, up to a bound; past
    /// the bound it may.
    private static func mayHoldAnObject(_ sample: Any, limit: Int = 256) -> Bool {
        var pending: [Any] = [sample]
        var next = 0
        while next < pending.count, next < limit {
            let inside = Mirror(reflecting: pending[next])
            next += 1
            switch inside.displayStyle {
            case .class:
                return true
            case .optional, .struct, .tuple, .enum, .collection, .set, .dictionary:
                for child in inside.children.prefix(limit) { pending.append(child.value) }
            default:
                continue
            }
        }
        return next >= limit
    }

    /// The module a type was declared in, which is the first part of its
    /// qualified name (`Swift.Array<Ollin.Vector2>` is `Swift`'s).
    private static func moduleName(of type: Any.Type) -> Substring {
        let qualified = String(reflecting: type)
        let end = qualified.firstIndex { $0 == "." || $0 == "<" } ?? qualified.endIndex
        return qualified[..<end]
    }
}
