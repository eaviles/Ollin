import Ollin

/// `curlNoise` drawn as a flow field: at each cell of a grid, a short line points
/// along the divergence-free curl of the Perlin field, so the directions read as
/// smooth, sourceless swirls. The field drifts because it's sampled with an
/// offset that grows with `time`.
@main
final class FlowField: Sketch {
    override func setup() {
        stroke(.white)
        strokeWeight(2 * scale)
    }

    override func draw() {
        background(.black)
        let step = 35 * scale
        var y = step / 2
        while y < height {
            var x = step / 2
            while x < width {
                let flow = curlNoise(x * 0.003 + time * 0.05, y * 0.003).normalized
                let p = Vector2(x, y)
                drawLine(p, p + flow * (step * 0.45))
                x += step
            }
            y += step
        }
    }
}
