import Ollin

/// The fluent `Visual` chain surface on one switchable contact sheet: the
/// **sources** (the coordinate gradient, the soft polygon, a flat color, and a
/// drawn layer read back into a chain), the coordinate **warps** (scroll,
/// repeat, scale, pixelate), the **color** adjustments (brightness, invert,
/// posterize, threshold, luma key, hue shift, color cycle, channel), the
/// two-chain **combines** (mix, difference, mask), and the **modulations**,
/// where one chain's color drives another's coordinates per pixel (rotate,
/// scale, pixelate, kaleidoscope).
///
/// Every tile is one chain compiled into a single GPU pass, generated at its
/// cell's own size and labeled with the calls it makes; several families share
/// an oscillator base so what each step changes reads at a glance, and every
/// number can animate (or hang off an `@Param`) without a recompile.
/// `Shaders/VisualSynth` is the performance-shaped sibling: one deep chain
/// rather than a catalog.
@main
final class VisualCatalog_Example: Sketch {

    enum Family: String, CaseIterable, ParamOption {
        case sources, warps, color, combines, modulations
    }

    @Param(style: .segmented, icon: "link") var family = Family.sources

    private let labelFont = OutlineFont.system

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

        let cell: (columns: Int, width: Int, height: Int)
        let chains: [(String, Visual)]
        switch family {
        case .sources:
            cell = sheetCell(for: 4)
            let scene = drawnScene(width: cell.width, height: cell.height)
            chains = [
                (".gradient(speed:)", .gradient(speed: 1)),
                (".shape.tinted", .shape(sides: 5, radius: 0.34, smoothing: 0.02)
                    .tinted(Color(hex: 0xFFB86B))),
                (".solid(color)", .solid(Color(hue: (t * 0.04).truncatingRemainder(dividingBy: 1),
                                               saturation: 0.65, brightness: 0.85))),
                (".layer(scene)", .layer(scene)),
            ]
        case .warps:
            cell = sheetCell(for: 4)
            let bands = Visual.oscillator(frequency: 9, speed: 0.8, colorShift: 0.25)
            chains = [
                (".scrolled(speedX:)", bands.scrolled(speedX: 0.12, speedY: 0.04)),
                (".repeated(offsetY:)", Visual.shape(sides: 3, radius: 0.42, smoothing: 0.03)
                    .tinted(Color(hex: 0x55D6BE))
                    .repeated(x: 4, y: 4, offsetY: 0.5)),
                (".scaled(amount)", bands.scaled(1 + 0.5 * sin(t * 0.7))),
                (".pixelated(x:y:)", Visual.voronoi(scale: 3, speed: 0.4, blending: 0.4)
                    .pixelated(x: 36, y: 12)),
            ]
        case .color:
            cell = sheetCell(for: 8)
            let field = Visual.oscillator(frequency: 6, speed: 0.7, colorShift: 0.35)
            chains = [
                (".brightness", field.brightness(0.35 * sin(t))),
                (".inverted", field.inverted(unipolar(sin(t * 0.8)))),
                (".posterized(levels: 4)", field.posterized(levels: 4, gamma: 0.8)),
                (".thresholded(0.5)", field.thresholded(0.5, softness: 0.05)),
                (".luma over .solid", Visual.solid(Color(hex: 0x7A1F3D))
                    .blended(with: field.luma(threshold: 0.45, softness: 0.1))),
                (".hueShifted", field.hueShifted(t * 0.08)),
                (".colorCycled", field.colorCycled(t * 0.12)),
                (".channel(.luminance)", field.channel(.luminance)),
            ]
        case .combines:
            cell = sheetCell(for: 3)
            let stripes = Visual.oscillator(frequency: 18, speed: 0.5, colorShift: 0.1)
            chains = [
                (".mixed(with:)", Visual.oscillator(frequency: 7, colorShift: 0.3)
                    .mixed(with: .voronoi(scale: 5, speed: 0.4)
                        .tinted(Color(hex: 0x3346FF)),
                           amount: unipolar(sin(t * 0.5)))),
                (".differenced(with:)", stripes.differenced(with: stripes.rotated(t * 0.15))),
                (".masked(by: .shape)", Visual.oscillator(frequency: 5, speed: 0.6, colorShift: 0.4)
                    .masked(by: .shape(sides: 60, radius: 0.26 + 0.06 * sin(t),
                                       smoothing: 0.05))),
            ]
        case .modulations:
            cell = sheetCell(for: 4)
            let web = Visual.oscillator(frequency: 14, speed: 0.6, colorShift: 0.2)
            chains = [
                (".rotated(by: .noise)", web.rotated(by: .noise(scale: 2, speed: 0.3),
                                                     amount: 1.2)),
                (".scaled(by: .oscillator)", web.scaled(by: .oscillator(frequency: 3, speed: 0.4),
                                                        amount: 0.5)),
                (".pixelated(by: .noise)", Visual.voronoi(scale: 4, speed: 0.3, blending: 0.3)
                    .pixelated(by: .noise(scale: 2, speed: 0.3), amount: 18, offset: 24)),
                (".kaleidoscope(by: .noise)", web.kaleidoscope(by: .noise(scale: 2, speed: 0.25),
                                                               segments: 6, amount: 0.15)),
            ]
        }

        let sheet: [(String, RenderTarget)] = chains.map {
            ($0.0, generate($0.1, width: cell.width, height: cell.height))
        }
        textFont(labelFont)
        drawSheet(sheet, columns: cell.columns) { tile, rect in
            drawImage(tile.image, in: rect)
        }
    }

    /// The small drawn scene the `.layer` source reads back into a chain: a
    /// chain samples it wherever its (possibly warped) coordinate lands, so a
    /// drawn layer warps, adjusts, and mixes like any procedural source.
    private func drawnScene(width w: Int, height h: Int) -> RenderTarget {
        let scene = makeRenderTarget(width: w, height: h)
        let cw = Double(w), ch = Double(h)
        withTarget(scene) {
            background(Color(hex: 0x101826))
            noStroke()
            fill(Color(hex: 0xFF5252)); drawCircle(cw * 0.32, ch * 0.38, cw * 0.16)
            fill(Color(hex: 0x40C4FF)); drawRect(cw * 0.5, ch * 0.52, cw * 0.3, ch * 0.24)
            fill(Color(hex: 0xFFD740))
            drawTriangle(cw * 0.3, ch * 0.82, cw * 0.16, ch * 0.6, cw * 0.46, ch * 0.6)
            stroke(Color(white: 1, alpha: 0.8)); strokeWeight(3); noFill()
            drawCircle(cw * 0.5, ch * 0.5, cw * 0.3 + sin(time) * cw * 0.03)
        }
        return scene
    }
}
