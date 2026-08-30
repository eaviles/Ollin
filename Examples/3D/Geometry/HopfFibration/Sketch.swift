import Ollin

/// **The Hopf fibration**: a sphere's worth of circles, no two of which meet, and every two
/// of which are linked exactly once.
///
/// Take an ordinary sphere. Every single point of it stands for a whole circle living in a
/// sphere-in-four-dimensions, and those circles fill that space completely without one of
/// them ever touching another. Bring them down into three dimensions and they come out as
/// this: nested tori of interlocking rings.
///
/// The linking is the part worth staring at. Pick any two rings in the picture, however far
/// apart, and you could not pull them free of each other without cutting one. That is true
/// of every pair, all the way through.
///
/// - **rings**: circles of latitude on the sphere, so each ring of base points lifts to one
///   torus and the tori nest inside each other. This is the arrangement that reads.
/// - **spiral**: base points spread evenly over the whole sphere instead, which fills space
///   more completely and is harder to follow. Both are the same fibration.
///
/// Two details make it legible rather than a ball of wool, and neither is decoration. The
/// **color comes from the base point** on the sphere, so the tangle is visibly a picture of
/// a sphere. And the **straight one is drawn**: the base point at the far pole lifts to a
/// circle through the point the projection sends to infinity, so it comes back as a line,
/// and it is the axis every other ring is threaded onto.
///
/// Try it: pull `latitudes` down to 1 to see a single torus on its own, or slide `span` up
/// so the rings crowd toward the near pole and the tori tighten around the middle circle.
@main
final class HopfFibration_Example: Sketch {

    enum Arrangement: String, CaseIterable, ParamOption { case rings, spiral }

    @Param(style: .segmented, icon: "circle.circle") var arrangement: Arrangement = .rings
    @Param(1 ... 7, icon: "circle.hexagonpath") var latitudes = 4
    @Param(6 ... 40, icon: "circle.grid.cross") var perCircle = 16
    @Param(30 ... 400, icon: "point.3.connected.trianglepath.dotted") var spiralCount = 120
    @Param(-0.9 ... 0.6, icon: "arrow.up.and.down") var span = -0.3
    @Param(0.004 ... 0.05, icon: "scribble") var thickness = 0.018

    override func draw() {
        background(Color(hex: 0x05070C))
        cameraShowcase(.orbitAndRise(period: 26, rise: 0.45, in: 14),
                       radius: 7.2, elevation: 0.28, fieldOfView: .pi / 3.6)

        // The far pole is added by hand to the rings, because `spanning` deliberately keeps
        // clear of it: its circle runs through the point the projection sends to infinity
        // and comes back as the straight axis. The spiral already reaches it on its own.
        let bases = arrangement == .rings
            ? hopfBases(latitudes: latitudes, perCircle: perCircle, spanning: span ... 0.92)
                + [Vector3(0, -1, 0)]
            : hopfBases(spiralCount: spiralCount)

        for fiber in hopfFibers(over: bases, segments: 200, reach: 6) {
            fill(color(for: fiber.base))
            drawTube(fiber.points, radius: thickness, sides: 7, closed: !fiber.isStraight)
        }
    }

    /// The color a fiber wears, taken from where on the sphere it came from: the angle
    /// around gives the hue, and the height gives how pale it is. Reading the color off the
    /// base point rather than off a counter is what shows that the whole tangle is one
    /// sphere seen from the inside.
    private func color(for base: Vector3) -> Color {
        let around = (atan2(base.z, base.x) / .tau + 1).truncatingRemainder(dividingBy: 1)
        let up = (base.y + 1) / 2
        return Color(hue: around, saturation: 0.42 + (1 - up) * 0.48,
                     brightness: 0.55 + up * 0.45)
    }
}
