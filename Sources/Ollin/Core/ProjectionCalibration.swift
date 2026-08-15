#if canImport(AppKit)
import AppKit
#endif
import CoreGraphics
import Foundation

/// Where the corners are kept between runs.
///
/// The corners belong to the room rather than to the piece. One projector on
/// one wall is out of true by the same amount whatever is playing, so the
/// numbers are filed under the display and every sketch that opens there picks
/// them up. Drag them once, show a year of work through them.
///
/// The file is JSON in `~/Library/Application Support/Ollin/Calibration/`, one
/// per display, readable on purpose: a wall that comes back wrong is worth
/// being able to look at.
enum ProjectionCalibration {

    /// The shape of the file. A calibration written by an older Ollin is
    /// ignored rather than guessed at.
    static let formatVersion = 1

    struct Record: Codable {
        var version: Int
        var savedAt: Date
        /// What the display measured when this was dragged, for a person
        /// reading the file. The corners are fractions, so they survive a
        /// resolution change on their own.
        var displayWidth: Int
        var displayHeight: Int
        var corners: Installation.Projection.Corners
    }

    /// Somewhere else to keep them, which only the tests set: they must not
    /// write over the calibration of whatever projector this machine drives.
    @MainActor static var directoryOverride: URL?

    @MainActor
    static func directory() -> URL? {
        if let directoryOverride {
            try? FileManager.default.createDirectory(at: directoryOverride,
                                                     withIntermediateDirectories: true)
            return directoryOverride
        }
        guard let support = try? FileManager.default.url(
            for: .applicationSupportDirectory, in: .userDomainMask,
            appropriateFor: nil, create: true) else { return nil }
        let directory = support.appendingPathComponent("Ollin/Calibration", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    @MainActor
    static func url(forDisplay key: String) -> URL? {
        directory()?.appendingPathComponent("\(key).json")
    }

    /// What this display is filed under. The system's own identifier for the
    /// panel, which survives being unplugged and plugged back in, where the
    /// display number it is read from does not.
    @MainActor
    static func key(for screenNumber: UInt32?) -> String {
        guard let screenNumber else { return "main" }
        let id = CGDirectDisplayID(screenNumber)
        if let uuid = CGDisplayCreateUUIDFromDisplayID(id)?.takeRetainedValue(),
           let text = CFUUIDCreateString(nil, uuid) as String? {
            return text
        }
        return "display-\(id)"
    }

    // MARK: Reading and writing

    /// The corners filed under this display, or nil when there are none.
    ///
    /// Nothing here may stop a piece from starting, which is the rule the
    /// checkpoint keeps too: a missing file, an unreadable one, or one written
    /// by an older Ollin is skipped and the piece opens fitted as declared.
    @MainActor
    static func corners(forDisplay key: String) -> Installation.Projection.Corners? {
        guard let url = url(forDisplay: key),
              let data = try? Data(contentsOf: url) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let record = try? decoder.decode(Record.self, from: data) else {
            ollinInstallationLog("calibration for \(key) unreadable; opening as declared")
            return nil
        }
        guard record.version == formatVersion else {
            ollinInstallationLog("calibration for \(key) is from an older Ollin; opening as declared")
            return nil
        }
        return record.corners
    }

    @MainActor
    @discardableResult
    static func save(_ corners: Installation.Projection.Corners,
                     forDisplay key: String, displaySize: CGSize) -> Bool {
        guard let url = url(forDisplay: key) else { return false }
        let record = Record(version: formatVersion, savedAt: Date(),
                            displayWidth: Int(displaySize.width.rounded()),
                            displayHeight: Int(displaySize.height.rounded()),
                            corners: corners)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(record) else { return false }
        do {
            try data.write(to: url, options: .atomic)
            return true
        } catch {
            ollinInstallationLog("could not write the calibration: \(error.localizedDescription)")
            return false
        }
    }

    /// Throw the corners away, so the next launch opens square again.
    @MainActor
    static func forget(display key: String) {
        guard let url = url(forDisplay: key) else { return }
        try? FileManager.default.removeItem(at: url)
    }
}

#if canImport(AppKit)
extension ProjectionCalibration {

    /// The identifier of the display a window is on, or of the main one.
    @MainActor
    static func key(for screen: NSScreen?) -> String {
        let number = (screen ?? NSScreen.main)?
            .deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber
        return key(for: number?.uint32Value)
    }
}
#endif
