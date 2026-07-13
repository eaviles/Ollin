import Ollin

/// The spring family portrait. Five dots chase the same hopping target, each
/// with a different `bounce`: drag (slow ooze), critical (fastest possible
/// arrival with no overshoot), and three grades of wobble. Same knob, five
/// personalities; watching them race is how to pick a feel.
///
/// The big dot is `@Sprung`: it chases the mouse with real momentum, so
/// moving the target mid-flight bends its path instead of restarting it,
/// and a click kicks it. That carried velocity is the thing an eased tween
/// cannot do, and it is why springs feel alive under a hand.
@main
final class Springs: Sketch {
    private var racers: [DampedSpring<Double>] = []
    private let bounces = [-0.5, 0.0, 0.3, 0.6, 0.85]

    @Sprung(duration: 0.55, bounce: 0.35) private var chaser = Vector2(540, 700)

    override func setup() {
        racers = bounces.map { DampedSpring(value: 330, duration: 0.6, bounce: $0) }
    }

    override func draw() {
        background(Color(hex: 0x12151C))
        // Posts inset far enough that even the wobbliest overshoot stays in
        // frame.
        let left = 330.0, right = width - 330
        let hop = Int(time / 2)                         // everyone retargets together
        let target = hop.isMultiple(of: 2) ? right : left

        textFont(OutlineFont.system)
        textSize(22)
        textAlign(.left, .bottom)
        for (i, bounce) in bounces.enumerated() {
            let y = 150 + Double(i) * 92
            // The lane and the two posts.
            stroke(Color(hex: 0x272C38)); strokeWeight(3)
            drawLine(left, y, right, y)
            for x in [left, right] {
                stroke(Color(hex: 0x3A4152)); strokeWeight(2)
                drawLine(x, y - 16, x, y + 16)
            }

            racers[i].step(toward: target, dt: deltaTime)
            noStroke()
            fill(Color(hue: 0.5 + Double(i) * 0.09, saturation: 0.65, brightness: 0.95))
            drawCircle(racers[i].value, y, 17)

            fill(Color(hex: 0x77809A))
            let label = bounce == 0 ? "bounce 0 (critical)" : "bounce \(bounce)"
            drawText(label, left, y - 26)
        }

        // The momentum dot: retargeted every frame, kicked on click.
        chaser = mouseIsPressed || mouseX > 0 || mouseY > 0
            ? Vector2(mouseX, mouseY) : Vector2(540, 700)
        noStroke()
        fill(Color(hex: 0xE9C46A))
        drawCircle(center: chaser, radius: 26)
        stroke(Color(hex: 0xE9C46A).withAlpha(0.4)); strokeWeight(2); noFill()
        drawLine(chaser, $chaser.target)
        drawCircle(center: $chaser.target, radius: 6)

        drawCaption("five bounces, one knob. move the mouse; click to kick")
    }

    override func mousePressed() {
        $chaser.kick(Vector2(0, -1400))
    }
}
