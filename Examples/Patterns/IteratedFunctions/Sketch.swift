import Ollin

/// The chaos game condensing onto three classic attractors.
///
/// An iterated function system is a handful of affine maps; play them at
/// random and every orbit falls onto their common attractor. This sketch
/// never clears: each frame drops another few thousand visits onto the
/// accumulation surface, so the fern (or triangle, or carpet) literally
/// condenses out of the noise. Click or press a key to switch systems.
@main
final class IteratedFunctions: Sketch {
    private let systems: [(name: String, system: IFS, flipped: Bool)] = [
        ("the fern", .barnsleyFern, true),
        ("the triangle", .sierpinskiTriangle, true),
        ("the carpet", .sierpinskiCarpet, false),
    ]
    private var index = 0
    private var frame: Rectangle { canvasRectangle.inset(by: 90) }

    override func setup() {
        noClear()
        background(Color(hex: 0x101318))
    }

    override func draw() {
        let entry = systems[index]
        var cloud = ifsPoints(entry.system, count: 3_000)
        if entry.flipped {
            // These systems grow upward in their own coordinates; the canvas
            // y axis grows downward.
            cloud = cloud.map { Vector2($0.x, -$0.y) }
        }
        fill(Color(hex: 0xB8D8B8, alpha: 0.5))
        drawPoints(fitted(cloud, in: frame), size: 1.4)
        drawCaption("the chaos game condenses \(entry.name); click or press a key for the next system")
    }

    override func mousePressed() { advance() }
    override func keyPressed() { advance() }

    private func advance() {
        index = (index + 1) % systems.count
        background(Color(hex: 0x101318))
    }
}
