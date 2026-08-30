import Ollin

//  Inspired by "Substrate" by Jared Tarbell (2003), complexification.net.
//  Original interpretation of the technique; no source code ported.

/// Crack growth: straight cracks race across the canvas, each recording its
/// angle into a raster grid. A crack that meets an older line stops, restarts
/// perpendicular to a random point on the existing pattern, and recruits one
/// more crack, so the plane subdivides into city-block cells. Each crack drags
/// a translucent one-sided wash across the open space beside it, so the cells
/// fill with watercolor as the map densifies.
///
/// The canvas never clears (`noClear()`): every frame lays only this frame's
/// marks, and the picture is the accumulation. The same seed always grows the
/// same city; `field.segments` is the whole street plan as plain line
/// segments, ready for the vector exports and the pen plotter.
@main
final class Cracks: Sketch {
    private let inks = [Color(hex: 0x1F5673), Color(hex: 0xC26D3F),
                        Color(hex: 0x8A9B68), Color(hex: 0x71486E),
                        Color(hex: 0xC7A94F), Color(hex: 0x9A4A4A),
                        Color(hex: 0x3E7C66)]
    private var field: CrackGrowth!

    override func setup() {
        noClear()
        seed(7)
        noStroke()
        field = CrackGrowth(width: width, height: height, seed: 7)
    }

    override func draw() {
        if frameCount == 1 { background(Color(hex: 0xF7F3EA)) }

        for mark in field.step(4) {
            // The wash: translucent grains crowding the crack, one ink per
            // crack for its whole life.
            let ink = inks[mark.crack % inks.count]
            for grain in CrackGrowth.grains(from: mark.point, to: mark.washExtent,
                                            gain: mark.gain) {
                fill(ink.withAlpha(grain.alpha))
                drawPoint(at: grain.position)
            }

            // The crack itself: a faint dark point with sub-pixel shiver, so
            // the line builds up grainy rather than ruled.
            fill(Color.black.withAlpha(0.33))
            drawPoint(mark.point.x + random(-0.33, 0.33),
                      mark.point.y + random(-0.33, 0.33))
        }
    }
}
