import Ollin

/// A 30×30 grid of dots that flee the cursor: each dot is pushed away from
/// `mouseX`/`mouseY` and swells as the pointer nears it.
///
/// `dist` gives each dot's distance to the cursor; `map(..., clamp: true)`
/// turns that into a 0...1 closeness `pct` (1 right under the cursor, 0 once
/// it's 200 points away). `pct` then drives both the push (along the unit
/// vector away from the cursor) and the radius.
@main
final class RepelGrid: Sketch {
    override func setup() {
        noStroke()
    }

    override func draw() {
        background(.black)
        for i in 0..<30 {
            for j in 0..<30 {
                let x = map(Double(i), 0, 29, 50, 750)
                let y = map(Double(j), 0, 29, 50, 750)

                let distance = dist(x, y, mouseX, mouseY)
                let pct = map(distance, 0, 200, 1, 0, clamp: true)

                var dx = x - mouseX
                var dy = y - mouseY
                if distance > 0 {            // normalize to a unit push direction
                    dx /= distance
                    dy /= distance
                }

                circle(x: x + dx * pct * 50,
                       y: y + dy * pct * 50,
                       radius: 5 + 8 * pct)
            }
        }
    }
}
