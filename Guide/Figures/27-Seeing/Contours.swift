// figure: frame=0
//
// Guide diagram (Chapter 27): a picture becomes geometry. Left: a generated
// ink study (blobby splashes and a ring, built pixel by pixel, standing in
// for a camera frame). Right: what ContourDetector traces out of it, drawn as
// stroked vector shapes, with the ring's hole preserved. The detection is the
// real Vision request, run once on the still image.
import Ollin
import OllinVision

final class Contours: Sketch {
    override var canvasSize: CanvasSize { .size(880, 550) }

    var picture: Image?
    var traced: [Shape] = []

    let ink = Color(hex: 0x2B2B2B)
    let faint = Color(hex: 0x2B2B2B, alpha: 0.28)
    let soft = Color(hex: 0x2B2B2B, alpha: 0.6)
    let accent = Color(hex: 0xE4572E)

    let rightPanel = Rectangle(x: 460, y: 100, width: 360, height: 360)

    override func setup() {
        let image = Contours.paintStudy()
        picture = image
        traced = Contours.trace(image, into: rightPanel)
    }

    override func draw() {
        background(Color(hex: 0xF7F5F1))
        textSize(19)

        let leftPanel = Rectangle(x: 60, y: 100, width: 360, height: 360)
        if let picture { drawImage(picture, in: leftPanel) }

        fill(accent.withAlpha(0.12))
        stroke(accent)
        strokeWeight(2)
        for shape in traced { drawShape(shape) }

        noFill()
        stroke(faint)
        strokeWeight(1.5)
        drawRect(leftPanel)
        drawRect(rightPanel)

        noStroke()
        fill(ink)
        textAlign(.center, .top)
        drawText("the picture", leftPanel.center.x, 472)
        drawText("the traced shapes, holes and all", rightPanel.center.x, 472)
        fill(soft)
        drawText("closed vector contours: ready for booleans, hatching, warping, or a plotter",
                 width / 2, 512)
    }

    /// An ink study built pixel by pixel: three blobby splashes (a metaball
    /// field, thresholded) and a ring, dark on white, the kind of high-contrast
    /// subject the contour tracer loves.
    static func paintStudy() -> Image {
        let n = 340
        var bytes = [UInt8](repeating: 255, count: n * n * 4)
        let blobs = [(105.0, 120.0, 42.0), (170.0, 95.0, 30.0), (135.0, 175.0, 34.0)]
        for y in 0 ..< n {
            for x in 0 ..< n {
                let px = Double(x), py = Double(y)
                var fieldSum = 0.0
                for (bx, by, r) in blobs {
                    let d2 = (px - bx) * (px - bx) + (py - by) * (py - by)
                    fieldSum += r * r / max(d2, 1)
                }
                let ringDistance = ((px - 252) * (px - 252) + (py - 256) * (py - 256))
                    .squareRoot()
                let isInk = fieldSum > 1 || abs(ringDistance - 52) < 16
                if isInk {
                    let i = (y * n + x) * 4
                    bytes[i] = 30; bytes[i + 1] = 30; bytes[i + 2] = 34
                }
            }
        }
        return Image(width: n, height: n, premultipliedRGBA: bytes)!
    }

    /// Run the one-shot contour detection and wait for it, mapping the result
    /// into the panel where the figure draws it.
    static func trace(_ image: Image, into panel: Rectangle) -> [Shape] {
        let result = try? waitFor(image) { try await ContourDetector.detect(in: $0) }
        return result?.shapes(in: panel) ?? []
    }
}
