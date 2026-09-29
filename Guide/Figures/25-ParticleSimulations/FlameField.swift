// figure: frame=180
//
// Guide figure (Chapter 25): the grains' kind of step, run once per cell of a
// texture instead of once per particle. The rule is a flame: the two bottom
// rows get fresh heat each step, in blocks of eight cells that are hot or cold
// at random, and every other cell takes the average of the cells just below
// it, less a little. Heat lives in the red channel; green and blue are worked
// out from it, so the field reads red, then orange, then white where it is
// hottest. Frame 180 at two steps a frame is well past the 240 rows it takes
// the heat to climb the field, so the flame has settled into its steady shape.
import Ollin

final class FlameField: Sketch {
    @Param("Cooling", 0.0...0.02) var cooling = 0.004

    lazy var flame = Simulation(width: 240, height: 240, substeps: 2, step: """
        float h;
        if (gid.y >= size.y - 2) {
            h = step(0.45, hash12(float2(floor(float(gid.x) / 8.0), float(u.frameCount))));
        } else {
            h = (tap(-1, 1).r + tap(0, 1).r + tap(1, 1).r + tap(0, 2).r) * 0.25;
            h = max(h - custom.x, 0.0);
        }
        result = float4(h, h * h, h * h * h * h, 1.0);
    """)

    override func draw() {
        background(.black)
        stepSimulation(flame, custom: SIMD4<Float>(Float(cooling), 0, 0, 0))
        drawImage(flame.image, in: Rectangle(x: 0, y: 0, width: width, height: height))
    }
}
