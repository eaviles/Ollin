import CoreGraphics
import CoreText
import Foundation
import Metal

// The contact-sheet export: render one frame of a sketch per tile and lay the
// results into a single labeled proof sheet, the way a generative artist culls
// a space for the keepers. Two spaces are sweepable: the variation seeds (one
// tile per seed) and a named `@Param` (one tile per value, seed pinned). Each
// tile is a fresh instance of the sketch prepared before `setup()`, driven by
// the same fixed-timestep headless engine as every other export, so a tile
// matches what a full-resolution export with the same settings would render.

extension OllinApp {

    /// Render `frame` of the sketch at each seed in `seeds` and tile the
    /// results into one proof-sheet image: a grid of thumbnails, each labeled
    /// with the seed that made it. `make` supplies a fresh sketch per tile (a
    /// stateful sketch must start clean for every seed); each instance is
    /// seeded before `setup()` runs, so a sketch that pins its own seed there
    /// renders the same tile every time. One renderer is reused across the
    /// whole sheet. Returns `nil` with no Metal device, a failed render, or
    /// empty `seeds`.
    ///
    /// `columns` defaults to the squarest grid; `tileWidth` is each thumbnail's
    /// width in pixels (height follows the canvas aspect).
    public static func contactSheet(of make: () -> Sketch, seeds: [Int],
                                    frame: Int = 0, fps: Double = 60,
                                    columns: Int? = nil, tileWidth: Int = 320,
                                    quality: RenderQuality = .detail) -> CGImage? {
        renderSheet(of: make,
                    tiles: seeds.map { seed in ("\(seed)", { $0.seed(seed) }) },
                    frame: frame, fps: fps, columns: columns,
                    tileWidth: tileWidth, quality: quality)
    }

    /// Render `frame` of the sketch at each value of a named `@Param` and tile
    /// the results into one proof-sheet image: a grid of thumbnails, each
    /// labeled with the value that made it. The complement of the seed sheet:
    /// where `contactSheet(of:seeds:)` walks the sketch's chance, this walks
    /// one of its knobs.
    ///
    /// `name` is the `@Param` property's name (`"radius"`, not `"Radius"`);
    /// numeric values apply to `Double` and `Int` parameters through the same
    /// restore path the live hosts use to carry knobs across reloads, so a
    /// value lands exactly as if the knob had been dragged there. Every tile
    /// runs at the same `seed` (one is rolled and recorded when not given), so
    /// the parameter is the only thing changing across the sheet. Returns
    /// `nil` when the sketch has no parameter by that name, listing what it
    /// does have on standard error.
    public static func contactSheet(of make: () -> Sketch,
                                    sweeping name: String, values: [Double],
                                    seed: Int? = nil,
                                    frame: Int = 0, fps: Double = 60,
                                    columns: Int? = nil, tileWidth: Int = 320,
                                    quality: RenderQuality = .detail) -> CGImage? {
        guard !values.isEmpty else { return nil }
        let probe = make()
        let handles = probe.parameters()
        guard handles.contains(where: { $0.name == name }) else {
            let available = handles.map(\.name).sorted().joined(separator: ", ")
            FileHandle.standardError.write(Data(
                "Ollin: no @Param named '\(name)'; this sketch has: \(available.isEmpty ? "none" : available)\n".utf8))
            return nil
        }
        let pinned = seed ?? Int.random(in: 1 ... 99_999)
        return renderSheet(of: make,
                           tiles: values.map { value in
                               (sheetNumber(value), { sketch in
                                   sketch.seed(pinned)
                                   sketch.parameters()
                                       .first(where: { $0.name == name })?
                                       .param.restore(.number(value))
                               })
                           },
                           frame: frame, fps: fps, columns: columns,
                           tileWidth: tileWidth, quality: quality)
    }

    /// The shared tiling core: one fresh sketch per tile, prepared by its
    /// tile's closure before the headless drive runs `setup()`, rendered
    /// through one reused renderer, and labeled.
    private static func renderSheet(of make: () -> Sketch,
                                    tiles: [(label: String, prepare: (Sketch) -> Void)],
                                    frame: Int, fps: Double, columns: Int?,
                                    tileWidth: Int, quality: RenderQuality) -> CGImage? {
        guard !tiles.isEmpty, let device = MTLCreateSystemDefaultDevice() else { return nil }

        // The first tile's instance doubles as the probe for everything the
        // sheet needs to know up front: its canvas aspect and its declared
        // `colorOutput` (every tile is the same sketch class, so one covers the
        // sheet). It must not be an extra instance, since the caller's factory
        // is expected to run exactly once per tile.
        let first = make()
        let output = first.colorOutput
        guard let renderer = try? MetalRenderer(device: device,
                                                pixelFormat: output.drawablePixelFormat,
                                                sampleCount: ollinPreferredSampleCount(device),
                                                encoding: output.presentEncoding) else {
            return nil
        }
        renderer.automaticQuality = quality
        renderer.renderScale = OllinApp.exportRenderScale
        isRenderingHeadless = true
        defer { isRenderingHeadless = false }

        let canvas = first.canvasSize
        let tileW = max(64, tileWidth)
        let tileH = max(1, Int((Double(tileW) * Double(canvas.height) / Double(canvas.width)).rounded()))
        let cols = max(1, columns ?? Int(Double(tiles.count).squareRoot().rounded(.up)))
        let rows = (tiles.count + cols - 1) / cols
        let margin = max(10, tileW / 20)
        let gutter = margin
        let labelHeight = max(20, Int(Double(tileW) * 0.085))
        let cellHeight = tileH + labelHeight
        let sheetWidth = margin * 2 + cols * tileW + (cols - 1) * gutter
        let sheetHeight = margin * 2 + rows * cellHeight + (rows - 1) * gutter

        // The sheet is composited in the sketch's own gamut, so a wide-gamut
        // sketch's tiles aren't clipped back to sRGB on the way onto it.
        guard let space = CGColorSpace(name: output == .standard ? CGColorSpace.sRGB : CGColorSpace.displayP3),
              let context = CGContext(data: nil, width: sheetWidth, height: sheetHeight,
                                      bitsPerComponent: 8, bytesPerRow: 0, space: space,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
            return nil
        }
        context.setFillColor(CGColor(srgbRed: 0.09, green: 0.09, blue: 0.10, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: sheetWidth, height: sheetHeight))
        context.interpolationQuality = .high
        context.textMatrix = .identity

        for (index, tile) in tiles.enumerated() {
            let sketch = index == 0 ? first : make()
            tile.prepare(sketch)
            renderer.resetAccumulation()   // a `noClear()` pile must not leak across tiles
            guard let image = renderImage(of: sketch, frame: frame, fps: fps, renderer: renderer) else {
                FileHandle.standardError.write(Data("\nOllin: failed to render tile '\(tile.label)'\n".utf8))
                return nil
            }
            let column = index % cols, row = index / cols
            let x = margin + column * (tileW + gutter)
            let topDownY = margin + row * (cellHeight + gutter)
            let tileRect = CGRect(x: x, y: sheetHeight - topDownY - tileH, width: tileW, height: tileH)
            context.draw(image, in: tileRect)
            drawSheetLabel(tile.label, in: context,
                           centerX: tileRect.midX,
                           baselineY: tileRect.minY - Double(labelHeight) * 0.70,
                           fontSize: Double(labelHeight) * 0.46)

            let line = String(format: "\r  rendering tile %d/%d (%@)    ",
                              index + 1, tiles.count, tile.label)
            FileHandle.standardError.write(Data(line.utf8))
        }
        FileHandle.standardError.write(Data("\n".utf8))
        return context.makeImage()
    }

    /// Render a contact sheet (see `contactSheet(of:seeds:)`) and write it as a
    /// PNG carrying the sheet's reproduction recipe (the seed list, frame, and
    /// fps), so the sheet itself records how to regenerate any tile.
    public static func exportContactSheet(_ make: () -> Sketch, to path: String, seeds: [Int],
                                          frame: Int = 0, fps: Double = 60,
                                          columns: Int? = nil, tileWidth: Int = 320,
                                          quality: RenderQuality = .detail) {
        print("Ollin: rendering a contact sheet of \(seeds.count) seeds")
        guard let sheet = contactSheet(of: make, seeds: seeds, frame: frame, fps: fps,
                                       columns: columns, tileWidth: tileWidth, quality: quality) else {
            fatalError("Ollin: failed to render the contact sheet (no Metal device?)")
        }
        let recipe = ExportMetadata.sheetRecipe(seeds: seeds, frame: frame, fps: fps)
        guard writePNG(sheet, to: path, recipe: recipe) else {
            fatalError("Ollin: failed to write \(path)")
        }
        print("Ollin: exported contact sheet of \(seeds.count) seeds → \(path) (\(sheet.width)×\(sheet.height))")
    }

    /// Render a parameter sweep (see `contactSheet(of:sweeping:values:)`) and
    /// write it as a PNG carrying the sweep's reproduction recipe (the
    /// parameter name, its values, and the pinned seed), so the sheet itself
    /// records how to regenerate any tile.
    public static func exportContactSheet(_ make: () -> Sketch, to path: String,
                                          sweeping name: String, values: [Double],
                                          seed: Int? = nil,
                                          frame: Int = 0, fps: Double = 60,
                                          columns: Int? = nil, tileWidth: Int = 320,
                                          quality: RenderQuality = .detail) {
        let pinned = seed ?? Int.random(in: 1 ... 99_999)
        print("Ollin: rendering a sweep of '\(name)' over \(values.count) values at seed \(pinned)")
        guard let sheet = contactSheet(of: make, sweeping: name, values: values,
                                       seed: pinned, frame: frame, fps: fps,
                                       columns: columns, tileWidth: tileWidth, quality: quality) else {
            fatalError("Ollin: failed to render the sweep (unknown parameter, or no Metal device?)")
        }
        let recipe = ExportMetadata.sheetRecipe(sweep: name, values: values, seed: pinned,
                                                frame: frame, fps: fps)
        guard writePNG(sheet, to: path, recipe: recipe) else {
            fatalError("Ollin: failed to write \(path)")
        }
        print("Ollin: exported sweep of '\(name)' over \(values.count) values → \(path) (\(sheet.width)×\(sheet.height))")
    }

    /// A number formatted the way a tile label wants it: `0.25`, not
    /// `0.250000`, and `2`, not `2.0`.
    static func sheetNumber(_ value: Double) -> String {
        String(format: "%g", value)
    }

    /// Draw a centered single-line label into the sheet, monospaced so seed
    /// numbers align column to column.
    private static func drawSheetLabel(_ text: String, in context: CGContext,
                                       centerX: Double, baselineY: Double, fontSize: Double) {
        let font = CTFontCreateWithName("Menlo-Regular" as CFString, fontSize, nil)
        let color = CGColor(srgbRed: 0.66, green: 0.66, blue: 0.70, alpha: 1)
        let attributes = [kCTFontAttributeName: font,
                          kCTForegroundColorAttributeName: color] as CFDictionary
        guard let attributed = CFAttributedStringCreate(nil, text as CFString, attributes) else { return }
        let line = CTLineCreateWithAttributedString(attributed)
        let width = CTLineGetTypographicBounds(line, nil, nil, nil)
        context.textPosition = CGPoint(x: centerX - width / 2, y: baselineY)
        CTLineDraw(line, context)
    }
}
