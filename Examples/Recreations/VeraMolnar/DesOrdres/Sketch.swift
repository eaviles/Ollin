//  Recreation after Vera Molnár — "(Dés)Ordres" (1974), her plotter drawing of
//  concentric squares randomly disrupted; a pun on "désordres" (disorders) and
//  "des ordres" (some orders). A homage, not a reproduction.
//  https://dam.org/museum/artists_ui/artists/molnar-vera/des-ordres/
//
//  Ported from the p5.js sketch week-1/vera-2 (MIT) in
//  https://github.com/eaviles/rtp-sfpc-f21-p5 — itself a p5 port of Zach
//  Lieberman's openFrameworks sample for the RTP class at SFPC, Fall 2021
//  (https://github.com/ofZach/RTP_SFPC_F21). Reworked for Ollin's API.

import Ollin

/// "(Dés)Ordres" (Vera Molnár, 1974): a 5×5 grid of cells, each a stack of 10
/// concentric squares — but each square is drawn only ~95% of the time, so the
/// orderly nesting frays into gaps. The title's pun (disorders / some orders)
/// is the idea: an underlying logic within the apparent disarray. **Move the
/// mouse**: `mouseX` seeds the randomness, so sliding it scrubs the disorder.
///
/// Demonstrates center-anchored `rect(center:width:height:)` and `randomSeed`
/// driven by input. After Vera Molnár.
@main
final class DesOrdres: Sketch {
    override func setup() {
        strokeWeight(2 * scale)
        noFill()
    }

    override func draw() {
        background(.white)
        randomSeed(Int(mouseX))   // the pattern is stable per mouseX, scrubs as you move

        // A 5×5 grid of centers inset ⅛ from each edge; each holds 10 nested
        // squares, the outermost nearly filling its cell. All canvas-relative.
        let side = min(width, height)
        let lo = side * 0.125, hi = side * 0.875
        let cell = (hi - lo) / 4
        for i in 0..<5 {
            for j in 0..<5 {
                let center = Vector2(map(Double(i), 0, 4, lo, hi),
                                     map(Double(j), 0, 4, lo, hi))
                for k in 0..<10 {
                    let size = map(Double(k), 0, 9, cell * 0.04, cell * 0.95)
                    if random() < 0.95 {
                        rect(center: center, width: size, height: size)
                    }
                }
            }
        }
    }
}
