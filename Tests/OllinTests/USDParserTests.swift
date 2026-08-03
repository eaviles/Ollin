import Testing
import Foundation
@testable import Ollin
#if canImport(ModelIO)
import ModelIO
#endif

/// GPU-free checks on the internal OllinUSD parser core: the usda text
/// parser, the usdc crate reader (versions 0.8-0.10), and the usdz package
/// container. The oracles are all local: the repo's example stage, inline
/// grammar fixtures, Model I/O's own usda/usdc exports of the same asset
/// (two independent code paths must agree, and both must agree with what
/// Model I/O reads back), and the system's shipped usdz files.
struct USDParserTests {

    // MARK: - Fixture locations

    private var repoRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    private var exampleStageURL: URL {
        repoRoot.appendingPathComponent("Examples/3D/Geometry/USDScene/stage.usda")
    }

    private static let shaderballURL = URL(fileURLWithPath:
        "/System/Library/PrivateFrameworks/CoreUSDEdit.framework/Versions/A/Resources/shaderball.usdz")

    private static let pencilKitResources = URL(fileURLWithPath:
        "/System/iOSSupport/System/Library/Frameworks/PencilKit.framework/Versions/A/Resources")

    // MARK: - usda text

    /// The example stage parses with its authored structure: layer metadata,
    /// the prim tree in authored order, mesh attributes, transforms, and
    /// material-binding relationships.
    @Test func usdaParsesTheExampleStage() throws {
        guard FileManager.default.fileExists(atPath: exampleStageURL.path) else { return }
        let stage = try USDStage.load(contentsOf: exampleStageURL)

        #expect(stage.metadata["defaultPrim"] == .string("Court"))
        #expect(stage.metadata["upAxis"] == .string("Y"))
        #expect(stage.metadata["metersPerUnit"] == .int(1))

        #expect(stage.prims.count == 1)
        let court = try #require(stage.prims.first)
        #expect(court.name == "Court")
        #expect(court.typeName == "Xform")
        #expect(court.specifier == .def)

        let dais = try #require(court.child("dais"))
        #expect(dais.typeName == "Mesh")
        guard case .floatTupleArray(3, let points)? = dais.attribute("points")?.value else {
            Issue.record("dais points did not parse as a float tuple array")
            return
        }
        #expect(points.count == 194 * 3)
        #expect(abs(points[0] - 2.7) < 1e-6)
        guard case .intArray(let counts)? = dais.attribute("faceVertexCounts")?.value else {
            Issue.record("dais faceVertexCounts did not parse as an int array")
            return
        }
        #expect(counts.first == 4)
        let scheme = try #require(dais.attribute("subdivisionScheme"))
        #expect(scheme.isUniform)
        #expect(scheme.value == .token("none"))
        #expect(dais.relationship("material:binding")?.targets == ["/Court/Materials/stone"])

        let plinths = try #require(court.child("plinths"))
        #expect(plinths.attribute("xformOp:translate")?.value == .tuple([0, 0.18, 0]))
        #expect(plinths.attribute("xformOpOrder")?.value == .tokenArray(["xformOp:translate"]))
        // Authored order survives: dais is authored before plinths.
        let daisIndex = try #require(court.children.firstIndex { $0.name == "dais" })
        let plinthsIndex = try #require(court.children.firstIndex { $0.name == "plinths" })
        #expect(daisIndex < plinthsIndex)
    }

    /// The grammar's corners: all three comment forms, escapes, triple-quoted
    /// strings, timeSamples blocks, connections, dictionaries, empty and
    /// tuple arrays, matrices as nested tuples, valueless declarations,
    /// variantSet blocks (skipped whole), and `;` statement separators.
    @Test func usdaHandlesGrammarCorners() throws {
        let source = #"""
        #usda 1.0
        (
            doc = """multi
        line"""
            customLayerData = {
                string note = "a \"quoted\" name\n"
                int count = 3
                dictionary nested = { double d = 1.5 }
            }
        )

        # line comment
        // another comment
        /* block
           comment */
        def "Untyped"
        {
        }

        def Xform "Root" (
            kind = "component"
            prepend apiSchemas = ["MaterialBindingAPI"]
        )
        {
            double3 xformOp:translate = (1, 2, 3)
            double3 xformOp:translate.timeSamples = {
                0: (0, 0, 0),
                24: (0, 5, 0),
            }
            uniform token[] xformOpOrder = ["xformOp:translate"]
            custom float gain = .5
            float ramp = 1.e3
            bool flag = 1
            asset tex = @textures/wood.png@
            float[] empty = []
            matrix4d m = ( (1, 0, 0, 0), (0, 1, 0, 0), (0, 0, 1, 0), (4, 5, 6, 1) )
            token out
            token out.connect = </Root/child.result>
            rel binding = [ </A>, </B> ]
            variantSet "look" = {
                "red" { float x = 1 }
                "blue" ( doc = "b" ) { float x = 2 }
            }
            int one = 1; int two = 2
            def Mesh "child"
            {
                point3f[] points = [(0, 0, 0), (1, 0, 0)]
                token result
            }
            over "patch"
            {
            }
        }
        """#
        let stage = try USDTextParser(text: source).parseStage()

        #expect(stage.metadata["doc"] == .string("multi\nline"))
        guard case .dictionary(let layerData)? = stage.metadata["customLayerData"] else {
            Issue.record("customLayerData did not parse as a dictionary")
            return
        }
        #expect(layerData["note"] == .string("a \"quoted\" name\n"))
        #expect(layerData["count"] == .int(3))
        #expect(layerData["nested"] == .dictionary(["d": .double(1.5)]))

        #expect(stage.prims.map(\.name) == ["Untyped", "Root"])
        #expect(stage.prims[0].typeName.isEmpty)

        let root = stage.prims[1]
        #expect(root.metadata["kind"] == .string("component"))
        // Untyped metadata keeps the literal's shape: quoted strings arrive
        // as strings here (a crate file's apiSchemas is a token list-op).
        #expect(root.metadata["apiSchemas"] == .stringArray(["MaterialBindingAPI"]))

        let translate = try #require(root.attribute("xformOp:translate"))
        #expect(translate.value == .tuple([1, 2, 3]))
        #expect(translate.timeSamples == [
            USDTimeSample(time: 0, value: .tuple([0, 0, 0])),
            USDTimeSample(time: 24, value: .tuple([0, 5, 0])),
        ])

        let gain = try #require(root.attribute("gain"))
        #expect(gain.isCustom)
        #expect(gain.value == .double(0.5))
        #expect(root.attribute("ramp")?.value == .double(1000))
        #expect(root.attribute("flag")?.value == .bool(true))
        #expect(root.attribute("tex")?.value == .asset("textures/wood.png"))
        #expect(root.attribute("empty")?.value == .floatArray([]))
        #expect(root.attribute("m")?.value ==
            .tuple([1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 4, 5, 6, 1]))

        let out = try #require(root.attribute("out"))
        #expect(out.value == nil)
        #expect(out.connections == ["/Root/child.result"])

        #expect(root.relationship("binding")?.targets == ["/A", "/B"])
        #expect(root.attribute("one")?.value == .int(1))
        #expect(root.attribute("two")?.value == .int(2))

        // The variantSet block was skipped whole; the children are the two
        // authored prims in order.
        #expect(root.children.map(\.name) == ["child", "patch"])
        #expect(root.children[1].specifier == .over)
        #expect(root.children[0].attribute("points")?.value == .floatTupleArray(3, [0, 0, 0, 1, 0, 0]))
    }

    // MARK: - Crate vs text vs Model I/O

    /// Model I/O exports the same asset as usda text and usdc crate; the two
    /// independent parser paths must yield the same tree (structure exactly,
    /// float payloads to text precision), and both must agree with what
    /// Model I/O itself reads back from the crate file.
    @Test func crateAndTextParsersAgreeOnModelIOExport() throws {
        #if canImport(ModelIO)
        guard FileManager.default.fileExists(atPath: exampleStageURL.path),
              MDLAsset.canExportFileExtension("usdc"),
              MDLAsset.canExportFileExtension("usda") else { return }
        let asset = MDLAsset(url: exampleStageURL)
        let tmp = FileManager.default.temporaryDirectory
        // One shared stem: Model I/O names the exported root prim after the
        // file, so different names would make the trees differ at the root.
        let stem = "ollin-\(ProcessInfo.processInfo.globallyUniqueString)"
        let usdaURL = tmp.appendingPathComponent(stem + ".usda")
        let usdcURL = tmp.appendingPathComponent(stem + ".usdc")
        defer {
            try? FileManager.default.removeItem(at: usdaURL)
            try? FileManager.default.removeItem(at: usdcURL)
        }
        do {
            try asset.export(to: usdaURL)
            try asset.export(to: usdcURL)
        } catch { return }  // soft-skip if this OS can't export

        let textStage = try USDStage.load(contentsOf: usdaURL)
        let crateStage = try USDStage.load(contentsOf: usdcURL)

        // Same tree shape in the same order.
        #expect(outline(of: textStage) == outline(of: crateStage))

        // Every mesh's geometry payload agrees between the two parsers:
        // indices exactly, points to the text file's printed precision.
        let textMeshes = collectPrims(textStage.prims) { $0.typeName == "Mesh" }
        let crateMeshes = collectPrims(crateStage.prims) { $0.typeName == "Mesh" }
        #expect(!textMeshes.isEmpty)
        #expect(textMeshes.count == crateMeshes.count)
        for (text, crate) in zip(textMeshes, crateMeshes) {
            #expect(text.name == crate.name)
            #expect(text.attribute("faceVertexIndices")?.value
                == crate.attribute("faceVertexIndices")?.value)
            guard case .floatTupleArray(3, let a)? = text.attribute("points")?.value,
                  case .floatTupleArray(3, let b)? = crate.attribute("points")?.value else {
                Issue.record("mesh '\(text.name)' points missing from a parse")
                continue
            }
            #expect(a.count == b.count)
            var worst: Float = 0
            for (x, y) in zip(a, b) { worst = max(worst, abs(x - y)) }
            #expect(worst < 1e-5)
        }

        // Ground truth: Model I/O's own read of the crate file agrees with
        // our crate parse on mesh names, vertex counts, and transforms.
        let readBack = MDLAsset(url: usdcURL)
        var mdlMeshCount = 0
        for index in 0..<readBack.count {
            walk(readBack.object(at: index)) { object in
                guard let mesh = object as? MDLMesh else { return }
                mdlMeshCount += 1
                guard let prim = collectPrims(crateStage.prims, where: { $0.name == object.name }).first,
                      case .floatTupleArray(3, let points)? = prim.attribute("points")?.value else {
                    Issue.record("no parsed prim for Model I/O mesh '\(object.name)'")
                    return
                }
                #expect(points.count == mesh.vertexCount * 3)
                if let transform = object.transform?.matrix,
                   case .tuple(let m)? = prim.attribute("xformOp:transform")?.value,
                   m.count == 16 {
                    for column in 0..<4 {
                        for row in 0..<4 {
                            // USD matrices are row-major; simd is column-major.
                            let ours = Float(m[column * 4 + row])
                            #expect(abs(ours - transform[column][row]) < 1e-5)
                        }
                    }
                }
            }
        }
        #expect(mdlMeshCount == crateMeshes.count)
        #endif
    }

    // MARK: - usdz packages

    /// The system shaderball (a crate 0.9 flattened layer in a stored zip)
    /// opens and yields real geometry, and every mesh's vertex count matches
    /// Model I/O's read of the same package.
    @Test func usdzReadsTheSystemShaderball() throws {
        guard FileManager.default.fileExists(atPath: Self.shaderballURL.path) else { return }
        let stage = try USDStage.load(contentsOf: Self.shaderballURL)
        #expect(!stage.prims.isEmpty)
        let meshes = collectPrims(stage.prims) { prim in
            guard case .floatTupleArray(3, let points)? = prim.attribute("points")?.value else {
                return false
            }
            return !points.isEmpty
        }
        #expect(!meshes.isEmpty)

        // Internal consistency: indices address exactly the authored points.
        for mesh in meshes {
            guard case .floatTupleArray(3, let points)? = mesh.attribute("points")?.value,
                  case .intArray(let indices)? = mesh.attribute("faceVertexIndices")?.value else {
                Issue.record("mesh '\(mesh.name)' lost points or indices")
                continue
            }
            #expect((indices.max().map { Int($0) + 1 } ?? 0) == points.count / 3)
        }

        #if canImport(ModelIO)
        // Ground truth: Model I/O expands vertices per face corner when it
        // reads a file it didn't author, so its vertex count equals our
        // faceVertexIndices count (not the authored points count).
        var ours: [String: [Int]] = [:]
        for mesh in meshes {
            guard case .intArray(let indices)? = mesh.attribute("faceVertexIndices")?.value else { continue }
            ours[mesh.name, default: []].append(indices.count)
        }
        let asset = MDLAsset(url: Self.shaderballURL)
        var theirs: [String: [Int]] = [:]
        for index in 0..<asset.count {
            walk(asset.object(at: index)) { object in
                guard let mesh = object as? MDLMesh else { return }
                theirs[object.name, default: []].append(mesh.vertexCount)
            }
        }
        guard !theirs.isEmpty else { return }  // soft-skip if Model I/O can't read it
        for (name, counts) in theirs {
            #expect(ours[name]?.sorted() == counts.sorted(),
                    "face-vertex counts for '\(name)' disagree with Model I/O")
        }
        #endif
    }

    /// Every PencilKit tool usdz (crate 0.8 packages) opens with prims.
    @Test func usdzReadsThePencilKitPens() throws {
        let files = (try? FileManager.default.contentsOfDirectory(
            at: Self.pencilKitResources, includingPropertiesForKeys: nil))?
            .filter { $0.pathExtension == "usdz" } ?? []
        guard !files.isEmpty else { return }
        for file in files {
            let stage = try USDStage.load(contentsOf: file)
            #expect(!stage.prims.isEmpty, "no prims in \(file.lastPathComponent)")
        }
    }

    // MARK: - Determinism & rejection

    /// Parsing the same bytes twice yields identical trees, and a canonical
    /// dump of the two parses is byte-identical.
    @Test func reparseIsByteDeterministic() throws {
        var candidates = [exampleStageURL]
        if FileManager.default.fileExists(atPath: Self.shaderballURL.path) {
            candidates.append(Self.shaderballURL)
        }
        for url in candidates where FileManager.default.fileExists(atPath: url.path) {
            let data = try Data(contentsOf: url)
            let first = try USDStage.load(data: data)
            let second = try USDStage.load(data: data)
            #expect(first == second)
            #expect(canonicalDump(first) == canonicalDump(second))
        }
    }

    /// Version and container sniffing fail cleanly: an unsupported crate
    /// version, truncated crate bytes, and unrecognizable bytes all throw.
    @Test func malformedInputsAreRejected() {
        var old = Data("PXR-USDC".utf8)
        old.append(contentsOf: [0, 7, 0, 0, 0, 0, 0, 0])
        old.append(Data(count: 72))
        #expect(throws: USDError.self) { try USDStage.load(data: old) }

        let truncated = Data("PXR-USDC".utf8) + Data([0, 9, 0])
        #expect(throws: USDError.self) { try USDStage.load(data: truncated) }

        #expect(throws: USDError.self) { try USDStage.load(data: Data("hello".utf8)) }
    }

    // MARK: - Helpers

    private func collectPrims(_ prims: [USDPrim],
                              where predicate: (USDPrim) -> Bool) -> [USDPrim] {
        var found: [USDPrim] = []
        for prim in prims {
            if predicate(prim) { found.append(prim) }
            found += collectPrims(prim.children, where: predicate)
        }
        return found
    }

    /// The tree's structural outline: names, types, and property names, one
    /// line per prim in tree order. Property names are sorted within a prim:
    /// Model I/O's text writer alphabetizes properties while its crate
    /// writer keeps authored order, so cross-format order isn't comparable.
    private func outline(of stage: USDStage) -> [String] {
        var lines: [String] = []
        func visit(_ prim: USDPrim, depth: Int) {
            let attrs = prim.attributes.map(\.name).sorted().joined(separator: ",")
            let rels = prim.relationships.map(\.name).sorted().joined(separator: ",")
            lines.append("\(String(repeating: "  ", count: depth))\(prim.typeName) \(prim.name) [\(attrs)] [\(rels)]")
            for child in prim.children { visit(child, depth: depth + 1) }
        }
        for prim in stage.prims { visit(prim, depth: 0) }
        return lines
    }

    #if canImport(ModelIO)
    private func walk(_ object: MDLObject, _ body: (MDLObject) -> Void) {
        body(object)
        for child in object.children.objects { walk(child, body) }
    }
    #endif

    /// A complete, canonically-ordered textual dump for byte-determinism
    /// comparison (dictionary keys sorted; every array element included).
    private func canonicalDump(_ stage: USDStage) -> String {
        var out = "stage \(dump(metadata: stage.metadata))\n"
        func visit(_ prim: USDPrim) {
            out += "prim \(prim.name) \(prim.typeName) \(prim.specifier) \(dump(metadata: prim.metadata))\n"
            for a in prim.attributes {
                out += "attr \(a.name) \(a.typeName) u:\(a.isUniform) c:\(a.isCustom) "
                out += a.value.map(dump(value:)) ?? "-"
                out += " ts:[" + a.timeSamples.map { "\($0.time)=\(dump(value: $0.value))" }
                    .joined(separator: ",") + "]"
                out += " conn:\(a.connections) \(dump(metadata: a.metadata))\n"
            }
            for r in prim.relationships {
                out += "rel \(r.name) \(r.targets) \(dump(metadata: r.metadata))\n"
            }
            for child in prim.children { visit(child) }
        }
        for prim in stage.prims { visit(prim) }
        return out
    }

    private func dump(metadata: [String: USDValue]) -> String {
        "{" + metadata.keys.sorted().map { "\($0)=\(dump(value: metadata[$0]!))" }
            .joined(separator: ";") + "}"
    }

    private func dump(value: USDValue) -> String {
        switch value {
        case .bool(let v): "b\(v)"
        case .int(let v): "i\(v)"
        case .uint(let v): "u\(v)"
        case .double(let v): "d\(v)"
        case .string(let v): "s(\(v))"
        case .token(let v): "t(\(v))"
        case .asset(let v): "a(\(v))"
        case .path(let v): "p(\(v))"
        case .tuple(let v): "tuple\(v)"
        case .boolArray(let v): "b[]\(v)"
        case .intArray(let v): "i[]\(v)"
        case .floatArray(let v): "f[]\(v)"
        case .doubleArray(let v): "d[]\(v)"
        case .stringArray(let v): "s[]\(v)"
        case .tokenArray(let v): "t[]\(v)"
        case .assetArray(let v): "a[]\(v)"
        case .pathArray(let v): "p[]\(v)"
        case .floatTupleArray(let arity, let v): "f\(arity)[]\(v)"
        case .doubleTupleArray(let arity, let v): "d\(arity)[]\(v)"
        case .dictionary(let v):
            "{" + v.keys.sorted().map { "\($0)=\(dump(value: v[$0]!))" }.joined(separator: ";") + "}"
        case .timeSamples(let v):
            "ts[" + v.map { "\($0.time)=\(dump(value: $0.value))" }.joined(separator: ",") + "]"
        case .block: "block"
        case .unsupported(let name): "unsupported(\(name))"
        }
    }
}
