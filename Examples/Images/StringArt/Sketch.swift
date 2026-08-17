import Ollin

/// String art: a shaded moon knitted out of one continuous thread.
///
/// `StringArt` rings the canvas with 200 pins and winds a single thread
/// between them, chord after chord, each one chosen greedily for the
/// darkness it still covers. Dark regions collect many crossings, light
/// regions few, and the straight lines add up to a shaded picture. The
/// canvas never clears (`noClear()`): every frame winds a few more chords
/// onto the accumulation, so the moon knits itself over the first seconds.
///
/// The winding is deterministic (no seed involved), and `art.thread` holds
/// the whole piece so far as one open polyline: draw it with `drawPolyline`
/// in a clearing sketch and the vector exports write a single continuous
/// line, exactly the thing a pen plotter loves most.
@main
final class StringArt: Sketch {
    private var art: Ollin.StringArt!
    private var pinsDrawn = false

    override func setup() {
        noClear()
        art = Ollin.StringArt(of: paint(), center: Vector2(width / 2, height / 2),
                              radius: 470, pins: 200, chords: 3000, ink: 0.08)
    }

    override func draw() {
        if frameCount == 1 {
            background(Color(hex: 0xF6F1E7))
            noStroke()
            fill(Color(hex: 0x3A3C46))
            for pin in art.pins { drawCircle(center: pin, radius: 2.4) }
        }

        noFill()
        stroke(Color(hex: 0x20222B).withAlpha(0.35))
        strokeWeight(1.0)
        for chord in art.step(8) {
            drawLine(chord.from, chord.to)
        }

        // The caption stays word-for-word stable: the canvas never clears,
        // so changing text would smear over itself.
        drawCaption("one continuous thread over 200 pins")
    }

    /// The picture the thread reproduces: a crescent moon, the dark sliver
    /// bold, the rest of the disk a faint earthshine veil, painted on white
    /// so the sky stays airy. Bold tonal masses are what the technique
    /// reads best.
    private func paint() -> Image {
        let n = 340
        let image = Image(width: n, height: n, color: .white)
        for y in 0 ..< n {
            for x in 0 ..< n {
                let u = (Double(x) + 0.5) / Double(n) * 2 - 1
                let v = (Double(y) + 0.5) / Double(n) * 2 - 1
                let disk = dist(u, v, 0, 0)
                guard disk < 0.68 else { continue }

                // The crescent: the disk minus a second disk pushed toward
                // the light, both edges softened a touch so the scoring
                // never reads a hard stair.
                let bite = dist(u, v, 0.3, -0.24)
                let inDisk = 1 - smoothstep(0.65, 0.68, disk)
                let inBite = smoothstep(0.58, 0.64, bite)
                let crescent = inDisk * inBite
                image[x, y] = Color(white: 0.82 - 0.66 * crescent)
            }
        }
        return image
    }
}
