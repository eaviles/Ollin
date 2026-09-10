// figure: frame=0
//
// Guide figure (Chapter 22): the camera as a surface. The same "camera frame"
// the LiveRoom figure uses, a bundled photograph of an alley under a bright
// sky, so the figure reproduces; everything after the frame is the real
// path. The frame is worn by a globe through `textured(_:)` and handed to
// `environment(.feed(...))` at once, so the picture on the globe is also the
// light on it, and the chrome ball beside it reflects the room the globe wears.
import Ollin
import OllinSamplePhotos

/// The stand-in feed: one still picture, held the way a webcam holds its latest.
final class PictureFeed: VideoFeed {
    let image: Image?
    init(_ image: Image) { self.image = image }
    var frame: Image? { image }
    var frameSize: Vector2? { image?.size }
}

final class LiveSurface: Sketch {
    override var canvasSize: CanvasSize { .size(880, 550) }

    lazy var feed = PictureFeed(SamplePhoto.alley.load().resized(width: 512, height: 512))
    let globe = Mesh.sphere(radius: 1.7, segments: 64, rings: 32)

    override func draw() {
        background(Color(hex: 0x0B0C12))
        toneMap(.aces)
        // The frame as the light…
        environment(.feed(feed))
        camera(.perspective(eye: Vector3(0.4, 0.9, 7.2), target: Vector3(0.3, -0.1, 0),
                            fieldOfView: .pi / 4.6))
        // …and the frame as the surface.
        if let frame = feed.frame {
            withState {
                translate(-0.6, 0, 0)
                rotateY(-0.9)
                fill(.white)
                material(.dielectric(roughness: 0.5))
                drawMesh(globe.textured(frame))
            }
        }
        withState {
            translate(2.5, -0.95, 0.9)
            fill(.white)
            material(.metal(roughness: 0.05))
            drawSphere(radius: 0.7)
        }
    }
}
