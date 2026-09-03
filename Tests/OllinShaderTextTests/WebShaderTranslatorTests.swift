import Testing
import Foundation
@testable import OllinShaderText

/// Each rule of the Metal-to-GLSL rewrite, pinned on the smallest source that
/// exercises it. The output is compared as text because the layout is part of
/// the contract: a translated file should read as the source did.
struct WebShaderTranslatorTests {

    private func body(_ metal: String) -> String {
        WebShaderTranslator.translate(metal).body
    }

    @Test func storageWordsAndTypeNamesAreRewritten() {
        let out = body("static inline float3 f(float2 p, half h, int2 i) { return float3(p, h) + float3(i, 0); }")
        #expect(out == "vec3 f(vec2 p, float h, ivec2 i) { return vec3(p, h) + vec3(i, 0); }")
    }

    @Test func matricesAndTheNarrowIntegersWiden() {
        let out = body("float2x2 m(ushort a, float3x3 n) { return float2x2(n[0].xy, n[1].xy); }")
        #expect(out == "mat2 m(uint a, mat3 n) { return mat2(n[0].xy, n[1].xy); }")
    }

    @Test func aReferenceParameterBecomesInout() {
        let translation = WebShaderTranslator.translate(
            "static inline float pmod(thread float &p, float s) { p = fmod(p, s); return p; }")
        #expect(translation.body == "float pmod(inout float p, float s) { p = ollin_fmod(p, s); return p; }")
        #expect(translation.helpers == [.fmod])
        #expect(translation.isClean)
    }

    @Test func aReferenceSpelledOnTheTypeAlsoBecomesInout() {
        #expect(body("void f(thread float2& p) { p = -p; }") == "void f(inout vec2 p) { p = -p; }")
    }

    @Test func selectBecomesTheHelperAndItsComparisonACall() {
        let translation = WebShaderTranslator.translate(
            "float3 f(float3 c) { return select(c * 2.0, c, c > 0.5); }")
        #expect(translation.body == "vec3 f(vec3 c) { return ollin_select(c * 2.0, c, ollin_gt(c, 0.5)); }")
        #expect(translation.helpers == [.select, .greaterThan])
    }

    @Test func anyAndAllTakeTheSameComparisonRewrite() {
        let translation = WebShaderTranslator.translate(
            "bool f(float2 p) { return any(p < 0.0) || all((p >= float2(1.0))); }")
        #expect(translation.body == "bool f(vec2 p) { return any(ollin_lt(p, 0.0)) || all((ollin_ge(p, vec2(1.0)))); }")
        #expect(translation.helpers == [.lessThan, .greaterThanEqual])
    }

    @Test func aConditionThatIsNotOneComparisonIsLeftAlone() {
        // The helper still applies, but a compound condition is not reshaped: the
        // reader sees exactly what was written and the browser names the line.
        let out = body("float f(float a, bool m) { return select(a, 1.0, m) + select(a, 2.0, a > 1.0 && m); }")
        #expect(out == "float f(float a, bool m) { return ollin_select(a, 1.0, m) + ollin_select(a, 2.0, a > 1.0 && m); }")
    }

    @Test func aConstantArrayBecomesAnArrayConstructor() {
        let out = body("""
        constant float3 g[3] = {
            float3(1, 0, 0), float3(0, 1, 0),
            float3(0, 0, 1),
        };
        """)
        #expect(out == """
        const vec3 g[3] = vec3[3](
            vec3(1, 0, 0), vec3(0, 1, 0),
            vec3(0, 0, 1)
        );
        """)
    }

    @Test func aStructInitializerBecomesAConstructor() {
        let out = body("""
        struct Ray { float3 o; float3 d; };
        Ray make(float3 o) { Ray r = { o, float3(0, 0, 1) }; return r; }
        Ray other(float3 o) { return { o, o }; }
        Ray third(float3 o) { return Ray{ o, -o }; }
        """)
        #expect(out == """
        struct Ray { vec3 o; vec3 d; };
        Ray make(vec3 o) { Ray r = Ray( o, vec3(0, 0, 1) ); return r; }
        Ray other(vec3 o) { return Ray( o, o ); }
        Ray third(vec3 o) { return Ray( o, -o ); }
        """)
    }

    @Test func aLocalArrayOfStructsNestsItsConstructors() {
        let out = body("""
        struct P { float a; };
        float f() { P ps[2] = { {1.0}, {2.0} }; return ps[1].a; }
        """)
        #expect(out.contains("P ps[2] = P[2]( P(1.0), P(2.0) );"))
    }

    @Test func metalConstantsBecomeDefines() {
        let translation = WebShaderTranslator.translate("float f(float a) { return a * M_PI_F + M_E_F; }")
        #expect(translation.body == "float f(float a) { return a * M_PI_F + M_E_F; }")
        #expect(translation.constants == ["M_PI_F", "M_E_F"])
        #expect(translation.support.contains("#define M_PI_F 3.14159265358979"))
        #expect(translation.support.contains("#define M_E_F 2.71828182845905"))
    }

    @Test func bitCastsMapByTheirTargetWidth() {
        let translation = WebShaderTranslator.translate("""
        uint f(float x) { return as_type<uint>(x); }
        float g(uint u) { return as_type<float>(u); }
        int2 h(float2 v) { return as_type<int2>(v); }
        """)
        #expect(translation.body == """
        uint f(float x) { return floatBitsToUint(x); }
        float g(uint u) { return ollin_bits_to_float(u); }
        ivec2 h(vec2 v) { return floatBitsToInt(v); }
        """)
        #expect(translation.helpers == [.bitsToFloat])
    }

    @Test func halfLiteralsAndNamespacePrefixesGo() {
        let out = body("half f(half x) { return metal::sin(x) * 2.0h + fast::cos(x) - precise::sqrt(1.5H); }")
        #expect(out == "float f(float x) { return sin(x) * 2.0 + cos(x) - sqrt(1.5); }")
    }

    @Test func theRenamedBuiltinsAndTheHelpersAreSpliced() {
        let translation = WebShaderTranslator.translate(
            "float f(float2 p) { return atan2(p.y, p.x) + rsqrt(fabs(p.x)) + saturate(p.y) + fma(p.x, p.y, 1.0) + rint(p.x); }")
        #expect(translation.body == "float f(vec2 p) { return atan(p.y, p.x) + inversesqrt(abs(p.x)) + ollin_saturate(p.y) + ollin_fma(p.x, p.y, 1.0) + roundEven(p.x); }")
        #expect(translation.helpers == [.saturate, .fma])
        #expect(translation.support.contains("float ollin_saturate(float x)"))
        #expect(translation.support.contains("vec4 ollin_fma(vec4 a, vec4 b, vec4 c)"))
    }

    @Test func discardCrosses() {
        #expect(body("void f(float a) { if (a < 0.0) discard_fragment(); }")
                == "void f(float a) { if (a < 0.0) discard; }")
    }

    @Test func directivesKeepWorkingWithTheirTypesRenamed() {
        let out = body("""
        #include <metal_stdlib>
        using namespace metal;
        #define TWO(v) (float2(v) * 2.0)
        #pragma something
        float2 f(float x) { return TWO(x); }
        """)
        #expect(!out.contains("#include"))
        #expect(!out.contains("using"))
        #expect(!out.contains("#pragma"))
        #expect(out.contains("#define TWO(v) (vec2(v) * 2.0)"))
        #expect(out.contains("vec2 f(float x) { return TWO(x); }"))
    }

    @Test func theAuthorsLayoutAndCommentsSurvive() {
        let metal = """
        // A comment above.
        static inline float3 tint(float3 c,    float k) {
        \tfloat3 lo = c * k;   // trailing note

            /* a block
               comment */
            return select(lo, c, c > 0.5);
        }
        """
        let out = body(metal)
        #expect(out == """
        // A comment above.
        vec3 tint(vec3 c,    float k) {
        \tvec3 lo = c * k;   // trailing note

            /* a block
               comment */
            return ollin_select(lo, c, ollin_gt(c, 0.5));
        }
        """)
    }

    @Test func reservedNamesAreRespelled() {
        let translation = WebShaderTranslator.translate(
            "float f(float input, float sample) { float out = input + sample; return out; }")
        #expect(translation.body == "float f(float input_, float sample_) { float out_ = input_ + sample_; return out_; }")
        #expect(translation.diagnostics.count == 3)
        #expect(translation.diagnostics.allSatisfy { $0.severity == .note })
        #expect(translation.isClean)
    }

    @Test func aMemberNamedLikeAReservedWordIsRespelledWhereItIsRead() {
        #expect(body("float f(float2 p) { return p.x; }") == "float f(vec2 p) { return p.x; }")
        #expect(body("struct S { float sample; }; float f(S s) { return s.sample; }")
                == "struct S { float sample_; }; float f(S s) { return s.sample_; }")
    }

    @Test func aUserFunctionNamedLikeABuiltinWins() {
        let translation = WebShaderTranslator.translate(
            "float saturate(float x) { return x; } float f(float x) { return saturate(x) + fmod(x, 2.0); }")
        #expect(translation.body == "float saturate(float x) { return x; } float f(float x) { return saturate(x) + ollin_fmod(x, 2.0); }")
        #expect(translation.helpers == [.fmod])
    }

    @Test func aFileScopeConstantIsConst() {
        #expect(body("constant float K = 2.0;\nfloat f() { return K; }") == "const float K = 2.0;\nfloat f() { return K; }")
    }

    @Test func aConstantReferenceParameterPassesByValue() {
        #expect(body("float f(constant float2& p) { return p.x; }") == "float f(vec2 p) { return p.x; }")
    }

    @Test func whatCannotCrossIsNamed() {
        let translation = WebShaderTranslator.translate("""
        float4 look(texture2d<float> t, sampler s, float2 uv) { return t.sample(s, uv); }
        float sum(device float* values, int n) { return values[n]; }
        float4 shade(float2 uv [[stage_in]]) { return float4(uv, sincos(uv.x, uv.y)); }
        """)
        #expect(!translation.isClean)
        let messages = translation.unsupported.map(\.message)
        #expect(messages.contains { $0.contains("'texture2d'") })
        #expect(messages.contains { $0.contains("'.sample('") })
        #expect(messages.contains { $0.contains("'sum' takes a pointer") })
        #expect(messages.contains { $0.contains("[[stage_in]]") })
        #expect(messages.contains { $0.contains("'sincos'") })
        // A message names the line it is about.
        #expect(translation.unsupported.contains { $0.message.contains("'sum'") && $0.line == 2 })
    }

    @Test func anEntryPointIsRefused() {
        let translation = WebShaderTranslator.translate(
            "fragment float4 main_fragment(float4 pos [[position]]) { return pos; }")
        #expect(translation.unsupported.contains { $0.message.contains("'fragment' marks an entry point") })
    }

    @Test func nothingIsAddedOrRemovedFromTheTokenStream() {
        // Every rule edits in place, so the token count is the lexer's count.
        let metal = "static inline float3 f(thread float2 &p) { p = select(p, -p, p < 0.0); return float3(p, fmod(p.x, 1.0h)); }"
        let translation = WebShaderTranslator.translate(metal)
        #expect(translation.tokens.count == ShaderLexer.tokenize(metal).count)
    }

    @Test func theSupportTextIsOrderedAndComplete() {
        let support = WebShaderCompat.source(for: [.select, .fmod, .lessThan], constants: ["M_PI_F"])
        let defineAt = support.range(of: "#define M_PI_F")!.lowerBound
        let fmodAt = support.range(of: "float ollin_fmod(")!.lowerBound
        let ltAt = support.range(of: "bool ollin_lt(")!.lowerBound
        let selectAt = support.range(of: "float ollin_select(")!.lowerBound
        #expect(defineAt < fmodAt && fmodAt < ltAt && ltAt < selectAt)
        #expect(support.contains("bvec3 ollin_lt(vec3 a, float b) { return lessThan(a, vec3(b)); }"))
    }
}
