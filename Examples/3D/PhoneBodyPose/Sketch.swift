import Foundation
import Ollin
import OllinPhone

/// A 3D stick figure driven live by a tethered iPhone running the **Ollin** capture
/// app — the first slice of Ollin's own iPhone-as-a-sensor-array app. Where the
/// Record3D examples borrow another app's RGBD feed, here the phone runs ARKit body
/// tracking on its Neural Engine and streams the skeleton; the Mac just draws it.
///
/// Setup: build + run the Ollin capture app (Apps/OllinPhoneApp) on the iPhone,
/// connect the cable, and stand in front of the phone's camera. The connection
/// retries on its own, so launching the app (or plugging in) after this sketch is
/// already running just begins the feed. Before a body is found, the device-motion
/// readout proves the USB wire is alive (tilt the phone and the gravity vector moves).
@main
final class PhoneBodyPose: Sketch {

    let device = PhoneDevice()

    // Orbit framing, eased frame-to-frame so live sensor noise doesn't jitter it.
    var orbitCenter: Vector3?

    override func setup() {
        device.start()
    }

    override func draw() {
        background(Color(white: 0.05))

        guard let body = device.latestBody, !body.positions.isEmpty else {
            // No skeleton yet — show the connection state, plus the motion readout if
            // the wire is already alive (the transport smoke-test).
            var text = device.waitingMessage + "\n\n" +
                "Run the Ollin capture app on the iPhone, connect the cable,\n" +
                "and stand in front of its camera."
            if let m = device.latestMotion {
                text += String(format: "\n\nmotion live · gravity (% .2f, % .2f, % .2f)",
                               m.gravity.x, m.gravity.y, m.gravity.z)
            }
            return drawStatus(text, style: .info)
        }

        // Ease the orbit target toward the figure's centroid so it holds steady.
        let center = body.center
        if let c = orbitCenter { orbitCenter = c.lerp(to: center, 0.12) } else { orbitCenter = center }

        let azimuth = mouseIsPressed ? map(mouseX, 0, width, .pi, -.pi) : time * 0.4
        camera(.orbiting(target: orbitCenter ?? center, radius: 2.6, azimuth: azimuth,
                         elevation: 0.12, fieldOfView: .pi / 3))

        // Tracked = warm white; extrapolated (ARKit lost the person) = dim blue.
        let tint = body.isTracked ? Color(white: 0.95) : Color(hex: 0x5C6B8A)
        drawPointCloud(body.cloud(jointSize: 0.055, boneSize: 0.018, color: tint))

        let state = body.isTracked ? "tracking" : "extrapolating"
        drawCaption("PhoneBodyPose — \(state), \(body.positions.count) joints; drag to spin")
    }
}
