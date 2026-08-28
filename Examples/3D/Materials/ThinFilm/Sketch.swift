import Ollin

/// Thin-film interference: the color a clear film makes when it lies on a surface.
///
/// Light reflects off the top of the film and off the bottom. The second wave travels
/// a little farther, so the two meet again out of step: some colors add and others
/// cancel. Nothing here is pigment, and that is why the color walks as the surface
/// turns away from you. `Material.thinFilm` turns it on, and
/// `Material.thinFilmThickness` sets how thick the film is, in **nanometers**, which
/// is light's own scale rather than the scene's.
///
/// The **top row** holds one surface and changes only the thickness, so the colors run
/// through their series: a thin film is warm, a thicker one goes magenta and then
/// green, and a thick one crowds its bands together and washes toward silver. The
/// **bottom row** is the four ready-made finishes: anodized metal, oil on a wet road,
/// the nacre of a shell, and a soap wall whose thickness walks up and down as you
/// watch, so its color travels the series the top row lays out side by side.
///
/// Every body is a plain sphere. The rings you see on each one are the film itself:
/// the light's path through it grows as the surface turns, so one thickness makes many
/// colors across one body.
@main
final class ThinFilm: Sketch {

    let spacing = 2.4

    override func draw() {
        background(Color(hex: 0x07080D))

        cameraShowcase(.sway(amplitude: 0.2, period: .tau / 0.09), target: .zero, radius: 12.6,
                       elevation: 0.2, fieldOfView: .pi / 4)
        // The room lights the bodies and fills their reflections; the backdrop stays
        // out of the way, so what is left on each sphere is the film's own doing.
        environment(.courtyard.intensity(1.25).rotated(-0.8).lightingOnly())
        // A wall you see through then carries the room behind it rather than the
        // environment, which is what lets the soap film read as a bubble against the dark.
        sceneThroughGlass()

        // A single moving key, so the film's colors can be seen to hold their place on
        // the surface while the highlight travels over them.
        pointLight(Color(kelvin: 5600),
                   at: Vector3(cos(time * 0.4) * 8, 5.5, sin(time * 0.4) * 8),
                   intensity: 1.15)

        // Top row: one polished metal, four thicknesses. A metal reflects nearly
        // everything that lands on it, so it shows the whole color series at once.
        let thicknesses = [250.0, 400, 550, 750]
        row(y: spacing / 2, labels: thicknesses.map { "\(Int($0)) nm" }) { col in
            fill(Color(white: 0.75))
            material(Material(shading: .physicallyBased, metallic: 1, roughness: 0.16,
                              thinFilm: 1, thinFilmThickness: thicknesses[col]))
            drawSphere(radius: 0.92)
        }

        // Bottom row: the finishes the library carries. The soap wall drains from 780
        // down to 320 nm and back, which walks its color down the same series the top
        // row lays out side by side.
        let drain = 550 + cos(time * 0.35) * 230
        row(y: -spacing / 2, labels: ["anodized", "oil on water", "nacre", "soap film"]) { col in
            switch col {
            case 0:
                fill(Color(white: 0.72))
                material(.anodized)
            case 1:
                fill(Color(hex: 0x0A0C10))
                material(.oilOnWater)
            case 2:
                fill(Color(white: 0.85))
                material(.nacre)
            default:
                fill(Color(white: 0.85))
                material(.soapFilm(thickness: drain))
            }
            drawSphere(radius: 0.92)
        }

        drawCaption("thin film: color made by interference, not by pigment")
    }

    /// One row of four bodies with a projected label under each.
    private func row(y: Double, labels: [String], body: (Int) -> Void) {
        for col in 0..<4 {
            let x = (Double(col) - 1.5) * spacing
            withState {
                translate(x, y, 0)
                body(col)
            }
            withState {
                textFont(OutlineFont.system)
                textSize(24)
                textAlign(.center)
                noStroke()
                fill(Color(white: 0.8))
                if let p = project(Vector3(x, y - 1.35, 0)) {
                    drawText(labels[col], at: p)
                }
            }
        }
    }
}
