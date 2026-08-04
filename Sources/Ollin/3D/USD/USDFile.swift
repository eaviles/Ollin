import Foundation

/// Opening a USD file of any of the three containers: `.usda` text, `.usdc`
/// crate, or a `.usdz` package holding one of those. Dispatch sniffs content,
/// never the file extension, so a mislabeled file still opens.
///
/// The supported envelope is a flattened single layer (what design tools
/// actually export): self-contained packages, variants at their defaults, no
/// cross-file composition. Sublayer/reference arcs are recorded in the raw
/// tree's metadata but not composed.
extension USDStage {

    /// A parsed stage plus its container context: the package archive and the
    /// default layer's entry name when the file was a `.usdz`, so consumers
    /// can resolve asset paths (textures) against the package.
    struct Opened {
        var stage: USDStage
        var archive: USDZipArchive?
        var defaultLayerName: String?
    }

    /// Parse the USD file at `url` (usda, usdc, or usdz).
    static func load(contentsOf url: URL) throws -> USDStage {
        try load(data: Data(contentsOf: url))
    }

    /// Parse USD `data` in any of the three containers.
    static func load(data: Data) throws -> USDStage {
        try open(data: data).stage
    }

    /// Parse USD `data`, keeping the package context alongside the stage.
    static func open(data: Data) throws -> Opened {
        if USDCrateReader.matches(data) {
            return Opened(stage: try USDCrateReader(data: data).readStage())
        }
        if USDZipArchive.matches(data) {
            let archive = try USDZipArchive(data: data)
            // The package's default layer is the first entry with a usd
            // extension, in archive order.
            for name in archive.entryNames {
                let ext = (name as NSString).pathExtension.lowercased()
                if ["usd", "usda", "usdc"].contains(ext), let bytes = archive.data(named: name) {
                    var opened = try open(data: bytes)
                    opened.archive = archive
                    opened.defaultLayerName = name
                    return opened
                }
            }
            throw USDError.malformed("usdz: no usd layer in package")
        }
        if let text = Self.usdaText(from: data) {
            return Opened(stage: try USDTextParser(text: text).parseStage())
        }
        throw USDError.unrecognizedFormat
    }

    /// Decode `data` as usda text if it opens with the `#usda` cookie
    /// (allowing a UTF-8 BOM), else nil.
    private static func usdaText(from data: Data) -> String? {
        var bytes = data
        if bytes.count >= 3, bytes[bytes.startIndex] == 0xEF,
           bytes[bytes.startIndex + 1] == 0xBB, bytes[bytes.startIndex + 2] == 0xBF {
            bytes = bytes.dropFirst(3)
        }
        guard bytes.starts(with: Array("#usda".utf8)) else { return nil }
        return String(data: bytes, encoding: .utf8)
    }
}
