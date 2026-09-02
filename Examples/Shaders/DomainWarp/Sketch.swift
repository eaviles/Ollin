import Ollin

/// A shader with runtime parameters: `Shader(_, params:)` hands the GPU a
/// small array of floats, and the MSL body reads them back as
/// `param(info, n)`. Here `param(info, 0)` is a slow drift fed `time` and
/// `param(info, 1)` is the `warp` parameter, so the field slides and churns with no
/// recompile; the `Shader` is rebuilt each frame, but compilation is cached by
/// the source text, so only the two floats change. That is the pattern for
/// animating any hand-written shader from Swift: parameters and clocks go in
/// `params`, math stays in the string.
///
/// The vehicle is the classic domain-warp recipe, written out by hand instead
/// of calling the one-line `warpedFbm(p, k)` helper because the intermediate
/// displacements are worth keeping: `q` (the first warp) and `r` (the second)
/// each tint the color. The same picture with no shader at all is
/// `generate(.noise(scale: 3, warp: 1))`; the shader's reason to exist here is
/// the parameter plumbing.
@main
final class DomainWarp_Example: Sketch {
    @Param(0 ... 2, icon: "tornado") var warp = 1.0

    private let marbleSource = """
    float4 shade(float2 uv, ShaderInfo info) {
        float2 p = uv * 3.0 + float2(param(info, 0), 0.0);
        float k = 4.0 * param(info, 1);

        // The field warps its own coordinates: q displaces the lookup, then r
        // displaces it again. The fixed offsets just decorrelate the layers.
        float2 q = float2(fbm(p), fbm(p + float2(5.2, 1.3)));
        float2 r = float2(fbm(p + k * q + float2(1.7, 9.2)),
                          fbm(p + k * q + float2(8.3, 2.8)));
        float f = fbm(p + k * r);

        // Ramp on the final value, then tint by how far each warp reached:
        // q picks out the broad weather fronts, r the fine veins. The last
        // line multiplies the ramp back in so the tints shade the marble
        // instead of graying it out.
        float3 col = mix(float3(0.07, 0.09, 0.15), float3(0.93, 0.90, 0.83),
                         smoothstep(0.1, 0.9, f));
        col = mix(col, float3(0.20, 0.38, 0.52), clamp(length(q) - 0.35, 0.0, 1.0) * 0.7);
        col = mix(col, float3(0.85, 0.55, 0.30), clamp(r.y - 0.25, 0.0, 1.0) * 0.6);
        col *= 0.55 + 0.9 * f;
        return float4(col, 1.0);
    }
    """

    override func draw() {
        // Rebuilding the Shader each frame is the intended way to animate its
        // params: compilation is cached by the source text, so only the two
        // floats change.
        let marble = Shader(marbleSource, params: [Float(time * 0.03), Float(warp)])
        drawImage(generate(.shader(marble)).image, 0, 0)
    }
}
