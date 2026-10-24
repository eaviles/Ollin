import Foundation

extension Filter {
    /// Where `repeated(_:count:scale:rotation:opacity:hueShift:jitter:seed:)` puts
    /// its copies: in a grid over the layer, around a ring, or along a line.
    /// Positions and sizes are fractions of the layer with the origin at its top
    /// left, and angles are in radians in the canvas's own directions.
    public struct CopyLayout: Sendable, Equatable {
        enum Shape: Sendable, Equatable {
            case grid(columns: Int)
            case ring(center: Vector2, radius: Double, angle: Double, sweep: Double, facesOut: Bool)
            case line(from: Vector2, to: Vector2)
        }

        var shape: Shape

        /// Copies in reading order over a grid `columns` wide, as many rows as the
        /// count needs, each copy the whole layer shrunk to fit its cell.
        public static func grid(columns: Int = 3) -> CopyLayout {
            CopyLayout(shape: .grid(columns: min(max(columns, 1), 64)))
        }

        /// Copies spaced around a circle `radius` of the layer's height from
        /// `center`, clockwise from `angle` (the top, by default) through `sweep`.
        /// A full turn spaces them evenly with no copy doubled at the end; a shorter
        /// sweep puts the first and last copies on its two ends. With `facesOut`,
        /// each copy turns with its place on the ring, its top pointing away from the
        /// center, as the numbers on a clock face or the petals of a flower.
        public static func ring(radius: Double = 0.3, center: Vector2 = Vector2(0.5, 0.5),
                                angle: Double = -.pi / 2, sweep: Double = 2 * .pi,
                                facesOut: Bool = false) -> CopyLayout {
            CopyLayout(shape: .ring(center: center, radius: radius, angle: angle,
                                    sweep: sweep, facesOut: facesOut))
        }

        /// Copies evenly spaced along the line from `from` to `to`, the first on
        /// `from` and the last on `to`.
        public static func line(from: Vector2 = Vector2(0.2, 0.5),
                                to: Vector2 = Vector2(0.8, 0.5)) -> CopyLayout {
            CopyLayout(shape: .line(from: from, to: to))
        }
    }

    /// Copies of the layer laid out by `layout`, each a step smaller, more turned,
    /// fainter, and further around the hue wheel than the one before it.
    ///
    /// ```swift
    /// let mark = makeRenderTarget()
    /// withTarget(mark) { fill(.orange); drawStar(width / 2, height / 2, 140, 60, points: 5) }
    /// drawImage(mark.filtered(.repeated(.ring(radius: 0.3, facesOut: true), count: 9,
    ///                                   scale: 0.92, hueShift: 0.3)).image, 0, 0)
    /// ```
    ///
    /// Each copy is the whole layer, moved so the layer's middle lands on the
    /// copy's place, so draw the thing to be copied in the middle of its layer. In a
    /// grid the layer first shrinks to fit a cell; around a ring or along a line it
    /// keeps its size. Copy `i` (the first is 0) is then scaled by `scale` to the
    /// power `i`, turned by `i` times `rotation` radians, its opacity multiplied by
    /// `opacity` to the power `i`, and its hue turned `i` times `hueShift` radians
    /// in OKLCH, which keeps its lightness. `jitter` from 0 to 1 nudges each copy's
    /// place, turn, and size by a seeded amount, the same on every frame for one
    /// `seed`. The first copy is on top and each later copy goes under the ones
    /// before it, composited in premultiplied light, so a trail fades away behind
    /// its leader. Up to 64 copies.
    public static func repeated(_ layout: CopyLayout, count: Int = 8, scale: Double = 0.9,
                                rotation: Double = 0, opacity: Double = 0.9,
                                hueShift: Double = 0, jitter: Double = 0,
                                seed: Int = 0) -> Filter {
        Filter(kind: .repeated(layout: layout, count: min(max(count, 0), 64),
                               scale: max(scale, 0), rotation: rotation,
                               opacity: min(max(opacity, 0), 1), hueShift: hueShift,
                               jitter: min(max(jitter, 0), 1), seed: seed))
    }
}

extension Filter.CopyLayout {
    /// The place (layer fractions) and the extra turn (radians) of copy `index`
    /// of `count` on a layer `aspect` wide for a height of 1.
    func placement(of index: Int, count: Int, aspect: Double) -> (center: Vector2, turn: Double) {
        switch shape {
        case let .grid(columns):
            let rows = max(1, (count + columns - 1) / columns)
            let column = index % columns, row = index / columns
            return (Vector2((Double(column) + 0.5) / Double(columns),
                            (Double(row) + 0.5) / Double(rows)), 0)
        case let .ring(center, radius, angle, sweep, facesOut):
            let full = abs(sweep) >= 2 * .pi - 1e-9
            let step = count <= 1 ? 0 : sweep / Double(full ? count : count - 1)
            let a = angle + step * Double(index)
            // The radius is in layer heights, so the x offset is divided by the
            // aspect and the ring stays round on a wide layer.
            return (Vector2(center.x + radius * cos(a) / max(aspect, 1e-6), center.y + radius * sin(a)),
                    facesOut ? a + .pi / 2 : 0)
        case let .line(from, to):
            let t = count <= 1 ? 0 : Double(index) / Double(count - 1)
            return (Vector2(from.x + (to.x - from.x) * t, from.y + (to.y - from.y) * t), 0)
        }
    }

    /// The shrink every copy starts from: the size of a grid's cell, or 1.
    func baseScale(count: Int) -> Double {
        guard case let .grid(columns) = shape else { return 1 }
        let rows = max(1, (count + columns - 1) / columns)
        return 1 / Double(max(columns, rows))
    }
}

extension Filter {
    /// The two texels per copy `ollin_fx_repeated` reads, front copy first:
    /// (center x, center y, turn, scale) and (opacity, hue turn, 0, 0). The
    /// jitter is drawn here from the seed, so a copy keeps its nudge from frame to
    /// frame and the page draws the same copies.
    static func copyStrip(layout: CopyLayout, count: Int, scale: Double, rotation: Double,
                          opacity: Double, hueShift: Double, jitter: Double, seed: Int,
                          aspect: Double) -> [SIMD4<Float>] {
        guard count > 0 else { return [.zero, .zero] }
        var rng = SplitMix64(seed: UInt64(bitPattern: Int64(seed)) &+ 0xC0_91E5)
        func spread() -> Double { Double(rng.next() >> 11) / Double(1 << 53) * 2 - 1 }
        let base = layout.baseScale(count: count)
        var strip: [SIMD4<Float>] = []
        strip.reserveCapacity(count * 2)
        for i in 0..<count {
            var (center, turn) = layout.placement(of: i, count: count, aspect: aspect)
            var size = base * pow(scale, Double(i))
            turn += rotation * Double(i)
            // Four draws a copy whatever the jitter, so a copy's nudge keeps its
            // direction as the jitter is turned up.
            let dx = spread(), dy = spread(), dt = spread(), ds = spread()
            if jitter > 0 {
                center = Vector2(center.x + jitter * 0.05 * dx / max(aspect, 1e-6),
                                 center.y + jitter * 0.05 * dy)
                turn += jitter * 0.4 * dt
                size *= 1 + jitter * 0.25 * ds
            }
            strip.append(SIMD4(Float(center.x), Float(center.y), Float(turn), Float(size)))
            strip.append(SIMD4(Float(pow(opacity, Double(i))), Float(hueShift * Double(i)), 0, 0))
        }
        return strip
    }
}
