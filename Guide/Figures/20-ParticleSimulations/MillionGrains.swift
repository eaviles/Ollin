// figure: frame=240
//
// Guide figure (Chapter 20): the same grain, three populations. Each strip
// runs the same GPU kernel and each grain sheds the same faint light; only
// the count changes, and density does the drawing.
import Ollin

final class MillionGrains: Sketch {
    static let step = """
        float x0 = custom.x, w = custom.y;
        if (life <= 0.0) {
            float2 r = hash22(float2(float(id) * 0.37, custom.z + floor(u.time)));
            position = float2(x0 + r.x * w, r.y * u.resolution.y);
            life = 0.6 + r.y * 2.4;
        }
        position += curlNoise(position * 0.0022 + float2(0.0, u.time * 0.03)) * 60.0 * u.dt;
        if (position.x < x0 || position.x > x0 + w) { life = 0.0; }
        life -= u.dt;
        color = float4(1.0, 0.72, 0.42, 0.3);
        size = 1.5;
    """

    lazy var few = Particles(count: 10_000, step: Self.step)
    lazy var many = Particles(count: 100_000, step: Self.step)
    lazy var million = Particles(count: 1_000_000, step: Self.step)

    override func setup() {
        toneMap(.aces, exposure: 1.3)
    }

    override func draw() {
        background(Color(hex: 0x05070C))
        let gutter = 8.0
        let strip = (width - gutter * 4) / 3
        let systems: [(Particles, String, Double)] = [
            (few, "10,000", gutter),
            (many, "100,000", gutter * 2 + strip),
            (million, "1,000,000", gutter * 3 + strip * 2),
        ]
        blendMode(.add)
        for (i, system) in systems.enumerated() {
            updateParticles(system.0, custom: SIMD4(Float(system.2), Float(strip), Float(i), 0))
            drawParticles(system.0)
        }
        blendMode(.normal)
        noStroke()
        for system in systems {
            fill(Color(hex: 0x05070C))
            drawRect(system.2, height - 44, strip, 44)
            fill(Color(white: 0.85))
            textSize(17)
            textAlign(.center, .middle)
            drawText(system.1, system.2 + strip / 2, height - 22)
        }
    }
}
