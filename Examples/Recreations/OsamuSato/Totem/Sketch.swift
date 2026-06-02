//  Recreation after Osamu Sato — "The Art of Computer Designing: A Black and
//  White Approach" (1993, Graphic-Sha), a book of designs built entirely from
//  basic vector shapes. This is a homage to the totemic figures of its Chapter 4
//  ("Circles"), where a deity is assembled from circles, crescents, and eyes in
//  bold black with a single red accent. An original Ollin interpretation built
//  from the book's vocabulary — not ported from its disk. A homage, not a
//  reproduction, and not affiliated with or endorsed by the artist.

import Foundation
import Ollin

/// A symmetric "computer totem" after Osamu Sato — the whole figure is assembled
/// from Ollin's analytic SDF primitives, leaning on the newer novelty shapes as
/// totem parts: a `horseshoe` crown and ears, a `parabola` finial cap, a
/// `tunnel` torso, a `blobbyCross` heart, a `roundedX` brow, `coolS` arm
/// ornaments, tapered `unevenCapsule` legs, and a `stairs` pedestal — around the
/// core `circle`/`ring`/`moon`/`triangle` set.
///
/// Sato's prints are still; Ollin's default is motion, so the totem comes alive:
/// it *breathes* (a slow scale pulse), its eyes pulse, and its bead-chain arms
/// lift and *wave*. Everything is mirrored about the vertical axis — the left and
/// right halves are drawn once and reflected — so it waves with both arms at once
/// and stays symmetric. Tune the motion with the `breath` / `gaze` / `wave` knobs.
@main
final class Totem: Sketch {
    @Param(0...1) var breath = 0.5     // how much the figure breathes
    @Param(0...1) var gaze = 0.5       // how much the eyes pulse
    @Param(0...1) var wave = 0.7       // how big the arms' wave is

    /// Sato's accent — a warm scarlet against black and white.
    let sato = Color(red: 0.85, green: 0.09, blue: 0.16)
    let ink = Color.black

    override func setup() {
        noStroke()
    }

    override func draw() {
        background(Color(white: 0.96))
        let s = scale
        let cx = width / 2
        let cy = height / 2
        // Local length unit: canvas-relative, so the totem holds at any size.
        func u(_ v: Double) -> Double { v * s }

        // Breathe about the figure's center.
        let pulse = 1 + 0.02 * breath * sin(time * 1.4)

        withState {
            translate(cx, cy)
            scale(pulse, pulse)
            // From here the origin is the figure center; +x right, +y down. Y runs
            // roughly -430 (crown) … +430 (pedestal).

            pedestal(u)
            legs(u)
            torso(u)
            arms(u)
            crown(u)
            head(u)
        }
    }

    // MARK: Parts (top to bottom in the figure; drawn back-to-front)

    /// The crown: a wide red crescent opening up, finial eye on a bead stalk above
    /// it, and a small black horseshoe "ear" on each side.
    private func crown(_ u: (Double) -> Double) {
        // Horseshoe ears, flanking the head, opening outward.
        fill(ink)
        for side in [-1.0, 1.0] {
            withState {
                translate(side * u(208), u(-250))
                rotate(side * .pi / 2)        // open toward the sides
                drawHorseshoe(0, 0, u(46), u(30), gap: 1.5)
            }
        }

        // Red crescent crown (concave side up), with dot horns and a center eye.
        fill(sato)
        withState {
            translate(0, u(-300))
            rotate(-.pi / 2)                  // moon opens +x by default → rotate up
            drawMoon(0, 0, u(150), u(140), u(58))
        }
        for side in [-1.0, 1.0] { drawCircle(side * u(132), u(-322), u(26)) }
        eye(u, 0, -262, 34, red: true)

        // Finial: a little parabola cap over an eye on a short bead stalk.
        fill(ink)
        beadColumn(u, x: 0, y0: -360, y1: -402, count: 3, r: 9)
        eye(u, 0, -420, 16)
        fill(sato)
        drawParabola(u(0), u(-446), u(46), u(30))
    }

    /// The face: a three-eyed mask — two black eyes flanking a red rounded-X
    /// "third eye".
    private func head(_ u: (Double) -> Double) {
        let p = 1 + 0.12 * gaze * sin(time * 2.0)   // eye pulse
        for side in [-1.0, 1.0] { eye(u, side * 78, -130, 38 * p) }
        fill(sato)
        drawRoundedX(u(0), u(-130), u(46), u(15))
    }

    /// The torso: a bold black tunnel (archway) body with a red blobby-cross heart,
    /// joined to the head by a short bead neck.
    private func torso(_ u: (Double) -> Double) {
        fill(ink)
        beadColumn(u, x: 0, y0: -40, y1: 8, count: 3, r: 13)
        drawTunnel(u(0), u(70), u(240), u(300))
        fill(sato)
        drawBlobbyCross(u(0), u(60), u(52))
        // Cool-S ornaments, cut in white inside the torso below the heart (mirrored).
        fill(.white)
        for side in [-1.0, 1.0] {
            withState {
                translate(side * u(58), u(140))
                scale(side, 1)                // mirror the asymmetric S
                drawCoolS(0, 0, u(66))
            }
        }
    }

    /// Arms: each one a bead chain raised from the shoulder that *waves* — the
    /// forearm sweeps from the elbow on a loop, ending in a ring "hand". Both arms
    /// move in mirror, so the figure stays symmetric.
    private func arms(_ u: (Double) -> Double) {
        fill(ink)
        // Forearm angle from straight up, swinging side to side over time.
        let theta = 0.3 + 0.6 * wave * sin(time * 3.0)
        let reach = 120.0
        for side in [-1.0, 1.0] {
            let shoulder = Vector2(side * 96, -30)
            let elbow = Vector2(side * 232, -40)          // raised out to the side
            let hand = Vector2(elbow.x + side * reach * sin(theta),
                               elbow.y - reach * cos(theta))
            wavingArm(u, shoulder: shoulder, elbow: elbow, hand: hand)
            eye(u, hand.x, hand.y, 28)
        }
    }

    /// Beads along the quadratic curve shoulder → elbow → hand, a ripple traveling
    /// down the chain and the radius easing from a fat shoulder to a slim wrist.
    private func wavingArm(_ u: (Double) -> Double, shoulder: Vector2, elbow: Vector2, hand: Vector2) {
        let count = 7
        for i in 0...count {
            let t = Double(i) / Double(count)
            let mt = 1 - t
            let p = shoulder * (mt * mt) + elbow * (2 * mt * t) + hand * (t * t)
            let shimmer = 1 + 0.1 * sin(time * 4 + t * 7)
            let r = (22 + (12 - 22) * t) * shimmer
            drawCircle(u(p.x), u(p.y), u(r))
        }
    }

    /// Legs: tapered capsules from the hips to ring "feet".
    private func legs(_ u: (Double) -> Double) {
        fill(ink)
        for side in [-1.0, 1.0] {
            drawUnevenCapsule(Vector2(side * u(70), u(210)),
                              Vector2(side * u(120), u(372)), u(40), u(26))
            eye(u, side * 120, 380, 46)
        }
    }

    /// A stepped pyramid pedestal: a staircase ascending toward the center on each
    /// side (mirrored), so they meet in a peak.
    private func pedestal(_ u: (Double) -> Double) {
        fill(ink)
        for side in [-1.0, 1.0] {
            withState {
                translate(0, u(404))
                scale(side, 1)
                drawStairs(u(-68), 0, u(34), u(22), steps: 4)   // meet flush at center
            }
        }
    }

    // MARK: Building blocks

    /// A concentric "Sato eye": filled disk, white iris, ink pupil.
    private func eye(_ u: (Double) -> Double, _ dx: Double, _ dy: Double, _ r: Double, red: Bool = false) {
        fill(red ? sato : ink); drawCircle(u(dx), u(dy), u(r))
        fill(.white);           drawCircle(u(dx), u(dy), u(r * 0.55))
        fill(ink);              drawCircle(u(dx), u(dy), u(r * 0.24))
    }

    /// A vertical stack of equal dots (a bead "stalk").
    private func beadColumn(_ u: (Double) -> Double, x: Double, y0: Double, y1: Double, count: Int, r: Double) {
        for i in 0..<count {
            let t = count > 1 ? Double(i) / Double(count - 1) : 0
            drawCircle(u(x), u(y0 + (y1 - y0) * t), u(r))
        }
    }

}
