import Foundation
import Ollin
import OllinBluetooth

/// Every Bluetooth device around this Mac, drawn as a room.
///
/// This one needs no gear of your own: a phone, a watch, a pair of earphones,
/// a car, a shop's beacon, all of them announce themselves several times a
/// second, and every announcement carries a signal strength. The Mac sits at
/// the center and each device sits at the distance its signal suggests, so
/// walking across the room with a phone in your pocket moves a dot.
///
/// The distance is a guess and it says so: radio goes through a wall and
/// around a body, so a dot wanders even when nothing moves.
///
/// The first run asks for permission to use Bluetooth. Until that is answered
/// the radio says nothing at all, and the sketch draws the reason instead.
@main
final class BluetoothRoom: Sketch {

    let scan = BluetoothScan()

    /// How far a device drifts from where its signal alone would put it.
    @Param(0...1) var wander = 0.35
    /// Nearest and farthest signal the ring covers, in dBm.
    @Param(-100 ... -20) var farthest = -95.0

    override func setup() {
        scan.start()
        textFont(.systemMedium)
    }

    override func draw() {
        background(Color(white: 0.05))
        let center = Vector2(width / 2, height / 2)
        let reach = min(width, height) * 0.42

        // With no radio there is no room to draw, so the reason takes the
        // whole canvas rather than sitting on top of empty rings.
        if let reason = scan.unavailableReason {
            drawReason(reason)
            return
        }
        drawRings(around: center, reach: reach)
        drawDevices(around: center, reach: reach)
        drawCaption()
    }

    // MARK: - The room

    private func drawDevices(around center: Vector2, reach: Double) {
        let devices = scan.peripherals
        for device in devices {
            let place = position(of: device, around: center, reach: reach)
            let closeness = closeness(of: device)

            // A device is a dot with a ring of its own, brighter as it gets
            // nearer, plus its name where there is room for one.
            noStroke()
            fill(Color(hue: 0.55 - closeness * 0.45, saturation: 0.7, brightness: 0.6 + closeness * 0.4))
            drawCircle(center: place, radius: 6 + closeness * 10)

            noFill()
            stroke(Color(white: 1, alpha: 0.12 + closeness * 0.25))
            strokeWeight(1.5)
            drawCircle(center: place, radius: 16 + closeness * 26)

            noStroke()
            fill(Color(white: 0.55 + closeness * 0.4))
            textSize(15)
            drawText(device.name, place.x + 22, place.y + 5)
        }
    }

    /// Where a device sits: the distance comes from its signal, the direction
    /// from its identifier, so one device keeps its own place in the room
    /// while its distance moves.
    private func position(of device: BluetoothPeripheral, around center: Vector2, reach: Double)
        -> Vector2
    {
        let angle = Double(stableNumber(device.id.uuidString) % 3600) / 3600 * .pi * 2
        let distance = (1 - closeness(of: device)) * reach

        // Radio is not a tape measure, so the dot is allowed to breathe about
        // where the signal puts it rather than pretending to a fixed spot.
        let drift = noise(Double(stableNumber(device.id.uuidString) % 997), time * 0.2)
        let wandered = distance + (drift - 0.5) * wander * reach * 0.35
        return center + Vector2(angle: angle, length: max(20, wandered))
    }

    /// 1 for a device in your hand, 0 for one at the edge of hearing.
    private func closeness(of device: BluetoothPeripheral) -> Double {
        let nearest = -35.0
        let span = nearest - farthest
        guard span > 0 else { return 0 }
        return min(max((Double(device.signal) - farthest) / span, 0), 1)
    }

    /// A number that is the same on every run for the same text, so a device
    /// keeps its direction across restarts.
    private func stableNumber(_ text: String) -> Int {
        var value = 2_166_136_261
        for byte in text.utf8 {
            value = (value ^ Int(byte)) &* 16_777_619 & 0xFFFF_FFFF
        }
        return value
    }

    // MARK: - The room's own furniture

    private func drawRings(around center: Vector2, reach: Double) {
        noFill()
        for step in 1...4 {
            let part = Double(step) / 4
            stroke(Color(white: 1, alpha: 0.06))
            strokeWeight(1)
            drawCircle(center: center, radius: reach * part)
        }
        noStroke()
        fill(Color(white: 0.9))
        drawCircle(center: center, radius: 7)
        fill(Color(white: 0.5))
        textSize(14)
        drawText("this Mac", center.x + 16, center.y + 5)
    }

    private func drawCaption() {
        let devices = scan.peripherals
        noStroke()
        fill(Color(white: 0.8))
        textSize(22)
        drawText("\(devices.count) devices in range", 36, 56)
        fill(Color(white: 0.45))
        textSize(15)
        drawText("distance is guessed from signal strength, so a dot wanders", 36, 84)
        if let nearest = devices.first {
            drawText("nearest: \(nearest.name) at \(nearest.signal) dBm", 36, height - 40)
        }
    }

    private func drawReason(_ reason: String) {
        noStroke()
        fill(Color(white: 0.85))
        textSize(24)
        drawText("Nothing to hear yet", 36, 60)
        fill(Color(white: 0.6))
        textSize(17)
        drawText(reason, in: Rectangle(x: 36, y: 90, width: width - 72, height: height - 130))
    }
}
