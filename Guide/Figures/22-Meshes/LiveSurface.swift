// figure: frame=0
//
// Guide figure (Chapter 22): the camera as a surface. The same authored "camera
// frame" the LiveRoom figure uses (a warm lamp side, a cool window side, a dark
// floor band), so the figure reproduces; everything after the frame is the real
// path. The frame is worn by a globe through `textured(_:)` and handed to
// `environment(.feed(...))` at once, so the picture on the globe is also the
// light on it, and the chrome ball beside it reflects the room the globe wears.
import Ollin

/// The stand-in feed: one authored frame, held the way a webcam holds its latest.
final class PictureFeed: VideoFeed {
    let image: Image?
    init(_ image: Image) { self.image = image }
    var frame: Image? { image }
    var frameSize: Vector2? { image?.size }
}

final class LiveSurface: Sketch {
    override var canvasSize: CanvasSize { .size(880, 550) }

    lazy var feed = PictureFeed(Self.roomFrame())
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

    /// The made-up room: a warm lamp glow on the left, a cool window on the
    /// right, a dark floor band below (the LiveRoom figure's frame).
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
                    c = Color.mix(warm, cool, fx)
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
