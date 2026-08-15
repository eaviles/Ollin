import Foundation
import Ollin

/// One canvas across every display the machine has.
///
/// The canvas here is long and low, the shape of a wall rather than of a screen.
/// Declaring `.spanning` spreads it over the displays in the arrangement they
/// are actually in, so two monitors side by side carry a half each and the sun
/// crossing it goes out of one and into the next.
///
/// Nothing in the drawing knows about any of that. It draws one canvas, and the
/// wall decides which part of it each display carries.
///
/// To see the wall before you have built it, rehearse it on one desk:
///
///     swift run --package-path Examples Example-Installation-ManyDisplays --rehearse 3
///
/// That opens one window per part, side by side. They are laid out apart rather
/// than overlapped, because two beams sharing a band add their light and two
/// windows sharing one would only hide each other.
///
/// The rule across the top is there for the same minute the corner handles are:
/// its ticks are every hundredth of the canvas and every tenth is taller, so a
/// join between two displays is easy to read and easy to line up. The rest is
/// the work. See `Docs/Output/Installation.md`.
@main
final class ManyDisplays: Sketch {

    override var canvasSize: CanvasSize { .size(3200, 900) }

    override var installation: Installation { Installation(displays: .spanning) }

    /// The piece repeats, so the clock the shaders read can start over on a lap
    /// and nothing on the wall moves when it does.
    override var loopDuration: Double? { 120 }

    private let sky = Ramp([Color(red: 0.04, green: 0.05, blue: 0.10),
                            Color(red: 0.10, green: 0.14, blue: 0.26),
                            Color(red: 0.35, green: 0.24, blue: 0.30)])

    override func draw() {
        background(Color(white: 0.03))
        drawTheSky()
        drawTheTide()
        drawTheSun()
        drawTheRule()
    }

    /// Bands down the canvas, so a display carrying its own part still shows a
    /// piece of the same sky as the display beside it.
    private func drawTheSky() {
        noStroke()
        let bands = 90
        let step = height * 0.62 / Double(bands)
        for band in 0..<bands {
            fill(sky.color(at: Double(band) / Double(bands)))
            drawRect(0, Double(band) * step, width, step + 1)
        }
    }

    /// A slow tide the length of the wall, drawn as one line of marks so that a
    /// wave leaving one display arrives on the next at the same height.
    private func drawTheTide() {
        noStroke()
        let marks = 640
        let lap = loopProgress(over: 120) * .tau
        for mark in 0..<marks {
            let u = Double(mark) / Double(marks - 1)
            let x = u * width
            let swell = sin(u * .tau * 3 + lap) * 0.5 + sin(u * .tau * 7 - lap * 1.6) * 0.28
            let y = height * 0.66 + swell * height * 0.13
            let lift = (swell + 0.8) / 1.6
            fill(Color(red: 0.55 + lift * 0.4, green: 0.72 + lift * 0.2,
                       blue: 0.86, alpha: 0.55 + lift * 0.4))
            drawCircle(x, y, 2.5 + lift * 4)
        }
    }

    /// One disc that crosses the whole canvas over a lap. On a wall it leaves
    /// one display and arrives on the next, which is the thing worth watching:
    /// it is one piece rather than several pieces in a row.
    private func drawTheSun() {
        let along = loopProgress(over: 120)
        let x = -height * 0.2 + along * (width + height * 0.4)
        let y = height * 0.42 - sin(along * .pi) * height * 0.22
        noStroke()
        for ring in stride(from: 5, through: 1, by: -1) {
            let radius = height * 0.06 * Double(ring)
            fill(Color(red: 0.98, green: 0.86, blue: 0.62, alpha: 0.05))
            drawCircle(x, y, radius)
        }
        fill(Color(red: 1, green: 0.93, blue: 0.78))
        drawCircle(x, y, height * 0.055)
    }

    /// A rule along the top, for the minute somebody is lining the wall up: a
    /// tick every hundredth of the canvas, a taller one every tenth.
    private func drawTheRule() {
        stroke(Color(white: 0.85, alpha: 0.5))
        strokeWeight(2)
        for tick in 0...100 {
            let x = Double(tick) / 100 * width
            let long = tick % 10 == 0
            drawLine(x, 0, x, long ? 34 : 14)
        }
    }
}
