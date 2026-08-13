import Foundation

/// Glyph mosaic: rebuild an image as a grid of text glyphs, each cell showing
/// the character whose ink best matches the cell's brightness. The classic
/// text-mode rendering, generalized: the character set is anything you type,
/// and the ramp is not hand-ordered. Every glyph's actual ink coverage is
/// measured in the active font, so quadrant blocks, checkered squares, braille
/// dots, and plain letters all sort themselves correctly.
///
/// ```swift
/// textFont(.builtin)                       // the bundled bitmap font
/// fill(.white)
/// drawGlyphMosaic(picture, columns: 72)    // white marks on the dark canvas
/// ```
///
/// By default bright cells get dense glyphs (light marks on a dark canvas);
/// pass `inverted: true` for the paper reading, where dark cells carry the
/// ink. Cells too faint for the sparsest glyph stay empty, so shadows read as
/// true voids. Deterministic given (image, columns, characters, font).

/// Curated character sets for `glyphMosaic`. The order doesn't matter: the
/// ramp is sorted by each glyph's measured ink in the active font, and
/// characters the font doesn't cover simply drop out.
public enum GlyphSet {
    /// Geometric and technical marks: dots, crosses, bars, fine grids,
    /// checkered squares, quadrant blocks, braille textures. The default, at
    /// its best in the bundled bitmap font (`textFont(BitmapFont.builtin)`),
    /// which covers every mark.
    public static let technical =
        "·⠂∙•⠒1x∷+=⠶✕▪∴≡⁘┼⠿※╬◌═◇○▖▘▝▗⊘⊞◐⊗✚✜▚▞⣤▤◈⊠□▣⣶◆●◉▧▦▀▄▌▐▙▟⊡◘░▩◙⣿■▒▬▓█"

    /// The traditional letterform ramp, for the typewriter look.
    public static let classic = ".:-=+*#%@"

    /// Block elements only: quadrants, half blocks, and shades, for a chunky
    /// mosaic with no recognizable characters.
    public static let blocks = "▖▗▘▝▚▞▙▛▜▟▀▄▌▐░▒▓█"
}

/// One cell of a glyph mosaic: which character landed where, and what the
/// image looked like underneath, for custom drawing (jitter, per-cell color,
/// vector export through `textToShapes`).
public struct GlyphMosaicCell: Sendable {
    /// Grid coordinates, `(0, 0)` at the top-left cell.
    public let column: Int
    public let row: Int
    /// The cell's center on the canvas.
    public let center: Vector2
    /// The cell's side length (cells are square).
    public let size: Double
    /// The glyph chosen for this cell.
    public let character: Character
    /// The sampled brightness under the cell, `0` black to `1` white,
    /// before any `inverted` mapping.
    public let brightness: Double
    /// The average color under the cell (straight alpha).
    public let color: Color
}

// MARK: - Ink measurement

/// One ramp entry: a character and its measured ink coverage, normalized so
/// the densest glyph in the set is `1`.
typealias GlyphRampEntry = (character: Character, coverage: Double)

/// Measured ramps are cached per (font, characters): a mosaic redrawn every
/// frame re-measures nothing.
@MainActor
private enum GlyphRampCache {
    static var storage: [String: [GlyphRampEntry]] = [:]
}

@MainActor
func glyphRamp(for characters: String, font: ActiveFont) -> [GlyphRampEntry] {
    let key = fontCacheKey(font) + "|" + characters
    if let cached = GlyphRampCache.storage[key] { return cached }

    // Dedupe preserving order (a Set walk would be nondeterministic).
    var seen = Set<Character>()
    var unique: [Character] = []
    for ch in characters where !seen.contains(ch) {
        seen.insert(ch)
        unique.append(ch)
    }

    var entries: [GlyphRampEntry] = []
    for ch in unique {
        let ink = inkCoverage(of: ch, in: font)
        if ink > 0 { entries.append((ch, ink)) }
    }
    // Sort by ink; ties break on the character so the ramp is deterministic.
    entries.sort { $0.coverage != $1.coverage ? $0.coverage < $1.coverage
                                              : String($0.character) < String($1.character) }
    if let max = entries.last?.coverage, max > 0 {
        entries = entries.map { ($0.character, $0.coverage / max) }
    }

    if GlyphRampCache.storage.count > 64 { GlyphRampCache.storage.removeAll() }
    GlyphRampCache.storage[key] = entries
    return entries
}

/// A stable identity for the ramp cache. Fonts don't expose identity, so this
/// keys on the traits that change a glyph set; the characters ride beside it.
private func fontCacheKey(_ font: ActiveFont) -> String {
    switch font {
    case .bitmap(let f):  return "b:\(f.pixelHeight):\(f.baseline):\(f.glyphs.count)"
    case .outline(let f): return "o:\(f.name)"
    case .stroke(let f):  return "s:\(f.unitsPerEm):\(f.glyphs.count)"
    }
}

/// The fraction of a square line-height cell this glyph inks, `0` when the
/// font has no glyph for it. Bitmap fonts count lit pixels exactly; outline
/// fonts integrate the filled glyph area; stroke fonts take pen travel times
/// a nominal pen width. Each is consistent within its kind, and the ramp is
/// re-normalized to its densest member, so the kinds never mix.
private func inkCoverage(of character: Character, in font: ActiveFont) -> Double {
    switch font {
    case .bitmap(let f):
        guard f.pixelHeight > 0, let glyph = f.glyph(for: character) else { return 0 }
        let lit = glyph.rows.reduce(0) { $0 + $1.nonzeroBitCount }
        return Double(lit) / Double(f.pixelHeight * f.pixelHeight)
    case .outline(let f):
        let size = 100.0
        // One character on its own has no direction to resolve, so the automatic
        // reading is the right one here whatever the sketch set.
        let shapes = f.glyphShapes(for: String(character), size: size,
                                   alignH: .left, alignV: .baseline,
                                   direction: .automatic, at: .zero)
        var area = 0.0
        for shape in shapes {
            // Holes wind opposite the outer contour, so the signed areas cancel.
            var signed = 0.0
            for contour in shape.contours { signed += signedArea(contour.points) }
            area += abs(signed)
        }
        return area / (size * size)
    case .stroke(let f):
        guard f.unitsPerEm > 0, let glyph = f.glyph(for: character) else { return 0 }
        var length = 0.0
        for polyline in glyph.polylines where polyline.count >= 2 {
            for i in 1 ..< polyline.count {
                length += polyline[i].distance(to: polyline[i - 1])
            }
        }
        // Ink is pen travel times a nominal pen width (a twelfth of the em).
        return (length / f.unitsPerEm) / 12
    }
}

/// Shoelace signed area of a closed polygon.
private func signedArea(_ points: [Vector2]) -> Double {
    guard points.count >= 3 else { return 0 }
    var sum = 0.0
    for i in 0 ..< points.count {
        let a = points[i]
        let b = points[(i + 1) % points.count]
        sum += a.x * b.y - b.x * a.y
    }
    return sum / 2
}

// MARK: - Sampling

@MainActor
private enum GlyphMosaicNotes {
    static var printed = Set<String>()
    static func note(_ message: String) {
        guard !printed.contains(message) else { return }
        printed.insert(message)
        print("Ollin: \(message)")
    }
}

@MainActor
func mosaicCells(of image: Image,
                 columns: Int,
                 characters: String,
                 bounds: Rectangle,
                 inverted: Bool,
                 font: ActiveFont) -> [GlyphMosaicCell] {
    guard columns >= 1, image.width > 0, image.height > 0,
          bounds.width > 0, bounds.height > 0 else { return [] }
    guard let pixels = image.premultipliedPixels() else {
        GlyphMosaicNotes.note("glyphMosaic needs CPU pixels; a texture-backed image has none. Read a video frame through its snapshot first.")
        return []
    }
    let ramp = glyphRamp(for: characters, font: font)
    guard !ramp.isEmpty else {
        GlyphMosaicNotes.note("glyphMosaic found no ink: none of the characters have a glyph in the active font.")
        return []
    }
    let coverages = ramp.map(\.coverage)
    // Below half the sparsest glyph's ink, the closest match is emptiness.
    let emptyBelow = coverages[0] / 2

    // The image keeps its aspect inside `bounds`; the grid tiles the fit.
    let fitted = Rectangle(fitting: image.size, in: bounds)
    let cell = fitted.width / Double(columns)
    guard cell > 0 else { return [] }
    let rows = Swift.max(Int((fitted.height / cell).rounded()), 1)
    let gridTop = fitted.y + (fitted.height - Double(rows) * cell) / 2

    let width = image.width, height = image.height
    var cells: [GlyphMosaicCell] = []
    cells.reserveCapacity(columns * rows)

    for row in 0 ..< rows {
        let py0 = Swift.min(row * height / rows, height - 1)
        let py1 = Swift.max(Swift.min((row + 1) * height / rows, height), py0 + 1)
        for column in 0 ..< columns {
            let px0 = Swift.min(column * width / columns, width - 1)
            let px1 = Swift.max(Swift.min((column + 1) * width / columns, width), px0 + 1)

            // Average the premultiplied bytes under the cell.
            var sumR = 0, sumG = 0, sumB = 0, sumA = 0
            for py in py0 ..< py1 {
                var i = (py * width + px0) * 4
                for _ in px0 ..< px1 {
                    sumR += Int(pixels[i])
                    sumG += Int(pixels[i + 1])
                    sumB += Int(pixels[i + 2])
                    sumA += Int(pixels[i + 3])
                    i += 4
                }
            }
            let count = Double((px1 - px0) * (py1 - py0)) * 255
            let alpha = Double(sumA) / count
            // Straight color: the premultiplied average divided back by
            // coverage (the ink convention stipple uses too).
            let r = alpha > 0 ? Swift.min(Double(sumR) / count / alpha, 1) : 0
            let g = alpha > 0 ? Swift.min(Double(sumG) / count / alpha, 1) : 0
            let b = alpha > 0 ? Swift.min(Double(sumB) / count / alpha, 1) : 0

            // Perceptually re-encoded brightness, so midtones land where the
            // eye expects.
            let y = 0.2126 * Color.srgbToLinear(r)
                  + 0.7152 * Color.srgbToLinear(g)
                  + 0.0722 * Color.srgbToLinear(b)
            let brightness = Color.linearToSrgb(y)

            // Ink scales by coverage, so transparency carries none in either
            // mapping and soft edges fade.
            let target = (inverted ? 1 - brightness : brightness) * alpha
            guard target >= emptyBelow else { continue }

            let chosen = nearestRampIndex(coverages, to: target)
            let straight = alpha > 0
                ? Color(red: r, green: g, blue: b, alpha: alpha)
                : .clear
            cells.append(GlyphMosaicCell(
                column: column, row: row,
                center: Vector2(fitted.x + (Double(column) + 0.5) * cell,
                                gridTop + (Double(row) + 0.5) * cell),
                size: cell,
                character: ramp[chosen].character,
                brightness: brightness,
                color: straight))
        }
    }
    return cells
}

/// Index of the coverage closest to `target` (ascending array; ties pick the
/// sparser glyph, deterministically).
private func nearestRampIndex(_ coverages: [Double], to target: Double) -> Int {
    var lo = 0, hi = coverages.count - 1
    if target <= coverages[0] { return 0 }
    if target >= coverages[hi] { return hi }
    while hi - lo > 1 {
        let mid = (lo + hi) / 2
        if coverages[mid] < target { lo = mid } else { hi = mid }
    }
    return target - coverages[lo] <= coverages[hi] - target ? lo : hi
}

// MARK: - Sketch sugar

public extension Sketch {
    /// The glyph mosaic of `image` as data: one `GlyphMosaicCell` per cell that
    /// earned a glyph, using the active `textFont`. The image keeps its aspect
    /// inside `bounds` (the whole canvas by default) and is sampled `columns`
    /// cells across; cells too faint for the sparsest glyph are omitted.
    /// Deterministic, so a mosaic is snapshot- and recipe-safe.
    ///
    /// Use this form for custom drawing; `drawGlyphMosaic` is the one-call form.
    func glyphMosaic(of image: Image,
                     columns: Int = 72,
                     characters: String = GlyphSet.technical,
                     in bounds: Rectangle? = nil,
                     inverted: Bool = false) -> [GlyphMosaicCell] {
        mosaicCells(of: image, columns: columns, characters: characters,
                    bounds: bounds ?? canvasRectangle, inverted: inverted,
                    font: drawer.currentFont)
    }

    /// Draw `image` as a glyph mosaic: a grid of characters from `characters`,
    /// each cell showing the glyph whose measured ink matches its brightness.
    /// Bright cells get dense glyphs (light marks on a dark canvas); pass
    /// `inverted: true` for the paper reading. Glyphs draw with the current
    /// `fill`, or tinted by the image itself with `colored: true`.
    ///
    /// The character set is any string; each glyph's ink is measured in the
    /// active `textFont` (and cached), so the ramp orders itself. The bundled
    /// bitmap font covers every mark in the default set:
    ///
    /// ```swift
    /// textFont(.builtin)
    /// fill(.white)
    /// drawGlyphMosaic(picture, columns: 72)
    /// ```
    ///
    /// `glyphScale` is the fraction of its cell each glyph draws at. The
    /// default leaves a gutter between cells, so even solid blocks read as
    /// discrete marks; `1` tiles full-cell glyphs (the block and shade
    /// characters) edge to edge for an unbroken mosaic.
    func drawGlyphMosaic(_ image: Image,
                         columns: Int = 72,
                         characters: String = GlyphSet.technical,
                         in bounds: Rectangle? = nil,
                         inverted: Bool = false,
                         colored: Bool = false,
                         glyphScale: Double = 0.85) {
        let cells = glyphMosaic(of: image, columns: columns, characters: characters,
                                in: bounds, inverted: inverted)
        guard let first = cells.first else { return }
        withState {
            textAlign(.center, .middle)
            textSize(first.size * Swift.max(glyphScale, 0))
            for cell in cells {
                if colored { fill(cell.color) }
                drawText(String(cell.character), at: cell.center)
            }
        }
    }
}
