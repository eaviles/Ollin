import Ollin

/// LinearFrame: a scene whose file is worth more than its picture.
///
/// The window shows what a screen can show: the bright side of each sphere is
/// white, and the fog decides what reads as far away. `--export-exr` writes the
/// frame one step earlier, in linear light, where the highlights are still
/// several times brighter than white and every pixel carries its distance from
/// the eye. That file is what a compositing program wants: the look can be
/// graded, the glow put on by hand, the haze replaced, none of it guessing at
/// numbers that were already thrown away.
///
/// ```sh
/// swift run Example-Export-LinearFrame --export-exr /tmp/frame.exr
/// swift run Example-Export-LinearFrame --export /tmp/frame.png        # the same frame, clipped
/// swift run Example-Export-LinearFrame --export-sequence /tmp/frames --seconds 2 --exr
/// ```
///
/// The printed line says what came through: the brightest component as a
/// multiple of white, and the nearest and farthest distances in the `Z` channel.
@main
final class LinearFrame: Sketch {
    @Param("Lamp", 2.0 ... 20.0, icon: "lightbulb.max") var lamp = 9.0
    @Param("Gloss", 0.0 ... 1.0, icon: "circle.lefthalf.filled") var gloss = 0.85
    @Param("Haze", 0.0 ... 0.12, icon: "cloud.fog") var haze = 0.045
    @Param("Turn", 0.0 ... 0.4, icon: "arrow.clockwise") var turn = 0.12

    override func setup() {
        seed(5)
    }

    override func draw() {
        background(Color(hex: 0x05070C))
        // A long lane down the scene, so the distances in the depth channel spread
        // from a couple of units to the far plane.
        perspective(eye: Vector3(0, 3.1, 7.4), target: Vector3(0, -0.5, -9),
                    fieldOfView: .pi / 3.2, near: 0.5, far: 40)
        fog(Color(hex: 0x0C121C), density: haze)

        ambientLight(Color(white: 0.06))
        // One hard lamp, close and bright, which is what puts the highlights past
        // white. A screen has to fold them back in; the linear file does not.
        let swing = cos(time * turn * .tau) * 2.2
        pointLight(Color(hue: 0.09, saturation: 0.22, brightness: 1),
                   at: Vector3(2.6 + swing, 2.8, 3.4), intensity: lamp)
        pointLight(Color(hue: 0.55, saturation: 0.55, brightness: 1),
                   at: Vector3(-3.8, 1.4, -6), intensity: lamp * 0.55)

        // A polished floor, so the lamp lays a long streak down the lane.
        withState {
            translate(0, -0.6, 0)
            fill(Color(white: 0.16))
            specular(0.55)
            specularSharpness(260)
            drawPlane(width: 30, depth: 44)
        }

        // Nine spheres walking away from the camera, alternating sides, so the
        // near ones and the far ones sit in the same frame.
        for i in 0..<9 {
            let t = Double(i) / 8
            withState {
                translate(i.isMultiple(of: 2) ? -1.9 : 1.9, -0.05 + t * 0.05,
                          2.4 - Double(i) * 2.2)
                fill(Color(hue: 0.02 + t * 0.55, saturation: 0.5, brightness: 0.9))
                specular(gloss)
                specularSharpness(90 + t * 260)
                drawSphere(radius: 0.55)
            }
        }
    }
}
