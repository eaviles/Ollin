import Foundation
import Ollin
import OllinBluetooth

/// One Bluetooth device, connected and read.
///
/// Type part of a device's name into the `deviceName` parameter and the sketch
/// connects to the first device that matches, then lists everything the
/// device offers, with each value as it arrives. A heart rate also drives the
/// disc, so a strap makes the whole canvas beat.
///
/// Run `Integration/BluetoothRoom` first to see what is around you and what
/// it calls itself. With nothing matching, this sketch waits, which is what it
/// does when the device is out of range too.
@main
final class BluetoothSensor: Sketch {

    /// Part of the device's name, as it advertises itself. Change it while
    /// the sketch runs and it looks for the new one.
    @Param var deviceName = "strap"

    private var device: BluetoothDevice?
    private var connectedName = ""
    private var log: [String] = []
    /// Rises on every beat and falls back, so the disc has a pulse.
    private var pulse = 0.0

    override func setup() {
        textFont(.systemMedium)
        lookFor(deviceName)
    }

    override func draw() {
        background(Color(white: 0.04))

        if deviceName != connectedName { lookFor(deviceName) }
        collect()

        drawDisc()
        drawHeading()
        drawValues()
    }

    // MARK: - The device

    private func lookFor(_ name: String) {
        device?.disconnect()
        connectedName = name
        log.removeAll()
        guard !name.isEmpty else {
            device = nil
            return
        }
        let found = BluetoothDevice(named: name)
        found.connect()
        // Battery is a value most devices hold and never announce, so it is
        // asked for again every ten seconds rather than once.
        found.poll(.batteryLevel, every: 10)
        device = found
    }

    /// Everything that arrived since the last frame, in order.
    private func collect() {
        guard let device else { return }
        for reading in device.readings() {
            let shown = reading.text
                ?? reading.number.map { format($0) }
                ?? "\(reading.bytes.count) bytes"
            log.append("\(reading.characteristic.name): \(shown)")
            if log.count > 14 { log.removeFirst(log.count - 14) }

            if reading.characteristic == .heartRateMeasurement { pulse = 1 }
        }
        // The pulse falls away between beats.
        pulse = max(0, pulse - deltaTime * 2.2)
    }

    // MARK: - Drawing

    private func drawDisc() {
        let center = Vector2(width / 2, height * 0.62)
        let beats = device?.number(.heartRateMeasurement)
        let base = min(width, height) * 0.16
        let radius = base * (1 + pulse * 0.22)

        noStroke()
        if let beats {
            fill(Color(hue: 0.98, saturation: 0.55, brightness: 0.35 + pulse * 0.5))
            drawCircle(center: center, radius: radius)
            fill(.white)
            textSize(72)
            textAlign(.center)
            drawText("\(Int(beats))", center.x, center.y + 24)
            textSize(18)
            fill(Color(white: 0.85))
            drawText("beats a minute", center.x, center.y + 56)
            textAlign(.left)
        } else {
            fill(Color(white: 0.12))
            drawCircle(center: center, radius: base)
        }
    }

    private func drawHeading() {
        noStroke()
        textSize(24)
        fill(Color(white: 0.85))

        guard let device else {
            fill(Color(white: 0.5))
            drawText("Type a name into the deviceName parameter", 36, 56)
            return
        }
        if let reason = device.unavailableReason {
            drawText("Nothing to read", 36, 56)
            fill(Color(white: 0.6))
            textSize(17)
            drawText(reason, in: Rectangle(x: 36, y: 80, width: width - 72, height: 160))
            return
        }
        if device.isConnected {
            fill(Color(red: 0.45, green: 0.9, blue: 0.55))
            drawText(device.name ?? "connected", 36, 56)
            fill(Color(white: 0.5))
            textSize(15)
            let signal = device.signal.map { "\($0) dBm" } ?? "signal unknown"
            let battery = device.int(.batteryLevel).map { "battery \($0)%" } ?? "battery unknown"
            drawText("connected, \(signal), \(battery)", 36, 84)
        } else {
            fill(Color(white: 0.55))
            drawText("looking for \"\(connectedName)\"", 36, 56)
            textSize(15)
            fill(Color(white: 0.4))
            drawText("nothing matching is in range yet", 36, 84)
        }
    }

    private func drawValues() {
        guard let device, device.isConnected else { return }
        noStroke()
        textSize(15)

        // What the device carries, on the left.
        fill(Color(white: 0.45))
        drawText("what it offers", 36, 140)
        for (row, characteristic) in device.characteristics.prefix(10).enumerated() {
            let value = device.latest(characteristic)
            let shown = value?.text ?? value?.number.map { format($0) } ?? "nothing yet"
            fill(Color(white: value == nil ? 0.35 : 0.8))
            drawText("\(characteristic.name)   \(shown)", 36, 168 + Double(row) * 26)
        }

        // What arrived, on the right, newest at the bottom.
        fill(Color(white: 0.45))
        drawText("as it arrives", width * 0.55, 140)
        for (row, line) in log.enumerated() {
            fill(Color(white: 0.3 + 0.5 * Double(row) / Double(max(log.count - 1, 1))))
            drawText(line, width * 0.55, 168 + Double(row) * 26)
        }
    }

    private func format(_ value: Double) -> String {
        value == value.rounded() ? "\(Int(value))" : String(format: "%.2f", value)
    }
}
