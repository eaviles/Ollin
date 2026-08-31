import Ollin

/// A piece that remembers how far it got, gets itself back up, and keeps the
/// record of every time it had to.
///
/// A run on a wall ends in ways a run at a desk does not: a crash at three in
/// the morning, or a frame that never finishes and leaves the screen frozen
/// with the process still alive. `restarts` puts a small watch over the run. It
/// starts the piece again after a crash, and after a piece that is still
/// running stops answering, which is how a frozen frame is found at all.
///
/// Each launch draws its own ring, from the outside in, and each ring is as long
/// as that run lasted. So the picture is a record of the piece's own life: a
/// short arc is a run that ended badly, and the ring still growing is this one.
///
/// That record is something the clock alone cannot rebuild: the same run at
/// the same second could not tell you how the earlier ones ended. So the runs
/// are marked `@Saved`, and the checkpoint writes them down every five seconds.
/// It covers both kinds of end. Quit with Command-Q, an ordinary end that
/// nothing restarts, then run it again: the rings are where you left them.
/// Crash it, and the watch brings it back with the older rings intact. Run it
/// with `--fresh` to start over, and the saved record is left alone for next
/// time. The file is JSON you can open, in
/// `~/Library/Application Support/Ollin/`.
///
/// Try it. Press **c** to crash it and **h** to hang it, and watch the piece
/// come back on its own with the last ring stopped where it stopped. Without
/// the checkpoint beside `restarts` the piece would come back at the beginning
/// every time.
///
/// Five seconds between checkpoints and ten without answering are
/// demonstration settings; a minute, and the half-minute stall default, suit a
/// piece that is actually going up somewhere. Run it with `--no-installation`
/// to work on it in an ordinary window, where a crash stays crashed. See
/// `Docs/Output/Installation.md`.
@main
final class Watched: Sketch {

    override var installation: Installation {
        Installation(checkpoint: .every(seconds: 5),
                     restarts: .onFailure(stalledAfter: 10))
    }

    /// How long each launch so far lasted, oldest first. Saved, so the record
    /// survives the crash it is a record of.
    @Saved var runs: [Double] = []

    /// This run's own length, which is what the last entry above is kept at.
    private var thisRun = 0.0
    private var counted = false

    private let ink = Ramp([Color(red: 0.20, green: 0.26, blue: 0.38),
                            Color(red: 0.36, green: 0.62, blue: 0.80),
                            Color(red: 0.94, green: 0.82, blue: 0.54),
                            Color(red: 0.88, green: 0.42, blue: 0.38)])

    override func setup() {
        textFont(OutlineFont.system)
    }

    override func draw() {
        // The count goes up on the first frame rather than in `setup()`, and
        // that is not a style choice: saved state is put back *after* `setup()`
        // runs, because `setup()` is where a sketch fills its properties in. A
        // launch counted there would be overwritten a moment later.
        if !counted {
            counted = true
            runs.append(0)
        }
        thisRun += deltaTime
        runs[runs.count - 1] = thisRun

        background(Color(white: 0.05))
        noFill()
        strokeCap(.round)

        let shown = Array(runs.suffix(12))
        let outer = shortSide * 0.40
        let step = outer / 15
        for (index, seconds) in shown.enumerated() {
            let radius = outer - Double(index) * step
            let live = index == shown.count - 1
            // Two minutes is a whole turn, so a long run reads as a full ring
            // and a run that ended after a few seconds reads as a stub.
            let turn = min(1, seconds / 120)
            stroke(ink.color(at: live ? 0.75 : Double(index) / Double(max(1, shown.count)))
                    .withAlpha(live ? 1 : 0.55))
            strokeWeight(live ? step * 0.42 : step * 0.30)
            drawArc(center: center, radiusX: radius, radiusY: radius,
                    start: -.pi / 2, stop: -.pi / 2 + turn * .tau)
        }

        label()
    }

    private func label() {
        noStroke()
        textAlign(.center, .middle)
        fill(Color(white: 0.92))
        textSize(shortSide * 0.045)
        drawText("run \(runs.count)", center.x, center.y - shortSide * 0.02)
        textSize(shortSide * 0.028)
        fill(Color(white: 0.55))
        drawText("\(Int(thisRun))s of \(Int(runs.reduce(0, +)))s in all",
                 center.x, center.y + shortSide * 0.03)
        textSize(shortSide * 0.022)
        fill(Color(white: 0.38))
        drawText("c crashes it, h hangs it", center.x, height * 0.93)
    }

    override func keyPressed() {
        switch key?.lowercased() ?? "" {
        case "c":
            // The kind of end nobody is there to see. The watch reads the exit
            // status, starts another run, and the ring above stops here.
            fatalError("crashing on purpose, to show the piece coming back")
        case "h":
            // The other kind, and the one an exit status cannot show: the
            // process stays perfectly alive with the main thread stuck in this
            // frame for ever. Only the heartbeat that stops arriving finds it.
            while true {}
        default:
            break
        }
    }
}
