import Ollin
import Testing

/// Pure-CPU checks on `Image.pixelSorted`: runs really sort, the threshold
/// window really guards, order flips with `reversed`, alpha rides its pixel,
/// and the whole transform is deterministic. No GPU is touched.
@Suite
struct PixelSortTests {
    /// A column of shuffled grays, sorted with the full window, comes out
    /// monotonically darker to brighter top to bottom.
    @Test func fullWindowSortsAColumn() {
        let grays: [Double] = [0.7, 0.1, 0.9, 0.4, 0.2, 0.6, 0.3, 0.8]
        let image = Image(width: 1, height: grays.count, color: .black)
        for (y, g) in grays.enumerated() { image[0, y] = Color(white: g) }

        let sorted = image.pixelSorted(.vertical, threshold: 0 ... 1)
        var previous = -1.0
        for y in 0 ..< grays.count {
            let value = sorted[0, y].luminance
            #expect(value >= previous - 1e-9)
            previous = value
        }
    }

    /// `reversed` flips the same column bright to dark.
    @Test func reversedFlipsTheOrder() {
        let grays: [Double] = [0.7, 0.1, 0.9, 0.4]
        let image = Image(width: 1, height: grays.count, color: .black)
        for (y, g) in grays.enumerated() { image[0, y] = Color(white: g) }

        let sorted = image.pixelSorted(.vertical, threshold: 0 ... 1, reversed: true)
        var previous = 2.0
        for y in 0 ..< grays.count {
            let value = sorted[0, y].luminance
            #expect(value <= previous + 1e-9)
            previous = value
        }
    }

    /// Pixels outside the brightness window hold their ground: only the run
    /// between them reorders.
    @Test func thresholdGuardsShadowsAndHighlights() {
        // dark, bright, mid-high, mid-low, dark: the window admits the mids.
        let grays: [Double] = [0.05, 0.95, 0.7, 0.4, 0.05]
        let image = Image(width: 1, height: grays.count, color: .black)
        for (y, g) in grays.enumerated() { image[0, y] = Color(white: g) }

        let sorted = image.pixelSorted(.vertical, threshold: 0.3 ... 0.8)
        // The guards never moved (byte-exact against the source pixels).
        #expect(sorted[0, 0] == image[0, 0])
        #expect(sorted[0, 1] == image[0, 1])
        #expect(sorted[0, 4] == image[0, 4])
        // The mid run sorted ascending.
        #expect(sorted[0, 2].luminance <= sorted[0, 3].luminance + 1e-9)
    }

    /// Rows sort the same way along the other axis.
    @Test func horizontalSortsARow() {
        let grays: [Double] = [0.9, 0.2, 0.5, 0.1]
        let image = Image(width: grays.count, height: 1, color: .black)
        for (x, g) in grays.enumerated() { image[x, 0] = Color(white: g) }

        let sorted = image.pixelSorted(.horizontal, threshold: 0 ... 1)
        var previous = -1.0
        for x in 0 ..< grays.count {
            let value = sorted[x, 0].luminance
            #expect(value >= previous - 1e-9)
            previous = value
        }
    }

    /// A pixel's alpha travels with its color: sorting a column that holds
    /// one translucent pixel keeps that pixel's color and alpha paired.
    @Test func alphaRidesItsPixel() {
        let image = Image(width: 1, height: 3, color: .black)
        image[0, 0] = Color(white: 0.8)
        image[0, 1] = Color(red: 1, green: 0, blue: 0, alpha: 0.5)
        image[0, 2] = Color(white: 0.2)

        let sorted = image.pixelSorted(.vertical, threshold: 0 ... 1)
        var found = false
        for y in 0 ..< 3 {
            let c = sorted[0, y]
            if abs(c.alpha - 0.5) < 0.02 {
                found = true
                #expect(c.red > 0.9)
                #expect(c.green < 0.1)
            }
        }
        #expect(found)
    }

    /// The transform is a pure function of its input.
    @Test func sortingIsDeterministic() {
        let image = Image(width: 17, height: 13, color: .black)
        for y in 0 ..< 13 {
            for x in 0 ..< 17 {
                image[x, y] = Color(white: Double((x * 31 + y * 17) % 100) / 100)
            }
        }
        let a = image.pixelSorted(.vertical, by: .brightness, threshold: 0.2 ... 0.9)
        let b = image.pixelSorted(.vertical, by: .brightness, threshold: 0.2 ... 0.9)
        for y in 0 ..< 13 {
            for x in 0 ..< 17 {
                #expect(a[x, y] == b[x, y])
            }
        }
    }

    /// Sorting by hue orders a rainbow row red through blue.
    @Test func hueKeyOrdersTheWheel() {
        let hues: [Double] = [0.6, 0.1, 0.9, 0.3]
        let image = Image(width: hues.count, height: 1, color: .black)
        for (x, h) in hues.enumerated() {
            image[x, 0] = Color(hue: h, saturation: 1, brightness: 0.5)
        }
        let sorted = image.pixelSorted(.horizontal, by: .hue, threshold: 0 ... 1)
        // Recover hue order via the red channel's rough monotonic proxy:
        // instead, just check determinism of arrangement by comparing the
        // two ends: the first pixel should be the h = 0.1 orange (more red
        // than blue), the last the h = 0.9 magenta-ish (more blue than green).
        #expect(sorted[0, 0].red > sorted[0, 0].blue)
        #expect(sorted[hues.count - 1, 0].blue > sorted[hues.count - 1, 0].green)
    }
}
