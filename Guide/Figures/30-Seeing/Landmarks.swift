// figure: frame=0 themed
//
// Guide diagram (Chapter 30): what the three body-reading trackers report.
// A hand is 21 named joints, a face is 76 landmark points grouped in named
// regions, a body is 19 named joints. The joint positions here are drawn by
// hand for the diagram, but the connections come straight from the API:
// Finger.chain wires the hand, Body.skeleton wires the body.
import Ollin
import OllinDiagram
import OllinVision

final class Landmarks: Sketch {
    override var canvasSize: CanvasSize { .size(880, 550) }

    @Param var darkTheme = false
    var theme: DiagramTheme { DiagramTheme(dark: darkTheme) }

    var paper: Color { theme.paper }
    var ink: Color { theme.ink }
    var faint: Color { theme.ink(0.28) }
    var soft: Color { theme.ink(0.6) }
    var accent: Color { theme.accent }

    override func draw() {
        background(paper)
        textSize(19)

        drawHandPanel(origin: Vector2(45, 105))
        drawFacePanel(origin: Vector2(330, 105))
        drawBodyPanel(origin: Vector2(615, 105))

        noStroke()
        fill(soft)
        textAlign(.center, .top)
        drawText("every joint is asked for by name, and mapped into the frame's rectangle",
                 width / 2, 512)
    }

    // MARK: Hand (21 joints, wired by Finger.chain)

    func drawHandPanel(origin: Vector2) {
        let joints: [HandJoint: Vector2] = [
            .wrist: Vector2(118, 268),
            .thumbCMC: Vector2(78, 235), .thumbMP: Vector2(50, 200),
            .thumbIP: Vector2(33, 172), .thumbTip: Vector2(20, 146),
            .indexMCP: Vector2(88, 150), .indexPIP: Vector2(80, 108),
            .indexDIP: Vector2(76, 78), .indexTip: Vector2(72, 50),
            .middleMCP: Vector2(118, 142), .middlePIP: Vector2(118, 95),
            .middleDIP: Vector2(118, 62), .middleTip: Vector2(118, 32),
            .ringMCP: Vector2(147, 150), .ringPIP: Vector2(154, 108),
            .ringDIP: Vector2(158, 78), .ringTip: Vector2(162, 52),
            .littleMCP: Vector2(172, 165), .littlePIP: Vector2(186, 133),
            .littleDIP: Vector2(194, 110), .littleTip: Vector2(201, 88),
        ]
        stroke(faint)
        strokeWeight(2.5)
        for finger in Finger.allCases {
            let chain = finger.chain.compactMap { joints[$0] }
            drawPolyline(chain.map { origin + $0 })
        }
        noStroke()
        fill(ink)
        for (_, p) in joints { drawCircle(origin.x + p.x, origin.y + p.y, 4.5) }

        label(".wrist", at: origin + Vector2(118, 268), dx: 14, dy: 4)
        label(".indexTip", at: origin + Vector2(72, 50), dx: -8, dy: -22)
        label(".thumbTip", at: origin + Vector2(20, 146), dx: -6, dy: 18)
        caption("Hand: 21 joints", x: origin.x + 115)
    }

    // MARK: Face (76 points in named regions)

    func drawFacePanel(origin: Vector2) {
        // The jawline (the .faceContour region), ear to ear.
        let contour: [Vector2] = [
            Vector2(35, 95), Vector2(38, 130), Vector2(45, 165), Vector2(57, 198),
            Vector2(75, 226), Vector2(98, 246), Vector2(122, 252), Vector2(146, 246),
            Vector2(169, 226), Vector2(187, 198), Vector2(199, 165), Vector2(206, 130),
            Vector2(209, 95),
        ]
        // Brows, eyes, nose, and lips, each its own region of points.
        let leftBrow: [Vector2] = [Vector2(55, 88), Vector2(72, 78), Vector2(92, 76), Vector2(110, 82)]
        let rightBrow: [Vector2] = [Vector2(134, 82), Vector2(152, 76), Vector2(172, 78), Vector2(189, 88)]
        let leftEye: [Vector2] = [Vector2(66, 110), Vector2(80, 102), Vector2(96, 104),
                                  Vector2(104, 114), Vector2(88, 120), Vector2(72, 118)]
        let rightEye: [Vector2] = [Vector2(140, 114), Vector2(148, 104), Vector2(164, 102),
                                   Vector2(178, 110), Vector2(172, 118), Vector2(156, 120)]
        let nose: [Vector2] = [Vector2(122, 108), Vector2(120, 135), Vector2(112, 158),
                               Vector2(122, 165), Vector2(132, 158)]
        let outerLips: [Vector2] = [Vector2(88, 200), Vector2(104, 192), Vector2(122, 190),
                                    Vector2(140, 192), Vector2(156, 200), Vector2(140, 214),
                                    Vector2(122, 218), Vector2(104, 214)]

        stroke(faint)
        strokeWeight(2.5)
        drawPolyline(contour.map { origin + $0 })
        for region in [leftBrow, rightBrow, nose] {
            drawPolyline(region.map { origin + $0 })
        }
        for loop in [leftEye, rightEye, outerLips] {
            var closed = loop.map { origin + $0 }
            closed.append(closed[0])
            drawPolyline(closed)
        }

        noStroke()
        fill(ink)
        for region in [contour, leftBrow, rightBrow, leftEye, rightEye, nose, outerLips] {
            for p in region { drawCircle(origin.x + p.x, origin.y + p.y, 3.5) }
        }
        fill(accent)
        drawCircle(origin.x + 85, origin.y + 111, 4)      // the pupils
        drawCircle(origin.x + 159, origin.y + 111, 4)

        label(".faceContour", at: origin + Vector2(45, 165), dx: -12, dy: 22, alignRight: true)
        label(".leftPupil", at: origin + Vector2(85, 111), dx: -6, dy: 16, alignRight: true)
        label(".outerLips", at: origin + Vector2(156, 200), dx: 12, dy: 6)
        caption("Face: 76 points, in regions", x: origin.x + 122)
    }

    // MARK: Body (19 joints, wired by Body.skeleton)

    func drawBodyPanel(origin: Vector2) {
        let joints: [BodyJoint: Vector2] = [
            .nose: Vector2(110, 36), .leftEye: Vector2(120, 30), .rightEye: Vector2(100, 30),
            .leftEar: Vector2(130, 36), .rightEar: Vector2(90, 36),
            .neck: Vector2(110, 62),
            .leftShoulder: Vector2(140, 74), .rightShoulder: Vector2(80, 74),
            .leftElbow: Vector2(156, 118), .rightElbow: Vector2(64, 118),
            .leftWrist: Vector2(168, 160), .rightWrist: Vector2(52, 160),
            .root: Vector2(110, 148),
            .leftHip: Vector2(128, 152), .rightHip: Vector2(92, 152),
            .leftKnee: Vector2(132, 205), .rightKnee: Vector2(88, 205),
            .leftAnkle: Vector2(134, 258), .rightAnkle: Vector2(86, 258),
        ]
        stroke(faint)
        strokeWeight(2.5)
        for (a, b) in Body.skeleton {
            if let pa = joints[a], let pb = joints[b] {
                drawLine(origin + pa, origin + pb)
            }
        }
        noStroke()
        fill(ink)
        for (_, p) in joints { drawCircle(origin.x + p.x, origin.y + p.y, 4.5) }

        label(".neck", at: origin + Vector2(110, 62), dx: 14, dy: -6)
        label(".root", at: origin + Vector2(110, 148), dx: 14, dy: 8)
        label(".leftWrist", at: origin + Vector2(168, 160), dx: -2, dy: 20, alignRight: true)
        caption("Body: 19 joints", x: origin.x + 110)
    }

    // MARK: Shared bits

    func label(_ text: String, at p: Vector2, dx: Double, dy: Double, alignRight: Bool = false) {
        noStroke()
        fill(accent)
        textSize(15)
        textAlign(alignRight ? .right : .left, .top)
        drawText(text, p.x + dx, p.y + dy)
        textSize(19)
    }

    func caption(_ text: String, x: Double) {
        noStroke()
        fill(ink)
        textAlign(.center, .top)
        drawText(text, x, 400)
    }
}
