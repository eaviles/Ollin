//  Recreation after Jared Tarbell, "Substrate" (2003), complexification.net:
//  cracks race across the plane, stop where they meet an older line, restart
//  perpendicular to a point on the existing pattern, and shade the open space
//  beside themselves with a translucent sand-grain wash. An original Ollin
//  interpretation built from the artwork and its published description, not
//  ported from the source. A homage, not a reproduction, and not affiliated
//  with or endorsed by the artist.

import Ollin

/// City blocks grown from colliding cracks, after Jared Tarbell's "Substrate".
///
/// `CrackGrowth` carries the whole technique: every crack writes its angle
/// into a raster grid, stops where it reads someone else's angle, restarts
/// perpendicular to a random claimed cell, and recruits one more crack. The
/// homage lives in the surface: a white ground, near-black grainy lines, and
/// a wash palette in the spirit of the hundred colors the original sampled
/// from a painting. Click to grow a fresh city from the next seed.
@main
final class Substrate: Sketch {
    /// Ticks per frame: how fast the city grows.
    @Param(1...12) var speed = 6.0

    /// Sands, ochres, rusts, olives, and slates; one per crack for its whole
    /// life, so a long line keeps its color through every restart.
    private let washes = Palette(
        Color(hex: 0xD9C9A5), Color(hex: 0xC7A26B), Color(hex: 0xA8763E),
        Color(hex: 0x8C5A33), Color(hex: 0x9E3B33), Color(hex: 0xB0413E),
        Color(hex: 0x704A41), Color(hex: 0x99856B), Color(hex: 0x7A6A53),
        Color(hex: 0x9C9A5E), Color(hex: 0x6B7F59), Color(hex: 0x51604F),
        Color(hex: 0x5C6E74), Color(hex: 0x41586B), Color(hex: 0xB89F80),
        Color(hex: 0x3F3F3B))

    private var field: CrackGrowth!
    private var citySeed = 3
    private var needsGround = true

    override func setup() {
        noClear()
        noStroke()
        regrow()
    }

    override func draw() {
        if needsGround {
            background(.white)
            needsGround = false
        }

        for mark in field.step(Int(speed)) {
            // The sand wash: translucent grains crowding the crack's side,
            // reaching only as far as the open space beside the line.
            let wash = washes[mark.crack % washes.count]
            for grain in CrackGrowth.grains(from: mark.point, to: mark.washExtent,
                                            gain: mark.gain) {
                fill(wash.withAlpha(grain.alpha))
                drawPoint(grain.position)
            }

            // The crack: a faint dark point with sub-pixel shiver, so the
            // line accumulates grainy rather than ruled.
            fill(Color.black.withAlpha(0.33))
            drawPoint(mark.point.x + random(-0.33, 0.33),
                      mark.point.y + random(-0.33, 0.33))
        }
    }

    /// A click clears the plane and grows a fresh city from the next seed.
    override func mousePressed() {
        citySeed += 1
        regrow()
    }

    private func regrow() {
        seed(citySeed)
        field = CrackGrowth(width: width, height: height, seed: UInt64(citySeed))
        needsGround = true
    }
}
