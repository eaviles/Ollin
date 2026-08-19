// figure: frame=0
//
// Guide figure (Chapter 25): a live-feed environment. The "camera frame" is one
// authored picture (a warm lamp side, a cool window side, a dark floor band) so
// the figure reproduces; everything after the frame is the real path. The same
// image is drawn as the backdrop and handed to `environment(.feed(...))`, so the
// picture behind the spheres is also the light on them: chrome reflects it, the
// rough metal smears it, the white matte one picks up its overall color.
import Ollin

/// The stand-in feed: one authored frame, held the way a webcam holds its latest.
final class PictureFeed: VideoFeed {
    let image: Image?
    init(_ image: Image) { self.image = image }
    var frame: Image? { image }
    var frameSize: Vector2? { image?.size }
}

final class LiveRoom: Sketch {
    override var canvasSize: CanvasSize { .size(880, 550) }

    lazy var feed = PictureFeed(Self.roomFrame())

    override func draw() {
        // The frame as the picture (what drawFrame(camera) would do)…
        if let frame = feed.frame { drawImage(frame, in: bounds) }
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

    /// The made-up room: a warm lamp glow on the left, a cool window on the
    /// right, a dark floor band below. Enough structure for the reflections
    /// to read, authored in code so the render never changes.
    static func roomFrame() -> Image {
        let w = 480, h = 270
        let img = Image(width: w, height: h, color: .black)
        for y in 0..<h {
            let fy = Double(y) / Double(h - 1)
            for x in 0..<w {
                let fx = Double(x) / Double(w - 1)
                var c: Color
                if fy > 0.72 {
                    c = Color(hue: 0.07, saturation: 0.35, brightness: 0.10 + 0.05 * (1 - fy))
                } else {
                    let warm = Color(hue: 0.07, saturation: 0.55, brightness: 0.75 - 0.45 * fy)
                    let cool = Color(hue: 0.58, saturation: 0.45, brightness: 0.55 - 0.25 * fy)
                    c = Color.mix(warm, cool, t: fx)
                    if fx > 0.62, fx < 0.9, fy > 0.12, fy < 0.55 {
                        c = Color(hue: 0.56, saturation: 0.18, brightness: 0.95)   // the window
                    }
                    if fx > 0.06, fx < 0.2, fy > 0.28, fy < 0.6 {
                        c = Color(hue: 0.09, saturation: 0.65, brightness: 0.9)    // the lamp
                    }
                }
                img[x, y] = c
            }
        }
        return img
    }
}
