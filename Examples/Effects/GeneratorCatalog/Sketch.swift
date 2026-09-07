import Ollin

/// The procedural `Generator` catalog on one switchable contact sheet: the
/// **basic** patterns (checkers, grid lines, bars, noise), the **design** set
/// (nine animated designer sources, each a single `generate` call), the
/// closed-form **fields** (quasicrystal, moire, gyroid slice, phyllotaxis, hex
/// pulses), and the **chains**, where a generated layer flows on into the rest
/// of the effect graph: noise mapped through a colormap, a grid multiplied over
/// that field, and the gyroid blurred and relit as liquid.
///
/// A `Generator` is a source filled from math alone, no input layer;
/// `generate(_:)` hands back a `RenderTarget` you draw, filter, blend, or feed
/// into a combine like any other layer. Every animated source takes a `phase`
/// you feed `time`. Each tile is generated at its cell's own size, so nothing
/// stretches. (The mesh gradient has its own example, `Effects/MeshGradient`.)
@main
final class GeneratorCatalog_Example: Sketch {

    enum Family: String, CaseIterable, ParamOption { case basic, design, fields, chains }

    @Param(style: .segmented, icon: "circle.grid.3x3") var family = Family.basic

    private let labelFont = OutlineFont.system

    /// A tile is a layer, plus an optional second layer multiplied over it in
    /// place (a filtered layer resolves on the canvas, so the multiply happens
    /// there rather than inside another target).
    private typealias Tile = (layer: RenderTarget, multiplied: RenderTarget?)

    /// The near-square layout `drawSheet` picks for `count` items, so each tile
    /// can be generated at its cell's own size.
    private func sheetCell(for count: Int) -> (columns: Int, width: Int, height: Int) {
        let cols = Int(Double(count).squareRoot().rounded(.up))
        let rows = (count + cols - 1) / cols
        let space = width * 0.01
        return (cols, Int((width - space * Double(cols + 1)) / Double(cols)),
                Int((height - space * Double(rows + 1)) / Double(rows)))
    }

    override func draw() {
        background(Color(white: 0.06))
        let t = time
        let s = 4 + sin(t * 0.4) * 2          // the basics breathe their feature scale

        let items: [(String, Tile)]
        let columns: Int
        switch family {
        case .basic:
            let (cols, w, h) = sheetCell(for: 5)
            columns = cols
            items = [
                ("checkers", (generate(.checkers(scale: s * 2, foreground: Color(hex: 0xF2C14E),
                                                 background: Color(hex: 0x222B3A)),
                                       width: w, height: h), nil)),
                ("gridLines", (generate(.gridLines(scale: s * 3, weight: 0.12,
                                                   foreground: Color(hex: 0x55D6BE),
                                                   background: Color(hex: 0x12161F)),
                                        width: w, height: h), nil)),
                ("bars", (generate(.bars(scale: s * 3, foreground: Color(hex: 0xE85D75),
                                         background: Color(hex: 0x1B1F2A)),
                                   width: w, height: h), nil)),
                ("noise", (generate(.noise(scale: s, sharpness: 0), width: w, height: h), nil)),
                ("gaborNoise", (generate(.gaborNoise(wavelength: 120 / s, bandwidth: 0.3,
                                                     angle: t * 0.2, spread: 0.2,
                                                     phase: t * 2, seed: 3,
                                                     foreground: Color(hex: 0xF2E8DC),
                                                     background: Color(hex: 0x1B1F2A)),
                                         width: w, height: h), nil)),
            ]
        case .design:
            let (cols, w, h) = sheetCell(for: 9)
            columns = cols
            items = [
                ("filaments", (generate(.filaments(phase: t), width: w, height: h), nil)),
                ("smokeRing", (generate(.smokeRing(colors: [.white, Color(hex: 0x6FD9FF)],
                                                   phase: t), width: w, height: h), nil)),
                ("colorPanels", (generate(.colorPanels(phase: t * 30), width: w, height: h), nil)),
                ("spiral", (generate(.spiral(phase: t * 0.4), width: w, height: h), nil)),
                ("waves", (generate(.waves(shape: 1.2, phase: t * 0.5), width: w, height: h), nil)),
                ("dotOrbit", (generate(.dotOrbit(phase: t), width: w, height: h), nil)),
                ("grainGradient", (generate(.grainGradient(shape: .blob, phase: t),
                                            width: w, height: h), nil)),
                ("pulsingBorder", (generate(.pulsingBorder(phase: t), width: w, height: h), nil)),
                ("godRays", (generate(.godRays(phase: t), width: w, height: h), nil)),
            ]
        case .fields:
            let (cols, w, h) = sheetCell(for: 5)
            columns = cols
            items = [
                ("quasicrystal", (generate(.quasicrystal(phase: t * 0.6), width: w, height: h), nil)),
                ("moire", (generate(.moire(phase: t), width: w, height: h), nil)),
                ("gyroid", (generate(.gyroid(phase: t * 0.5), width: w, height: h), nil)),
                ("phyllotaxis", (generate(.phyllotaxis(phase: t * 0.05), width: w, height: h), nil)),
                ("hexPulse", (generate(.hexPulse(phase: t * 2), width: w, height: h), nil)),
            ]
        case .chains:
            let (cols, w, h) = sheetCell(for: 3)
            columns = cols
            let mapped = generate(.noise(scale: s), width: w, height: h)
                .filtered(.gradientMap(.turbo))
            let grid = generate(.gridLines(scale: s * 4, weight: 0.08,
                                           foreground: Color(white: 0.1), background: .white),
                                width: w, height: h)
            let relit = generate(.gyroid(foreground: .white, background: .black,
                                         thickness: 0.5, phase: t * 0.5),
                                 width: w, height: h)
                .filtered(.gaussianBlur(radius: 6))
                .filtered(.relight(.liquid, height: 3, color: Color(hex: 0x2B6C8C)))
            items = [
                ("noise → turbo", (mapped, nil)),
                ("noise × grid", (mapped, grid)),
                ("gyroid + relight", (relit, nil)),
            ]
        }

        textFont(labelFont)
        drawSheet(items, columns: columns) { tile, cell in
            drawImage(tile.layer.image, in: cell)
            if let over = tile.multiplied {
                withState { blendMode(.multiply); drawImage(over.image, in: cell) }
            }
        }
    }
}
