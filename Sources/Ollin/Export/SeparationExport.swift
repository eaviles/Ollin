import CoreGraphics
import CoreText
import Foundation
import Metal

// The print-separation export: render one frame headlessly, split it into
// per-ink grayscale masters (see `Image.separated(into:paper:)`), and write
// one PNG per ink plus an overprint-preview composite. Every file gets the
// same white margin band with registration targets drawn in full ink at the
// four corners: each drum prints its own targets, so when the crosses stack
// on paper the layers are in register. The artwork itself is never drawn
// over; the band extends the canvas.

extension OllinApp {

    /// Render `frame` of `sketch` headlessly and separate it into per-ink
    /// masters. `inks` falls back to the sketch's declared `printInks`; returns
    /// `nil` with no inks to separate into, no Metal device, or a failed
    /// render. The separation itself is `Image.separated(into:paper:)`.
    @MainActor
    public static func separations(of sketch: Sketch, inks: [Ink]? = nil,
                                   paper: Color = .white,
                                   frame: Int = 0, fps: Double = 60,
                                   quality: RenderQuality = .detail) -> PrintSeparation? {
        guard let inkSet = inks ?? sketch.printInks, !inkSet.isEmpty else { return nil }
        guard let cgImage = image(of: sketch, frame: frame, fps: fps, quality: quality) else {
            return nil
        }
        return Image(cgImage: cgImage).separated(into: inkSet, paper: paper)
    }

    /// Render one frame, separate it, and write the print files: one grayscale
    /// master per ink (`art-1-black.png`, `art-2-fluorescent-pink.png`, ...)
    /// plus the overprint preview (`art-preview.png`), each carrying the
    /// reproduction recipe. `screen` transforms the separation before writing
    /// (pass `{ $0.halftoned(pitch: 8) }` or `{ $0.dithered() }` for 1-bit
    /// masters); `drawsRegistrationMarks` adds the white margin band with corner
    /// targets and the layer label, identical on every file.
    ///
    /// ```swift
    /// OllinApp.exportSeparations(sketch, to: "poster.png") { $0.dithered() }
    /// ```
    ///
    /// From the command line: `--export-separations poster.png` (see
    /// `handleCommandLine`).
    @MainActor
    public static func exportSeparations(_ sketch: Sketch, to path: String,
                                         inks: [Ink]? = nil, paper: Color = .white,
                                         frame: Int = 0, fps: Double = 60,
                                         drawsRegistrationMarks: Bool = true,
                                         quality: RenderQuality = .detail,
                                         screen: (PrintSeparation) -> PrintSeparation = { $0 }) {
        guard let inkSet = inks ?? sketch.printInks, !inkSet.isEmpty else {
            FileHandle.standardError.write(Data("""
                --export-separations splits a sketch into per-ink printing masters.
                Declare the inks in the sketch:
                    override var printInks: [Ink]? { [.fluorescentPink, .blue, .yellow] }
                or name them on the command line:
                    --export-separations out.png --inks "fluorescent pink, blue, yellow"

                """.utf8))
            return
        }
        print("Ollin: rendering separations into \(inkSet.count) inks (\(inkSet.map(\.name).joined(separator: ", ")))")
        guard let cgImage = image(of: sketch, frame: frame, fps: fps, quality: quality) else {
            fatalError("Ollin: failed to render the frame for separation (no Metal device?)")
        }
        let separation = screen(Image(cgImage: cgImage).separated(into: inkSet, paper: paper))
        guard !separation.layers.isEmpty else {
            fatalError("Ollin: the separation produced no layers")
        }

        var metadata = ExportMetadata.capture(from: sketch, frame: frame, fps: fps)
        metadata.inks = inkSet.map(\.name)
        let recipe = metadata.recipe

        let stem = (path as NSString).deletingPathExtension
        let band = drawsRegistrationMarks ? max(24, min(separation.width, separation.height) / 24) : 0

        for (index, layer) in separation.layers.enumerated() {
            let label = "\(index + 1)/\(separation.layers.count)  \(layer.ink.name)  " +
                        "\(Int((layer.averageInk * 100).rounded()))% ink"
            guard let sheet = separationSheet(layer.master.cgImage, band: band, label: label),
                  writePNG(sheet, to: layerPath(stem: stem, index: index, ink: layer.ink),
                           recipe: recipe) else {
                fatalError("Ollin: failed to write \(layerPath(stem: stem, index: index, ink: layer.ink))")
            }
            print("  \(label) → \(layerPath(stem: stem, index: index, ink: layer.ink))")
        }

        let previewLabel = "overprint preview  \(separation.layers.count) inks"
        guard let sheet = separationSheet(separation.preview().cgImage, band: band,
                                          label: previewLabel),
              writePNG(sheet, to: "\(stem)-preview.png", recipe: recipe) else {
            fatalError("Ollin: failed to write \(stem)-preview.png")
        }
        print("Ollin: exported \(separation.layers.count) masters + preview → \(stem)-*.png " +
              "(\(separation.width)×\(separation.height)" +
              (band > 0 ? " + \(band)px marks band)" : ")"))
    }

    /// The file a layer's master is written to: the base path with the layer
    /// number and the ink's name slugged in (`art-2-fluorescent-pink.png`).
    static func layerPath(stem: String, index: Int, ink: Ink) -> String {
        let slug = ink.name.lowercased()
            .map { $0.isLetter || $0.isNumber ? String($0) : "-" }
            .joined()
        return "\(stem)-\(index + 1)-\(slug).png"
    }

    /// Compose one print file: the image centered on a white sheet with a
    /// `band`-pixel margin, registration targets in the four corners, and the
    /// layer label along the bottom, all in full black so every drum prints
    /// its own marks in its own ink. `band: 0` writes the bare image.
    static func separationSheet(_ image: CGImage, band: Int, label: String) -> CGImage? {
        guard band > 0 else { return image }
        let width = image.width + band * 2
        let height = image.height + band * 2
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(data: nil, width: width, height: height,
                                      bitsPerComponent: 8, bytesPerRow: 0, space: space,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
            return nil
        }
        context.setFillColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        // The master's bytes are ink fractions; place it 1:1 with no
        // resampling so they arrive at the press untouched.
        context.interpolationQuality = .none
        context.draw(image, in: CGRect(x: band, y: band,
                                       width: image.width, height: image.height))

        let black = CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 1)
        context.setStrokeColor(black)
        context.setLineWidth(max(1, Double(band) / 16))
        let radius = Double(band) * 0.28
        let arm = radius * 1.6
        for cx in [Double(band) / 2, Double(width) - Double(band) / 2] {
            for cy in [Double(band) / 2, Double(height) - Double(band) / 2] {
                context.strokeEllipse(in: CGRect(x: cx - radius, y: cy - radius,
                                                 width: radius * 2, height: radius * 2))
                context.move(to: CGPoint(x: cx - arm, y: cy))
                context.addLine(to: CGPoint(x: cx + arm, y: cy))
                context.move(to: CGPoint(x: cx, y: cy - arm))
                context.addLine(to: CGPoint(x: cx, y: cy + arm))
                context.strokePath()
            }
        }

        let fontSize = Double(band) * 0.42
        let font = CTFontCreateWithName("Menlo-Regular" as CFString, fontSize, nil)
        let attributes = [kCTFontAttributeName: font,
                          kCTForegroundColorAttributeName: black] as CFDictionary
        if let attributed = CFAttributedStringCreate(nil, label as CFString, attributes) {
            let line = CTLineCreateWithAttributedString(attributed)
            context.textMatrix = .identity
            context.textPosition = CGPoint(x: Double(band) * 2,
                                           y: (Double(band) - fontSize * 0.72) / 2)
            CTLineDraw(line, context)
        }
        return context.makeImage()
    }
}
