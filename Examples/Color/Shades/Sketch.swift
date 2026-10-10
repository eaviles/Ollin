import Ollin
import OllinSamplePhotos

/// A photograph mapped onto a palette the way a pixel artist builds one: a few
/// ramps of shades, each turning warmer toward its light and cooler toward its
/// shadow, and every cell of the picture snapped to the swatch it looks most
/// like.
///
/// The four bases are the colors the picture is mostly made of
/// (`extractPalette(from:)`), and `Palette.shades(of:count:hueDrift:)` grows a
/// ramp from each. A cell's average color goes to `palette.nearestIndex(to:)`,
/// measured in OKLab, or in CIEDE2000 with the parameter on. The bars under
/// the picture are two lightness histograms: the photograph's in gray, the
/// mapped picture's in color, with the photograph's 2% and 98% percentiles
/// marked, the working black and white a levels adjustment would start from.
///
/// Turn `Hue drift` to zero and the ramps go flat: the same lightness steps,
/// one hue each, and the picture loses the warm light and cool shade the drift
/// gives it.
@main
final class Shades: Sketch {
    @Param("Hue drift", 0...0.25) var hueDrift = 1.0 / 12
    @Param("Shades per ramp", 3...8) var perRamp = 5
    @Param("Measure in CIEDE2000") var measuresCIEDE2000 = false

    private let columns = 72
    private var rows = 48
    private var photograph = Image(width: 1, height: 1)
    private var bases: [Color] = []
    private var cells: [Color] = []
    private var photoHistogram: Histogram?

    // The mapped picture, kept until a parameter changes.
    private var mappedKey: [Double] = []
    private var palette = Palette([])
    private var mapped: [Int] = []
    private var mappedHistogram: Histogram?

    override func setup() {
        noStroke()
        photograph = SamplePhoto.textiles.load()
        rows = Int((Double(columns) * Double(photograph.height) / Double(photograph.width)).rounded())
        bases = Array(extractPalette(from: photograph, count: 4, seed: 3))
        photoHistogram = photograph.histogram(of: .lightness, bins: 96)

        // One average per cell, read once: the picture never changes.
        let cellWidth = Double(photograph.width) / Double(columns)
        let cellHeight = Double(photograph.height) / Double(rows)
        cells = (0 ..< rows).flatMap { row in
            (0 ..< columns).map { column in
                photograph.averageColor(in: Rectangle(x: Double(column) * cellWidth,
                                                      y: Double(row) * cellHeight,
                                                      width: cellWidth, height: cellHeight))
            }
        }
    }

    override func draw() {
        background(Color(hex: 0x111317))
        remapIfNeeded()

        // The mapped picture, then the ramps and the histograms under it, the
        // whole block centered on the canvas.
        let swatch = 34.0
        let panelHeight = Double(bases.count) * (swatch + 4) - 4
        let aspect = Double(rows) / Double(columns)
        let pictureWidth = min(width - 180, (height - 180 - 40 - panelHeight) / aspect)
        let pictureHeight = pictureWidth * aspect
        let top = (height - pictureHeight - 40 - panelHeight) / 2
        let frame = Rectangle(x: (width - pictureWidth) / 2, y: top,
                              width: pictureWidth, height: pictureHeight)
        let panel = Rectangle(x: frame.x, y: frame.y + frame.height + 40,
                              width: frame.width, height: panelHeight)
        let cell = frame.width / Double(columns)
        for row in 0 ..< rows {
            for column in 0 ..< columns {
                fill(palette[mapped[row * columns + column]])
                drawRect(frame.x + Double(column) * cell, frame.y + Double(row) * cell, cell + 0.5, cell + 0.5)
            }
        }

        // The ramps, one row each, darkest on the left.
        for r in 0 ..< bases.count {
            for i in 0 ..< perRamp {
                fill(palette[r * perRamp + i])
                drawRect(panel.x + Double(i) * (swatch + 4), panel.y + Double(r) * (swatch + 4),
                         swatch, swatch)
            }
        }

        // The two lightness histograms, and the photograph's working ends.
        let chartLeft = panel.x + Double(perRamp) * (swatch + 4) + 40
        let chart = Rectangle(x: chartLeft, y: panel.y,
                              width: panel.x + panel.width - chartLeft, height: panelHeight)
        if let photoHistogram, let mappedHistogram {
            drawBars(photoHistogram, in: chart, color: Color(white: 0.42))
            drawBars(mappedHistogram, in: chart, color: Color(hex: 0xF2B880).withAlpha(0.85))
            stroke(Color(white: 0.85))
            strokeWeight(1.5)
            for fraction in [0.02, 0.98] {
                let x = chart.x + chart.width * photoHistogram.percentile(fraction)
                drawLine(x, chart.y - 6, x, chart.y + chart.height)
            }
            noStroke()
        }

        drawCaption(measuresCIEDE2000 ? "snapped to the nearest shade, CIEDE2000"
                                      : "snapped to the nearest shade, OKLab")
    }

    private func remapIfNeeded() {
        let key = [hueDrift, Double(perRamp), measuresCIEDE2000 ? 1 : 0]
        guard key != mappedKey else { return }
        mappedKey = key
        palette = Palette(bases.flatMap { Palette.shades(of: $0, count: perRamp, hueDrift: hueDrift).colors })
        let measure: ColorDistance = measuresCIEDE2000 ? .ciede2000 : .oklab
        mapped = cells.map { palette.nearestIndex(to: $0, measure: measure) ?? 0 }

        // The mapped picture as an image of its own, one pixel a cell, so its
        // histogram counts the same cells the photograph's averages came from.
        let picture = Image(width: columns, height: rows)
        for (i, entry) in mapped.enumerated() { picture[i % columns, i / columns] = palette[entry] }
        mappedHistogram = picture.histogram(of: .lightness, bins: 96)
    }

    private func drawBars(_ histogram: Histogram, in box: Rectangle, color: Color) {
        guard let tallest = histogram.counts.max(), tallest > 0 else { return }
        fill(color)
        let bar = box.width / Double(histogram.counts.count)
        for (i, count) in histogram.counts.enumerated() where count > 0 {
            let h = box.height * Double(count) / Double(tallest)
            drawRect(box.x + Double(i) * bar, box.y + box.height - h, bar * 0.8, h)
        }
    }
}
