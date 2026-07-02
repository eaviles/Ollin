import Ollin

/// Interactive camera control: drive the camera by hand.
///
/// `cameraControl()` is opt-in, like `lights()`: call it each frame and the viewer
/// can drag to orbit the scene, scroll to dolly in and out, and right-drag (or
/// shift / option-drag) to pan the target. The motion is damped, so it settles
/// smoothly and a flick keeps a little spin. The framing arguments set the opening
/// shot; after that the viewer owns the pose.
///
/// Everything else is an ordinary 3D sketch: a small still life on a floor,
/// turning gently so it reads as solid even when the camera is still. Only the one
/// `cameraControl()` call hands the camera to the viewer.
@main
final class CameraControl3D: Sketch {

    override func draw() {
        background(Color(white: 0.05))
        cameraControl(target: Vector3(0, -0.2, 0), radius: 9, elevation: 0.35, fieldOfView: .pi / 4)

        lightingPreset(.threePoint)
        castShadows()

        withState {
            translate(0, -1.4, 0)
            fill(Color(white: 0.5)); specular(0.05)
            drawPlane(width: 18, depth: 18)
        }
        withState {
            translate(-2.3, -0.4, 0.4)
            fill(Color(white: 0.85)); specular(0.7); shininess(120)
            drawSphere(radius: 1.0)
        }
        withState {
            translate(0.4, -0.2, -0.3)
            rotateY(time * 0.3); rotateX(0.3)
            fill(Color(hue: 0.04, saturation: 0.5, brightness: 0.9)); specular(0.4); shininess(48)
            drawBox(size: 1.5)
        }
        withState {
            translate(2.6, -0.5, 0.6)
            rotateX(0.9); rotateY(time * 0.4)
            fill(Color(hue: 0.58, saturation: 0.45, brightness: 0.9)); specular(0.5); shininess(64)
            drawTorus(radius: 0.75, tube: 0.3)
        }

        drawCaption("Drag to orbit   ·   scroll to zoom   ·   right or shift-drag to pan")
    }
}
