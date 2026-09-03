import Foundation

/// The GLSL ES 3.00 side of the Metal-to-GLSL rewrite: the names that map one to
/// one, the small helpers a page needs where the two languages disagree, the
/// named constants Metal's standard library supplies, and the words GLSL keeps
/// for itself. It is the import's table read the other way: where the import
/// splices a Metal helper for a GLSL built-in Metal lacks, this splices a GLSL
/// helper for a Metal built-in GLSL lacks, and only when the translation used it.
package enum WebShaderCompat {

    /// A helper the page needs. The raw value is the name the translation calls,
    /// so a pass records what it used by inserting the case.
    package enum Helper: String, CaseIterable, Comparable, Sendable {
        /// Metal's `fmod` truncates the quotient where GLSL's `mod` floors it, so
        /// the truncating form is written out rather than mapped onto `mod`.
        case fmod = "ollin_fmod"
        /// Metal's `select(a, b, c)` picks `b` where `c` is true, component-wise.
        case select = "ollin_select"
        case saturate = "ollin_saturate"
        case fma = "ollin_fma"
        /// `as_type<float>` from an integer, where GLSL has one function per width.
        case bitsToFloat = "ollin_bits_to_float"
        /// The vector comparisons GLSL spells as calls. Each takes a scalar or a
        /// vector on either side, so the rewrite needs no knowledge of the types.
        case lessThan = "ollin_lt"
        case lessThanEqual = "ollin_le"
        case greaterThan = "ollin_gt"
        case greaterThanEqual = "ollin_ge"
        case equal = "ollin_eq"
        case notEqual = "ollin_ne"

        package static func < (a: Helper, b: Helper) -> Bool { a.rawValue < b.rawValue }
    }

    /// What every page shader starts with. A fragment shader must state a float
    /// precision before anything else in GLSL ES.
    package static let preamble = "#version 300 es\nprecision highp float;\nprecision highp int;\n"

    /// The support text a translation needs ahead of its body: the constants it
    /// read, then the helpers it called, in a fixed order so two runs produce the
    /// same file.
    package static func source(for helpers: Set<Helper>, constants: Set<String>) -> String {
        var parts: [String] = []
        let defines = constants.sorted().compactMap { name -> String? in
            guard let value = constantValues[name] else { return nil }
            return "#define \(name) \(value)"
        }
        if !defines.isEmpty { parts.append(defines.joined(separator: "\n")) }
        for helper in helpers.sorted() {
            parts.append(body(of: helper))
        }
        return parts.joined(separator: "\n\n")
    }

    private static func body(of helper: Helper) -> String {
        switch helper {
        case .fmod:
            return """
            float ollin_fmod(float x, float y) { return x - y * trunc(x / y); }
            vec2 ollin_fmod(vec2 x, vec2 y) { return x - y * trunc(x / y); }
            vec3 ollin_fmod(vec3 x, vec3 y) { return x - y * trunc(x / y); }
            vec4 ollin_fmod(vec4 x, vec4 y) { return x - y * trunc(x / y); }
            vec2 ollin_fmod(vec2 x, float y) { return x - y * trunc(x / y); }
            vec3 ollin_fmod(vec3 x, float y) { return x - y * trunc(x / y); }
            vec4 ollin_fmod(vec4 x, float y) { return x - y * trunc(x / y); }
            """
        case .select:
            return """
            float ollin_select(float a, float b, bool c) { return c ? b : a; }
            vec2 ollin_select(vec2 a, vec2 b, bvec2 c) { return mix(a, b, c); }
            vec3 ollin_select(vec3 a, vec3 b, bvec3 c) { return mix(a, b, c); }
            vec4 ollin_select(vec4 a, vec4 b, bvec4 c) { return mix(a, b, c); }
            int ollin_select(int a, int b, bool c) { return c ? b : a; }
            ivec2 ollin_select(ivec2 a, ivec2 b, bvec2 c) { return ivec2(c.x ? b.x : a.x, c.y ? b.y : a.y); }
            ivec3 ollin_select(ivec3 a, ivec3 b, bvec3 c) { return ivec3(c.x ? b.x : a.x, c.y ? b.y : a.y, c.z ? b.z : a.z); }
            ivec4 ollin_select(ivec4 a, ivec4 b, bvec4 c) { return ivec4(c.x ? b.x : a.x, c.y ? b.y : a.y, c.z ? b.z : a.z, c.w ? b.w : a.w); }
            """
        case .saturate:
            return """
            float ollin_saturate(float x) { return clamp(x, 0.0, 1.0); }
            vec2 ollin_saturate(vec2 x) { return clamp(x, 0.0, 1.0); }
            vec3 ollin_saturate(vec3 x) { return clamp(x, 0.0, 1.0); }
            vec4 ollin_saturate(vec4 x) { return clamp(x, 0.0, 1.0); }
            """
        case .fma:
            return """
            float ollin_fma(float a, float b, float c) { return a * b + c; }
            vec2 ollin_fma(vec2 a, vec2 b, vec2 c) { return a * b + c; }
            vec3 ollin_fma(vec3 a, vec3 b, vec3 c) { return a * b + c; }
            vec4 ollin_fma(vec4 a, vec4 b, vec4 c) { return a * b + c; }
            """
        case .bitsToFloat:
            return """
            float ollin_bits_to_float(int v) { return intBitsToFloat(v); }
            float ollin_bits_to_float(uint v) { return uintBitsToFloat(v); }
            vec2 ollin_bits_to_float(ivec2 v) { return intBitsToFloat(v); }
            vec2 ollin_bits_to_float(uvec2 v) { return uintBitsToFloat(v); }
            vec3 ollin_bits_to_float(ivec3 v) { return intBitsToFloat(v); }
            vec3 ollin_bits_to_float(uvec3 v) { return uintBitsToFloat(v); }
            vec4 ollin_bits_to_float(ivec4 v) { return intBitsToFloat(v); }
            vec4 ollin_bits_to_float(uvec4 v) { return uintBitsToFloat(v); }
            """
        case .lessThan: return relational("ollin_lt", operator: "<", vector: "lessThan")
        case .lessThanEqual: return relational("ollin_le", operator: "<=", vector: "lessThanEqual")
        case .greaterThan: return relational("ollin_gt", operator: ">", vector: "greaterThan")
        case .greaterThanEqual: return relational("ollin_ge", operator: ">=", vector: "greaterThanEqual")
        case .equal: return relational("ollin_eq", operator: "==", vector: "equal")
        case .notEqual: return relational("ollin_ne", operator: "!=", vector: "notEqual")
        }
    }

    /// One comparison helper over the float and int families, with the scalar
    /// broadcast on either side that Metal's operators allow.
    private static func relational(_ name: String, operator op: String, vector: String) -> String {
        var lines: [String] = []
        lines.append("bool \(name)(float a, float b) { return a \(op) b; }")
        lines.append("bool \(name)(int a, int b) { return a \(op) b; }")
        for n in 2...4 {
            for (v, s, b) in [("vec\(n)", "float", "bvec\(n)"), ("ivec\(n)", "int", "bvec\(n)")] {
                lines.append("\(b) \(name)(\(v) a, \(v) b) { return \(vector)(a, b); }")
                lines.append("\(b) \(name)(\(v) a, \(s) b) { return \(vector)(a, \(v)(b)); }")
                lines.append("\(b) \(name)(\(s) a, \(v) b) { return \(vector)(\(v)(a), b); }")
            }
        }
        return lines.joined(separator: "\n")
    }

    /// The comparison helper for an operator token.
    package static func relationalHelper(for op: String) -> Helper? {
        switch op {
        case "<": return .lessThan
        case "<=": return .lessThanEqual
        case ">": return .greaterThan
        case ">=": return .greaterThanEqual
        case "==": return .equal
        case "!=": return .notEqual
        default: return nil
        }
    }

    /// Type names that map one to one. A half is a float on the page (GLSL ES
    /// has no 16-bit type in a fragment shader), and the narrow integers widen.
    package static let typeNames: [String: String] = [
            "float2": "vec2", "float3": "vec3", "float4": "vec4",
            "half": "float", "half2": "vec2", "half3": "vec3", "half4": "vec4",
            "int2": "ivec2", "int3": "ivec3", "int4": "ivec4",
            "uint2": "uvec2", "uint3": "uvec3", "uint4": "uvec4",
            "bool2": "bvec2", "bool3": "bvec3", "bool4": "bvec4",
            "short": "int", "short2": "ivec2", "short3": "ivec3", "short4": "ivec4",
            "ushort": "uint", "ushort2": "uvec2", "ushort3": "uvec3", "ushort4": "uvec4",
            "char": "int", "char2": "ivec2", "char3": "ivec3", "char4": "ivec4",
            "uchar": "uint", "uchar2": "uvec2", "uchar3": "uvec3", "uchar4": "uvec4",
            "long": "int", "ulong": "uint", "size_t": "uint", "ptrdiff_t": "int",
            "float2x2": "mat2", "float3x3": "mat3", "float4x4": "mat4",
            "float2x3": "mat2x3", "float2x4": "mat2x4", "float3x2": "mat3x2",
            "float3x4": "mat3x4", "float4x2": "mat4x2", "float4x3": "mat4x3",
            "half2x2": "mat2", "half3x3": "mat3", "half4x4": "mat4",
            "packed_float2": "vec2", "packed_float3": "vec3", "packed_float4": "vec4",
            "packed_half2": "vec2", "packed_half3": "vec3", "packed_half4": "vec4",
        ]

    /// Built-ins whose only difference is the name.
    package static let renamedFunctions: [String: String] = [
        "atan2": "atan",
        "fabs": "abs",
        "rsqrt": "inversesqrt",
        "dfdx": "dFdx", "dfdy": "dFdy",
        "rint": "roundEven",
        "fmin": "min", "fmax": "max",
        "powr": "pow",
        "mad": "ollin_fma",
    ]

    /// Names with no GLSL ES 3.00 form worth writing out. Each becomes a note in
    /// the translated file rather than a silent change.
    package static let unsupportedFunctions: [String: String] = [
        "sincos": "GLSL has no sincos; call sin and cos.",
        "ldexp": "GLSL ES 3.00 has no ldexp; multiply by exp2 of the exponent.",
        "frexp": "GLSL ES 3.00 has no frexp; take log2 and exp2 by hand.",
        "popcount": "GLSL ES 3.00 has no bit count.",
        "clz": "GLSL ES 3.00 has no leading-zero count.",
        "reverse_bits": "GLSL ES 3.00 has no bit reversal.",
        "extract_bits": "GLSL ES 3.00 has no bit-field extract; shift and mask by hand.",
        "insert_bits": "GLSL ES 3.00 has no bit-field insert; shift and mask by hand.",
        "copysign": "GLSL has no copysign; use abs and sign.",
        "min3": "GLSL has no min3; nest two min calls.",
        "max3": "GLSL has no max3; nest two max calls.",
        "median3": "GLSL has no median3; write it from min and max.",
        "sinpi": "GLSL has no sinpi; multiply by pi and call sin.",
        "cospi": "GLSL has no cospi; multiply by pi and call cos.",
        "tanpi": "GLSL has no tanpi; multiply by pi and call tan.",
        "exp10": "GLSL has no exp10; use pow(10.0, x).",
        "log10": "GLSL has no log10; divide log(x) by log(10.0).",
        "fdim": "GLSL has no fdim; write max(x - y, 0.0).",
        "nextafter": "GLSL has no nextafter.",
        "simd_sum": "A SIMD-group reduction has no place in a page fragment.",
        "simd_shuffle": "A SIMD-group shuffle has no place in a page fragment.",
        "sizeof": "GLSL has no sizeof.",
    ]

    /// Texture and sampler types and the member calls a texture answers. The page
    /// binds a layer through its own seam, so a read spelled against a Metal
    /// texture is reported rather than guessed at.
    package static let textureTypes: Set<String> = [
        "texture1d", "texture2d", "texture3d", "texturecube", "texture2d_array",
        "texture1d_array", "texturecube_array", "texture2d_ms", "depth2d", "depthcube",
        "depth2d_array", "sampler", "texture_buffer",
    ]
    package static let textureMembers: Set<String> = [
        "sample", "read", "write", "gather", "get_width", "get_height", "get_depth",
        "get_num_mip_levels", "get_num_samples", "sample_compare",
    ]

    /// Address-space words a page has no room for: anything that points into a
    /// buffer another stage wrote.
    package static let bufferAddressSpaces: Set<String> = [
        "device", "threadgroup", "threadgroup_imageblock", "ray_data", "object_data",
    ]

    /// Entry-point and template words that belong to the wrapper, never to the
    /// body a page carries.
    package static let entryPointWords: Set<String> = ["vertex", "fragment", "kernel", "visible", "intersection"]

    /// The named constants Metal's standard library supplies, as the literal each
    /// stands for. Emitted as a `#define` so the body keeps the name.
    package static let constantValues: [String: String] = [
        "M_PI_F": "3.14159265358979", "M_PI_H": "3.14159265358979", "M_PI": "3.14159265358979",
        "M_PI_2_F": "1.57079632679490", "M_PI_2_H": "1.57079632679490", "M_PI_2": "1.57079632679490",
        "M_PI_4_F": "0.785398163397448", "M_PI_4_H": "0.785398163397448", "M_PI_4": "0.785398163397448",
        "M_1_PI_F": "0.318309886183791", "M_1_PI_H": "0.318309886183791", "M_1_PI": "0.318309886183791",
        "M_2_PI_F": "0.636619772367581", "M_2_PI_H": "0.636619772367581", "M_2_PI": "0.636619772367581",
        "M_2_SQRTPI_F": "1.12837916709551", "M_2_SQRTPI": "1.12837916709551",
        "M_E_F": "2.71828182845905", "M_E_H": "2.71828182845905", "M_E": "2.71828182845905",
        "M_LOG2E_F": "1.44269504088896", "M_LOG2E": "1.44269504088896",
        "M_LOG10E_F": "0.434294481903252", "M_LOG10E": "0.434294481903252",
        "M_LN2_F": "0.693147180559945", "M_LN2": "0.693147180559945",
        "M_LN10_F": "2.30258509299405", "M_LN10": "2.30258509299405",
        "M_SQRT2_F": "1.41421356237310", "M_SQRT2_H": "1.41421356237310", "M_SQRT2": "1.41421356237310",
        "M_SQRT1_2_F": "0.707106781186548", "M_SQRT1_2_H": "0.707106781186548", "M_SQRT1_2": "0.707106781186548",
        "FLT_MAX": "3.402823466e+38", "FLT_MIN": "1.175494351e-38", "FLT_EPSILON": "1.192092896e-07",
        "MAXFLOAT": "3.402823466e+38", "HALF_MAX": "65504.0", "HALF_MIN": "6.103515625e-05",
        "HALF_EPSILON": "0.0009765625",
        "INFINITY": "uintBitsToFloat(0x7f800000u)", "HUGE_VALF": "uintBitsToFloat(0x7f800000u)",
        "NAN": "uintBitsToFloat(0x7fc00000u)",
        "INT_MAX": "2147483647", "INT_MIN": "(-2147483647 - 1)", "UINT_MAX": "4294967295u",
    ]

    /// Words GLSL ES 3.00 reserves that Metal lets a shader use as a name. An
    /// identifier spelled with one is renamed with a trailing underscore. The words
    /// other rules consume (`static`, `inline`, `half`, `short`, `using`,
    /// `namespace`, `template`, `sizeof`) are not here; those rules speak first.
    package static let reservedWords: Set<String> = [
        "attribute", "varying", "coherent", "restrict", "readonly", "writeonly", "resource",
        "atomic_uint", "noperspective", "patch", "sample", "subroutine", "common", "partition",
        "active", "asm", "class", "union", "enum", "typedef", "this", "goto", "volatile",
        "public", "external", "interface", "fixed", "superp",
        "input", "output", "hvec2", "hvec3", "hvec4", "dvec2", "dvec3", "dvec4", "fvec2",
        "fvec3", "fvec4", "sampler3DRect", "filter", "image1D", "image2D", "image3D",
        "imageCube", "cast", "precision", "invariant", "lowp", "mediump", "highp", "layout",
        "centroid", "flat", "smooth", "uniform", "buffer", "shared", "in", "out", "inout",
        "discard", "texture",
    ]
}
