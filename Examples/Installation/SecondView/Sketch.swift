import Ollin

/// SecondView: one stage in two windows, seen from two places. The sketch's
/// own window is the stage from the house, a few blocks under a lamp. A second
/// window, "Plan", is the same stage from straight above: a layer the sketch
/// draws in the same `draw()` through a camera of its own, which
/// `makeWindow(showing:title:)` gives a window. Press and drag in the plan to
/// move the lamp and the stage follows, since both pictures are one world.
/// Drag either window to another display and make it full screen to put
/// that view on a projector.
///
/// ```sh
/// swift run Example-Installation-SecondView
/// ```
///
/// A camera set inside a layer's block belongs to that layer, so the plan
/// looks down while the stage looks across. Inside the block the sketch's
/// questions about the camera are about the plan's: `cameraRay(through:)`
/// turns the plan window's pointer into a ray down to the floor, and
/// `project(_:)` puts the lamp's mark over the place it stands. In an export
/// only the stage is written: no second window opens, and the lamp stays
/// where the sketch starts it.
@main
final class SecondView: Sketch {
    override var canvasSize: CanvasSize { .size(1280, 720) }

    @Param("Blocks", 3 ... 12, icon: "square.stack.3d.up") var blocks = 7
    @Param("Lamp height", 1 ... 5, icon: "lightbulb") var lampHeight = 2.6

    private var plan: RenderTarget!
    private var planWindow: SketchWindow!
    /// Where the lamp stands on the floor, in the scene's own units.
    private var lamp = Vector2(1.2, 0.6)
    /// How much of the floor the plan shows, in scene units, edge to edge.
    private let floorSpan = 9.0
    private let block = Mesh.box(width: 0.8, height: 1, depth: 0.8)
    private let floor = Mesh.plane(width: 9, depth: 9)

    /// The plan's camera: straight down at the floor, with the far side of the
    /// stage at the top of the picture, framing the floor edge to edge.
    private var fromAbove: Camera3D {
        .orthographic(eye: Vector3(0, 12, 0), target: .zero, up: Vector3(0, 0, -1), height: floorSpan)
    }

    override func setup() {
        plan = makeRenderTarget(width: 480, height: 480)
        planWindow = makeWindow(showing: plan, title: "Plan")
    }

    /// Where block `i` stands on the floor, how tall it is, and its color.
    private func placement(_ i: Int) -> (at: Vector2, tall: Double, color: Color) {
        let turn = Double(i) / Double(blocks) * .tau
        let reach = 1.6 + 1.2 * noise(Double(i) * 3.7)
        let tall = 0.5 + 1.6 * noise(Double(i) * 1.3 + 20)
        return (Vector2(cos(turn), sin(turn)) * reach, tall,
                Color(hue: Double(i) / Double(blocks), saturation: 0.55, brightness: 0.9))
    }

    /// The stage itself: the floor and the blocks. Drawn once for each view,
    /// through whichever camera the surface being drawn has.
    private func drawStage() {
        material(.matte)
        fill(Color(white: 0.55))
        drawMesh(floor)
        for i in 0 ..< blocks {
            let placed = placement(i)
            fill(placed.color)
            withState {
                translate(placed.at.x, placed.tall / 2, placed.at.y)
                scale(1, placed.tall, 1)
                drawMesh(block)
            }
        }
    }

    override func draw() {
        background(Color(white: 0.06))

        // A press in the plan puts the lamp under the pointer. The plan's
        // pointer is in the layer's own points, and inside the layer's block
        // the ray through a point is a ray through the plan's camera, so the
        // place where that ray meets the floor is where the lamp goes.
        withTarget(plan) {
            camera(fromAbove)
            if planWindow.mouseIsPressed, let ray = cameraRay(through: planWindow.mouse),
               ray.direction.y < 0 {
                let floorHit = ray.origin + ray.direction * (-ray.origin.y / ray.direction.y)
                let half = floorSpan / 2
                lamp = Vector2(min(max(floorHit.x, -half), half), min(max(floorHit.z, -half), half))
            }
        }

        // The lights are the frame's: set once, they light both views.
        ambientLight(Color(white: 0.18))
        pointLight(Color(red: 1, green: 0.9, blue: 0.75), at: Vector3(lamp.x, lampHeight, lamp.y),
                   intensity: 6)

        // The stage, from the house.
        camera(.perspective(eye: Vector3(0, 3.2, 8.5), target: Vector3(0, 0.6, 0), fieldOfView: .pi / 4))
        drawStage()

        // The plan: the same stage through the layer's own camera, set above,
        // and the lamp marked where it stands.
        withTarget(plan) {
            background(Color(white: 0.06))
            drawStage()
            if let mark = project(Vector3(lamp.x, 0, lamp.y)) {
                noFill()
                stroke(.white)
                strokeWeight(2)
                drawCircle(center: mark, radius: 10)
                drawLine(mark.x - 16, mark.y, mark.x + 16, mark.y)
                drawLine(mark.x, mark.y - 16, mark.x, mark.y + 16)
            }
        }
    }
}
