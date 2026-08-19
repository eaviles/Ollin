// figure: frame=1
//
// Guide diagram (Chapter 23): the two ways an unattended run ends badly, and
// what the watch does about each. A night on the timeline: a crash, a frame
// that never finishes, and a piece back up within seconds of both.
import Ollin

final class BackUp: Sketch {
    override var canvasSize: CanvasSize { .size(880, 396) }

    let paper = Color(hex: 0xF7F5F1)
    let ink = Color(hex: 0x2B2B2B)
    let soft = Color(hex: 0x2B2B2B, alpha: 0.55)
    let accent = Color(hex: 0xE4572E)
    let live = Color(hex: 0x6B9EC7)
    let frozen = Color(hex: 0x9AA3AE)

    /// The night, in hours from 22:00.
    let hours = 10.0
    let left = 124.0, right = 838.0

    /// Each run: when it started, when it ended, and how it ended. The second
    /// one keeps running long after it stops answering, which is the whole
    /// point of the picture.
    let runs: [(start: Double, quiet: Double, end: Double, how: String)] = [
        (0.0, 3.3, 3.3, "crash"),
        (3.4, 6.2, 6.7, "stopped answering"),
        (6.8, 10.0, 10.0, ""),
    ]

    override func draw() {
        background(paper)
        noStroke()

        axis(y: 330)
        for run in runs { bar(run, y: 150) }
        beats(y: 246)
        caption()
    }

    /// One run: the stretch it was answering, then the stretch it was still
    /// there and no longer answering, then how it ended.
    func bar(_ run: (start: Double, quiet: Double, end: Double, how: String), y: Double) {
        let height = 30.0
        fill(live)
        drawRect(x(run.start), y, x(run.quiet) - x(run.start), height, cornerRadius: 5)
        if run.end > run.quiet {
            // Alive, and no longer drawing. Nothing in the exit status says so.
            fill(frozen)
            drawRect(x(run.quiet), y, x(run.end) - x(run.quiet), height, cornerRadius: 5)
        }
        guard !run.how.isEmpty else { return }

        stroke(accent)
        strokeWeight(2)
        drawLine(Vector2(x(run.end), y - 12), Vector2(x(run.end), y + height + 12))
        noStroke()
        fill(accent)
        textSize(15)
        textAlign(.center, .bottom)
        drawText(run.how, x(run.end), y - 18)
    }

    /// The heartbeat under the runs: a mark every couple of seconds while the
    /// main thread is turning, and nothing at all once it is stuck.
    func beats(y: Double) {
        fill(soft)
        textSize(15)
        textAlign(.right, .middle)
        drawText("heartbeat", left - 16, y + 4)

        for run in runs {
            var at = run.start + 0.12
            while at < run.quiet {
                fill(live)
                drawRect(center: Vector2(x(at), y + 4), width: 3, height: 14, cornerRadius: 1.5)
                at += 0.22
            }
        }
        fill(soft)
        textSize(14)
        textAlign(.center, .top)
        drawText("nothing arrives, so the watch stops it",
                 (x(6.2) + x(6.7)) / 2 + 40, y + 20)
    }

    func axis(y: Double) {
        stroke(ink.withAlpha(0.35))
        strokeWeight(1)
        drawLine(Vector2(left, y), Vector2(right, y))
        noStroke()
        fill(soft)
        textSize(14)
        textAlign(.center, .top)
        for hour in stride(from: 0.0, through: hours, by: 2) {
            let clock = (22 + Int(hour)) % 24
            drawText(String(format: "%02d:00", clock), x(hour), y + 10)
        }

        fill(ink)
        textSize(15)
        textAlign(.right, .middle)
        drawText("the piece", left - 16, 165)
    }

    func caption() {
        fill(soft)
        textSize(16)
        textAlign(.center, .top)
        drawText("the process you start is the watch; the piece runs as its child, and a new one starts within seconds",
                 width / 2, 366)
    }

    func x(_ hour: Double) -> Double { left + (right - left) * hour / hours }
}
