import CoreGraphics
import CoreText
import Foundation
import Metal

// The contact-sheet export: render one frame of a sketch at each of a list of
// variation seeds and tile the results into a single labeled proof sheet, the
// way a generative artist culls a seed space for the keepers. Each tile is a
// fresh instance of the sketch seeded before `setup()`, driven by the same
// fixed-timestep headless engine as every other export, so a tile matches what
// `--export --seed N` would render at full resolution.

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
        guard !seeds.isEmpty, let device = MTLCreateSystemDefaultDevice(),
              let renderer = try? MetalRenderer(device: device, pixelFormat: ollinColorPixelFormat,
                                                sampleCount: ollinPreferredSampleCount(device)) else {
            return nil
        }
        renderer.automaticQuality = quality
        isRenderingHeadless = true
        defer { isRenderingHeadless = false }

        // Grid geometry, from the canvas aspect of the first tile's instance
        // (every tile is the same sketch class, so one probe covers the sheet).
        let first = make()
        let canvas = first.canvasSize
        let tileW = max(64, tileWidth)
        let tileH = max(1, Int((Double(tileW) * Double(canvas.height) / Double(canvas.width)).rounded()))
        let cols = max(1, columns ?? Int(Double(seeds.count).squareRoot().rounded(.up)))
        let rows = (seeds.count + cols - 1) / cols
        let margin = max(10, tileW / 20)
        let gutter = margin
        let labelHeight = max(20, Int(Double(tileW) * 0.085))
        let cellHeight = tileH + labelHeight
        let sheetWidth = margin * 2 + cols * tileW + (cols - 1) * gutter
        let sheetHeight = margin * 2 + rows * cellHeight + (rows - 1) * gutter

        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(data: nil, width: sheetWidth, height: sheetHeight,
                                      bitsPerComponent: 8, bytesPerRow: 0, space: space,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
            return nil
        }
        context.setFillColor(CGColor(srgbRed: 0.09, green: 0.09, blue: 0.10, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: sheetWidth, height: sheetHeight))
        context.interpolationQuality = .high
        context.textMatrix = .identity

        for (index, seed) in seeds.enumerated() {
            let sketch = index == 0 ? first : make()
            sketch.seed(seed)
            renderer.resetAccumulation()   // a `noClear()` pile must not leak across tiles
            guard let tile = renderImage(of: sketch, frame: frame, fps: fps, renderer: renderer) else {
                FileHandle.standardError.write(Data("\nOllin: failed to render seed \(seed)\n".utf8))
                return nil
            }
            let column = index % cols, row = index / cols
            let x = margin + column * (tileW + gutter)
            let topDownY = margin + row * (cellHeight + gutter)
            let tileRect = CGRect(x: x, y: sheetHeight - topDownY - tileH, width: tileW, height: tileH)
            context.draw(tile, in: tileRect)
            drawSheetLabel("\(seed)", in: context,
                           centerX: tileRect.midX,
                           baselineY: tileRect.minY - Double(labelHeight) * 0.70,
                           fontSize: Double(labelHeight) * 0.46)

            let line = String(format: "\r  rendering tile %d/%d (seed %d)    ",
                              index + 1, seeds.count, seed)
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
