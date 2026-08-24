import Ollin

/// A shape hidden in the picture's own repetition.
///
/// The background repeats at a fixed spacing, so both eyes pair up the same
/// pattern and read it at the depth that spacing stands for. Shorten the repeat a
/// little and the pair reads as nearer. That is the whole trick: a depth map
/// becomes a picture by shortening the repeat wherever the shape is closer, and
/// the surface you end up seeing was never drawn.
///
/// Look *through* the picture, at something behind the screen, until the repeats
/// double up. It takes a moment the first time. Crossing your eyes instead reads
/// the same picture inside out, so the shape sinks rather than stands.
///
/// Hold the mouse to see the depth map it was built from.
///
/// The picture is drawn at its own pixel size rather than scaled, which matters
/// here more than anywhere else: scaling resamples the repeats the eyes have to
/// pair. View the window at its true size, not zoomed.
///
/// The relief travels over the loop, from flat to as deep as the eyes can still
/// pair. Watch what happens at the far end: past about a third of the repeat the
/// picture stops fusing at all, which is the honest limit of the technique rather
/// than a setting to turn up.
@main
final class Autostereogram_Example: Sketch {
    override var loopDuration: Double? { 16 }

    // The depth map is made at the size it will be drawn at, so the picture goes
    // down one pixel per pixel. Scaling a stereogram resamples the very repeats
    // the eyes have to pair, and a resampled one is much harder to fuse.
    private let depth = Image(width: 960, height: 720, color: .black)

    override func draw() {
        background(Color(hex: 0x0A0C12))

        let phase = loopProgress(over: 16) * .tau
        paint(turn: phase)
        let relief = 0.06 + 0.22 * (1 - cos(phase)) / 2

        let frame = Rectangle(x: (width - 960) / 2, y: (height - 720) / 2,
                              width: 960, height: 720)
        if mouseIsPressed {
            drawImage(depth, in: frame, fit: .contain)
            drawCaption("the depth map: bright is near, and near is where the repeat shortens")
            return
        }

        drawAutostereogram(of: depth, in: frame,
                           settings: Autostereogram(repeatWidth: 108, relief: relief),
                           seed: 9)
        drawCaption("look through the picture until the pattern doubles up; "
            + "relief \(Int((relief * 100).rounded()))% of the repeat")
    }

    /// A turning ring of blocks over a tilted ground, painted as depth: white is
    /// near. Hard edges read best, since a soft edge has nothing for the eyes to
    /// lock onto.
    private func paint(turn: Double) {
        let w = depth.width, h = depth.height
        for y in 0 ..< h {
            for x in 0 ..< w {
                let u = (Double(x) + 0.5) / Double(w) * 2 - 1
                let v = (Double(y) + 0.5) / Double(h) * 2 - 1
                // A ground that leans away, so there is depth even off the shape.
                var level = 0.12 + 0.10 * (1 - (v * 0.5 + 0.5))

                // Six blocks on a ring, each standing at its own height.
                for i in 0 ..< 6 {
                    let angle = Double(i) / 6 * .tau + turn
                    let cx = 0.52 * cos(angle), cy = 0.42 * sin(angle)
                    let half = 0.15 + 0.05 * sin(Double(i) * 1.7)
                    if abs(u - cx) < half, abs(v - cy) < half * 1.2 {
                        level = 0.55 + 0.45 * (Double(i) / 5)
                    }
                }
                // And a plinth in the middle, so there is something with a flat top.
                if abs(u) < 0.22, abs(v) < 0.22 { level = 1 }

                depth[x, y] = Color(white: clamp(level, 0, 1))
            }
        }
    }
}
