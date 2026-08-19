// figure: frame=0
//
// Guide figure (Chapter 21): 2D drawing inside a 3D depth buffer. Three pillars
// at increasing distance, each ringed by an ordinary drawCircle given that
// pillar's depth. Every ring is cut where its pillar stands in front of it, and
// every ring is the same 96-point radius on the canvas: a 2D mark keeps its
// canvas size and only gains a place in the depth test. The numbered tags ride
// the pillar tops as billboards.
import Ollin

final class DepthCompositing: Sketch {
    override var canvasSize: CanvasSize { .size(880, 550) }

    override func draw() {
        background(Color(hex: 0x0E1117))
        camera(.perspective(eye: Vector3(0, 1.9, 8.0), target: Vector3(0, 0.7, 0),
                            fieldOfView: .pi / 4.2))
        lightingPreset(.studio)

        // Three pillars marching away from the camera.
        let posts: [(x: Double, z: Double, tint: UInt32)] = [
            (x: -2.5, z: 2.2, tint: 0x4E9DE0),
            (x: 0.1, z: -0.4, tint: 0x63C4A8),
            (x: 2.7, z: -2.8, tint: 0xE0A24E),
        ]
        for post in posts {
            withState {
                translate(post.x, 0.9, post.z)
                fill(Color(hex: post.tint))
                material(.glossy)
                drawBox(width: 1.05, height: 2.6, depth: 1.05)
            }
        }

        // A flat 2D ring per pillar, given that pillar's depth. Nothing here is
        // 3D geometry: it is drawCircle, z-tested.
        for post in posts {
            let anchor = Vector3(post.x, 0.9, post.z)
            withState {
                depth(at: anchor)
                noFill()
                stroke(Color(hex: 0xF5F0E6))
                strokeWeight(7)
                if let screen = project(anchor) {
                    drawCircle(center: screen, radius: 96)
                }
            }
        }

        // Tags riding the pillar tops, anchored in the world.
        for (index, post) in posts.enumerated() {
            withBillboard(at: Vector3(post.x, 2.35, post.z)) {
                noStroke()
                fill(Color(hex: 0xF5F0E6))
                drawCircle(0, 0, 17)
                fill(Color(hex: 0x0E1117))
                textSize(20)
                textAlign(.center, .middle)
                drawText("\(index + 1)", 0, 0)
            }
        }
    }
}
