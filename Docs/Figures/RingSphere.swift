// figure: frame=119
//
// Docs figure (Drawing/DepthOfField.md): the ring sphere through a real lens,
// the scene of the `Rendering/LineSpray` example, after
// six hundred passes of the running mean. A hundred and fifty rings of latitude
// nudged by a curl field and lit from one side, with a burst of short bright
// spokes at the center, printed through `developed`.
import Ollin

final class RingSphere: Sketch {
    override var canvasSize: CanvasSize { .size(1919, 1003) }

    private var spray: LineSpray!

    override func setup() {
        seed(3)
        spray = makeLineSpray(buildScene(), sampling: .perLine(25), passesPerFrame: 5,
                              bokeh: Bokeh(focalDistance: 49.19, strength: 0.095, minSize: 0.015))
    }

    override func draw() {
        background(.black)
        camera(.orbiting(target: .zero, radius: 49,
                         azimuth: -26.57 * .pi / 180, elevation: -24.09 * .pi / 180,
                         fieldOfView: 20 * .pi / 180, near: 2, far: 200))
        drawLineSpray(spray)
        drawImage(spray.developed(exposure: 526, ground: Color(red: 21 / 255, green: 16 / 255, blue: 16 / 255)).image, 0, 0)
    }

    private func buildScene() -> [SprayLine] {
        var lines: [SprayLine] = []
        let light = Vector3(0.2, 0.35, 0.5).normalized
        for j in 0 ..< 150 {
            let latitude = Double(j) / 150 * .pi
            let ringRadius = -sin(latitude), z = cos(latitude)
            let segments = 70 + Int(abs(floor(ringRadius * 360)))
            for i in 0 ..< segments {
                let a1 = Double(i) / Double(segments) * .tau
                let a2 = Double(i + 1) / Double(segments) * .tau
                let r = random() > 0.92 ? 5.9 : 5.75
                let p1 = Vector3(cos(a1) * ringRadius * r, sin(a1) * ringRadius * r, z * r)
                let p2 = Vector3(cos(a2) * ringRadius * r, sin(a2) * ringRadius * r, z * r)
                let q1 = p1 + displacement(p1), q2 = p2 + displacement(p2)
                let diffuse = pow(max(p1.normalized.dot(light), 0), 3)
                let radiance = 0.1 * diffuse + 0.002
                lines.append(line(q1, q2, radiance))
                if random() > 0.975 {
                    let boost = random() > 0.8 ? 6.0 : 2.0
                    let inner = 0.1 + random() * 0.3
                    let outer = inner + pow(random(), 2) * 0.25
                    lines.append(line(q1 * inner, q1 * outer, boost * radiance))
                }
            }
        }
        return lines
    }

    private func displacement(_ p: Vector3) -> Vector3 {
        let strength = 0.1 + curlNoise(p * 0.15).normalized.x * 0.7
        return curlNoise(p * 0.5).normalized * strength
    }

    private func line(_ a: Vector3, _ b: Vector3, _ radiance: Double) -> SprayLine {
        SprayLine(from: a, to: b, light: SIMD3(repeating: radiance))
    }
}
