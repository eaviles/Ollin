import Ollin

/// Steer a dot with the keyboard. `moveAxis`, polled every frame in `draw()`,
/// folds WASD and the arrows into one -1...1 direction in canvas orientation
/// (up is `(0, -1)`, opposite keys cancel), so the eight-line key check every
/// driving sketch writes becomes a single read. Tap the space bar to shift the
/// trail's color (`keyPressed()`, reading `key`); letting any key go flashes a
/// ring off the dot (`keyReleased()`, the once-per-release hook).
@main
final class Keys: Sketch {
    private var x = 0.0
    private var y = 0.0
    private var trail: [Vector2] = []
    private var hue = 0.55
    private var releasedAt = -1.0

    override func setup() {
        noStroke()
        x = width / 2
        y = height / 2
    }

    override func draw() {
        background(.black)

        // The held movement keys as one read: `moveAxis` folds WASD and the
        // arrows into a single -1...1 direction, opposite keys cancelling.
        let speed = 7 * scale
        x += moveAxis.x * speed
        y += moveAxis.y * speed

        let r = 22 * scale
        x = max(r, min(width - r, x))           // keep the dot on the canvas
        y = max(r, min(height - r, y))

        // A short trail makes the motion legible, and visible in a still frame.
        trail.append(Vector2(x, y))
        if trail.count > 48 { trail.removeFirst() }

        for (i, p) in trail.enumerated() {
            let t = Double(i) / Double(max(1, trail.count - 1))   // 0 oldest … 1 newest
            // The cosine palette cycles by construction, so no wrap is needed.
            fill(CosinePalette.rainbow.color(at: hue + t * 0.15))
            drawCircle(p.x, p.y, r * (0.3 + 0.7 * t))
        }

        // A released key flashes a ring off the dot: `keyReleased()` stamped
        // the time below, and the ring grows and fades for half a second.
        let age = time - releasedAt
        if age >= 0, age < 0.5 {
            withState {
                noFill()
                stroke(Color(white: 1, alpha: 0.8 * (1 - age / 0.5)))
                strokeWeight(3 * scale)
                drawCircle(x, y, r + age * 260 * scale)
            }
        }
    }

    /// A one-shot key action: the space bar shifts where the trail samples the
    /// rainbow palette.
    override func keyPressed() {
        if key == " " { hue += 0.17 }
    }

    /// The one-shot release hook: any key letting go starts the ring flash.
    override func keyReleased() {
        releasedAt = time
    }
}
