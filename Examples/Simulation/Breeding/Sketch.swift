import Ollin

/// Evolution with nobody keeping score. Sixteen ornaments, each drawn from eight
/// numbers, and the only thing deciding which ones have children is that you liked
/// looking at them. Pick a few, breed, pick again: in a dozen rounds the grid will be
/// full of things nobody could have written a formula for, including you.
///
/// This is the older half of the idea and still the stranger one. A search that is
/// scored can only ever find what the score was written to want. A search you judge by
/// eye can go somewhere you did not know you were headed, because you are allowed to
/// change your mind between generations.
///
/// Click ornaments to pick them (a picked one is ringed). `space` breeds the next
/// generation from your picks, `c` clears them, `r` throws the lot away and starts
/// over. Press `1`, `2`, `3` to change how two parents are mixed.
@main
final class Breeding_Example: Sketch {
    var pool: Population!
    var chosen: Set<Int> = []
    var mixName = "independent"

    let columns = 4
    let rows = 4

    /// The tiles, with room under them for the caption.
    private var grid: Grid {
        Grid(in: Rectangle(x: 0, y: 0, width: width, height: height - 48),
             columns: columns, rows: rows)
    }

    override func setup() {
        // Eight genes: how many arms, how sharp they are, how much they twist, two
        // hues, how many rings, the line weight, and how far the middle is hollowed.
        pool = population(count: columns * rows, genes: 8)
    }

    override func draw() {
        background(Color(hex: 0x0B0D12))
        let cells = grid.cells

        for (i, cell) in cells.enumerated() where i < pool.count {
            withState {
                translate(cell.center.x, cell.center.y)
                drawOrnament(pool[i], size: min(cell.frame.width, cell.frame.height) * 0.38)
            }
            if chosen.contains(i) {
                noFill()
                stroke(Color(hex: 0xF2C14E))
                strokeWeight(2)
                let ring = cell.frame.inset(by: 8)
                drawRect(corner: Vector2(ring.x, ring.y), width: ring.width, height: ring.height,
                         cornerRadius: 10)
            }
        }

        drawCaption("Breeding · generation \(pool.generation) · \(chosen.count) picked · "
            + "mixing \(mixName) · click to pick, space to breed, c clears, r starts over")
    }

    /// Eight numbers read as a drawing. Nothing here knows it is being evolved: the
    /// genome is just where the numbers came from.
    private func drawOrnament(_ g: Genome, size: Double) {
        let arms = g.value(0, in: 3 ... 11)
        let sharpness = g.value(1, in: 0.4 ... 6.0)
        let twist = g.value(2, in: -1.2 ... 1.2)
        let hue = g.value(3, in: 0.0 ... 1.0)
        let accent = hue + g.value(4, in: -0.35 ... 0.35)
        let rings = g.value(5, in: 1 ... 4)
        let weight = g.value(6, in: 0.6 ... 3.4)
        let hollow = g.value(7, in: 0.1 ... 0.7)

        strokeWeight(weight)
        for ring in 0..<rings {
            let t = rings > 1 ? Double(ring) / Double(rings - 1) : 0
            let scale = 1.0 - t * 0.55
            let shade = Color(hue: fract(hue + t * (accent - hue)),
                              saturation: 0.55, brightness: 0.95)
            fill(shade.withAlpha(0.30))
            stroke(shade)
            // A rosette: the radius rises and falls `arms` times round the circle, and
            // `sharpness` decides whether that reads as a flower or a star. The petals
            // dip below the mean, so this has to be a `drawShape`: a polygon fan would
            // bridge straight across every valley.
            //
            // `twist` turns each ring rather than bending the petals, because the lobe
            // has to come back to where it started after a full turn. Shearing it by
            // the angle leaves the last point somewhere else than the first, and
            // `close()` then draws the straight line between them as a stray spur.
            let spin = twist * t
            drawShape { p in
                let steps = 240
                for i in 0...steps {
                    let a = Double(i) / Double(steps) * .tau
                    let lobe = pow(abs(cos(Double(arms) * a / 2)), sharpness)
                    let r = size * scale * (hollow + (1 - hollow) * lobe)
                    let point = Vector2(cos(a + spin) * r, sin(a + spin) * r)
                    if i == 0 { p.move(to: point) } else { p.line(to: point) }
                }
                p.close()
            }
        }
    }

    override func mousePressed() {
        for (i, cell) in grid.cells.enumerated() where cell.frame.contains(Vector2(mouseX, mouseY)) {
            if chosen.contains(i) { chosen.remove(i) } else { chosen.insert(i) }
        }
    }

    override func keyPressed() {
        switch key {
        case " ": pool.breed(from: chosen); chosen = []
        case "c": chosen = []
        case "r": pool.reroll(); chosen = []
        case "1": pool.crossover = .independent; mixName = "independent"
        case "2": pool.crossover = .split;       mixName = "split"
        case "3": pool.crossover = .blend;       mixName = "blend"
        default:  break
        }
    }
}
