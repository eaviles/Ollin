import Foundation

/// A named, ready-to-use camera motion you hand to `cameraMove(_:)` instead of
/// keyframing the camera by hand.
///
/// Every move is a way to *look at an object* on a turntable: it modulates the
/// orbit pose (the azimuth, elevation, and radius around a centered target), so
/// it suits the kind of scene Ollin draws most (a transforming solid, a particle
/// system, a point cloud) rather than flying a camera through an architectural
/// space. Angles are in radians, matching the rest of the camera API.
///
/// ```swift
/// override func draw() {
///     cameraMove(.turntable(period: 12), radius: 6)   // a slow product-shot spin
///     drawBox(size: 2)
/// }
/// ```
///
/// A move composes over the pose it starts from, so framing a shot by hand with
/// `cameraControl()` first and then switching to a move lets it drift on from
/// where you left it. The finite moves (`pushIn`, `tilt`, `reveal`, …) ease over
/// a duration and then hold; the cyclic ones (`turntable`, `sway`, `handheld`)
/// run continuously.
public struct CameraMove: Sendable, Equatable {
    /// The motion and its parameters. Internal; build a move through the static
    /// factories below.
    enum Kind: Sendable {
        case turntable(period: Double)
        case sway(amplitude: Double, period: Double)
        case pushIn(factor: Double, duration: Double, ease: Easing)
        case pullOut(factor: Double, duration: Double, ease: Easing)
        case tilt(to: Double, duration: Double, ease: Easing)
        case orbitAndRise(period: Double, rise: Double, duration: Double)
        case reveal(duration: Double, ease: Easing)
        case handheld(amount: Double, speed: Double)
    }

    let kind: Kind

    /// A continuous turntable spin around the object, one full turn every `period`
    /// seconds. Positive turns one way, negative the other.
    public static func turntable(period: Double) -> CameraMove {
        CameraMove(kind: .turntable(period: period))
    }

    /// A gentle azimuth rock back and forth by `amplitude` radians, one full cycle
    /// every `period` seconds, so the object is seen from a range of angles without
    /// a full spin.
    public static func sway(amplitude: Double = .pi / 6, period: Double = 8) -> CameraMove {
        CameraMove(kind: .sway(amplitude: amplitude, period: period))
    }

    /// Dolly closer, scaling the radius by `factor` (below 1 zooms in) over
    /// `duration` seconds, then holds.
    public static func pushIn(by factor: Double = 0.5, in duration: Double = 2,
                              ease: Easing = .easeInOut) -> CameraMove {
        CameraMove(kind: .pushIn(factor: factor, duration: duration, ease: ease))
    }

    /// Dolly away, scaling the radius by `factor` (above 1 zooms out) over
    /// `duration` seconds, then holds.
    public static func pullOut(by factor: Double = 2, in duration: Double = 2,
                               ease: Easing = .easeInOut) -> CameraMove {
        CameraMove(kind: .pullOut(factor: factor, duration: duration, ease: ease))
    }

    /// Sweep the elevation to `elevation` radians (rise to look down on the object,
    /// drop to look up at it) over `duration` seconds, then holds.
    public static func tilt(to elevation: Double, in duration: Double = 2,
                            ease: Easing = .easeInOut) -> CameraMove {
        CameraMove(kind: .tilt(to: elevation, duration: duration, ease: ease))
    }

    /// The spiral beauty pass: turn continuously (one revolution every `period`
    /// seconds) while the elevation rises by `rise` radians over `duration`, then
    /// keeps turning at the lifted height.
    public static func orbitAndRise(period: Double = 12, rise: Double = 0.5,
                                    in duration: Double = 6) -> CameraMove {
        CameraMove(kind: .orbitAndRise(period: period, rise: rise, duration: duration))
    }

    /// An opening shot: start close and low, then pull back out to the framed radius
    /// and rise to the framed elevation over `duration` seconds, then holds.
    public static func reveal(in duration: Double = 3, ease: Easing = .easeOut) -> CameraMove {
        CameraMove(kind: .reveal(duration: duration, ease: ease))
    }

    /// Subtle operator breathing: small continuous drift on the azimuth, elevation,
    /// and radius (from a smooth noise field) so a held shot reads as alive rather
    /// than locked. `amount` scales the wobble, `speed` how fast it wanders.
    public static func handheld(amount: Double = 0.04, speed: Double = 1) -> CameraMove {
        CameraMove(kind: .handheld(amount: amount, speed: speed))
    }

    /// The curated default motion for `cameraShowcase(_:)`: a gentle, slow product-shot
    /// turntable, one revolution every `period` seconds. A calm orbit that showcases
    /// the object without drawing attention to the camera. (A `.turntable` under the
    /// hood, so `cameraShowcase` lets the viewer take it over and eases back when idle.)
    public static func autoOrbit(period: Double = 24) -> CameraMove {
        CameraMove(kind: .turntable(period: period))
    }

    /// Two moves are the same motion when their numeric parameters match; the
    /// easing curve is excluded (it is a closure, not comparable), which is enough
    /// for the rig to tell when a *different* move has been handed in.
    public static func == (a: CameraMove, b: CameraMove) -> Bool {
        switch (a.kind, b.kind) {
        case let (.turntable(p1), .turntable(p2)):
            return p1 == p2
        case let (.sway(a1, p1), .sway(a2, p2)):
            return a1 == a2 && p1 == p2
        case let (.pushIn(f1, d1, _), .pushIn(f2, d2, _)):
            return f1 == f2 && d1 == d2
        case let (.pullOut(f1, d1, _), .pullOut(f2, d2, _)):
            return f1 == f2 && d1 == d2
        case let (.tilt(t1, d1, _), .tilt(t2, d2, _)):
            return t1 == t2 && d1 == d2
        case let (.orbitAndRise(p1, r1, d1), .orbitAndRise(p2, r2, d2)):
            return p1 == p2 && r1 == r2 && d1 == d2
        case let (.reveal(d1, _), .reveal(d2, _)):
            return d1 == d2
        case let (.handheld(a1, s1), .handheld(a2, s2)):
            return a1 == a2 && s1 == s2
        default:
            return false
        }
    }
}
