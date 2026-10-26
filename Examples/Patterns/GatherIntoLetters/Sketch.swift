import Ollin

/// A cloud of dots gathers into a word, scatters, and gathers into the next,
/// each dot sent to one point of the letters so that the distance everyone
/// travels, added up, is the least it can be. Choosing who goes where is the
/// assignment problem, and `Matching.optimal` solves it exactly. With distance
/// as the cost no two roads ever cross, which is why the flight reads as one
/// calm motion rather than a swarm, and every road is drawn while the dots are
/// on it.
///
/// Press `g` to pair the same journey by the greedy rule instead, each dot in
/// turn taking the nearest point still free: the roads tangle, and the caption
/// says how much farther everyone travels for it.
///
/// ```sh
/// swift run Example-Patterns-GatherIntoLetters --export-loop /tmp/gather.gif
/// ```
@main
final class GatherIntoLetters_Example: Sketch {
    private let words = ["GATHER", "INTO", "LETTERS"]
    private let period = 2.5
    /// The flight's share of a period: the dots lift off a little after they
    /// have landed and are down again with a third of the period to hold.
    private let liftOff = 0.05, landing = 0.65
    /// A lap is a gather and a scatter per word.
    override var loopDuration: Double? { period * Double(words.count * 2) }

    private let count = 1_600
    /// `stops[k][i]` is where dot `i` sits before flight `k`, one list per
    /// pairing rule, so the whole journey is known before the first frame.
    private var optimalStops: [[Vector2]] = []
    private var greedyStops: [[Vector2]] = []
    private var optimalTravel: [Double] = []
    private var greedyTravel: [Double] = []
    private var greedy = false

    override func setup() {
        seed(7)
        // The places the dots visit in turn: a cloud over the canvas, then a
        // word, then another cloud, then the next word. Each word is made of
        // as many points per letter as its area deserves, fitted to one width.
        var places: [[Vector2]] = []
        let field = canvasRectangle.inset(by: Insets(top: 70, right: 70, bottom: 110, left: 70))
        for word in words {
            places.append((0 ..< count).map { _ in randomVector(in: field) })
            textSize(100)
            let probe = boxAround(textToShapes(word, at: .zero))
            textSize(100 * 900 / max(probe.width, 1))
            let shapes = textToShapes(word, at: .zero)
            let shift = center - boxAround(shapes).center
            let area = shapes.reduce(0.0) { $0 + $1.area }
            var points: [Vector2] = []
            for (k, shape) in shapes.enumerated() {
                let share = k == shapes.count - 1
                    ? count - points.count
                    : Int((Double(count) * shape.area / area).rounded())
                points += randomPoints(in: shape, count: share).map { $0 + shift }
            }
            places.append(points)
        }
        // The places come round in a fixed order, so every flight's pairing is
        // found once here. A dot's next stop is the point its partner names.
        optimalStops = [places[0]]
        greedyStops = [places[0]]
        for k in places.indices {
            let next = places[(k + 1) % places.count]
            let best = Matching.optimal(optimalStops[k], next)
            optimalStops.append((0 ..< count).map { next[best.partner(of: $0) ?? 0] })
            optimalTravel.append(best.totalCost)
            let rough = Matching.greedy(greedyStops[k], next)
            greedyStops.append((0 ..< count).map { next[rough.partner(of: $0) ?? 0] })
            greedyTravel.append(rough.totalCost)
        }
    }

    override func draw() {
        background(Color(hex: 0x0E1117))
        let stops = greedy ? greedyStops : optimalStops
        let lap = (time / period).rounded(.down)
        let flight = Int(lap) % (words.count * 2)
        let phase = time / period - lap
        let progress = smoothstep(liftOff, landing, phase)
        let from = stops[flight], to = stops[flight + 1]
        let flying = progress > 0 && progress < 1

        if flying {
            // Every dot's whole road, faint, so the pairing itself shows.
            stroke(Color(hex: 0x3E5C7E).withAlpha(0.4))
            strokeWeight(1 * scale)
            for i in 0 ..< count { drawLine(from[i], to[i]) }
        }
        noStroke()
        fill(flying ? Color(hex: 0xE8B44A) : Color(hex: 0xF2EFE8))
        for i in 0 ..< count {
            drawCircle(center: from[i].lerp(to: to[i], progress), radius: 3 * scale)
        }

        let least = optimalTravel[flight], rough = greedyTravel[flight]
        let travel = Int((greedy ? rough : least) / 1000)
        drawCaption(greedy
            ? "greedy pairing: \(count) dots travel \(travel)k points, "
                + String(format: "%.2f", rough / least) + " times the least (g: optimal)"
            : "optimal pairing: \(count) dots travel \(travel)k points, no two roads cross (g: greedy)")
    }

    override func keyPressed() {
        if key == "g" { greedy.toggle() }
    }

    /// The one rectangle around every glyph of a word.
    private func boxAround(_ shapes: [Shape]) -> Rectangle {
        let boxes = shapes.compactMap(\.bounds)
        guard let first = boxes.first else { return Rectangle(center: .zero, width: 1, height: 1) }
        return boxes.dropFirst().reduce(first) { $0.union($1) }
    }
}
