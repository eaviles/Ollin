@testable import Ollin
import CoreGraphics
import Foundation
import Testing

/// What a picture does when the box it is given is not its shape (`ImageFit`).
///
/// The render probes stage one picture four bands wide, red then green then blue
/// then white, at an aspect of 4:1, drawn into a square. The three answers put
/// different bands in different places, and no tolerance can confuse them:
/// stretched shows all four as quarters, contained shows all four in a band with
/// the backdrop above and below, and covered shows only the middle two.
@Suite(.serialized)
@MainActor
struct ImageFitTests {

    // MARK: The crop arithmetic

    /// The crop is centered on the picture. Neither `.cover` nor anything built
    /// on it favors an edge, so the middle of the picture is always the part
    /// that survives.
    @Test(arguments: [Rectangle(x: 0, y: 0, width: 100, height: 100),
                      Rectangle(x: 0, y: 0, width: 300, height: 100),
                      Rectangle(x: 0, y: 0, width: 40, height: 900)])
    func theCropIsCentered(_ box: Rectangle) {
        let crop = Drawer.coveringCrop(of: Vector2(640, 480), in: box)
        #expect(abs(crop.center.x - 0.5) < 1e-12)
        #expect(abs(crop.center.y - 0.5) < 1e-12)
    }

    /// One axis always survives whole. Cropping both would shrink the picture
    /// for no reason, since covering only ever needs to lose the surplus on the
    /// one axis that has any.
    @Test(arguments: [Vector2(640, 480), Vector2(100, 1000), Vector2(1000, 100)])
    func oneAxisOfTheCropSurvivesWhole(_ size: Vector2) {
        let crop = Drawer.coveringCrop(of: size, in: Rectangle(x: 0, y: 0, width: 300, height: 200))
        #expect(abs(Swift.max(crop.width, crop.height) - 1) < 1e-12,
                "neither axis is whole: \(crop)")
    }

    /// The deciding law: what the crop leaves must have the *box's* shape, or the
    /// picture arrives stretched after all. Measured in the picture's own pixels,
    /// which is where the two aspect ratios finally meet.
    @Test(arguments: [(Vector2(640, 480), Rectangle(x: 0, y: 0, width: 300, height: 300)),
                      (Vector2(640, 480), Rectangle(x: 0, y: 0, width: 90, height: 400)),
                      (Vector2(100, 900), Rectangle(x: 0, y: 0, width: 800, height: 200)),
                      (Vector2(50, 50), Rectangle(x: 0, y: 0, width: 640, height: 480))])
    func whatTheCropLeavesHasTheBoxesShape(_ size: Vector2, _ box: Rectangle) {
        let crop = Drawer.coveringCrop(of: size, in: box)
        let kept = (crop.width * size.x) / (crop.height * size.y)
        #expect(abs(kept - box.width / box.height) < 1e-9,
                "kept \(kept), box \(box.width / box.height)")
    }

    /// A picture already the box's shape loses nothing.
    @Test func aMatchingPictureIsNotCropped() {
        let crop = Drawer.coveringCrop(of: Vector2(600, 400),
                                       in: Rectangle(x: 0, y: 0, width: 300, height: 200))
        #expect(crop == Rectangle(x: 0, y: 0, width: 1, height: 1))
    }

    /// The crop never asks for anything outside the picture.
    @Test(arguments: [Vector2(640, 480), Vector2(3, 4000), Vector2(4000, 3)])
    func theCropStaysInsideThePicture(_ size: Vector2) {
        let crop = Drawer.coveringCrop(of: size, in: Rectangle(x: 0, y: 0, width: 137, height: 61))
        #expect(crop.x >= 0 && crop.y >= 0)
        #expect(crop.x + crop.width <= 1 + 1e-12)
        #expect(crop.y + crop.height <= 1 + 1e-12)
    }

    /// Nothing to divide by means nothing to crop.
    @Test func aDegeneratePictureIsReadWhole() {
        let box = Rectangle(x: 0, y: 0, width: 100, height: 100)
        #expect(Drawer.coveringCrop(of: Vector2(0, 100), in: box).width == 1)
        #expect(Drawer.coveringCrop(of: Vector2(100, 100),
                                    in: Rectangle(x: 0, y: 0, width: 0, height: 5)).height == 1)
    }

    // MARK: fitting against covering

    /// The two are the same construction with the two ends of one choice: fitting
    /// takes the smaller scale and sits inside, covering takes the larger and
    /// runs past. Both keep the shape and both stay centered.
    @Test(arguments: [Vector2(640, 480), Vector2(120, 900), Vector2(50, 50)])
    func fittingSitsInsideAndCoveringRunsPast(_ size: Vector2) {
        let box = Rectangle(x: 40, y: 90, width: 300, height: 200)
        let inside = Rectangle(fitting: size, in: box)
        let outside = Rectangle(covering: size, in: box)

        for made in [inside, outside] {
            #expect(abs(made.width / made.height - size.x / size.y) < 1e-9, "shape: \(made)")
            #expect(abs(made.center.x - box.center.x) < 1e-9)
            #expect(abs(made.center.y - box.center.y) < 1e-9)
        }
        #expect(inside.width <= box.width + 1e-9 && inside.height <= box.height + 1e-9)
        #expect(outside.width >= box.width - 1e-9 && outside.height >= box.height - 1e-9)
    }

    // MARK: What actually draws

    /// Four bands across, one row of texels tall enough that filtering never
    /// reaches from one band into the middle of the next.
    static func fourBands() -> Image {
        let image = Image(width: 16, height: 4, color: .black)
        let colors: [Color] = [.red, .green, .blue, .white]
        for x in 0..<16 {
            for y in 0..<4 { image[x, y] = colors[x / 4] }
        }
        return image
    }

    final class Probe: Sketch {
        var fit: ImageFit = .stretch
        override var canvasSize: CanvasSize { .square(240) }

        static func make(_ fit: ImageFit) -> Probe {
            let p = Probe()
            p.fit = fit
            return p
        }

        override func draw() {
            background(Color(hex: 0x304050))
            drawImage(ImageFitTests.fourBands(), in: bounds, fit: fit)
        }
    }

    private func pixels(of image: CGImage) -> [UInt8] {
        let w = image.width, h = image.height
        var data = [UInt8](repeating: 0, count: w * h * 4)
        let ctx = CGContext(data: &data, width: w, height: h, bitsPerComponent: 8,
                            bytesPerRow: w * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        return data
    }

    /// The mean of one channel over a fractional patch of the frame.
    private func patch(_ image: CGImage, x0: Double, x1: Double,
                       y0: Double, y1: Double, channel: Int) -> Double {
        let d = pixels(of: image)
        var sum = 0, count = 0
        for py in Int(Double(image.height) * y0)..<Int(Double(image.height) * y1) {
            for px in Int(Double(image.width) * x0)..<Int(Double(image.width) * x1) {
                sum += Int(d[(py * image.width + px) * 4 + channel]); count += 1
            }
        }
        return Double(sum) / Double(Swift.max(count, 1))
    }

    /// Red, green and blue read at the center of each quarter across, on a row.
    private func quarters(_ image: CGImage, row: Double) -> [(r: Double, g: Double, b: Double)] {
        (0..<4).map { q in
            let x0 = 0.05 + Double(q) * 0.25, x1 = 0.20 + Double(q) * 0.25
            return (patch(image, x0: x0, x1: x1, y0: row - 0.04, y1: row + 0.04, channel: 0),
                    patch(image, x0: x0, x1: x1, y0: row - 0.04, y1: row + 0.04, channel: 1),
                    patch(image, x0: x0, x1: x1, y0: row - 0.04, y1: row + 0.04, channel: 2))
        }
    }

    private func render(_ fit: ImageFit) -> CGImage? {
        OllinApp.image(of: Probe.make(fit), frame: 1)
    }

    /// The old behavior, and still the default: every band lands, each a quarter
    /// of the square, and the picture's own proportions are gone.
    @Test(.enabled(if: Snapshot.hasMetal))
    func stretchShowsEveryBandAcrossTheWholeSquare() throws {
        let q = quarters(try #require(render(.stretch)), row: 0.5)
        #expect(q[0].r > 200 && q[0].g < 60, "band 1 should be red: \(q[0])")
        #expect(q[1].g > 200 && q[1].r < 60, "band 2 should be green: \(q[1])")
        #expect(q[2].b > 200 && q[2].r < 60, "band 3 should be blue: \(q[2])")
        #expect(q[3].r > 200 && q[3].g > 200 && q[3].b > 200, "band 4 should be white: \(q[3])")
    }

    /// Contained, all four bands are still there, squeezed into a band a quarter
    /// of the height, with the backdrop showing above and below it.
    @Test(.enabled(if: Snapshot.hasMetal))
    func containKeepsEveryBandAndLeavesTheBoxShowing() throws {
        let frame = try #require(render(.contain))
        let q = quarters(frame, row: 0.5)
        #expect(q[0].r > 200 && q[1].g > 200 && q[2].b > 200 && q[3].r > 200,
                "the whole picture should still be there: \(q)")
        // The backdrop is 0x304050, so a bar reads dark and blue-ish.
        let bar = patch(frame, x0: 0.3, x1: 0.7, y0: 0.05, y1: 0.15, channel: 2)
        let barRed = patch(frame, x0: 0.3, x1: 0.7, y0: 0.05, y1: 0.15, channel: 0)
        #expect(bar > 60 && bar < 110, "the top bar should be the backdrop: \(bar)")
        #expect(barRed < 70, "and not the picture: \(barRed)")
    }

    /// Covered, the square is filled edge to edge and the picture pays for it:
    /// only the middle quarter of it is read, which is the right half of the
    /// green band and the left half of the blue one.
    @Test(.enabled(if: Snapshot.hasMetal))
    func coverFillsTheSquareAndCropsToTheMiddle() throws {
        let frame = try #require(render(.cover))
        let left = patch(frame, x0: 0.1, x1: 0.4, y0: 0.1, y1: 0.9, channel: 1)
        let leftRed = patch(frame, x0: 0.1, x1: 0.4, y0: 0.1, y1: 0.9, channel: 0)
        let right = patch(frame, x0: 0.6, x1: 0.9, y0: 0.1, y1: 0.9, channel: 2)
        let rightRed = patch(frame, x0: 0.6, x1: 0.9, y0: 0.1, y1: 0.9, channel: 0)
        #expect(left > 200 && leftRed < 60, "the left half should be green: \(left), \(leftRed)")
        #expect(right > 200 && rightRed < 60, "the right half should be blue: \(right), \(rightRed)")
        // Nothing of the backdrop survives: the picture reaches every corner.
        let corner = patch(frame, x0: 0.0, x1: 0.05, y0: 0.0, y1: 0.05, channel: 1)
        #expect(corner > 200, "a corner should be picture, not backdrop: \(corner)")
    }
}
