import Ollin

/// A day passing over a bay, and the sketch saying what it shows while it
/// shows it. Turn on VoiceOver (⌘F5) and the window reads back the sentence
/// under `describe`, then each named part in turn.
///
/// The point of the example is where the words come from: the same numbers that
/// place the sun write the sentence about the sun, so the description cannot
/// drift away from the picture. Nothing here is written twice.
///
/// Two things worth watching. The sun is dropped from the description when it
/// sets, because a part that has left the picture must leave the words with it.
/// And the glow and the shimmer on the water are never described: they are
/// texture, not meaning, and a list of every shape tells nobody what the piece
/// looks like.
///
/// The `showWords` parameter draws the description on the canvas, so you can read
/// what somebody using a screen reader is given.
@main
final class Describing: Sketch {

    /// Draw the description as well as saying it, so it can be checked by eye.
    @Param(icon: "text.bubble") var showWords = true

    let day = 24.0                       // one day per 24 seconds
    override var loopDuration: Double? { day }

    override func setup() {
        textFont(.systemMedium)
    }

    override func draw() {
        // The day opens a little after sunrise, so the sun is in the picture on
        // the first frame and takes the first place in the reading order.
        let phase = loopProgress(over: day, phase: 0.06)
        let daylight = max(0, sin(phase * .tau))     // 0 at night, 1 at noon

        // The sun rides a half circle over the bay, and drops below it at night.
        let horizon = height * 0.68
        let sunRadius = width * 0.055
        let sunCenter = Vector2(width * (0.1 + 0.8 * phase),
                                horizon - sin(phase * .tau) * height * 0.5)
        let sun = Rectangle(center: sunCenter, width: sunRadius * 2, height: sunRadius * 2)
        let sunIsUp = sunCenter.y + sunRadius < horizon

        // A boat crosses the water once a day, the other way round.
        let boatX = width * (0.95 - 0.9 * phase)
        let boat = Rectangle(center: Vector2(boatX, horizon + height * 0.14),
                             width: width * 0.1, height: height * 0.06)

        drawScene(daylight: daylight, horizon: horizon, sun: sun, boat: boat)

        // What the sketch says about itself, written from the same numbers.
        describe("A bay at \(timeOfDay(phase)). \(sky(sunIsUp: sunIsUp, at: sunCenter)), "
                 + "and a small boat crosses the water \(boatHeading(phase)).")
        // A part that is no longer in the picture is dropped from the
        // description: empty words remove it.
        describe("the sun", as: sunIsUp
                 ? "\(sunColor(daylight)) disc \(place(of: sunCenter)), \(Int(sunRadius * 2)) wide"
                 : "", in: sun)
        describe("the water", as: "a flat band across the lower third, "
                 + "\(daylight > 0.15 ? "blue-gray and lit" : "almost black")",
                 in: Rectangle(x: 0, y: horizon, width: width, height: height - horizon))
        describe("the boat", as: "a small dark hull with one sail, "
                 + "\(Int(boatX / width * 100))% of the way across", in: boat)

        if showWords { drawWords() }
    }

    // MARK: - The picture

    private func drawScene(daylight: Double, horizon: Double, sun: Rectangle, boat: Rectangle) {
        background(Color.mix(Color(hex: 0x121A2B), Color(hex: 0x9EC6E8), daylight))
        noStroke()

        // The sun, with a soft glow that fades as it drops.
        let disc = Color.mix(Color(hex: 0xE8DCC8), Color(hex: 0xFFE9A8), daylight)
        for ring in stride(from: 5.0, through: 1.0, by: -1.0) {
            fill(disc.withAlpha(0.055 * daylight))
            drawCircle(center: sun.center, radius: sun.width / 2 * ring)
        }
        fill(disc)
        drawCircle(center: sun.center, radius: sun.width / 2)

        // The water, and a few shimmer bands lying on it.
        let water = Color.mix(Color(hex: 0x0B1220), Color(hex: 0x3E7CA6), daylight)
        fill(water)
        drawRect(0, horizon, width, height - horizon)
        for i in 0 ..< 9 {
            let y = horizon + (height - horizon) * (Double(i) + 0.5) / 9
            let sway = sin(time * 0.6 + Double(i)) * width * 0.06
            fill(Color.white.withAlpha(0.05 * daylight))
            drawRect(center: Vector2(width * 0.5 + sway, y),
                     width: width * (0.5 - Double(i) * 0.04), height: 3 * scale)
        }

        // The boat: a hull and one sail.
        fill(Color(hex: 0x16202E))
        drawTriangle(Vector2(boat.center.x, boat.corner.y),
                     Vector2(boat.center.x + boat.width * 0.32, boat.center.y),
                     Vector2(boat.center.x, boat.center.y))
        drawRect(center: Vector2(boat.center.x, boat.center.y + boat.height * 0.22),
                 width: boat.width * 0.75, height: boat.height * 0.2)
    }

    /// Draw the description, so what is said and what is drawn can be compared.
    private func drawWords() {
        withState {
            noStroke()
            let lines = accessibleDescription.lines
            let lineHeight = 26 * scale
            fill(Color(red: 0, green: 0, blue: 0, alpha: 0.55))
            drawRect(0, 0, width, lineHeight * Double(lines.count) + 24 * scale)
            fill(.white)
            textSize(14 * scale)
            textAlign(.left, .middle)
            for (i, line) in lines.enumerated() {
                drawText(line, 20 * scale, 22 * scale + Double(i) * lineHeight)
            }
        }
    }

    // MARK: - The words

    /// The sun rises at phase 0 and sets at phase 0.5, so the names have to
    /// change on the same numbers the sun does.
    private func timeOfDay(_ phase: Double) -> String {
        switch phase {
        case ..<0.05: "dawn"
        case ..<0.20: "mid morning"
        case ..<0.32: "noon"
        case ..<0.45: "late afternoon"
        case ..<0.50: "dusk"
        default: "night"
        }
    }

    private func sky(sunIsUp: Bool, at p: Vector2) -> String {
        sunIsUp ? "The sun stands \(place(of: p))" : "The sky is empty and dark"
    }

    private func sunColor(_ daylight: Double) -> String {
        daylight > 0.5 ? "a pale yellow" : "a deep orange"
    }

    /// Where something is, in the words a person would use.
    private func place(of p: Vector2) -> String {
        let up = p.y < height * 0.3 ? "high" : p.y < height * 0.6 ? "halfway up" : "low"
        let across = p.x < width * 0.4 ? "left" : p.x > width * 0.6 ? "right" : "middle"
        return "\(up) on the \(across)"
    }

    private func boatHeading(_ phase: Double) -> String {
        phase < 0.5 ? "from the right" : "toward the left"
    }
}
