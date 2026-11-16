// A homage after John Whitney (1917-1995), made for learning. Not a reproduction
// of the film, and not affiliated with or endorsed by the artist or his estate.
// Written from his own account of *Matrix* (1971) in *Digital Harmony: On the
// Complementarity of Music and Visual Art* (Byte Books, 1980): "All motion is
// along a closed invisible pathway (the matrix) which is a classical Lissajous
// figure positioned symmetrically within the motion picture field", and the
// film "is simply a sequence of events of clustering and dispersal"; a figure
// caption in the same book counts 24 squares on a three-dimensional pathway,
// and its chapter on differential motion gives the rule, one element at a
// rate, the second at twice it, the third at three times. No code of anyone's
// was ported. The pathway's numbers, the turning of the squares, the stops,
// and the color are this sketch's own.
import Ollin

/// Whitney's matrix. Twenty-four squares travel one closed path that is never
/// drawn, and square 1 goes along it at one rate, square 2 at twice that,
/// square 24 at twenty-four times. They leave from one place as one square,
/// string out along the path, and keep meeting again in small companies: two
/// places at half the cycle, three at a third, eight at an eighth. He called
/// the film a sequence of clustering and dispersal, and that is all it is.
///
/// The path is a Lissajous figure in three dimensions. Across and down it is
/// a figure eight lying on its side, gone around twice in one circuit; the
/// third dimension is depth, gone through once, and a square is drawn larger
/// the nearer it is. So the two passes over one place on the eight happen at
/// two depths, and a meeting there is a small square inside a large one.
///
/// The action steps. The cycle is cut into as many parts as there are squares,
/// and in each part the last square goes once around the whole path while the
/// first moves a twenty-fourth of it, so every stop finds every square on one
/// of twenty-four places. A square turns as it travels, an eighth of a turn
/// from one place to the next, and so stands square or on its corner at a
/// stop.
@main
final class Matrix: Sketch {

    /// How many squares travel the path, counted in twos. The cycle has this
    /// many stops. A square that has gone once around has turned an eighth of
    /// a turn for every place, and an even count brings it home standing as it
    /// left.
    @Param(6...48, step: 2) var squares = 24
    /// Seconds for the whole cycle, which is the period of the loop.
    @Param(12...240) var cycle = 72.0
    /// How much nearer and farther the path runs: the side of the nearest
    /// square over the side of the farthest.
    @Param(1...12) var depth = 6.0
    /// The width of the lines.
    @Param(0.5...6) var lineWidth = 2.2

    /// The film's frame, four to three.
    override var canvasSize: CanvasSize { .size(1440, 1080) }
    override var loopDuration: Double? { cycle }

    /// The share of each part spent moving; the rest holds on the stop.
    static let moveShare = 0.78

    /// One square at a moment: where its middle is, the length of its side,
    /// and how far it has turned.
    struct Placed {
        var center: Vector2
        var side: Double
        var turn: Double

        /// The four corners, in order around the square.
        var corners: [Vector2] {
            let half = side / 2
            return [Vector2(-half, -half), Vector2(half, -half), Vector2(half, half), Vector2(-half, half)]
                .map { center + $0.rotated(by: turn) }
        }
    }

    /// The pathway. `along` counts circuits, so 0 and 1 are the same place:
    /// the middle of the field, at the nearest depth. `reach` is how far the
    /// eight extends each way from the middle, `near` the side of a square at
    /// the nearest depth, `depth` that side over the farthest one's, and
    /// `places` how many places the path is cut into (a square turns an
    /// eighth of a turn from one to the next).
    static func path(along: Double, reach: Vector2, near: Double, depth: Double, places: Int) -> Placed {
        let angle = .tau * along
        // A point twice as far away is drawn half the size. With the nearest
        // depth at distance 1 the farthest is at distance `depth`.
        let distance = 1 + (depth - 1) * (1 - cos(angle)) / 2
        return Placed(center: Vector2(reach.x * sin(2 * angle), reach.y * sin(4 * angle)),
                      side: near / distance,
                      turn: .pi / 4 * along * Double(places))
    }

    /// How far around the path square `number` is at `lap` (0 to 1 of the
    /// cycle), in circuits. The parts already covered are whole numbers of
    /// one place, so that share is kept exact.
    static func progress(of number: Int, lap: Double, squares: Int) -> Double {
        let place = (lap - lap.rounded(.down)) * Double(squares)
        let part = min(squares - 1, Int(place))
        let within = (place - Double(part)) / moveShare
        let whole = Double((number * part) % squares) / Double(squares)
        return whole + Double(number) * glide(within) / Double(squares)
    }

    /// Slow away from a stop and slow into the next.
    static func glide(_ amount: Double) -> Double {
        let t = min(max(amount, 0), 1)
        return t * t * t * (t * (t * 6 - 15) + 10)
    }

    /// Three line colors, dealt to the squares in turn.
    let inks = [Color(red: 0.99, green: 0.95, blue: 0.84),
                Color(red: 1.0, green: 0.80, blue: 0.16),
                Color(red: 1.0, green: 0.36, blue: 0.20)]

    override func draw() {
        let lap = loopProgress(over: cycle)

        // The ground warms from maroon to red and back once in a lap.
        let warmth = (1 - cos(.tau * lap)) / 2
        background(Color(red: 0.24, green: 0.04, blue: 0.11)
            .mixed(with: Color(red: 0.62, green: 0.07, blue: 0.09), warmth, in: .oklab))

        noFill()
        strokeWeight(lineWidth * scale)
        strokeJoin(.miter)

        let reach = Vector2(width * 0.29, height * 0.21)
        for number in 1 ... squares {
            let along = Self.progress(of: number, lap: lap, squares: squares)
            let square = Self.path(along: along, reach: reach, near: height * 0.44,
                                   depth: depth, places: squares)
            stroke(inks[number % inks.count])
            drawPolyline(square.corners.map { center + $0 }, closed: true)
        }
    }
}
