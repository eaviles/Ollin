import SwiftUI
import ARKit
import simd

/// **Ollin Capture** — Ollin's own iPhone sensor app. The phone runs ARKit (body
/// pose, face, rear-LiDAR scene depth, person segmentation, the reconstructed room
/// surface with the flat planes in it, and the room's own light) on its Neural
/// Engine plus CoreMotion device motion, and streams them to a
/// tethered Mac over USB (usbmuxd → `PhoneWire.streamPort`), where an Ollin sketch
/// reads them in `draw()` via `OllinPhone`'s `PhoneDevice`.
@main
struct OllinCaptureApp: App {
    var body: some Scene {
        WindowGroup { ContentView() }
    }
}

/// Which on-device sensor ARKit drives. Body, World, Segment, and Room use the rear
/// camera, Face the front TrueDepth camera. Only one ARKit session runs at a time, so
/// they are mutually exclusive and the app runs one at a time. World streams a LiDAR
/// RGBD frame (depth + color + pose); Body a skeleton; Face the expression mesh;
/// Segment a person matte (+ color) for a silhouette/cutout; Room the reconstructed
/// surface, block by block, with each triangle labelled, and the flat planes found
/// alongside it.
///
/// The room's light streams in every mode, so it is not a mode of its own.
enum CaptureMode: String, CaseIterable, Identifiable {
    case body = "Body"
    case face = "Face"
    case world = "World"
    case segment = "Segment"
    case room = "Room"
    var id: String { rawValue }
}

/// Owns the network server and the sensor streamers, and publishes the live status
/// the screen shows. `@MainActor` — the AR/motion callbacks land on main.
@MainActor
@Observable
final class SensorStreamer {

    var clientCount = 0
    var mode: CaptureMode = .body
    var bodyTracked = false
    var jointCount = 0
    var faceTracked = false
    var topExpression = ""
    var depthTracked = false
    var depthInfo = ""
    var segTracked = false
    var segInfo = ""
    var meshTracked = false
    var meshInfo = ""
    var planeInfo = ""
    var lightInfo = ""
    var lightLive = false
    var gravity = SIMD3<Float>(0, 0, 0)
    var motionLive = false
    var status = "Starting…"

    let bodySupported = ARBodyTrackingConfiguration.isSupported
    let faceSupported = ARFaceTrackingConfiguration.isSupported
    let depthSupported = ARWorldTrackingConfiguration.supportsFrameSemantics(.sceneDepth)
    let segSupported = ARWorldTrackingConfiguration.supportsFrameSemantics(.personSegmentation)
    let meshSupported = ARWorldTrackingConfiguration.supportsSceneReconstruction(.mesh)

    private var server: SensorServer?
    private let ar = ARStreamer()
    private let face = FaceStreamer()
    private let depth = DepthStreamer()
    private let seg = SegmentationStreamer()
    private let room = RoomStreamer()
    private let motion = MotionStreamer()

    /// How many blocks of the room have gone out, and how many were dropped for
    /// being too big to carry, so the screen can report both.
    private var meshBlocksSent = 0
    private var meshBlocksSkipped = 0
    /// The flat surfaces reported so far, and how many of them are still live, so the
    /// screen can say what the phone has found.
    private var planesSent = 0
    private var livePlanes: Set<UUID> = []
    private var started = false

    func start() {
        guard !started else { return }
        started = true
        UIApplication.shared.isIdleTimerDisabled = true   // keep streaming while idle

        do {
            let server = try SensorServer(port: PhoneWire.streamPort) { [weak self] count in
                Task { @MainActor in self?.clientCount = count }
            }
            self.server = server
        } catch {
            status = "Couldn't open the listener: \(error.localizedDescription)"
            return
        }

        motion.onSample = { [weak self] sample in
            guard let self else { return }
            self.server?.send(PhoneWire.encode(.motion(sample)))
            self.motionLive = true
            self.gravity = sample.gravity
        }
        motion.start()

        ar.onPose = { [weak self] sample in
            guard let self else { return }
            self.server?.send(PhoneWire.encode(.pose(sample)))
            self.bodyTracked = sample.tracked
            self.jointCount = sample.joints.count
        }

        face.onFaces = { [weak self] samples in
            guard let self else { return }
            self.server?.send(PhoneWire.encode(.face(samples)))
            self.faceTracked = samples.contains { $0.tracked }
            if let primary = samples.first {
                let expr = Self.describe(primary.blendShapes)
                self.topExpression = samples.count > 1 ? "\(samples.count) faces · \(expr)" : expr
            } else {
                self.topExpression = ""
            }
        }

        depth.onDepth = { [weak self] sample in
            guard let self else { return }
            self.server?.send(PhoneWire.encode(.depth(sample)))
            self.depthTracked = sample.tracked
            self.depthInfo = "\(sample.depthWidth)×\(sample.depthHeight) · \(sample.colorJPEG.count / 1024) KB"
        }

        seg.onSegmentation = { [weak self] sample in
            guard let self else { return }
            self.server?.send(PhoneWire.encode(.segmentation(sample)))
            self.segTracked = sample.tracked
            self.segInfo = "\(sample.matteWidth)×\(sample.matteHeight) · \(sample.colorJPEG.count / 1024) KB"
        }

        room.onChunk = { [weak self] sample in
            guard let self else { return }
            self.server?.send(PhoneWire.encode(.sceneMesh(sample)))
            self.meshBlocksSent += 1
            self.meshTracked = sample.tracked
            self.meshInfo = "\(self.meshBlocksSent) blocks"
            if self.meshBlocksSkipped > 0 {
                self.meshInfo += " · \(self.meshBlocksSkipped) too big"
            }
        }

        room.onOversized = { [weak self] count in
            self?.meshBlocksSkipped = count
        }

        room.onPlane = { [weak self] sample in
            guard let self else { return }
            self.server?.send(PhoneWire.encode(.plane(sample)))
            self.planesSent += 1
            if sample.removed { self.livePlanes.remove(sample.id) } else { self.livePlanes.insert(sample.id) }
            self.planeInfo = "\(self.livePlanes.count) found"
        }

        // Every session estimates the light, so they all report to the same handler
        // and a mode switch never interrupts it.
        let reporters: [any LightReporting] = [ar, face, depth, seg, room]
        for reporter in reporters {
            reporter.lightSampler.onLight = { [weak self] sample in
                guard let self else { return }
                self.server?.send(PhoneWire.encode(.light(sample)))
                self.lightLive = true
                self.lightInfo = String(format: "%.0f lm · %.0f K",
                                        sample.ambientIntensity, sample.colorTemperature)
                if sample.hasDirection { self.lightInfo += " · with direction" }
            }
        }

        applyMode()
    }

    /// Switch the active camera/tracker. Only one ARKit session runs at a time, so
    /// the other is paused first; device motion keeps streaming across the switch.
    func setMode(_ newMode: CaptureMode) {
        guard newMode != mode else { return }
        mode = newMode
        applyMode()
    }

    private func applyMode() {
        // Only one ARKit session at a time — stop the others before starting one.
        switch mode {
        case .body:
            face.stop(); depth.stop(); seg.stop(); room.stop()
            ar.start()
            status = bodySupported ? "Streaming body" : "This device doesn't support body tracking"
        case .face:
            ar.stop(); depth.stop(); seg.stop(); room.stop()
            face.start()
            status = faceSupported ? "Streaming face" : "This device doesn't support face tracking"
        case .world:
            ar.stop(); face.stop(); seg.stop(); room.stop()
            depth.start()
            status = depthSupported ? "Streaming depth" : "This device has no LiDAR for depth"
        case .segment:
            ar.stop(); face.stop(); depth.stop(); room.stop()
            seg.start()
            status = segSupported ? "Streaming segmentation" : "This device doesn't support person segmentation"
        case .room:
            ar.stop(); face.stop(); depth.stop(); seg.stop()
            // A fresh session rebuilds the room from nothing, so the Mac's own count
            // starts again with it.
            meshBlocksSent = 0
            meshBlocksSkipped = 0
            meshInfo = ""
            planesSent = 0
            livePlanes.removeAll()
            planeInfo = ""
            room.start()
            status = meshSupported
                ? "Streaming the room surface and its flat planes"
                : "Streaming flat planes (this device has no LiDAR to build a surface)"
        }
    }

    /// Name the strongest-firing blendshape, for the status readout.
    private static func describe(_ blendShapes: [Float]) -> String {
        var best = -1, bestValue: Float = 0.15        // ignore near-neutral noise
        for (i, v) in blendShapes.enumerated() where v > bestValue { best = i; bestValue = v }
        guard best >= 0, let shape = PhoneBlendShape(rawValue: UInt8(best)) else { return "neutral" }
        return String(format: "%@ %.0f%%", "\(shape)", bestValue * 100)
    }
}

struct ContentView: View {
    @State private var streamer = SensorStreamer()

    private var connected: Bool { streamer.clientCount > 0 }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            VStack(spacing: 28) {
                Spacer()

                // Title
                VStack(spacing: 6) {
                    Text("OLLIN")
                        .font(.system(size: 44, weight: .heavy, design: .rounded))
                        .foregroundStyle(.white)
                    Text("CAPTURE")
                        .font(.system(size: 18, weight: .semibold, design: .rounded))
                        .tracking(8)
                        .foregroundStyle(.white.opacity(0.55))
                }

                // Connection lamp
                HStack(spacing: 10) {
                    Circle()
                        .fill(connected ? Color.red : Color.gray)
                        .frame(width: 14, height: 14)
                        .shadow(color: connected ? .red : .clear, radius: 8)
                    Text(connected ? "ON AIR · Mac connected" : "READY · waiting for the Mac")
                        .font(.system(.headline, design: .rounded))
                        .foregroundStyle(.white.opacity(0.9))
                }

                // Capture mode — one ARKit session at a time (rear: body/world/segment,
                // front: face), so the modes are mutually exclusive.
                Picker("Mode", selection: Binding(
                    get: { streamer.mode },
                    set: { streamer.setMode($0) }
                )) {
                    ForEach(CaptureMode.allCases) { mode in Text(mode.rawValue).tag(mode) }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 28)

                // Status rows
                VStack(alignment: .leading, spacing: 12) {
                    switch streamer.mode {
                    case .body:
                        row("Body", streamer.bodySupported
                            ? (streamer.bodyTracked ? "tracking · \(streamer.jointCount) joints" : "searching…")
                            : "unsupported on this device",
                            ok: streamer.bodyTracked)
                    case .face:
                        row("Face", streamer.faceSupported
                            ? (streamer.faceTracked ? "tracking · \(streamer.topExpression)" : "searching…")
                            : "unsupported on this device",
                            ok: streamer.faceTracked)
                    case .world:
                        row("Depth", streamer.depthSupported
                            ? (streamer.depthTracked ? "streaming · \(streamer.depthInfo)" : "starting…")
                            : "needs LiDAR (Pro)",
                            ok: streamer.depthTracked)
                    case .segment:
                        row("Person", streamer.segSupported
                            ? (streamer.segTracked ? "streaming · \(streamer.segInfo)" : "starting…")
                            : "needs A12+ for segmentation",
                            ok: streamer.segTracked)
                    case .room:
                        row("Surface", streamer.meshSupported
                            ? (streamer.meshInfo.isEmpty ? "walk around to build it…" : "streaming · \(streamer.meshInfo)")
                            : "needs LiDAR (Pro)",
                            ok: streamer.meshTracked)
                        row("Planes", streamer.planeInfo.isEmpty
                            ? "looking for flat surfaces…" : "streaming · \(streamer.planeInfo)",
                            ok: !streamer.planeInfo.isEmpty)
                    }
                    row("Light", streamer.lightLive ? streamer.lightInfo : "measuring…",
                        ok: streamer.lightLive)
                    row("Motion", streamer.motionLive
                        ? String(format: "live · gravity (% .2f, % .2f, % .2f)",
                                 streamer.gravity.x, streamer.gravity.y, streamer.gravity.z)
                        : "starting…",
                        ok: streamer.motionLive)
                    row("Port", "\(PhoneWire.streamPort) · over USB", ok: connected)
                }
                .padding(20)
                .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 16))
                .padding(.horizontal, 28)

                Text(streamer.status)
                    .font(.footnote)
                    .foregroundStyle(.white.opacity(0.4))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)

                Spacer()
                Text("Connect the cable and run a sketch on the Mac")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.3))
                    .padding(.bottom, 12)
            }
        }
        .onAppear { streamer.start() }
    }

    private func row(_ label: String, _ value: String, ok: Bool) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label)
                .font(.system(.subheadline, design: .rounded).weight(.semibold))
                .foregroundStyle(.white.opacity(0.5))
                .frame(width: 70, alignment: .leading)
            Text(value)
                .font(.system(.subheadline, design: .monospaced))
                .foregroundStyle(ok ? Color.green.opacity(0.9) : .white.opacity(0.75))
            Spacer(minLength: 0)
        }
    }
}
