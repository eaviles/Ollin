import Testing
import Foundation
import Metal
@testable import Ollin

private let hasMetal = MTLCreateSystemDefaultDevice() != nil

/// `ollin check`: compile a shader file on the real device and say what it found.
///
/// The point of the command is that a person editing a `.metal` outside a running
/// sketch can find out whether it compiles, and where it went wrong, without launching
/// something that draws it. So the tests that matter are about *where* a mistake is
/// reported, and about the two things the command claims to know: what the shader is,
/// and which parameters it reads.
@MainActor
struct ShaderCheckTests {

    /// A folder with the given files in it, removed when the test ends.
    private func folder(_ files: [String: String]) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("ollin-check-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        for (name, text) in files {
            try text.write(to: url.appendingPathComponent(name), atomically: true, encoding: .utf8)
        }
        return url
    }

    // MARK: What it says about a shader that works

    @Test(.enabled(if: hasMetal))
    func aShaderThatCompilesIsReportedOk() throws {
        let dir = try folder(["plain.metal": """
        float4 shade(float2 uv, ShaderInfo info) {
            return float4(uv, 0.0, 1.0);
        }
        """])
        defer { try? FileManager.default.removeItem(at: dir) }
        let report = ShaderCheck.check(path: dir.appendingPathComponent("plain.metal").path)
        #expect(report.ok, "\(report.diagnostics)")
        #expect(report.shape == .generator)
        #expect(!report.shapeWasGiven)
        #expect(report.parameters.isEmpty)
        #expect(report.included.isEmpty)
    }

    @Test(.enabled(if: hasMetal))
    func aShaderThatReadsAFileItIncludesCompiles() throws {
        let dir = try folder([
            "helper.metal": "float2 tilt(float2 uv) { return uv * 1.5; }",
            "uses.metal": """
            #include "helper.metal"

            float4 shade(float2 uv, ShaderInfo info) {
                return float4(tilt(uv), param(info, 0), 1.0);
            }
            """])
        defer { try? FileManager.default.removeItem(at: dir) }
        let report = ShaderCheck.check(path: dir.appendingPathComponent("uses.metal").path)
        #expect(report.ok, "\(report.diagnostics)")
        #expect(report.parameters == [0])
        #expect(report.included.count == 1)
        #expect(report.included[0].hasSuffix("helper.metal"))
    }

    // MARK: Where a mistake is reported

    @Test(.enabled(if: hasMetal))
    func anErrorLandsAtTheLineTheAuthorWrote() throws {
        let dir = try folder(["broken.metal": """
        float4 shade(float2 uv, ShaderInfo info) {
            float v = noize(uv);
            return float4(v, v, v, 1.0);
        }
        """])
        defer { try? FileManager.default.removeItem(at: dir) }
        let path = dir.appendingPathComponent("broken.metal").path
        let report = ShaderCheck.check(path: path)
        #expect(!report.ok)
        // The mistake is on line 2 of the file the author is looking at, and the
        // diagnostic must name that file rather than the composed source.
        #expect(report.diagnostics.contains("broken.metal:2:"))
        #expect(!report.diagnostics.contains("program_source"))
    }

    /// The load-bearing one for includes. A mistake inside a file that was pulled in
    /// must be reported against *that* file at *its* own line, not at the line of the
    /// shader that included it, or the include is worse than copying the helper by hand.
    @Test(.enabled(if: hasMetal))
    func anErrorInsideAnIncludedFileNamesThatFile() throws {
        let dir = try folder([
            "helper.metal": """
            // A helper with a mistake on its third line.
            float2 tilt(float2 uv) {
                return uv * scail;
            }
            """,
            "uses.metal": """
            #include "helper.metal"

            float4 shade(float2 uv, ShaderInfo info) {
                return float4(tilt(uv), 0.0, 1.0);
            }
            """])
        defer { try? FileManager.default.removeItem(at: dir) }
        let report = ShaderCheck.check(path: dir.appendingPathComponent("uses.metal").path)
        #expect(!report.ok)
        #expect(report.diagnostics.contains("helper.metal:3:"))
        #expect(!report.diagnostics.contains("uses.metal:"))
    }

    @Test(.enabled(if: hasMetal))
    func aMissingIncludeIsReportedBeforeTheCompilerIsAsked() throws {
        let dir = try folder(["uses.metal": """
        #include "gone.metal"

        float4 shade(float2 uv, ShaderInfo info) { return 1.0; }
        """])
        defer { try? FileManager.default.removeItem(at: dir) }
        let report = ShaderCheck.check(path: dir.appendingPathComponent("uses.metal").path)
        #expect(!report.ok)
        #expect(report.diagnostics.contains("uses.metal:1"))
        #expect(report.diagnostics.contains("cannot find \"gone.metal\""))
        // The compiler never ran, so nothing about undeclared identifiers leaks in.
        #expect(!report.diagnostics.contains("undeclared"))
    }

    @Test func aFileThatIsNotThereIsSaidSo() {
        let report = ShaderCheck.check(path: "/nowhere/at/all/none.metal")
        #expect(!report.ok)
        #expect(report.diagnostics.contains("cannot read the file"))
    }

    // MARK: What the shader is

    @Test func theShapeFollowsTheLayersItReads() {
        #expect(ShaderCheck.inferredShape(of: "return float4(uv, 0, 1);") == .generator)
        #expect(ShaderCheck.inferredShape(of: "return sample(info, uv);") == .filter)
        #expect(ShaderCheck.inferredShape(of: "return sampleRaw(info, uv);") == .filter)
        #expect(ShaderCheck.inferredShape(of: "return sample(info, uv) + sampleAux(info, uv);")
                == .combine)
        #expect(ShaderCheck.inferredShape(of: "return sampleAuxRaw(info, uv);") == .combine)
    }

    @Test func aWordEndingInSampleIsNotALayerRead() {
        // `discSample` is a helper in Ollin's own shader library, and a shader that
        // calls it reads no layer at all. Matching on the bare word would call it a
        // filter and then compile it against an input that is not there.
        #expect(ShaderCheck.inferredShape(of: "float2 p = discSample(hash12(uv));") == .generator)
        #expect(ShaderCheck.inferredShape(of: "int sampleCount = 8;") == .generator)
    }

    @Test(.enabled(if: hasMetal))
    func aGivenShapeIsUsedInsteadOfTheGuess() throws {
        let dir = try folder(["filter.metal": """
        float4 shade(float2 uv, ShaderInfo info) { return sample(info, uv); }
        """])
        defer { try? FileManager.default.removeItem(at: dir) }
        let path = dir.appendingPathComponent("filter.metal").path
        let asFilter = ShaderCheck.check(path: path, as: .filter)
        #expect(asFilter.ok, "\(asFilter.diagnostics)")
        #expect(asFilter.shapeWasGiven)
        // Compiled as a generator there is no layer to read, so it must fail.
        let asGenerator = ShaderCheck.check(path: path, as: .generator)
        #expect(!asGenerator.ok)
        #expect(asGenerator.shape == .generator)
    }

    // MARK: The readers are functions, not macros

    /// `sample` is a member function on every Metal texture type, and Ollin's own
    /// segments call it hundreds of times. While the readers were macros, a
    /// function-like `#define sample(info, p)` rewrote any two-argument `t.sample(s, uv)`
    /// in an included file into a member that does not exist. As a free function it is
    /// never a candidate for member-call syntax, so the call goes through untouched.
    @Test(.enabled(if: hasMetal))
    func aTextureMemberSampleIsLeftAlone() throws {
        let dir = try folder(["member.metal": """
        float4 shade(float2 uv, ShaderInfo info) {
            texture2d<float> t = info.in0;
            sampler s = info.in0samp;
            return t.sample(s, uv);
        }
        """])
        defer { try? FileManager.default.removeItem(at: dir) }
        let report = ShaderCheck.check(path: dir.appendingPathComponent("member.metal").path,
                                       as: .filter)
        #expect(report.ok, "\(report.diagnostics)")
    }

    /// The same call with a sampling option takes three arguments. A macro refused that
    /// outright ("too many arguments provided to function-like macro invocation"), which
    /// is worse than a wrong rewrite, since the call is ordinary Metal.
    @Test(.enabled(if: hasMetal))
    func aTextureSampleWithAnOptionIsLeftAlone() throws {
        let dir = try folder(["level.metal": """
        float4 shade(float2 uv, ShaderInfo info) {
            texture2d<float> t = info.in0;
            sampler s = info.in0samp;
            return t.sample(s, uv, level(0));
        }
        """])
        defer { try? FileManager.default.removeItem(at: dir) }
        let report = ShaderCheck.check(path: dir.appendingPathComponent("level.metal").path,
                                       as: .filter)
        #expect(report.ok, "\(report.diagnostics)")
    }

    /// A shader may declare a helper of its own called `sample`. Under a macro the
    /// declaration itself failed, whatever it meant.
    @Test(.enabled(if: hasMetal))
    func aHelperOfYourOwnMayBeCalledSample() throws {
        let dir = try folder(["own.metal": """
        float sample(float x) { return x * 2.0; }

        float4 shade(float2 uv, ShaderInfo info) {
            return float4(sample(uv.x), 0.0, 0.0, 1.0);
        }
        """])
        defer { try? FileManager.default.removeItem(at: dir) }
        let report = ShaderCheck.check(path: dir.appendingPathComponent("own.metal").path)
        #expect(report.ok, "\(report.diagnostics)")
    }

    // MARK: Narrowing the library

    @Test func aUsingListIsReadOrRefused() {
        #expect(ShaderCheck.modules(named: "all") == .all)
        #expect(ShaderCheck.modules(named: "none")?.isEmpty == true)
        #expect(ShaderCheck.modules(named: "noise") == .noise)
        #expect(ShaderCheck.modules(named: "sdf, domain") == [.sdf, .domain])
        #expect(ShaderCheck.modules(named: "SDF") == .sdf)
        #expect(ShaderCheck.modules(named: "nonsense") == nil)
        #expect(ShaderCheck.modules(named: "sdf,nonsense") == nil)
        #expect(ShaderCheck.names(of: [.color, .sdf]) == ["color", "sdf"])
    }

    /// The point of the flag: a shader written against a narrowed library can be checked
    /// the way it runs, rather than only against everything.
    @Test(.enabled(if: hasMetal))
    func aNarrowedLibraryLeavesOutWhatWasNotAskedFor() throws {
        let dir = try folder(["noisy.metal": """
        float4 shade(float2 uv, ShaderInfo info) {
            return float4(float3(fbm(uv * 4.0)), 1.0);
        }
        """])
        defer { try? FileManager.default.removeItem(at: dir) }
        let path = dir.appendingPathComponent("noisy.metal").path
        let withNoise = ShaderCheck.check(path: path, using: .noise)
        #expect(withNoise.ok, "\(withNoise.diagnostics)")
        #expect(withNoise.modules == .noise)
        let without = ShaderCheck.check(path: path, using: .sdf)
        #expect(!without.ok)
        #expect(without.diagnostics.contains("fbm"))
    }

    // MARK: What it reads

    @Test func theParametersItReadsAreCollected() {
        #expect(ShaderCheck.parameterIndices(in: "param(info, 0) + param(info, 2)") == [0, 2])
        #expect(ShaderCheck.parameterIndices(in: "param(info, 1) * param(info, 1)") == [1])
        #expect(ShaderCheck.parameterIndices(in: "param( info , 3 )") == [3])
        #expect(ShaderCheck.parameterIndices(in: "float paramCount = 2.0;").isEmpty)
        #expect(ShaderCheck.parameterIndices(in: "no parameters here").isEmpty)
    }
}
