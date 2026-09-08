import Ollin
import OllinSerial

/// A board with no firmware of your own. Upload StandardFirmata to the board
/// (File > Examples > Firmata in its IDE), plug it in, and its pins answer to
/// the sketch: the six analog pins draw as bars, digital pins 2 through 7 as
/// dots (input with the board's pull-up, so a button to ground lights its
/// dot), a click flips the LED on pin 13, and the mouse's height sets the PWM
/// duty on pin 9. Asking a pin is what turns it on, the board is told again
/// after every reset, and until a board turns up the sketch says so.
///
/// Try it: `swift run Example-Integration-Firmata`, then twist a
/// potentiometer on A0 or wire a button between pin 2 and ground.
@main
final class Firmata_Example: Sketch {
    private let board = FirmataBoard(matching: "usb")
    private var led = false

    override func setup() { board.open() }

    override func mousePressed() {
        led.toggle()
        board.write(13, led)
    }

    override func draw() {
        background(Color(hex: 0x14202B))
        textFont(.system)
        textAlign(.left, .top)
        fill(Color(hex: 0xF2E8DC))
        textSize(22)

        guard board.isOpen else {
            drawText("waiting for a board on USB", 40, 40)
            return
        }
        let firmware = board.firmware.map { "\($0.name) \($0.majorVersion).\($0.minorVersion)" }
        drawText(firmware ?? "connected, waiting for the board to answer", 40, 40)

        // The analog pins as bars.
        let barWidth = (width - 80) / 6
        for pin in 0 ..< 6 {
            let level = board.analog(pin, default: 0)
            let x = 40 + Double(pin) * barWidth
            noStroke()
            fill(Color(hex: 0x2B6C8C))
            drawRect(x + 8, height * 0.6 - level * height * 0.4, barWidth - 16, level * height * 0.4)
            fill(Color(hex: 0xF2E8DC))
            textSize(16)
            textAlign(.center, .top)
            drawText("A\(pin)", x + barWidth / 2, height * 0.6 + 10)
        }

        // Digital pins 2...7 as dots.
        for (i, pin) in (2 ... 7).enumerated() {
            let x = 40 + (Double(i) + 0.5) * barWidth
            let on = board.digital(pin, pullUp: true, default: false)
            noStroke()
            fill(on ? Color(hex: 0xE8B44A) : Color(hex: 0x2B3A4A))
            drawCircle(x, height * 0.78, 18)
            fill(Color(hex: 0xF2E8DC))
            textAlign(.center, .top)
            drawText("D\(pin)", x, height * 0.78 + 28)
        }

        // The mouse's height is the PWM duty on pin 9, the click the LED.
        let duty = 1 - min(max(mouseY / height, 0), 1)
        board.write(9, duty)
        textAlign(.left, .top)
        drawText("pin 9 PWM \(Int(duty * 100))%   pin 13 LED \(led ? "on" : "off")   (click to flip)",
                 40, height - 50)
    }
}
