import Foundation
import Ollin
import OllinRecord3D

/// An iPhone RGBD point cloud, orbited in 3D: a recorded `.r3d` clip by
/// default, and the live USB stream the moment a tethered phone offers one.
///
/// Capture a clip in the **Record3D** iOS app (a LiDAR or TrueDepth iPhone),
/// AirDrop the `.r3d` to your Mac, and it lands in ~/Downloads; this sketch
/// finds the newest one there (or set `OLLIN_R3D` to a specific path). Each
/// frame's color image and metric depth map are unprojected with the
/// recording's true camera intrinsics into a colored cloud, framed and spun so
/// the depth reads as real space. No networking, no live tether: just a file.
///
/// The live stream borrows the phone's depth camera in real time instead: open
/// the Record3D app, enable **USB streaming** in its Settings, keep it on the
/// live screen, and plug the phone into the Mac with a cable. The connection
/// retries on its own, so starting the stream (or plugging in) while the clip
/// is playing just takes over the view; move in front of the lens and the
/// cloud moves. The live path tunes itself to whichever camera is streaming,
/// and its transport is the standard usbmuxd tunnel, the frame format read
/// clean-room from the wire.
///
/// Record3D is by Marek Šimoník (record3d.app), credited as the capture app
/// and the source of both the `.r3d` format and the stream format, which Ollin
/// reads clean-room from their public structure (the `record3d` library is
/// LGPL-2.1 and never copied).
@main
final class Record3DCloud: Sketch {

    /// The live tether. It costs nothing while no phone streams, and the
    /// moment one does, its frames take over from the file.
    let device = Record3DDevice()

    var recording: Record3DRecording?
    var loadedPath: String?
    var loadError: String?

    // The orbit framing, eased frame-to-frame (see the framing note in show).
    var orbitCenter: Vector3?
    var orbitRadius = 0.0

    // The Downloads scan, held for a couple of seconds between looks. Listing a
    // folder is a blocking filesystem call (and the folder is privacy-guarded,
    // so the very first look can wait on a consent prompt); at every frame it
    // stalls the draw loop for nothing, since a new AirDrop landing within two
    // seconds is as fresh as anyone needs.
    var foundPath: String?
    var lastScan = -Double.greatestFiniteMagnitude

    override func setup() {
        device.start()
    }

    override func draw() {
        background(Color(white: 0.04))

        // The live stream wins whenever the tethered phone offers a frame;
        // otherwise the newest recording plays.
        if let frame = device.latestFrame {
            drawLive(frame)
        } else {
            drawRecording()
        }
    }

    // MARK: - The live stream

    func drawLive(_ frame: RGBDFrame) {
        // Tune for the camera in use: the front TrueDepth camera is short-range
        // and noisy past a meter (a face up close), so clamp tight and demand
        // high confidence; the rear LiDAR reaches across a room, so open the
        // range up.
        let tuning = Tuning.forCamera(frame.camera)
        let cloud = frame.pointCloud(minConfidence: tuning.confidence,
                                     depthRange: tuning.range, pointSize: tuning.pointSize)
        guard !cloud.isEmpty else { return }

        show(cloud, caption: "Record3DCloud: live \(tuning.label), " +
                             "\(frame.depthWidth)×\(frame.depthHeight) depth, " +
                             "\(cloud.count) pts; drag to spin")
    }

    // MARK: - The recorded clip

    func drawRecording() {
        if time - lastScan > 2 {
            lastScan = time
            foundPath = Self.findRecording()
        }
        guard let path = foundPath else {
            return drawStatus("Record a clip in the Record3D app, then AirDrop the .r3d here.\n" +
                              "This sketch reads the newest .r3d in ~/Downloads\n" +
                              "(or set OLLIN_R3D to a path). Or plug the phone in over USB\n" +
                              "with streaming enabled, and the live camera takes over.", style: .info)
        }

        // Load once per file; reloading every frame would re-parse the archive.
        if path != loadedPath {
            loadedPath = path
            loadError = nil
            orbitCenter = nil       // re-frame for the new recording
            do { recording = try Record3DRecording(path: path) }
            catch { recording = nil; loadError = "\(error)" }
        }
        if let loadError { return drawStatus("Couldn't open \((path as NSString).lastPathComponent):\n\(loadError)",
                                             style: .warning) }
        guard let recording, recording.frameCount > 0 else { return }

        // Play the clip, looping, at its own frame rate.
        let rate = recording.frameRate > 0 ? recording.frameRate : 15
        let index = recording.frameCount == 1 ? 0 : Int(time * rate) % recording.frameCount
        guard let cloud = try? recording.pointCloud(at: index, minConfidence: .medium,
                                                    depthRange: 0.1...8, pointSize: 0.005) else { return }
        guard !cloud.isEmpty else { return }

        show(cloud, caption: "Record3DCloud: an iPhone RGBD recording orbited as a point cloud; drag to spin")
    }

    // MARK: - Framing either cloud

    /// Frame the cloud: orbit its centroid at a radius set by how spread out it
    /// is, then draw it under the turntable.
    ///
    /// The framing is derived from depth that flickers a little frame to frame
    /// (sensor noise, points crossing the confidence/range filters), so
    /// snapping the orbit target/radius to it makes the whole cloud jump. Ease
    /// toward it instead: a static scene holds still, real camera motion is
    /// still followed.
    func show(_ cloud: PointCloud, caption: String) {
        var sum = Vector3.zero
        for p in cloud.points { sum += p.position }
        let center = sum / Double(cloud.count)
        var spread = 0.0
        for p in cloud.points { spread += p.position.distanceSquared(to: center) }
        let radius = max(0.6, (spread / Double(cloud.count)).squareRoot() * 3)

        if let c = orbitCenter {
            orbitCenter = c.lerp(to: center, 0.08)
            orbitRadius += (radius - orbitRadius) * 0.08
        } else {
            orbitCenter = center
            orbitRadius = radius
        }

        cameraShowcase(.turntable(period: .tau / 0.3), target: orbitCenter ?? center, radius: orbitRadius,
                    elevation: 0.18, fieldOfView: .pi / 3)
        drawPointCloud(cloud)

        drawCaption(caption)
    }

    /// The per-camera point-cloud settings, derived from which camera is streaming.
    struct Tuning {
        let range: ClosedRange<Double>
        let confidence: DepthConfidence
        let pointSize: Double
        let label: String

        static func forCamera(_ camera: Record3DCamera) -> Tuning {
            switch camera {
            case .trueDepth:   // front: a face up close, noisy background
                return Tuning(range: 0.2...1.2, confidence: .high, pointSize: 0.004,
                              label: "TrueDepth (front)")
            case .lidar:       // rear: a whole room
                return Tuning(range: 0.3...5.0, confidence: .medium, pointSize: 0.009,
                              label: "LiDAR (rear)")
            case .unknown:
                return Tuning(range: 0.1...8.0, confidence: .medium, pointSize: 0.006,
                              label: "depth camera")
            }
        }
    }

    /// The newest `.r3d` in ~/Downloads, or the `OLLIN_R3D` override if set.
    static func findRecording() -> String? {
        let fm = FileManager.default
        if let override = ProcessInfo.processInfo.environment["OLLIN_R3D"],
           fm.fileExists(atPath: override) { return override }
        guard let downloads = fm.urls(for: .downloadsDirectory, in: .userDomainMask).first,
              let files = try? fm.contentsOfDirectory(at: downloads,
                                                      includingPropertiesForKeys: [.contentModificationDateKey])
        else { return nil }
        let newest = files
            .filter { $0.pathExtension.lowercased() == "r3d" }
            .max { modified($0) < modified($1) }
        return newest?.path
    }

    private static func modified(_ url: URL) -> Date {
        (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
    }
}
