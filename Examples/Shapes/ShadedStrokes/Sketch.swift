import Ollin

/// A stroke drawn in a material: graphite catching on the paper's tooth,
/// charcoal and pastel at coarser grains, a stick of three colors, a brush
/// streaking two pigments, a brush running dry, wet paint dragging the colors
/// under it, and oil lit by its own ridges. One picker across the eight media,
/// each set with `strokeMedium(_:)` beside `stroke` and `strokeWeight`.
///
/// A hand that is not there writes three marks across the sheet. In the dry
/// media it presses hard at the start of each and lifts toward the end, so the
/// line breaks into specks as the press lightens rather than fading. The middle
/// mark crosses three painted swatches, which the wet media drag along behind
/// them.
///
/// Drag to draw your own marks in the chosen medium. On a Force Touch trackpad
/// a lighter press thins the pigment; elsewhere a hurried stroke does. `c`
/// clears what you drew.
@main
final class ShadedStrokes: Sketch {
    enum Medium: String, CaseIterable, ParamOption {
        case pencil, charcoal, pastel, multicolor, bristles, dryBrush, wet, oil

        /// The media made of dry pigment on the paper's tooth.
        var isDry: Bool { self == .pencil || self == .charcoal || self == .pastel || self == .multicolor }
    }

    @Param(icon: "paintbrush.pointed") var medium = Medium.pencil
    @Param("Weight", 6 ... 90, icon: "lineweight") var weight = 46.0

    override var loopDuration: Double? { 10 }

    /// The mark under the pointer, and the marks already drawn with the medium
    /// each was drawn in, so changing the picker restyles only what comes next.
    var mark = StrokeMark()
    var drawn: [(mark: StrokeMark, medium: Medium)] = []

    let paper = Color(red: 0.96, green: 0.94, blue: 0.9)
    let swatches = [Color(red: 0.2, green: 0.36, blue: 0.62),
                    Color(red: 0.88, green: 0.47, blue: 0.55),
                    Color(red: 0.95, green: 0.74, blue: 0.24)]

    override func draw() {
        background(paper)
        // Three painted swatches across the middle of the sheet.
        noStroke()
        for (i, swatch) in swatches.enumerated() {
            fill(swatch)
            drawRect(150 + Double(i) * 260, 420, 260, 240)
        }

        noFill()
        strokeCap(.round)
        strokeJoin(.round)
        // The three written marks grow over the first two thirds of the loop
        // and hold for the rest.
        let t = loopProgress(over: 10)
        for (i, y) in [250.0, 540, 830].enumerated() {
            let progress = min(max((t - Double(i) * 0.12) / 0.5, 0), 1)
            draw(written(y: y, upTo: progress, lifting: medium.isDry), in: medium)
        }

        for stroke in drawn { draw(stroke.mark, in: stroke.medium) }
        if mouseIsPressed { record(into: &mark) }
        draw(mark, in: medium)

        // The caption in ink, since the sheet is light.
        noStroke()
        fill(Color(white: 0.4))
        textSize(20)
        textAlign(.center, .bottom)
        drawText("\(medium.rawValue)  ·  drag to draw  ·  c clears", width / 2, height - 28)
    }

    override func mousePressed() {
        // Whether the device measures pressure is only known once it has sent
        // some, so the response is chosen per mark.
        let opacity: StrokeResponse = pressureIsAvailable
            ? .pressure(light: 0.12)
            : .speed(reference: 1800, fast: 0.15)
        mark = StrokeMark(StrokeDynamics(opacity: opacity), smoothing: 0.5)
        mark.pressureDeadZone = 0.05
        mark.pressureCurve = 1.4
    }

    override func mouseReleased() {
        if !mark.isEmpty { drawn.append((mark, medium)) }
        mark.clear()
    }

    override func keyPressed() {
        if key == "c" { drawn = []; mark.clear() }
    }

    /// One mark in one medium: its pigment, its weight, and the medium itself.
    func draw(_ mark: StrokeMark, in medium: Medium) {
        guard !mark.isEmpty else { return }
        withState {
            strokeWeight(weight)
            switch medium {
            case .pencil:
                stroke(Color(red: 0.13, green: 0.13, blue: 0.15))
                strokeMedium(.pencil)
            case .charcoal:
                stroke(Color(red: 0.1, green: 0.09, blue: 0.09))
                strokeMedium(.charcoal)
            case .pastel:
                stroke(Color(red: 0.78, green: 0.33, blue: 0.2))
                strokeMedium(.pastel)
            case .multicolor:
                stroke(.white)
                strokeMedium(.pastel(palette: [Color(red: 0.78, green: 0.33, blue: 0.2),
                                               Color(red: 0.95, green: 0.65, blue: 0.07),
                                               Color(red: 0.16, green: 0.2, blue: 0.36)]))
            case .bristles:
                stroke(Color(red: 0.75, green: 0.16, blue: 0.2))
                strokeMedium(.bristles(Color(red: 0.95, green: 0.65, blue: 0.07)))
            case .dryBrush:
                stroke(Color(red: 0.12, green: 0.12, blue: 0.14))
                strokeMedium(.dryBrush)
            case .wet:
                stroke(Color(red: 0.72, green: 0.12, blue: 0.2))
                strokeMedium(.wet)
            case .oil:
                stroke(Color(red: 0.82, green: 0.36, blue: 0.14))
                strokeMedium(.oil)
            }
            drawMark(mark)
        }
    }

    /// The hand's mark along one row, written up to `progress` of its length: a
    /// gentle wave across the sheet, its width easing off a little as it lifts,
    /// and when `lifting`, its pressure (here, its opacity) falling from full to
    /// a seventh.
    func written(y: Double, upTo progress: Double, lifting: Bool) -> StrokeMark {
        let count = 120
        let last = Int(Double(count) * progress)
        guard last >= 1 else { return StrokeMark() }
        return StrokeMark(samples: (0 ... last).map { k in
            let u = Double(k) / Double(count)
            let x = 90 + 900 * u
            let wave = sin(u * .tau * 1.25 + y * 0.01) * 46
            return StrokeMark.Sample(position: Vector2(x, y + wave),
                                     width: 1 - 0.25 * u,
                                     opacity: lifting ? 1 - 0.86 * u : 1)
        })
    }
}
