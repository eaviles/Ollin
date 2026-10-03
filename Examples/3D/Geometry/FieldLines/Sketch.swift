import Ollin

/// **Field lines**: the magnetic field of a planet drawn as lines in space, looping
/// out of one pole and back into the other, with a pulse of light running along
/// each one.
///
/// A magnet the size of a planet has a simple field far from its surface: every
/// line of it keeps to a shell where the distance from the center is `L·sin²θ`, `θ`
/// measured from the magnetic axis, so each line leaves the surface at one latitude
/// and comes back at the same latitude on the other side. The sketch draws a few of
/// those shells at even steps round the axis, each line a `drawPolyline` through
/// points in space with a color for every point. The planet is a solid sphere, so it
/// hides the far half of every loop, and the axis is tilted the way a planet's
/// magnetic axis usually is, by a 3D `rotateZ` that moves the lines with it.
///
/// The lines take a weight measured on the canvas by default, so a line keeps its
/// width near the camera and far from it. Set **units** to world and the weight is
/// read in the scene's own units instead: the lines thin as they go back into the
/// scene, like thread would. **grid** and **axes** turn on the two helpers built
/// from the same lines, a floor across the equator and the magnetic axis itself.
///
/// Try it: raise **shells** and **lines** for a denser field, or slow the **pulse**
/// to zero to see the field still.
@main
final class FieldLines_Example: Sketch {

    @Param(1 ... 6, icon: "circle.dotted") var shells = 4
    @Param(4 ... 24, icon: "line.3.horizontal") var lines = 12
    @Param(0.5 ... 6, icon: "lineweight") var weight = 2.0
    @Param var units: StrokeUnits = .screen
    @Param(0 ... 1, icon: "bolt.horizontal") var pulse = 0.35
    @Param(icon: "grid") var grid = true
    @Param(icon: "move.3d") var axes = true

    /// How far each shell reaches at the magnetic equator, in planet radii.
    private func reach(_ shell: Int) -> Double { 1.6 * pow(1.45, Double(shell)) }

    override func draw() {
        background(Color(hex: 0x05060B))
        cameraShowcase(.turntable(period: 48), target: Vector3(0, -0.3, 0), radius: 12,
                       elevation: 0.22, fieldOfView: .pi / 3.6)
        directionalLight(.white, direction: Vector3(-0.6, -0.4, -0.7), intensity: 1.1)
        ambientLight(Color(white: 0.12))

        if grid {
            stroke(Color(hex: 0x2A3346))
            strokeWeight(1)
            drawGrid(size: 16, divisions: 16)
        }

        rotateZ(0.2)                                   // the magnetic axis, tilted

        fill(Color(hex: 0x1D3E6E))
        specular(0.3); specularSharpness(32)
        drawSphere(radius: 1, segments: 64, rings: 32)

        if axes {
            strokeWeight(2)
            drawAxes(length: 2.4)
        }

        strokeWeight(units == .world ? weight * 0.012 : weight, in: units)
        strokeCap(.round)
        strokeJoin(.round)
        for shell in 0 ..< shells {
            let l = reach(shell)
            // Where the shell meets the surface: L·sin²θ = 1.
            let start = asin((1 / l).squareRoot())
            let hue = 0.08 + 0.5 * Double(shell) / Double(max(shells - 1, 1))
            for k in 0 ..< lines {
                let around = (Double(k) + 0.5 * Double(shell % 2)) / Double(lines) * .tau
                var points: [Vector3] = []
                var colors: [Color] = []
                let steps = 72 + 24 * shell
                for i in 0 ... steps {
                    let along = Double(i) / Double(steps)
                    let theta = start + (.pi - 2 * start) * along
                    let r = l * sin(theta) * sin(theta)
                    points.append(Vector3(r * sin(theta) * cos(around), r * cos(theta),
                                          r * sin(theta) * sin(around)))
                    colors.append(color(hue: hue, along: along, line: k + shell * lines))
                }
                drawPolyline(points, colors: colors)
            }
        }
    }

    /// The line's own color, brightened where the pulse is: a short bright stretch
    /// running from the south pole to the north, each line at its own phase.
    private func color(hue: Double, along: Double, line: Int) -> Color {
        let phase = Double((line * 37) % 101) / 101
        var gap = (along - (time * pulse * 0.25 + phase)).truncatingRemainder(dividingBy: 1)
        if gap < 0 { gap += 1 }
        let glow = pulse > 0 ? exp(-pow(min(gap, 1 - gap) / 0.05, 2)) : 0
        return Color(hue: hue, saturation: 0.75 - 0.55 * glow, brightness: 0.55 + 0.45 * glow)
    }
}
