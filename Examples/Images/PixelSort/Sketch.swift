import Ollin

/// A painted dusk skyline, melted by pixel sorting.
///
/// `pixelSorted` rearranges runs of an image's own pixels: nothing is
/// recolored, the pixels just change places, which is what gives the streaks
/// their molten reading. Runs are bounded by a brightness window, so the
/// deep shadows and the sun's core hold their ground while the midtones
/// pour. Here the window's top edge breathes over the loop, so the melt
/// advances and recedes; hold the mouse to add the second, horizontal pass
/// (the classic treatment sorts both axes).
///
/// The source is painted once in `setup()` (a gradient sky, a low sun, and
/// ragged hills), so the sketch carries no asset. Sorting is CPU work at the
/// image's own resolution; the source is kept small and drawn scaled up.
@main
final class PixelSort: Sketch {
    override var loopDuration: Double? { 12 }

    private var source = Image(width: 320, height: 320, color: .black)

    override func setup() {
        seed(9)
        paint()
    }

    override func draw() {
        background(.black)

        // The window's ceiling breathes: low, only faint streaks; high, the
        // whole midtone sky pours. The floor sits just above the hills, so
        // the horizon holds; the stars sit above the ceiling and break the
        // runs, which is where the jagged teeth come from.
        let ceiling = 0.7 + 0.2 * sin(loopProgress(over: 12) * .tau)
        var sorted = source.pixelSorted(.vertical, threshold: 0.24 ... ceiling,
                                        reversed: true)
        if mouseIsPressed {
            sorted = sorted.pixelSorted(.horizontal, threshold: 0.24 ... ceiling)
        }
        drawImage(sorted, in: canvasRectangle)

        drawCaption("brightness-bounded runs, sorted; hold the mouse for the horizontal pass")
    }

    /// The image the sort melts: a dusk gradient roughened by fbm cloud
    /// texture, a low sun, a field of stars, and two ridges of hills. The
    /// texture matters: run boundaries land differently in every column,
    /// which is what makes the sorted streaks jagged instead of smooth.
    private func paint() {
        let n = source.width
        for y in 0 ..< n {
            let v = (Double(y) + 0.5) / Double(n)
            for x in 0 ..< n {
                let u = (Double(x) + 0.5) / Double(n)

                // Sky: a deep zenith warming toward the horizon, with clouds.
                let cloud = signedFbm(u * 5, v * 4, octaves: 4) * 0.14
                let t = clamp((1 - v) * (1 - v) + cloud, 0, 1)
                var color = Color.mix(Color(hex: 0xF2B24A), Color(hex: 0x1B1F3A), t: t)

                // The sun, low and slightly off-center.
                let d = dist(u, v, 0.38, 0.62)
                if d < 0.09 { color = Color(hex: 0xFFE9B8) }

                // Two hill ridges, the nearer one darker.
                let far = 0.68 + signedNoise(u * 3.1 + 10) * 0.05
                let near = 0.82 + signedNoise(u * 2.2 + 40) * 0.07
                if v > far { color = Color(hex: 0x3A2F45) }
                if v > near { color = Color(hex: 0x14101E) }

                source[x, y] = color
            }
        }

        // Stars: bright single pixels above the sort window, so each one
        // splits a run and leaves a streak edge below it.
        for _ in 0 ..< 240 {
            let x = Int(random(0, Double(n)))
            let y = Int(random(0, Double(n) * 0.72))
            source[min(x, n - 1), min(y, n - 1)] = Color(white: random(0.85, 1))
        }
    }
}
