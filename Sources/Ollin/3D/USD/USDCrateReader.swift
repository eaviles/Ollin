import Foundation

/// A reader for the `.usdc` crate binary format, versions 0.8 through 0.10,
/// reimplemented from the format's structure (see ATTRIBUTION.md): a
/// bootstrap header, a table of contents naming six sections (TOKENS,
/// STRINGS, FIELDS, FIELDSETS, PATHS, SPECS), and value data addressed by
/// 64-bit ValueReps. Everything is little-endian; structural sections are
/// LZ4-wrapped and mostly integer-coded (`USDCrateSupport`).
///
/// The reader materializes the same raw tree the text parser yields: prims
/// with metadata, attributes (defaults, time samples, connections), and
/// relationships, in authored order (the `primChildren` / `properties`
/// fields when present, path-tree traversal order otherwise).
final class USDCrateReader {

    private let data: Data
    private var tokens: [String] = []
    private var stringTokenIndexes: [UInt32] = []
    private var fieldNameIndexes: [UInt32] = []
    private var fieldReps: [UInt64] = []
    private var fieldSets: [UInt32] = []

    private struct PathEntry {
        var parent = -1
        var element = ""
        var isProperty = false
        var full = ""
        var defined = false
    }
    private var paths: [PathEntry] = []
    /// Child path indexes per parent path index, in traversal order.
    private var childOrder: [[Int]] = []
    private var rootPathIndex = -1

    private struct Spec {
        var fieldSetIndex: Int
        var type: Int
    }
    /// Spec per path index (a path carries at most one spec).
    private var specs: [Int: Spec] = [:]

    /// Spec types (SdfSpecType): the ones assembly reads.
    private enum SpecType {
        static let attribute = 1
        static let prim = 6
        static let pseudoRoot = 7
        static let relationship = 8
    }

    /// Whether `data` starts with the crate magic.
    static func matches(_ data: Data) -> Bool {
        data.count >= 8 && data.prefix(8).elementsEqual(Array("PXR-USDC".utf8))
    }

    init(data: Data) throws {
        // Re-base a sliced Data so byte offsets equal file offsets.
        self.data = data.startIndex == 0 ? data : Data(data)
        try readStructure()
    }

    // MARK: - Structure

    private func readStructure() throws {
        guard Self.matches(data), data.count >= 88 else {
            throw USDError.malformed("usdc: bad bootstrap")
        }
        let major = data[8], minor = data[9], patch = data[10]
        guard major == 0, (8...10).contains(minor) else {
            throw USDError.unsupportedVersion("\(major).\(minor).\(patch)")
        }
        let tocOffset = Int(try i64(at: 16))
        guard tocOffset > 0, tocOffset < data.count else {
            throw USDError.malformed("usdc: bad TOC offset")
        }

        var sections: [String: (start: Int, size: Int)] = [:]
        let sectionCount = Int(try u64(at: tocOffset))
        guard sectionCount >= 0, sectionCount < 1024 else {
            throw USDError.malformed("usdc: implausible section count")
        }
        for s in 0..<sectionCount {
            let base = tocOffset + 8 + s * 32
            let nameBytes = try bytes(at: base, count: 16)
            let name = String(decoding: nameBytes.prefix { $0 != 0 }, as: UTF8.self)
            let start = Int(try i64(at: base + 16))
            let size = Int(try i64(at: base + 24))
            guard start >= 0, size >= 0, start + size <= data.count else {
                throw USDError.malformed("usdc: section '\(name)' out of bounds")
            }
            sections[name] = (start, size)
        }
        for required in ["TOKENS", "FIELDS", "FIELDSETS", "PATHS", "SPECS"] {
            guard sections[required] != nil else {
                throw USDError.malformed("usdc: missing \(required) section")
            }
        }

        try readTokens(at: sections["TOKENS"]!.start)
        if let strings = sections["STRINGS"] { try readStrings(at: strings.start) }
        try readFields(at: sections["FIELDS"]!.start)
        try readFieldSets(at: sections["FIELDSETS"]!.start)
        try readPaths(at: sections["PATHS"]!.start)
        try readSpecs(at: sections["SPECS"]!.start)
    }

    private func readTokens(at start: Int) throws {
        let count = Int(try u64(at: start))
        let uncompressed = Int(try u64(at: start + 8))
        let compressed = Int(try u64(at: start + 16))
        let blob = try bytes(at: start + 24, count: compressed)
        let buf = try USDLZ4.decompress(blob, capacity: uncompressed)
        guard buf.last == 0 else { throw USDError.malformed("usdc: token pool not terminated") }
        tokens = []
        tokens.reserveCapacity(count)
        var cursor = buf.startIndex
        for _ in 0..<count {
            guard cursor < buf.endIndex else { throw USDError.malformed("usdc: token pool short") }
            guard let nul = buf[cursor...].firstIndex(of: 0) else {
                throw USDError.malformed("usdc: unterminated token")
            }
            tokens.append(String(decoding: buf[cursor..<nul], as: UTF8.self))
            cursor = nul + 1
        }
    }

    private func readStrings(at start: Int) throws {
        let count = Int(try u64(at: start))
        stringTokenIndexes = try loadArray(at: start + 8, count: count, as: UInt32.self)
    }

    private func readFields(at start: Int) throws {
        let count = Int(try u64(at: start))
        var cursor = start + 8
        let indexesSize = Int(try u64(at: cursor)); cursor += 8
        fieldNameIndexes = try USDIntegerCoding.decodeInt32(try bytes(at: cursor, count: indexesSize),
                                                            count: count)
            .map { UInt32(bitPattern: $0) }
        cursor += indexesSize
        let repsSize = Int(try u64(at: cursor)); cursor += 8
        let repsBuf = try USDLZ4.decompress(try bytes(at: cursor, count: repsSize),
                                            capacity: count * 8)
        fieldReps = repsBuf.withUnsafeBytes { raw in
            (0..<count).map { raw.loadUnaligned(fromByteOffset: $0 * 8, as: UInt64.self) }
        }
        for index in fieldNameIndexes where Int(index) >= tokens.count {
            throw USDError.malformed("usdc: field name token out of range")
        }
    }

    private func readFieldSets(at start: Int) throws {
        let count = Int(try u64(at: start))
        let size = Int(try u64(at: start + 8))
        fieldSets = try USDIntegerCoding.decodeInt32(try bytes(at: start + 16, count: size),
                                                     count: count)
            .map { UInt32(bitPattern: $0) }
        guard fieldSets.isEmpty || fieldSets.last == .max else {
            throw USDError.malformed("usdc: field sets not terminated")
        }
    }

    private func readPaths(at start: Int) throws {
        let numPaths = Int(try u64(at: start))
        let numEncoded = Int(try u64(at: start + 8))
        var cursor = start + 16
        func codedInts() throws -> [Int32] {
            let size = Int(try u64(at: cursor))
            cursor += 8
            let out = try USDIntegerCoding.decodeInt32(try bytes(at: cursor, count: size),
                                                       count: numEncoded)
            cursor += size
            return out
        }
        let pathIndexes = try codedInts()
        let elementTokens = try codedInts()
        let jumps = try codedInts()

        paths = Array(repeating: PathEntry(), count: numPaths)
        childOrder = Array(repeating: [], count: numPaths)
        guard numEncoded > 0 else { return }

        // The three arrays describe a pre-order traversal: each element
        // defines one path slot; jumps encode leaf (-2), child-only (-1),
        // sibling-only (0), or both (sibling at +jump). Iterative with an
        // explicit stack so deep scenes can't overflow the call stack; a
        // pushed sibling keeps its own parent context.
        var stack: [(start: Int, parent: Int)] = [(0, -1)]
        while let top = stack.popLast() {
            var cur = top.start
            var parent = top.parent
            traversal: while true {
                guard cur >= 0, cur < numEncoded else {
                    throw USDError.malformed("usdc: path traversal out of range")
                }
                let this = cur
                cur += 1
                let pathIdx = Int(UInt32(bitPattern: pathIndexes[this]))
                guard pathIdx < numPaths else {
                    throw USDError.malformed("usdc: path index out of range")
                }
                if parent < 0 {
                    paths[pathIdx] = PathEntry(parent: -1, element: "", isProperty: false,
                                               full: "/", defined: true)
                    rootPathIndex = pathIdx
                } else {
                    let signed = Int(elementTokens[this])
                    let tokenIdx = abs(signed)
                    guard tokenIdx < tokens.count else {
                        throw USDError.malformed("usdc: path token out of range")
                    }
                    let element = tokens[tokenIdx]
                    let isProperty = signed < 0
                    let parentFull = paths[parent].full
                    let full: String
                    if isProperty {
                        full = parentFull + "." + element
                    } else if element.hasPrefix("{") || element.hasPrefix("[") {
                        // Variant-selection / relational-target elements
                        // append with no separator.
                        full = parentFull + element
                    } else {
                        full = parentFull == "/" ? "/" + element : parentFull + "/" + element
                    }
                    paths[pathIdx] = PathEntry(parent: parent, element: element,
                                               isProperty: isProperty, full: full, defined: true)
                    childOrder[parent].append(pathIdx)
                }
                let jump = Int(jumps[this])
                let hasChild = jump > 0 || jump == -1
                let hasSibling = jump >= 0
                if hasChild {
                    if hasSibling { stack.append((this + jump, parent)) }
                    parent = pathIdx
                } else if !hasSibling {
                    break traversal
                }
            }
        }
    }

    private func readSpecs(at start: Int) throws {
        let count = Int(try u64(at: start))
        var cursor = start + 8
        func codedInts() throws -> [Int32] {
            let size = Int(try u64(at: cursor))
            cursor += 8
            let out = try USDIntegerCoding.decodeInt32(try bytes(at: cursor, count: size),
                                                       count: count)
            cursor += size
            return out
        }
        let pathIndexes = try codedInts()
        let fieldSetIndexes = try codedInts()
        let specTypes = try codedInts()
        for i in 0..<count {
            let pathIdx = Int(UInt32(bitPattern: pathIndexes[i]))
            let fieldSetIdx = Int(UInt32(bitPattern: fieldSetIndexes[i]))
            let type = Int(specTypes[i])
            // A malformed spec drops; the rest of the file still reads.
            guard pathIdx < paths.count, paths[pathIdx].defined,
                  fieldSetIdx < fieldSets.count,
                  fieldSetIdx == 0 || fieldSets[fieldSetIdx - 1] == .max,
                  type > 0, type < 12,
                  specs[pathIdx] == nil
            else { continue }
            specs[pathIdx] = Spec(fieldSetIndex: fieldSetIdx, type: type)
        }
    }

    // MARK: - Stage assembly

    func readStage() throws -> USDStage {
        var stage = USDStage()
        guard rootPathIndex >= 0 else { return stage }

        var rootChildNames: [String]?
        if let rootSpec = specs[rootPathIndex], rootSpec.type == SpecType.pseudoRoot {
            for (name, rep) in try fieldList(rootSpec.fieldSetIndex) {
                let value = try unpack(rep, depth: 0)
                if name == "primChildren" {
                    if case .tokenArray(let names) = value { rootChildNames = names }
                } else {
                    stage.metadata[name] = value
                }
            }
        }

        let rootPrims = orderedChildren(of: rootPathIndex, by: rootChildNames)
        for index in rootPrims {
            if let prim = try buildPrim(at: index) { stage.prims.append(prim) }
        }
        return stage
    }

    private func buildPrim(at pathIndex: Int) throws -> USDPrim? {
        guard let spec = specs[pathIndex], spec.type == SpecType.prim else { return nil }
        var prim = USDPrim(name: paths[pathIndex].element)
        var childNames: [String]?
        var propertyNames: [String]?

        for (name, rep) in try fieldList(spec.fieldSetIndex) {
            let value = try unpack(rep, depth: 0)
            switch name {
            case "specifier":
                if case .token(let t) = value {
                    prim.specifier = t == "over" ? .over : (t == "class" ? .class : .def)
                }
            case "typeName":
                if case .token(let t) = value { prim.typeName = t }
            case "primChildren":
                if case .tokenArray(let names) = value { childNames = names }
            case "properties":
                if case .tokenArray(let names) = value { propertyNames = names }
            default:
                prim.metadata[name] = value
            }
        }

        // Properties first (they share the child list), then child prims.
        let propertyIndexes = childOrder[pathIndex].filter { paths[$0].isProperty }
        for index in orderedByName(propertyIndexes, names: propertyNames) {
            guard let propSpec = specs[index] else { continue }
            switch propSpec.type {
            case SpecType.attribute:
                prim.attributes.append(try buildAttribute(name: paths[index].element,
                                                          fieldSetIndex: propSpec.fieldSetIndex))
            case SpecType.relationship:
                prim.relationships.append(try buildRelationship(name: paths[index].element,
                                                                fieldSetIndex: propSpec.fieldSetIndex))
            default:
                continue
            }
        }

        let childIndexes = childOrder[pathIndex].filter { !paths[$0].isProperty }
        for index in orderedByName(childIndexes, names: childNames) {
            if let child = try buildPrim(at: index) { prim.children.append(child) }
        }
        return prim
    }

    private func buildAttribute(name: String, fieldSetIndex: Int) throws -> USDAttribute {
        var attr = USDAttribute(name: name)
        for (field, rep) in try fieldList(fieldSetIndex) {
            let value = try unpack(rep, depth: 0)
            switch field {
            case "typeName":
                if case .token(let t) = value { attr.typeName = t }
            case "default":
                attr.value = value
            case "timeSamples":
                if case .timeSamples(let samples) = value { attr.timeSamples = samples }
            case "variability":
                if case .token(let t) = value { attr.isUniform = (t == "uniform") }
            case "custom":
                if case .bool(let b) = value { attr.isCustom = b }
            case "connectionPaths":
                if case .pathArray(let targets) = value { attr.connections = targets }
            case "connectionChildren":
                continue
            default:
                attr.metadata[field] = value
            }
        }
        return attr
    }

    private func buildRelationship(name: String, fieldSetIndex: Int) throws -> USDRelationship {
        var rel = USDRelationship(name: name)
        for (field, rep) in try fieldList(fieldSetIndex) {
            let value = try unpack(rep, depth: 0)
            switch field {
            case "targetPaths":
                if case .pathArray(let targets) = value { rel.targets = targets }
            case "targetChildren":
                continue
            default:
                rel.metadata[field] = value
            }
        }
        return rel
    }

    /// The (name, rep) run for a spec's field set, terminated by the sentinel.
    private func fieldList(_ fieldSetIndex: Int) throws -> [(String, UInt64)] {
        var result: [(String, UInt64)] = []
        var i = fieldSetIndex
        while i < fieldSets.count, fieldSets[i] != .max {
            let fieldIndex = Int(fieldSets[i])
            guard fieldIndex < fieldNameIndexes.count else {
                throw USDError.malformed("usdc: field index out of range")
            }
            result.append((tokens[Int(fieldNameIndexes[fieldIndex])], fieldReps[fieldIndex]))
            i += 1
        }
        return result
    }

    private func orderedChildren(of pathIndex: Int, by names: [String]?) -> [Int] {
        orderedByName(childOrder[pathIndex].filter { !paths[$0].isProperty }, names: names)
    }

    /// Order path indexes by an authored name list when present, keeping
    /// unmatched entries in traversal order at the end.
    private func orderedByName(_ indexes: [Int], names: [String]?) -> [Int] {
        guard let names, !names.isEmpty else { return indexes }
        var byName: [String: Int] = [:]
        for index in indexes where byName[paths[index].element] == nil {
            byName[paths[index].element] = index
        }
        var ordered: [Int] = []
        var used = Set<Int>()
        for name in names {
            if let index = byName[name] {
                ordered.append(index)
                used.insert(index)
            }
        }
        ordered += indexes.filter { !used.contains($0) }
        return ordered
    }

    // MARK: - Value unpacking

    private struct Rep {
        let raw: UInt64
        var isArray: Bool { raw & (1 << 63) != 0 }
        var isInlined: Bool { raw & (1 << 62) != 0 }
        var isCompressed: Bool { raw & (1 << 61) != 0 }
        var type: Int { Int((raw >> 48) & 0xFF) }
        var payload: UInt64 { raw & 0xFFFF_FFFF_FFFF }
        var inlined: UInt32 { UInt32(truncatingIfNeeded: raw) }
        var offset: Int { Int(payload) }
    }

    private func unpack(_ rawRep: UInt64, depth: Int) throws -> USDValue {
        guard depth < 32 else { throw USDError.malformed("usdc: value nesting too deep") }
        let rep = Rep(raw: rawRep)
        if rep.isArray { return try unpackArray(rep) }

        switch rep.type {
        case 1: return .bool(rep.inlined & 0xFF != 0)
        case 2: return .int(Int64(rep.inlined & 0xFF))
        case 3: return .int(Int64(Int32(bitPattern: rep.inlined)))
        case 4: return .uint(UInt64(rep.inlined))
        case 5:
            return rep.isInlined ? .int(Int64(Int32(bitPattern: rep.inlined)))
                                 : .int(try i64(at: rep.offset))
        case 6:
            return rep.isInlined ? .uint(UInt64(rep.inlined))
                                 : .uint(try u64(at: rep.offset))
        case 7: return .double(Double(Float16(bitPattern: UInt16(truncatingIfNeeded: rep.inlined))))
        case 8: return .double(Double(Float(bitPattern: rep.inlined)))
        case 9:
            return rep.isInlined ? .double(Double(Float(bitPattern: rep.inlined)))
                                 : .double(try f64(at: rep.offset))
        case 10: return .string(try string(atStringIndex: Int(rep.inlined)))
        case 11: return .token(try token(at: Int(rep.inlined)))
        case 12:
            // The inlined scalar asset path carries a token index, unlike its
            // array elements, which carry string indexes.
            return .asset(try token(at: Int(rep.inlined)))
        case 13, 14, 15:
            let dim = rep.type - 11  // 2, 3, 4
            if rep.isInlined { return .tuple(Self.inlinedDiagonal(rep.inlined, dim: dim)) }
            return .tuple(try loadArray(at: rep.offset, count: dim * dim, as: Double.self))
        case 16: return .tuple(try loadArray(at: rep.offset, count: 4, as: Double.self))
        case 17: return .tuple(try loadArray(at: rep.offset, count: 4, as: Float.self).map(Double.init))
        case 18: return .tuple(try loadHalves(at: rep.offset, count: 4).map(Double.init))
        case 19, 20, 22, 23, 24, 26, 27, 28, 30, 25, 29:
            return .tuple(try vectorComponents(rep))
        case 21:
            // Vec2h inlines with raw half bits, the one vector that does.
            if rep.isInlined {
                let h0 = Float16(bitPattern: UInt16(truncatingIfNeeded: rep.inlined))
                let h1 = Float16(bitPattern: UInt16(truncatingIfNeeded: rep.inlined >> 16))
                return .tuple([Double(h0), Double(h1)])
            }
            return .tuple(try loadHalves(at: rep.offset, count: 2).map(Double.init))
        case 31:
            if rep.isInlined || rep.payload == 0 { return .dictionary([:]) }
            var cursor = rep.offset
            return .dictionary(try readDictionary(at: &cursor, depth: depth))
        case 32: return .tokenArray(try readListOp(at: rep.offset) { try self.token(at: $0) })
        case 33: return .stringArray(try readListOp(at: rep.offset) { try self.string(atStringIndex: $0) })
        case 34: return .pathArray(try readListOp(at: rep.offset) { try self.path(at: $0) })
        case 40:
            let count = Int(try u64(at: rep.offset))
            let indexes = try loadArray(at: rep.offset + 8, count: count, as: UInt32.self)
            return .pathArray(try indexes.map { try path(at: Int($0)) })
        case 41:
            let count = Int(try u64(at: rep.offset))
            let indexes = try loadArray(at: rep.offset + 8, count: count, as: UInt32.self)
            return .tokenArray(try indexes.map { try token(at: Int($0)) })
        case 42:
            switch rep.inlined {
            case 1: return .token("over")
            case 2: return .token("class")
            default: return .token("def")
            }
        case 43: return .token(rep.inlined == 1 ? "private" : "public")
        case 44: return .token(rep.inlined == 0 ? "varying" : "uniform")
        case 45:
            let count = Int(try u64(at: rep.offset))
            var map: [String: USDValue] = [:]
            var cursor = rep.offset + 8
            for _ in 0..<count {
                let key = try string(atStringIndex: Int(try u32(at: cursor)))
                let value = try string(atStringIndex: Int(try u32(at: cursor + 4)))
                map[key] = .string(value)
                cursor += 8
            }
            return .dictionary(map)
        case 46: return try unpackTimeSamples(at: rep.offset, depth: depth)
        case 48:
            let count = Int(try u64(at: rep.offset))
            return .doubleArray(try loadArray(at: rep.offset + 8, count: count, as: Double.self))
        case 50:
            let count = Int(try u64(at: rep.offset))
            let indexes = try loadArray(at: rep.offset + 8, count: count, as: UInt32.self)
            return .stringArray(try indexes.map { try string(atStringIndex: Int($0)) })
        case 51: return .block
        case 52, 53:
            var cursor = rep.offset
            return try readNestedValue(at: &cursor, depth: depth + 1)
        case 56: return .double(try f64(at: rep.offset))
        default:
            return .unsupported(Self.typeName(rep.type))
        }
    }

    /// Vec2/3/4 of f/d/i (the int8-inlinable vectors): inlined as signed
    /// bytes, one per component, else raw components at the offset.
    private func vectorComponents(_ rep: Rep) throws -> [Double] {
        let (arity, kind) = Self.vectorShape(rep.type)
        if rep.isInlined {
            return (0..<arity).map {
                Double(Int8(bitPattern: UInt8(truncatingIfNeeded: rep.inlined >> ($0 * 8))))
            }
        }
        switch kind {
        case .float: return try loadArray(at: rep.offset, count: arity, as: Float.self).map(Double.init)
        case .double: return try loadArray(at: rep.offset, count: arity, as: Double.self)
        case .int: return try loadArray(at: rep.offset, count: arity, as: Int32.self).map(Double.init)
        case .half: return try loadHalves(at: rep.offset, count: arity).map(Double.init)
        }
    }

    private enum ScalarKind { case float, double, int, half }

    private static func vectorShape(_ type: Int) -> (arity: Int, kind: ScalarKind) {
        switch type {
        case 19: (2, .double)
        case 20: (2, .float)
        case 21: (2, .half)
        case 22: (2, .int)
        case 23: (3, .double)
        case 24: (3, .float)
        case 25: (3, .half)
        case 26: (3, .int)
        case 27: (4, .double)
        case 28: (4, .float)
        case 29: (4, .half)
        case 30: (4, .int)
        default: (1, .double)
        }
    }

    private static func inlinedDiagonal(_ bits: UInt32, dim: Int) -> [Double] {
        var m = [Double](repeating: 0, count: dim * dim)
        for i in 0..<dim {
            m[i * dim + i] = Double(Int8(bitPattern: UInt8(truncatingIfNeeded: bits >> (i * 8))))
        }
        return m
    }

    // MARK: - Arrays

    private func unpackArray(_ rep: Rep) throws -> USDValue {
        if rep.payload == 0 { return Self.emptyArray(of: rep.type) }
        if rep.isCompressed { return try unpackCompressedArray(rep) }
        let offset = rep.offset
        let count = Int(try u64(at: offset))
        let body = offset + 8
        switch rep.type {
        case 1:
            let raw = try loadArray(at: body, count: count, as: UInt8.self)
            return .boolArray(raw.map { $0 != 0 })
        case 2: return .intArray(try loadArray(at: body, count: count, as: UInt8.self).map(Int64.init))
        case 3: return .intArray(try loadArray(at: body, count: count, as: Int32.self).map(Int64.init))
        case 4: return .intArray(try loadArray(at: body, count: count, as: UInt32.self).map(Int64.init))
        case 5: return .intArray(try loadArray(at: body, count: count, as: Int64.self))
        case 6: return .intArray(try loadArray(at: body, count: count, as: UInt64.self)
            .map(Int64.init(bitPattern:)))
        case 7: return .floatArray(try loadHalves(at: body, count: count))
        case 8: return .floatArray(try loadArray(at: body, count: count, as: Float.self))
        case 9: return .doubleArray(try loadArray(at: body, count: count, as: Double.self))
        case 10:
            let indexes = try loadArray(at: body, count: count, as: UInt32.self)
            return .stringArray(try indexes.map { try string(atStringIndex: Int($0)) })
        case 11:
            let indexes = try loadArray(at: body, count: count, as: UInt32.self)
            return .tokenArray(try indexes.map { try token(at: Int($0)) })
        case 12:
            // Array elements are string indexes, unlike the inlined scalar.
            let indexes = try loadArray(at: body, count: count, as: UInt32.self)
            return .assetArray(try indexes.map { try string(atStringIndex: Int($0)) })
        case 13, 14, 15:
            let dim = rep.type - 11
            return .doubleTupleArray(dim * dim,
                                     try loadArray(at: body, count: count * dim * dim, as: Double.self))
        case 16: return .doubleTupleArray(4, try loadArray(at: body, count: count * 4, as: Double.self))
        case 17: return .floatTupleArray(4, try loadArray(at: body, count: count * 4, as: Float.self))
        case 18: return .floatTupleArray(4, try loadHalves(at: body, count: count * 4))
        case 19...30:
            let (arity, kind) = Self.vectorShape(rep.type)
            switch kind {
            case .float:
                return .floatTupleArray(arity, try loadArray(at: body, count: count * arity, as: Float.self))
            case .half:
                return .floatTupleArray(arity, try loadHalves(at: body, count: count * arity))
            case .double:
                return .doubleTupleArray(arity, try loadArray(at: body, count: count * arity, as: Double.self))
            case .int:
                return .doubleTupleArray(arity, try loadArray(at: body, count: count * arity, as: Int32.self)
                    .map(Double.init))
            }
        case 56: return .doubleArray(try loadArray(at: body, count: count, as: Double.self))
        default:
            return .unsupported(Self.typeName(rep.type) + "[]")
        }
    }

    private func unpackCompressedArray(_ rep: Rep) throws -> USDValue {
        let offset = rep.offset
        let count = Int(try u64(at: offset))
        guard count >= 0, count <= data.count else {
            throw USDError.malformed("usdc: implausible array count")
        }
        let body = offset + 8

        // Small arrays (fewer than 16 elements) store raw even when the
        // compressed bit is set.
        if count < 16 {
            var raw = rep
            raw = Rep(raw: rep.raw & ~(UInt64(1) << 61))
            return try unpackArray(raw)
        }

        switch rep.type {
        case 3, 4:
            let ints = try USDIntegerCoding.decodeInt32(try compressedBody(at: body), count: count)
            return .intArray(rep.type == 3 ? ints.map(Int64.init)
                                           : ints.map { Int64(UInt32(bitPattern: $0)) })
        case 5, 6:
            let ints = try USDIntegerCoding.decodeInt64(try compressedBody(at: body), count: count)
            return .intArray(ints)
        case 7, 8, 9:
            return try unpackCompressedFloatArray(rep, count: count, at: body)
        default:
            throw USDError.malformed("usdc: compressed array of non-compressible type \(rep.type)")
        }
    }

    /// Compressed float arrays store either all-integer values ('i') or a
    /// lookup table plus indexes ('t'); both ride the integer coder.
    private func unpackCompressedFloatArray(_ rep: Rep, count: Int, at body: Int) throws -> USDValue {
        let code = try bytes(at: body, count: 1)[0]
        var cursor = body + 1
        switch code {
        case UInt8(ascii: "i"):
            let ints = try USDIntegerCoding.decodeInt32(try compressedBody(at: cursor), count: count)
            switch rep.type {
            case 9: return .doubleArray(ints.map(Double.init))
            default: return .floatArray(ints.map(Float.init))
            }
        case UInt8(ascii: "t"):
            let lutSize = Int(try u32(at: cursor))
            cursor += 4
            func lookup<T>(_ lut: [T]) throws -> [T] {
                let indexes = try USDIntegerCoding.decodeInt32(try compressedBody(at: cursor), count: count)
                return try indexes.map {
                    let i = Int(UInt32(bitPattern: $0))
                    guard i < lut.count else { throw USDError.malformed("usdc: float LUT index out of range") }
                    return lut[i]
                }
            }
            switch rep.type {
            case 7:
                let lut = try loadHalves(at: cursor, count: lutSize)
                cursor += lutSize * 2
                return .floatArray(try lookup(lut))
            case 8:
                let lut = try loadArray(at: cursor, count: lutSize, as: Float.self)
                cursor += lutSize * 4
                return .floatArray(try lookup(lut))
            default:
                let lut = try loadArray(at: cursor, count: lutSize, as: Double.self)
                cursor += lutSize * 8
                return .doubleArray(try lookup(lut))
            }
        default:
            throw USDError.malformed("usdc: unknown float-array compression code")
        }
    }

    /// The `uint64 compressedSize` + bytes shape shared by every compressed
    /// array payload.
    private func compressedBody(at offset: Int) throws -> Data {
        let size = Int(try u64(at: offset))
        return try bytes(at: offset + 8, count: size)
    }

    private static func emptyArray(of type: Int) -> USDValue {
        switch type {
        case 1: .boolArray([])
        case 2, 3, 4, 5, 6: .intArray([])
        case 7, 8: .floatArray([])
        case 9, 56: .doubleArray([])
        case 10: .stringArray([])
        case 11: .tokenArray([])
        case 12: .assetArray([])
        case 13, 14, 15:
            .doubleTupleArray((type - 11) * (type - 11), [])
        case 16: .doubleTupleArray(4, [])
        case 17, 18: .floatTupleArray(4, [])
        case 19...30:
            vectorShape(type).kind == .double || vectorShape(type).kind == .int
                ? .doubleTupleArray(vectorShape(type).arity, [])
                : .floatTupleArray(vectorShape(type).arity, [])
        default: .unsupported(typeName(type) + "[]")
        }
    }

    // MARK: - Structured values

    /// A dictionary body: count, then per entry a string-index key and a
    /// nested value. `cursor` advances past the dictionary.
    private func readDictionary(at cursor: inout Int, depth: Int) throws -> [String: USDValue] {
        let count = Int(try u64(at: cursor))
        cursor += 8
        var result: [String: USDValue] = [:]
        for _ in 0..<count {
            let key = try string(atStringIndex: Int(try u32(at: cursor)))
            cursor += 4
            result[key] = try readNestedValue(at: &cursor, depth: depth + 1)
        }
        return result
    }

    /// A nested value: a forward offset (relative to its own field) jumping
    /// over the value's data to an 8-byte rep. `cursor` lands after the rep.
    private func readNestedValue(at cursor: inout Int, depth: Int) throws -> USDValue {
        guard depth < 32 else { throw USDError.malformed("usdc: value nesting too deep") }
        let fieldPos = cursor
        let forward = Int(try i64(at: fieldPos))
        guard forward >= 8 else { throw USDError.malformed("usdc: bad nested value offset") }
        let rep = try u64(at: fieldPos + forward)
        cursor = fieldPos + forward + 8
        return try unpack(rep, depth: depth + 1)
    }

    /// Time samples: a forward offset to the times rep, then a forward offset
    /// to the per-sample rep list.
    private func unpackTimeSamples(at offset: Int, depth: Int) throws -> USDValue {
        let offA = Int(try i64(at: offset))
        let timesRepPos = offset + offA
        let timesValue = try unpack(try u64(at: timesRepPos), depth: depth + 1)
        let times: [Double]
        switch timesValue {
        case .doubleArray(let t): times = t
        case .floatArray(let t): times = t.map(Double.init)
        case .intArray(let t): times = t.map(Double.init)
        default: throw USDError.malformed("usdc: time samples times are not numeric")
        }
        let p2 = timesRepPos + 8
        let offB = Int(try i64(at: p2))
        var cursor = p2 + offB
        let numValues = Int(try u64(at: cursor))
        cursor += 8
        guard numValues == times.count else {
            throw USDError.malformed("usdc: time samples count mismatch")
        }
        var samples: [USDTimeSample] = []
        samples.reserveCapacity(numValues)
        for i in 0..<numValues {
            let rep = try u64(at: cursor + i * 8)
            samples.append(USDTimeSample(time: times[i], value: try unpack(rep, depth: depth + 1)))
        }
        return .timeSamples(samples)
    }

    /// A list-op body: a presence-bit header, then the present vectors in
    /// stream order (explicit, added, prepended, appended, deleted, ordered).
    /// Flattens to the effective item list: explicit items when explicit,
    /// else prepended + added + appended.
    private func readListOp(at offset: Int, element: (Int) throws -> String) throws -> [String] {
        var cursor = offset
        let header = try bytes(at: cursor, count: 1)[0]
        cursor += 1
        let isExplicit = header & 1 != 0
        func vector(if bit: UInt8) throws -> [String] {
            guard header & bit != 0 else { return [] }
            let count = Int(try u64(at: cursor))
            cursor += 8
            let indexes = try loadArray(at: cursor, count: count, as: UInt32.self)
            cursor += count * 4
            return try indexes.map { try element(Int($0)) }
        }
        let explicitItems = try vector(if: 2)
        let added = try vector(if: 4)
        let prepended = try vector(if: 32)
        let appended = try vector(if: 64)
        _ = try vector(if: 8)   // deleted
        _ = try vector(if: 16)  // ordered
        return isExplicit ? explicitItems : prepended + added + appended
    }

    // MARK: - Table lookups

    private func token(at index: Int) throws -> String {
        guard index >= 0, index < tokens.count else {
            throw USDError.malformed("usdc: token index out of range")
        }
        return tokens[index]
    }

    private func string(atStringIndex index: Int) throws -> String {
        guard index >= 0, index < stringTokenIndexes.count else {
            throw USDError.malformed("usdc: string index out of range")
        }
        return try token(at: Int(stringTokenIndexes[index]))
    }

    private func path(at index: Int) throws -> String {
        guard index >= 0, index < paths.count, paths[index].defined else {
            throw USDError.malformed("usdc: path index out of range")
        }
        return paths[index].full
    }

    private static func typeName(_ type: Int) -> String {
        switch type {
        case 35: "referenceListOp"
        case 36, 37, 38, 39: "intListOp"
        case 47: "payload"
        case 49: "layerOffsetVector"
        case 54: "unregisteredValueListOp"
        case 55: "payloadListOp"
        case 57: "pathExpression"
        default: "type\(type)"
        }
    }

    // MARK: - Raw reads

    private func bytes(at offset: Int, count: Int) throws -> Data {
        guard offset >= 0, count >= 0, offset <= data.count, count <= data.count - offset else {
            throw USDError.malformed("usdc: read out of bounds")
        }
        return data.subdata(in: offset..<offset + count)
    }

    private func u32(at offset: Int) throws -> UInt32 {
        guard offset >= 0, offset + 4 <= data.count else {
            throw USDError.malformed("usdc: read out of bounds")
        }
        return data.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: offset, as: UInt32.self) }
    }

    private func u64(at offset: Int) throws -> UInt64 {
        guard offset >= 0, offset + 8 <= data.count else {
            throw USDError.malformed("usdc: read out of bounds")
        }
        return data.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: offset, as: UInt64.self) }
    }

    private func i64(at offset: Int) throws -> Int64 {
        Int64(bitPattern: try u64(at: offset))
    }

    private func f64(at offset: Int) throws -> Double {
        Double(bitPattern: try u64(at: offset))
    }

    /// Bulk-load `count` bitwise elements at `offset`.
    private func loadArray<T>(at offset: Int, count: Int, as type: T.Type) throws -> [T] {
        let byteCount = count * MemoryLayout<T>.stride
        guard offset >= 0, count >= 0, offset <= data.count, byteCount <= data.count - offset else {
            throw USDError.malformed("usdc: array read out of bounds")
        }
        return data.withUnsafeBytes { raw in
            [T](unsafeUninitializedCapacity: count) { buffer, initialized in
                let src = UnsafeRawBufferPointer(rebasing: raw[offset..<offset + byteCount])
                UnsafeMutableRawBufferPointer(buffer).copyMemory(from: src)
                initialized = count
            }
        }
    }

    private func loadHalves(at offset: Int, count: Int) throws -> [Float] {
        try loadArray(at: offset, count: count, as: UInt16.self)
            .map { Float(Float16(bitPattern: $0)) }
    }
}
