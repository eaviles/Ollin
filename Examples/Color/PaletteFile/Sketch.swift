import Ollin

/// Reading palettes off disk. `loadPalettes` returns every palette in a file;
/// `loadPalette` returns the first one.
///
/// Two files, two layouts, one call each. `palettes.csv` puts a palette on
/// every line, so it loads as six of them. `sunset.hex` puts one color per
/// line, so the whole file is a single palette. Nothing declared the format:
/// the loader reads the bytes and works it out, and the same call reads a JSON
/// array of palettes or an Adobe `.ase` swatch file too.
///
/// The bar along the bottom is the single palette from the `.hex` file, and
/// each row above it is one line of the CSV.
@main
final class PaletteFile: Sketch {
    var rows: [Palette] = []
    var accent = Palette([])

    override func setup() {
        noStroke()

        // `in:` never defaults to a bundle: a default would find Ollin's, not
        // this sketch's. `.module` is the sketch's own.
        rows = loadPalettes(resource: "palettes", withExtension: "csv", in: .module)
        accent = loadPalette(resource: "sunset", withExtension: "hex", in: .module) ?? Palette(.white)
    }

    override func draw() {
        background(Color(hex: 0x14161A))
        guard !rows.isEmpty else {
            drawStatus("No palettes loaded", style: .warning)
            return
        }

        // One row per palette, one cell per color. `Grid` carries the indices,
        // so the whole layout is a single loop.
        let g = grid(columns: rows[0].count, rows: rows.count,
                     padding: Insets(top: 90, right: 90, bottom: 220, left: 90), gutter: 10)
        for cell in g.cells {
            let palette = rows[cell.row]
            // A slow shimmer: each swatch lifts as the wave passes through it.
            let phase = time * 0.6 - Double(cell.column) * 0.35 - Double(cell.row) * 0.2
            let lift = unipolar(sin(phase)) * 10

            fill(palette[cell.column])
            drawRect(center: cell.center, width: cell.frame.width,
                     height: cell.frame.height - lift, cornerRadius: 6)
        }

        // The `.hex` file as one continuous bar.
        let bar = Rectangle(x: 90, y: height - 170, width: width - 180, height: 80)
        let step = bar.width / Double(accent.count)
        for i in 0..<accent.count {
            fill(accent[i])
            drawRect(bar.x + Double(i) * step, bar.y, step, bar.height)
        }

        drawCaption("\(rows.count) palettes from palettes.csv, one from sunset.hex")
    }
}
