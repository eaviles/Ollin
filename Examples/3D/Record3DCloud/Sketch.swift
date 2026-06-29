import Foundation
import Ollin
import OllinRecord3D

/// A recorded RGBD clip from an iPhone, orbited as a 3D point cloud — the
/// device-free first slice of the iPhone-as-a-sensor-array work.
///
/// Capture a clip in the **Record3D** iOS app (a LiDAR or TrueDepth iPhone),
/// AirDrop the `.r3d` to your Mac, and it lands in ~/Downloads — this sketch
/// finds the newest one there (or set `OLLIN_R3D` to a specific path). Each
/// frame's color image and metric depth map are unprojected with the recording's
/// true camera intrinsics into a colored cloud, framed and spun so the depth
/// reads as real space. No networking, no live tether: just a file.
///
/// Record3D is by Marek Šimoník (record3d.app) — credited as the capture app
/// and the source of the `.r3d` format, which Ollin reads clean-room from its
/// public structure (the `record3d` library is LGPL-2.1 and never copied).
@main
final class Record3DCloud: Sketch {

    var recording: Record3DRecording?
    var loadedPath: String?
    var loadError: String?

    // The orbit framing, eased frame-to-frame (see the framing block in draw).
    var orbitCenter: Vector3?
    var orbitRadius = 0.0

    override func draw() {
        background(Color(white: 0.04))

        guard let path = Self.findRecording() else {
            return drawStatus("Record a clip in the Record3D app, then AirDrop the .r3d here.\n" +
                              "This sketch reads the newest .r3d in ~/Downloads\n" +
                              "(or set OLLIN_R3D to a path).", style: .info)
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
        let rate = recording.fps > 0 ? recording.fps : 15
        let index = recording.frameCount == 1 ? 0 : Int(time * rate) % recording.frameCount
        guard let cloud = try? recording.pointCloud(at: index, minimumConfidence: .medium,
                                                    depthRange: 0.1...8, pointSize: 0.005) else { return }
        guard !cloud.isEmpty else { return }

        // Frame the cloud: orbit its centroid at a radius set by how spread out it is.
        var sum = Vector3.zero
        for p in cloud.points { sum += p.position }
        let center = sum / Double(cloud.count)
        var spread = 0.0
        for p in cloud.points { spread += p.position.distanceSquared(to: center) }
        let radius = max(0.6, (spread / Double(cloud.count)).squareRoot() * 3)

        // The framing is derived from depth that flickers a little frame to frame
        // (sensor noise, points crossing the confidence/range filters), so snapping
        // the orbit target/radius to it makes the whole cloud jump. Ease toward it
        // instead: a static scene holds still, real camera motion is still followed.
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

        drawCaption("Record3DCloud — an iPhone RGBD recording orbited as a point cloud; drag to spin")
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
