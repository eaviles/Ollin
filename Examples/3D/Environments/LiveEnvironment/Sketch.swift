import Ollin
import OllinVision

/// A live camera environment: the room lights the scene.
///
/// `environment(.feed(camera))` wraps the webcam's latest frame around the scene
/// and bakes it into the image-based lighting, refreshing as frames arrive. A
/// chrome sphere reflects the room, a rough metal smears it into a satin sheen,
/// and a white matte sphere picks up the room's overall color and brightness:
/// walk past the camera, or hold up something colorful, and the spheres respond.
///
/// The feed lights the scene but never draws as the backdrop, so the sketch shows
/// the camera frame itself behind the spheres; lighting and picture stay one
/// world. Any `VideoFeed` works the same way: a playing video, a screen capture,
/// or the phone's camera over the USB link.
@main
final class LiveEnvironment: Sketch {

    let camera = Camera()

    override func setup() { try? camera.start() }

    override func draw() {
        background(Color(hex: 0x0B0C12))
        toneMap(.aces)

        // The room as the picture: the same frames that light the spheres.
        drawFrame(camera)

        // The room as the light.
        environment(.feed(camera))

        cameraShowcase(.sway(amplitude: 0.35, period: .tau / 0.1), target: .zero,
                       radius: 10, elevation: 0.08, fieldOfView: .pi / 4.6)

        let roughness = [0.03, 0.35, 0.9]
        for (i, r) in roughness.enumerated() {
            withState {
                translate((Double(i) - 1) * 2.6, 0, 0)
                if i < 2 {
                    fill(.white)
                    material(.metal(roughness: r))
                } else {
                    fill(Color(white: 0.92))
                    material(.dielectric(roughness: r))
                }
                drawSphere(radius: 1.05)
            }
        }
    }
}
