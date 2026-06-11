import Foundation

/// A gradient built from a list of colors — evenly spaced, or placed with
/// explicit stops — sampled with `color(at:)` like `CosinePalette` and
/// `Colormap`. Interpolation runs through a chosen `ColorSpace` (OKLab by
/// default, which blends evenly); `t` clamps to the ends.
///
/// ```swift
/// let heat = Ramp([.black, .red, Color(hex: 0xFFCC00), .white])
/// fill(heat.color(at: energy))
///
/// let sky = Ramp(stops: [(0, Color(hex: 0x0B1A40)),
///                        (0.8, Color(hex: 0x3C6DD0)),
///                        (1, Color(hex: 0xFFD9A0))], in: .oklch)
/// ```
public struct Ramp: Equatable, Hashable, Sendable {
    /// A color pinned to a position in `0...1`.
    public struct Stop: Equatable, Hashable, Sendable {
        public var position: Double
        public var color: Color

        public init(position: Double, color: Color) {
            self.position = position
            self.color = color
        }
    }

    /// The stops, kept sorted by position.
    public private(set) var stops: [Stop]
    /// The space `color(at:)` interpolates through.
    public var space: ColorSpace

    /// Spread colors evenly from 0 to 1. An empty list makes a clear ramp; a
    /// single color makes a constant one.
    public init(_ colors: [Color], in space: ColorSpace = .oklab) {
        let n = colors.count
        switch n {
        case 0: self.init(stops: [(0, .clear)], in: space)
        case 1: self.init(stops: [(0, colors[0])], in: space)
        default: self.init(stops: colors.enumerated().map {
            (Double($0.offset) / Double(n - 1), $0.element)
        }, in: space)
        }
    }

    /// Place colors at explicit positions (sorted for you; positions clamp to
    /// `0...1`). Two stops sharing a position make a hard edge.
    public init(stops: [(position: Double, color: Color)], in space: ColorSpace = .oklab) {
        let sorted = stops
            .map { Stop(position: min(max($0.position, 0), 1), color: $0.color) }
            .sorted { $0.position < $1.position }
        self.stops = sorted.isEmpty ? [Stop(position: 0, color: .clear)] : sorted
        self.space = space
    }

    /// The color at `t`, clamped to the ends. Between stops, the bracketing
    /// pair mixes in `space`.
    public func color(at t: Double) -> Color {
        guard let last = stops.last else { return .clear }
        guard t > stops[0].position else { return stops[0].color }
        guard t < last.position else { return last.color }
        // The first stop past t brackets it with its predecessor.
        let upper = stops.firstIndex { $0.position > t } ?? stops.count - 1
        let a = stops[upper - 1]
        let b = stops[upper]
        let span = b.position - a.position
        guard span > 0 else { return b.color }
        return Color.mix(a.color, b.color, t: (t - a.position) / span, in: space)
    }
}
