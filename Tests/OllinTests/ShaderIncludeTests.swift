import Testing
import Foundation
import Metal
@testable import Ollin

private let hasMetal = MTLCreateSystemDefaultDevice() != nil

/// A file the stub loader can hand back, so the resolver's own rules are tested without
/// touching the disk.
private func stub(_ files: [String: String]) -> (String, String) -> ShaderIncludes.Source? {
    { spelling, _ in
        files[spelling].map { ShaderIncludes.Source(key: spelling, name: spelling, text: $0) }
    }
}

/// The resolver behind `#include "…"`, on its own.
///
/// Metal's runtime compiler has no include search path, so every rule here is Ollin's
/// own: what a file named twice does, what a cycle does, and where a diagnostic lands
/// after a file has been spliced into the middle of another one.
struct ShaderIncludeTests {

    // MARK: What gets pulled in

    @Test func aFileIsReadInWhereItIsNamed() {
        let result = ShaderIncludes.resolve("""
        a();
        #include "helper.metal"
        b();
        """, name: "root.metal", load: stub(["helper.metal": "float helper() { return 1.0; }"]))
        #expect(result.ok)
        #expect(result.source.contains("float helper() { return 1.0; }"))
        #expect(result.included == ["helper.metal"])
        // The lines around it keep their own numbering: the file is announced at its
        // own line 1, and the line after the directive resumes at 3.
        #expect(result.source.contains("#line 1 \"helper.metal\""))
        #expect(result.source.contains("#line 3 \"root.metal\""))
    }

    @Test func aFileNamedTwiceIsReadOnce() {
        let files = ["b.metal": "#include \"d.metal\"\nfloat b();",
                     "c.metal": "#include \"d.metal\"\nfloat c();",
                     "d.metal": "float shared_thing();"]
        let result = ShaderIncludes.resolve("#include \"b.metal\"\n#include \"c.metal\"",
                                            name: "a.metal", load: stub(files))
        #expect(result.ok)
        let appearances = result.source.components(separatedBy: "float shared_thing();").count - 1
        #expect(appearances == 1)
        #expect(result.included == ["b.metal", "d.metal", "c.metal"])
    }

    @Test func aCycleIsReportedRatherThanFollowed() {
        let files = ["a.metal": "#include \"b.metal\"", "b.metal": "#include \"a.metal\"\nfloat b();"]
        let result = ShaderIncludes.resolve("#include \"b.metal\"", name: "a.metal",
                                            rootKey: "a.metal", load: stub(files))
        #expect(!result.ok)
        #expect(result.problems.count == 1)
        #expect(result.problems[0].contains("b.metal:1"))
        #expect(result.problems[0].contains("already open"))
        // b itself still came in, once: only the loop back to the root was refused.
        #expect(result.source.contains("float b();"))
    }

    /// A spelling that names a place of its own is taken as it is, which is how a shader
    /// reaches a library cloned somewhere else on the machine. What that library then
    /// includes resolves from where *it* sits, which is the form such libraries use
    /// between their own files.
    @Test func anAbsoluteSpellingReachesOutsideTheSketchFolder() throws {
        let library = FileManager.default.temporaryDirectory
            .appendingPathComponent("ollin-library-\(UUID().uuidString)")
        let sketch = FileManager.default.temporaryDirectory
            .appendingPathComponent("ollin-sketch-\(UUID().uuidString)")
        for folder in [library, sketch] {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        }
        defer { for folder in [library, sketch] { try? FileManager.default.removeItem(at: folder) } }
        try FileManager.default.createDirectory(at: library.appendingPathComponent("math"),
                                                withIntermediateDirectories: true)
        try "float base() { return 3.0; }"
            .write(to: library.appendingPathComponent("math/base.metal"),
                   atomically: true, encoding: .utf8)
        try "#include \"math/base.metal\"\nfloat top() { return base(); }"
            .write(to: library.appendingPathComponent("top.metal"), atomically: true, encoding: .utf8)

        let source = "#include \"\(library.appendingPathComponent("top.metal").path)\"\nfloat use();"
        let result = ShaderIncludes.resolveFromFilesystem(
            source, name: sketch.appendingPathComponent("shader.metal").path)
        #expect(result.ok, "\(result.problems)")
        #expect(result.source.contains("float base() { return 3.0; }"))
        #expect(result.included.count == 2)
    }

    @Test func aFileThatIncludesItselfIsRefusedOnDisk() throws {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("ollin-cycle-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let shader = folder.appendingPathComponent("loop.metal")
        try "#include \"loop.metal\"\nfloat a();".write(to: shader, atomically: true, encoding: .utf8)
        let result = ShaderIncludes.resolveFromFilesystem(
            try String(contentsOf: shader, encoding: .utf8), name: shader.path)
        #expect(!result.ok)
        #expect(result.problems.count == 1)
        #expect(result.problems[0].contains("already open"))
    }

    @Test func aMissingFileIsReportedAtTheLineThatAskedForIt() {
        let result = ShaderIncludes.resolve("float a();\n\n#include \"gone.metal\"\nfloat b();",
                                            name: "root.metal", load: stub([:]))
        #expect(!result.ok)
        #expect(result.problems == ["root.metal:3: cannot find \"gone.metal\"."])
        // The directive leaves one blank line behind, so what follows keeps its number.
        #expect(result.source.split(separator: "\n", omittingEmptySubsequences: false).count == 4)
    }

    @Test func aNestTooDeepIsBounded() {
        // Every file includes the next, past the limit. Each level is its own file, so
        // nothing here is a cycle: only the depth guard can stop it.
        var files: [String: String] = [:]
        for i in 0..<(ShaderIncludes.depthLimit + 4) {
            files["f\(i).metal"] = "#include \"f\(i + 1).metal\"\nfloat f\(i)();"
        }
        files["f\(ShaderIncludes.depthLimit + 4).metal"] = "float last();"
        let result = ShaderIncludes.resolve("#include \"f0.metal\"", name: "root.metal",
                                            load: stub(files))
        #expect(!result.ok)
        #expect(result.problems.count == 1)
        #expect(result.problems[0].contains("nested deeper"))
    }

    // MARK: What is left alone

    @Test func anAngleIncludeIsLeftAlone() {
        let source = "#include <metal_stdlib>\nusing namespace metal;"
        let result = ShaderIncludes.resolve(source, name: "root.metal", load: stub([:]))
        #expect(result.ok)
        #expect(result.source == source)
    }

    @Test func aCommentedIncludeIsLeftAlone() {
        let source = "// #include \"helper.metal\"\nfloat a();"
        let result = ShaderIncludes.resolve(source, name: "root.metal",
                                            load: stub(["helper.metal": "float helper();"]))
        #expect(result.ok)
        #expect(result.source == source)
        #expect(result.included.isEmpty)
    }

    @Test func aSourceWithNoIncludeComesBackUntouched() {
        let source = "float4 shade(float2 uv, ShaderInfo info) { return 1.0; }"
        let result = ShaderIncludes.resolve(source, name: "root.metal", load: stub([:]))
        #expect(result.source == source)
        #expect(result.included.isEmpty)
    }

    @Test func aLeadingDirectiveIsOptional() {
        let plain = ShaderIncludes.resolve("float a();", name: "root.metal", load: stub([:]))
        #expect(plain.source == "float a();")
        let named = ShaderIncludes.resolve("float a();", name: "root.metal", startLine: 12,
                                           leadingLineDirective: true, load: stub([:]))
        #expect(named.source == "#line 12 \"root.metal\"\nfloat a();")
    }

    // MARK: Several roots at once

    @Test func severalRootsShareWhatHasBeenRead() {
        // The order the roots arrive in must not matter: a root that another root has
        // already pulled in is skipped, so every file lands once and after what it needs.
        let files = ["base.metal": "float base();"]
        let roots = ["one", "two"].map {
            ShaderIncludes.Source(key: "\($0).metal", name: "\($0).metal",
                                  text: "#include \"base.metal\"\nfloat \($0)();")
        }
        let result = ShaderIncludes.resolveAll(roots, load: stub(files))
        #expect(result.ok)
        let appearances = result.source.components(separatedBy: "float base();").count - 1
        #expect(appearances == 1)
        // base is read before either root's own body.
        let base = result.source.range(of: "float base();")!
        #expect(result.source.range(of: "float one();")!.lowerBound > base.upperBound)
        #expect(result.source.range(of: "float two();")!.lowerBound > base.upperBound)
    }

    @Test func aRootThatIsAlsoADependencyIsNotReadTwice() {
        let roots = [ShaderIncludes.Source(key: "top.metal", name: "top.metal",
                                           text: "#include \"base.metal\"\nfloat top();"),
                     ShaderIncludes.Source(key: "base.metal", name: "base.metal",
                                           text: "float base();")]
        let result = ShaderIncludes.resolveAll(roots, load: stub(["base.metal": "float base();"]))
        #expect(result.ok)
        #expect(result.source.components(separatedBy: "float base();").count - 1 == 1)
    }

    // MARK: On disk

    @Test func aSiblingFileResolvesAgainstTheFileThatAskedForIt() throws {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("ollin-include-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let helper = folder.appendingPathComponent("helper.metal")
        try "float helper() { return 2.0; }".write(to: helper, atomically: true, encoding: .utf8)
        let shader = folder.appendingPathComponent("shader.metal")
        try "#include \"helper.metal\"\nfloat use() { return helper(); }"
            .write(to: shader, atomically: true, encoding: .utf8)

        let result = ShaderIncludes.resolveFromFilesystem(
            try String(contentsOf: shader, encoding: .utf8), name: shader.path)
        #expect(result.ok)
        #expect(result.source.contains("float helper() { return 2.0; }"))
        #expect(result.included.count == 1)
        #expect(result.included[0].hasSuffix("helper.metal"))
    }

    /// A compute kernel reaches the same seam, so one helper file can serve a kernel
    /// and a fragment shader rather than being copied into both.
    @MainActor
    @Test(.enabled(if: hasMetal))
    func aComputeKernelReadsAFileItIncludes() throws {
        let device = try #require(MTLCreateSystemDefaultDevice())
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("ollin-kernel-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        try "float2 tilt(float2 p) { return p * 1.5; }"
            .write(to: folder.appendingPathComponent("helper.metal"), atomically: true, encoding: .utf8)
        let kernelURL = folder.appendingPathComponent("kernel.metal")
        try """
        #include "helper.metal"

        kernel void probe(device float2 *out [[buffer(0)]], uint i [[thread_position_in_grid]]) {
            out[i] = tilt(float2(float(i), 0.0));
        }
        """.write(to: kernelURL, atomically: true, encoding: .utf8)

        let kernel = try #require(ComputeKernel(entry: "probe", contentsOf: kernelURL))
        let composed = MetalRenderer.composeComputeSource(kernel.source,
                                                          sourcePath: kernel.sourcePath)
        #expect(composed.contains("float2 tilt(float2 p)"))
        #expect(throws: Never.self) { try device.makeLibrary(source: composed, options: nil) }
    }

    // MARK: The built-in segments

    /// The load-bearing one for the framework's own shader set. Each segment declares
    /// what it needs with an `#include`, so the list of segments carries no order at
    /// all. If a declaration is missing, the fixed list happens to hide it and any
    /// other order does not, which is exactly what this shuffles for.
    @MainActor
    @Test(.enabled(if: hasMetal))
    func theBuiltInSegmentsCompileInAnyOrder() throws {
        let device = try #require(MTLCreateSystemDefaultDevice())
        let rayTracing = MetalRenderer.rayTracingAvailable(on: device)
        var orders: [[String]] = [MetalRenderer.shaderSourceNames,
                                  MetalRenderer.shaderSourceNames.reversed(),
                                  MetalRenderer.shaderSourceNames.sorted(by: >)]
        // A few fixed shuffles, seeded so a failure repeats rather than haunts.
        for seed in [7, 19, 41] as [UInt64] {
            var rng = SeededRandom(seed: seed)
            orders.append(MetalRenderer.shaderSourceNames.shuffled(using: &rng))
        }
        for order in orders {
            let roots = order.compactMap { MetalRenderer.bundleShaderFile("\($0).metal", "") }
            #expect(roots.count == order.count)
            let assembled = MetalRenderer.assembleShaderSource(
                roots: roots, load: MetalRenderer.bundleShaderFile)
            #expect(assembled.ok, "\(assembled.problems)")
            let source = MetalRenderer.rayTracingDefine(rayTracing) + assembled.source
            #expect(throws: Never.self) { try device.makeLibrary(source: source, options: nil) }
        }
    }

    /// Every segment must be reachable, and reached once, whatever order they arrive in.
    @MainActor
    @Test func everySegmentLandsExactlyOnce() {
        let roots = MetalRenderer.shaderSourceNames.reversed()
            .compactMap { MetalRenderer.bundleShaderFile("\($0).metal", "") }
        let assembled = MetalRenderer.assembleShaderSource(roots: roots,
                                                           load: MetalRenderer.bundleShaderFile)
        let names = assembled.included.map { ($0 as NSString).lastPathComponent }
        for name in MetalRenderer.shaderSourceNames {
            #expect(names.filter { $0 == "\(name).metal" }.count == 1, "\(name)")
        }
        // The shared CPU/GPU header comes along, once, as somebody's declared need.
        #expect(names.filter { $0 == "OllinShaderTypes.h" }.count == 1)
    }
}

/// A tiny reproducible generator, so a shuffled order is the same on every run.
private struct SeededRandom: RandomNumberGenerator {
    var state: UInt64
    init(seed: UInt64) { state = seed &* 0x9E3779B97F4A7C15 | 1 }
    mutating func next() -> UInt64 {
        state ^= state << 13
        state ^= state >> 7
        state ^= state << 17
        return state
    }
}
