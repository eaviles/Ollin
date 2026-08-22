import Foundation

public extension StrokeFont {
    /// Ollin's bundled single-line font: **Hershey Sans** (`futural`), a clean
    /// single-stroke sans from the public-domain Hershey vector fonts. Loaded once
    /// from the bundled `.jhf`; if the resource is somehow unavailable, this is an
    /// empty font (text draws nothing rather than crashing).
    static let builtin: StrokeFont = {
        if let url = OllinResources.bundle.url(forResource: "futural", withExtension: "jhf"),
           let font = StrokeFont(jhfContentsOf: url) {
            return font
        }
        return StrokeFont(glyphs: [:], unitsPerEm: 28, ascentUnits: 21, descentUnits: 7, lineGapUnits: 8)
    }()
}
