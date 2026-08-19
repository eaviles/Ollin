import Foundation
import Ollin

/// The 1€ filter cleans up a noisy live signal — staying responsive when it moves
/// fast and steady when it crawls, which a fixed low-pass can't manage at both
/// ends. `@Smoothed` is the sugar: assign the raw value every frame, read a clean
/// one. It's the denoising counterpart to `@Eased` (which glides toward a target
/// you already know).
///
/// Here a target sweeps a slow figure-eight with a burst of jitter shaken on top
/// each frame — a stand-in for a shaky sensor or mouse. The faint gray dots are
/// the raw signal; the blue trail and black head are the smoothed `Vector2`,
/// gliding through the noise.
@main
final class Smoothing: Sketch {
    @Smoothed(beta: 0.01) var smooth = Vector2.zero

    var rawTrail: [Vector2] = []
    var smoothTrail: [Vector2] = []
    let keep = 150

    override func setup() {
        seed(11)                                     // deterministic jitter
    }

    override func draw() {
        background(.white)

        // A smooth underlying motion (a Lissajous figure-eight) plus jitter.
        let t = time * 0.9
        let base = Vector2(width * (0.5 + 0.30 * sin(t)),
                           height * (0.5 + 0.30 * sin(t * 2)))
        let raw = base + ring(innerRadius: 0, outerRadius: 28 * scale)
        smooth = raw                                 // feed raw, read smoothed

        rawTrail.append(raw); smoothTrail.append(smooth)
        if rawTrail.count > keep { rawTrail.removeFirst() }
        if smoothTrail.count > keep { smoothTrail.removeFirst() }

        // Raw signal: faint scattered dots.
        noStroke(); fill(Color(white: 0.82))
        for q in rawTrail { drawCircle(center: q, radius: 4 * scale) }

        // Smoothed signal: a trail fading in toward a bold head.
        for (i, q) in smoothTrail.enumerated() {
            let a = Double(i) / Double(keep)
            fill(Color(red: 0.1, green: 0.2, blue: 0.95, alpha: a))
            drawCircle(center: q, radius: 6 * scale)
        }
        fill(.black); drawCircle(center: smooth, radius: 14 * scale)
    }
}
