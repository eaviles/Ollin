import Ollin
import OllinSamplePhotos
import OllinVision

/// The camera as a surface: the webcam's frame worn by a globe, and lighting it.
///
/// A camera frame is an `Image`, and an `Image` goes wherever an image goes: onto a
/// mesh through `textured(_:)`, and around the scene as its light through
/// `environment(.feed(feed))`. A live picture on a surface therefore asks for no
/// API of its own:
///
/// ```swift
/// environment(.feed(feed))                    // the room as the light
/// if let frame = feed.frame {
///     drawMesh(globe.textured(frame))         // the room as the surface
/// }
/// ```
///
/// Two things shape the sketch instead of the framework. The material is set every
/// frame, since each capture arrives as a fresh `Image`; and a fresh `Image` builds
/// its texture the first time it is drawn, so the feed costs one upload per new
/// frame and nothing while the frame holds. That is cheap for one surface and adds
/// up across many, so wear the feed on the thing that matters and let the same feed
/// light the rest. Walk past the camera and the globe carries you around with it.
/// With no camera, or under `--photo`, the globe wears the bundled city instead.
@main
final class LiveSurface: Sketch {

    let feed = Camera.orStill(SamplePhoto.city.load())
    /// Built once; only its material changes, once per new frame.
    let globe = Mesh.sphere(radius: 1.7, segments: 64, rings: 32)

    override func draw() {
        background(Color(hex: 0x0B0C12))
        toneMap(.aces)

        // Before the first frame, the standard waiting notice; nothing to wear yet.
        guard let frame = feed.frame else { drawFrame(feed); return }

        // The room as the light: the same frames the globe wears.
        environment(.feed(feed))

        cameraShowcase(.sway(amplitude: 0.3, period: .tau / 0.08), target: .zero,
                       radius: 7.5, elevation: 0.14, fieldOfView: .pi / 4.6)

        // The room as the surface: a fresh image each frame, one upload each.
        withState {
            rotateY(time * 0.25)
            fill(.white)
            material(.dielectric(roughness: 0.5))
            drawMesh(globe.textured(frame))
        }

        // A chrome ball beside it, reflecting the room the globe is wearing.
        withState {
            translate(2.9, -0.9, 0.6)
            fill(.white)
            material(.metal(roughness: 0.05))
            drawSphere(radius: 0.65)
        }

        drawCaption("The camera frame as a surface, and as the light")
    }
}
