// figure: frame=0
//
// Guide figure (Chapter 22): a live-feed environment. The "camera frame" is one
// bundled photograph, an alley with bright sky above and shaded walls below, so
// the figure reproduces; everything after the frame is the real path. The same
// image is drawn as the backdrop and handed to `environment(.feed(...))`, so the
// picture behind the spheres is also the light on them: chrome reflects it, the
// rough metal smears it, the white matte one picks up its overall color.
import Ollin
import OllinSamplePhotos

/// The stand-in feed: one still picture, held the way a webcam holds its latest.
final class PictureFeed: VideoFeed {
    let image: Image?
    init(_ image: Image) { self.image = image }
    var frame: Image? { image }
    var frameSize: Vector2? { image?.size }
}

final class LiveRoom: Sketch {
    override var canvasSize: CanvasSize { .size(880, 550) }

    lazy var feed = PictureFeed(SamplePhoto.alley.load().resized(width: 512, height: 512))

    override func draw() {
        // The frame as the picture (what drawFrame(camera) would do)…
        if let frame = feed.frame { drawImage(frame, in: bounds, fit: .cover) }
        // …and the frame as the light.
        environment(.feed(feed))
        toneMap(.aces)

        camera(.perspective(eye: Vector3(0, 0.25, 6.4), target: Vector3(0, 0, 0),
                            fieldOfView: .pi / 4.6))
        let roughness = [0.03, 0.35, 0.9]
        for (i, r) in roughness.enumerated() {
            withState {
                translate((Double(i) - 1) * 2.5, 0, 0)
                if i < 2 {
                    fill(.white)
                    material(.metal(roughness: r))
                } else {
                    fill(Color(white: 0.92))
                    material(.dielectric(roughness: r))
                }
                drawSphere(radius: 1.02)
            }
        }
    }
}
