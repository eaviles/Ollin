import Ollin

/// **Diffusion curves**: a few marks held as color sources, and the color let
/// out into the space between them until it settles. Away from the marks every
/// pixel ends up the average of its four neighbors, which is the rule a soap
/// film obeys, so the field is smooth everywhere and nothing overshoots.
///
/// A curve drawn with `drawDiffusionCurve` carries a different color on each
/// side, so the field jumps across it. That is what a gradient cannot do: a
/// gradient needs a direction and two ends, and this needs neither.
///
/// Try it: hold the mouse down to move the light, or drop the `sharpness` and watch
/// the solve go soft.
@main
final class DiffusionCurves_Example: Sketch {
    @Param(0 ... 1, icon: "circle.lefthalf.filled") var sharpness = 0.8
    @Param(icon: "scribble.variable") var showMarks = false

    let sky = Color(hex: 0x2A3D66)
    let dusk = Color(hex: 0xE86F4A)
    let deep = Color(hex: 0x101A2E)
    let sand = Color(hex: 0xE8C98A)

    override func draw() {
        let marks = renderTarget()
        withTarget(marks) {
            background(Color(white: 0, alpha: 0))

            // A horizon: warm above, deep below, bent by a slow wave.
            let horizon = stride(from: -20.0, through: width + 20, by: 12).map { x in
                Vector2(x, height * 0.45 + sin(x / width * 5 + time * 0.4) * height * 0.03)
            }
            drawDiffusionCurve(horizon, left: dusk, right: deep, width: 4)

            // A second curve lower down, cool over warm, so the two fields meet.
            let ridge = stride(from: -20.0, through: width + 20, by: 12).map { x in
                Vector2(x, height * 0.78 - sin(x / width * 3 - time * 0.25) * height * 0.05)
            }
            drawDiffusionCurve(ridge, left: sand, right: sky, width: 4)

            // The light: one bright dot the whole upper field bends around.
            noStroke()
            fill(Color(hex: 0xFFE9B0))
            let lightX = mouseIsPressed ? mouseX : width * 0.5 + cos(time * 0.3) * width * 0.3
            drawCircle(lightX, height * 0.22, 26)

            // Two cool anchors in the corners, so the sky has somewhere to go.
            fill(sky)
            drawCircle(width * 0.04, height * 0.04, 20)
            drawCircle(width * 0.96, height * 0.04, 20)
        }

        drawImage(marks.filtered(.diffuse(sharpness: sharpness)).image, 0, 0)
        if showMarks { drawImage(marks.image, 0, 0) }
    }
}
