import Foundation
import simd
import Ollin
import OllinPhone

/// The words the phone can read, standing in the room where they really are. The
/// capture app reads the text in front of the rear camera on-device and lifts each
/// line's corners to metric 3D through the LiDAR depth, so a book's spine, a
/// poster, or a sign hangs here as a framed panel of glowing wire type, facing the
/// way it faces in the room. Point the phone at another sign and it joins the
/// scene; on a phone with no LiDAR the same stream arrives flat and draws as a 2D
/// overlay instead.
///
/// Setup: build + run the Ollin capture app (Apps/OllinPhoneApp) on the iPhone,
/// choose **Text**, connect the cable, and aim the rear camera at anything
/// readable. Reading is steadiest a meter or two from large, well-lit text.
@main
final class PhoneWorldText: Sketch {

    let device = PhoneDevice()

    /// Where the orbit looks, eased frame-to-frame so live noise doesn't jitter it.
    var orbitCenter: Vector3?

    /// The wire type of each distinct string, built once: the stroke-font
    /// contours normalized to a unit-width, y-up box centered on the origin, so
    /// drawing a line is just scaling them by its real width in meters.
    var typeCache: [String: WireType] = [:]

    struct WireType {
        var polylines: [(points: [Vector2], closed: Bool)]
        var height: Double
    }

    let inkColor = Color(hex: 0xFFC46B)        // the letters
    let frameColor = Color(hex: 0x5E708F)      // the panel around them

    override func setup() {
        device.start()
    }

    override func draw() {
        background(Color(white: 0.05))

        let lines = device.latestTexts
        guard !lines.isEmpty else {
            var text = device.waitingMessage + "\n\n" +
                "Run the Ollin capture app on the iPhone in Text mode,\n" +
                "connect the cable, and aim the rear camera at a sign or a page."
            if let m = device.latestMotion {
                text += String(format: "\n\nmotion live · gravity (% .2f, % .2f, % .2f)",
                               m.gravity.x, m.gravity.y, m.gravity.z)
            }
            return drawStatus(text, style: .info)
        }

        let placed = lines.filter { $0.worldTransform != nil }
        if placed.isEmpty {
            drawFlatLines(lines)
        } else {
            drawPlacedLines(placed)
        }
        drawCaption(caption(for: lines, placed: !placed.isEmpty))
    }

    // MARK: The room (a LiDAR phone)

    private func drawPlacedLines(_ lines: [PhoneText]) {
        // Aim at the middle of everything readable, and step back far enough to
        // hold the whole spread of signs in frame.
        var center = Vector3.zero
        for line in lines { center += line.worldCenter }
        center /= Double(lines.count)
        if let c = orbitCenter { orbitCenter = c.lerp(to: center, 0.1) } else { orbitCenter = center }
        let spread = lines.map { $0.worldCenter.distance(to: center) }.max() ?? 0
        cameraShowcase(.turntable(period: .tau / 0.3), target: orbitCenter ?? center,
                       radius: 1.2 + spread * 1.6, elevation: 0.12, fieldOfView: .pi / 3)
        environment(.studio.intensified(to: 0.9))

        for line in lines {
            guard let placement = line.worldTransform else { continue }
            let width = max(0.05, line.worldWidth)
            let height = max(0.02, line.worldHeight)
            let type = wireType(of: line.text)
            withState {
                transform(placement)
                material(.clay)
                // The panel: the line's real quad, framed so it reads as a
                // surface even edge on.
                fill(frameColor)
                drawTube([Vector3(-width / 2, -height / 2, 0), Vector3(width / 2, -height / 2, 0),
                          Vector3(width / 2, height / 2, 0), Vector3(-width / 2, height / 2, 0)],
                         radius: max(0.003, width * 0.01), sides: 5, closed: true)
                // The words: stroke-font contours scaled to the panel's width and
                // floated a touch off the surface so they never z-fight it.
                fill(inkColor)
                let radius = max(0.0025, width * 0.014)
                for polyline in type.polylines {
                    let path = polyline.points.map {
                        Vector3($0.x * width, $0.y * width, 0.01)
                    }
                    drawTube(path, radius: radius, sides: 6, closed: polyline.closed)
                }
            }
        }
    }

    // MARK: The flat overlay (no LiDAR to lift through)

    private func drawFlatLines(_ lines: [PhoneText]) {
        textSize(26)
        for line in lines {
            withState {
                stroke(frameColor)
                strokeWeight(3)
                noFill()
                drawPolygon(line.corners(in: bounds))
                noStroke()
                fill(inkColor)
                let box = line.bounds(in: bounds)
                drawText(line.text, box.x, box.y - 8)
            }
        }
    }

    // MARK: The wire type

    /// The stroke-font geometry of one string, cached by the string: contours in
    /// a unit-width, y-up box centered on the origin. The bundled vector font is
    /// open strokes, which is exactly what a tube wants.
    private func wireType(of text: String) -> WireType {
        if let hit = typeCache[text] { return hit }
        textSize(120)
        var polylines: [(points: [Vector2], closed: Bool)] = []
        var minX = Double.infinity, minY = Double.infinity
        var maxX = -Double.infinity, maxY = -Double.infinity
        for shape in textToShapes(text, 0, 0) {
            for contour in shape.contours where contour.points.count >= 2 {
                polylines.append((contour.points, contour.isClosed))
                for p in contour.points {
                    minX = min(minX, p.x); maxX = max(maxX, p.x)
                    minY = min(minY, p.y); maxY = max(maxY, p.y)
                }
            }
        }
        guard maxX > minX else {
            let empty = WireType(polylines: [], height: 0)
            typeCache[text] = empty
            return empty
        }
        // Normalize: origin at the center, width 1, canvas y (down) flipped to
        // world y (up), the aspect kept by sharing one scale.
        let s = 1 / (maxX - minX)
        let cx = (minX + maxX) / 2, cy = (minY + maxY) / 2
        let normalized = polylines.map { polyline in
            (points: polyline.points.map { Vector2(($0.x - cx) * s, (cy - $0.y) * s) },
             closed: polyline.closed)
        }
        let type = WireType(polylines: normalized, height: (maxY - minY) * s)
        typeCache[text] = type
        return type
    }

    private func caption(for lines: [PhoneText], placed: Bool) -> String {
        var parts = ["PhoneWorldText, \(lines.count) \(lines.count == 1 ? "line" : "lines") · \(placed ? "3D" : "2D, no LiDAR")"]
        if let biggest = device.latestText {
            parts.append("“\(String(biggest.text.prefix(28)))”")
        }
        return parts.joined(separator: " · ")
    }
}
