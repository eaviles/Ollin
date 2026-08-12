import Testing
import Foundation
@testable import OllinProjects

/// The translation, checked rule by rule. Each one is stated against what the
/// source said, so a rewrite that merely produces *something* cannot pass.
struct ShaderImportTests {

    // MARK: The rule that silently changes a picture

    /// The two languages round a modulo opposite ways, and only for negative
    /// input. Tiling a plane that reaches left of the origin is the ordinary
    /// thing this kind of shader does, so the built-in must never be used.
    @Test func moduloBecomesTheFlooringForm() {
        let result = ShaderImport.translate(glsl: """
        void mainImage(out vec4 c, in vec2 f) { c = vec4(mod(f.x, 2.0)); }
        """)
        #expect(result.metalSource.contains("ollin_glsl_mod(f.x, 2.0)"))
        #expect(result.metalSource.contains("x - y * floor(x / y)"))
        #expect(!result.metalSource.contains("fmod"))
    }

    /// And the helper is left out of a shader that never asked for one.
    @Test func aShaderWithNoModuloCarriesNoHelper() {
        let result = ShaderImport.translate(glsl: """
        void mainImage(out vec4 c, in vec2 f) { c = vec4(f.x); }
        """)
        #expect(!result.metalSource.contains("ollin_glsl_mod"))
    }

    // MARK: Names

    @Test func typesAreRenamed() {
        let result = ShaderImport.translate(glsl: """
        void mainImage(out vec4 c, in vec2 f) {
            vec3 a = vec3(1.0); mat2 m = mat2(1.0, 0.0, 0.0, 1.0); ivec2 i = ivec2(0);
            c = vec4(a * m[0].x + float(i.x), 1.0);
        }
        """)
        #expect(result.metalSource.contains("float3 a = float3(1.0);"))
        #expect(result.metalSource.contains("float2x2 m = float2x2("))
        #expect(result.metalSource.contains("int2 i = int2(0);"))
        #expect(!result.metalSource.contains("vec3"))
    }

    /// The arc tangent is one name over two argument counts in GLSL and two
    /// names in Metal, so the count is what picks the spelling.
    @Test func theArcTangentPicksItsNameByArgumentCount() {
        let result = ShaderImport.translate(glsl: """
        void mainImage(out vec4 c, in vec2 f) { c = vec4(atan(f.y, f.x) + atan(f.x)); }
        """)
        #expect(result.metalSource.contains("atan2(f.y, f.x)"))
        #expect(result.metalSource.contains("atan(f.x)"))
    }

    @Test func comparisonsBecomeOperators() {
        let result = ShaderImport.translate(glsl: """
        void mainImage(out vec4 c, in vec2 f) {
            c = vec4(any(lessThan(f, vec2(1.0))) && all(greaterThanEqual(f, vec2(0.0))));
        }
        """)
        #expect(result.metalSource.contains("(f < float2(1.0))"))
        #expect(result.metalSource.contains("(f >= float2(0.0))"))
        #expect(!result.metalSource.contains("lessThan"))
    }

    @Test func aWrittenParameterBecomesAReference() {
        let result = ShaderImport.translate(glsl: """
        void split(in vec2 p, out float a, inout float b) { a = p.x; b += p.y; }
        void mainImage(out vec4 c, in vec2 f) { float a; float b = 0.0; split(f, a, b); c = vec4(a, b, 0, 1); }
        """)
        #expect(result.metalSource.contains("void split(float2 p, thread float &a, thread float &b)"))
    }

    @Test func aStructIsBuiltTheMetalWay() {
        let result = ShaderImport.translate(glsl: """
        struct Hit { float d; vec3 col; };
        void mainImage(out vec4 c, in vec2 f) { Hit h = Hit(0.0, vec3(1.0)); c = vec4(h.col, 1.0); }
        """)
        #expect(result.metalSource.contains("Hit h = Hit{0.0, float3(1.0)}"))
    }

    // MARK: The values the site supplies

    @Test func suppliedValuesBecomeFieldsOfInfo() {
        let result = ShaderImport.translate(glsl: """
        void mainImage(out vec4 c, in vec2 f) {
            c = vec4(iTime, iResolution.xy / 2.0, float(iFrame));
        }
        """)
        #expect(result.metalSource.contains("info.time"))
        #expect(result.metalSource.contains("info.resolution.xy"))
        #expect(result.metalSource.contains("int(info.frame)"))
        #expect(!result.metalSource.contains("iTime"))
    }

    /// A supplied value is a global in the language this came from and cannot be
    /// one in Metal, so it travels as a parameter. It must reach the functions
    /// that need it, and must not clutter the ones that do not.
    @Test func infoTravelsOnlyAsFarAsItIsNeeded() {
        let result = ShaderImport.translate(glsl: """
        float pure(vec2 p) { return dot(p, p); }
        float reads(vec2 p) { return p.x + iTime; }
        float calls(vec2 p) { return reads(p) * 2.0; }
        void mainImage(out vec4 c, in vec2 f) { c = vec4(pure(f) + calls(f)); }
        """)
        #expect(result.metalSource.contains("float pure(float2 p) {"))
        #expect(result.metalSource.contains("float reads(float2 p, ShaderInfo info)"))
        #expect(result.metalSource.contains("float calls(float2 p, ShaderInfo info)"))
        // And the calls carry it too.
        #expect(result.metalSource.contains("reads(p, info)"))
        #expect(result.metalSource.contains("calls(f, info)"))
        #expect(result.metalSource.contains("pure(f)"))
        #expect(!result.metalSource.contains("pure(f, info)"))
    }

    // MARK: How many inputs, and what that makes it

    @Test func howManyInputsDecidesWhatTheShaderBecomes() {
        func routing(_ glsl: String) -> ShaderImport.Routing {
            ShaderImport.translate(glsl: glsl).routing
        }
        #expect(routing("void mainImage(out vec4 c, in vec2 f) { c = vec4(1.0); }") == .generator)
        #expect(routing("void mainImage(out vec4 c, in vec2 f) { c = texture(iChannel0, f); }") == .filter)
        #expect(routing("""
        void mainImage(out vec4 c, in vec2 f) { c = texture(iChannel0, f) + texture(iChannel1, f); }
        """) == .combine)
    }

    /// A texture is measured from its bottom edge and a layer from its top, so a
    /// coordinate must turn over on the way in. Without this every imported
    /// filter comes out upside down.
    @Test func aLayerReadTurnsTheCoordinateOver() {
        let result = ShaderImport.translate(glsl: """
        void mainImage(out vec4 c, in vec2 f) { c = texture(iChannel0, f / iResolution.xy); }
        """)
        #expect(result.metalSource.contains("sample(info, ollin_channel_uv(f / info.resolution.xy))"))
        #expect(result.metalSource.contains("return float2(uv.x, 1.0 - uv.y);"))
    }

    @Test func moreInputsThanThereAreLayersIsReported() {
        let result = ShaderImport.translate(glsl: """
        void mainImage(out vec4 c, in vec2 f) {
            c = texture(iChannel0, f) + texture(iChannel1, f) + texture(iChannel2, f);
        }
        """)
        #expect(result.needsAttention)
    }

    // MARK: The entry point

    @Test func theEntryPointIsWrittenAroundTheShader() {
        let result = ShaderImport.translate(glsl: """
        void mainImage(out vec4 c, in vec2 f) { c = vec4(1.0); }
        """)
        #expect(result.metalSource.contains("float4 shade(float2 uv, ShaderInfo info) {"))
        // The pixel position arrives measured from the bottom, in pixels.
        #expect(result.metalSource.contains("float2 fragCoord = float2(uv.x, 1.0 - uv.y) * info.resolution;"))
        // And the fourth channel is held opaque, which is what the source did.
        #expect(result.metalSource.contains("return float4(fragColor.rgb, 1.0);"))
    }

    @Test func aShaderWithNoEntryPointSaysSo() {
        let result = ShaderImport.translate(glsl: "float f(vec2 p) { return p.x; }")
        #expect(result.needsAttention)
        #expect(result.diagnostics.contains { $0.message.contains("No entry point") })
    }

    // MARK: What the reader is told

    @Test func theHeaderKeepsWhereItCameFrom() {
        let result = ShaderImport.translate(
            glsl: "void mainImage(out vec4 c, in vec2 f) { c = vec4(1.0); }",
            provenance: .init(title: "Sea", author: "someone", url: "https://example.invalid/view/abc"))
        #expect(result.metalSource.contains("Shader: Sea"))
        #expect(result.metalSource.contains("Author: someone"))
        #expect(result.metalSource.contains("Source: https://example.invalid/view/abc"))
        #expect(result.metalSource.contains("under the terms its author gave it"))
    }

    /// The author's own layout and comments are what make the result editable, so
    /// the translation must leave everything it did not have a reason to change.
    @Test func theAuthorsLayoutAndCommentsSurvive() {
        let result = ShaderImport.translate(glsl: """
        // A comment worth keeping.
        void mainImage(out vec4 fragColor, in vec2 fragCoord) {

            float a = 1.0;    // trailing note

            fragColor = vec4(a);
        }
        """)
        #expect(result.metalSource.contains("// A comment worth keeping."))
        #expect(result.metalSource.contains("float a = 1.0;    // trailing note"))
        #expect(result.metalSource.contains("\n\n    float a"))
    }

    /// Two runs must agree, so a generated project can be committed.
    @Test func theSameShaderTranslatesTheSameWayTwice() {
        let glsl = """
        const float K = 2.0;
        float f(vec2 p) { return mod(p.x, K) + iTime; }
        void mainImage(out vec4 c, in vec2 g) { c = vec4(f(g)); }
        """
        #expect(ShaderImport.translate(glsl: glsl).metalSource
                == ShaderImport.translate(glsl: glsl).metalSource)
    }
}

/// The project written around an imported shader.
struct ImportedShaderProjectTests {

    static func request(_ glsl: String, kind: ProjectKind = .macSketch,
                        destination: URL = URL(fileURLWithPath: "/tmp/ollin-import-test")) -> ProjectRequest {
        let result = ShaderImport.translate(glsl: glsl)
        return ProjectRequest(
            name: "Imported", kind: kind, template: .blank,
            importedShader: ImportedShader(result),
            destination: destination,
            framework: .localPath(URL(fileURLWithPath: "/tmp/ollin")))
    }

    static let generatorGLSL = "void mainImage(out vec4 c, in vec2 f) { c = vec4(1.0); }"
    static let filterGLSL = "void mainImage(out vec4 c, in vec2 f) { c = texture(iChannel0, f); }"
    static let combineGLSL = """
    void mainImage(out vec4 c, in vec2 f) { c = texture(iChannel0, f) + texture(iChannel1, f); }
    """

    @Test func aShaderProjectKeepsTheShaderInItsOwnFile() throws {
        let project = try ProjectGenerator.plan(Self.request(Self.generatorGLSL))
        let shader = try #require(project.files.first { $0.path.hasSuffix("imported.metal") })
        #expect(shader.contents.contains("float4 shade(float2 uv, ShaderInfo info)"))

        let manifest = try #require(project.files.first { $0.path == "Package.swift" })
        // Copied, not processed: a processed shader is compiled into a library
        // instead of staying the source the sketch loads.
        #expect(manifest.contents.contains(".copy(\"imported.metal\")"))

        let sketch = try #require(project.files.first { $0.path.hasSuffix("Sketch.swift") })
        #expect(sketch.contents.contains("Shader(resource: \"imported\", in: .module)"))
        #expect(sketch.contents.contains("generate(imported)"))
    }

    /// One loose file has no target to declare a resource on, so the shader has
    /// to travel inside the Swift source.
    @Test func aLooseFileCarriesTheShaderInline() throws {
        let project = try ProjectGenerator.plan(Self.request(Self.generatorGLSL, kind: .singleFile))
        #expect(!project.files.contains { $0.path.hasSuffix(".metal") })
        let sketch = try #require(project.files.first { $0.path.hasSuffix(".swift") })
        #expect(sketch.contents.contains("Shader(#\"\"\""))
        #expect(sketch.contents.contains("float4 shade(float2 uv, ShaderInfo info)"))
    }

    @Test func theSketchMatchesHowManyInputsTheShaderReads() throws {
        func sketch(_ glsl: String) throws -> String {
            let project = try ProjectGenerator.plan(Self.request(glsl))
            return try #require(project.files.first { $0.path.hasSuffix("Sketch.swift") }).contents
        }
        #expect(try sketch(Self.generatorGLSL).contains("generate(imported)"))

        let filter = try sketch(Self.filterGLSL)
        #expect(filter.contains("layer.filtered(.shader(imported))"))
        #expect(filter.contains("withTarget(layer)"))

        let combine = try sketch(Self.combineGLSL)
        #expect(combine.contains("base.combined(with: aux, .shader(imported))"))
    }

    @Test func aShaderNeedingAHandSaysSoInTheSketch() throws {
        let project = try ProjectGenerator.plan(Self.request("""
        uniform vec2 knob;
        void mainImage(out vec4 c, in vec2 f) { c = vec4(knob, 0.0, 1.0); }
        """))
        let sketch = try #require(project.files.first { $0.path.hasSuffix("Sketch.swift") })
        #expect(sketch.contents.contains("TODO(ollin)"))
    }
}
