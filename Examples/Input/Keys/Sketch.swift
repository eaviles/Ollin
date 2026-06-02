import Ollin

/// Steer a dot with the keyboard. Hold the arrow keys (or WASD) and it glides —
/// `isKeyDown(_:)`, polled every frame in `draw()`, gives smooth motion while a
/// key is held, which the once-per-press `keyPressed()` hook can't. Tap the
/// space bar to shift the trail's color (`keyPressed()`, reading `key`).
@main
final class Keys: Sketch {
    private var x = 0.0
    private var y = 0.0
    private var trail: [Vector2] = []
    private var hue = 0.55

    override func setup() {
        noStroke()
        x = width / 2
        y = height / 2
    }

    override func draw() {
        background(.black)

        // Held-key polling: move while a direction key is down — arrows or WASD,
        // so this shows `isKeyDown(_:)` for both a named key and a character.
        let speed = 7 * scale
        if isKeyDown(.leftArrow)  || isKeyDown("a") { x -= speed }
        if isKeyDown(.rightArrow) || isKeyDown("d") { x += speed }
        if isKeyDown(.upArrow)    || isKeyDown("w") { y -= speed }
        if isKeyDown(.downArrow)  || isKeyDown("s") { y += speed }

        let r = 22 * scale
        x = max(r, min(width - r, x))           // keep the dot on the canvas
        y = max(r, min(height - r, y))

        // A short trail makes the motion legible — and visible in a still frame.
        trail.append(Vector2(x, y))
        if trail.count > 48 { trail.removeFirst() }

        for (i, p) in trail.enumerated() {
            let t = Double(i) / Double(max(1, trail.count - 1))   // 0 oldest … 1 newest
            fill(Palette.rainbow.color(at: (hue + t * 0.15).truncatingRemainder(dividingBy: 1)))
            drawCircle(p.x, p.y, r * (0.3 + 0.7 * t))
        }
    }

    /// A one-shot key action: the space bar shifts where the trail samples the
    /// rainbow palette.
    override func keyPressed() {
        if key == " " { hue = (hue + 0.17).truncatingRemainder(dividingBy: 1) }
    }
}
