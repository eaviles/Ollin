// Drawer, the text half: drawText over the three font kinds (bitmap, outline,
// stroke), the glyph-atlas path, per-glyph and on-path layout, box wrap, and
// the text metrics surface.

import Foundation
import simd
import COllinShaders

extension Drawer {
    // MARK: Text

    /// Draw `string` at `(x, y)` using the active `textFont` / `textSize` /
    /// `textAlign`. `\n` starts a new line; text rides the transform stack and
    /// stays crisp at any size. A **bitmap** font stamps each lit pixel as a fill
    /// color square on the SDF path; an **outline** font draws each glyph as a
    /// vector `Shape`: it takes the current `fill`, and, once the sketch has set
    /// one, the current `stroke` (`noFill()` plus a `stroke(...)` gives
    /// outline-only text). The initial default stroke never applies to text: a
    /// 1px opaque band straddling every contour reads as bolding on a light
    /// ground and eats thin light glyphs on a dark one, so glyphs decorate only
    /// with a stroke the sketch asked for; a **stroke** (single-line) font draws each
    /// glyph as open pen paths with the current `stroke` and no fill. Unknown
    /// characters advance the pen but draw nothing.
    func drawText(_ string: String, _ x: Double, _ y: Double) {
        guard textPixelSize > 0, !string.isEmpty else { return }
        switch currentFont {
        case .bitmap(let font):  drawBitmapText(string, x, y, font: font)
        case .outline(let font):
            // The atlas path is opt-in and raster, so SVG export keeps the vector
            // outline path; everything else honors `textMode`.
            if textRenderMode == .atlas, svgRecorder == nil {
                drawAtlasText(string, x, y, font: font)
            } else {
                drawOutlineText(string, x, y, font: font)
            }
        case .stroke(let font):  drawStrokeText(string, x, y, font: font)
        }
    }

    /// Run `body` with any of the given text style applied for its duration,
    /// then put the standing state back exactly. `color` paints the glyphs in
    /// that color whatever the font kind: the fill for bitmap and outline
    /// text (with the outline decoration a standing `stroke` would add
    /// suppressed, since a one-call color asks for exactly that color), or the
    /// stroke for a stroke font. A `nil` argument changes nothing.
    func withTextStyle(size: Double?, color: Color?,
                       alignH: HorizontalTextAlign?, alignV: VerticalTextAlign?, _ body: () -> Void) {
        let savedSize = textPixelSize
        let savedH = textAlignH
        let savedV = textAlignV
        let savedFill = fillPaint
        let savedStroke = strokePaint
        let savedStrokeSet = strokeSet
        if let size { textSize(size) }
        if let alignH { textAlignH = alignH }
        if let alignV { textAlignV = alignV }
        if let color {
            if case .stroke = currentFont {
                strokePaint = .color(color)
                strokeSet = true
            } else {
                fillPaint = .color(color)
                strokePaint = nil
            }
        }
        body()
        textPixelSize = savedSize
        textAlignH = savedH
        textAlignV = savedV
        fillPaint = savedFill
        strokePaint = savedStroke
        strokeSet = savedStrokeSet
    }

    /// The one-call styled label: `drawText` with `size`/`color`/`align`
    /// applied through `withTextStyle` for this draw alone.
    func drawText(_ string: String, _ x: Double, _ y: Double,
                  size: Double?, color: Color?, alignH: HorizontalTextAlign?, alignV: VerticalTextAlign?) {
        withTextStyle(size: size, color: color, alignH: alignH, alignV: alignV) {
            drawText(string, x, y)
        }
    }

    /// Stroke path: each glyph is a set of open pen polylines, drawn with the
    /// current `stroke` (weight, join, cap). Fill is ignored: the inverse of
    /// outline text.
    private func drawStrokeText(_ string: String, _ x: Double, _ y: Double, font: StrokeFont) {
        guard strokePaint != nil, strokeWidth > 0 else { return }
        forEachStrokeGlyphPolyline(string, x, y, font: font) { polyline in
            drawPolyline(polyline)
        }
    }

    /// Walk the pen polylines of `string`, laid out with the active text state,
    /// calling `body` with each polyline in canvas space. Shared by
    /// `drawStrokeText` and `textToShapes` so the stroke layout lives in one place.
    private func forEachStrokeGlyphPolyline(_ string: String, _ x: Double, _ y: Double,
                                            font: StrokeFont, _ body: ([Vector2]) -> Void) {
        guard font.unitsPerEm > 0 else { return }
        let scale = textPixelSize / font.unitsPerEm
        let ascent = font.ascentUnits * scale
        let descent = font.descentUnits * scale
        let leading = (font.ascent + font.descent + font.leading) * textPixelSize   // baseline-to-baseline
        let lines = string.split(separator: "\n", omittingEmptySubsequences: false)
        let blockHeight = Double(lines.count - 1) * leading + ascent + descent

        // First line's baseline, from the vertical anchor.
        let firstBaseline: Double
        switch textAlignV {
        case .top:      firstBaseline = y + ascent
        case .baseline: firstBaseline = y
        case .middle:   firstBaseline = y - blockHeight / 2 + ascent
        case .bottom:   firstBaseline = y - blockHeight + ascent
        }

        for (lineIndex, line) in lines.enumerated() {
            let baselineY = firstBaseline + Double(lineIndex) * leading
            let lineWidth = font.lineAdvanceUnits(of: line) * scale
            // Left edge of this line, from the horizontal anchor.
            var penX: Double
            switch textAlignH {
            case .left:   penX = x
            case .center: penX = x - lineWidth / 2
            case .right:  penX = x - lineWidth
            }
            for ch in line {
                if let glyph = font.glyph(for: ch) {
                    for polyline in glyph.polylines {
                        body(polyline.map { Vector2(penX + $0.x * scale, baselineY + $0.y * scale) })
                    }
                }
                penX += font.advanceUnits(for: ch) * scale
            }
        }
    }

    /// Bitmap path: one fill color square per lit pixel (see `forEachBitmapPixel`).
    private func drawBitmapText(_ string: String, _ x: Double, _ y: Double, font: BitmapFont) {
        guard let fill = fillPaint else { return }
        forEachBitmapPixel(string, x, y, font: font) { center, module in
            let half = SIMD2<Float>(Float(module / 2), Float(module / 2))
            // Fill-only square; opt out of hollow so a set band doesn't turn each
            // pixel into a ring.
            appendSDF(shape: .box, center: center, size: half,
                      fill: fill, stroke: nil, applyHollow: false)
        }
    }

    /// Run `body` with the stroke the text paths honor: the active stroke once
    /// the sketch has set one, and none under the initial default (see
    /// `drawText`). Gates the glyph paths that decorate through `drawShape`
    /// (the SVG branch, text on a path, per-glyph drawing); `drawOutlineText`'s
    /// raster path checks `strokeSet` directly.
    func withTextStroke(_ body: () -> Void) {
        if strokeSet { body(); return }
        let saved = strokePaint
        strokePaint = nil
        body()
        strokePaint = saved
    }

    /// Outline path: each glyph fills (and strokes) like any other shape. The
    /// per-glyph flatten + triangulation are cached in local space and reused, so a
    /// redrawn label only translates cached vertices — the same geometry a
    /// `glyphShapes` + `drawShape` pass would emit, without re-tessellating every
    /// frame. SVG export keeps the `drawShape` path (its recorder wants `Shape`s).
    private func drawOutlineText(_ string: String, _ x: Double, _ y: Double, font: OutlineFont) {
        let hasFill = fillPaint != nil
        let hasStroke = strokeSet && strokePaint != nil && strokeWidth > 0
        guard hasFill || hasStroke else { return }

        let placed = font.placedGlyphs(for: string, size: textPixelSize,
                                       alignH: textAlignH, alignV: textAlignV,
                                       direction: textWritingDirection,
                                       justify: textJustification, hangs: textHangsInBox,
                                       at: Vector2(x, y))

        if svgRecorder != nil {
            for glyph in placed {
                // A picture glyph has no outline to write into a vector file. It
                // goes through the image path, which is what counts it as a skipped
                // image in the export's own report.
                if let picture = glyph.picture {
                    drawImage(picture, in: glyph.pictureRect)
                    continue
                }
                withTextStroke { OutlineFont.shapes(of: [glyph]).forEach(drawShape) }
            }
            return
        }

        // One paint resolution for the whole run; an along-path fill sweeps
        // around the text anchor.
        let fillVP = fillPaint.map { vertexPaint($0, anchor: Vector2(x, y)) }
        let strokeVP = strokePaint.map { vertexPaint($0, anchor: Vector2(x, y)) }
        for glyph in placed {
            // Emoji carry their own colors, so they are drawn as pictures and take
            // neither the fill nor the stroke.
            if let picture = glyph.picture {
                drawImage(picture, in: glyph.pictureRect)
                continue
            }
            let origin = glyph.origin
            if let vp = fillVP {
                let tri = glyph.localFill
                replicated {
                    for i in stride(from: 0, to: tri.count - 2, by: 3) {
                        let p0 = tri[i] + origin
                        let p1 = tri[i + 1] + origin
                        let p2 = tri[i + 2] + origin
                        emit(p0.simd2, color: vp.color(at: p0))
                        emit(p1.simd2, color: vp.color(at: p1))
                        emit(p2.simd2, color: vp.color(at: p2))
                    }
                }
            }
            if hasStroke, let vp = strokeVP {
                let half = strokeWidth / 2
                for contour in glyph.localContours where contour.points.count >= 2 {
                    appendStrokedPath(contour.points.map { $0 + origin },
                                      closed: contour.isClosed, half: half, paint: vp)
                }
            }
        }
    }

    /// Atlas path (`textMode(.atlas)`): each glyph is one textured quad sampling
    /// the font's SDF atlas, so a paragraph costs a handful of vertex writes per
    /// glyph instead of a flatten + triangulation. Fill-only (the volume case is
    /// filled body text); the outline path keeps fill + stroke. The whole call is
    /// one batch — all glyphs share the atlas texture.
    private func drawAtlasText(_ string: String, _ x: Double, _ y: Double, font: OutlineFont) {
        guard let fill = fillPaint else { return }
        let placed = font.placedAtlasGlyphs(for: string, size: textPixelSize,
                                            alignH: textAlignH, alignV: textAlignV,
                                            direction: textWritingDirection,
                                            justify: textJustification, hangs: textHangsInBox,
                                            at: Vector2(x, y))
        guard !placed.isEmpty else { return }

        // A distance field holds one channel, so an emoji cannot ride the atlas and
        // is drawn as an ordinary picture instead. The atlas has no slot for a space
        // either, so asking the color cache only where a slot is missing keeps the
        // volume path paying nothing per ordinary glyph.
        var slots = [GlyphAtlas.Slot?]()
        slots.reserveCapacity(placed.count)
        for g in placed {
            let slot = font.atlas.slot(for: g.glyph, font: g.font)
            slots.append(slot)
            guard slot == nil, let color = font.colorGlyphs.glyph(g.glyph, font: g.font) else { continue }
            drawImage(color.image, in: color.rect(at: g.origin, size: textPixelSize))
        }

        // The tint carries the fill: per-corner for a gradient (glyph quads are
        // small, so corner interpolation tracks the paint), constant for a color.
        let vp = vertexPaint(fill, anchor: Vector2(x, y))
        beginGlyphBatch(font.atlas)
        replicated {
            for (index, g) in placed.enumerated() {
                guard let slot = slots[index] else { continue }   // space / picture / unplaced
                // Cell rect (em, y-up) → canvas: x grows with em-x, canvas-y falls as
                // em-y rises (font y-up vs Ollin y-down). Where the column turns its
                // glyphs, each corner takes the same quarter turn clockwise about the
                // pen. A quarter turn keeps the quad a quad, and it carries each
                // corner's own patch of the atlas with it, so the picture turns too.
                func corner(_ emX: Double, _ emY: Double, _ u: Float, _ v: Float) -> OllinImageVertex {
                    let lx = emX * textPixelSize, ly = -emY * textPixelSize
                    let px = Float(g.turned ? g.origin.x - ly : g.origin.x + lx)
                    let py = Float(g.turned ? g.origin.y + lx : g.origin.y + ly)
                    // The paint is sampled at the vertex the GPU will see, which is
                    // the rounded one.
                    return imageVertex(px, py, u, v,
                                       vp.color(at: Vector2(Double(px), Double(py))))
                }
                let tl = corner(slot.emLeft, slot.emTop, slot.u0, slot.v0)
                let tr = corner(slot.emRight, slot.emTop, slot.u1, slot.v0)
                let br = corner(slot.emRight, slot.emBottom, slot.u1, slot.v1)
                let bl = corner(slot.emLeft, slot.emBottom, slot.u0, slot.v1)
                glyphVertices.append(contentsOf: [tl, tr, br, tl, br, bl])
            }
        }
    }

    /// Walk the lit pixels of `string`, laid out with the active text state,
    /// calling `body` with each pixel's center (canvas space) and module size (its
    /// on-screen side). Shared by `drawBitmapText` and `textToShapes` so the
    /// bitmap layout lives in one place.
    private func forEachBitmapPixel(_ string: String, _ x: Double, _ y: Double,
                                    font: BitmapFont, _ body: (Vector2, Double) -> Void) {
        guard font.pixelHeight > 0 else { return }
        let module = textPixelSize / Double(font.pixelHeight)
        let lines = string.split(separator: "\n", omittingEmptySubsequences: false)
        let blockHeight = Double((lines.count - 1) * font.lineHeight + font.pixelHeight) * module

        // First line's top edge, from the vertical anchor.
        let topY0: Double
        switch textAlignV {
        case .top:      topY0 = y
        case .baseline: topY0 = y - Double(font.baseline) * module
        case .middle:   topY0 = y - blockHeight / 2
        case .bottom:   topY0 = y - blockHeight
        }

        for (lineIndex, line) in lines.enumerated() {
            let lineTop = topY0 + Double(lineIndex * font.lineHeight) * module
            let lineWidth = Double(font.inkWidth(of: String(line))) * module
            // Left edge of this line, from the horizontal anchor.
            var penX: Double
            switch textAlignH {
            case .left:   penX = x
            case .center: penX = x - lineWidth / 2
            case .right:  penX = x - lineWidth
            }

            var previous: Character? = nil
            for ch in line {
                if let prev = previous { penX += Double(font.kerning(between: prev, ch)) * module }
                if let glyph = font.glyph(for: ch) {
                    let cellLeft = penX + Double(glyph.xOffset) * module
                    let cellTop = lineTop + Double(glyph.yOffset) * module
                    for row in 0..<glyph.height {
                        for col in 0..<glyph.width where glyph.isSet(col, row) {
                            let cx = cellLeft + (Double(col) + 0.5) * module
                            let cy = cellTop + (Double(row) + 0.5) * module
                            body(Vector2(cx, cy), module)
                        }
                    }
                }
                penX += Double(font.advance(for: ch)) * module
                previous = ch
            }
        }
    }

    /// The glyph geometry of `string` as `Shape`s positioned at `(x, y)` with the
    /// active `textFont` / `textSize` / `textAlign` — text as first-class geometry
    /// you can fill, stroke, warp, sample, or animate. An **outline** font returns
    /// one `Shape` per glyph (a letter with a counter keeps its hole); a **bitmap**
    /// font returns its lit pixels as little squares.
    func textToShapes(_ string: String, _ x: Double, _ y: Double) -> [Shape] {
        guard textPixelSize > 0, !string.isEmpty else { return [] }
        switch currentFont {
        case .outline(let font):
            let placed = font.placedGlyphs(for: string, size: textPixelSize,
                                           alignH: textAlignH, alignV: textAlignV,
                                           direction: textWritingDirection, at: Vector2(x, y))
            if placed.contains(where: { $0.picture != nil }) {
                noteOnce("an emoji is a picture in the font, not an outline, so textToShapes left it out; drawText still draws it.")
            }
            return OutlineFont.shapes(of: placed)
        case .bitmap(let font):
            var squares: [Contour] = []
            forEachBitmapPixel(string, x, y, font: font) { center, module in
                let h = module / 2
                squares.append(Contour([
                    Vector2(center.x - h, center.y - h), Vector2(center.x + h, center.y - h),
                    Vector2(center.x + h, center.y + h), Vector2(center.x - h, center.y + h),
                ], closed: true))
            }
            return squares.isEmpty ? [] : [Shape(contours: squares)]
        case .stroke(let font):
            // A stroke font's geometry is open pen polylines (no fill) — stroke
            // them, or warp and re-stroke.
            var strokes: [Contour] = []
            forEachStrokeGlyphPolyline(string, x, y, font: font) { polyline in
                strokes.append(Contour(polyline, closed: false))
            }
            return strokes.isEmpty ? [] : [Shape(contours: strokes)]
        }
    }

    /// Draw `string` as solid type in the 3D scene: the active outline font set
    /// at `size` world units and extruded `depth` deep, standing upright and
    /// centered on the model origin. Only the *font* comes from the text state
    /// (with `textAlign`'s horizontal half lining up the rows of a multi-line
    /// string), since `textSize` is measured in canvas points and this size is
    /// measured in world units.
    func drawText3D(_ string: String, size: Double, depth: Double) {
        guard case .outline(let font) = currentFont else {
            noteOnce("drawText3D builds its solid from glyph outlines, so it needs an outline font; the active font is a pixel-grid or single-line face, and nothing was drawn.")
            return
        }
        drawMesh(.text(string, font: font, size: size, depth: depth, align: textAlignH))
    }

    /// The on-screen width of `string`'s widest line, in points, at the active
    /// `textFont` / `textSize` — for laying text out.
    func textWidth(_ string: String) -> Double {
        switch currentFont {
        case .bitmap(let font):
            guard font.pixelHeight > 0 else { return 0 }
            let module = textPixelSize / Double(font.pixelHeight)
            return Double(font.inkWidth(of: string)) * module
        case .outline(let font):
            return font.width(of: string, size: textPixelSize, direction: textWritingDirection)
        case .stroke(let font):
            return font.width(of: string, size: textPixelSize)
        }
    }

    /// The characters in `string` the active font cannot draw, in the order they
    /// appear. An **outline** font asks the whole system, so this is empty unless no
    /// installed face has the character at all (it then draws as a box). A
    /// **bitmap** or **stroke** font has only the glyphs in its own file, and
    /// anything else advances the pen and draws nothing, so this is how to find out
    /// before you draw.
    func textMissingCharacters(_ string: String) -> [Character] {
        switch currentFont {
        case .outline(let font): return font.missingCharacters(in: string)
        case .bitmap(let font):
            return string.filter { $0 != "\n" && font.glyph(for: $0) == nil }
        case .stroke(let font):
            return string.filter { $0 != "\n" && $0 != " " && font.glyph(for: $0) == nil }
        }
    }

    /// Distance from the baseline up to the top of the tallest glyphs, in points,
    /// at the active font and size.
    func textAscent() -> Double {
        switch currentFont {
        case .bitmap(let font):
            guard font.pixelHeight > 0 else { return 0 }
            return Double(font.baseline) * (textPixelSize / Double(font.pixelHeight))
        case .outline(let font):
            return font.ascent * textPixelSize
        case .stroke(let font):
            return font.ascent * textPixelSize
        }
    }

    /// Distance from the baseline down to the bottom of the lowest descenders, in
    /// points, at the active font and size.
    func textDescent() -> Double {
        switch currentFont {
        case .bitmap(let font):
            guard font.pixelHeight > 0 else { return 0 }
            let module = textPixelSize / Double(font.pixelHeight)
            return Double(font.pixelHeight - font.baseline) * module
        case .outline(let font):
            return font.descent * textPixelSize
        case .stroke(let font):
            return font.descent * textPixelSize
        }
    }

    /// The baseline-to-baseline distance for a new line, in points, at the active
    /// font and size (what `\n` advances by).
    func textLeading() -> Double {
        switch currentFont {
        case .bitmap(let font):
            guard font.pixelHeight > 0 else { return 0 }
            return Double(font.lineHeight) * (textPixelSize / Double(font.pixelHeight))
        case .outline(let font):
            return (font.ascent + font.descent + font.leading) * textPixelSize
        case .stroke(let font):
            return (font.ascent + font.descent + font.leading) * textPixelSize
        }
    }

    /// The bounding box `string` occupies if drawn at `(x, y)` with the active text
    /// state — width is the widest line, height spans the whole block.
    func textBounds(_ string: String, _ x: Double, _ y: Double) -> Rectangle {
        let extent = textWidth(string)   // along the writing axis: line width, or column length
        let ascent = textAscent(), descent = textDescent(), advance = textLeading()
        let lineCount = string.split(separator: "\n", omittingEmptySubsequences: false).count
        let across = Double(max(0, lineCount - 1)) * advance

        if runsVertically {
            // A column is one em across where its glyphs stand upright, and as wide
            // as its own ascent and descent where they are turned.
            let blockWidth = across + (turnsGlyphs ? ascent + descent : textPixelSize)
            let left: Double
            switch textAlignH {
            case .left:   left = x
            case .center: left = x - blockWidth / 2
            case .right:  left = x - blockWidth
            }
            let top: Double
            switch textAlignV {
            case .top, .baseline: top = y
            case .middle:         top = y - extent / 2
            case .bottom:         top = y - extent
            }
            return Rectangle(x: left, y: top, width: blockWidth, height: extent)
        }

        let blockHeight = across + ascent + descent
        let top: Double
        switch textAlignV {
        case .top:      top = y
        case .baseline: top = y - ascent
        case .middle:   top = y - blockHeight / 2
        case .bottom:   top = y - blockHeight
        }
        let left: Double
        switch textAlignH {
        case .left:   left = x
        case .center: left = x - extent / 2
        case .right:  left = x - extent
        }
        return Rectangle(x: left, y: top, width: extent, height: blockHeight)
    }

    /// Draw `string` wrapped into `rect`: words break to the next line at the box
    /// width, and `textAlign` positions the wrapped block within the box —
    /// horizontal `.left`/`.center`/`.right` against the box edges, vertical
    /// `.top`/`.middle`/`.bottom`. Explicit `\n`s start new paragraphs. The text
    /// overflows below the box if it's too tall (no vertical clip yet).
    func drawText(_ string: String, in rect: Rectangle) {
        guard textPixelSize > 0, !string.isEmpty else { return }
        let vertical = runsVertically
        // Text wraps when it runs out of room along the axis it travels: the box's
        // width across a line, its height down a column.
        let limit = vertical ? rect.height : rect.width
        guard limit > 0 else { return }
        let (lines, paragraphEnds) = wrappedLines(string, limit)

        // Justification lives for this call only. A box is the one thing that says
        // how far a line should run, so nothing outside it may leave this set.
        if textJustifies {
            textJustification = TextJustification(extent: limit, naturalLines: paragraphEnds)
        }
        // Hanging lives for this call only, for the same reason: the box is the edge
        // a stop hangs past.
        textHangsInBox = textHangsPunctuation
        defer { textJustification = nil; textHangsInBox = false }

        // Each alignment names a box edge, and the plain `drawText` already reads
        // those two axes the way the current writing direction needs, so the anchors
        // themselves do not change: what changes is which one aligns the lines and
        // which one places the block. Vertical text fills from the right, so
        // `textAlign(.right, .top)` is what fills a box from its opening corner.
        let anchorX: Double
        switch textAlignH {
        case .left:   anchorX = rect.x
        case .center: anchorX = rect.center.x
        case .right:  anchorX = rect.x + rect.width
        }
        let anchorY: Double
        switch textAlignV {
        case .top, .baseline: anchorY = rect.y   // a box anchors the block's top edge
        case .middle:         anchorY = rect.center.y
        case .bottom:         anchorY = rect.y + rect.height
        }
        drawText(lines.joined(separator: "\n"), anchorX, anchorY)
    }

    /// Greedily break `string` into lines that run no further than `maxExtent` along
    /// the writing axis at the current font and size: the width of a line, the length
    /// of a column. Existing `\n`s are kept as paragraph breaks. Returns the
    /// rewrapped string for the normal `drawText` to lay out.
    ///
    /// Where a line may break comes from the system's own rules rather than from
    /// the spaces in the text (`LineBreaks`), because most of the world does not
    /// mark word ends with a space: Japanese breaks between characters and Thai
    /// between words that nothing in the string separates. A piece longer than the
    /// box on its own keeps its line and overflows.
    ///
    /// Those rules carry the Japanese ones with them. A piece is the unit that may
    /// not be split, so a closing bracket, a full stop and a small kana all arrive
    /// joined to the character they follow, and an opening bracket to the one it
    /// precedes. Filling greedily by whole pieces is therefore what pushes a
    /// forbidden character onto the next line along with its neighbor, which is the
    /// behavior those rules ask for.
    func wrapToExtent(_ string: String, _ maxExtent: Double) -> String {
        wrappedLines(string, maxExtent).lines.joined(separator: "\n")
    }

    /// The same wrap, keeping which lines end a paragraph rather than a box.
    ///
    /// Once the lines are joined the two kinds of break look identical, and only one
    /// of them may be stretched: a line that ends because the writing ended is short
    /// on purpose. So the wrap is asked for the distinction while it still knows it.
    func wrappedLines(_ string: String, _ maxExtent: Double) -> (lines: [String], paragraphEnds: Set<Int>) {
        var lines: [String] = []
        var paragraphEnds: Set<Int> = []
        for paragraph in string.split(separator: "\n", omittingEmptySubsequences: false) {
            var current = ""
            for piece in LineBreaks.pieces(of: String(paragraph)) {
                let candidate = current + piece
                // Trailing spaces belong to the line that ends there, so they are
                // not measured against the box. A stop allowed to hang is not
                // measured either: that is the whole of what hanging does here, and
                // it is why the piece it rides on can stay on this line.
                let trimmed = trimmedTrailing(candidate)
                if current.isEmpty || textWidth(trimmed) - hangingWidth(of: trimmed) <= maxExtent {
                    current = candidate
                } else {
                    lines.append(trimmedTrailing(current))
                    current = piece
                }
            }
            lines.append(trimmedTrailing(current))
            paragraphEnds.insert(lines.count - 1)
        }
        return (lines, paragraphEnds)
    }

    /// How far `line`'s last character reaches past the rest of it, in points, when
    /// hanging is on and that character is one that may hang. Zero otherwise.
    ///
    /// Measured as the difference the character makes to the line rather than read
    /// off the character on its own, so it carries whatever the shaping did about
    /// the pair. It costs a second measurement, and only a line that ends in a stop
    /// pays it.
    func hangingWidth(of line: String) -> Double {
        guard textHangsPunctuation, HangingPunctuation.endsWithHangable(line) else { return 0 }
        return max(0, textWidth(line) - textWidth(String(line.dropLast())))
    }

    /// `string` without its trailing whitespace.
    private func trimmedTrailing(_ string: String) -> String {
        var out = string
        while let last = out.last, last.isWhitespace { out.removeLast() }
        return out
    }

    /// Draw `string` glyph by glyph, handing each to `perGlyph` so you can give it
    /// its own transform or color before stamping it (`TextGlyph.draw()`). Laid out
    /// on a single line with the active `textFont` / `textSize` / `textAlign`; you
    /// do the drawing, so `fill` / `stroke` and any transform apply per glyph.
    func drawText(_ string: String, _ x: Double, _ y: Double, perGlyph: (TextGlyph) -> Void) {
        guard textPixelSize > 0, !string.isEmpty else { return }
        let run = glyphRun(string)
        guard !run.isEmpty else { return }

        let runLength = (run.last?.pen ?? 0) + (run.last?.advance ?? 0)
        let ascent = textAscent(), descent = textDescent()
        let vertical = runsVertically

        // Where the run starts, and the fixed coordinate it holds across its own
        // axis: the baseline of a line, the center axis of a column.
        // How wide the column is, and where its axis sits inside it: an em square
        // either side of the middle where the glyphs stand upright, the ascent and
        // the descent either side of the baseline where they are turned.
        let turned = turnsGlyphs
        let columnWidth = turned ? ascent + descent : textPixelSize
        let axisFromLeft = turned ? descent : textPixelSize / 2
        let runStart: Double, across: Double
        if vertical {
            switch textAlignV {
            case .top, .baseline: runStart = y
            case .middle:         runStart = y - runLength / 2
            case .bottom:         runStart = y - runLength
            }
            switch textAlignH {
            case .left:   across = x + axisFromLeft
            case .center: across = x + axisFromLeft - columnWidth / 2
            case .right:  across = x + axisFromLeft - columnWidth
            }
        } else {
            switch textAlignH {
            case .left:   runStart = x
            case .center: runStart = x - runLength / 2
            case .right:  runStart = x - runLength
            }
            switch textAlignV {
            case .top:      across = y + ascent
            case .baseline: across = y
            case .middle:   across = y + (ascent - descent) / 2
            case .bottom:   across = y - descent
            }
        }
        // A stroke font's glyph geometry is open pen paths: stroke them rather than
        // fill (the same split `drawText` makes between the font kinds).
        let strokesGlyphs = currentFont.isStroke

        for (index, item) in run.enumerated() {
            let origin = vertical ? Vector2(across, runStart + item.pen)
                                  : Vector2(runStart + item.pen, across)
            let shapes = item.localShapes.map { shifted($0, by: origin) }
            // The piece's own cell: the advance box across a line, and down a column
            // the em-wide square the writing system sets to.
            let bounds = vertical
                ? Rectangle(x: origin.x - axisFromLeft, y: origin.y,
                            width: columnWidth, height: item.advance)
                : Rectangle(x: origin.x, y: origin.y - ascent,
                            width: item.advance, height: ascent + descent)
            let picture = item.picture
            let pictureRect = Rectangle(x: origin.x + item.localPictureRect.x,
                                        y: origin.y + item.localPictureRect.y,
                                        width: item.localPictureRect.width,
                                        height: item.localPictureRect.height)
            let glyph = TextGlyph(text: item.text, index: index, count: run.count,
                                  position: origin, bounds: bounds, shapes: shapes,
                                  isPicture: picture != nil,
                                  drawThunk: { [weak self] in
                                      guard let self else { return }
                                      if let picture {
                                          self.drawImage(picture, in: pictureRect)
                                      } else if strokesGlyphs {
                                          shapes.forEach { $0.contours.forEach { self.drawPolyline($0.points) } }
                                      } else {
                                          self.withTextStroke { shapes.forEach { self.drawShape($0) } }
                                      }
                                  })
            perGlyph(glyph)
        }
    }

    /// Draw `string` with its glyphs riding `path`: each glyph is centered on the
    /// point `offset + (its distance along the run)` measured as arc length from the
    /// path's start, and rotated to the path's tangent there (its baseline sits on
    /// the curve). Glyphs that fall before the start or past the end are skipped, so
    /// animating `offset` flows the text on and off the ends. Single-line; takes
    /// `fill` and `stroke` like `drawText`.
    ///
    /// The text always runs *along* the path, so `textDirection(.topToBottom)` is
    /// not honored here: the curve already carries the direction the writing would
    /// have supplied, and the sideways glyph forms would fight the turn it applies.
    func drawText(_ string: String, along path: Path, offset: Double) {
        guard textPixelSize > 0, !string.isEmpty else { return }
        guard fillPaint != nil || (strokePaint != nil && strokeWidth > 0) else { return }
        if runsVertically {
            noteOnce("text on a path follows the path, so a column direction does not apply to it; the run stays along the curve.")
        }
        let run = glyphRun(string, vertical: false)
        let points = path.contour.points
        guard run.count > 0, points.count >= 2 else { return }

        // Cumulative arc length along the flattened path.
        var cumulative: [Double] = [0]
        cumulative.reserveCapacity(points.count)
        for i in 1..<points.count { cumulative.append(cumulative[i - 1] + (points[i] - points[i - 1]).length) }
        let total = cumulative.last ?? 0
        guard total > 0 else { return }
        let strokesGlyphs = currentFont.isStroke   // stroke open pen paths, don't fill

        for item in run {
            let distance = offset + item.pen + item.advance / 2
            guard distance >= 0, distance <= total else { continue }   // off the path: skip
            let (anchor, angle) = pointAndTangent(points: points, cumulative: cumulative, at: distance)
            let cosA = cos(angle), sinA = sin(angle)
            if let picture = item.picture {
                // A picture cannot bend, so it rides the curve upright, centered on
                // its own point like every other piece.
                let rect = item.localPictureRect
                let lx = rect.center.x - item.advance / 2, ly = rect.center.y
                let center = Vector2(anchor.x + lx * cosA - ly * sinA,
                                     anchor.y + lx * sinA + ly * cosA)
                drawImage(picture, in: Rectangle(x: center.x - rect.width / 2,
                                                 y: center.y - rect.height / 2,
                                                 width: rect.width, height: rect.height))
                continue
            }
            for shape in item.localShapes {
                let placed = shape.mapPoints { q in
                    // Center the glyph on its anchor, then rotate to the tangent.
                    let lx = q.x - item.advance / 2
                    let ly = q.y
                    return Vector2(anchor.x + lx * cosA - ly * sinA,
                                   anchor.y + lx * sinA + ly * cosA)
                }
                if strokesGlyphs {
                    placed.contours.forEach { drawPolyline($0.points) }
                } else {
                    withTextStroke { drawShape(placed) }
                }
            }
        }
    }

    /// The point and tangent angle at arc-length `distance` along a flattened path.
    private func pointAndTangent(points: [Vector2], cumulative: [Double],
                                 at distance: Double) -> (Vector2, Double) {
        let d = min(max(distance, 0), cumulative.last ?? 0)
        var i = 1
        while i < cumulative.count, cumulative[i] < d { i += 1 }
        guard i < points.count else {
            let dir = points[points.count - 1] - points[points.count - 2]
            return (points[points.count - 1], atan2(dir.y, dir.x))
        }
        let segmentLength = cumulative[i] - cumulative[i - 1]
        let t = segmentLength > 0 ? (d - cumulative[i - 1]) / segmentLength : 0
        let a = points[i - 1], b = points[i]
        let dir = b - a
        return (a + dir * t, atan2(dir.y, dir.x))
    }

    /// The active font's single-line glyph run (see `GlyphRunItem`), dispatched on
    /// the font kind.
    private func glyphRun(_ string: String, vertical: Bool = true) -> [GlyphRunItem] {
        switch currentFont {
        case .outline(let font):
            let along = vertical && runsVertically
            return font.glyphRun(for: string, size: textPixelSize,
                                 direction: along ? textWritingDirection : horizontalDirection)
        case .bitmap(let font):  return bitmapGlyphRun(string, font: font)
        case .stroke(let font):  return strokeGlyphRun(string, font: font)
        }
    }

    /// Whether the text being drawn now really runs down a column.
    ///
    /// Vertical setting needs the sideways glyph forms and the column positions the
    /// system's layout engine supplies, which only an outline font goes through. A
    /// bitmap or stroke font has neither, so it says so once and stays horizontal,
    /// the way it already does for a right-to-left line.
    var runsVertically: Bool {
        guard textWritingDirection.isVertical else { return false }
        guard case .outline = currentFont else {
            noteOnce("a column needs an outline font for the shaping the system's layout engine supplies, so this text stays horizontal.")
            return false
        }
        return true
    }

    /// Whether the column being drawn now turns its glyphs rather than setting them
    /// upright on an em square. Only a real column can, so this reads the font too.
    var turnsGlyphs: Bool { runsVertically && textWritingDirection.turnsGlyphs }

    /// The writing direction with the vertical axis taken out: what a path lays its
    /// text along. A path already says which way the text travels and how it turns,
    /// so a column has nothing left to mean there, while left-to-right and
    /// right-to-left still decide the order the pieces ride in.
    private var horizontalDirection: TextDirection {
        textWritingDirection.isVertical ? .automatic : textWritingDirection
    }

    /// A stroke font's single-line glyph run — each glyph's pen polylines as local
    /// open `Contour`s (pen origin at the origin, baseline at `y = 0`).
    private func strokeGlyphRun(_ string: String, font: StrokeFont) -> [GlyphRunItem] {
        guard font.unitsPerEm > 0, textPixelSize > 0 else { return [] }
        let scale = textPixelSize / font.unitsPerEm
        var items: [GlyphRunItem] = []
        var penX = 0.0
        for ch in string.replacingOccurrences(of: "\n", with: " ") {
            var contours: [Contour] = []
            if let glyph = font.glyph(for: ch) {
                for polyline in glyph.polylines {
                    contours.append(Contour(polyline.map { Vector2($0.x * scale, $0.y * scale) }, closed: false))
                }
            }
            let advance = font.advanceUnits(for: ch) * scale
            items.append(GlyphRunItem(text: String(ch), pen: penX, advance: advance,
                                      localShapes: contours.isEmpty ? [] : [Shape(contours: contours)],
                                      picture: nil,
                                      localPictureRect: Rectangle(x: 0, y: 0, width: 0, height: 0)))
            penX += advance
        }
        return items
    }

    /// A bitmap font's single-line glyph run — each glyph's lit pixels as local
    /// square `Contour`s (pen origin at the origin, baseline at `y = 0`).
    private func bitmapGlyphRun(_ string: String, font: BitmapFont) -> [GlyphRunItem] {
        guard font.pixelHeight > 0, textPixelSize > 0 else { return [] }
        let module = textPixelSize / Double(font.pixelHeight)
        let baselineLocal = Double(font.baseline) * module
        var items: [GlyphRunItem] = []
        var penX = 0.0
        var previous: Character? = nil
        for ch in string.replacingOccurrences(of: "\n", with: " ") {
            if let prev = previous { penX += Double(font.kerning(between: prev, ch)) * module }
            var squares: [Contour] = []
            if let glyph = font.glyph(for: ch) {
                let cellLeft = Double(glyph.xOffset) * module
                let cellTop = Double(glyph.yOffset) * module - baselineLocal   // baseline at y = 0
                for row in 0..<glyph.height {
                    for col in 0..<glyph.width where glyph.isSet(col, row) {
                        let cx = cellLeft + (Double(col) + 0.5) * module
                        let cy = cellTop + (Double(row) + 0.5) * module
                        let h = module / 2
                        squares.append(Contour([Vector2(cx - h, cy - h), Vector2(cx + h, cy - h),
                                                Vector2(cx + h, cy + h), Vector2(cx - h, cy + h)], closed: true))
                    }
                }
            }
            let advance = Double(font.advance(for: ch)) * module
            items.append(GlyphRunItem(text: String(ch), pen: penX, advance: advance,
                                      localShapes: squares.isEmpty ? [] : [Shape(contours: squares)],
                                      picture: nil,
                                      localPictureRect: Rectangle(x: 0, y: 0, width: 0, height: 0)))
            penX += advance
            previous = ch
        }
        return items
    }

    /// A `Shape` with every contour point shifted by `offset` (winding preserved).
    private func shifted(_ shape: Shape, by offset: Vector2) -> Shape {
        shape.mapPoints { $0 + offset }
    }

    /// A straight line segment from `a` to `b`, stroked with the current stroke
    /// paint and weight. Rendered through the high-quality fringe expander — edge-
    /// expanded triangles plus a ~1px AA fringe — so it's crisp at any angle and
    /// resolution, honoring `strokeCap` (`.butt` by default). Solid, translucent,
    /// and gradient strokes all take this path. Needs a stroke to draw.
    func drawLine(_ a: Vector2, _ b: Vector2) {
        guard let stroke = strokePaint, strokeWidth > 0 else { return }
        if strokedAsBrush([a, b], closed: false) { return }
        if svgRecorder != nil {
            svgRecord(.line(a, b), fill: nil, stroke: stroke)
            return
        }
        guard (b - a).length > 1e-9 else { return }
        // A hairline is almost impossible to hit with a pointer, so the region a
        // host picks it by is at least a few points wide either side of it.
        if recordsSourceSites {
            recordSourcePick(.capsule(a: a, b: b, radius: Swift.max(strokeWidth / 2, 5)))
        }
        appendFringeStroke([a, b], closed: false, paint: vertexPaint(stroke, anchor: (a + b) / 2))
    }

    /// A rectangle whose long axis runs from `a` to `b` with the given `thickness`
    /// across it — a thick bar between two points, with square (not round) ends.
    /// Unlike `drawRect`, which is axis-aligned and rotated via the transform stack,
    /// this places the bar by its two endpoints, so connecting a pair of moving
    /// points is one call. It's a filled region (takes `fill`, an outline `stroke`,
    /// `strokeAlign`, and `hollow`), where `drawLine` is a round-capped stroke.
    /// Recorded as a single analytic SDF instance — crisp at any size and
    /// effectively free. A zero-length bar (`a == b`) or non-positive thickness
    /// draws nothing.
    func drawOrientedBox(_ a: Vector2, _ b: Vector2, thickness: Double) {
        guard thickness > 0, (b - a).length > 1e-9 else { return }
        let center = (a + b) / 2
        let dir = (b - a) / (b - a).length
        let halfLen = (b - a).length / 2
        let halfThick = thickness / 2
        // AABB half-extent of the rotated box: each axis is reached by the
        // corner that combines the box's half-length along `dir` and half-thickness
        // along the perpendicular (|perp.x| == |dir.y|, |perp.y| == |dir.x|).
        let half = SIMD2<Float>(
            Float(halfLen * abs(dir.x) + halfThick * abs(dir.y)),
            Float(halfLen * abs(dir.y) + halfThick * abs(dir.x)))
        if svgRecorder != nil {
            let perp = Vector2(-dir.y, dir.x)
            let along = dir * halfLen, across = perp * halfThick
            svgRecord(.polygon([center + along + across, center + along - across,
                                center - along - across, center - along + across]),
                      fill: fillPaint, stroke: strokePaint)
            return
        }
        appendSDF(shape: .orientedBox, center: center, size: half,
                  fill: fillPaint, stroke: strokePaint, extra: Float(thickness),
                  param0: (a - center).simd2, param1: (b - center).simd2)
    }

    /// An oriented box through scalar endpoint coordinates — the positional form of
    /// `drawOrientedBox(_:_:thickness:)`: the centerline from `(x1, y1)` to `(x2, y2)`.
    func drawOrientedBox(_ x1: Double, _ y1: Double, _ x2: Double, _ y2: Double, thickness: Double) {
        drawOrientedBox(Vector2(x1, y1), Vector2(x2, y2), thickness: thickness)
    }

    /// A vesica (a pointed lens) whose two tips are placed at `a` and `b`, bulging
    /// to `width` across the middle. Like `drawOrientedBox`, it's positioned by its
    /// two endpoints rather than a center and rotation, so spanning a moving pair of
    /// points is one call. It's a filled region (takes `fill`, an outline `stroke`,
    /// `strokeAlign`, and `hollow`). `width` is the full waist width; keeping it
    /// below the tip distance gives a lens, equal to it gives a circle. A zero-length
    /// span (`a == b`) or non-positive width draws nothing. Recorded as a single
    /// analytic SDF instance — crisp at any size and effectively free.
    func drawOrientedVesica(_ a: Vector2, _ b: Vector2, width: Double) {
        guard width > 0, (b - a).length > 1e-9 else { return }
        let center = (a + b) / 2
        let dir = (b - a) / (b - a).length
        let halfLen = (b - a).length / 2
        let halfWidth = width / 2
        // The lens is inscribed in the oriented box of half-length `halfLen` (along
        // the tip axis) and half-width `halfWidth` (across it), so its AABB is the
        // same as that box's (see drawOrientedBox).
        let half = SIMD2<Float>(
            Float(halfLen * abs(dir.x) + halfWidth * abs(dir.y)),
            Float(halfLen * abs(dir.y) + halfWidth * abs(dir.x)))
        if svgRecorder != nil {
            let perp = Vector2(-dir.y, dir.x)
            let local = SDFOutline.orientedVesica(halfLength: halfLen, halfWidth: halfWidth)
            svgRecordTraced(local.map { loop in loop.map { center + dir * $0.x + perp * $0.y } },
                            fill: fillPaint, stroke: strokePaint)
            return
        }
        appendSDF(shape: .orientedVesica, center: center, size: half,
                  fill: fillPaint, stroke: strokePaint, extra: Float(halfWidth),
                  param0: (a - center).simd2, param1: (b - center).simd2)
    }

    /// An oriented vesica through scalar tip coordinates — the positional form of
    /// `drawOrientedVesica(_:_:width:)`: tips at `(x1, y1)` and `(x2, y2)`.
    func drawOrientedVesica(_ x1: Double, _ y1: Double, _ x2: Double, _ y2: Double, width: Double) {
        drawOrientedVesica(Vector2(x1, y1), Vector2(x2, y2), width: width)
    }

    /// A quadratic Bézier curve stroked with the current stroke paint and weight:
    /// from `start` to `end`, bending toward the single control point `control`.
    /// The curve flattens to a polyline and renders through the high-quality fringe
    /// expander — smooth at any angle and resolution, no tessellated fill or SDF.
    /// Solid, translucent, and gradient strokes all take this path. Stroke-only: a
    /// curve has no interior, so it takes the current stroke (not fill). For a cubic
    /// curve (two control points), sample it into a `Shape` contour. Needs a stroke
    /// to draw.
    func drawBezier(_ start: Vector2, _ control: Vector2, _ end: Vector2) {
        guard let stroke = strokePaint, strokeWidth > 0 else { return }
        if strokeBrushShape != nil {
            var flat = [start]
            flat.append(contentsOf: CurveSampling.quadratic(from: start, control: control, end: end))
            if strokedAsBrush(flat, closed: false) { return }
        }
        if svgRecorder != nil {
            svgRecord(.quad(start: start, control: control, end: end), fill: nil, stroke: stroke)
            return
        }
        var pts = [start]
        pts.append(contentsOf: CurveSampling.quadratic(from: start, control: control, end: end))
        appendFringeStroke(pts, closed: false, paint: vertexPaint(stroke, anchor: (start + end) / 2))
    }

    /// A quadratic Bézier curve through scalar coordinates — the positional form of
    /// `drawBezier(_:_:_:)`: `(x1, y1)` start, `(cx, cy)` control, `(x2, y2)` end.
    func drawBezier(_ x1: Double, _ y1: Double, _ cx: Double, _ cy: Double,
                    _ x2: Double, _ y2: Double) {
        drawBezier(Vector2(x1, y1), Vector2(cx, cy), Vector2(x2, y2))
    }

    /// A filled, **convex** polygon through `points` (triangle fan), plus a
    /// stroked closed outline if a stroke is set. The fan only fills correctly
    /// for convex inputs (triangles, quads, regular n-gons, convex pieces); for
    /// concave outlines or holes, build a `Shape` and use `drawShape`, which
    /// triangulates properly.
    func drawPolygon(_ points: [Vector2]) {
        guard points.count >= 3 else { return }
        if svgRecorder != nil {
            svgRecord(.polygon(points), fill: fillPaint, stroke: strokePaint)
            return
        }
        if let fill = fillPaint {
            let vp = vertexPaint(fill, anchor: Drawer.boundsCenter(points))
            let p0 = points[0].simd2
            let c0 = vp.color(at: points[0])
            replicated {
                for i in 1..<(points.count - 1) {    // fan from the first vertex
                    emit(p0, color: c0)
                    emit(points[i].simd2, color: vp.color(at: points[i]))
                    emit(points[i + 1].simd2, color: vp.color(at: points[i + 1]))
                }
            }
        }
        if let stroke = strokePaint, strokeWidth > 0 {
            appendFringeStroke(points, closed: true,
                               paint: vertexPaint(stroke, anchor: Drawer.boundsCenter(points)))
        }
    }

    /// A vector `Shape`: a filled region that may be **concave** and may have
    /// **holes**, plus a stroked outline of each contour. The fill is
    /// triangulated (even-odd winding, so nested contours cut holes); open
    /// contours are stroke-only. Both fill and stroke go through the triangle
    /// path, so a `Shape` composites in draw order with everything else.
    func drawShape(_ shape: Shape) {
        // A brushed outline stamps on the vector path as well as the raster one,
        // so the fill is emitted on its own first (this call again, with no
        // stroke) and the stamps follow it in draw order.
        if strokeBrushShape != nil, strokePaint != nil, strokeWidth > 0 {
            let saved = strokePaint
            strokePaint = nil
            drawShape(shape)
            strokePaint = saved
            for contour in shape.contours where contour.points.count >= 2 {
                _ = strokedAsBrush(contour.points, closed: contour.isClosed)
            }
            return
        }
        if svgRecorder != nil {
            svgRecord(.path(shape), fill: fillPaint, stroke: strokePaint)
            return
        }
        if let fill = fillPaint {
            let vp = vertexPaint(fill, anchor: Drawer.boundsCenter(shape.contours.flatMap(\.points)))
            let triangles = shape.triangulatedFill()
            replicated {
                for i in stride(from: 0, to: triangles.count - 2, by: 3) {
                    emit(triangles[i].simd2, color: vp.color(at: triangles[i]))
                    emit(triangles[i + 1].simd2, color: vp.color(at: triangles[i + 1]))
                    emit(triangles[i + 2].simd2, color: vp.color(at: triangles[i + 2]))
                }
            }
        }
        if let stroke = strokePaint, strokeWidth > 0 {
            for contour in shape.contours where contour.points.count >= 2 {
                appendFringeStroke(contour.points, closed: contour.isClosed,
                                   paint: vertexPaint(stroke, anchor: contour.points[0]))
            }
        }
    }
}
