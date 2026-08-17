@testable import Ollin
import Testing

/// Pure-CPU checks on `Buddhabrot`: the orbit test's escape step and interior
/// shortcuts, the deposit rules, determinism, exact slice composition, and the
/// mirrored plate. No GPU.
@Suite
struct BuddhabrotTests {

    @Test
    func aKnownSeedEscapesAtItsKnownStep() {
        // c = 2 + 0i: z1 = 2 (on the circle, still in), z2 = 6 (out), so the
        // escape step is 2 and the orbit holds the one in-bound point.
        var orbit: [Double] = []
        let escape = Buddhabrot.escapeOrbit(cx: 2, cy: 0, cap: 10, orbit: &orbit)
        #expect(escape == 2)
        #expect(orbit == [2, 0])
    }

    @Test
    func interiorSeedsPlotNothing() {
        var orbit: [Double] = []
        // Inside the main cardioid: rejected by the closed form.
        #expect(Buddhabrot.escapeOrbit(cx: -0.2, cy: 0.1, cap: 50, orbit: &orbit) == nil)
        // Inside the period-2 bulb: rejected by the closed form.
        #expect(Buddhabrot.escapeOrbit(cx: -1, cy: 0.05, cap: 50, orbit: &orbit) == nil)
        // Inside the period-3 bulb, which no shortcut covers: the orbit
        // survives the cap and is discarded as in-the-set.
        #expect(Buddhabrot.escapeOrbit(cx: -0.12, cy: 0.75, cap: 2000, orbit: &orbit) == nil)
    }

    @Test
    func theSameSeedDevelopsTheSameBytes() {
        let plate = Buddhabrot(iterations: [300, 60, 20])
        let a = Buddhabrot.Renderer(plate, width: 48, height: 48, seed: 11)
        let b = Buddhabrot.Renderer(plate, width: 48, height: 48, seed: 11)
        a.accumulate(samples: 30_000)
        b.accumulate(samples: 30_000)
        #expect(samePixels(a.image(), b.image()))
    }

    @Test
    func slicesComposeExactly() {
        let plate = Buddhabrot(iterations: [300])
        let sliced = Buddhabrot.Renderer(plate, width: 48, height: 48, seed: 5)
        let whole = Buddhabrot.Renderer(plate, width: 48, height: 48, seed: 5)
        sliced.accumulate(samples: 10_000)
        sliced.accumulate(samples: 10_000)
        whole.accumulate(samples: 20_000)
        #expect(sliced.samples == whole.samples)
        #expect(samePixels(sliced.image(), whole.image()))
    }

    @Test
    func thePlateIsMirroredAboutTheRealAxis() {
        // A power-of-two window keeps the pixel mapping's mirror exact, so
        // the conjugate deposit lands column w-1-x for every column x.
        let plate = Buddhabrot(iterations: [200],
                               window: Rectangle(x: -2, y: -2, width: 4, height: 4))
        let renderer = Buddhabrot.Renderer(plate, width: 64, height: 64, seed: 3)
        renderer.accumulate(samples: 40_000)
        let image = renderer.image()
        var lit = 0
        for y in 0 ..< 64 {
            for x in 0 ..< 32 {
                let left = image[x, y], right = image[63 - x, y]
                #expect(left == right)
                if left.red > 0 { lit += 1 }
            }
        }
        #expect(lit > 100)   // the plate actually exposed
    }

    @Test
    func oneCapServesAllThreeChannelsAsGray() {
        #expect(Buddhabrot(iterations: [700]).channelCaps == [700, 700, 700])
        #expect(Buddhabrot(iterations: [700]).isGrayscale)
        #expect(Buddhabrot(iterations: [5000, 500, 50]).channelCaps == [5000, 500, 50])
        #expect(!Buddhabrot(iterations: [5000, 500, 50]).isGrayscale)
    }

    @Test
    func aLongerCapExposesMoreThanAShortOne() {
        // Same seed and samples: every orbit the short cap keeps, the long cap
        // keeps too, and the long one also keeps the slower escapers. The
        // develop normalizes each plate, so the honest monotone measure is
        // which pixels got lit at all, not how bright they developed.
        let short = Buddhabrot.Renderer(Buddhabrot(iterations: [30]),
                                        width: 48, height: 48, seed: 9)
        let long = Buddhabrot.Renderer(Buddhabrot(iterations: [3000]),
                                       width: 48, height: 48, seed: 9)
        short.accumulate(samples: 20_000)
        long.accumulate(samples: 20_000)
        #expect(litPixels(long.image()) > litPixels(short.image()))
    }

    private func samePixels(_ a: Image, _ b: Image) -> Bool {
        guard a.width == b.width, a.height == b.height else { return false }
        for y in 0 ..< a.height {
            for x in 0 ..< a.width where a[x, y] != b[x, y] { return false }
        }
        return true
    }

    private func litPixels(_ image: Image) -> Int {
        var lit = 0
        for y in 0 ..< image.height {
            for x in 0 ..< image.width where image[x, y].red > 0 { lit += 1 }
        }
        return lit
    }
}
