import Foundation
import Ollin
import OllinRecord3D

/// 2D markers floating at **true metric depths** inside a live RGBD feed — the
/// metric sibling of `DepthOcclusion`. There the occlusion plane was a normalized
/// 0…1 value; here it's a real distance in **meters**, because the camera is built
/// from the depth frame's own lens.
///
/// `camera(.intrinsic(frame.intrinsics))` makes a metric camera from the
/// stream's calibration, then `drawDepthScene(frame)` lays down the color picture
/// *and* writes the frame's metric depth (meters) into the depth buffer. So a marker
/// placed at a world point a fixed number of meters away — `withBillboard(at:)`
/// puts it there with correct occlusion — is hidden the instant something nearer
/// than that distance passes in front of it. Drag up and down to push the plane of
/// markers from 0.3 m to 3 m; walk toward the camera and you cross each marker's
/// distance and start blocking it.
///
/// Setup mirrors `Record3DLiveCloud`: open **Record3D** on a LiDAR iPhone (point the
/// rear camera at the room), enable **USB streaming** in its Settings, keep it on
/// the live screen, and connect the cable. The connection retries on its own.
///
/// The feed is letterboxed into the canvas by its own aspect (no stretch, whatever
/// the phone's orientation), and the metric camera letterboxes to match — so the
/// markers always land on the picture.
///
/// Record3D is by Marek Šimoník (record3d.app) — credited as the capture app and
/// the source of the stream format, read clean-room from its public structure.
@main
final class MetricDepthScene: Sketch {

    let device = Record3DDevice()

    // The marker plane's distance in meters, eased so it glides as you drag.
    var planeMeters = 1.0

    override func setup() {
        device.start()
    }

    override func draw() {
        background(Color(white: 0.04))

        guard let frame = device.latestFrame else {
            return drawStatus(device.waitingMessage + "\n\n" +
                              "Open Record3D on the iPhone, enable USB streaming in Settings,\n" +
                              "keep it on the live screen, and connect the cable.", style: .info)
        }

        // A metric camera from the feed's own intrinsics: a point cloud, a depth
        // scene, and any placed object now share one space measured in meters.
        camera(.intrinsic(frame.intrinsics))

        // The backdrop picture + the frame's metric depth, written into the depth
        // buffer. Fills the canvas (the camera projects the scene across the canvas).
        drawDepthScene(frame)

        // Drag up/down to set the plane distance (0.3 m near … 3 m far), eased.
        let target = mouseIsPressed ? map(mouseY, 0, height, 0.3, 3.0) : planeMeters
        planeMeters += (target - planeMeters) * 0.15

        // A grid of markers, each placed at a screen position unprojected to the
        // plane's metric depth — so it sits exactly under that pixel, `planeMeters`
        // away. `withBillboard` lands it there with metric occlusion: hidden wherever
        // the depth scene wrote something nearer than the plane.
        let k = frame.intrinsics
        let cols = 5, rows = 4
        noStroke()
        for j in 0..<rows {
            for i in 0..<cols {
                let col = Double(k.width) * (Double(i) + 0.5) / Double(cols)
                let row = Double(k.height) * (Double(j) + 0.5) / Double(rows)
                let world = k.unproject(col: col, row: row, depth: planeMeters)
                withBillboard(at: world) {
                    let hue = (Double(i) / Double(cols) + Double(j) / Double(rows) * 0.5
                               + time * 0.05).truncatingRemainder(dividingBy: 1)
                    fill(Color(hue: hue, saturation: 0.7, brightness: 1.0, alpha: 0.92))
                    drawCircle(0, 0, 26)
                    fill(Color(white: 0.05))
                    drawCircle(0, 0, 9)
                }
            }
        }

        drawCaption(String(format: "MetricDepthScene — markers at %.2f m; drag to move the plane, " +
                           "step closer to block them", planeMeters))
    }
}
