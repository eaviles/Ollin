import Ollin

/// Color output: how much of the frame survives the trip to the screen.
///
/// The canvas has always composited in linear floating-point, so it holds
/// colors an ordinary 8-bit sRGB screen cannot show: saturations outside sRGB,
/// and light piled up past full brightness. `colorOutput` decides how much of
/// that reaches the display instead of being flattened at the last step.
///
/// This sketch declares `.extended`, the deepest setting, and shows both halves
/// of what that buys:
///
///   • Top row, the gamut. Each swatch is a color named in Display P3 beside
///     the nearest thing sRGB can hold. On a `.standard` sketch the two are
///     identical, because the P3 one is clipped on the way out. Here they are
///     not: the left of each pair is a red, green, and blue no sRGB screen can
///     make.
///   • Bottom, the range. A lamp whose core runs to `3.0`, well past white.
///     On a display with headroom the core is genuinely brighter than the white
///     caption text; without headroom it clips to the same white, which is what
///     every sketch did before.
///
/// The heading reports what this display is actually granting: `1.0x` means the
/// screen (or the window) has no headroom right now and only the gamut half is
/// visible. Turn the display brightness down and watch the number climb, since
/// the system grants headroom relative to how bright white already is.
///
/// Export it and both halves survive, as long as the format can hold them.
/// `--export-video` writes HDR10. `--export lamp.heic` writes a still whose
/// bright core rides along in a gain map, and reports how far above white it
/// went. `--export lamp.png` keeps the wide gamut but clips the core, because
/// PNG has nowhere to put brightness above white.
@main
final class ColorOutput_Example: Sketch {

    override var colorOutput: ColorOutput { .extended }

    // Left of each pair is named in Display P3, right is the sRGB neighbour.
    private let pairs: [(name: String, wide: Color, plain: Color)] = [
        ("red",   Color(displayP3: 1, green: 0, blue: 0),   Color(red: 1, green: 0, blue: 0)),
        ("green", Color(displayP3: 0, green: 1, blue: 0),   Color(red: 0, green: 1, blue: 0)),
        ("blue",  Color(displayP3: 0, green: 0, blue: 1),   Color(red: 0, green: 0, blue: 1)),
        ("cyan",  Color(displayP3: 0, green: 1, blue: 1),   Color(red: 0, green: 1, blue: 1)),
    ]

    override func draw() {
        background(Color(hex: 0x08090C))
        noStroke()

        // The gamut half: each pair butted together, so the seam between them is
        // the whole demonstration.
        let margin = width * 0.08
        let slot = (width - margin * 2) / Double(pairs.count)
        let top = height * 0.16, swatch = height * 0.22
        for (i, pair) in pairs.enumerated() {
            let x = margin + Double(i) * slot
            fill(pair.wide)
            drawRect(x, top, slot * 0.46, swatch)
            fill(pair.plain)
            drawRect(x + slot * 0.46, top, slot * 0.46, swatch)

            fill(Color(white: 0.65))
            textAlign(.center)
            drawText(pair.name, x + slot * 0.46, top + swatch + height * 0.045)
        }

        // The range half: a lamp summed additively so its core lands near 3.0,
        // three times as bright as white. `.clamp` is deliberate. A tone-map
        // curve would squeeze exactly this back under 1.0.
        let cx = width / 2, cy = height * 0.68
        let r = min(width, height) * 0.20
        let breathe = 1 + sin(time * 0.6) * 0.35
        blendMode(.add)
        for ring in 0 ..< 3 {
            let t = Double(ring) / 3
            fill(.radial(center: Vector2(cx, cy), radius: r * (1 - t * 0.55),
                         Ramp(stops: [(0.0, Color(white: breathe, alpha: 0.9)),
                                      (1.0, Color(white: breathe, alpha: 0))])))
            drawCircle(cx, cy, r * (1 - t * 0.55))
        }
        blendMode(.normal)

        // A white reference bar right beside the core: on an extended display
        // the lamp reads brighter than this, which is the point.
        fill(.white)
        drawRect(cx + r * 1.1, cy - height * 0.03, width * 0.10, height * 0.06)
        fill(Color(white: 0.65))
        textAlign(.left)
        drawText("white", cx + r * 1.1, cy + height * 0.075)

        textAlign(.center)
        fill(.white)
        let granted = String(format: "%.2fx", displayHeadroom)
        drawText("colorOutput .extended  ·  display headroom \(granted)", width / 2, height * 0.085)
        drawCaption(displayHeadroom > 1.05
                    ? "the lamp's core is brighter than white; each left swatch is outside sRGB"
                    : "no headroom right now: the gamut half still shows, the bright core clips")
    }
}
