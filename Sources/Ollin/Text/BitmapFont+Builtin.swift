import Foundation

public extension BitmapFont {
    /// Ollin's bundled default bitmap font: **Cozette** by Ines (the.moonwit.ch),
    /// a 13px proportional-baseline pixel font, MIT-licensed and vendored as a BDF
    /// resource. It's the default `textFont`, so `drawText` works with no setup,
    /// and covers a wide range — Latin (including the Spanish accents `á é í ó ú`,
    /// `ñ`, `ü`, `¿`, `¡`), Cyrillic, Greek, and Japanese kana.
    ///
    /// Loaded once from the bundled BDF (see `BitmapFont(bdfContentsOf:)`); if the
    /// resource is somehow unavailable, this is an empty font (text draws nothing
    /// rather than crashing).
    static let builtin: BitmapFont = {
        if let url = OllinResources.bundle.url(forResource: "cozette", withExtension: "bdf"),
           let font = BitmapFont(bdfContentsOf: url) {
            return font
        }
        return BitmapFont(glyphs: [:], pixelHeight: 7)
    }()
}
