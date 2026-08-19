import CoreGraphics
import Metal

/// How much color a finished frame is allowed to carry on its way out of the
/// sketch.
///
/// The canvas already composites in a linear, floating-point intermediate, so a
/// frame holds far more color than an ordinary screen shows: components can run
/// past 1.0 where light piles up, and they carry more precision than eight bits
/// per channel. All of that is thrown away at the very last step, where the
/// frame is encoded for an 8-bit sRGB display. This setting decides how much of
/// it survives instead.
///
/// - `standard` keeps today's behavior exactly: 8-bit sRGB, dithered at the
///   quantization. Every sketch that says nothing gets this.
/// - `wide` presents through Display P3 in a floating-point drawable. Two things
///   change: colors named outside sRGB (see `Color(displayP3:green:blue:)`)
///   survive to the screen instead of clipping, and smooth gradients stop
///   banding, because nothing is quantized to eight bits on the way.
/// - `extended` adds the other axis: values above 1.0 stay above 1.0, and a
///   display with headroom shows them *brighter than white* rather than
///   clipping them to it. A video exported from an `extended` sketch is written
///   as HDR10.
///
/// It's declared, not called, because the window's drawable is built once from
/// it:
///
/// ```swift
/// final class Glow: Sketch {
///     override var colorOutput: ColorOutput { .extended }
/// }
/// ```
///
/// **Brightness above white.** In `extended`, 1.0 is paper white (whatever the
/// display's brightness makes it) and higher values are highlights above it.
/// How far above depends on the screen: a display reporting 2x headroom shows
/// up to 2.0 and clips past that. So `extended` is worth reaching for when a
/// sketch *makes* values above 1 (additive blending, a bloom, accumulated
/// light); it does nothing for a frame that never leaves 0…1.
///
/// **Tone-mapping and `extended` pull against each other.** `ToneMap.reinhard`
/// and `.aces` exist to squeeze out-of-range values into 0…1 for an ordinary
/// screen, which is precisely what an HDR display does not need. Leave the
/// tone-map at its `.clamp` default here and the highlights keep their
/// brightness; set a curve and they are compressed back to white before the
/// display ever sees them.
public enum ColorOutput: String, Hashable, Sendable, CaseIterable {

    /// 8-bit sRGB, dithered at the quantization (the default). What every
    /// screen, image, and video player handles without a thought.
    case standard

    /// Display P3 through a floating-point drawable: colors outside sRGB reach
    /// the screen, and gradients stop banding. Still 0…1, so nothing is
    /// brighter than white.
    case wide

    /// Display P3 *and* brightness above white: values over 1.0 are shown as
    /// highlights on a display with headroom, and an exported video is HDR10.
    case extended

    /// Whether the frame keeps values above 1.0 on its way to the display.
    public var isHighDynamicRange: Bool { self == .extended }
}

extension ColorOutput {

    /// The drawable/display texture format. `standard` keeps the 8-bit sRGB
    /// target (so its whole path stays byte-identical); the other two present
    /// through the same float format the canvas already composites in, which is
    /// what carries both the wider gamut and the values above 1.
    var drawablePixelFormat: MTLPixelFormat {
        self == .standard ? .bgra8Unorm_srgb : .rgba16Float
    }

    /// The color space the presented pixels are in. `standard` leaves it nil,
    /// since the drawable's own sRGB format already says it. The float paths
    /// say it out loud, because a float drawable carries no encoding of its own.
    var displayColorSpace: CGColorSpace? {
        switch self {
        case .standard: nil
        case .wide, .extended: CGColorSpace(name: CGColorSpace.extendedLinearDisplayP3)
        }
    }

    /// Whether the layer asks the system for brightness above SDR white. Only
    /// `extended` does; `wide` is a gamut change, not a range one.
    var wantsExtendedDynamicRange: Bool { self == .extended }

    /// How the present pass encodes for this output.
    var presentEncoding: PresentEncoding {
        switch self {
        case .standard: .srgb8
        case .wide: .linearDisplayP3
        case .extended: .linearDisplayP3Extended
        }
    }

    /// The ceiling the present pass clamps to, given the display's current
    /// headroom. `wide` is standard-range, so it stops at white whatever the
    /// screen can do.
    func ceiling(displayHeadroom: Float) -> Float {
        self == .extended ? max(1, displayHeadroom) : 1
    }
}

/// What the present pass writes: the encoding the destination texture expects.
/// A renderer is built for one of these and carries it for its lifetime, the
/// way it carries its pixel format.
enum PresentEncoding: Int32 {
    /// 8-bit sRGB, dithered: the shipped path, and the only one that runs
    /// `ollin_present_fragment`.
    case srgb8 = 0
    /// Linear Display P3 into a float target, standard range: the wide-gamut
    /// screen and still read-back, which stop at white.
    case linearDisplayP3 = 1
    /// Rec. 2020 primaries, PQ-encoded (SMPTE ST 2084) into a float target: the
    /// form an HDR10 video encoder is handed.
    case pqRec2020 = 2
    /// The same linear Display P3, but keeping values above white. The shader
    /// treats it exactly like `linearDisplayP3`; what differs is the ceiling the
    /// renderer starts at, unbounded here and pulled down to the display's real
    /// headroom by a live host. Off-screen there is no display to ask, and
    /// stopping at white would quietly throw away the highlights an extended
    /// frame exists for.
    case linearDisplayP3Extended = 3

    /// Whether this encoding writes into the float display texture (both the
    /// Display P3 forms and the PQ one do).
    var isFloat: Bool { self != .srgb8 }
}

public extension ColorOutput {

    /// The luminance 1.0 stands for when a frame is written as HDR video, in
    /// candelas per square meter. 203 is the standard's own reference white
    /// (ITU-R BT.2408), which is what makes an exported clip's paper white land
    /// where every other HDR video's does.
    static let referenceWhiteNits: Double = 203

    /// The brightest highlight an exported HDR video carries, in candelas per
    /// square meter, about 4.9x white. Values above it are clipped, and the
    /// figure is what the file declares it was mastered for.
    static let peakNits: Double = 1000
}
