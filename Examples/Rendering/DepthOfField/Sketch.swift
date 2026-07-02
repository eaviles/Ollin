import Ollin
import simd

/// Depth of field, *earned* rather than faked. A blurred photograph isn't a sharp
/// image with a blur filter on top — it's countless light rays that each landed in a
/// slightly different place because they passed through the lens out of focus. This
/// sketch renders that literally. A handful of smooth 3D curves are drawn not as
/// lines but as a haze of faint samples scattered along them, and each sample is
/// displaced within a disc whose radius grows with how far that point sits from the
/// focal plane. Where a curve crosses the focus it stays a crisp bright ribbon; away
/// from it the samples spread into soft bokeh. The blur *emerges* from the statistics
/// of where the light fell — there is no blur filter anywhere.
///
/// **It runs on the GPU compute path.** Every frame a kernel generates a *million*
/// fresh samples — the displacement math below, per sample, never touching the CPU —
/// and they sum as light in a linear float buffer:
///   • `blendMode(.add)` — every sample adds light to the pile.
///   • `noClear()` — the canvas isn't cleared, so the spray accumulates and refines.
///   • `toneMap(.aces)` — light piles up well past full brightness in float; the
///     film-like curve rolls those highlights into a glow instead of clipping.
/// At this sample count the ribbons converge almost instantly, where the CPU version
/// needed many frames of accumulation to fill in — that's the point of compute.
///
/// A mild perspective makes near samples larger, so out-of-focus foreground curves
/// bloom into big soft discs while distant ones stay small — the look of a fast lens.
/// The scene turns slowly, so each ribbon racks through the fixed focal plane as it
/// rotates. **Drag left↔right to move the focal plane** and pull focus through the
/// depth yourself. **Press any key** to toggle colour-shift: each sample is drawn as
/// three particles (its R, G, B channels) displaced by slightly different radii, so
/// the bokeh grows chromatic-aberration fringes — the same emergent trick, per
/// channel.
///
/// Inspired by Anders Hoff's depth-of-field and colour-shift technique (inconvergent).
@main
final class DepthOfField_Example: Sketch {
    private var ribbons: Particles!
    private var colourShift = true

    // 1,000,000 particles ≈ 333k samples, each drawn as 3 channel-particles.
    private let particleCount = 1_000_000

    override func setup() {
        background(Color(red: 0.015, green: 0.015, blue: 0.03))   // the one base wipe
        noClear()                                                 // then accumulate
        toneMap(.aces)                                            // roll highlights into a glow

        // Nine smooth closed curves (3D Lissajous figures), fixed by the seed and
        // baked straight into the kernel source as constant arrays — the kernel is a
        // string the sketch builds. Each gets integer frequencies (so the curve
        // closes), random phases, and its own hue evenly spaced round the wheel.
        seed(4)
        var freq = "", phase = "", col = ""
        for i in 0 ..< 9 {
            let fx = Int(random(1, 4)), fy = Int(random(1, 4)), fz = Int(random(1, 4))
            let c = Color(hue: Double(i) / 9, saturation: 0.8, brightness: 1)
            freq  += "float3(\(fx), \(fy), \(fz)), "
            phase += "float3(\(random(.tau)), \(random(.tau)), \(random(.tau))), "
            col   += "float3(\(c.red), \(c.green), \(c.blue)), "
        }

        ribbons = Particles(count: particleCount, step: """
            const float TAU = 6.28318530718;
            const float3 freq[9]  = { \(freq) };
            const float3 phase[9] = { \(phase) };
            const float3 col[9]   = { \(col) };

            // Each particle is one colour channel (id % 3) of one sample (id / 3).
            // Re-roll the sample each frame so the spray refines and animates.
            uint sample = id / 3u;
            uint channel = id % 3u;
            float2 rseed = float2(float(sample), float(u.frameCount));
            uint r = uint(hash12(rseed) * 9.0) % 9u;
            float t = hash12(rseed + 1.7);

            // A point along the curve, then rotate (x, z) about the vertical axis.
            float3 p3 = 0.95 * sin(freq[r] * t * TAU + phase[r]);
            float ang = u.time * 0.10;
            float ca = cos(ang), sa = sin(ang);
            float rx =  p3.x * ca + p3.z * sa;
            float rz = -p3.x * sa + p3.z * ca;

            // Perspective: near samples sit larger than far ones.
            float persp = 2.4 / (rz + 3.0);
            float radius = min(u.resolution.x, u.resolution.y) * 0.30;
            float2 cen = u.resolution * 0.5;
            float sx = cen.x + rx * radius * persp;
            float sy = cen.y - p3.y * radius * persp;

            // Distance from the focal plane (custom.x) sets the bokeh disc radius.
            float focus = custom.x;
            float defocus = abs(rz - focus);
            float blur = defocus * (radius * 0.14) * persp;
            float refScale = min(u.resolution.x, u.resolution.y) / 1000.0;
            float dotSize = (0.5 + defocus * 1.4) * persp * refScale;
            // Energy conservation: a wider disc means each sample dims, so a ribbon's
            // total brightness stays roughly constant. Faint, because a million sum.
            float alpha = 0.0009 / (1.0 + defocus * 6.0);

            // An offset within the bokeh disc; colour-shift (custom.y) spreads the
            // three channels to slightly different radii for chromatic fringes.
            float2 off = discSample(rseed + 3.3) * blur;
            float shift = custom.y * min(defocus, 1.0);
            float chOff = (channel == 0u) ? (1.0 + shift) : (channel == 2u) ? (1.0 - shift) : 1.0;
            float3 mask = (channel == 0u) ? float3(1, 0, 0)
                        : (channel == 1u) ? float3(0, 1, 0) : float3(0, 0, 1);

            position = float2(sx, sy) + off * chOff;
            size = dotSize;
            color = float4(col[r] * mask, alpha);
            life = 1.0;
        """)
    }

    override func keyPressed() { colourShift.toggle() }

    override func draw() {
        blendMode(.add)
        // Fixed focal plane by default (so the depth read stays crisp while the
        // ribbons rotate through it); drag to rack it through the depth yourself.
        let focus = mouseIsPressed ? Float(map(mouseX, 0, width, -0.9, 0.9)) : 0
        let shift = Float(colourShift ? 0.16 : 0)
        updateParticles(ribbons, custom: SIMD4(focus, shift, 0, 0))
        drawParticles(ribbons)

        blendMode(.normal)
        drawCaption("drag to rack focus · press a key: colour-shift \(colourShift ? "on" : "off")")
    }
}
