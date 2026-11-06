import Ollin

/// SecondView: one piece in two windows. The sketch's own window is the
/// stage, a few blocks under a lamp seen from the house. A second window,
/// "Plan", is the floor from above with the lamp marked on it: a layer the
/// sketch draws in the same `draw()`, which `makeWindow(showing:title:)`
/// gives a window of its own. Press and drag in the plan to move the lamp
/// and the stage follows, since both pictures are drawn from one state.
/// Drag either window to another display and make it full screen to put
/// that view on a projector.
///
/// ```sh
/// swift run Example-Installation-SecondView
/// ```
///
/// The plan is drawn flat, with 2D shapes: a frame has one 3D camera, and
/// the stage uses it. In an export only the stage is written: no second
/// window opens, and the lamp stays where the sketch starts it.
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

    /// A place on the floor as a place on the plan, in the layer's points.
    private func onPlan(_ p: Vector2) -> Vector2 {
        Vector2((p.x / floorSpan + 0.5) * Double(plan.width), (p.y / floorSpan + 0.5) * Double(plan.height))
    }

    override func draw() {
        // A press in the plan puts the lamp there: the plan's pointer is in the
        // layer's own points, and the layer shows the floor edge to edge.
        if planWindow.mouseIsPressed {
            lamp = Vector2((planWindow.mouseX / Double(plan.width) - 0.5) * floorSpan,
                           (planWindow.mouseY / Double(plan.height) - 0.5) * floorSpan)
        }

        // The stage, from the house.
        background(Color(white: 0.06))
        ambientLight(Color(white: 0.18))
        pointLight(Color(red: 1, green: 0.9, blue: 0.75), at: Vector3(lamp.x, lampHeight, lamp.y),
                   intensity: 6)
        camera(.perspective(eye: Vector3(0, 3.2, 8.5), target: Vector3(0, 0.6, 0), fieldOfView: .pi / 4))
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

        // The plan, from above: the same blocks as squares, and the lamp.
        withTarget(plan) {
            background(Color(white: 0.1))
            let unit = Double(plan.width) / floorSpan
            noStroke()
            let mark = onPlan(lamp)
            // The lamp's reach on the floor, under the blocks.
            fill(Color(red: 1, green: 0.9, blue: 0.75, alpha: 0.12))
            drawCircle(center: mark, radius: lampHeight * unit)
            for i in 0 ..< blocks {
                let placed = placement(i)
                fill(placed.color)
                drawRect(center: onPlan(placed.at), width: 0.8 * unit, height: 0.8 * unit)
            }
            // The lamp itself, on top.
            noFill()
            stroke(.white)
            strokeWeight(2)
            drawCircle(center: mark, radius: 10)
            drawLine(mark.x - 16, mark.y, mark.x + 16, mark.y)
            drawLine(mark.x, mark.y - 16, mark.x, mark.y + 16)
        }
    }
}
