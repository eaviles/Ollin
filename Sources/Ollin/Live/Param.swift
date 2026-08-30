import Foundation
import os

/// How a `@Param` eases into a new value instead of snapping to it. Pass one to a
/// parameter to soften *every* source that drives the knob: a MIDI fader, an OSC
/// address, or a drag of the inspector slider all glide rather than jump.
///
/// ```swift
/// @Param(20...400, smoothing: .eased(0.3)) var radius = 120.0   // 0.3s glide
/// @Param(0...1, smoothing: .smoothed) var mix = 0.5             // adaptive 1€ filter
/// @Param(0...127) var snappy = 64.0                             // immediate (default)
/// ```
///
/// `.eased` glides to the target over a fixed time along an `Easing` curve:
/// crisp and predictable. `.smoothed` runs the value through a `OneEuroFilter`,
/// which stays steady while the knob is still and opens up as it moves, the
/// better feel for a hand on live hardware. Smoothing applies to `Double`
/// parameters; the other kinds switch instantly.
public enum ParamSmoothing: Sendable {
    /// Glide to each new value over `duration` seconds, shaped by `curve`.
    case eased(duration: Double, curve: Easing)
    /// Denoise the value with a 1€ filter (Casiez, Roussel & Vogel): `minCutoff`
    /// sets the resting smoothness, `beta` how quickly it opens up as the value
    /// moves.
    case smoothed(minCutoff: Double, beta: Double)

    /// `.eased(0.3)`: a glide of `duration` seconds with a gentle ease-out.
    public static func eased(_ duration: Double, curve: Easing = .easeOut) -> ParamSmoothing {
        .eased(duration: duration, curve: curve)
    }

    /// The 1€ filter at its gentle defaults, a good start for a live knob.
    public static var smoothed: ParamSmoothing { .smoothed(minCutoff: 1, beta: 0.007) }
}

// MARK: - Stored values

/// A parameter value in its host-persistable form. The live hosts record one per
/// tuned knob (keyed by property name) and re-apply it across reloads, so the
/// payload is a small, codable value rather than the parameter's Swift type.
public enum ParamStored: Equatable, Sendable, Codable {
    /// A `Double` or `Int` parameter's value.
    case number(Double)
    /// A `Bool` parameter's value.
    case boolean(Bool)
    /// An enum parameter's selected case, by its case name.
    case option(String)
    /// A `Color` parameter's value, as sRGB components in `0...1`.
    case color(red: Double, green: Double, blue: Double, alpha: Double)
    /// A `Vector2` parameter's value.
    case vector(x: Double, y: Double)
    /// A `Vector3` parameter's value.
    case vector3(x: Double, y: Double, z: Double)
    /// A `Rectangle` parameter's value.
    case rectangle(x: Double, y: Double, width: Double, height: Double)
    /// An `Insets` parameter's value.
    case insets(top: Double, right: Double, bottom: Double, left: Double)
    /// A `ClosedRange<Double>` parameter's value.
    case range(lower: Double, upper: Double)
    /// A `String` parameter's value.
    case text(String)
    /// A `Palette` or `Ramp` parameter's value: its colors in order, each with
    /// the position it sits at, and the name of the space a ramp blends
    /// through (`nil` for a palette, whose colors are evenly spread and never
    /// blended).
    case colors(stops: [ParamColorStop], space: String?)

    /// The stored spelling of every case. `rectangle` travels as `"rect"`,
    /// the key takes, checkpoints, and the room's messages carry on the wire.
    enum CodingKeys: String, CodingKey {
        case number, boolean, option, color, vector, vector3
        case rectangle = "rect"
        case insets, range, text, colors
    }
}

/// One color of a stored palette or ramp: where it sits in `0...1`, and its
/// sRGB components.
public struct ParamColorStop: Equatable, Sendable, Codable {
    public var position: Double
    public var red: Double
    public var green: Double
    public var blue: Double
    public var alpha: Double

    public init(position: Double, red: Double, green: Double, blue: Double, alpha: Double) {
        self.position = position
        self.red = red
        self.green = green
        self.blue = blue
        self.alpha = alpha
    }

    public init(position: Double, color: Color) {
        self.init(position: position, red: color.red, green: color.green,
                  blue: color.blue, alpha: color.alpha)
    }

    /// The stop's color.
    public var color: Color {
        Color(red: red, green: green, blue: blue, alpha: alpha)
    }
}

/// Positions for `count` colors spread evenly over `0...1`, which is how a
/// palette's colors sit (and how `Palette.ramp(in:)` places them).
private func evenPositions(_ count: Int) -> [Double] {
    guard count > 1 else { return count == 1 ? [0] : [] }
    return (0..<count).map { Double($0) / Double(count - 1) }
}

// MARK: - Controls

/// A type-erased description of the inspector control that edits a parameter:
/// which control kind to show, its metadata, and closures that read and write
/// the live value. The inspector switches on this to build the right row; the
/// closures are safe to call from the main thread while anything else drives
/// the same knob.
public enum ParamControl {
    case slider(Slider)
    case stepper(Stepper)
    case toggle(Toggle)
    case menu(Menu)
    case colorWell(ColorWell)
    case vector(Vector)
    case vector3(Vector3Fields)
    case rectangle(RectangleFields)
    case insets(InsetsFields)
    case range(RangeFields)
    case text(TextBox)
    case swatches(Swatches)

    /// A `Double` knob: a slider over `range`, optionally snapped to `step`.
    /// `style: .field` drops the track and leaves the scrubbable value field.
    public struct Slider: Sendable {
        public let range: ClosedRange<Double>
        public let step: Double?
        public let style: ParamNumericStyle
        public let read: @Sendable () -> Double
        public let write: @Sendable (Double) -> Void
        public init(range: ClosedRange<Double>, step: Double?,
                    style: ParamNumericStyle = .slider,
                    read: @escaping @Sendable () -> Double,
                    write: @escaping @Sendable (Double) -> Void) {
            self.range = range; self.step = step; self.style = style; self.read = read; self.write = write
        }
    }

    /// An `Int` knob: a value field with increment/decrement, stepping by `step`.
    public struct Stepper: Sendable {
        public let range: ClosedRange<Int>
        public let step: Int
        public let read: @Sendable () -> Int
        public let write: @Sendable (Int) -> Void
        public init(range: ClosedRange<Int>, step: Int,
                    read: @escaping @Sendable () -> Int,
                    write: @escaping @Sendable (Int) -> Void) {
            self.range = range; self.step = step; self.read = read; self.write = write
        }
    }

    /// A `Bool` knob: an on/off switch.
    public struct Toggle: Sendable {
        public let read: @Sendable () -> Bool
        public let write: @Sendable (Bool) -> Void
        public init(read: @escaping @Sendable () -> Bool,
                    write: @escaping @Sendable (Bool) -> Void) {
            self.read = read; self.write = write
        }
    }

    /// An enum knob: a pop-up menu (or segmented control) over `options`,
    /// addressed by index.
    public struct Menu: Sendable {
        public let options: [String]
        public let style: ParamMenuStyle
        public let read: @Sendable () -> Int
        public let write: @Sendable (Int) -> Void
        public init(options: [String], style: ParamMenuStyle = .menu,
                    read: @escaping @Sendable () -> Int,
                    write: @escaping @Sendable (Int) -> Void) {
            self.options = options; self.style = style; self.read = read; self.write = write
        }
    }

    /// A `Color` knob: a color well.
    public struct ColorWell: Sendable {
        public let read: @Sendable () -> Color
        public let write: @Sendable (Color) -> Void
        public init(read: @escaping @Sendable () -> Color,
                    write: @escaping @Sendable (Color) -> Void) {
            self.read = read; self.write = write
        }
    }

    /// A `Vector2` knob: paired x/y value fields, each over its own range,
    /// optionally with an XY pad below (`style: .pad`).
    public struct Vector: Sendable {
        public let xRange: ClosedRange<Double>
        public let yRange: ClosedRange<Double>
        public let style: ParamVectorStyle
        public let read: @Sendable () -> Vector2
        public let write: @Sendable (Vector2) -> Void
        public init(xRange: ClosedRange<Double>, yRange: ClosedRange<Double>,
                    style: ParamVectorStyle = .fields,
                    read: @escaping @Sendable () -> Vector2,
                    write: @escaping @Sendable (Vector2) -> Void) {
            self.xRange = xRange; self.yRange = yRange; self.style = style
            self.read = read; self.write = write
        }
    }

    /// A `Vector3` knob: x/y/z value fields, each over its own range.
    public struct Vector3Fields: Sendable {
        public let xRange: ClosedRange<Double>
        public let yRange: ClosedRange<Double>
        public let zRange: ClosedRange<Double>
        public let read: @Sendable () -> Vector3
        public let write: @Sendable (Vector3) -> Void
        public init(xRange: ClosedRange<Double>, yRange: ClosedRange<Double>,
                    zRange: ClosedRange<Double>,
                    read: @escaping @Sendable () -> Vector3,
                    write: @escaping @Sendable (Vector3) -> Void) {
            self.xRange = xRange; self.yRange = yRange; self.zRange = zRange
            self.read = read; self.write = write
        }
    }

    /// A `Rectangle` knob: x/y/w/h value fields, each over its own range.
    public struct RectangleFields: Sendable {
        public let xRange: ClosedRange<Double>
        public let yRange: ClosedRange<Double>
        public let widthRange: ClosedRange<Double>
        public let heightRange: ClosedRange<Double>
        public let read: @Sendable () -> Rectangle
        public let write: @Sendable (Rectangle) -> Void
        public init(xRange: ClosedRange<Double>, yRange: ClosedRange<Double>,
                    widthRange: ClosedRange<Double>, heightRange: ClosedRange<Double>,
                    read: @escaping @Sendable () -> Rectangle,
                    write: @escaping @Sendable (Rectangle) -> Void) {
            self.xRange = xRange; self.yRange = yRange
            self.widthRange = widthRange; self.heightRange = heightRange
            self.read = read; self.write = write
        }
    }

    /// An `Insets` knob: t/r/b/l value fields sharing one per-edge range.
    public struct InsetsFields: Sendable {
        public let edgeRange: ClosedRange<Double>
        public let read: @Sendable () -> Insets
        public let write: @Sendable (Insets) -> Void
        public init(edgeRange: ClosedRange<Double>,
                    read: @escaping @Sendable () -> Insets,
                    write: @escaping @Sendable (Insets) -> Void) {
            self.edgeRange = edgeRange; self.read = read; self.write = write
        }
    }

    /// A `ClosedRange<Double>` knob: min/max value fields within `outer`, over
    /// a two-thumb slider by default (`style: .field` drops the track).
    public struct RangeFields: Sendable {
        public let outer: ClosedRange<Double>
        public let style: ParamNumericStyle
        public let read: @Sendable () -> ClosedRange<Double>
        public let write: @Sendable (ClosedRange<Double>) -> Void
        public init(outer: ClosedRange<Double>,
                    style: ParamNumericStyle = .slider,
                    read: @escaping @Sendable () -> ClosedRange<Double>,
                    write: @escaping @Sendable (ClosedRange<Double>) -> Void) {
            self.outer = outer; self.style = style; self.read = read; self.write = write
        }
    }

    /// A `String` knob: a free text field.
    public struct TextBox: Sendable {
        public let read: @Sendable () -> String
        public let write: @Sendable (String) -> Void
        public init(read: @escaping @Sendable () -> String,
                    write: @escaping @Sendable (String) -> Void) {
            self.read = read; self.write = write
        }
    }

    /// A `Palette` or `Ramp` knob: a strip of colors, each opened in a color
    /// well. Every color carries the position it sits at, so a ramp's stops
    /// can be moved along the band; a palette's colors are spread evenly and
    /// their positions only say where each block is drawn.
    public struct Swatches: Sendable {
        /// One color on the strip.
        public struct Stop: Equatable, Sendable {
            public var position: Double
            public var color: Color
            public init(position: Double, color: Color) {
                self.position = position
                self.color = color
            }
        }

        /// Whether the strip reads as blocks or as one blended band.
        public let style: ParamSwatchStyle
        /// How many colors the strip may hold; the add and remove buttons stop
        /// at its ends.
        public let count: ClosedRange<Int>
        /// What the value itself shows at `t`. The blended band draws this
        /// rather than a plain gradient between the stops, since a ramp blends
        /// through a space of its own choosing.
        public let sample: @Sendable (Double) -> Color
        public let read: @Sendable () -> [Stop]
        public let write: @Sendable ([Stop]) -> Void

        public init(style: ParamSwatchStyle, count: ClosedRange<Int>,
                    sample: @escaping @Sendable (Double) -> Color,
                    read: @escaping @Sendable () -> [Stop],
                    write: @escaping @Sendable ([Stop]) -> Void) {
            self.style = style; self.count = count; self.sample = sample
            self.read = read; self.write = write
        }
    }
}

// MARK: - Value kinds

/// How a numeric parameter presents in the inspector.
public enum ParamNumericStyle: Sendable {
    /// A slider with the value field beside it (the default). For a
    /// `ClosedRange` parameter this is a two-thumb slider.
    case slider
    /// The value field alone: scrub or type, no track. The fit for a precise
    /// quantity or a range so wide a slider's resolution would be useless.
    case field
}

/// How a `Vector2` parameter presents in the inspector.
public enum ParamVectorStyle: Sendable {
    /// Paired x/y value fields (the default).
    case fields
    /// The x/y fields plus an XY pad: drag a dot in a square mapped to the
    /// two ranges. The fit for a position or direction tuned by feel.
    case pad
}

/// How an option (enum or named-choices) parameter presents in the inspector.
public enum ParamMenuStyle: Sendable {
    /// A pop-up menu (the default). Scales to any number of options.
    case menu
    /// A segmented control: every option visible at once. The fit for two to
    /// four short names; more than fits the row falls back to reading poorly,
    /// so prefer the menu for long case lists.
    case segmented
}

/// How a `Palette` or `Ramp` parameter presents in the inspector.
public enum ParamSwatchStyle: Sendable {
    /// Separate blocks of color, one per swatch: a `Palette`.
    case blocks
    /// One blended band with a handle per stop: a `Ramp`.
    case gradient
}

/// The constraint payload of a `Palette` or `Ramp` parameter: how many colors
/// the strip may hold, and how it reads.
public struct ParamSwatchConstraints: Sendable {
    public var count: ClosedRange<Int>
    public var style: ParamSwatchStyle
    public init(count: ClosedRange<Int>, style: ParamSwatchStyle) {
        self.count = count
        self.style = style
    }
}

/// The numeric constraint payload of a `Double` or `Int` parameter: the allowed
/// range, an optional step the value snaps to, and the presentation style.
public struct ParamNumericConstraints<Number: Comparable & Sendable>: Sendable {
    public var range: ClosedRange<Number>
    public var step: Number?
    public var style: ParamNumericStyle
    public init(range: ClosedRange<Number>, step: Number? = nil, style: ParamNumericStyle = .slider) {
        self.range = range
        self.step = step
        self.style = style
    }
}

/// A value a `@Param` can hold. Each kind carries its own constraint payload
/// (a numeric range, or nothing), knows how to clamp to it, round-trips through
/// `ParamStored` for host persistence, and describes the inspector control that
/// edits it. The built-in kinds are `Double`, `Int`, `Bool`, `Color`, and any
/// enum conforming to `ParamOption`.
public protocol ParamValue: Equatable, Sendable {
    associatedtype Constraints: Sendable
    static func clamped(_ value: Self, by constraints: Constraints) -> Self
    static func stored(_ value: Self) -> ParamStored
    static func restored(_ stored: ParamStored) -> Self?
    static func control(for param: Param<Self>) -> ParamControl
}

extension Double: ParamValue {
    public typealias Constraints = ParamNumericConstraints<Double>

    public static func clamped(_ value: Double, by constraints: Constraints) -> Double {
        var v = Swift.min(Swift.max(value, constraints.range.lowerBound), constraints.range.upperBound)
        if let step = constraints.step, step > 0 {
            let lower = constraints.range.lowerBound
            v = lower + ((v - lower) / step).rounded() * step
            v = Swift.min(v, constraints.range.upperBound)
        }
        return v
    }

    public static func stored(_ value: Double) -> ParamStored { .number(value) }

    public static func restored(_ stored: ParamStored) -> Double? {
        guard case .number(let v) = stored else { return nil }
        return v
    }

    public static func control(for param: Param<Double>) -> ParamControl {
        .slider(.init(range: param.constraints.range, step: param.constraints.step,
                      style: param.constraints.style,
                      read: { param.wrappedValue }, write: { param.wrappedValue = $0 }))
    }
}

extension Int: ParamValue {
    public typealias Constraints = ParamNumericConstraints<Int>

    public static func clamped(_ value: Int, by constraints: Constraints) -> Int {
        var v = Swift.min(Swift.max(value, constraints.range.lowerBound), constraints.range.upperBound)
        if let step = constraints.step, step > 1 {
            let lower = constraints.range.lowerBound
            v = lower + (v - lower + step / 2) / step * step
            v = Swift.min(v, constraints.range.upperBound)
        }
        return v
    }

    public static func stored(_ value: Int) -> ParamStored { .number(Double(value)) }

    public static func restored(_ stored: ParamStored) -> Int? {
        guard case .number(let v) = stored else { return nil }
        return Int(v.rounded())
    }

    public static func control(for param: Param<Int>) -> ParamControl {
        .stepper(.init(range: param.constraints.range, step: param.constraints.step ?? 1,
                       read: { param.wrappedValue }, write: { param.wrappedValue = $0 }))
    }
}

extension Bool: ParamValue {
    public typealias Constraints = Void
    public static func clamped(_ value: Bool, by _: Void) -> Bool { value }
    public static func stored(_ value: Bool) -> ParamStored { .boolean(value) }
    public static func restored(_ stored: ParamStored) -> Bool? {
        guard case .boolean(let v) = stored else { return nil }
        return v
    }
    public static func control(for param: Param<Bool>) -> ParamControl {
        .toggle(.init(read: { param.wrappedValue }, write: { param.wrappedValue = $0 }))
    }
}

extension Color: ParamValue {
    public typealias Constraints = Void
    public static func clamped(_ value: Color, by _: Void) -> Color { value }
    public static func stored(_ value: Color) -> ParamStored {
        .color(red: value.red, green: value.green, blue: value.blue, alpha: value.alpha)
    }
    public static func restored(_ stored: ParamStored) -> Color? {
        guard case .color(let r, let g, let b, let a) = stored else { return nil }
        return Color(red: r, green: g, blue: b, alpha: a)
    }
    public static func control(for param: Param<Color>) -> ParamControl {
        .colorWell(.init(read: { param.wrappedValue }, write: { param.wrappedValue = $0 }))
    }
}

/// The per-axis constraint payload of a `Vector2` parameter.
public struct ParamVectorConstraints: Sendable {
    public var x: ClosedRange<Double>
    public var y: ClosedRange<Double>
    public var style: ParamVectorStyle
    public init(x: ClosedRange<Double>, y: ClosedRange<Double>,
                style: ParamVectorStyle = .fields) {
        self.x = x
        self.y = y
        self.style = style
    }
}

/// The per-axis constraint payload of a `Vector3` parameter.
public struct ParamVector3Constraints: Sendable {
    public var x: ClosedRange<Double>
    public var y: ClosedRange<Double>
    public var z: ClosedRange<Double>
    public init(x: ClosedRange<Double>, y: ClosedRange<Double>, z: ClosedRange<Double>) {
        self.x = x
        self.y = y
        self.z = z
    }
}

extension Vector3: ParamValue {
    public typealias Constraints = ParamVector3Constraints

    public static func clamped(_ value: Vector3, by constraints: Constraints) -> Vector3 {
        Vector3(Swift.min(Swift.max(value.x, constraints.x.lowerBound), constraints.x.upperBound),
                Swift.min(Swift.max(value.y, constraints.y.lowerBound), constraints.y.upperBound),
                Swift.min(Swift.max(value.z, constraints.z.lowerBound), constraints.z.upperBound))
    }

    public static func stored(_ value: Vector3) -> ParamStored {
        .vector3(x: value.x, y: value.y, z: value.z)
    }

    public static func restored(_ stored: ParamStored) -> Vector3? {
        guard case .vector3(let x, let y, let z) = stored else { return nil }
        return Vector3(x, y, z)
    }

    public static func control(for param: Param<Vector3>) -> ParamControl {
        .vector3(.init(xRange: param.constraints.x, yRange: param.constraints.y,
                       zRange: param.constraints.z,
                       read: { param.wrappedValue }, write: { param.wrappedValue = $0 }))
    }
}

extension Vector2: ParamValue {
    public typealias Constraints = ParamVectorConstraints

    public static func clamped(_ value: Vector2, by constraints: Constraints) -> Vector2 {
        Vector2(Swift.min(Swift.max(value.x, constraints.x.lowerBound), constraints.x.upperBound),
                Swift.min(Swift.max(value.y, constraints.y.lowerBound), constraints.y.upperBound))
    }

    public static func stored(_ value: Vector2) -> ParamStored { .vector(x: value.x, y: value.y) }

    public static func restored(_ stored: ParamStored) -> Vector2? {
        guard case .vector(let x, let y) = stored else { return nil }
        return Vector2(x, y)
    }

    public static func control(for param: Param<Vector2>) -> ParamControl {
        .vector(.init(xRange: param.constraints.x, yRange: param.constraints.y,
                      style: param.constraints.style,
                      read: { param.wrappedValue }, write: { param.wrappedValue = $0 }))
    }
}

/// The per-field constraint payload of a `Rectangle` parameter.
public struct ParamRectangleConstraints: Sendable {
    public var x: ClosedRange<Double>
    public var y: ClosedRange<Double>
    public var width: ClosedRange<Double>
    public var height: ClosedRange<Double>
    public init(x: ClosedRange<Double>, y: ClosedRange<Double>,
                width: ClosedRange<Double>, height: ClosedRange<Double>) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }
}

extension Rectangle: ParamValue {
    public typealias Constraints = ParamRectangleConstraints

    public static func clamped(_ value: Rectangle, by constraints: Constraints) -> Rectangle {
        func clamp(_ v: Double, _ range: ClosedRange<Double>) -> Double {
            Swift.min(Swift.max(v, range.lowerBound), range.upperBound)
        }
        return Rectangle(x: clamp(value.x, constraints.x), y: clamp(value.y, constraints.y),
                         width: clamp(value.width, constraints.width),
                         height: clamp(value.height, constraints.height))
    }

    public static func stored(_ value: Rectangle) -> ParamStored {
        .rectangle(x: value.x, y: value.y, width: value.width, height: value.height)
    }

    public static func restored(_ stored: ParamStored) -> Rectangle? {
        guard case .rectangle(let x, let y, let w, let h) = stored else { return nil }
        return Rectangle(x: x, y: y, width: w, height: h)
    }

    public static func control(for param: Param<Rectangle>) -> ParamControl {
        .rectangle(.init(xRange: param.constraints.x, yRange: param.constraints.y,
                         widthRange: param.constraints.width, heightRange: param.constraints.height,
                         read: { param.wrappedValue }, write: { param.wrappedValue = $0 }))
    }
}

extension Insets: ParamValue {
    public typealias Constraints = ClosedRange<Double>

    public static func clamped(_ value: Insets, by range: Constraints) -> Insets {
        func clamp(_ v: Double) -> Double {
            Swift.min(Swift.max(v, range.lowerBound), range.upperBound)
        }
        return Insets(top: clamp(value.top), right: clamp(value.right),
                      bottom: clamp(value.bottom), left: clamp(value.left))
    }

    public static func stored(_ value: Insets) -> ParamStored {
        .insets(top: value.top, right: value.right, bottom: value.bottom, left: value.left)
    }

    public static func restored(_ stored: ParamStored) -> Insets? {
        guard case .insets(let t, let r, let b, let l) = stored else { return nil }
        return Insets(top: t, right: r, bottom: b, left: l)
    }

    public static func control(for param: Param<Insets>) -> ParamControl {
        .insets(.init(edgeRange: param.constraints,
                      read: { param.wrappedValue }, write: { param.wrappedValue = $0 }))
    }
}

/// The constraint payload of a `ClosedRange<Double>` parameter: the outer
/// bounds both ends stay inside, and the presentation style.
public struct ParamRangeConstraints: Sendable {
    public var outer: ClosedRange<Double>
    public var style: ParamNumericStyle
    public init(outer: ClosedRange<Double>, style: ParamNumericStyle = .slider) {
        self.outer = outer
        self.style = style
    }
}

extension ClosedRange: ParamValue where Bound == Double {
    public typealias Constraints = ParamRangeConstraints

    /// Both ends clamp into the outer bounds, and the pair stays ordered: a
    /// minimum pushed past the maximum drags the maximum along with it.
    public static func clamped(_ value: ClosedRange<Double>, by constraints: Constraints) -> ClosedRange<Double> {
        let outer = constraints.outer
        let lower = Swift.min(Swift.max(value.lowerBound, outer.lowerBound), outer.upperBound)
        let upper = Swift.min(Swift.max(value.upperBound, lower), outer.upperBound)
        return lower...upper
    }

    public static func stored(_ value: ClosedRange<Double>) -> ParamStored {
        .range(lower: value.lowerBound, upper: value.upperBound)
    }

    public static func restored(_ stored: ParamStored) -> ClosedRange<Double>? {
        guard case .range(let lower, let upper) = stored, lower <= upper else { return nil }
        return lower...upper
    }

    public static func control(for param: Param<ClosedRange<Double>>) -> ParamControl {
        .range(.init(outer: param.constraints.outer, style: param.constraints.style,
                     read: { param.wrappedValue }, write: { param.wrappedValue = $0 }))
    }
}

extension String: ParamValue {
    public typealias Constraints = Void
    public static func clamped(_ value: String, by _: Void) -> String { value }
    public static func stored(_ value: String) -> ParamStored { .text(value) }
    public static func restored(_ stored: ParamStored) -> String? {
        guard case .text(let value) = stored else { return nil }
        return value
    }
    public static func control(for param: Param<String>) -> ParamControl {
        .text(.init(read: { param.wrappedValue }, write: { param.wrappedValue = $0 }))
    }
}

extension Palette: ParamValue {
    public typealias Constraints = ParamSwatchConstraints

    /// Colors past the upper bound are dropped from the end. A palette shorter
    /// than the lower bound is left as it is: there is no color to invent, and
    /// the bound is there to stop the row's remove button, not to pad a value
    /// the sketch set for itself.
    public static func clamped(_ value: Palette, by constraints: Constraints) -> Palette {
        guard value.count > constraints.count.upperBound else { return value }
        return Palette(Array(value.colors.prefix(constraints.count.upperBound)))
    }

    public static func stored(_ value: Palette) -> ParamStored {
        let positions = evenPositions(value.count)
        return .colors(stops: zip(positions, value.colors).map { ParamColorStop(position: $0, color: $1) },
                       space: nil)
    }

    public static func restored(_ stored: ParamStored) -> Palette? {
        guard case .colors(let stops, _) = stored else { return nil }
        return Palette(stops.map(\.color))
    }

    public static func control(for param: Param<Palette>) -> ParamControl {
        .swatches(.init(
            style: .blocks, count: param.constraints.count,
            sample: { param.wrappedValue.color(at: $0) },
            read: {
                let palette = param.wrappedValue
                return zip(evenPositions(palette.count), palette.colors)
                    .map { ParamControl.Swatches.Stop(position: $0, color: $1) }
            },
            write: { param.wrappedValue = Palette($0.map(\.color)) }))
    }
}

extension Ramp: ParamValue {
    public typealias Constraints = ParamSwatchConstraints

    /// Stops past the upper bound are dropped from the end, the same way a
    /// palette's colors are.
    public static func clamped(_ value: Ramp, by constraints: Constraints) -> Ramp {
        guard value.stops.count > constraints.count.upperBound else { return value }
        return Ramp(stops: value.stops.prefix(constraints.count.upperBound)
                        .map { (position: $0.position, color: $0.color) },
                    in: value.space)
    }

    public static func stored(_ value: Ramp) -> ParamStored {
        .colors(stops: value.stops.map { ParamColorStop(position: $0.position, color: $0.color) },
                space: value.space.paramName)
    }

    /// A palette's payload restores too (it carries no space), so a knob that
    /// changed from one to the other keeps its colors.
    public static func restored(_ stored: ParamStored) -> Ramp? {
        guard case .colors(let stops, let space) = stored else { return nil }
        return Ramp(stops: stops.map { (position: $0.position, color: $0.color) },
                    in: space.flatMap(ColorSpace.init(paramName:)) ?? .oklab)
    }

    public static func control(for param: Param<Ramp>) -> ParamControl {
        .swatches(.init(
            style: .gradient, count: param.constraints.count,
            sample: { param.wrappedValue.color(at: $0) },
            read: {
                param.wrappedValue.stops.map {
                    ParamControl.Swatches.Stop(position: $0.position, color: $0.color)
                }
            },
            write: { stops in
                param.wrappedValue = Ramp(stops: stops.map { (position: $0.position, color: $0.color) },
                                          in: param.wrappedValue.space)
            }))
    }
}

private extension ColorSpace {
    /// The name a ramp knob persists its blending space under. Stable: a
    /// renamed key forgets a tuned ramp's space.
    var paramName: String {
        switch self {
        case .rgb: "rgb"
        case .hsb: "hsb"
        case .oklab: "oklab"
        case .oklch: "oklch"
        case .okhsl: "okhsl"
        case .paint: "paint"
        }
    }

    init?(paramName: String) {
        switch paramName {
        case "rgb": self = .rgb
        case "hsb": self = .hsb
        case "oklab": self = .oklab
        case "oklch": self = .oklch
        case "okhsl": self = .okhsl
        case "paint": self = .paint
        default: return nil
        }
    }
}

/// An enum a `@Param` can hold: the inspector shows its cases as a pop-up menu.
/// Declare the enum `CaseIterable` and conform:
///
/// ```swift
/// enum Style: String, CaseIterable, ParamOption { case dots, rings, mesh }
/// @Param var style: Style = .dots
/// ```
///
/// The menu shows each case under `optionLabel`, which defaults to the
/// humanized case name (`linearBurn` reads "Linear Burn"); override it for
/// custom wording. Persistence keys on the case *name*, so renaming a case
/// forgets a tuned selection (reordering is safe).
public protocol ParamOption: ParamValue, CaseIterable where Constraints == ParamMenuStyle {
    /// The name the inspector menu shows for this case.
    var optionLabel: String { get }
}

public extension ParamOption {
    var optionLabel: String { ParamHandle.humanize(String(describing: self)) }

    static func clamped(_ value: Self, by _: ParamMenuStyle) -> Self { value }

    static func stored(_ value: Self) -> ParamStored { .option(String(describing: value)) }

    static func restored(_ stored: ParamStored) -> Self? {
        guard case .option(let name) = stored else { return nil }
        return allCases.first { String(describing: $0) == name }
    }

    static func control(for param: Param<Self>) -> ParamControl {
        let cases = Array(allCases)
        return .menu(.init(options: cases.map { $0.optionLabel }, style: param.constraints,
                           read: { cases.firstIndex(of: param.wrappedValue) ?? 0 },
                           write: { index in
                               guard cases.indices.contains(index) else { return }
                               param.wrappedValue = cases[index]
                           }))
    }
}

/// A catalog type a `@Param` can hold: not an enum, but a set of *named
/// choices* the inspector shows as a pop-up menu. The fit for a struct with a
/// fixed roster of built-ins. The type's `Equatable` lets the menu find the
/// current choice; a value that matches no choice reads as the first entry,
/// and persistence keys on the choice name.
///
/// ```swift
/// @Param var mood: LightingPreset = .standard   // a built-in conformer
/// ```
public protocol ParamChoices: ParamValue where Constraints == ParamMenuStyle {
    /// The menu's roster, in display order. Names are humanized for display
    /// ("goldenHour" reads "Golden Hour") and used as-is for persistence.
    static var paramChoices: [(name: String, value: Self)] { get }
}

public extension ParamChoices {
    static func clamped(_ value: Self, by _: ParamMenuStyle) -> Self { value }

    static func stored(_ value: Self) -> ParamStored {
        .option(paramChoices.first { $0.value == value }?.name ?? paramChoices.first?.name ?? "")
    }

    static func restored(_ stored: ParamStored) -> Self? {
        guard case .option(let name) = stored else { return nil }
        return paramChoices.first { $0.name == name }?.value
    }

    static func control(for param: Param<Self>) -> ParamControl {
        let choices = paramChoices
        return .menu(.init(options: choices.map { ParamHandle.humanize($0.name) },
                           style: param.constraints,
                           read: {
                               let current = param.wrappedValue
                               return choices.firstIndex { $0.value == current } ?? 0
                           },
                           write: { index in
                               guard choices.indices.contains(index) else { return }
                               param.wrappedValue = choices[index].value
                           }))
    }
}

// MARK: Built-in options

// Ollin's own CaseIterable mode enums make natural knobs, so they conform out
// of the box: `@Param var blend: BlendMode = .normal` gets a menu for free.
extension BlendMode: ParamOption {}
extension StrokeCap: ParamOption {}
extension StrokeJoin: ParamOption {}
extension Colormap: ParamOption {}
extension Turmite.Preset: ParamOption {}
extension RenderQuality: ParamOption {}
extension WFCSymmetry: ParamOption {}
extension RenderingIntent: ParamOption {}

// The curated-preset structs join through the named-choices tier. The
// parameterized Material helpers (`.glass(...)`, `.metal(...)`, `.skin(radius:)`)
// stay off the menu: a menu needs fixed values, so pick the nearest built-in
// and turn the knobs from there.
extension Material: ParamChoices {
    public static var paramChoices: [(name: String, value: Material)] {
        [("matte", .matte), ("clay", .clay), ("rubber", .rubber),
         ("plastic", .plastic), ("ceramic", .ceramic), ("glossy", .glossy),
         ("polished", .polished), ("toon", .toon), ("gooch", .gooch),
         ("iridescent", .iridescent), ("soapBubble", .soapBubble),
         ("oilSlick", .oilSlick), ("beetle", .beetle), ("glitter", .glitter),
         ("sequin", .sequin), ("velvet", .velvet), ("jade", .jade), ("wax", .wax),
         ("brushedMetal", .brushedMetal), ("polishedMetal", .polishedMetal),
         ("smoothPlastic", .smoothPlastic), ("roughPlastic", .roughPlastic),
         ("frostedGlass", .frostedGlass), ("clearGlass", .clearGlass),
         ("gummy", .gummy), ("lacquer", .lacquer),
         ("satin", .satin), ("felt", .felt),
         ("anodized", .anodized), ("oilOnWater", .oilOnWater), ("nacre", .nacre)]
    }
}

extension LightingPreset: ParamChoices {
    public static var paramChoices: [(name: String, value: LightingPreset)] {
        [("standard", .standard), ("threePoint", .threePoint), ("goldenHour", .goldenHour),
         ("noir", .noir), ("studio", .studio), ("moonlight", .moonlight)]
    }
}

// The shaping curves join the same tier: each built-in carries its own name,
// which is what lets the menu find the current one and persist it. A curve
// built from a closure is not on the menu, so the row reads as the first
// entry, and a reload restores that rather than the closure.
extension Easing: ParamChoices {
    public static var paramChoices: [(name: String, value: Easing)] { Easing.all }
}

// MARK: - The wrapper

/// A tunable parameter the live host surfaces as an inspector control. Declare
/// it on a sketch and read it like a normal property; the live host discovers
/// it, shows the control that matches its type, and persists its value across
/// reloads.
///
/// ```swift
/// final class Pulse: Sketch {
///     @Param(0...200) var radius = 120.0                // slider, label "Radius"
///     @Param("Speed", 0.1...4) var rate = 1.0           // slider, explicit label
///     @Param(1...12) var rings = 5                      // Int: stepper
///     @Param var filled = true                          // Bool: toggle
///     @Param var tint: Color = .purple                  // Color: color well
///     @Param var style: Style = .dots                   // ParamOption enum: menu
///     @Param(x: 0...1080, y: 0...1080)
///     var center = Vector2(540, 540)                    // Vector2: x/y fields
/// }
/// ```
///
/// Every form takes an optional `icon:` (an SF Symbol name shown leading the
/// row) and `group:` (a section name; the inspector renders each group as its
/// own titled card, in declaration order):
///
/// ```swift
/// @Param(0...1, icon: "circle.dashed", group: "Shape") var wobble = 0.4
/// ```
///
/// A numeric value is always clamped to its range (and snapped to `step:` when
/// given). Pass a label to override the one derived from the property name.
///
/// The value is safe to read and write from any thread: the live inspector
/// drives it from the main thread, and an external control source (a hardware
/// fader, a networked message) may drive the same knob from its own thread, so
/// the storage is guarded by a lock and the type is `Sendable`.
@propertyWrapper
public final class Param<Value: ParamValue>: @unchecked Sendable, FrameAdvancing {
    /// The value plus its glide state, kept together behind one lock. The glide
    /// fields only move for a smoothed `Double` parameter.
    private struct Storage: Sendable {
        var current: Value                   // the (possibly gliding) value reads return
        var target: Value                    // what `current` is easing toward
        var easeStart: Double                // `current` when the target was last set (`.eased`)
        var easeElapsed: Double              // seconds into the current `.eased` glide
        var filter: OneEuroFilter<Double>?   // `.smoothed` state, nil otherwise
    }
    private let storage: OSAllocatedUnfairLock<Storage>

    /// The show-rule, type-erased over its source knob, or `nil` while the row
    /// always shows. Behind its own lock: `setup()` writes it once, and the
    /// inspector reads it on the main thread while the value lock stays busy.
    private let showRule = OSAllocatedUnfairLock<(@Sendable () -> Bool)?>(initialState: nil)

    /// The value kind's constraint payload: the range and optional step for a
    /// numeric parameter, `Void` for the kinds that need none.
    public let constraints: Value.Constraints
    /// An explicit display label, or `nil` to derive one from the property name.
    public let label: String?
    /// An SF Symbol name the inspector shows leading the row, or `nil` for none.
    public let icon: String?
    /// The inspector section this knob belongs to, or `nil` for the default group.
    public let group: String?
    /// How the value eases into changes, or `nil` for an immediate snap.
    /// Only the `Double` initializers offer smoothing.
    public let smoothing: ParamSmoothing?

    /// The current value (the gliding one when smoothed); assigning sets a new
    /// target the value eases toward (or snaps to, with no smoothing).
    public var wrappedValue: Value {
        get { storage.withLock { Value.clamped($0.current, by: constraints) } }
        set { retarget(newValue) }
    }

    /// The parameter itself, via `$radius`, handy for passing it around.
    public var projectedValue: Param<Value> { self }

    init(_ value: Value, label: String?, constraints: Value.Constraints,
         smoothing: ParamSmoothing?, icon: String?, group: String?) {
        self.constraints = constraints
        self.label = label
        self.icon = icon
        self.group = group
        self.smoothing = smoothing
        let v = Value.clamped(value, by: constraints)
        var filter: OneEuroFilter<Double>?
        if case .smoothed(let minCutoff, let beta) = smoothing {
            var f = OneEuroFilter<Double>(minCutoff: minCutoff, beta: beta)
            f.set((v as? Double) ?? 0)
            filter = f
        }
        self.storage = OSAllocatedUnfairLock(initialState: Storage(
            current: v, target: v, easeStart: (v as? Double) ?? 0,
            easeElapsed: .greatestFiniteMagnitude, filter: filter))
    }

    /// Jump straight to `value` with no glide (both the value and the target), and
    /// reseat any filter so it continues from there. Used for direct restores,
    /// like the live host re-applying a tuned value across a reload, where
    /// animating in from the default would be wrong.
    public func set(_ value: Value) {
        let v = Value.clamped(value, by: constraints)
        storage.withLock { state in
            state.current = v
            state.target = v
            state.easeStart = (v as? Double) ?? 0
            state.easeElapsed = .greatestFiniteMagnitude   // at rest
            state.filter?.set((v as? Double) ?? 0)
        }
    }

    /// Show this knob's inspector row only while `rule` passes for `other`'s
    /// current value. While the rule fails, the row leaves the inspector, and a
    /// group whose rows are all hidden drops its whole card. The value itself is
    /// untouched: a hidden knob still holds, persists, and restores its value,
    /// and any OSC/MIDI binding keeps driving it.
    ///
    /// Set the rule in `setup()`, reaching both knobs through `$`:
    ///
    /// ```swift
    /// override func setup() {
    ///     $toonBands.show(when: $shading) { $0 == .toon }
    ///     $ior.show(when: $transmission) { $0 > 0 }
    /// }
    /// ```
    ///
    /// The rule captures the other parameter, never the sketch, so a live reload
    /// swaps both out together. Calling this again replaces the rule.
    public func show<Other: ParamValue>(when other: Param<Other>,
                                        _ rule: @escaping @Sendable (Other) -> Bool) {
        showRule.withLock { $0 = { rule(other.wrappedValue) } }
    }

    /// Whether the inspector should show this knob's row right now: `true`
    /// unless a `show(when:_:)` rule is set and currently fails.
    public var isShown: Bool {
        guard let rule = showRule.withLock({ $0 }) else { return true }
        return rule()
    }

    /// Set a new target. With no smoothing the value snaps; otherwise it begins
    /// gliding from wherever it is now. Assigning the value it's already heading
    /// for is a no-op, so it's safe to drive every frame (a knob repeating its
    /// last position won't restart the glide).
    private func retarget(_ value: Value) {
        let v = Value.clamped(value, by: constraints)
        storage.withLock { state in
            guard v != state.target else { return }
            state.target = v
            if smoothing == nil {
                state.current = v
            } else {
                state.easeStart = (state.current as? Double) ?? 0
                state.easeElapsed = 0
            }
        }
    }

    /// Step the glide one frame. A no-op for un-smoothed params. Called by the
    /// sketch each frame, the same pass that advances `@Eased` / `@Smoothed`.
    /// Smoothing is only offered by the `Double` initializers, so a smoothed
    /// parameter always holds a `Double` and the casts below can't fail.
    package func advance(by dt: Double) {
        guard let smoothing else { return }
        storage.withLock { state in
            guard let target = state.target as? Double else { return }
            switch smoothing {
            case .eased(let duration, let curve):
                guard duration > 0, state.easeElapsed < duration else {
                    state.current = state.target
                    return
                }
                state.easeElapsed += dt
                let t = Swift.min(state.easeElapsed / duration, 1)
                let value = state.easeStart + (target - state.easeStart) * curve(t)
                if let v = value as? Value { state.current = v }
            case .smoothed:
                if var filter = state.filter {
                    let value = filter.filter(target, deltaTime: dt)
                    state.filter = filter
                    if let v = value as? Value { state.current = v }
                }
            }
        }
    }
}

// MARK: Per-kind initializers

public extension Param where Value == Double {
    /// A `Double` knob over `range`, optionally snapped to `step`. The default
    /// presentation is a slider; `style: .field` keeps just the value field.
    convenience init(wrappedValue: Double, _ range: ClosedRange<Double>, step: Double? = nil,
                     style: ParamNumericStyle = .slider, smoothing: ParamSmoothing? = nil,
                     icon: String? = nil, group: String? = nil) {
        self.init(wrappedValue, label: nil, constraints: .init(range: range, step: step, style: style),
                  smoothing: smoothing, icon: icon, group: group)
    }

    convenience init(wrappedValue: Double, _ label: String, _ range: ClosedRange<Double>,
                     step: Double? = nil, style: ParamNumericStyle = .slider,
                     smoothing: ParamSmoothing? = nil,
                     icon: String? = nil, group: String? = nil) {
        self.init(wrappedValue, label: label, constraints: .init(range: range, step: step, style: style),
                  smoothing: smoothing, icon: icon, group: group)
    }

    /// The allowed range; the value is clamped to it. (The mapping target for
    /// OSC and MIDI bindings.)
    var range: ClosedRange<Double> { constraints.range }
}

public extension Param where Value == Int {
    /// An `Int` stepper over `range`, stepping by `step` (default 1).
    convenience init(wrappedValue: Int, _ range: ClosedRange<Int>, step: Int? = nil,
                     icon: String? = nil, group: String? = nil) {
        self.init(wrappedValue, label: nil, constraints: .init(range: range, step: step),
                  smoothing: nil, icon: icon, group: group)
    }

    convenience init(wrappedValue: Int, _ label: String, _ range: ClosedRange<Int>,
                     step: Int? = nil, icon: String? = nil, group: String? = nil) {
        self.init(wrappedValue, label: label, constraints: .init(range: range, step: step),
                  smoothing: nil, icon: icon, group: group)
    }

    /// The allowed range; the value is clamped to it.
    var range: ClosedRange<Int> { constraints.range }
}

public extension Param where Value == Bool {
    /// A `Bool` toggle.
    convenience init(wrappedValue: Bool, icon: String? = nil, group: String? = nil) {
        self.init(wrappedValue, label: nil, constraints: (), smoothing: nil, icon: icon, group: group)
    }

    convenience init(wrappedValue: Bool, _ label: String, icon: String? = nil, group: String? = nil) {
        self.init(wrappedValue, label: label, constraints: (), smoothing: nil, icon: icon, group: group)
    }
}

public extension Param where Value == Color {
    /// A `Color` well.
    convenience init(wrappedValue: Color, icon: String? = nil, group: String? = nil) {
        self.init(wrappedValue, label: nil, constraints: (), smoothing: nil, icon: icon, group: group)
    }

    convenience init(wrappedValue: Color, _ label: String, icon: String? = nil, group: String? = nil) {
        self.init(wrappedValue, label: label, constraints: (), smoothing: nil, icon: icon, group: group)
    }
}

public extension Param where Value == Vector2 {
    /// A `Vector2` point: paired x/y fields, each clamped to its own range.
    /// `style: .pad` adds a draggable XY pad under the fields.
    convenience init(wrappedValue: Vector2, x: ClosedRange<Double>, y: ClosedRange<Double>,
                     style: ParamVectorStyle = .fields,
                     icon: String? = nil, group: String? = nil) {
        self.init(wrappedValue, label: nil, constraints: .init(x: x, y: y, style: style),
                  smoothing: nil, icon: icon, group: group)
    }

    convenience init(wrappedValue: Vector2, _ label: String,
                     x: ClosedRange<Double>, y: ClosedRange<Double>,
                     style: ParamVectorStyle = .fields,
                     icon: String? = nil, group: String? = nil) {
        self.init(wrappedValue, label: label, constraints: .init(x: x, y: y, style: style),
                  smoothing: nil, icon: icon, group: group)
    }
}

public extension Param where Value == Vector3 {
    /// A `Vector3` point: x/y/z fields, each clamped to its own range.
    convenience init(wrappedValue: Vector3, x: ClosedRange<Double>, y: ClosedRange<Double>,
                     z: ClosedRange<Double>, icon: String? = nil, group: String? = nil) {
        self.init(wrappedValue, label: nil, constraints: .init(x: x, y: y, z: z),
                  smoothing: nil, icon: icon, group: group)
    }

    convenience init(wrappedValue: Vector3, _ label: String,
                     x: ClosedRange<Double>, y: ClosedRange<Double>, z: ClosedRange<Double>,
                     icon: String? = nil, group: String? = nil) {
        self.init(wrappedValue, label: label, constraints: .init(x: x, y: y, z: z),
                  smoothing: nil, icon: icon, group: group)
    }
}

public extension Param where Value: ParamOption {
    /// An enum menu over the type's cases; `style: .segmented` shows every
    /// case at once (best for two to four short names).
    convenience init(wrappedValue: Value, style: ParamMenuStyle = .menu,
                     icon: String? = nil, group: String? = nil) {
        self.init(wrappedValue, label: nil, constraints: style, smoothing: nil, icon: icon, group: group)
    }

    convenience init(wrappedValue: Value, _ label: String, style: ParamMenuStyle = .menu,
                     icon: String? = nil, group: String? = nil) {
        self.init(wrappedValue, label: label, constraints: style, smoothing: nil, icon: icon, group: group)
    }
}

public extension Param where Value: ParamChoices {
    /// A menu over the type's named choices; `style: .segmented` shows every
    /// choice at once (best for two to four short names).
    convenience init(wrappedValue: Value, style: ParamMenuStyle = .menu,
                     icon: String? = nil, group: String? = nil) {
        self.init(wrappedValue, label: nil, constraints: style, smoothing: nil, icon: icon, group: group)
    }

    convenience init(wrappedValue: Value, _ label: String, style: ParamMenuStyle = .menu,
                     icon: String? = nil, group: String? = nil) {
        self.init(wrappedValue, label: label, constraints: style, smoothing: nil, icon: icon, group: group)
    }
}

public extension Param where Value == Rectangle {
    /// A `Rectangle` region: x/y/w/h fields, each clamped to its own range.
    convenience init(wrappedValue: Rectangle, x: ClosedRange<Double>, y: ClosedRange<Double>,
                     width: ClosedRange<Double>, height: ClosedRange<Double>,
                     icon: String? = nil, group: String? = nil) {
        self.init(wrappedValue, label: nil,
                  constraints: .init(x: x, y: y, width: width, height: height),
                  smoothing: nil, icon: icon, group: group)
    }

    convenience init(wrappedValue: Rectangle, _ label: String,
                     x: ClosedRange<Double>, y: ClosedRange<Double>,
                     width: ClosedRange<Double>, height: ClosedRange<Double>,
                     icon: String? = nil, group: String? = nil) {
        self.init(wrappedValue, label: label,
                  constraints: .init(x: x, y: y, width: width, height: height),
                  smoothing: nil, icon: icon, group: group)
    }
}

public extension Param where Value == Insets {
    /// Per-edge insets: t/r/b/l fields, each clamped to the one shared range.
    convenience init(wrappedValue: Insets, _ range: ClosedRange<Double>,
                     icon: String? = nil, group: String? = nil) {
        self.init(wrappedValue, label: nil, constraints: range,
                  smoothing: nil, icon: icon, group: group)
    }

    convenience init(wrappedValue: Insets, _ label: String, _ range: ClosedRange<Double>,
                     icon: String? = nil, group: String? = nil) {
        self.init(wrappedValue, label: label, constraints: range,
                  smoothing: nil, icon: icon, group: group)
    }
}

public extension Param where Value == ClosedRange<Double> {
    /// A min/max pair, both ends kept ordered and inside `outer`, edited on a
    /// two-thumb slider (`style: .field` keeps just the paired fields).
    convenience init(wrappedValue: ClosedRange<Double>, in outer: ClosedRange<Double>,
                     style: ParamNumericStyle = .slider,
                     icon: String? = nil, group: String? = nil) {
        self.init(wrappedValue, label: nil, constraints: .init(outer: outer, style: style),
                  smoothing: nil, icon: icon, group: group)
    }

    convenience init(wrappedValue: ClosedRange<Double>, _ label: String,
                     in outer: ClosedRange<Double>, style: ParamNumericStyle = .slider,
                     icon: String? = nil, group: String? = nil) {
        self.init(wrappedValue, label: label, constraints: .init(outer: outer, style: style),
                  smoothing: nil, icon: icon, group: group)
    }
}

public extension Param where Value == Palette {
    /// A palette of colors: a strip of blocks, each opened in its own color
    /// well. `count:` bounds how many the strip holds, which is where the
    /// row's add and remove buttons stop.
    convenience init(wrappedValue: Palette, count: ClosedRange<Int> = 1...12,
                     icon: String? = nil, group: String? = nil) {
        self.init(wrappedValue, label: nil, constraints: .init(count: count, style: .blocks),
                  smoothing: nil, icon: icon, group: group)
    }

    convenience init(wrappedValue: Palette, _ label: String, count: ClosedRange<Int> = 1...12,
                     icon: String? = nil, group: String? = nil) {
        self.init(wrappedValue, label: label, constraints: .init(count: count, style: .blocks),
                  smoothing: nil, icon: icon, group: group)
    }
}

public extension Param where Value == Ramp {
    /// A gradient: one blended band with a handle per stop, each opened in its
    /// own color well and dragged along the band. The ramp keeps the space it
    /// blends through; only its stops are edited here.
    convenience init(wrappedValue: Ramp, count: ClosedRange<Int> = 2...8,
                     icon: String? = nil, group: String? = nil) {
        self.init(wrappedValue, label: nil, constraints: .init(count: count, style: .gradient),
                  smoothing: nil, icon: icon, group: group)
    }

    convenience init(wrappedValue: Ramp, _ label: String, count: ClosedRange<Int> = 2...8,
                     icon: String? = nil, group: String? = nil) {
        self.init(wrappedValue, label: label, constraints: .init(count: count, style: .gradient),
                  smoothing: nil, icon: icon, group: group)
    }
}

public extension Param where Value == String {
    /// A free text field.
    convenience init(wrappedValue: String, icon: String? = nil, group: String? = nil) {
        self.init(wrappedValue, label: nil, constraints: (), smoothing: nil, icon: icon, group: group)
    }

    convenience init(wrappedValue: String, _ label: String, icon: String? = nil, group: String? = nil) {
        self.init(wrappedValue, label: label, constraints: (), smoothing: nil, icon: icon, group: group)
    }
}

// MARK: - Discovery

/// The type-erased face of a `Param`, whatever its value kind: the display
/// metadata, the inspector control, and the persistence round-trip. The live
/// hosts drive parameters entirely through this.
public protocol AnyParam: AnyObject, Sendable {
    /// An explicit display label, or `nil` to derive one from the property name.
    var label: String? { get }
    /// An SF Symbol name shown leading the inspector row, or `nil` for none.
    var icon: String? { get }
    /// The inspector section this knob belongs to, or `nil` for the default group.
    var group: String? { get }
    /// The inspector control that edits this parameter (metadata + live get/set).
    var control: ParamControl { get }
    /// Whether the inspector should show this parameter's row right now: `true`
    /// unless a show-rule (`Param.show(when:_:)`) is set and currently fails.
    var isShown: Bool { get }
    /// The current value in its host-persistable form.
    var stored: ParamStored { get }
    /// Jump straight to a persisted value with no glide; a payload of the wrong
    /// kind is ignored. Used by the hosts to re-apply tuned values on reload.
    func restore(_ stored: ParamStored)
}

extension Param: AnyParam {
    public var control: ParamControl { Value.control(for: self) }
    public var stored: ParamStored { Value.stored(wrappedValue) }
    public func restore(_ stored: ParamStored) {
        guard let value = Value.restored(stored) else { return }
        set(value)
    }
}

/// A discovered `@Param` on a sketch: its persistence key (the property name),
/// the parameter itself (type-erased), and its display metadata. The live host
/// builds one inspector row per handle.
public struct ParamHandle: Identifiable {
    /// The property name, a stable key for persisting the value across reloads.
    public let name: String
    public let param: any AnyParam
    public var id: String { name }
    public var label: String { param.label ?? ParamHandle.humanize(name) }
    public var icon: String? { param.icon }
    public var group: String? { param.group }
    public var control: ParamControl { param.control }
    /// Whether the row belongs in the inspector right now (see `Param.show(when:_:)`).
    public var isShown: Bool { param.isShown }

    /// "radius" -> "Radius", "noiseScale" -> "Noise Scale".
    static func humanize(_ name: String) -> String {
        var words: [String] = []
        var current = ""
        for character in name {
            if character.isUppercase, !current.isEmpty {
                words.append(current)
                current = ""
            }
            current.append(character)
        }
        if !current.isEmpty { words.append(current) }
        return words.map { $0.prefix(1).uppercased() + $0.dropFirst() }.joined(separator: " ")
    }
}

public extension Sketch {
    /// The `@Param` parameters declared on this sketch, discovered via reflection
    /// (walking the class hierarchy). The live host uses this to build the
    /// inspector; most sketches never call it directly.
    func parameters() -> [ParamHandle] {
        var handles: [ParamHandle] = []
        var mirror: Mirror? = Mirror(reflecting: self)
        while let current = mirror {
            for child in current.children {
                guard let param = child.value as? any AnyParam, let storageName = child.label else { continue }
                // Property-wrapper storage is named `_radius`; strip the underscore.
                let name = storageName.hasPrefix("_") ? String(storageName.dropFirst()) : storageName
                handles.append(ParamHandle(name: name, param: param))
            }
            mirror = current.superclassMirror
        }
        return handles
    }
}
