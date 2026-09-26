import Foundation

/// A nominal frame rate: how many frames an export writes, or a headless clock
/// steps, in one second.
///
/// A plain number stands in for one wherever a rate is expected, so `fps: 60`
/// and `fps: 24` read as they always did. The named rates are the ones whose
/// number is awkward to type and easy to get slightly wrong: broadcast's
/// fractional rates are exact fractions here (`.ntsc` is 30000/1001, not
/// 29.97), so a video's frame timestamps land on the grid a player expects.
///
/// ```swift
/// try OllinApp.exportVideo(sketch, to: "clip.mp4", frames: 300, fps: 24)
/// try OllinApp.exportVideo(sketch, to: "clip.mp4", frames: 300, fps: .ntsc)
///
/// let rate: FrameRate = .film
/// rate.framesPerSecond     // 24
/// rate.frameDuration       // 1/24 of a second
/// rate.frames(in: 2.5)     // 60
/// ```
///
/// The rate is kept as a fraction, `frames` in `seconds`, reduced to lowest
/// terms. A decimal becomes the fraction that spells it to a thousandth
/// (`FrameRate(29.97)` is 2997/100), which is a different rate from `.ntsc`
/// by one part in a million; name the broadcast rate when that is the one you
/// mean.
public struct FrameRate: Hashable, Sendable, CustomStringConvertible,
                         ExpressibleByIntegerLiteral, ExpressibleByFloatLiteral {
    /// The numerator of the rate: this many frames in `seconds` seconds.
    public let frames: Int
    /// The denominator of the rate: `frames` frames take this many seconds.
    public let seconds: Int

    /// A rate of `frames` frames every `seconds` seconds, reduced to lowest
    /// terms: `FrameRate(30000, per: 1001)` is the exact NTSC rate, and
    /// `FrameRate(60, per: 2)` is the same value as `30`. A denominator of
    /// zero or below is taken as one.
    public init(_ frames: Int, per seconds: Int) {
        let f = max(0, frames)
        let s = max(1, seconds)
        let g = Self.gcd(f, s)
        self.frames = f / g
        self.seconds = s / g
    }

    /// The rate a decimal spells, to a thousandth of a frame per second: a
    /// whole number stays whole (`FrameRate(24)` is 24/1), and a fraction
    /// becomes the fraction over 1000 that names it, reduced.
    public init(_ framesPerSecond: Double) {
        let fps = framesPerSecond.isFinite ? min(max(0, framesPerSecond), 1_000_000) : 0
        if fps == fps.rounded() {
            self.init(Int(fps), per: 1)
        } else {
            self.init(Int((fps * 1000).rounded()), per: 1000)
        }
    }

    public init(integerLiteral value: Int) { self.init(value, per: 1) }
    public init(floatLiteral value: Double) { self.init(value) }

    // MARK: Named rates

    /// 24 frames per second, the rate of film.
    public static let film = FrameRate(24, per: 1)
    /// 25 frames per second, the rate of PAL and SECAM video.
    public static let pal = FrameRate(25, per: 1)
    /// 30000/1001 frames per second (29.97), the rate of NTSC video and the one
    /// most broadcast delivery still asks for.
    public static let ntsc = FrameRate(30000, per: 1001)
    /// 24000/1001 frames per second (23.976), film slowed for NTSC.
    public static let ntscFilm = FrameRate(24000, per: 1001)
    /// 60000/1001 frames per second (59.94), NTSC at double rate.
    public static let ntscDouble = FrameRate(60000, per: 1001)

    /// The named rate for a name as it is spelled here: `"film"`, `"pal"`,
    /// `"ntsc"`, `"ntscFilm"`, `"ntscDouble"`, case-insensitively. Nothing
    /// else matches; a number is not a name.
    public init?(named name: String) {
        switch name.lowercased() {
        case "film": self = .film
        case "pal": self = .pal
        case "ntsc": self = .ntsc
        case "ntscfilm": self = .ntscFilm
        case "ntscdouble": self = .ntscDouble
        default: return nil
        }
    }

    /// A rate read from text as a flag or a field spells it: a named rate, a
    /// number (`"29.97"`), or a fraction (`"30000/1001"`). `nil` for anything
    /// else, and for a rate of zero or below.
    public init?(parsing text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        if let named = FrameRate(named: trimmed) {
            self = named
        } else if let value = Double(trimmed), value > 0 {
            self.init(value)
        } else {
            let parts = trimmed.split(separator: "/", omittingEmptySubsequences: false)
            guard parts.count == 2, let n = Int(parts[0]), let d = Int(parts[1]),
                  n > 0, d > 0 else { return nil }
            self.init(n, per: d)
        }
    }

    // MARK: Reading it

    /// The rate as a number, `frames / seconds`.
    public var framesPerSecond: Double { Double(frames) / Double(seconds) }

    /// How long one frame lasts, in seconds; infinite for a rate of zero.
    public var frameDuration: Double {
        frames > 0 ? Double(seconds) / Double(frames) : .infinity
    }

    /// How many frames cover `seconds` of time, rounded to the nearest whole
    /// frame: the count an export of that many seconds writes.
    public func frames(in seconds: Double) -> Int {
        Int((seconds * framesPerSecond).rounded())
    }

    /// How long `count` frames last, in seconds.
    public func seconds(for count: Int) -> Double {
        Double(count) * frameDuration
    }

    /// The rate as it is usually said: `60 fps`, `29.97 fps`.
    public var description: String {
        let fps = framesPerSecond
        if fps == fps.rounded() { return "\(Int(fps)) fps" }
        return String(format: "%.2f fps", fps).replacingOccurrences(of: ".00 ", with: " ")
    }

    /// The rate as a media timescale and the tick one frame advances it by,
    /// so frame `k` sits at `k * tick / timescale` exactly on the rate's own
    /// fraction. A fractional rate keeps its own denominator as the tick and
    /// its numerator as the timescale (NTSC is 1001 on 30000, the convention
    /// every broadcast file uses); a whole-number rate takes the thousandfold
    /// clock the exporters always wrote (60 is 1000 on 60000). The writer's
    /// track has to be told this timescale, or it rounds the times onto its
    /// own default and 1001/30000 lands on 1/30.
    var mediaClock: (timescale: Int32, tick: Int64) {
        if seconds == 1 {
            let scaled = frames.multipliedReportingOverflow(by: 1000)
            if !scaled.overflow, scaled.partialValue > 0, scaled.partialValue <= Int(Int32.max) {
                return (Int32(scaled.partialValue), 1000)
            }
        } else if frames > 0, frames <= Int(Int32.max) {
            return (Int32(frames), Int64(seconds))
        }
        return (Int32(clamping: Int((framesPerSecond * 1000).rounded())), 1000)
    }

    private static func gcd(_ a: Int, _ b: Int) -> Int {
        var (x, y) = (a, b)
        while y != 0 { (x, y) = (y, x % y) }
        return max(1, x)
    }
}
