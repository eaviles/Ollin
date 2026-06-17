import Foundation
import Ollin
import OllinPhone

/// Background replacement, live from a tethered iPhone — the on-device sibling of
/// `Vision/PersonSegmentation`. The phone's Neural Engine segments the people in its
/// rear camera; this lifts them onto a drifting gradient backdrop, with the tinted
/// matte doubling as a soft drop shadow.
///
/// Setup: install **Ollin Capture** on an A12+ iPhone, launch it, tap the **Segment**
/// segment, and connect the cable. The connection retries on its own, so tapping
/// Segment (or plugging in) after this sketch is already running just begins the feed.
///
/// The matte and cutout come back upright for how the phone is held and line up with
/// each other (the capture app sends its orientation; `PhoneDevice` rotates to match).
/// The transport is the standard usbmuxd tunnel; the wire format is Ollin's own.
@main
final class PhoneSegmentation: Sketch {

    let device = PhoneDevice()

    override func setup() {
        device.start()
    }

    override func draw() {
        // A slowly drifting two-tone backdrop to lift the person onto. `Color(hue:)`
        // wraps, so `time` drives the hue with no bookkeeping.
        let top = Color(hue: time * 0.03, saturation: 0.55, brightness: 0.55)
        let bottom = Color(hue: time * 0.03 + 0.5, saturation: 0.5, brightness: 0.12)
        noStroke()
        fill(.linear(from: Vector2(0, 0), to: Vector2(0, height), [top, bottom]))
        drawRect(canvasRectangle)

        guard let cutout = device.latestSegmentationCutout else {
            return drawStatus(device.waitingMessage + "\n\n" +
                              "Open Ollin Capture on an A12+ iPhone, tap the Segment tab,\n" +
                              "and connect the cable.", style: .info)
        }

        // Letterbox the camera frame into the canvas; the matte shares the same rect.
        let frameSize = Vector2(Double(cutout.width), Double(cutout.height))
        let rect = Rectangle(fitting: frameSize, in: canvasRectangle)

        // The matte as a soft drop shadow: tinted dark and translucent, nudged
        // down-right behind the cutout (the same matte, recolored by `tint`).
        if let matte = device.latestSegmentationMatte {
            withState {
                translate(rect.width * 0.03, rect.width * 0.04)
                tint(Color(white: 0, alpha: 0.35))
                drawImage(matte, in: rect)
            }
        }

        // The person, lifted off their real background.
        drawImage(cutout, in: rect)

        drawCaption("PhoneSegmentation — \(cutout.width)×\(cutout.height) cutout on a live backdrop")
    }
}
