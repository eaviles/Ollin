// figure: frame=0
//
// Guide figure (Chapter 22): the Hopf fibration. A sphere's worth of circles, no two of
// which meet, colored by where on the sphere each one came from, with the straight one
// standing through the middle.
import Ollin

final class HopfFibration: Sketch {
    override var canvasSize: CanvasSize { .size(880, 540) }

    override func draw() {
        background(Color(hex: 0x05070C))
        camera(.perspective(eye: Vector3(3.5, 2.6, 4.7), target: .zero,
                            fieldOfView: .pi / 3.6))

        let bases = hopfBases(latitudes: 4, perCircle: 15, spanning: -0.3 ... 0.92)
            + [Vector3(0, -1, 0)]
        for fiber in hopfFibers(over: bases, segments: 190, reach: 3.1) {
            fill(color(for: fiber.base))
            drawTube(fiber.points, radius: 0.022, sides: 7, closed: !fiber.isStraight)
        }
    }

    /// Hue around the sphere, lightness up it, so the tangle reads as a picture of a
    /// sphere rather than as a rainbow handed out in draw order.
    private func color(for base: Vector3) -> Color {
        let around = (atan2(base.z, base.x) / .tau + 1).truncatingRemainder(dividingBy: 1)
        let up = (base.y + 1) / 2
        return Color(hue: around, saturation: 0.42 + (1 - up) * 0.46,
                     brightness: 0.58 + up * 0.42)
    }
}
