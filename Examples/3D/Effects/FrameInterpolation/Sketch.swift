import Ollin

/// Frame interpolation: draw half as often, move at the display's rate.
///
/// With `frameInterpolation()` on, the sketch's `draw()` runs on every other
/// refresh, and on the refresh between the platform builds the frame that
/// belongs in the middle from the two drawn either side of it, reading the
/// depth buffer and the same per-pixel motion the upscaler uses. The clock is
/// untouched, so the rings keep their speed and only their sampling halves.
///
/// The scene is deliberately busy so the trade is visible: a ring of orbiting
/// blocks, a spinning arm, and a fast pendulum, all crossing each other, which
/// is the hard case for anything that has to guess what happened between two
/// pictures. Watch the FPS readout in the inspector while toggling: it counts
/// the frames the *sketch* drew, so it halves while the motion on screen does
/// not. Two things to look for: a drawn frame waits one refresh before it is
/// shown, so the mouse-driven camera feels about 16 ms later, and a mark moving
/// faster than the interpolator can follow (turn `speed` up) is repeated rather
/// than smeared. Exports never interpolate: what you keep is the frames the
/// sketch drew.
@main
final class FrameInterpolation: Sketch {

    @Param(icon: "square.stack.3d.forward.dottedline", group: "Image")
    var interpolating = true

    @Param(0.2...4, icon: "speedometer", group: "Motion")
    var speed = 1.0

    override func draw() {
        background(Color(white: 0.04))

        cameraShowcase(.sway(period: 30), target: Vector3(0, 1.0, 0),
                       radius: 11, elevation: 0.3, fieldOfView: .pi / 3.2)
        environment(.sky(turbidity: 4, sunElevation: 0.4))
        directionalLight(.white, direction: Vector3(-0.4, -0.9, -0.3), intensity: 0.95)
        castShadows()
        if interpolating { frameInterpolation() }

        withState {
            fill(Color(white: 0.62))
            material(.dielectric(roughness: 0.5))
            translate(0, -0.1, 0)
            drawBox(width: 16, height: 0.2, depth: 16)
        }

        // A ring of blocks going around, each one declared as a mover so the
        // interpolator is handed its exact screen motion rather than guessing.
        let turn = time * 0.55 * speed
        for i in 0..<12 {
            let a = Double(i) / 12 * .tau
            withMotion("block\(i)") {
                withState {
                    fill(Color(hue: Double(i) / 12, saturation: 0.5, brightness: 0.9))
                    material(.metal(roughness: 0.25))
                    rotate(turn, axis: .unitY)
                    translate(cos(a) * 4.2, 0.75 + sin(a * 3 + turn) * 0.35, sin(a) * 4.2)
                    rotate(a + turn, axis: .unitY)
                    drawBox(width: 0.8, height: 0.8, depth: 0.8)
                }
            }
        }

        // The fast one: a thin arm sweeping the middle, the mark most likely to
        // outrun what a made frame can follow.
        withMotion("arm") {
            withState {
                fill(Color(hex: 0xF2C14E))
                material(.metal(roughness: 0.15))
                translate(0, 1.6, 0)
                rotate(time * 2.4 * speed, axis: .unitY)
                translate(1.9, 0, 0)
                drawBox(width: 3.6, height: 0.09, depth: 0.09)
            }
        }

        // A pendulum, whose speed changes through every swing: an easy read on
        // whether the in-between picture arrives at the right moment.
        withMotion("pendulum") {
            withState {
                fill(Color(hex: 0xE05A47))
                material(.dielectric(roughness: 0.3))
                translate(sin(time * 1.9 * speed) * 3.4, 2.6, -2.2)
                drawSphere(radius: 0.42)
            }
        }

        drawCaption("frameInterpolation() \(interpolating ? "on: draws 30, shows 60" : "off") - toggle it in the inspector")
    }
}
