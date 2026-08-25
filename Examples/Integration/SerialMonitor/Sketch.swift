import Foundation
import Ollin
import OllinSerial

/// Every serial device on this Mac, live, and whatever the open one prints.
/// With nothing plugged in it waits; plug a microcontroller in and the port
/// (matching "usb") opens by itself, every line the board prints scrolls up
/// the screen, and a line that is a plain number also fills the bar at the
/// bottom (the classic 0...1023 analog read). Unplugging is fine too: the
/// port waits and reconnects on its own when the board comes back.
///
/// Press 1-9 to open a specific device from the list, space to send "ping"
/// back to the board.
@main
final class SerialMonitor: Sketch {

    var port: SerialPort!
    var opened = "first device matching \"usb\""
    var devices: [SerialDevice] = []
    var lastScan = -10.0
    var log: [String] = []

    override func setup() {
        port = SerialPort(matching: "usb", baudRate: 9600)
        port.open()
    }

    override func draw() {
        background(Color(white: 0.06))

        // Rescan once a second, so plugging and unplugging shows up live.
        if time - lastScan > 1 {
            devices = SerialPort.availableDevices()
            lastScan = time
        }

        // Drain this frame's lines into the scrolling log.
        for line in port.lines() {
            log.append(line)
            if log.count > 16 { log.removeFirst(log.count - 16) }
        }

        let margin = 30 * scale
        noStroke()

        // The device list.
        textSize(22 * scale)
        fill(Color(white: 0.85))
        drawText("Serial devices", margin, 50 * scale)
        fill(Color(white: 0.55))
        if devices.isEmpty {
            drawText("none: plug a board in", margin, 86 * scale)
        }
        for (index, device) in devices.prefix(9).enumerated() {
            drawText("\(index + 1)  \(device.name)   \(device.path)",
                     margin, (86 + Double(index) * 32) * scale)
        }

        // What is open, and the lines it prints.
        let status = port.isOpen ? "open" : "waiting…"
        fill(port.isOpen ? Color(red: 0.4, green: 0.9, blue: 0.5) : Color(white: 0.55))
        drawText("\(opened): \(status)   (1-9 opens, space sends \"ping\")",
                 margin, height * 0.42)
        fill(Color(white: 0.75))
        for (index, line) in log.enumerated() {
            drawText(line, margin, height * 0.42 + (40 + Double(index) * 30) * scale)
        }

        // A numeric line also reads as a value; the bar is the latest one.
        if let value = port.float() {
            let level = min(max(Double(value), 0), 1023) / 1023
            let barY = height - 70 * scale
            let barWidth = width - margin * 2
            fill(Color(white: 0.18))
            drawRect(margin, barY, barWidth, 26 * scale)
            fill(CosinePalette.neon.color(at: 0.25 + level * 0.5))
            drawRect(margin, barY, barWidth * level, 26 * scale)
        }
    }

    override func keyPressed() {
        if key == " " {
            port.writeLine("ping")
            return
        }
        guard let digit = key?.wholeNumberValue,
              digit >= 1, digit <= min(devices.count, 9) else { return }
        let device = devices[digit - 1]
        port.close()
        port = SerialPort(device: device, baudRate: 9600)
        port.open()
        opened = device.name
        log.removeAll()
    }
}
