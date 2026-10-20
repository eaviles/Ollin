import Foundation

// MARK: - Creases

public extension Heightfield {

    /// The profile of a crease across its width, read at `s`, the signed
    /// distance from the crease line in units of its width: the height a fold
    /// adds at that distance, with the crease's own peak at 1. It is the sum
    /// of three closed forms, so a fold reads as a fold rather than a bump:
    ///
    /// - a **cusp**, `exp(√f − √(s² + f))` with the floor `f` = 0.004, a sharp
    ///   peak whose tip is rounded over a few hundredths of the width;
    /// - an **asymmetric step**, `0.3 · tanh(2s) · exp(−s² / 8)`, which lifts
    ///   the flank on the positive side and lowers the other, the way a sheet
    ///   folded over sits higher on one side of the crease, fading out over a
    ///   few widths;
    /// - a **flanking trough**, `−0.35 · exp(−(|s| − 2)² / 0.5)`, the hollow
    ///   a crease presses into the sheet two widths out on either side.
    ///
    /// Past eight widths out, where the sum is under a thousandth, the profile
    /// is read at eight, so the kernel has a reach. The same formula shapes the
    /// folds of `Filter.paperTexture`, so a crease pressed into a heightfield
    /// and a fold in the paper filter are one kernel.
    static func creaseProfile(at s: Double) -> Double {
        let s = min(max(s, -8), 8)
        let floor = 0.004
        let cusp = exp(floor.squareRoot() - (s * s + floor).squareRoot())
        let step = 0.3 * tanh(2 * s) * exp(-s * s / 8)
        let offset = abs(s) - 2
        let trough = -0.35 * exp(-offset * offset / 0.5)
        return cusp + step + trough
    }

    /// The field with a crease folded into it along `path`, a polyline in the
    /// field's normalized coordinates (`u`, `v` in `0…1`, the coordinates the
    /// closure initializer samples at). Every sample takes `amplitude` times
    /// `creaseProfile(at:)` of its signed distance from the path in units of
    /// `width` (also in normalized coordinates), so the crease is `width` wide
    /// at its cusp, lifts the flank on the path's positive side (where the
    /// segment's direction crossed with the offset to the sample is positive)
    /// and lowers the other, and presses a shallow trough two widths out on
    /// both sides. Walk the path the other way to swap the flanks. A
    /// negative `amplitude` sinks the crease instead. The sheet's other heights
    /// are kept, so creases stack: fold a field several times for a crumpled
    /// sheet, and `normalized()` restores `0…1` when the folds take it past.
    ///
    /// ```swift
    /// var sheet = Heightfield(columns: 257, rows: 257, repeating: 0.5)
    /// sheet = sheet.creased(along: [Vector2(0.1, 0.2), Vector2(0.9, 0.7)], width: 0.03, amplitude: 0.3)
    /// ```
    ///
    /// A path of fewer than two points or a width of zero changes nothing.
    func creased(along path: [Vector2], width: Double, amplitude: Double) -> Heightfield {
        guard path.count >= 2, width > 0, amplitude != 0 else { return self }
        var result = self
        for y in 0 ..< rows {
            let v = Double(y) / Double(rows - 1)
            for x in 0 ..< columns {
                let u = Double(x) / Double(columns - 1)
                let s = Heightfield.signedDistance(from: Vector2(u, v), to: path) / width
                result[x, y] += amplitude * Heightfield.creaseProfile(at: s)
            }
        }
        return result
    }

    /// The signed distance from `point` to the polyline `path`: the distance to
    /// its nearest segment, positive where that segment's direction crossed
    /// with the offset to the point is positive and negative on the other side.
    internal static func signedDistance(from point: Vector2, to path: [Vector2]) -> Double {
        var best = Double.infinity
        var sign = 1.0
        for i in 1 ..< path.count {
            let a = path[i - 1], b = path[i]
            let ab = b - a
            let lengthSquared = ab.lengthSquared
            let t = lengthSquared > 0 ? min(max((point - a).dot(ab) / lengthSquared, 0), 1) : 0
            let nearest = a + ab * t
            let d = (point - nearest).length
            if d < best {
                best = d
                let side = ab.cross(point - a)
                sign = side >= 0 ? 1 : -1
            }
        }
        return best * sign
    }
}
