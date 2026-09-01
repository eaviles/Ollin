import Foundation
import Ollin
import OllinSerial

/// The classic physical-computing loop, self-contained. The sketch runs *both*
/// ends of the wire: a tiny fake device (the manager side of a pty pair)
/// prints a sensor-ish number thirty times a second, and a `SerialPort` opens
/// the other side exactly the way it would open a USB microcontroller. The
/// trace is drawn from what arrives over the port, so what you see is the
/// serial round trip, not a local variable. Click to send a line back: the
/// fake device flips its wave upside down, which is the write path working.
///
/// To read a real board instead, see the `SerialMonitor` example. This
/// sketch's serial-facing code is the same either way; only the device is
/// fake.
@main
final class SerialLoopback: Sketch {

    var device: FakeDevice!
    var port: SerialPort!
    var trace: [Double] = []
    var received = 0

    override func setup() {
        device = FakeDevice()
        port = SerialPort(path: device.path, baudRate: 9600)
        port.open()
    }

    override func draw() {
        background(Color(white: 0.06))

        // The drain: every line since the last frame, one trace point each,
        // so the wave is exactly the stream no matter the frame rate.
        for line in port.lines() {
            received += 1
            if let sample = Double(line) { trace.append(sample) }
        }
        if trace.count > 240 { trace.removeFirst(trace.count - 240) }

        // The polling cache: the latest value, read whenever this frame lands.
        let value = port.number(default: 512)

        // The trace, pinned to the right edge and growing in leftward.
        let points = trace.enumerated().map { index, sample in
            let slot = 239 - (trace.count - 1 - index)
            return Vector2(
                width * Double(slot) / 239,
                height * 0.62 - (sample / 1023 - 0.5) * height * 0.5
            )
        }
        noFill()
        stroke(CosinePalette.neon.color(at: 0.3 + value / 1023 * 0.4))
        strokeWeight(4 * scale)
        drawPolyline(points)
        if let tip = points.last {
            noStroke()
            fill(.white)
            drawCircle(center: tip, radius: 10 * scale)
        }

        noStroke()
        fill(Color(white: 0.6))
        textSize(22 * scale)
        drawText("serial ↺ \(port.isOpen ? device.path : "opening…")", 30 * scale, 50 * scale)
        drawText("latest \(Int(value))   lines \(received)   click to flip the wave", 30 * scale, 84 * scale)
    }

    override func mousePressed() {
        port.writeLine("flip")
    }
}

/// The device end of the wire: the manager side of a pty pair, printing a
/// wobbly value on a timer and flipping the wave when any line comes back.
final class FakeDevice: @unchecked Sendable {

    let path: String
    private let manager: Int32
    private let queue = DispatchQueue(label: "serial-loopback.device")
    private let timer: DispatchSourceTimer
    private var clock = 0.0
    private var flipped = false

    init() {
        let descriptor = posix_openpt(O_RDWR | O_NOCTTY)
        precondition(
            descriptor >= 0 && grantpt(descriptor) == 0 && unlockpt(descriptor) == 0,
            "could not create the pty pair"
        )
        var settings = termios()
        if tcgetattr(descriptor, &settings) == 0 {
            cfmakeraw(&settings)
            _ = tcsetattr(descriptor, TCSANOW, &settings)
        }
        _ = fcntl(descriptor, F_SETFL, fcntl(descriptor, F_GETFL) | O_NONBLOCK)
        manager = descriptor
        path = String(cString: ptsname(descriptor))

        timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now(), repeating: 1.0 / 30.0)
        timer.setEventHandler { [weak self] in self?.tick() }
        timer.activate()
    }

    private func tick() {
        // Anything sent back flips the wave.
        var buffer = [UInt8](repeating: 0, count: 256)
        if read(manager, &buffer, buffer.count) > 0 { flipped.toggle() }

        clock += 1.0 / 30.0
        var wave = sin(clock * 1.4) * 0.8 + sin(clock * 4.3) * 0.2
        if flipped { wave = -wave }
        let value = Int((wave * 0.5 + 0.5) * 1023)
        let line = "\(value)\n"
        _ = line.withCString { write(manager, $0, strlen($0)) }
    }
}
