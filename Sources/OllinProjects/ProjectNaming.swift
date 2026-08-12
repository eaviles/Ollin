import Foundation

/// Naming a new sketch, for the common case where the name is not the point.
///
/// A dated serial (`Sketch2026001`) sorts a folder of sketches by when they were
/// made and never asks you to think of a title before you have made anything.
/// The year comes from the caller rather than a clock in here, so the rule can
/// be tested and so a run reproduces.
public enum ProjectNaming {
    public static let defaultPrefix = "Sketch"

    /// The next unused serial in `folder`: one past the highest already there,
    /// or 001 when nothing matches.
    ///
    /// Both files and folders count, since the same name can be either a loose
    /// `.swift` file or a project folder, and a serial should never be reused
    /// across the two.
    public static func nextSerial(
        in folder: URL,
        year: Int,
        prefix: String = defaultPrefix
    ) -> String {
        let existing = (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []
        let highest = existing.compactMap { serialNumber(of: $0, year: year, prefix: prefix) }.max()
        return serial(year: year, number: (highest ?? 0) + 1, prefix: prefix)
    }

    /// `Sketch2026007` for year 2026, number 7.
    public static func serial(year: Int, number: Int, prefix: String = defaultPrefix) -> String {
        "\(prefix)\(year)\(String(format: "%03d", number))"
    }

    /// The serial number inside a name, or nil when the name is not one of ours.
    /// A `.swift` suffix is ignored, so a loose file and a folder read alike.
    static func serialNumber(of name: String, year: Int, prefix: String) -> Int? {
        var stem = name
        if stem.hasSuffix(".swift") { stem.removeLast(6) }

        let head = "\(prefix)\(year)"
        guard stem.hasPrefix(head) else { return nil }

        let digits = stem.dropFirst(head.count)
        // Exactly the trailing number, so `Sketch2026007-old` is somebody else's
        // name and never bumps the count.
        guard !digits.isEmpty, digits.allSatisfy(\.isNumber) else { return nil }
        return Int(digits)
    }
}
