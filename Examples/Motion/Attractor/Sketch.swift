//  Ported from @eaviles's sketch 2025.003. Reworked for Ollin's API.

import Foundation
import Ollin

/// A rotating de Jong–style attractor: a chaotic `(x, y)` recurrence whose state
/// carries over from one step to the next (and across frames), sampled into a
/// bloom of fine dots. The whole field spins with `time`, and each of the 512
/// spokes adds another turn, so the orbit smears into a soft radial flower.
///
/// This is the headline for `drawPoint`: ~98k dots a frame (512 × 191), each a
/// single SDF instance — per-point CPU work is one struct write. The dots are
/// small on purpose; the more of them, the denser and softer the bloom, and at
/// these sizes the disk fades by area so the field stays smooth rather than
/// aliasing into hard speckle.
@main
final class Attractor: Sketch {
    let pointCount = 512
    let iterations = 192

    // The recurrence state persists across frames (the orbit keeps evolving),
    // so it lives on the sketch, not in `draw()`.
    var x = 0.0
    var y = 0.0

    override func setup() {
        noStroke()
    }

    override func draw() {
        background(.black)
        fill(.white)
        pointSize(3 * scale)

        translate(center)
        let t = time * 0.002
        rotate(t * 1000 * .pi / 180)        // a slow overall spin

        let step = Double.tau / Double(pointCount)
        let reach = 200 * scale
        for n in 0..<pointCount {
            rotate(step)                    // one more turn per spoke
            let nn = Double(n)
            for _ in 1..<iterations {
                let a = sin(.tau * t + nn - y) + cos(.tau * t + .tau * nn / 100 - x)
                let b = cos(.tau * t + nn + y) + sin(.tau * t + .tau * nn / 100 + x)
                x = a
                y = b
                drawPoint(reach * x, reach * y)
            }
        }
    }
}
