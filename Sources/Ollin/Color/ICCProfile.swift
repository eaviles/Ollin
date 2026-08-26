@preconcurrency import ColorSync
import CoreGraphics
import Foundation

// Print color management, part one: the profile as a value.
//
// A color profile describes what a device actually does with numbers: which
// physical color a monitor emits, or a press lays down on a given paper, for
// every set of components it is handed. The canvas is described by one
// profile (sRGB by default, Display P3 for a wide-gamut sketch) and the press
// by another, and the whole of print color management is the question those
// two profiles answer together: what happens to this artwork on the way to
// that paper?
//
// The profiles here are values, not handles: a name, the ICC bytes, and the
// few header fields worth reading (which color model it speaks, how many
// channels, whether it describes an output device). Everything that needs a
// live profile object builds one from the bytes and caches it, so an
// `ICCProfile` stays `Sendable`, `Hashable`, and cheap to pass around.
//
// The transforms themselves are the system's. ColorSync is the color engine
// every color-managed application on the machine already shares, it reads the
// same profiles a print shop hands out, and it is far better tested than
// anything written here would be. So Ollin parses, caches, and asks; it does
// not do the interpolation.

/// How a color that the destination cannot reproduce is brought inside its
/// gamut. The choice matters most for saturated colors and for the deepest
/// shadows, which is where a screen routinely holds colors a press cannot.
public enum RenderingIntent: String, Sendable, CaseIterable {
    /// Compress the whole picture so the relationships between colors survive,
    /// at the price of shifting colors that would have been reproducible. The
    /// usual choice for photographs, and only as good as the tables the
    /// profile carries for it (a profile without them falls back to
    /// `relative`).
    case perceptual
    /// Keep every reproducible color exactly, and clip the rest to the nearest
    /// color the destination holds. White stays white, so the picture keeps
    /// its brightness. The usual choice for flat graphic work, and the
    /// default here.
    case relative
    /// Favor vividness over accuracy: saturation is preserved even where the
    /// hue has to move. Made for charts and diagrams, not pictures.
    case saturation
    /// Like `relative`, but without remapping white, so the paper's own color
    /// shows up as a tint over the whole picture. This is what makes a proof
    /// show creamy stock as cream rather than as white.
    case absolute

    var colorSyncValue: CFString {
        switch self {
        case .perceptual: ICCProfile.constant(kColorSyncRenderingIntentPerceptual)
        case .relative: ICCProfile.constant(kColorSyncRenderingIntentRelative)
        case .saturation: ICCProfile.constant(kColorSyncRenderingIntentSaturation)
        case .absolute: ICCProfile.constant(kColorSyncRenderingIntentAbsolute)
        }
    }
}

/// One ICC color profile: a monitor, a press, a paper stock, described in the
/// interchange format every color-managed tool reads.
///
/// The built-in profiles cover the everyday cases (`.sRGB`, `.displayP3`,
/// `.genericCMYK`), and a press hands out its own as a `.icc` file, which
/// loads from a URL, from `Data`, or from a sketch's bundled resources:
///
/// ```swift
/// let press = ICCProfile(contentsOf: printerProfileURL) ?? .genericCMYK
/// let proof = SoftProof(press)                 // what that press will make of it
/// drawImage(artwork.softProofed(proof), 0, 0)
/// ```
///
/// `ICCProfile.installed()` lists what is already on the machine, which is
/// how a sketch offers the profiles a studio has installed without asking
/// anyone to type a path. See `Docs/Output/PrintColor.md`.
public struct ICCProfile: Sendable, Hashable {

    /// The color model a profile speaks in. A press profile is `.cmyk`, a
    /// monitor or camera profile `.rgb`, a single-ink or grayscale device
    /// `.gray`.
    public enum Space: String, Sendable, CaseIterable {
        case rgb, cmyk, gray, lab, other
    }

    /// The profile's own description, as it appears in a color picker: "Display
    /// P3", "US Web Coated (SWOP) v2".
    public let name: String
    /// The ICC bytes themselves, ready to embed in an export or hand to a
    /// color engine.
    public let data: Data
    /// Which color model the profile describes.
    public let space: Space
    /// How many components a color takes in this profile: 3 for RGB, 4 for
    /// CMYK, 1 for gray, and more for the extended ink sets some presses use.
    public let channelCount: Int
    /// Whether the profile describes an output device (a printer or a press)
    /// rather than a display, a camera, or a working space. The proof of a
    /// print is only meaningful against one of these, though nothing stops
    /// you proofing a screen against another screen.
    public let isOutputDevice: Bool

    /// A cheap stable digest of the bytes, so a profile can key a transform
    /// cache without hashing tens of kilobytes on every lookup.
    let fingerprint: UInt64

    /// Load a profile from ICC bytes. `nil` when the bytes are not a profile
    /// the system can read.
    public init?(data: Data) {
        guard data.count >= 128,
              ColorSyncProfileCreate(data as CFData, nil)?.takeRetainedValue() != nil else {
            return nil
        }
        self.data = data
        self.space = Self.space(inHeaderOf: data)
        self.channelCount = Self.channelCount(inHeaderOf: data)
        self.isOutputDevice = Self.headerTag(data, at: 12) == "prtr"
        self.fingerprint = Self.digest(data)
        self.name = Self.description(of: data) ?? "Untitled profile"
    }

    /// Load a profile from a `.icc` (or `.icm`) file: the file a press, a
    /// paper maker, or a display calibration hands out.
    public init?(contentsOf url: URL) {
        guard let data = try? Data(contentsOf: url) else { return nil }
        self.init(data: data)
    }

    /// Load a profile bundled with the sketch. Pass the sketch's own bundle
    /// (`.module` inside a sketch target); a default would resolve to the
    /// framework's bundle instead of yours.
    public init?(resource name: String, extension ext: String? = "icc", in bundle: Bundle) {
        guard let url = bundle.url(forResource: name, withExtension: ext) else { return nil }
        self.init(contentsOf: url)
    }

    /// One color's worth of component names, in the profile's own order, for
    /// labeling a plate or a readout: "Cyan", "Magenta", "Yellow", "Black".
    public var channelNames: [String] {
        switch space {
        case .rgb: ["Red", "Green", "Blue"]
        case .gray: ["Gray"]
        case .lab: ["L", "a", "b"]
        case .cmyk: ["Cyan", "Magenta", "Yellow", "Black"]
        case .other: (1 ... max(1, channelCount)).map { "Channel \($0)" }
        }
    }

    public static func == (lhs: ICCProfile, rhs: ICCProfile) -> Bool {
        lhs.fingerprint == rhs.fingerprint && lhs.data.count == rhs.data.count
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(fingerprint)
        hasher.combine(data.count)
    }
}

// MARK: - The built-in profiles

public extension ICCProfile {
    /// The web's standard color space, and what an Ollin canvas is in unless
    /// the sketch declares otherwise.
    static let sRGB = ICCProfile(system: CGColorSpace.sRGB, fallbackName: "sRGB")
    /// The wider space a modern Apple display shows, and what a `.wide` or
    /// `.extended` `colorOutput` canvas is in.
    static let displayP3 = ICCProfile(system: CGColorSpace.displayP3, fallbackName: "Display P3")
    /// The wide RGB working space photographers and prepress hand around.
    static let adobeRGB = ICCProfile(system: CGColorSpace.adobeRGB1998, fallbackName: "Adobe RGB")
    /// A four-ink press, in the generic form the system ships. Real print work
    /// wants the profile for the actual press and paper, which the shop will
    /// hand you; this stands in until then and is close enough to show which
    /// colors are in trouble.
    static let genericCMYK = ICCProfile(system: CGColorSpace.genericCMYK,
                                        fallbackName: "Generic CMYK")
    /// A single-ink (grayscale) device.
    static let genericGray = ICCProfile(system: CGColorSpace.genericGrayGamma2_2,
                                        fallbackName: "Generic Gray")

    /// The profiles installed on this machine, in name order: the system set
    /// plus anything a printer driver, a paper maker, or a calibration has
    /// added. Reading them costs a directory walk, so hold the result rather
    /// than calling it inside `draw()`.
    static func installed() -> [ICCProfile] {
        var seen = Set<UInt64>()
        var found: [ICCProfile] = []
        for directory in profileDirectories {
            guard let walker = FileManager.default.enumerator(
                at: directory, includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles, .skipsPackageDescendants]) else { continue }
            for case let url as URL in walker {
                let ext = url.pathExtension.lowercased()
                guard ext == "icc" || ext == "icm", let profile = ICCProfile(contentsOf: url),
                      seen.insert(profile.fingerprint).inserted else { continue }
                found.append(profile)
            }
        }
        return found.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    /// The installed profile whose description matches, ignoring case and
    /// spacing: `ICCProfile.installed(named: "us web coated (swop) v2")`.
    /// `nil` when the machine has no such profile.
    static func installed(named name: String) -> ICCProfile? {
        let key = fold(name)
        return installed().first { fold($0.name) == key }
    }

    /// The profiles matching the canvas of a sketch with this color output, so
    /// a proof knows what it is starting from.
    static func canvas(_ output: ColorOutput) -> ICCProfile {
        output == .standard ? .sRGB : .displayP3
    }
}

// MARK: - Header reading and system lookup

extension ICCProfile {
    /// The three directories the system reads profiles from, most general
    /// first.
    static var profileDirectories: [URL] {
        var directories = [URL(fileURLWithPath: "/System/Library/ColorSync/Profiles"),
                           URL(fileURLWithPath: "/Library/ColorSync/Profiles")]
        if let home = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask).first {
            directories.append(home.appendingPathComponent("ColorSync/Profiles"))
        }
        return directories.filter { FileManager.default.fileExists(atPath: $0.path) }
    }

    /// A built-in profile, taken from the system color space of that name. The
    /// fallback exists so the property can be non-optional; on any Apple
    /// platform the space is there and the fallback is unreachable.
    init(system name: CFString, fallbackName: String) {
        if let space = CGColorSpace(name: name), let icc = space.copyICCData() as Data?,
           let profile = ICCProfile(data: icc) {
            self = profile
        } else {
            self.init(empty: fallbackName)
        }
    }

    /// The stand-in a missing system profile leaves behind: it converts
    /// nothing, so every operation hands its input straight back.
    init(empty name: String) {
        self.name = name
        self.data = Data()
        self.space = .other
        self.channelCount = 0
        self.isOutputDevice = false
        self.fingerprint = 0
    }

    /// Whether the profile carries bytes a color engine can use.
    var isUsable: Bool { !data.isEmpty }

    /// A live ColorSync profile built from the bytes. Not cached: the callers
    /// that matter cache the whole transform instead.
    var colorSyncProfile: ColorSyncProfile? {
        guard isUsable else { return nil }
        return ColorSyncProfileCreate(data as CFData, nil)?.takeRetainedValue()
    }

    /// A four-character tag from the 128-byte ICC header.
    private static func headerTag(_ data: Data, at offset: Int) -> String {
        guard data.count >= offset + 4 else { return "" }
        let bytes = data[data.startIndex.advanced(by: offset)
            ..< data.startIndex.advanced(by: offset + 4)]
        return String(bytes: bytes, encoding: .ascii) ?? ""
    }

    /// The header's data color space signature, at offset 16.
    private static func space(inHeaderOf data: Data) -> Space {
        switch headerTag(data, at: 16) {
        case "RGB ": .rgb
        case "CMYK": .cmyk
        case "GRAY": .gray
        case "Lab ": .lab
        default: .other
        }
    }

    /// How many components a color takes, read from the same signature. The
    /// `nCLR` family spells its channel count into the tag ("6CLR"), which is
    /// how an extended ink set announces itself.
    private static func channelCount(inHeaderOf data: Data) -> Int {
        let tag = headerTag(data, at: 16)
        switch tag {
        case "RGB ", "Lab ", "XYZ ", "YCbr", "Yxy ", "HSV ", "HLS ", "CMY ": return 3
        case "CMYK", "4CLR": return 4
        case "GRAY": return 1
        default:
            guard tag.count == 4, tag.hasSuffix("CLR"),
                  let count = Int(String(tag.prefix(1)), radix: 16) else { return 0 }
            return count
        }
    }

    /// The profile's description tag, read through the system so the v2 and v4
    /// spellings are both handled.
    private static func description(of data: Data) -> String? {
        guard let profile = ColorSyncProfileCreate(data as CFData, nil)?.takeRetainedValue(),
              let copied = ColorSyncProfileCopyDescriptionString(profile) else { return nil }
        let text = copied.takeRetainedValue() as String
        return text.isEmpty ? nil : text
    }

    /// FNV-1a over the bytes: enough to tell two profiles apart as a cache key.
    private static func digest(_ data: Data) -> UInt64 {
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in data {
            hash ^= UInt64(byte)
            hash = hash &* 0x0000_0100_0000_01b3
        }
        return hash
    }

    static func fold(_ name: String) -> String {
        name.lowercased().filter { !$0.isWhitespace && $0 != "-" && $0 != "_" }
    }

    /// ColorSync spells its dictionary keys as unmanaged strings, so every use
    /// goes through here rather than repeating the unwrap.
    static func constant(_ value: Unmanaged<CFString>?) -> CFString {
        value?.takeUnretainedValue() ?? "" as CFString
    }
}
