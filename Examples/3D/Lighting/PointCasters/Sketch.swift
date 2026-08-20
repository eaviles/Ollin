import Ollin

/// PointCasters: a key light and two lamps in the room, all three throwing shadows.
///
/// A point light casts every way at once, so it is the expensive kind: it needs a whole
/// cube of depth around it, or a set of rays traced from each lit pixel. A frame can
/// hold several of them all the same. Here a directional key rakes in from above, a warm
/// lamp circles the props at head height, and a cool one crosses it the other way. Watch
/// one prop: the key pins a shadow under it while each lamp swings its own around it,
/// and where two shadows overlap the floor keeps only what the third light still reaches.
///
/// The renderer picks the cheaper route for the GPU it is on, and nothing here changes
/// with it. On Apple silicon each lamp traces its own rays; elsewhere each renders its
/// own six-face cube of depth.
@main
final class PointCasters: Sketch {

    override func draw() {
        background(Color(hex: 0x080A10))

        cameraShowcase(.turntable(period: .tau / 0.1), target: Vector3(0, 1.0, 0),
                       radius: 15, elevation: 0.8, fieldOfView: .pi / 4.4)

        ambientLight(Color(white: 0.05))

        // The key: high, cool, and steady, so its shadows sit under the props.
        directionalLight(Color(hex: 0xDCE6FF), direction: Vector3(0.25, -1.0, -0.35),
                         intensity: 0.55)

        // The warm lamp, circling the props at head height.
        let warmAngle = time * 0.35
        pointLight(Color(hue: 0.07, saturation: 0.45, brightness: 1.0),
                   at: Vector3(cos(warmAngle) * 6.0, 3.4, sin(warmAngle) * 6.0),
                   intensity: 1.5, specular: .white)

        // The cool lamp, crossing it the other way and a little lower.
        let coolAngle = -time * 0.27 + .pi
        pointLight(Color(hue: 0.55, saturation: 0.5, brightness: 1.0),
                   at: Vector3(cos(coolAngle) * 5.2, 2.6, sin(coolAngle) * 5.2),
                   intensity: 1.3, specular: .white)

        castShadows()
        shadowSoftness(0.4)

        // The floor that catches all three sets of shadows.
        withState {
            fill(Color(white: 0.7))
            specular(0.05)
            drawPlane(width: 44, depth: 44)
        }

        specular(0.25)
        shininess(40)

        withState {
            translate(-1.6, 1.1, 1.8)
            rotateY(time * 0.4)
            fill(Color(hue: 0.02, saturation: 0.5, brightness: 0.95))
            drawBox(size: 2.2)
        }
        withState {
            translate(2.6, 1.3, -0.6)
            fill(Color(hue: 0.4, saturation: 0.42, brightness: 0.95))
            drawSphere(radius: 1.3)
        }
        withState {
            translate(0.2, 1.6, -3.0)
            rotateY(-time * 0.3)
            fill(Color(hue: 0.72, saturation: 0.4, brightness: 0.95))
            drawCylinder(radius: 0.7, height: 3.2)
        }

        drawCaption("Three casters: a key overhead and two lamps circling the props")
    }
}
