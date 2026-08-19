// figure: frame=200
//
// Guide diagram (Chapter 19): the same Lorenz field twice. On the left, one
// orbit integrated once and drawn as the thin curve it is. On the right, the
// field under 600,000 particles stepped every frame, where the shape arrives
// as material and its density is the attractor's own.
import Ollin

final class AttractorFlow_Figure: Sketch {
    override var canvasSize: CanvasSize { .size(1180, 540) }

    var curve = PointCloud()
    var flow: AttractorFlow!

    override func setup() {
        flow = attractorFlow(count: 600_000, .lorenz(), seed: 11)
        flow.size = flow.extent / 190

        // The single orbit, moved to sit beside the flow. A cloud drawn from the
        // CPU takes the 3D transform stack; the flow's positions are the GPU's own
        // and stay where the equations put them.
        let path = AttractorSystem.lorenz().attractor.orbit(count: 200_000, settle: 2000)
        curve = PointCloud(positions: path, color: Color(white: 1, alpha: 0.34),
                           size: flow.extent / 190)
    }

    override func draw() {
        background(Color(hex: 0x05070C))
        blendMode(.add)
        toneMap(.aces)
        camera(.orbiting(target: Vector3(flow.center.x - flow.extent * 1.25,
                                         flow.center.y, flow.center.z),
                         radius: flow.extent * 5.2, azimuth: 0.42, elevation: 0.14,
                         fieldOfView: .pi / 4))

        withState {
            translate(-flow.extent * 2.5, 0, 0)
            drawPointCloud(curve)
        }
        updateAttractorFlow(flow)
        drawParticles(flow)
    }
}
