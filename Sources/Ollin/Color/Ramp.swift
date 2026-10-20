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
    /// Whether the ramp holds each color flat up to the next stop instead of
    /// blending between them (see `stepped(_:)`).
    public private(set) var isStepped: Bool = false

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

    /// Place `Stop` values at explicit positions: the typed form of the tuple
    /// list above, for stops built or edited as values (sorted for you;
    /// positions clamp to `0...1`).
    public init(stops: [Stop], in space: ColorSpace = .oklab) {
        self.init(stops: stops.map { (position: $0.position, color: $0.color) }, in: space)
    }

    /// A ramp that holds each color flat: the first color from 0 up to the
    /// second, the second up to the third, and so on, in equal bands with hard
    /// edges and no blending. The poster-flat gradient, and the stripe
    /// spectrum of holographic foil.
    ///
    /// ```swift
    /// let stripes = Ramp.stepped([.red, .orange, .yellow, .green, .blue])
    /// stripes.color(at: 0.3)   // orange, exactly, with no red in it
    /// ```
    public static func stepped(_ colors: [Color]) -> Ramp {
        let n = colors.count
        return stepped(stops: colors.enumerated().map { (Double($0.offset) / Double(max(n, 1)), $0.element) })
    }

    /// A stepped ramp with each color placed: it holds from its own position
    /// up to the next stop's, and the last holds to 1. Below the first stop the
    /// first color shows.
    public static func stepped(stops: [(position: Double, color: Color)]) -> Ramp {
        var ramp = Ramp(stops: stops)
        ramp.isStepped = true
        return ramp
    }

    /// The typed form of `stepped(stops:)`.
    public static func stepped(stops: [Stop]) -> Ramp {
        stepped(stops: stops.map { (position: $0.position, color: $0.color) })
    }

    /// The same ramp run the other way: every stop moves to `1 - position`, so
    /// the color that sat at 0 sits at 1, and a hard edge keeps its two colors
    /// in mirrored order. The `_r` of a colormap, as a property. A stepped ramp
    /// keeps its bands, each now running the other way.
    public var reversed: Ramp {
        guard isStepped else {
            return Ramp(stops: stops.reversed().map { Stop(position: 1 - $0.position, color: $0.color) },
                        in: space)
        }
        // A stepped band runs from its stop to the next one, so reversed it
        // starts where the next one ended.
        var mirrored: [Stop] = []
        for (i, stop) in stops.enumerated() {
            let end = i + 1 < stops.count ? stops[i + 1].position : 1
            mirrored.append(Stop(position: 1 - end, color: stop.color))
        }
        var ramp = Ramp(stops: mirrored, in: space)
        ramp.isStepped = true
        return ramp
    }

    /// The color at `t`, clamped to the ends. Between stops, the bracketing
    /// pair mixes in `space`; a stepped ramp holds the color of the last stop
    /// at or below `t`.
    public func color(at t: Double) -> Color {
        guard let last = stops.last else { return .clear }
        guard t > stops[0].position else { return stops[0].color }
        if isStepped {
            return stops.last { $0.position <= t }?.color ?? stops[0].color
        }
        guard t < last.position else { return last.color }
        // The first stop past t brackets it with its predecessor.
        let upper = stops.firstIndex { $0.position > t } ?? stops.count - 1
        let a = stops[upper - 1]
        let b = stops[upper]
        let span = b.position - a.position
        guard span > 0 else { return b.color }
        return Color.mix(a.color, b.color, (t - a.position) / span, in: space)
    }
}

public extension Ramp {
    /// A ramp over wavelengths of light: `stops` colors placed evenly `from`
    /// one wavelength `to` another, in nanometers, each the pure hue of its
    /// wavelength (`Color(wavelength:)`, the nearest a display shows at full
    /// brightness), so `color(at:)` walks the physical spectrum, violet at
    /// 400 through blue, green, yellow, and orange to red at 700. A hue wheel
    /// gives a different rainbow: this one has no magenta, since no single
    /// wavelength is magenta, and its green is wide. The visible range is
    /// about 380 to 780, and the ends are clamped to it; running `from` the
    /// longer wavelength `to` the shorter reverses the ramp.
    ///
    /// ```swift
    /// let spectrum = Ramp.wavelengths()                  // 400 to 700
    /// fill(spectrum.color(at: 0.5))                      // 550 nm, green
    /// let warm = Ramp.wavelengths(from: 570, to: 700)    // yellow to red
    /// ```
    static func wavelengths(from: Double = 400, to: Double = 700, stops: Int = 31,
                            in space: ColorSpace = .oklab) -> Ramp {
        let lo = min(max(from, 380), 780), hi = min(max(to, 380), 780)
        let n = max(stops, 2)
        let colors = (0 ..< n).map { i -> Color in
            let t = Double(i) / Double(n - 1)
            return Color(wavelength: lo + (hi - lo) * t)
        }
        return Ramp(colors, in: space)
    }

    /// The stripe spectrum of holographic foil: eight flat bands from violet
    /// through blue, cyan, green, yellow, and orange to red and magenta, the
    /// order a diffraction grating spreads white light in, as a stepped ramp.
    /// What `Filter.holographicFoil` reads unless handed another ramp.
    static let holographic = Ramp.stepped([
        Color(hex: 0x7B3FE4), Color(hex: 0x2E5CFF), Color(hex: 0x18C8F0), Color(hex: 0x3EE07A),
        Color(hex: 0xF4E04D), Color(hex: 0xFF9A3C), Color(hex: 0xFF4D6D), Color(hex: 0xE24CCF),
    ])

    /// The sky of airbrushed lettering chrome, read from the top of the shape
    /// down to its horizon: deep navy through blue to a pale sky that goes
    /// nearly white where it meets the horizon. What `Filter.chrome` paints
    /// above the horizon unless handed another ramp.
    static let chromeSky = Ramp([
        Color(hex: 0x0A1F5C), Color(hex: 0x1F6FE0), Color(hex: 0x8FD0FF), Color(hex: 0xEAF7FF),
    ])

    /// The floor of airbrushed lettering chrome, read from the horizon down to
    /// the bottom of the shape: dark brown through orange and gold to a pale
    /// yellow. What `Filter.chrome` paints below the horizon unless handed
    /// another ramp.
    static let chromeFloor = Ramp([
        Color(hex: 0x3A1A06), Color(hex: 0xC8641C), Color(hex: 0xF2C65A), Color(hex: 0xFFF0B8),
    ])
}
