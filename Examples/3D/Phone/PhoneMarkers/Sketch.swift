import Foundation
import simd
import Ollin
import OllinPhone

/// A sketch that lives on a printed picture. The capture app holds a small library
/// of reference pictures and scanned objects, finds them in the room on its own
/// Neural Engine, and sends where each one stands. Here every picture it finds
/// becomes a stage: a city of columns rises off the paper, breathing on a slow
/// wave, framed by the print's own edge. A scanned object arrives as the box its
/// scan measured, drawn as a cage around the real thing.
///
/// Setup: build + run the Ollin capture app (Apps/OllinPhoneApp) on the iPhone,
/// choose **Markers**, and drop a picture into its folder (connect the cable, open
/// the phone in Finder, Files, then Ollin Capture). Name the file with the width you
/// printed it at, like `poster@30cm.png`, so the room's measurements are right. A
/// picture with plenty of detail is found from further away than a flat one.
@main
final class PhoneMarkers: Sketch {

    let device = PhoneDevice()

    /// How tall the tallest column stands, as a share of the print's width.
    @Param(0...0.6) var relief = 0.28

    /// How many columns run across the print. The other way follows the shape.
    @Param(4...24) var columns = 12

    /// How fast the wave under the columns travels.
    @Param(0...2) var speed = 0.45

    /// Where the orbit looks, eased frame to frame so live noise does not jitter it.
    var orbitCenter: Vector3?

    let stageColor = Color(hex: 0x1A1E2B)
    let towerColor = Color(hex: 0x6FD6C4)
    let frameColor = Color(hex: 0xFFB347)
    let cageColor = Color(hex: 0xC98BFF)

    override func setup() {
        device.start()
    }

    override func draw() {
        background(Color(white: 0.05))

        let markers = device.latestMarkers
        guard !markers.isEmpty else { return drawWaiting() }

        aimAt(markers)
        environment(.studio.intensity(0.9))

        for marker in markers {
            if marker.isObject {
                drawCage(marker)
            } else if marker.isTracked {
                drawCity(on: marker)
            } else {
                drawOutline(marker, color: frameColor.withAlpha(0.25))
            }
        }
        drawCaption(caption(for: markers))
    }

    // MARK: The picture as a stage

    private func drawCity(on marker: PhoneMarker) {
        let width = marker.width, height = marker.height
        withState {
            transform(marker.placement)
            material(.clay)

            // The print itself, as a floor to build on.
            fill(stageColor)
            drawBox(width: width, height: height, depth: max(0.001, width * 0.004))

            // The columns: a grid across the print, each riding a wave that travels
            // over it. Heights are a share of the print's width, so a business card
            // and a poster carry the same city at their own scale.
            let across = max(2, columns)
            let down = max(2, Int((Double(across) * height / max(width, 1e-6)).rounded()))
            let cell = width / Double(across)
            let side = cell * 0.55
            fill(towerColor)
            for row in 0..<down {
                for column in 0..<across {
                    let x = (Double(column) + 0.5) / Double(across) - 0.5
                    let y = (Double(row) + 0.5) / Double(down) - 0.5
                    let wave = noise(Double(column) * 0.35, Double(row) * 0.35, time * speed)
                    let tall = width * relief * (0.15 + wave * wave)
                    withState {
                        translate(x * width, y * height, tall / 2)
                        drawBox(width: side, height: side, depth: tall)
                    }
                }
            }
        }
        drawOutline(marker, color: frameColor)
    }

    /// The print's own edge, as a thin frame standing just off the paper.
    private func drawOutline(_ marker: PhoneMarker, color: Color) {
        let corners = marker.corners.map { $0 + marker.facing * 0.002 }
        guard corners.count == 4 else { return }
        withState {
            fill(color)
            material(.clay)
            drawTube(corners, radius: max(0.002, marker.width * 0.012), sides: 6, closed: true)
        }
    }

    // MARK: A scanned object as a cage

    private func drawCage(_ marker: PhoneMarker) {
        withState {
            transform(marker.placement)
            fill(cageColor)
            material(.clay)
            let w = marker.width / 2, h = marker.height / 2, d = marker.depth / 2
            let radius = max(0.002, min(marker.width, marker.height) * 0.03)
            // The twelve edges of the box, as four rings and four uprights.
            for level in [-h, h] {
                drawTube([Vector3(-w, level, -d), Vector3(w, level, -d),
                          Vector3(w, level, d), Vector3(-w, level, d)],
                         radius: radius, sides: 5, closed: true)
            }
            for x in [-w, w] {
                for z in [-d, d] {
                    drawTube([Vector3(x, -h, z), Vector3(x, h, z)], radius: radius, sides: 5)
                }
            }
        }
    }

    // MARK: The room

    private func aimAt(_ markers: [PhoneMarker]) {
        var center = Vector3.zero
        for marker in markers { center += marker.position }
        center /= Double(markers.count)
        if let held = orbitCenter { orbitCenter = held.lerp(to: center, 0.1) } else { orbitCenter = center }
        let target = orbitCenter ?? center
        let spread = markers.map { $0.position.distance(to: center) }.max() ?? 0
        let size = markers.map(\.width).max() ?? 0.3
        cameraShowcase(.turntable(period: .tau / 0.25), target: target,
                       radius: size * 2.2 + spread * 1.6, elevation: 0.35, fieldOfView: .pi / 3)
    }

    private func drawWaiting() {
        // While the stream is alive the empty set means the phone is looking and
        // has found nothing, which is a different thing to say than "connecting".
        var text = device.isStreaming
            ? "Connected. Nothing it knows is in view.\n\n" +
              "Choose Markers on the phone, drop a picture into its folder,\n" +
              "and point the rear camera at the print."
            : device.waitingMessage + "\n\n" +
              "Run the Ollin capture app on the iPhone in Markers mode,\n" +
              "drop a picture into its folder, and point the rear camera at the print."
        if let motion = device.latestMotion {
            text += String(format: "\n\nmotion live · gravity (% .2f, % .2f, % .2f)",
                           motion.gravity.x, motion.gravity.y, motion.gravity.z)
        }
        drawStatus(text, style: .info)
    }

    private func caption(for markers: [PhoneMarker]) -> String {
        let following = markers.filter(\.isTracked)
        var parts = ["PhoneMarkers, \(markers.count) known · \(following.count) in view"]
        if let biggest = device.latestMarker {
            parts.append(String(format: "%@ · %.0f cm wide", biggest.name, biggest.width * 100))
        }
        return parts.joined(separator: " · ")
    }
}
