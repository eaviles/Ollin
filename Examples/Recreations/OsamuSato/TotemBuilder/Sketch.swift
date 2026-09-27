//  Recreation after Osamu Sato - "The Art of Computer Designing: A Black and
//  White Approach" (1993, Graphic-Sha), Chapter 4, "Circles", read from the
//  scan of the book on the Internet Archive: the chapter's opening figure,
//  captioned "This picture was created with circles" (page 59), its pieces
//  laid out one by one (pages 60 and 61: hand, foot and tail, eye, antenna and
//  nose, mouth, neck, ear, face, body), and the three lessons that build them
//  (pages 62 to 67: dividing and combining, symmetry, rotation). A homage,
//  not a reproduction, and not affiliated with or endorsed by the artist.
//  https://archive.org/details/satoArtOfComputerDesigning
//
//  An original Ollin interpretation written from the printed pages. The
//  variants of each piece, their proportions, and the way they are dealt are
//  our own. Nothing was ported: the book shipped a disk of its designs, and
//  none of it was used.

import Foundation
import Ollin

/// "A monster made of a circle" (Osamu Sato, *The Art of Computer Designing*,
/// 1993, Chapter 4). The chapter takes its opening figure apart piece by
/// piece and shows how each one is made from nothing but circles, by one of
/// three moves. A hand, a foot, a tail, and an eye come from dividing circles
/// and combining them: a disk cut by another disk leaves a crescent, and two
/// disks that overlap leave a lens. An antenna, a nose, a mouth, and a neck
/// come from symmetry: half a piece is built and mirrored. An ear, a face,
/// and a body come from rotation: one circle is copied around another. The
/// captions tell the monster's story. "The gaping mouth in his stomach is
/// always hungry for food." And the program that makes his circles "can be
/// rotated to create the shape over and over, resulting in a monster who is
/// hungry his entire body over."
///
/// This sketch builds a new monster from those pieces for every seed. Each
/// piece has a few forms, all made the chapter's way, and the seed deals one
/// of each, with the counts of the rotated circles and the proportions of
/// head, neck, and body. Every mark is a disk, a ring, a crescent (a disk
/// with a disk cut out of it), or a lens (the overlap of two disks), in black
/// or the paper's white, and at most one piece is red. Everything but the
/// tail is built on the right and mirrored to the left. The tail, when there
/// is one, hangs from the middle, the one piece the chapter leaves
/// unmirrored.
///
/// The monster is still hungry. A pulse runs down the circles around his
/// face and body from top to bottom, on both sides at once. He blinks, his
/// hands wave together, his antenna bobs, and his mouth chews. `motion` is
/// how much of that there is (0 holds him still for a print), and the seed is
/// the monster. Proof a day's pile with `--export-grid`.
@main
final class TotemBuilder: Sketch {
    @Param(0 ... 1, icon: "waveform.path") var motion = 0.6

    override var canvasSize: CanvasSize { .size(1000, 1250) }

    private let paper = Color(white: 0.955)
    private let ink = Color(white: 0.06)
    private let red = Color(red: 0.85, green: 0.09, blue: 0.16)

    // MARK: Marks

    /// The only shapes a piece is made of.
    private enum Form {
        case disk(radius: Double)
        case ring(inner: Double, outer: Double)
        /// A disk with a disk cut out of it, the cut toward `angle`.
        case crescent(outer: Double, inner: Double, offset: Double, angle: Double)
        /// The overlap of two equal disks, its tips along `angle`.
        case lens(length: Double, width: Double, angle: Double)
    }

    private enum Ink { case ink, paper, accent }

    private struct Mark {
        var shape: Form
        var center: Vector2
        var ink: Ink

        /// The same mark reflected across the monster's axis.
        var mirrored: Mark {
            var m = self
            m.center = Vector2(-center.x, center.y)
            switch shape {
            case let .crescent(outer, inner, offset, angle):
                m.shape = .crescent(outer: outer, inner: inner, offset: offset, angle: .pi - angle)
            case let .lens(length, width, angle):
                m.shape = .lens(length: length, width: width, angle: .pi - angle)
            case .disk, .ring:
                break
            }
            return m
        }

        var reach: Double {
            switch shape {
            case let .disk(r): return r
            case let .ring(_, outer): return outer
            case let .crescent(outer, _, _, _): return outer
            case let .lens(length, width, _): return max(length, width) / 2
            }
        }
    }

    // MARK: The dealt monster

    /// One monster: a form for every piece, and its proportions.
    private struct Plan {
        var headRadius = 0.7
        var neckLength = 0.2
        var face = 0, faceBeads = 18
        var eyes = 0, nose = 0, ears = 0, antenna = 0, neck = 0
        var body = 0, bodyBumps = 10, bodyBeads = 12, bumpsOffset = false
        var mouth = 0, hands = 0, feet = 0
        var hasTail = false, tailCurlsRight = true
        var shoulder = 1.2      // where the arms leave the body, from the top
        var hip = 2.5           // where the feet sit, from the top
        var accent = 0          // 0 none, then eyes, nose, antenna, mouth, hands, ears
    }

    private var plan = Plan()

    override func setup() {
        noStroke()
        var p = Plan()
        p.headRadius = random(0.6, 0.84)
        p.neckLength = random(0.14, 0.32)
        p.face = Int(random(2))
        p.faceBeads = [14, 18, 22, 26][Int(random(4))]
        p.eyes = Int(random(3))
        p.nose = Int(random(3))
        p.ears = Int(random(3))
        p.antenna = Int(random(3))
        p.neck = Int(random(2))
        p.body = Int(random(2))
        p.bodyBumps = [6, 8, 10, 12][Int(random(4))]
        p.bodyBeads = [10, 12, 14, 16][Int(random(4))]
        p.bumpsOffset = random(1) < 0.5
        p.mouth = Int(random(3))
        p.hands = Int(random(2))
        p.feet = Int(random(2))
        p.hasTail = random(1) < 0.6
        p.tailCurlsRight = random(1) < 0.5
        p.shoulder = random(1.05, 1.45)
        p.hip = random(2.35, 2.7)
        p.accent = Int(random(7))
        plan = p
    }

    override func draw() {
        background(paper)
        let rest = marks(at: 0, amount: 0)
        // Fit the monster at rest to the page, the axis on the page's middle.
        var halfWidth = 0.0, top = Double.infinity, bottom = -Double.infinity
        for m in rest {
            halfWidth = max(halfWidth, abs(m.center.x) + m.reach)
            top = min(top, m.center.y - m.reach)
            bottom = max(bottom, m.center.y + m.reach)
        }
        let fit = min(width * 0.8 / (2 * halfWidth), height * 0.84 / (bottom - top))
        let origin = Vector2(width / 2, height / 2 - fit * (top + bottom) / 2)
        let breathe = 1 + 0.012 * motion * sin(time * 1.3)

        for m in marks(at: time, amount: motion) {
            switch m.ink {
            case .ink: fill(ink)
            case .paper: fill(paper)
            case .accent: fill(red)
            }
            let c = origin + m.center * (fit * breathe)
            let s = fit * breathe
            switch m.shape {
            case let .disk(r):
                drawCircle(c.x, c.y, r * s)
            case let .ring(inner, outer):
                drawRing(c.x, c.y, inner * s, outer * s)
            case let .crescent(outer, inner, offset, angle):
                withState {
                    translate(c.x, c.y)
                    rotate(angle)
                    drawMoon(0, 0, outer * s, inner * s, offset * s)
                }
            case let .lens(length, width, angle):
                withState {
                    translate(c.x, c.y)
                    rotate(angle)
                    drawVesica(0, 0, length * s, width * s)
                }
            }
        }
    }

    // MARK: Building the monster

    /// Every mark of the monster at time `t`, in body units (the body's
    /// radius is 1, its center the origin, y down), back to front. `amount`
    /// scales every motion; at 0 he stands still.
    private func marks(at t: Double, amount: Double) -> [Mark] {
        let p = plan
        var out: [Mark] = []
        /// A piece built on the right and mirrored to the left.
        func pair(_ build: () -> [Mark]) {
            let right = build()
            out += right
            out += right.map(\.mirrored)
        }
        /// A piece on the axis, symmetric by construction.
        func middle(_ build: () -> [Mark]) { out += build() }
        func ink(for piece: Int) -> Ink { p.accent == piece ? .accent : .ink }

        let headY = -(1 + p.neckLength + p.headRadius)
        let hr = p.headRadius
        let blink = amount * blinkAmount(at: t)
        let wave = amount * sin(t * 2.6)
        let bob = amount * sin(t * 3.1)
        let chew = amount * max(0, sin(t * 4.2))

        // The tail, drawn first so the body covers its root.
        if p.hasTail {
            let side = p.tailCurlsRight ? 1.0 : -1.0
            let sway = 0.12 * amount * sin(t * 1.7)
            out += [
                Mark(shape: .crescent(outer: 0.2, inner: 0.19, offset: 0.1, angle: side > 0 ? .pi + sway : sway),
                     center: Vector2(side * 0.08, 1.12), ink: .ink),
                Mark(shape: .crescent(outer: 0.19, inner: 0.18, offset: 0.1, angle: side > 0 ? sway : .pi + sway),
                     center: Vector2(side * -0.04, 1.43), ink: .ink),
                Mark(shape: .disk(radius: 0.075), center: Vector2(side * 0.1, 1.6), ink: .ink),
            ]
        }

        // The feet.
        let hipPoint = Vector2(sin(p.hip), -cos(p.hip)) * 0.96
        pair {
            switch p.feet {
            case 0:
                // A crescent opening up and out, a ball at its toe.
                return [
                    Mark(shape: .crescent(outer: 0.26, inner: 0.24, offset: 0.12, angle: -.pi / 3),
                         center: hipPoint + Vector2(0.08, 0.14), ink: .ink),
                    Mark(shape: .disk(radius: 0.09), center: hipPoint + Vector2(0.3, 0.1), ink: .ink),
                ]
            default:
                // A disk with three toes.
                let foot = hipPoint + Vector2(0.06, 0.18)
                return [Mark(shape: .disk(radius: 0.2), center: foot, ink: .ink)] + (0 ..< 3).map { i in
                    let a = 0.35 + Double(i) * 0.5
                    return Mark(shape: .disk(radius: 0.055), center: foot + Vector2(cos(a), sin(a)) * 0.24, ink: .ink)
                }
            }
        }

        // The hands, raised from the shoulders and waving together.
        let shoulderPoint = Vector2(sin(p.shoulder), -cos(p.shoulder))
        pair {
            let lift = 0.25 * wave
            let knuckle = shoulderPoint * 1.32 + Vector2(0.18, -0.28 - 0.08 * wave)
            var hand: [Mark]
            switch p.hands {
            case 0:
                // A crescent swept up from the shoulder, a knuckle, three bead fingers.
                hand = [
                    Mark(shape: .crescent(outer: 0.36, inner: 0.34, offset: 0.17, angle: -2.4 + lift),
                         center: shoulderPoint * 1.18 + Vector2(0.02, -0.04), ink: ink(for: 5)),
                    Mark(shape: .disk(radius: 0.1), center: knuckle, ink: ink(for: 5)),
                ]
            default:
                // Two crescents closing like a claw on a knuckle.
                hand = [
                    Mark(shape: .crescent(outer: 0.26, inner: 0.25, offset: 0.12, angle: -2.2 + lift),
                         center: knuckle + Vector2(-0.12, 0.2), ink: ink(for: 5)),
                    Mark(shape: .crescent(outer: 0.22, inner: 0.21, offset: 0.1, angle: 2.6 + lift),
                         center: knuckle + Vector2(0.14, 0.02), ink: ink(for: 5)),
                    Mark(shape: .disk(radius: 0.09), center: knuckle, ink: ink(for: 5)),
                ]
            }
            for f in 0 ..< 3 {
                let a = -1.9 + Double(f) * 0.62 + 0.18 * wave
                for b in 1 ... 4 {
                    let at = knuckle + Vector2(cos(a), sin(a)) * (0.07 + Double(b) * 0.075)
                    hand.append(Mark(shape: .disk(radius: 0.042 - Double(b) * 0.004), center: at, ink: ink(for: 5)))
                }
            }
            return hand
        }

        // The body: a disk whose circles are copied around it by rotation.
        middle { body(p, t: t, amount: amount, chew: chew) }

        // The neck: a stem of circles, and what the chapter's neck hangs on it.
        let neckTop = -(1 + p.neckLength) - 0.1, neckBottom = -0.9
        middle {
            (0 ..< 4).map { i in
                let y = neckBottom + (neckTop - neckBottom) * Double(i) / 3
                return Mark(shape: .disk(radius: 0.13), center: Vector2(0, y), ink: .ink)
            }
        }
        let neckY = -(1 + p.neckLength / 2)
        if p.neck == 0 {
            pair {
                [
                    Mark(shape: .disk(radius: 0.12), center: Vector2(0.1, neckY), ink: .ink),
                    Mark(shape: .disk(radius: 0.04), center: Vector2(0.1, neckY), ink: .paper),
                    Mark(shape: .crescent(outer: 0.1, inner: 0.09, offset: 0.06, angle: 0),
                         center: Vector2(0.33, neckY), ink: .ink),
                    Mark(shape: .ring(inner: 0.02, outer: 0.045), center: Vector2(0.31, neckY), ink: .ink),
                ] + (1 ... 3).map { i in
                    Mark(shape: .disk(radius: 0.03 - Double(i) * 0.005),
                         center: Vector2(0.4 + Double(i) * 0.07, neckY), ink: .ink)
                }
            }
        } else {
            pair {
                (1 ... 3).map { i in
                    Mark(shape: .disk(radius: 0.05 - Double(i) * 0.008),
                         center: Vector2(0.16 + Double(i) * 0.1, neckY), ink: .ink)
                }
            }
        }

        // The ears, behind the head.
        pair { ears(p, headY: headY, amount: amount, t: t) }

        // The face: the head's disk or ring, its rotated beads, its window.
        middle { face(p, headY: headY, t: t, amount: amount) }

        // The eyes.
        let onInk = p.face == 0
        let eyeCenter = onInk ? Vector2(0.76 * hr, headY) : Vector2(0.27 * hr, headY - 0.1 * hr)
        let eyeScale = onInk ? 1.2 : 1.1
        pair { eye(p, at: eyeCenter, scale: eyeScale * hr, onInk: onInk, blink: blink) }

        // The nose, on the axis inside the window.
        middle { nose(p, at: Vector2(0, headY + (onInk ? 0.04 : 0.24) * hr), scale: (onInk ? 1.6 : 1.1) * hr) }

        // The antenna, on top of the head.
        middle { antenna(p, top: headY - hr * 1.08, scale: hr, bob: bob) }

        return out
    }

    /// Once every few seconds the eyes close for a moment.
    private func blinkAmount(at t: Double) -> Double {
        let u = (t / 4.7).truncatingRemainder(dividingBy: 1)
        return u > 0.94 ? sin((u - 0.94) / 0.06 * .pi) : 0
    }

    /// The pulse that runs down both sides at once: 0 at rest, up to 1.
    private func pulse(fromTop angle: Double, t: Double, amount: Double) -> Double {
        amount * max(0, sin(t * 3.4 - 2.2 * abs(angle)))
    }

    /// The body: rim bumps, the disk, its ring of beads, and the window with
    /// the mouth in it.
    private func body(_ p: Plan, t: Double, amount: Double, chew: Double) -> [Mark] {
        var m: [Mark] = []
        let bumps = p.bodyBumps
        let start = p.bumpsOffset ? Double.pi / Double(bumps) : 0
        for i in 0 ..< bumps {
            let a = start + 2 * Double.pi * Double(i) / Double(bumps)
            let folded = min(a, 2 * .pi - a)
            let r = 0.1 * (1 + 0.25 * pulse(fromTop: folded, t: t, amount: amount))
            m.append(Mark(shape: .disk(radius: r), center: Vector2(sin(a), -cos(a)) * 1.0, ink: .ink))
        }
        m.append(Mark(shape: .disk(radius: 1), center: .zero, ink: .ink))
        let beads = p.bodyBeads
        let window: Double
        if p.body == 0 {
            // White rings, each with a black dot, copied around.
            for i in 0 ..< beads {
                let a = 2 * Double.pi * Double(i) / Double(beads)
                let folded = min(a, 2 * .pi - a)
                let grow = 1 + 0.2 * pulse(fromTop: folded, t: t, amount: amount)
                let c = Vector2(sin(a), -cos(a)) * 0.76
                m.append(Mark(shape: .disk(radius: 0.085 * grow), center: c, ink: .paper))
                m.append(Mark(shape: .disk(radius: 0.038 * grow), center: c, ink: .ink))
            }
            window = 0.56
        } else {
            // A white band, and a ring of white dots outside it.
            for i in 0 ..< beads {
                let a = 2 * Double.pi * Double(i) / Double(beads)
                let folded = min(a, 2 * .pi - a)
                let grow = 1 + 0.25 * pulse(fromTop: folded, t: t, amount: amount)
                m.append(Mark(shape: .disk(radius: 0.06 * grow), center: Vector2(sin(a), -cos(a)) * 0.82, ink: .paper))
            }
            m.append(Mark(shape: .ring(inner: 0.6, outer: 0.66), center: .zero, ink: .paper))
            window = 0.52
        }
        m.append(Mark(shape: .disk(radius: window), center: .zero, ink: .paper))
        m += mouth(p, window: window, chew: chew)
        return m
    }

    /// The mouth in the stomach.
    private func mouth(_ p: Plan, window w: Double, chew: Double) -> [Mark] {
        let color: Ink = p.accent == 4 ? .accent : .ink
        var m: [Mark] = []
        func both(_ mark: Mark) { m.append(mark); m.append(mark.mirrored) }
        switch p.mouth {
        case 0:
            // Crossed bones at the sides, an arch of beads, and a moustache
            // of two bowls with beads along their rims.
            let bone = Vector2(0.6 * w, -0.1 * w)
            both(Mark(shape: .disk(radius: 0.09 * w), center: bone, ink: color))
            for (dx, dy) in [(1.0, 1.0), (1.0, -1.0), (-1.0, 1.0), (-1.0, -1.0)] {
                both(Mark(shape: .disk(radius: 0.072 * w), center: bone + Vector2(dx, dy) * (0.14 * w), ink: color))
            }
            let dip = 0.07 * w * chew
            m.append(Mark(shape: .disk(radius: 0.11 * w), center: Vector2(0, -0.36 * w + dip), ink: color))
            for i in 1 ... 3 {
                let s = Double(i) / 3
                both(Mark(shape: .disk(radius: (0.11 - 0.012 * Double(i)) * w),
                          center: Vector2(0.13 * w * Double(i), (-0.36 + 0.15 * Double(i)) * w + dip * (1 - s)), ink: color))
            }
            both(Mark(shape: .crescent(outer: 0.3 * w, inner: 0.3 * w, offset: 0.15 * w, angle: -.pi / 2),
                      center: Vector2(0.28 * w, 0.42 * w), ink: color))
            for i in 0 ..< 4 {
                both(Mark(shape: .disk(radius: 0.055 * w),
                          center: Vector2(0.07 * w + Double(i) * 0.14 * w, 0.3 * w), ink: color))
            }
        case 1:
            // One gaping bowl, a bead at each corner.
            m.append(Mark(shape: .crescent(outer: 0.62 * w, inner: 0.6 * w, offset: 0.24 * w + 0.08 * w * chew,
                                           angle: -.pi / 2), center: Vector2(0, 0.06 * w), ink: color))
            both(Mark(shape: .disk(radius: 0.09 * w), center: Vector2(0.58 * w, -0.14 * w), ink: color))
        default:
            // A lens with an eye in it: the stomach looking back.
            m.append(Mark(shape: .lens(length: 1.3 * w, width: (0.52 - 0.2 * chew) * w, angle: 0),
                          center: .zero, ink: color))
            m.append(Mark(shape: .disk(radius: 0.17 * w), center: .zero, ink: .paper))
            m.append(Mark(shape: .disk(radius: 0.08 * w), center: .zero, ink: color))
            both(Mark(shape: .disk(radius: 0.07 * w), center: Vector2(0.76 * w, 0), ink: color))
        }
        return m
    }

    /// One ear, on the right of a head at `headY`.
    private func ears(_ p: Plan, headY: Double, amount: Double, t: Double) -> [Mark] {
        let hr = p.headRadius
        let color: Ink = p.accent == 6 ? .accent : .ink
        switch p.ears {
        case 0:
            // A disk with bumps copied around it, cut from the outside, three
            // dots in the cut.
            let c = Vector2(hr * 1.2, headY)
            var m: [Mark] = []
            for i in 0 ..< 7 {
                let a = Double.pi / 2 + Double(i) / 6 * .pi
                m.append(Mark(shape: .disk(radius: 0.07 * hr), center: c + Vector2(cos(a), sin(a)) * (0.34 * hr), ink: color))
            }
            m.append(Mark(shape: .crescent(outer: 0.36 * hr, inner: 0.3 * hr, offset: 0.28 * hr, angle: 0),
                          center: c, ink: color))
            for i in -1 ... 1 {
                m.append(Mark(shape: .disk(radius: 0.055 * hr),
                              center: c + Vector2(0.26 * hr, Double(i) * 0.16 * hr), ink: color))
            }
            return m
        case 1:
            // A crescent opening up and out, a dot in its bowl.
            let c = Vector2(hr * 1.14, headY - 0.3 * hr)
            let tilt = -Double.pi / 4 - 0.1 * amount * sin(t * 2.1)
            return [
                Mark(shape: .crescent(outer: 0.32 * hr, inner: 0.3 * hr, offset: 0.16 * hr, angle: tilt),
                     center: c, ink: color),
                Mark(shape: .disk(radius: 0.08 * hr), center: c + Vector2(cos(tilt), sin(tilt)) * (0.2 * hr), ink: color),
            ]
        default:
            return []
        }
    }

    /// The head: a black disk with beads around it and a white window, or a
    /// black ring with white-eyed beads around it.
    private func face(_ p: Plan, headY: Double, t: Double, amount: Double) -> [Mark] {
        let hr = p.headRadius
        let c = Vector2(0, headY)
        var m: [Mark] = []
        let n = p.faceBeads
        for i in 0 ..< n {
            let a = 2 * Double.pi * Double(i) / Double(n)
            let folded = min(a, 2 * .pi - a)
            let grow = 1 + 0.3 * pulse(fromTop: folded, t: t, amount: amount)
            let at = c + Vector2(sin(a), -cos(a)) * (hr * (p.face == 0 ? 1.1 : 1.0))
            m.append(Mark(shape: .disk(radius: 0.065 * hr * grow), center: at, ink: .ink))
            if p.face == 1 {
                m.append(Mark(shape: .disk(radius: 0.03 * hr * grow), center: at, ink: .paper))
            }
        }
        if p.face == 0 {
            m.append(Mark(shape: .disk(radius: hr), center: c, ink: .ink))
            m.append(Mark(shape: .disk(radius: 0.52 * hr), center: c, ink: .paper))
        } else {
            m.append(Mark(shape: .ring(inner: 0.56 * hr, outer: hr), center: c, ink: .ink))
            m.append(Mark(shape: .disk(radius: 0.09 * hr), center: c + Vector2(0, -1.13 * hr), ink: .ink))
        }
        return m
    }

    /// One eye, the right one. On a black ground it is drawn in the paper's
    /// white, on a white ground in black.
    private func eye(_ p: Plan, at c: Vector2, scale s: Double, onInk: Bool, blink: Double) -> [Mark] {
        let fore: Ink = p.accent == 1 ? .accent : (onInk ? .paper : .ink)
        let back: Ink = onInk ? .ink : .paper
        let open = 1 - 0.85 * blink
        switch p.eyes {
        case 0:
            // A lens with a white eye in it, a dot at each tip.
            return [
                Mark(shape: .lens(length: 0.36 * s, width: 0.17 * s * open, angle: 0), center: c, ink: fore),
                Mark(shape: .disk(radius: 0.058 * s * open), center: c, ink: back),
                Mark(shape: .disk(radius: 0.026 * s * open), center: c, ink: fore),
                Mark(shape: .disk(radius: 0.035 * s), center: c + Vector2(0.2 * s, 0), ink: fore),
                Mark(shape: .disk(radius: 0.035 * s), center: c - Vector2(0.2 * s, 0), ink: fore),
            ]
        case 1:
            // Three circles, one inside the next.
            return [
                Mark(shape: .disk(radius: 0.13 * s), center: c, ink: fore),
                Mark(shape: .disk(radius: 0.075 * s * open), center: c, ink: back),
                Mark(shape: .disk(radius: 0.034 * s), center: c, ink: fore),
            ]
        default:
            // A crescent facing the nose, a dot in its bowl.
            return [
                Mark(shape: .crescent(outer: 0.13 * s, inner: 0.12 * s, offset: 0.06 * s + 0.05 * s * blink,
                                      angle: .pi), center: c, ink: fore),
                Mark(shape: .disk(radius: 0.04 * s * open), center: c - Vector2(0.05 * s, 0), ink: fore),
            ]
        }
    }

    /// The nose, on the axis.
    private func nose(_ p: Plan, at c: Vector2, scale s: Double) -> [Mark] {
        let color: Ink = p.accent == 2 ? .accent : .ink
        switch p.nose {
        case 0:
            // A gourd of two circles between two crescents facing in.
            let side = Mark(shape: .crescent(outer: 0.11 * s, inner: 0.1 * s, offset: 0.055 * s, angle: 0),
                            center: c + Vector2(-0.24 * s, 0), ink: color)
            return [
                side, side.mirrored,
                Mark(shape: .disk(radius: 0.022 * s), center: c + Vector2(0, -0.16 * s), ink: color),
                Mark(shape: .disk(radius: 0.058 * s), center: c + Vector2(0, -0.07 * s), ink: color),
                Mark(shape: .disk(radius: 0.085 * s), center: c + Vector2(0, 0.06 * s), ink: color),
            ]
        case 1:
            // Beads falling in size.
            return (0 ..< 3).map { i in
                Mark(shape: .disk(radius: (0.035 + 0.022 * Double(i)) * s),
                     center: c + Vector2(0, (-0.14 + Double(i) * 0.11) * s), ink: color)
            }
        default:
            return [Mark(shape: .ring(inner: 0.045 * s, outer: 0.09 * s), center: c, ink: color)]
        }
    }

    /// The antenna, standing on `top`.
    private func antenna(_ p: Plan, top: Double, scale s: Double, bob: Double) -> [Mark] {
        let color: Ink = p.accent == 3 ? .accent : .ink
        var m: [Mark] = []
        func both(_ mark: Mark) { m.append(mark); m.append(mark.mirrored) }
        switch p.antenna {
        case 0:
            // A knob of circles with a row of dots out to each side.
            let s = s * 1.4
            let y = top - 0.1 * s
            m.append(Mark(shape: .disk(radius: 0.1 * s), center: Vector2(0, y), ink: color))
            m.append(Mark(shape: .disk(radius: 0.055 * s), center: Vector2(0, y - 0.13 * s), ink: color))
            m.append(Mark(shape: .disk(radius: 0.06 * s), center: Vector2(0, y + 0.12 * s), ink: color))
            both(Mark(shape: .crescent(outer: 0.09 * s, inner: 0.085 * s, offset: 0.045 * s, angle: .pi),
                      center: Vector2(0.14 * s, y), ink: color))
            for i in 0 ..< 4 {
                let x = (0.3 + Double(i) * 0.13) * s
                let lift = 0.04 * s * bob * Double(i + 1) / 4
                both(Mark(shape: .disk(radius: (0.045 - 0.004 * Double(i)) * s), center: Vector2(x, y - lift), ink: color))
            }
        case 1:
            // A stalk of beads, a ring on top.
            let lean = 0.03 * s * bob
            for i in 0 ..< 3 {
                m.append(Mark(shape: .disk(radius: (0.075 - 0.015 * Double(i)) * s),
                              center: Vector2(0, top - (0.04 + Double(i) * 0.12) * s - lean * Double(i)), ink: color))
            }
            m.append(Mark(shape: .ring(inner: 0.06 * s, outer: 0.12 * s), center: Vector2(0, top - 0.52 * s - 2 * lean), ink: color))
        default:
            // A crown: a crescent opening up, a dot on each horn, an eye in the bowl.
            let c = Vector2(0, top - 0.24 * s)
            m.append(Mark(shape: .crescent(outer: 0.48 * s, inner: 0.46 * s, offset: 0.2 * s, angle: -.pi / 2),
                          center: c, ink: color))
            both(Mark(shape: .disk(radius: 0.075 * s), center: c + Vector2(0.45 * s, -0.2 * s - 0.03 * s * bob), ink: color))
            m.append(Mark(shape: .disk(radius: 0.1 * s), center: c + Vector2(0, -0.08 * s), ink: color))
            m.append(Mark(shape: .disk(radius: 0.05 * s), center: c + Vector2(0, -0.08 * s), ink: .paper))
            m.append(Mark(shape: .disk(radius: 0.022 * s), center: c + Vector2(0, -0.08 * s), ink: color))
        }
        return m
    }
}
