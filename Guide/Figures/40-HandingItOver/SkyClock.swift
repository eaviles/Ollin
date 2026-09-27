// figure: frame=0 unstable
//
// Guide payoff (Chapter 40): the sky clock, one sketch handed to the Mac's
// surfaces. A sky whose top and bottom colors are read from two ramps across
// the day, stars that fade in from six at night to six in the morning, a sun
// that crosses from six to six and a moon that crosses the other twelve hours,
// and a ridge of land drawn last so both set behind it. The hour comes from
// `date`, so the same file reads right in a window, as the wallpaper, in the
// menu-bar strip, and in a widget. Nothing reads the mouse or the keys, and
// every position and size is a fraction of the canvas. Unstable because the
// hour is the wall clock's when the render runs, and a figure has no public
// way to hold it, so each render draws a different part of the day.
import Ollin

final class SkyClock: Sketch {
    // The day as a band, midnight to midnight: 0.25 is six in the morning, 0.5 is noon.
    @Param var zenith = Ramp(stops: [(0.00, Color(hex: 0x060A1C)),
                                     (0.21, Color(hex: 0x0E1535)),
                                     (0.30, Color(hex: 0x4F77BF)),
                                     (0.50, Color(hex: 0x2B6ED3)),
                                     (0.72, Color(hex: 0x4A6CB4)),
                                     (0.79, Color(hex: 0x1C1B45)),
                                     (1.00, Color(hex: 0x060A1C))])
    @Param var horizon = Ramp(stops: [(0.00, Color(hex: 0x10162E)),
                                      (0.21, Color(hex: 0x2A2A55)),
                                      (0.26, Color(hex: 0xF3A06B)),
                                      (0.33, Color(hex: 0xC9E0F2)),
                                      (0.68, Color(hex: 0xC4DCF0)),
                                      (0.76, Color(hex: 0xEE7F4A)),
                                      (0.81, Color(hex: 0x2A2450)),
                                      (1.00, Color(hex: 0x10162E))])
    @Param var land = Color(hex: 0x10131C)

    override var canvasSize: CanvasSize { .size(1600, 900) }   // the shape it opens and exports at
    override var windowMode: WindowMode { .resizable }         // on a surface, the surface's size
    override var widgetTimeline: WidgetTimeline { .every(minutes: 15, count: 4) }

    var stars: [Vector2] = []

    override func setup() {
        seed(1440)                                              // the same stars and ridge in every picture
        stars = (0..<80).map { _ in Vector2(random(1), random(0.7)) }   // fractions, not pixels
    }

    override func draw() {
        let hour = WidgetTimeline.timeOfDay(at: date) / 3600    // 0 up to 24
        let day = hour / 24                                     // where the ramps are read

        noStroke()
        fill(.linear(from: uv(0, 0), to: uv(0, 0.8),
                     [zenith.color(at: day), horizon.color(at: day)]))
        drawRect(0, 0, width, height)

        let night = max(0, cos(day * .tau))                     // 1 at midnight, 0 from six to six
        fill(Color.white.withAlpha(night * 0.9))
        for star in stars {
            drawCircle(center: uv(star.x, star.y), radius: 2 * scale)
        }

        drawBody(at: (hour - 6) / 12, radius: 70 * scale, color: Color(hex: 0xFFD27A))
        drawBody(at: (hour + 6).truncatingRemainder(dividingBy: 24) / 12,
                 radius: 45 * scale, color: Color(hex: 0xE8ECF6))

        var ridge: [Vector2] = []
        for i in 0...48 {
            let u = Double(i) / 48
            ridge.append(uv(u, 0.76 + noise(u * 4) * 0.08))
        }
        fill(land)
        drawPolygon(ridge + [uv(1, 1), uv(0, 1)])
    }

    // A sun or a moon, `arc` of the way along its path: 0 rising at the left, 1 setting at the right.
    func drawBody(at arc: Double, radius: Double, color: Color) {
        guard arc > -0.1, arc < 1.1 else { return }             // below the land for the other half of the day
        let spot = uv(arc, 0.8 - sin(arc * .pi) * 0.6)
        fill(.radial(center: spot, radius: radius * 4, [color.withAlpha(0.3), color.withAlpha(0)]))
        drawCircle(center: spot, radius: radius * 4)
        fill(color)
        drawCircle(center: spot, radius: radius)
    }
}
