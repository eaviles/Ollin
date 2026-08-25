import Ollin

/// A star chart drawn once, replayed every frame. `setup()` scatters 150,000
/// stars into a spiral galaxy and records them into a `Batch`: the geometry
/// uploads to the GPU once, and each frame's `drawBatch(field)` replays it for
/// (almost) nothing. The transform in force at `drawBatch` time moves the whole
/// recording as a unit, so the galaxy turns with one `rotate` even though no
/// star is ever re-recorded.
///
/// The second batch shows the other use: a compass rosette recorded once and
/// *stamped* five times around the chart, each at its own position, angle, and
/// size. One recording, many placements.
///
/// Flip the **retained** knob off to draw the same stars through the ordinary
/// per-frame path (the exact same helper the recording captured) and watch the
/// frame time in the inspector: that gap is the recording cost the batch pays
/// once instead of every frame.
@main
final class RetainedBatch: Sketch {
    override var loopDuration: Double? { 40 }

    @Param var retained = true   // off = re-record all 150k stars every frame

    private struct Star {
        var position: Vector2
        var radius: Double
        var color: Color
    }

    private var stars: [Star] = []
    private var field: Batch!
    private var rosette: Batch!

    override func setup() {
        seed(31_417)
        makeStars()
        // Record once. The body is the same call the dynamic path makes below;
        // the batch simply remembers its geometry so the frames don't redo it.
        field = makeBatch { drawStars() }
        rosette = makeBatch { drawRosette() }
        noStroke()
    }

    override func draw() {
        background(Color(hex: 0x060612))

        // The galaxy, turning: the draw-time transform moves the whole replay,
        // so the 150k recorded stars ride one rotate about the canvas center.
        withState {
            translate(center)
            rotate(loopProgress(over: 40) * .tau)
            translate(-width / 2, -height / 2)
            if retained {
                drawBatch(field)
            } else {
                drawStars()          // the same stars, re-recorded every frame
            }
        }

        // The rosette, stamped: one recording, five placements. Each stamp is a
        // fresh transform around the same batch.
        for i in 0 ..< 5 {
            let a = Double(i) / 5 * .tau - .tau / 4
            let orbit = shortSide * 0.42
            withState {
                translate(width / 2 + cos(a) * orbit, height / 2 + sin(a) * orbit)
                rotate(a + loopProgress(over: 40) * .tau)
                scale(i == 0 ? 1.0 : 0.55)
                drawBatch(rosette)
            }
        }
    }

    /// The static composition: two log-spiral arms of gaussian-scattered stars,
    /// a warm dense core, and a faint halo. Built once in `setup()` so the
    /// retained and per-frame paths draw the identical field.
    private func makeStars() {
        let center = center
        let reach = shortSide * 0.46
        stars.reserveCapacity(150_000)

        let armColors = [Color(hex: 0x8DB4FF), Color(hex: 0xC8D9FF)]
        for i in 0 ..< 110_000 {
            // Two arms: angle marches with radius (a log spiral), scatter widens outward.
            let t = pow(random(1), 0.6)
            let arm = Double(i % 2) * .pi
            let angle = arm + t * 3.4 + randomGaussian() * 0.18
            let r = reach * t
            let p = center + Vector2(angle: angle) * r
                  + Vector2(randomGaussian(), randomGaussian()) * reach * 0.035
            let bright = random(0.25, 1)
            stars.append(Star(position: p,
                              radius: random(0.5, 1.4) * (bright > 0.97 ? 2.2 : 1),
                              color: randomChoice(armColors).withAlpha(bright * 0.8)))
        }
        for _ in 0 ..< 25_000 {   // the core: tight, warm
            let p = center + Vector2(randomGaussian(), randomGaussian()) * reach * 0.08
            stars.append(Star(position: p, radius: random(0.6, 1.8),
                              color: Color(hex: 0xFFD9A0).withAlpha(random(0.3, 0.9))))
        }
        for _ in 0 ..< 15_000 {   // the halo: sparse, dim, everywhere
            let p = Vector2(random(width), random(height))
            stars.append(Star(position: p, radius: random(0.4, 1),
                              color: Color(hex: 0x9FB0D8).withAlpha(random(0.1, 0.4))))
        }
    }

    private func drawStars() {
        for star in stars {
            fill(star.color)
            drawCircle(star.position.x, star.position.y, star.radius)
        }
    }

    /// A small engraved compass rosette: a hollow ring, a tick ring, and an
    /// eight-point star, all region shapes so the whole motif is a handful of
    /// SDF instances.
    private func drawRosette() {
        let ink = Color(hex: 0xE8DDC4)
        noFill()
        stroke(ink.withAlpha(0.9))
        strokeWeight(1.5)
        drawCircle(0, 0, 46)
        drawCircle(0, 0, 34)
        noStroke()
        fill(ink.withAlpha(0.9))
        for i in 0 ..< 16 {
            withState {
                rotate(Double(i) / 16 * .tau)
                drawRect(-0.8, -44, 1.6, i % 4 == 0 ? 7 : 4)
            }
        }
        drawStar(0, 0, 30, 7, points: 8)
        fill(Color(hex: 0x060612))
        drawCircle(0, 0, 5)
        fill(ink)
        drawCircle(0, 0, 2.5)
    }
}
