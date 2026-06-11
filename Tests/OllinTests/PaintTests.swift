import Testing
@testable import Ollin

/// GPU-free checks on the gradient paint model: the `Gradient` factories, and
/// the `BakedGradient` LUT row both render paths sample from (the strip texture
/// on the SDF side, per-vertex colors on the tessellated side).
@Suite
struct PaintTests {

    @Test func factoriesCarryGeometryAndRamp() {
        let ramp = Ramp([.black, .white])
        let linear = Gradient.linear(from: Vector2(0, 0), to: Vector2(0, 100), ramp)
        #expect(linear.ramp == ramp)
        #expect(linear.geometry == .linear(start: Vector2(0, 0), end: Vector2(0, 100)))

        let radial = Gradient.radial(center: Vector2(50, 50), radius: 25, [.red, .blue])
        #expect(radial.geometry == .radial(center: Vector2(50, 50), radius: 25))
        #expect(radial.ramp.stops.count == 2)

        let along = Gradient.alongPath(ramp)
        #expect(along.geometry == .alongPath)

        #expect(Paint.color(.red).solidColor == .red)
        #expect(Paint.gradient(linear).solidColor == nil)
    }

    @Test func bakedRowMatchesRampEnds() {
        let ramp = Ramp([Color(hex: 0x102030), Color(hex: 0xF0E0D0)])
        let baked = BakedGradient(ramp)
        #expect(baked.bytes.count == BakedGradient.width * 4)
        #expect(baked.samples.count == BakedGradient.width)

        // First and last texels are the ramp's end colors, byte-exact.
        #expect(baked.bytes[0] == 0x10 && baked.bytes[1] == 0x20 && baked.bytes[2] == 0x30)
        let last = (BakedGradient.width - 1) * 4
        #expect(baked.bytes[last] == 0xF0 && baked.bytes[last + 1] == 0xE0 && baked.bytes[last + 2] == 0xD0)
        #expect(baked.bytes[3] == 255 && baked.bytes[last + 3] == 255)
    }

    @Test func bakedRowTracksTheRampMidpoint() {
        // The baked texel nearest t = 0.5 must match the exact OKLab mix within
        // a quantization step, so both render paths paint the ramp's colors.
        let ramp = Ramp([.red, .blue])
        let baked = BakedGradient(ramp)
        let exact = ramp.color(at: 0.5)
        let sample = baked.sample(0.5)
        #expect(abs(Double(sample.x) - exact.red) < 2.0 / 255)
        #expect(abs(Double(sample.y) - exact.green) < 2.0 / 255)
        #expect(abs(Double(sample.z) - exact.blue) < 2.0 / 255)
    }

    @Test func sampleClampsAndInterpolates() {
        let ramp = Ramp([.black, .white])
        let baked = BakedGradient(ramp)
        #expect(baked.sample(-1) == baked.samples[0])
        #expect(baked.sample(2) == baked.samples[BakedGradient.width - 1])
        // Between texels the sample interpolates monotonically.
        let a = baked.sample(0.25), b = baked.sample(0.75)
        #expect(a.x < b.x)
    }

    @Test func hardEdgeSurvivesBaking() {
        // Two stops sharing a position make a hard edge; the baked row must jump
        // across it, not smear (the texels straddling 0.5 differ by ~full range).
        let ramp = Ramp(stops: [(0, .black), (0.5, .black), (0.5, .white), (1, .white)])
        let baked = BakedGradient(ramp)
        let below = baked.sample(0.49), above = baked.sample(0.51)
        #expect(above.x - below.x > 0.9)
    }

    @Test func gradientAlphaRidesTheRow() {
        let ramp = Ramp([Color(red: 1, green: 0, blue: 0, alpha: 1),
                         Color(red: 1, green: 0, blue: 0, alpha: 0)])
        let baked = BakedGradient(ramp)
        #expect(baked.sample(0).w == 1)
        #expect(baked.sample(1).w == 0)
        #expect(abs(baked.sample(0.5).w - 0.5) < 2.0 / 255)
    }
}
