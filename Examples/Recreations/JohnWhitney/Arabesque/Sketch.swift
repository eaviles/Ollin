// A homage after John Whitney (1917-1995), made for learning. Not a reproduction
// of the film, and not affiliated with or endorsed by the artist or his estate.
// Written from his own analysis of *Arabesque* (1975, made with Larry Cuba as
// its programmer) in chapter IX of *Digital Harmony: On the Complementarity of
// Music and Visual Art* (Byte Books, 1980): a ring of 360 numbered points, all
// moving to the right, each at a rate set by its number, a point that reaches
// the right edge of the field coming back in at the left, and the action
// stopping at whole-number fractions of its cycle for a switch of polarity, in
// X, in Y, or in both. The book's chapter XII also prints a short Pascal
// program for the ring's first action (copyright John Whitney, 1980). It was
// read to check this reading of chapter IX, and none of it was copied: the code
// here is written from the chapter's prose. The chapter can be read as putting
// points 1 and 360 either side of the bottom of the ring; here, as in that
// program, point 360 stands on it, which is what makes a stop its own mirror
// image. How long a run and a switch take, the ring's size, the copies, and
// the color are this sketch's own.
import Ollin

/// Whitney's ring. The points are numbered around a circle from the bottom,
/// and point 1 moves right at one rate, point 2 at twice it, point 360 at three
/// hundred and sixty times it. A point that leaves on the right comes back on
/// the left, so the circle is combed out across the whole field and reads as
/// scatter. Whenever the action has covered a whole-number fraction of its
/// cycle, the points stand on rings again: two of them at a half, three at a
/// third, five at a fifth.
///
/// The film takes the cycle in stages. It runs to a fraction, stops there,
/// and turns the picture over, which he calls a switch of polarity. In X the
/// sign goes smoothly from plus to minus, and the figure closes to a vertical
/// line and opens as its mirror image. In Y it closes to a horizontal line
/// and opens upside down, and in both it closes to a point. Then the run goes
/// on, always to the right. Here `parts` is the fraction: a lap is that many
/// runs, each ending on rings, and the switches go X, Y, both, X, the order
/// he gives for the fifths of his third section.
///
/// A stop is its own mirror image left to right, so a switch in X ends on the
/// picture it began with. A switch in Y leaves the figure upside down until
/// the next one, and the last stop of a lap, the ring itself, turns it back if
/// it needs to, so the lap closes on the frame it opened with.
@main
final class Arabesque: Sketch {

    /// About how many points make the ring: the nearest multiple of `parts`,
    /// so that every stop puts the same number on each ring. His is 360.
    @Param(60...720) var points = 360
    /// Seconds for the whole cycle, which is the period of the loop.
    @Param(10...180) var cycle = 30.0
    /// The whole number the cycle is cut into. The action stops at each
    /// of these fractions.
    @Param(2...12) var parts = 5
    /// The ring's width as a share of its height: 1 is the circle that opens
    /// the film, less is the upright ellipse of its third section.
    @Param(0.2...1) var proportion = 0.5
    /// How many copies of the action play, one behind the other.
    @Param(1...6) var voices = 3
    /// Seconds between one copy and the next: near enough for all of them to
    /// share one switch. The film's enter 32 frames apart.
    @Param(0...4) var canon = 1.0
    /// How big the marks are.
    @Param(1...8) var dotSize = 3.2

    /// A wheel of light colors, so no turn of it goes dark.
    let wheel = CosinePalette(a: (0.6, 0.6, 0.6), b: (0.4, 0.4, 0.4),
                              c: (1, 1, 1), d: (0.0, 0.33, 0.67))

    /// The film's frame, four to three.
    override var canvasSize: CanvasSize { .size(1440, 1080) }
    override var loopDuration: Double? { cycle }

    /// The share of each part spent running; the rest is the switch.
    static let runShare = 0.62

    /// Which coordinates a stop switches.
    struct Switch: OptionSet {
        let rawValue: Int
        static let x = Switch(rawValue: 1)
        static let y = Switch(rawValue: 2)
        static let both: Switch = [.x, .y]
        /// The order of his third section, taken round again when a lap has
        /// more stops than four.
        static let order: [Switch] = [.x, .y, .both, .x]
    }

    /// Where the action is at one instant: how many whole parts of the cycle
    /// are behind it, how far into the running part it is, and the polarity
    /// of each coordinate.
    struct Moment {
        /// Whole parts of the cycle already covered.
        var covered: Int
        /// How far past them the run has gone, 0 to 1 of one part.
        var advance: Double
        /// The X and Y polarity, 1 to -1. Y stays at -1 between a switch in
        /// Y and the next one, which is the figure standing upside down.
        var polarity: Vector2
    }

    /// The action at `lap`, counted in cycles: the whole part of it is laps
    /// already made, and the rest says where in this lap it is.
    static func moment(lap: Double, parts: Int) -> Moment {
        let place = (lap - lap.rounded(.down)) * Double(parts)
        let part = min(parts - 1, Int(place))
        let within = place - Double(part)

        // Whether the figure stands upside down as this part begins: once for
        // every earlier stop whose switch took in Y.
        var upsideDown = false
        for stop in 0 ..< part where switchAt(stop: stop, of: parts, upsideDown: upsideDown).contains(.y) {
            upsideDown.toggle()
        }
        let standing = upsideDown ? -1.0 : 1.0

        if within < runShare {
            return Moment(covered: part, advance: glide(within / runShare),
                          polarity: Vector2(1, standing))
        }
        let turn = cos(.pi * glide((within - runShare) / (1 - runShare)))
        let axes = switchAt(stop: part, of: parts, upsideDown: upsideDown)
        return Moment(covered: part + 1, advance: 0,
                      polarity: Vector2(axes.contains(.x) ? turn : 1,
                                        axes.contains(.y) ? standing * turn : standing))
    }

    /// The switch made at a stop, counted from 0. The last stop of a lap is
    /// the ring come back, and it takes in Y only when the figure is upside
    /// down, so the lap ends the way it began.
    static func switchAt(stop: Int, of parts: Int, upsideDown: Bool) -> Switch {
        if stop == parts - 1 { return upsideDown ? .both : .x }
        return Switch.order[stop % Switch.order.count]
    }

    /// Slow away from a stop and slow into the next, so the rings are seen
    /// coming apart and coming together.
    static func glide(_ amount: Double) -> Double {
        let t = min(max(amount, 0), 1)
        return t * t * t * (t * (t * 6 - 15) + 10)
    }

    /// Every point of the ring at a moment, on a field `field` wide and
    /// centered on zero. Point `number` has moved right by `number` times the
    /// distance point 1 has, taken modulo the field.
    static func figure(count: Int, parts: Int, moment: Moment,
                       field: Double, radius: Vector2) -> [Vector2] {
        (1 ... count).map { number in
            let angle = .tau * Double(number) / Double(count)
            // The parts already covered are whole numbers of 1/parts, so that
            // share of the travel is kept exact; only the run in hand is not.
            let whole = Double((number * moment.covered) % parts) / Double(parts)
            let running = Double(number) * moment.advance / Double(parts)
            let travel = whole + running
            var x = radius.x * sin(angle) + (travel - travel.rounded(.down)) * field
            x -= ((x + field / 2) / field).rounded(.down) * field
            return Vector2(x * moment.polarity.x, radius.y * cos(angle) * moment.polarity.y)
        }
    }

    /// The number of points drawn: `points` to the nearest multiple of `parts`.
    var count: Int { max(1, (points + parts / 2) / parts) * parts }

    override func draw() {
        background(Color(white: 0.03))
        noStroke()

        blendMode(.add)

        let reach = height * 0.4
        for voice in 0 ..< voices {
            // Each copy is the same action, later by `canon` seconds.
            let lap = (time - Double(voice) * canon) / cycle
            let moment = Self.moment(lap: lap, parts: parts)
            let ring = Self.figure(count: count, parts: parts, moment: moment, field: width,
                                   radius: Vector2(reach * proportion, reach))

            // One color to a copy, each turning once around the wheel in a lap.
            fill(wheel.color(at: lap + Double(voice) / Double(voices) * 0.5))
            drawCircles(ring.map { center + $0 }, radius: dotSize * scale)
        }
    }
}
