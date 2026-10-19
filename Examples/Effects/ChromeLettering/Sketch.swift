import Ollin

/// Airbrushed lettering chrome, the logo convention: a sky above a horizon, a
/// floor below it, a dark core band at the join with a razor break and a bright
/// wire beside it. `.chrome` paints it over whatever silhouette a layer holds,
/// so the word is drawn white into a layer and the filter does the rest, the
/// horizon's bend drifting along with `phase`. Three palettes are three pairs
/// of ramps (`sky` and `floor`), with the core and the wire picked to match.
@main
final class ChromeLettering: Sketch {
    enum Palette: String, CaseIterable, ParamOption { case classic, gold, night }

    @Param("Palette", icon: "paintpalette") var palette = Palette.classic
    @Param("Horizon", 0.2 ... 0.8, icon: "rectangle.split.1x2") var horizon = 0.52
    @Param("Warp", 0 ... 40, icon: "water.waves") var warp = 16.0
    @Param("Waves", 0.5 ... 4, icon: "waveform.path") var waves = 1.5
    @Param("Drift", 0 ... 2, icon: "wind") var drift = 1.0

    override func draw() {
        background(Color(hex: 0x111318))

        // Each word gets a layer just its own height, so the sky ramp runs from
        // the top of the letters to the horizon and the floor ramp from the
        // horizon to their bottom: the whole look lands inside the word.
        textFont(.systemBold)
        textSize(100)
        let size = 100 * width * 0.9 / max(textWidth("CHROME"), 1)
        let wordBand = size * 0.8
        let word = makeRenderTarget(width: Int(width), height: Int(wordBand))
        withTarget(word) {
            noStroke()
            fill(.white)
            textFont(.systemBold)
            textAlign(.center, .middle)
            textSize(size)
            drawText("CHROME", width / 2, wordBand / 2)
        }
        let subSize = width * 0.085
        let subBand = subSize * 1.3
        let sub = makeRenderTarget(width: Int(width), height: Int(subBand))
        withTarget(sub) {
            noStroke()
            fill(.white)
            textFont(.systemBold)
            textAlign(.center, .middle)
            textSize(subSize)
            drawText("lettering", width / 2, subBand / 2)
        }

        let look: Filter
        switch palette {
        case .classic:
            look = .chrome(horizon: horizon, warp: warp, waves: waves, phase: time * drift)
        case .gold:
            look = .chrome(horizon: horizon, warp: warp, waves: waves,
                           sky: Ramp([Color(hex: 0x3B1D00), Color(hex: 0xC98A1E), Color(hex: 0xFFF2B0)]),
                           floor: Ramp([Color(hex: 0x5A2E00), Color(hex: 0xE2A232), Color(hex: 0xFFE89A)]),
                           core: Color(hex: 0x2A1400), wire: Color(hex: 0xFFF8DC), phase: time * drift)
        case .night:
            look = .chrome(horizon: horizon, warp: warp, waves: waves,
                           sky: Ramp([Color(hex: 0x05060F), Color(hex: 0x3A2B8C), Color(hex: 0xD9C8FF)]),
                           floor: Ramp([Color(hex: 0x1B0A2E), Color(hex: 0xB02A7A), Color(hex: 0xFFC2E0)]),
                           core: Color(hex: 0x0A0410), wire: .white, phase: time * drift)
        }
        let top = (height - wordBand - subBand - height * 0.05) / 2
        drawImage(word.filtered(look).image, 0, top)
        drawImage(sub.filtered(look).image, 0, top + wordBand + height * 0.05)
    }
}
