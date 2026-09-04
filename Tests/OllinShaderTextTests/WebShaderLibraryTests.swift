import Testing
import Foundation
import OllinWebGate
@testable import OllinShaderText

/// The shader helper library translated whole. The text checks say every
/// function crossed with nothing Metal-only left behind; the browser checks say
/// the result actually compiles, section by section, and that the two rules with
/// a semantic difference (the sign of `fmod`, the shape of `select`) compute what
/// Metal computes. The browser checks are skipped, with the reason in the log,
/// on a machine whose browser cannot give a WebGL2 context.
struct WebShaderLibraryTests {

    // MARK: Support

    /// Walk up from this file to the folder holding the framework's manifest.
    static func repositoryRoot() -> URL? {
        var directory = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        for _ in 0 ..< 8 {
            let manifest = directory.appendingPathComponent("Package.swift")
            if let text = try? String(contentsOf: manifest, encoding: .utf8), text.contains("name: \"Ollin\"") {
                return directory
            }
            let parent = directory.deletingLastPathComponent()
            if parent == directory { break }
            directory = parent
        }
        return nil
    }

    /// The library's Metal text, read from the checkout.
    static func libraryText() throws -> String {
        let root = try #require(Self.repositoryRoot())
        let url = root.appendingPathComponent("Sources/Ollin/Renderer/OllinShaderLib.metal")
        return try String(contentsOf: url, encoding: .utf8)
    }

    static let everySection = Set(WebShaderLibrary.sectionNames)

    /// The framework's own segments the page cuts sections from, beside the
    /// library, read from the checkout in the order the exporter joins them.
    static func segmentText() throws -> String {
        let root = try #require(Self.repositoryRoot())
        return try ["OllinShaderLib", "ShaderCore", "ShaderShapes", "ShaderCombinator", "ShaderRaymarch", "ShaderEffects"].map { name in
            try String(contentsOf: root.appendingPathComponent("Sources/Ollin/Renderer/\(name).metal"), encoding: .utf8)
        }.joined(separator: "\n")
    }

    /// A whole page shader: the preamble, the support the translation needs, the
    /// translated sections, and a `main` so the program links.
    static func pageShader(_ translation: WebShaderTranslation, main: String = "out vec4 o;\nvoid main() { o = vec4(1.0); }") -> String {
        WebShaderCompat.preamble + "\n" + translation.support + "\n\n" + translation.body + "\n" + main + "\n"
    }

    /// Words that would mean a Metal spelling survived.
    static let metalOnlyWords = ["float2", "float3", "float4", "half", "static", "inline", "thread", "constant",
                                 "atan2", "fmod", "select", "fabs", "rsqrt", "metal", "as_type"]

    static func metalWordsLeft(in text: String) -> [String] {
        let tokens = ShaderLexer.tokenize(text)
        var found: Set<String> = []
        for t in tokens where t.kind == .identifier && metalOnlyWords.contains(t.text) {
            found.insert(t.text)
        }
        return found.sorted()
    }

    // MARK: The text

    @Test func theSectionsCloseOverTheirDependencies() {
        #expect(WebShaderLibrary.closure(of: []) == ["base"])
        #expect(WebShaderLibrary.closure(of: ["noise"]) == ["base", "hash", "noise"])
        #expect(WebShaderLibrary.closure(of: ["visual"]) == ["base", "hash", "noise", "visual"])
        #expect(WebShaderLibrary.closure(of: ["sdf", "domain"]) == ["base", "sdf", "domain"])
    }

    @Test func onlyTheMarkedSectionsReachThePage() throws {
        let metal = try Self.libraryText()
        let sdf = WebShaderLibrary.sections(of: metal, wanted: ["sdf"])
        #expect(sdf.contains("sdEllipse"))
        #expect(sdf.contains("srgbToLinear"))          // base always comes along
        #expect(!sdf.contains("hash12("))              // hash was not asked for
        #expect(!sdf.contains("#include"))             // the preamble never crosses
        #expect(!sdf.contains("ollin_grid_coord"))     // nor the compute-only tail
        #expect(!sdf.contains("OLLIN_RK4_STEP"))
        let everything = WebShaderLibrary.sections(of: metal, wanted: Self.everySection)
        #expect(everything.contains("ollin_vis_blend"))
        #expect(!everything.contains("ollin_lorenz"))
    }

    @Test func everySectionTranslatesClean() throws {
        let metal = try Self.libraryText()
        for section in WebShaderLibrary.sectionNames {
            let translation = WebShaderLibrary.translate(metal, wanted: [section])
            #expect(translation.isClean, "\(section): \(translation.unsupported.map(\.message))")
            #expect(Self.metalWordsLeft(in: translation.body).isEmpty,
                    "\(section) still says \(Self.metalWordsLeft(in: translation.body))")
        }
        let whole = WebShaderLibrary.translate(metal, wanted: Self.everySection)
        #expect(whole.isClean)
        #expect(whole.diagnostics.isEmpty, "\(whole.diagnostics.map(\.message))")
        #expect(whole.helpers.isSuperset(of: [.select, .fmod, .greaterThan, .lessThan]))
        #expect(whole.constants == ["M_PI_F"])
    }

    @Test func everyFunctionCrosses() throws {
        let metal = try Self.libraryText()
        let sections = WebShaderLibrary.sections(of: metal, wanted: Self.everySection)
        let before = WebShaderLibrary.definedFunctions(in: sections)
        let translation = WebShaderTranslator.translate(sections)
        let after = WebShaderLibrary.definedFunctions(in: translation.body)
        #expect(before.count > 100)
        #expect(before == after)
        // The line structure is the source's own, so a browser error names the
        // same line a reader would open in the Metal file's section.
        #expect(sections.split(separator: "\n", omittingEmptySubsequences: false).count
                == translation.body.split(separator: "\n", omittingEmptySubsequences: false).count)
    }

    @Test func theKnownDisagreementsAreRewrittenNotMapped() throws {
        let metal = try Self.libraryText()
        let body = WebShaderLibrary.translate(metal, wanted: Self.everySection).body
        // fmod keeps Metal's truncating sign through the helper, never GLSL's mod.
        #expect(body.contains("p = ollin_fmod(p + halfS, s);"))
        #expect(!body.contains(" mod("))
        // select with a vector condition goes through the helper pair.
        #expect(body.contains("return ollin_select(lo, hi, ollin_gt(c, 0.04045));"))
        #expect(body.contains("p = ollin_select(p, p + s, ollin_lt(p, 0.0));"))
        // A reference parameter is inout.
        #expect(body.contains("float pmod(inout float p, float s)"))
        #expect(body.contains("float sdBezier(vec2 pos, vec2 A, vec2 B, vec2 C, inout float outT)"))
        // The gradient table is a const array constructor without its trailing comma.
        #expect(body.contains("const vec3 ollin_grad3[12] = vec3[12]("))
        #expect(body.contains("vec3( 0,  1,-1), vec3( 0, -1,-1)\n);"))
        // The named constant stays a name and gets its define.
        #expect(body.contains("M_PI_F * p.x"))
    }

    @Test func theSegmentSectionsTranslateClean() throws {
        let text = try Self.segmentText()
        #expect(WebShaderLibrary.closure(of: ["shapes"]) == ["base", "sdf", "shapes"])
        #expect(WebShaderLibrary.closure(of: ["present"]) == ["base", "hash", "present"])
        #expect(WebShaderLibrary.closure(of: ["combinator"]) == ["base", "combinator"])
        #expect(WebShaderLibrary.closure(of: ["raymarch"]) == ["base", "hash", "noise", "sdf", "combinator", "raymarch"])
        for section in WebShaderLibrary.segmentSectionNames {
            let translation = WebShaderLibrary.translate(text, wanted: [section])
            #expect(translation.isClean, "\(section): \(translation.unsupported.map(\.message))")
            #expect(Self.metalWordsLeft(in: translation.body).isEmpty,
                    "\(section) still says \(Self.metalWordsLeft(in: translation.body))")
        }
        // The shapes: the coverage function the fragment calls, with its
        // reference outputs as inout, over the sdf primitives it needs.
        let shapes = WebShaderLibrary.translate(text, wanted: ["shapes"]).body
        #expect(shapes.contains("void ollin_sdf_coverage(uint shape, uint align, vec2 p, vec2 size,"))
        #expect(shapes.contains("inout float fillCov, inout float strokeCov,"))
        #expect(shapes.contains("float ollin_sdf_distance(uint shape, vec2 p, vec2 size,"))
        #expect(shapes.contains("float sdEllipse("))
        #expect(shapes.contains("float perceptualCoverage(float c)"))
        #expect(!shapes.contains("resolvePaint"))       // a texture reader stays behind
        #expect(!shapes.contains("fragment float4"))     // so does the entry point
        // The present pass: the dither and the tone-map curve, over the hash.
        let present = WebShaderLibrary.translate(text, wanted: ["present"]).body
        #expect(present.contains("float ditherTriangle(vec2 fragCoord)"))
        #expect(present.contains("vec3 toneMapACES(vec3 x)"))
        #expect(present.contains("float hash12(vec2 p)"))
        #expect(!present.contains("ollin_present_fragment"))
        // The composed field's VM arithmetic: the combine switch with its reference
        // outputs as inout, the point transforms over the page's own node record,
        // the buffer-walking fragment left behind.
        let combinator = WebShaderLibrary.translate(text, wanted: ["combinator"]).body
        #expect(combinator.contains("void ollin_sdf_combine(uint op, float da, vec4 ca, float db, vec4 cb,"))
        #expect(combinator.contains("float k, float n, inout float outD, inout vec4 outC)"))
        #expect(combinator.contains("vec2 ollin_sdf_xform(vec2 p, SDFNode nd)"))
        #expect(combinator.contains("struct SDFNode {"))
        #expect(!combinator.contains("ollin_sdfgroup_fragment"))
        #expect(!combinator.contains("distStack"))
        // The raymarcher: every 3D distance function and the leaf switch, over the
        // combinator's joint ops and the library's value noise; the march stays behind.
        let raymarch = WebShaderLibrary.translate(text, wanted: ["raymarch"]).body
        #expect(raymarch.contains("float ollin_sdf3d_eval(uint shape, vec3 p, vec4 geo0, vec4 geo1)"))
        #expect(raymarch.contains("float ollin_sd3_mandelbulb(vec3 p, float unit, float power, int iterations)"))
        #expect(raymarch.contains("vec3 ollin_sdf3d_xform(vec3 p, SDFNode3D nd)"))
        #expect(raymarch.contains("float ollin_op_stairs(float a, float b, float r, float n)"))
        #expect(raymarch.contains("float valueNoise(vec3 p)"))
        #expect(!raymarch.contains("ollin_sdf3d_field"))
        #expect(!raymarch.contains("ollin_raymarch_fragment"))
    }

    // MARK: The browser

    @Test(.enabled("a browser with WebGL2 is needed") { await HeadlessBrowser.hasWebGL2() })
    func theWholeLibraryAndEachSectionCompileInABrowser() async throws {
        let metal = try Self.libraryText()
        var shaders: [String] = []
        var names: [String] = []
        shaders.append(Self.pageShader(WebShaderLibrary.translate(metal, wanted: Self.everySection)))
        names.append("all")
        for section in WebShaderLibrary.sectionNames {
            shaders.append(Self.pageShader(WebShaderLibrary.translate(metal, wanted: [section])))
            names.append(section)
        }
        let dom = try await HeadlessBrowser.dom(of: WebGLPage.compile(shaders))
        for (i, name) in names.enumerated() {
            let verdict = try #require(HeadlessBrowser.text(of: "r\(i)", in: dom))
            #expect(verdict == "OK", "\(name): \(verdict.prefix(1200))")
        }
    }

    @Test(.enabled("a browser with WebGL2 is needed") { await HeadlessBrowser.hasWebGL2() })
    func theSegmentSectionsCompileInABrowser() async throws {
        let text = try Self.segmentText()
        let shaders = WebShaderLibrary.segmentSectionNames.map {
            Self.pageShader(WebShaderLibrary.translate(text, wanted: [$0]))
        }
        let dom = try await HeadlessBrowser.dom(of: WebGLPage.compile(shaders))
        for (i, name) in WebShaderLibrary.segmentSectionNames.enumerated() {
            let verdict = try #require(HeadlessBrowser.text(of: "r\(i)", in: dom))
            #expect(verdict == "OK", "\(name): \(verdict.prefix(1200))")
        }
    }

    @Test(.enabled("a browser with WebGL2 is needed") { await HeadlessBrowser.hasWebGL2() })
    func theGateCatchesABrokenLibrary() async throws {
        // A gate that cannot fail proves nothing, so break the translated text
        // on purpose and read the browser's complaint, line and all.
        let metal = try Self.libraryText()
        let translation = WebShaderLibrary.translate(metal, wanted: ["sdf"])
        let broken = Self.pageShader(translation, main: "out vec4 o;\nvoid main() { o = vec4(undeclared_thing); }")
        let dom = try await HeadlessBrowser.dom(of: WebGLPage.compile([broken]))
        let verdict = try #require(HeadlessBrowser.text(of: "r0", in: dom))
        #expect(verdict.hasPrefix("FAIL compile"))
        #expect(verdict.contains("undeclared_thing"))
        let mainLine = broken.split(separator: "\n", omittingEmptySubsequences: false)
            .firstIndex { $0.contains("undeclared_thing") }! + 1
        #expect(verdict.contains(":\(mainLine):"), "the log should name line \(mainLine): \(verdict.prefix(300))")
    }

    @Test(.enabled("a browser with WebGL2 is needed") { await HeadlessBrowser.hasWebGL2() })
    func theRewrittenMathComputesWhatMetalComputes() async throws {
        let metal = try Self.libraryText()
        let translation = WebShaderLibrary.translate(metal, wanted: ["domain"])
        let main = """
        out vec4 o;
        void main() {
            int x = int(gl_FragCoord.x);
            vec4 v = vec4(0.0, 0.0, 0.0, 1.0);
            if (x == 0) v.rg = vec2(0.5 + 0.25 * ollin_fmod(-1.5, 1.0), 0.5 + 0.25 * ollin_fmod(1.5, 1.0));
            else if (x == 1) v.rgb = ollin_select(vec3(0.0), vec3(1.0), ollin_gt(vec3(0.2, 0.5, 0.8), 0.5));
            else if (x == 2) v.rgb = srgbToLinear(vec3(0.5));
            else if (x == 3) { float p = -0.3; float cell = pmod(p, 1.0); v.rg = vec2(p + 0.5, cell + 0.5); }
            else if (x == 4) { float p = -2.0; float s = mirror(p, 0.5); v.rg = vec2(p * 0.25, s * 0.25 + 0.5); }
            else if (x == 5) { vec2 p = vec2(-0.3, 1.2); vec2 cell = pmod2(p, vec2(1.0)); v = vec4(p + 0.5, cell * 0.25 + 0.5); }
            o = v;
        }
        """
        let dom = try await HeadlessBrowser.dom(of: WebGLPage.pixels(fragment: Self.pageShader(translation, main: main), width: 6))
        let report = try #require(HeadlessBrowser.text(of: "r0", in: dom))
        #expect(!report.hasPrefix("FAIL"), "\(report.prefix(600))")
        let pixels = WebGLPage.bytes(from: report)
        try #require(pixels.count == 6)

        func near(_ a: Int, _ b: Double) -> Bool { abs(Double(a) - b * 255.0) <= 2.0 }

        // fmod(-1.5, 1.0) is -0.5 in Metal (truncating); GLSL's mod would say 0.5.
        #expect(near(pixels[0][0], 0.375), "\(pixels[0])")
        #expect(near(pixels[0][1], 0.625), "\(pixels[0])")
        // select picks the second where the condition holds, component-wise.
        #expect(pixels[1][0] == 0 && pixels[1][1] == 0 && pixels[1][2] == 255, "\(pixels[1])")
        // The sRGB curve in linear light.
        #expect(near(pixels[2][0], 0.21404), "\(pixels[2])")
        // pmod centers the cell: -0.3 stays -0.3 in cell 0.
        #expect(near(pixels[3][0], 0.2) && near(pixels[3][1], 0.5), "\(pixels[3])")
        // mirror folds -2.0 about 0.5 to 1.5 and reports the side it came from.
        #expect(near(pixels[4][0], 0.375) && near(pixels[4][1], 0.25), "\(pixels[4])")
        // pmod2 over both axes: (-0.3, 1.2) lands at (-0.3, 0.2) in cell (0, 1).
        #expect(near(pixels[5][0], 0.2) && near(pixels[5][1], 0.7), "\(pixels[5])")
        #expect(near(pixels[5][2], 0.5) && near(pixels[5][3], 0.75), "\(pixels[5])")
    }
}
