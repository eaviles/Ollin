// figure: frame=0 themed
//
// Guide figure (Chapter 16): what a HEIC still keeps that this page cannot
// show. One probe, a lamp summed past white on an `.extended` sketch, is
// rendered once through OllinApp.image(of:), the float frame `--export
// lamp.heic` is written from, and its pixels are read back twice: clamped at
// white, which is the picture inside the file and what an SDR page shows, and
// as the gain map, the record of how far above white each pixel went. Both
// panels are those real pixels, and the peak is measured from them.
//
// WhatTheStillKeeps is declared first on purpose: the loader compiles the
// first `class …: Sketch` it finds, so the probe comes after it.
import CoreGraphics
import Ollin
import OllinDiagram

final class WhatTheStillKeeps: Sketch {
    override var canvasSize: CanvasSize { .size(880, 420) }

    @Param var darkTheme = false
    var theme: DiagramTheme { DiagramTheme(dark: darkTheme) }

    /// The one render, read back once and kept for the themed second pass.
    private var base: Image?
    private var map: Image?
    private var peak = 1.0

    override func setup() { noLoop() }

    override func draw() {
        background(theme.paper)
        textFont(.system)
        if base == nil { readBack() }

        let side = 280.0, gap = 80.0, top = 62.0
        let left = (width - side * 2 - gap) / 2
        let panels = [Rectangle(x: left, y: top, width: side, height: side),
                      Rectangle(x: left + side + gap, y: top, width: side, height: side)]
        if let base { drawImage(base, in: panels[0]) }
        if let map { drawImage(map, in: panels[1]) }

        let titles = ["the picture inside the file", "the gain map beside it"]
        let notes = ["the frame clamped at white: what this page shows",
                     String(format: "how far above white each pixel went: up to %.1f×", peak)]
        for (i, panel) in panels.enumerated() {
            noFill()
            stroke(theme.border)
            strokeWeight(1.5)
            drawRect(panel)
            noStroke()
            drawText(titles[i], panel.center.x, top - 22, size: 16, color: theme.ink, align: .center, .middle)
            drawText(notes[i], panel.center.x, top + side + 12, size: 12, color: theme.muted, align: .center, .top)
        }
        drawText("+", width / 2, top + side / 2, size: 34, color: theme.muted, align: .center, .middle)

        diagramCaption("one HEIC, two pictures: the frame clamped at white, and what was clamped",
                       at: 378, theme: theme)
    }

    /// Render the probe and read its float pixels, linear Display P3 with the
    /// highlights still above 1, the way the still export receives them.
    private func readBack() {
        guard let exported = OllinApp.image(of: LampProbe()),
              let space = CGColorSpace(name: CGColorSpace.extendedLinearDisplayP3) else { return }
        let w = exported.width, h = exported.height
        var floats = [Float](repeating: 0, count: w * h * 4)
        let info = CGBitmapInfo.floatComponents.rawValue
            | CGBitmapInfo.byteOrder32Little.rawValue
            | CGImageAlphaInfo.premultipliedLast.rawValue
        floats.withUnsafeMutableBytes { raw in
            guard let context = CGContext(data: raw.baseAddress, width: w, height: h,
                                          bitsPerComponent: 32, bytesPerRow: w * 16,
                                          space: space, bitmapInfo: info) else { return }
            context.draw(exported, in: CGRect(x: 0, y: 0, width: w, height: h))
        }

        var top: Float = 1
        for i in stride(from: 0, to: floats.count, by: 4) {
            top = max(top, floats[i], floats[i + 1], floats[i + 2])
        }
        peak = Double(top)

        var baseBytes = [UInt8](repeating: 255, count: w * h * 4)
        var mapBytes = [UInt8](repeating: 255, count: w * h * 4)
        for p in 0 ..< w * h {
            let r = Double(floats[p * 4]), g = Double(floats[p * 4 + 1]), b = Double(floats[p * 4 + 2])
            // The base picture: clamped, then named as the P3 color it is, so
            // the framework's own conversion lands it in sRGB bytes.
            let clamped = Color(displayP3: encoded(min(r, 1)), green: encoded(min(g, 1)), blue: encoded(min(b, 1)))
            baseBytes[p * 4] = byte(clamped.red)
            baseBytes[p * 4 + 1] = byte(clamped.green)
            baseBytes[p * 4 + 2] = byte(clamped.blue)
            // The map: the gain each pixel needs back, on a log scale from
            // none to the frame's peak, which is how the file stores it.
            let gain = max(r, g, b, 1)
            let level = peak > 1 ? log2(gain) / log2(peak) : 0
            let v = byte(level)
            mapBytes[p * 4] = v
            mapBytes[p * 4 + 1] = v
            mapBytes[p * 4 + 2] = v
        }
        base = Image(width: w, height: h, premultipliedRGBA: baseBytes)
        map = Image(width: w, height: h, premultipliedRGBA: mapBytes)
    }

    /// The sRGB transfer curve, which Display P3 shares.
    private func encoded(_ v: Double) -> Double {
        v <= 0.0031308 ? 12.92 * v : 1.055 * pow(v, 1 / 2.4) - 0.055
    }

    private func byte(_ v: Double) -> UInt8 {
        UInt8(max(0, min(255, (v * 255).rounded())))
    }
}

/// A lamp summed additively past white, beside a bar that is exactly white.
final class LampProbe: Sketch {
    override var canvasSize: CanvasSize { .size(280, 280) }
    override var colorOutput: ColorOutput { .extended }

    override func draw() {
        background(Color(hex: 0x08090C))
        noStroke()
        let center = Vector2(width * 0.4, height * 0.5), r = shortSide * 0.3
        blendMode(.add)
        for ring in 0 ..< 3 {
            let t = Double(ring) / 3
            fill(.radial(center: center, radius: r * (1 - t * 0.55),
                         Ramp(stops: [(0.0, Color(white: 1, alpha: 0.9)),
                                      (1.0, Color(white: 1, alpha: 0))])))
            drawCircle(center: center, radius: r * (1 - t * 0.55))
        }
        blendMode(.normal)
        fill(.white)
        drawRect(width * 0.74, height * 0.44, width * 0.17, height * 0.12)
        fill(Color(white: 0.65))
        textAlign(.left)
        textSize(12)
        drawText("white", width * 0.74, height * 0.64)
    }
}
