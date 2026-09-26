import Foundation
import Testing
import OllinMutation
@testable import Ollin

/// The depth class, the declared-size class's twin: an input nested deeper
/// than its reader allows is refused or read to the limit, never recursed
/// into until the stack runs out. A stack overflow is a trap the mutation
/// harness cannot reach (its edits never nest a structure ten thousand deep),
/// so each reader that recurses is handed such an input directly, on a thread
/// with the half-megabyte stack a secondary thread gets, where the main
/// thread's eight would hide a recursion a background load would die of.
///
/// Beside it, the file a file names: a model whose buffer, a material whose
/// picture, or a shader whose include is a device reads only regular files, so
/// `/dev/zero` is refused rather than read without end.
@Suite(.enabled(if: !underThreadSanitizer, "these measure the stack a debug build uses, and the sanitizer's instrumented frames are larger by a margin no sketch runs with"))
struct DeepInputTests {

    /// What a read on the small stack came back with.
    final class Outcome: @unchecked Sendable {
        var value = ""
    }

    /// Runs `body` on a thread with a 512 KB stack and returns what it said.
    static func onSmallStack(_ body: @escaping @Sendable () -> String) async -> String {
        let outcome = Outcome()
        await withCheckedContinuation { (done: CheckedContinuation<Void, Never>) in
            let thread = Thread {
                outcome.value = body()
                done.resume()
            }
            thread.stackSize = 512 * 1024
            thread.start()
        }
        return outcome.value
    }

    @Test func aFormulaNestedPastItsLimitIsRefused() async {
        let deep = 100_000
        let cases = [
            String(repeating: "(", count: deep) + "1" + String(repeating: ")", count: deep),
            String(repeating: "-", count: deep) + "1",
            "1" + String(repeating: "+1", count: deep),
            String(repeating: "2^", count: deep) + "2",
            String(repeating: "sin(", count: deep) + "1" + String(repeating: ")", count: deep),
        ]
        for source in cases {
            let said = await Self.onSmallStack {
                do { _ = try Formula(source); return "read" } catch { return "refused" }
            }
            #expect(said == "refused", "\(source.prefix(12))…")
        }
        // A formula a person writes, nested a few deep and a few dozen long,
        // still reads.
        #expect((try? Formula("sin(cos(tan((x + 1) * (y - 2))))" + String(repeating: " + x", count: 100))) != nil)
    }

    @Test @MainActor func anAutomationChainedTenThousandDeepPlays() async throws {
        // Every track's formula reads the next one's parameter, so the order
        // the plan works out is a chain as long as the file.
        let count = 10_000
        var tracks: [String] = []
        for i in 0..<count {
            tracks.append(#"{"name": "p\#(i)", "formula": "p\#(i + 1) + 1"}"#)
        }
        let json = #"{"version": 3, "loops": false, "speed": 1, "start": 0, "tracks": [\#(tracks.joined(separator: ","))]}"#
        let automation = try JSONDecoder().decode(Automation.self, from: Data(json.utf8))
        final class Target: Sketch { @Param(0...10) var p0 = 1.0 }
        let player = AutomationPlayer(automation)
        player.apply(to: Target(), at: 0.5)
        #expect(automation.tracks.count == count)
    }

    @Test func aModelNestedPastItsLimitStopsThere() async {
        let depth = 5_000
        let said = await Self.onSmallStack {
            var nodes: [String] = []
            for i in 0..<depth {
                nodes.append(i + 1 < depth ? #"{"children": [\#(i + 1)], "translation": [0, 1, 0]}"# : #"{"mesh": 0}"#)
            }
            let json = GLTFSeed.make().text.replacingOccurrences(of: #""scenes": [{"name": "seed", "nodes": [0, 3]}]"#,
                                                                 with: #""scenes": [{"nodes": [4]}]"#)
            // The seed's own nodes stay first (0 to 3); the chain starts at 4.
            let chained = json.replacingOccurrences(
                of: #"{"name": "lamp", "translation": [2, 3, 4], "extensions": {"KHR_lights_punctual": {"light": 0}}}]"#,
                with: #"{"name": "lamp", "translation": [2, 3, 4]}, "# + nodes.enumerated().map { index, node in
                    node.replacingOccurrences(of: "[\(index + 1)]", with: "[\(index + 5)]")
                }.joined(separator: ", ") + "]")
            guard let doc = GLTFDocument(data: Data(chained.utf8), isBinary: false,
                                         baseDirectory: URL(fileURLWithPath: NSTemporaryDirectory())) else { return "unread" }
            let scene = Scene.loadGLTFScene(doc)
            _ = Mesh.loadGLTF(doc)
            var deepest = 0
            func measure(_ node: SceneNode, _ level: Int) {
                deepest = max(deepest, level)
                for child in node.children { measure(child, level + 1) }
            }
            for node in scene?.nodes ?? [] { measure(node, 1) }
            // Read at the limit the way a sketch reads a scene.
            var inconsistent = 0
            if let scene { ModelFileMutationTests.read(scene, inconsistent: &inconsistent) }
            return "\(deepest)"
        }
        #expect(said == "\(GLTFDocument.maxNodeDepth)")
    }

    @Test func aStageAtItsLimitLoadsAndReads() async {
        let said = await Self.onSmallStack {
            // The deepest stage the reader takes, a mesh at the bottom: parsed,
            // built into a scene, walked, and merged, all on the small stack.
            // The limit counts values as well as prims, so the mesh's array of
            // points and each point in it take the last two levels.
            let depth = USDStage.maxDepth - 1
            let mesh = #"def Mesh "m" { point3f[] points = [(0, 0, 0), (1, 0, 0), (0, 1, 0)] int[] faceVertexCounts = [3] int[] faceVertexIndices = [0, 1, 2] }"#
            let text = "#usda 1.0\n" + String(repeating: #"def Xform "a" { double3 xformOp:translate = (0, 1, 0) uniform token[] xformOpOrder = ["xformOp:translate"] "#, count: depth - 2)
                + mesh + String(repeating: " }", count: depth - 2)
            guard let scene = Scene.loadUSDScene(data: Data(text.utf8), fileURL: URL(fileURLWithPath: "/tmp/deep.usda")) else {
                return "unread"
            }
            var inconsistent = 0
            ModelFileMutationTests.read(scene, inconsistent: &inconsistent)
            guard let merged = Mesh.merged(scene) else { return "no mesh" }
            return "\(merged.triangleCount)"
        }
        #expect(said == "1")
    }

    @Test func aStageNestedPastItsLimitIsRefused() async {
        let said = await Self.onSmallStack {
            let depth = 20_000
            let text = "#usda 1.0\n" + String(repeating: #"def Xform "a" {"#, count: depth)
                + String(repeating: "}", count: depth)
            do { _ = try USDStage.load(data: Data(text.utf8)); return "read" } catch { return "refused" }
        }
        #expect(said == "refused")
    }

    @Test func aValueNestedPastItsLimitIsRefused() async {
        let said = await Self.onSmallStack {
            let depth = 20_000
            let text = "#usda 1.0\n(\n customLayerData = " + String(repeating: "{ dictionary d = ", count: depth)
                + "{}" + String(repeating: " }", count: depth) + "\n)\n"
            do { _ = try USDStage.load(data: Data(text.utf8)); return "read" } catch { return "refused" }
        }
        #expect(said == "refused")
    }

    @Test func aDocumentNestedDeepReturns() async {
        let said = await Self.onSmallStack {
            let depth = 100_000
            let json = String(repeating: "[", count: depth) + "1" + String(repeating: "]", count: depth)
            let svg = #"<svg xmlns="http://www.w3.org/2000/svg">"# + String(repeating: "<g>", count: depth)
                + #"<rect width="1" height="1"/>"# + String(repeating: "</g>", count: depth) + "</svg>"
            _ = try? JSON(data: Data(json.utf8))
            _ = try? SVG(data: Data(svg.utf8))
            return "returned"
        }
        #expect(said == "returned")
    }

    @Test func aFileThatNamesADeviceIsRefused() throws {
        let folder = ScratchFolder("named")
        let device = "/dev/zero"
        let gltf = GLTFSeed.make().text.replacingOccurrences(of: #""uri": "data:application/octet-stream;base64,"#,
                                                             with: #""uri": "\#(device)", "x": ""#)
        #expect(GLTFDocument(data: Data(gltf.utf8), isBinary: false, baseDirectory: folder.url) == nil)
        folder.write(Array("newmtl m\nKd 1 0 0\nmap_Kd \(device)\n".utf8), named: "m.mtl")
        let obj = folder.write(Array("mtllib m.mtl\nusemtl m\nv 0 0 0\nv 1 0 0\nv 0 1 0\nf 1 2 3\n".utf8), named: "m.obj")
        #expect((try? Mesh(contentsOf: obj))?.material?.texture == nil)
        let result = ShaderIncludes.resolveFromFilesystem("#include \"\(device)\"\n", name: folder.url.appendingPathComponent("s.metal").path)
        #expect(result.problems.contains { $0.contains("cannot find") })
        #expect(NamedFile.data(at: folder.url) == nil, "a folder is not a file")
        #expect(NamedFile.data(at: obj) != nil)
    }
}
