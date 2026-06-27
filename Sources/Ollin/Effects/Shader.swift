import Foundation

/// A fragment shader you write yourself, run through Ollin's effect graph. You
/// supply a small Metal function and Ollin wraps it into a full GPU pass:
///
/// ```metal
/// float4 shade(float2 uv, ShaderInfo info) {
///     float2 p = uv * 8.0;
///     float v = 0.5 + 0.5 * sin((cos(p.x) * cos(p.y) + info.time) * 3.0);
///     return palette(v, float3(0.5), float3(0.5),
///                    float3(1.0), float3(0.0, 0.33, 0.67));   // from Ollin's shader library
/// }
/// ```
///
/// `uv` runs 0…1 across the layer (top-left origin), and `info` carries `time`,
/// `deltaTime`, `frame`, `resolution`, `mouse`, and your own `params` (read with
/// `param(info, i)`). Return a straight (non-premultiplied) sRGB color.
///
/// How many input layers the shader reads decides what it is: none makes it a
/// *generator* (`generate(.shader(s))`), one makes it a *filter*
/// (`layer.filtered(.shader(s))`, read with `sample(info, uv)`), two make it a
/// *combine* (`a.combined(with: b, .shader(s))`, read with `sample` + `sampleAux`).
///
/// The body can be an inline Swift string (it hot-reloads with the sketch in
/// OllinLive) or a `.metal` resource file. Ollin's shader library (palettes,
/// noise, hashes, OKLab, `smin`, domain operators) is available inside it; a
/// compile error is reported with line numbers relative to *your* source.
public struct Shader: Sendable {

    /// Which sections of Ollin's shader library to splice into the shader before
    /// it compiles. Every helper is dead-code-eliminated if unused, so on the GPU
    /// the choice costs nothing; it only trims *compile* time, which matters when
    /// many shaders compile or hot-reload at once. The default splices everything.
    public struct Modules: OptionSet, Sendable {
        public let rawValue: Int
        public init(rawValue: Int) { self.rawValue = rawValue }
        /// Cosine palette and the OKLab / OKLCH perceptual color conversions.
        public static let color  = Modules(rawValue: 1 << 0)
        /// `hash12` / `hash22` / `hash33`.
        public static let hash   = Modules(rawValue: 1 << 1)
        /// Value noise, FBM, and gradient noise (depends on `hash`).
        public static let noise  = Modules(rawValue: 1 << 2)
        /// `smin` and the 2D signed-distance helpers.
        public static let sdf    = Modules(rawValue: 1 << 3)
        /// Domain operators: repeat, mirror, polar fold.
        public static let domain = Modules(rawValue: 1 << 4)
        /// Every section (the default).
        public static let all: Modules = [.color, .hash, .noise, .sdf, .domain]
    }

    /// The MSL source the user wrote (the body that defines `shade`), resolved to a
    /// string at construction so the descriptor stays `Sendable` and the render
    /// thread never reads a file. For a `.metal` resource, the path it was read from
    /// (so OllinLive can watch it); empty for an inline string.
    let source: String
    let resourcePath: String
    let params: [Float]
    let modules: Modules

    /// A shader from inline Metal source: a string defining `float4 shade(float2 uv,
    /// ShaderInfo info)`. `params` are floats your shader reads with `param(info, i)`.
    public init(_ source: String, params: [Float] = [], using modules: Modules = .all) {
        self.source = source
        self.resourcePath = ""
        self.params = params
        self.modules = modules
    }

    /// A shader from a `.metal` resource file. `in:` is required (it can't default to
    /// Ollin's own bundle); the file is read now, on the calling thread, so the
    /// descriptor carries the source itself.
    public init(resource name: String, in bundle: Bundle,
                params: [Float] = [], using modules: Modules = .all) {
        let url = bundle.url(forResource: name, withExtension: "metal")
            ?? bundle.url(forResource: name, withExtension: nil)
        self.source = url.flatMap { try? String(contentsOf: $0, encoding: .utf8) } ?? ""
        self.resourcePath = url?.path ?? ""
        self.params = params
        self.modules = modules
    }

    /// The user `params` packed into the fixed-width `float4` rows the shader buffer
    /// expects, padded with zeros and truncated to the cap.
    var paddedParams: [SIMD4<Float>] {
        var rows = [SIMD4<Float>](repeating: .zero, count: 8)   // OLLIN_SHADER_PARAM_ROWS
        for (i, v) in params.prefix(32).enumerated() { rows[i / 4][i % 4] = v }
        return rows
    }
}

/// A user shader that failed to compile. `message` is the cleaned, friendly
/// diagnostic with line numbers relative to the source you wrote; `raw` is the
/// compiler's full output, kept for when you need it.
public struct ShaderCompileError: Error, Sendable, CustomStringConvertible {
    public let message: String
    public let raw: String
    public var description: String { message }
}
