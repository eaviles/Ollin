import Ollin

/// `Combine.paintMix` beside `Combine.mix`: the same yellow wash laid over the
/// same blue field, combined both ways at once. On the left the two layers
/// cross-dissolve as light (`.mix`, a per-pixel lerp), and where yellow crosses
/// blue the lerp lands in gray. On the right each pixel's two colors become
/// reflectance spectra and blend through the Kubelka-Munk model (`.paintMix`),
/// the way scattering pigments blend, so the same overlap meets in green. The
/// wash's coverage gates the paint mix: where the yellow layer is empty the
/// ground passes through untouched, so the wash reads as paint laid on the
/// field, while the linear dissolve fades everything toward the wash layer,
/// its empty regions included (watch the left half's paper dim).
///
/// Both spellings of a two-input combine have a call site here: the right half
/// and the chip row go through `combined(with:_:)` on a pair of render targets,
/// and the left half is the `compose { }` sugar, `.mixed(with: aside { })`.
/// The chips run the same two combines over flat swatches of the two inks, so
/// the mixture colors read on their own.
///
/// Try it: slide `amount` from 0 (all base) to 1 (the wash wins where it
/// covers), or switch `quality`, the wavelength-tap tier of the paint model.
@main
final class PigmentMix_Example: Sketch {

    @Param("Amount", 0 ... 1, icon: "slider.horizontal.3") var amount = 0.5
    @Param(style: .segmented, icon: "dial.medium") var quality = RenderQuality.default

    private let paper = Color(hex: 0xF1EAD9)
    private let blueInk = Color(hex: 0x2B55C4)
    private let yellowInk = Color(hex: 0xF0C419)

    override func draw() {
        background(Color(hex: 0x14161C))

        let leftField = Rectangle(x: 26, y: 150,
                                  width: width / 2 - 39, height: height - 280)
        let rightField = Rectangle(x: width / 2 + 13, y: 150,
                                   width: width / 2 - 39, height: height - 280)
        let sway = Vector2(cos(time * 0.31), sin(time * 0.23)) * 34

        // The left half through the compose sugar: the blue field is the layer,
        // the yellow wash an aside drawn only to feed the linear dissolve.
        compose {
            layer { fieldScene(in: leftField, sway: sway) }
                .mixed(with: aside { washScene(in: leftField, sway: sway) },
                       amount: amount)
        }

        // The right half by hand: two targets combined through the paint model.
        let base = makeRenderTarget()
        withTarget(base) { fieldScene(in: rightField, sway: sway) }
        let overlay = makeRenderTarget()
        withTarget(overlay) { washScene(in: rightField, sway: sway) }
        drawImage(base.combined(with: overlay,
                                .paintMix(amount: amount, quality: quality)).image, 0, 0)

        drawChips()
        drawLabels(left: leftField, right: rightField)
        drawCaption("Yellow over blue, combined twice: light meets in gray, pigment in green.")
    }

    /// One half's base: the paper ground and the blue field, clipped to it.
    private func fieldScene(in field: Rectangle, sway: Vector2) {
        withClip(field) {
            noStroke()
            fill(paper)
            drawRect(field.x, field.y, field.width, field.height)
            wash(blueInk, at: field.center + Vector2(-80, -70) + sway)
        }
    }

    /// One half's overlay: the yellow wash alone, transparent everywhere else,
    /// so its coverage is exactly where the paint lies.
    private func washScene(in field: Rectangle, sway: Vector2) {
        withClip(field) {
            wash(yellowInk, at: field.center + Vector2(80, 75) - sway)
        }
    }

    /// One broad soft wash: a radial fade from full ink out to clear.
    private func wash(_ ink: Color, at center: Vector2, radius: Double = 290) {
        noStroke()
        fill(.radial(center: center, radius: radius,
                     Ramp(stops: [(0.0, ink), (0.5, ink), (1.0, ink.withAlpha(0))])))
        drawCircle(center.x, center.y, radius)
    }

    /// Flat swatches of the two inks and their two mixtures: the same combines
    /// the halves run, over solid chips, so the colors read on their own.
    private func drawChips() {
        let blueChip = makeRenderTarget(width: 96, height: 96)
        withTarget(blueChip) { background(blueInk) }
        let yellowChip = makeRenderTarget(width: 96, height: 96)
        withTarget(yellowChip) { background(yellowInk) }
        let asLight = blueChip.combined(with: yellowChip, .mix(amount: amount))
        let asPaint = blueChip.combined(with: yellowChip,
                                        .paintMix(amount: amount, quality: quality))

        let side = 84.0, gap = 14.0
        let x0 = (width - side * 4 - gap * 3) / 2
        withState {
            noStroke()
            fill(Color(white: 1, alpha: 0.85))
            textSize(15)
            textAlign(.center)
            for (i, chip) in [("blue", blueChip), (".mix", asLight),
                              (".paintMix", asPaint), ("yellow", yellowChip)].enumerated() {
                let x = x0 + Double(i) * (side + gap)
                drawImage(chip.1.image, in: Rectangle(x: x, y: 26, width: side, height: side))
                drawText(chip.0, x + side / 2, 134)
            }
        }
    }

    private func drawLabels(left: Rectangle, right: Rectangle) {
        withState {
            noStroke()
            fill(.white)
            textSize(30)
            textAlign(.center)
            drawText("mixed as light (.mix)", left.center.x, height - 92)
            drawText("mixed as paint (.paintMix)", right.center.x, height - 92)
        }
    }
}
