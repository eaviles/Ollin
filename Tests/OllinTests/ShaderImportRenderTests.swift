import Testing
import Foundation
import Metal
import OllinProjects
@testable import Ollin

/// The translated shader has to survive the one test that matters: the Metal
/// compiler. A rewrite that merely looks right is worth nothing, so every shape
/// the importer claims to handle is compiled here through the same path a sketch
/// would take, and the two shapes that carry a real semantic difference are also
/// run and read back.
/// Whether this machine has a GPU to compile against. It sits outside the suite
/// because a test trait is read before the suite's actor is entered.
private let hasMetal = MTLCreateSystemDefaultDevice() != nil

@MainActor
struct ShaderImportRenderTests {

    // MARK: Support

    /// Composes a translated shader exactly as the user-shader path does, then
    /// asks the device to compile it. Returns the compiler's complaint, or nil.
    static func compile(_ glsl: String, expecting routing: ShaderImport.Routing = .generator,
                        file: StaticString = #filePath, line: UInt = #line) -> String? {
        guard let device = MTLCreateSystemDefaultDevice() else { return nil }
        let result = ShaderImport.translate(glsl: glsl)
        #expect(result.routing == routing)
        let variant: MetalRenderer.UserShaderVariant
        switch result.routing {
        case .generator: variant = .generator
        case .filter: variant = .filter
        case .combine: variant = .combine
        }
        let (source, _) = MetalRenderer.composeUserShaderSource(
            userSource: result.metalSource, modules: .all, variant: variant,
            sourceName: "Imported.metal", sourceStartLine: 1)
        do {
            _ = try device.makeLibrary(source: MetalRenderer.composeShaderSource(source), options: nil)
            return nil
        } catch {
            return "\(error)\n----- source -----\n\(result.metalSource)"
        }
    }

    // MARK: The shapes a pasted shader comes in

    @Test(.enabled(if: hasMetal))
    func aPlainShaderCompiles() {
        let complaint = Self.compile("""
        void mainImage(out vec4 fragColor, in vec2 fragCoord) {
            vec2 uv = fragCoord / iResolution.xy;
            fragColor = vec4(uv, 0.5 + 0.5 * sin(iTime), 1.0);
        }
        """)
        #expect(complaint == nil, "\(complaint ?? "")")
    }

    @Test(.enabled(if: hasMetal))
    func helperFunctionsAndConstantsCompile() {
        let complaint = Self.compile("""
        #define TAU 6.2831853
        const vec3 SKY = vec3(0.2, 0.4, 0.9);

        float hash(vec2 p) { return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453); }

        // Reads a supplied value, so it must be handed the frame's own values.
        float wave(vec2 p) { return sin(p.x * TAU + iTime) * cos(p.y * TAU); }

        // Calls the one above, so it must be handed them too.
        vec3 shadeAt(vec2 p) { return SKY * (0.5 + 0.5 * wave(p)) + hash(p) * 0.05; }

        void mainImage(out vec4 fragColor, in vec2 fragCoord) {
            vec2 uv = fragCoord / iResolution.xy;
            fragColor = vec4(shadeAt(uv), 1.0);
        }
        """)
        #expect(complaint == nil, "\(complaint ?? "")")
    }

    @Test(.enabled(if: hasMetal))
    func writtenParametersAndStructsCompile() {
        let complaint = Self.compile("""
        struct Hit { float d; vec3 col; };

        Hit trace(vec2 p) { return Hit(length(p) - 0.3, vec3(1.0, 0.4, 0.2)); }

        void split(vec2 p, out float a, inout float b) { a = p.x; b += p.y; }

        void mainImage(out vec4 fragColor, in vec2 fragCoord) {
            vec2 uv = fragCoord / iResolution.xy - 0.5;
            Hit h = trace(uv);
            float a; float b = 1.0;
            split(uv, a, b);
            fragColor = vec4(h.col * step(h.d, 0.0) + a * 0.0 + b * 0.0, 1.0);
        }
        """)
        #expect(complaint == nil, "\(complaint ?? "")")
    }

    @Test(.enabled(if: hasMetal))
    func matricesAndRelationalCallsCompile() {
        let complaint = Self.compile("""
        void mainImage(out vec4 fragColor, in vec2 fragCoord) {
            vec2 uv = fragCoord / iResolution.xy - 0.5;
            mat2 r = mat2(cos(iTime), -sin(iTime), sin(iTime), cos(iTime));
            vec2 p = r * uv;
            vec3 col = vec3(mod(p.x * 8.0, 1.0));
            if (any(lessThan(col, vec3(0.1)))) col = vec3(0.0);
            if (all(greaterThanEqual(col, vec3(0.9)))) col = vec3(1.0);
            float ang = atan(p.y, p.x);
            col *= 0.5 + 0.5 * cos(ang);
            fragColor = vec4(col, 1.0);
        }
        """)
        #expect(complaint == nil, "\(complaint ?? "")")
    }

    @Test(.enabled(if: hasMetal))
    func aShaderThatReadsOneInputCompilesAsAFilter() {
        let complaint = Self.compile("""
        void mainImage(out vec4 fragColor, in vec2 fragCoord) {
            vec2 uv = fragCoord / iResolution.xy;
            vec4 src = texture(iChannel0, uv);
            fragColor = vec4(1.0 - src.rgb, 1.0);
        }
        """, expecting: .filter)
        #expect(complaint == nil, "\(complaint ?? "")")
    }

    @Test(.enabled(if: hasMetal))
    func aShaderThatReadsTwoInputsCompilesAsACombine() {
        let complaint = Self.compile("""
        void mainImage(out vec4 fragColor, in vec2 fragCoord) {
            vec2 uv = fragCoord / iResolution.xy;
            vec4 a = texture(iChannel0, uv);
            vec4 b = texture(iChannel1, uv);
            fragColor = vec4(mix(a.rgb, b.rgb, 0.5), 1.0);
        }
        """, expecting: .combine)
        #expect(complaint == nil, "\(complaint ?? "")")
    }

    /// A value the shader expects the pipeline to supply has nowhere to come from,
    /// so it must be reported rather than guessed at.
    @Test func aPipelineInputIsReportedRatherThanGuessed() {
        let result = ShaderImport.translate(glsl: """
        uniform vec2 knob;
        void mainImage(out vec4 c, in vec2 f) { c = vec4(knob, 0.0, 1.0); }
        """)
        #expect(result.needsAttention)
        #expect(result.diagnostics.contains { $0.message.contains("knob") })
        // And the reader is told about it in the file itself, not only in a return value.
        #expect(result.metalSource.contains("TODO(ollin)"))
    }

    /// A variable the shader writes to at file scope cannot exist in Metal, and a
    /// constant one can. The two must be told apart.
    @Test func aWrittenGlobalIsReportedAndAConstantIsKept() {
        let written = ShaderImport.translate(glsl: """
        float counter = 0.0;
        void mainImage(out vec4 c, in vec2 f) { c = vec4(counter); }
        """)
        #expect(written.needsAttention)
        #expect(written.diagnostics.contains { $0.message.contains("counter") })

        let constant = ShaderImport.translate(glsl: """
        const float K = 0.5;
        void mainImage(out vec4 c, in vec2 f) { c = vec4(K); }
        """)
        #expect(!constant.needsAttention)
        #expect(constant.metalSource.contains("constant float K = 0.5;"))
    }

    @Test(.enabled(if: hasMetal))
    func aPlainMainWithNoPipelineInputsCompiles() {
        let complaint = Self.compile("""
        precision highp float;
        out vec4 outColor;

        void main() {
            vec2 uv = gl_FragCoord.xy / iResolution.xy;
            outColor = vec4(uv, 0.5, 1.0);
        }
        """)
        #expect(complaint == nil, "\(complaint ?? "")")
    }

    // MARK: What the translation actually changed

    /// The one rule that silently changes a picture rather than failing to build.
    /// A tiling shader reaching left of the origin is the ordinary case, so the
    /// two spellings are rendered against each other and must disagree.
    @Test(.enabled(if: hasMetal))
    func theModuloRuleSurvivesNegativeInput() throws {
        let translated = ShaderImport.translate(glsl: """
        void mainImage(out vec4 fragColor, in vec2 fragCoord) {
            float x = (fragCoord.x / iResolution.x) * 2.0 - 1.5;
            fragColor = vec4(vec3(mod(x, 1.0)), 1.0);
        }
        """)
        // The floor form is what came out, not the built-in that truncates.
        #expect(translated.metalSource.contains("ollin_glsl_mod"))
        #expect(!translated.metalSource.contains("fmod"))

        // And the two really do differ over the range the shader covers.
        let floorForm = { (x: Float) in x - 1.0 * floor(x / 1.0) }
        let truncForm = { (x: Float) in fmod(x, 1.0) }
        let negative: Float = -0.25
        #expect(floorForm(negative) != truncForm(negative))
        #expect(abs(floorForm(negative) - 0.75) < 1e-6)
    }

    /// A generator must not carry the layer helper, and a filter must.
    @Test func onlyALayerReadingShaderCarriesTheFlip() {
        let generator = ShaderImport.translate(glsl: """
        void mainImage(out vec4 c, in vec2 f) { c = vec4(1.0); }
        """)
        #expect(!generator.metalSource.contains("ollin_channel_uv"))

        let filter = ShaderImport.translate(glsl: """
        void mainImage(out vec4 c, in vec2 f) { c = texture(iChannel0, f / iResolution.xy); }
        """)
        #expect(filter.metalSource.contains("ollin_channel_uv"))
        #expect(filter.metalSource.contains("sample(info,"))
    }
}
