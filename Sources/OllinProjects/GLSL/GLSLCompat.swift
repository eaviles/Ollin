import Foundation

/// The small Metal functions a translated shader may need, spliced in only when
/// the translation actually used one. Each stands in for a GLSL built-in that
/// Metal either spells differently or does not provide.
enum GLSLCompat {

    /// A helper the output needs. The raw value is the name the translation calls,
    /// so a pass records what it used by inserting the case.
    enum Helper: String, CaseIterable, Comparable {
        case mod = "ollin_glsl_mod"
        case inverse = "ollin_glsl_inverse"
        case matrixCompMult = "ollin_glsl_matrix_comp_mult"

        static func < (a: Helper, b: Helper) -> Bool { a.rawValue < b.rawValue }
    }

    /// The source for a set of helpers, in a fixed order so two runs of the
    /// importer produce the same file.
    static func source(for helpers: Set<Helper>) -> String {
        guard !helpers.isEmpty else { return "" }
        var parts: [String] = []
        for helper in helpers.sorted() {
            parts.append(body(of: helper))
        }
        return parts.joined(separator: "\n\n")
    }

    private static func body(of helper: Helper) -> String {
        switch helper {
        case .mod:
            // The two languages disagree here, and only for negative inputs: one
            // takes the floor of the quotient and the other truncates it, so the
            // results differ in sign. Tiling a plane that reaches left of or below
            // the origin is exactly the case that goes wrong, and it is the most
            // common thing this kind of shader does, so the built-in cannot be
            // used and the floor form is written out instead.
            return """
            inline float  ollin_glsl_mod(float  x, float  y) { return x - y * floor(x / y); }
            inline float2 ollin_glsl_mod(float2 x, float2 y) { return x - y * floor(x / y); }
            inline float3 ollin_glsl_mod(float3 x, float3 y) { return x - y * floor(x / y); }
            inline float4 ollin_glsl_mod(float4 x, float4 y) { return x - y * floor(x / y); }
            inline float2 ollin_glsl_mod(float2 x, float  y) { return x - y * floor(x / y); }
            inline float3 ollin_glsl_mod(float3 x, float  y) { return x - y * floor(x / y); }
            inline float4 ollin_glsl_mod(float4 x, float  y) { return x - y * floor(x / y); }
            """
        case .inverse:
            // Metal has no matrix inverse. These two cover what a fragment shader
            // normally inverts; a 4x4 has to be written by hand.
            return """
            inline float2x2 ollin_glsl_inverse(float2x2 m) {
                float d = m[0][0] * m[1][1] - m[1][0] * m[0][1];
                return float2x2(float2( m[1][1], -m[0][1]),
                                float2(-m[1][0],  m[0][0])) * (1.0 / d);
            }
            inline float3x3 ollin_glsl_inverse(float3x3 m) {
                float3 a = m[0], b = m[1], c = m[2];
                float3 r0 = cross(b, c), r1 = cross(c, a), r2 = cross(a, b);
                float d = dot(a, r0);
                return float3x3(float3(r0.x, r1.x, r2.x),
                                float3(r0.y, r1.y, r2.y),
                                float3(r0.z, r1.z, r2.z)) * (1.0 / d);
            }
            """
        case .matrixCompMult:
            return """
            inline float2x2 ollin_glsl_matrix_comp_mult(float2x2 a, float2x2 b) {
                return float2x2(a[0] * b[0], a[1] * b[1]);
            }
            inline float3x3 ollin_glsl_matrix_comp_mult(float3x3 a, float3x3 b) {
                return float3x3(a[0] * b[0], a[1] * b[1], a[2] * b[2]);
            }
            inline float4x4 ollin_glsl_matrix_comp_mult(float4x4 a, float4x4 b) {
                return float4x4(a[0] * b[0], a[1] * b[1], a[2] * b[2], a[3] * b[3]);
            }
            """
        }
    }

    /// Type names that map one to one.
    static let typeNames: [String: String] = [
        "vec2": "float2", "vec3": "float3", "vec4": "float4",
        "ivec2": "int2", "ivec3": "int3", "ivec4": "int4",
        "uvec2": "uint2", "uvec3": "uint3", "uvec4": "uint4",
        "bvec2": "bool2", "bvec3": "bool3", "bvec4": "bool4",
        "mat2": "float2x2", "mat3": "float3x3", "mat4": "float4x4",
        "mat2x2": "float2x2", "mat2x3": "float2x3", "mat2x4": "float2x4",
        "mat3x2": "float3x2", "mat3x3": "float3x3", "mat3x4": "float3x4",
        "mat4x2": "float4x2", "mat4x3": "float4x3", "mat4x4": "float4x4",
    ]

    /// Built-ins whose only difference is the name.
    static let renamedFunctions: [String: String] = [
        "inversesqrt": "rsqrt",
        "dFdx": "dfdx", "dFdy": "dfdy",
        "dFdxFine": "dfdx", "dFdyFine": "dfdy",
        "dFdxCoarse": "dfdx", "dFdyCoarse": "dfdy",
        "roundEven": "rint",
    ]

    /// Comparisons that GLSL spells as a call and Metal spells as an operator. The
    /// rewrite drops the name and turns the argument comma into the operator.
    static let relationalOperators: [String: String] = [
        "lessThan": "<", "lessThanEqual": "<=",
        "greaterThan": ">", "greaterThanEqual": ">=",
        "equal": "==", "notEqual": "!=",
    ]

    /// Names with no Metal counterpart worth writing out. Each becomes a note in
    /// the translated file rather than a silent change.
    static let unsupportedFunctions: [String: String] = [
        "outerProduct": "Metal has no outerProduct; write the product out by hand.",
        "packSnorm2x16": "Metal spells the packing functions differently; pack by hand.",
        "unpackSnorm2x16": "Metal spells the packing functions differently; unpack by hand.",
        "packUnorm2x16": "Metal spells the packing functions differently; pack by hand.",
        "unpackUnorm2x16": "Metal spells the packing functions differently; unpack by hand.",
        "textureGather": "A gather has no layer equivalent here; sample the four texels.",
        "textureProj": "Divide by the last component yourself, then sample.",
        "imageLoad": "Image load and store belong to a compute kernel, not this pass.",
        "imageStore": "Image load and store belong to a compute kernel, not this pass.",
    ]
}
