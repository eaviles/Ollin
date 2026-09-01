// figure: frame=100 probe
//
// Guide diagram (Chapter 23): half a million blades of grass a mesh pipeline
// grows inside the draw call, individually curved and tinted, receiving the
// boulders' cast shadows, with no geometry buffers anywhere.
import Ollin

final class GrassMeadow_Figure: Sketch {
    override var canvasSize: CanvasSize { .size(1180, 540) }

    private var meadow = StrandField(width: 90, depth: 90, count: 500_000)

    override func setup() {
        meadow.bladeHeight = 0.7
        meadow.heightVariance = 0.45
        meadow.bladeWidth = 0.045
        meadow.lean = 0.34
        meadow.swayAmplitude = 0.14
        meadow.swayFrequency = 1.9
        meadow.lowColor = Color(hue: 0.31, saturation: 0.6, brightness: 0.18)
        meadow.tipColor = Color(hue: 0.24, saturation: 0.52, brightness: 0.66)
        meadow.detailNear = 10
        meadow.detailFar = 42
    }

    override func draw() {
        background(Color(hex: 0x11141B))
        let t = time * 0.04
        let eye = Vector3(cos(t * .tau) * 26, 2.6, sin(t * .tau) * 26)
        let ahead = Vector3(cos(t * .tau + 0.16) * 24, 0.9, sin(t * .tau + 0.16) * 24)
        camera(Camera3D(eye: eye, target: ahead, far: 80))
        ambientLight(Color(white: 0.15))
        directionalLight(Color(hue: 0.1, saturation: 0.25, brightness: 1.0),
                         direction: Vector3(-0.5, -0.75, -0.4), intensity: 1.0)
        directionalLight(Color(white: 0.4), direction: Vector3(0.55, 0.3, 0.5), intensity: 0.25,
                         castsShadow: false)   // a fill, so one shadow and one pass
        castShadows()
        fog(Color(hex: 0x11141B), density: 0.03)
        withState {
            fill(Color(hue: 0.29, saturation: 0.35, brightness: 0.16))
            specular(0.03)
            drawPlane(width: 200, depth: 200)
        }
        specular(0.1)
        specularSharpness(20)
        for i in 0 ..< 7 {
            withState {
                let a = Double(i) / 7 * .tau + 0.4
                let r = 8.0 + Double(i % 3) * 7.5
                translate(cos(a) * r, 0.55, sin(a) * r)
                rotateY(Double(i) * 1.3)
                scale(1 + Double(i % 3) * 0.6, 0.75, 1.2)
                fill(Color(hue: 0.09, saturation: 0.1, brightness: 0.5))
                drawSphere(radius: 0.9)
            }
        }
        drawStrands(meadow)
    }
}
