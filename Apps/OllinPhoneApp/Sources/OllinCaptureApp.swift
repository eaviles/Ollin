import SwiftUI
import ARKit
import simd

/// **Ollin Capture**, Ollin's own iPhone sensor app. The phone runs ARKit (body
/// pose, face, rear-LiDAR scene depth, person segmentation, the reconstructed room
/// surface with the flat planes in it, and the room's own light) on its Neural
/// Engine, plus the 21-joint hand skeletons and the readable text in view (Vision
/// over the ARKit frames, lifted to 3D through the LiDAR depth), a front-camera
/// selfie matte (Vision, no ARKit), and CoreMotion device motion, and streams them
/// to a tethered Mac over USB (usbmuxd → `PhoneWire.streamPort`), where an Ollin
/// sketch reads them in `draw()` via `OllinPhone`'s `PhoneDevice`.
@main
struct OllinCaptureApp: App {
    var body: some Scene {
        WindowGroup { ContentView() }
    }
}

/// Which on-device sensor runs. Body, World, Segment, Room, Hands, and Text use
/// the rear camera through ARKit; Face the front TrueDepth camera through ARKit;
/// Selfie the front camera through a plain capture session plus Vision. Only one
/// camera session runs at a time, so they are mutually exclusive and the app runs
/// one at a time. World streams a LiDAR RGBD frame (depth + color + pose); Body a
/// skeleton; Face the expression mesh; Segment a person matte (+ color) for a
/// silhouette/cutout; Selfie the same matte from the front camera, mirrored like
/// the preview; Room the reconstructed surface, block by block, with each triangle
/// labeled, and the flat planes found alongside it; Hands the 21-joint hand
/// skeletons in view, lifted to metric 3D through the LiDAR depth where the device
/// has it; Text the lines it can read in the scene, their corners lifted the same
/// way; Markers the reference pictures and scanned objects it knows, each reported
/// where it stands in the room.
///
/// Wand is the one mode that reports the person rather than the room: the phone's
/// own place and heading, with the thumb on the screen beside it, so a sketch on
/// the Mac can be pointed at and pressed.
///
/// The room's light streams in every ARKit mode, so it is not a mode of its own.
/// Selfie runs no ARKit session, so it is the one mode with no light readings.
enum CaptureMode: String, CaseIterable, Identifiable {
    case body = "Body"
    case face = "Face"
    case world = "World"
    case segment = "Segment"
    case selfie = "Selfie"
    case room = "Room"
    case hands = "Hands"
    case text = "Text"
    case markers = "Markers"
    case wand = "Wand"
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
    var selfiePresent = false
    var selfieInfo = ""
    var meshTracked = false
    var meshInfo = ""
    var planeInfo = ""
    var handsTracked = false
    var handsInfo = ""
    var textTracked = false
    var textInfo = ""
    var markersFound = false
    var markerInfo = ""
    var wandTracked = false
    var wandInfo = ""
    /// What the phone is looking for, and what it could not use, for the screen.
    var markerReferences: [MarkerReference] = []
    var markerNotes: [String] = []
    var lightInfo = ""
    var lightLive = false
    var gravity = SIMD3<Float>(0, 0, 0)
    var motionLive = false
    var status = "Starting…"

    let bodySupported = ARBodyTrackingConfiguration.isSupported
    let faceSupported = ARFaceTrackingConfiguration.isSupported
    let depthSupported = ARWorldTrackingConfiguration.supportsFrameSemantics(.sceneDepth)
    let segSupported = ARWorldTrackingConfiguration.supportsFrameSemantics(.personSegmentation)
    let selfieSupported = SelfieStreamer.hasFrontCamera
    let meshSupported = ARWorldTrackingConfiguration.supportsSceneReconstruction(.mesh)
    let handsLift = ARWorldTrackingConfiguration.supportsFrameSemantics(.sceneDepth)
    let textLift = ARWorldTrackingConfiguration.supportsFrameSemantics(.sceneDepth)

    private var server: SensorServer?
    private let ar = ARStreamer()
    private let face = FaceStreamer()
    private let depth = DepthStreamer()
    private let seg = SegmentationStreamer()
    private let selfie = SelfieStreamer()
    private let room = RoomStreamer()
    private let hands = HandStreamer()
    private let text = TextStreamer()
    private let markers = MarkerStreamer()
    /// The one streamer the screen writes into rather than only reading: the pad
    /// under the thumb is part of this sensor, so the view reaches it directly.
    let wand = WandStreamer()
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

        ar.onBodies = { [weak self] samples in
            guard let self else { return }
            self.server?.send(PhoneWire.encode(.pose(samples)))
            self.bodyTracked = samples.contains { $0.isTracked }
            self.jointCount = samples.first?.joints.count ?? 0
        }

        face.onFaces = { [weak self] samples in
            guard let self else { return }
            self.server?.send(PhoneWire.encode(.face(samples)))
            self.faceTracked = samples.contains { $0.isTracked }
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

        // The selfie matte rides the same wire kind as the rear-camera one; the Mac
        // reads whichever mode is running through the same accessors.
        selfie.onSegmentation = { [weak self] sample in
            guard let self else { return }
            self.server?.send(PhoneWire.encode(.segmentation(sample)))
            self.selfiePresent = sample.tracked
            self.selfieInfo = "\(sample.matteWidth)×\(sample.matteHeight) · \(sample.colorJPEG.count / 1024) KB"
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

        hands.onHands = { [weak self] samples in
            guard let self else { return }
            self.server?.send(PhoneWire.encode(.hands(samples)))
            self.handsTracked = !samples.isEmpty
            if samples.isEmpty {
                self.handsInfo = "no hands in view"
            } else {
                let lifted = samples.contains { $0.joints.values.contains(where: \.hasWorldPosition) }
                self.handsInfo = "\(samples.count) · \(lifted ? "3D" : "2D")"
            }
        }

        text.onTexts = { [weak self] samples in
            guard let self else { return }
            self.server?.send(PhoneWire.encode(.texts(samples)))
            self.textTracked = !samples.isEmpty
            if samples.isEmpty {
                self.textInfo = "no text in view"
            } else {
                let lifted = samples.contains(where: \.hasWorldCorners)
                self.textInfo = "\(samples.count) \(samples.count == 1 ? "line" : "lines") · \(lifted ? "3D" : "2D")"
            }
        }

        markers.onMarkers = { [weak self] samples in
            guard let self else { return }
            self.server?.send(PhoneWire.encode(.markers(samples)))
            let following = samples.filter(\.tracked)
            self.markersFound = !following.isEmpty
            if following.isEmpty {
                self.markerInfo = self.markerReferences.isEmpty
                    ? "nothing to look for yet"
                    : "looking for \(self.markerReferences.count)"
            } else {
                let names = following.prefix(3).map(\.name).joined(separator: ", ")
                self.markerInfo = "\(following.count) in view · \(names)"
            }
        }

        wand.onWand = { [weak self] sample in
            guard let self else { return }
            self.server?.send(PhoneWire.encode(.wand(sample)))
            self.wandTracked = sample.tracked
            var parts = [sample.tracked ? "tracking" : "finding its place…"]
            if sample.pressed { parts.append("pressed") }
            parts.append("\(sample.pressCount) presses")
            self.wandInfo = parts.joined(separator: " · ")
        }

        markers.onLibrary = { [weak self] library in
            guard let self else { return }
            self.markerReferences = library.references
            self.markerNotes = library.notes
        }

        // Every ARKit session estimates the light, so they all report to the same
        // handler and a mode switch never interrupts it. Selfie runs no ARKit
        // session and reports none.
        let reporters: [any LightReporting] = [ar, face, depth, seg, room, hands, text, markers, wand]
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
        // Only one camera session at a time, so every switch stops them all and then
        // starts the one it wants. One list, so a new mode can never forget one.
        stopAllSessions()
        switch mode {
        case .body:
            ar.start()
            status = bodySupported ? "Streaming body" : "This device doesn't support body tracking"
        case .face:
            face.start()
            status = faceSupported ? "Streaming face" : "This device doesn't support face tracking"
        case .world:
            depth.start()
            status = depthSupported ? "Streaming depth" : "This device has no LiDAR for depth"
        case .segment:
            seg.start()
            status = segSupported ? "Streaming segmentation" : "This device doesn't support person segmentation"
        case .selfie:
            selfie.start()
            status = selfieSupported
                ? "Streaming the front-camera person matte, mirrored like the preview"
                : "This device has no front camera"
        case .hands:
            handsTracked = false
            handsInfo = ""
            hands.start()
            status = handsLift
                ? "Streaming hand pose, lifted to 3D through the LiDAR depth"
                : "Streaming hand pose in 2D (this device has no LiDAR to lift it)"
        case .text:
            textTracked = false
            textInfo = ""
            text.start()
            status = textLift
                ? "Streaming the readable text, lifted to 3D through the LiDAR depth"
                : "Streaming the readable text in 2D (this device has no LiDAR to lift it)"
        case .markers:
            markersFound = false
            markerInfo = ""
            markers.start()
            status = "Looking for the pictures and objects in the app's own folder"
        case .wand:
            wandTracked = false
            wandInfo = ""
            wand.start()
            status = "Point the back of the phone at the sketch, and press the pad below"
        case .room:
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

    /// Read the reference folder again, so a picture dropped in over the cable while
    /// the app is running is looked for without a restart.
    func reloadMarkers() {
        guard mode == .markers else { return }
        markers.reload()
    }

    /// Stop every camera session. Safe on one that never started, so a mode switch
    /// calls it unconditionally.
    private func stopAllSessions() {
        ar.stop(); face.stop(); depth.stop(); seg.stop(); selfie.stop()
        room.stop(); hands.stop(); text.stop(); markers.stop(); wand.stop()
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

    /// Whether the thumb is on the wand pad, kept here because the gesture reports
    /// a change rather than a landing, and the first change after a release is what
    /// counts as a press.
    @State private var padPressed = false
    /// Where the thumb sits on the pad, in the pad's own points, for the marker.
    @State private var padPoint: CGPoint = .zero

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

                // Capture mode: one camera session at a time (rear: body/world/
                // segment/room/hands/text/markers/wand, front: face/selfie), so the
                // modes are mutually exclusive. Ten modes outgrew the segmented
                // control, so they wrap as four rows of chips.
                VStack(spacing: 8) {
                    modeRow([.body, .face, .world])
                    modeRow([.segment, .selfie, .room])
                    modeRow([.hands, .text, .markers])
                    modeRow([.wand], padTo: 3)
                }
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
                    case .selfie:
                        row("Person", streamer.selfieSupported
                            ? (streamer.selfieInfo.isEmpty ? "starting…"
                               : "streaming · \(streamer.selfieInfo)\(streamer.selfiePresent ? "" : " · nobody in view")")
                            : "no front camera",
                            ok: streamer.selfiePresent)
                    case .hands:
                        row("Hands", streamer.handsInfo.isEmpty
                            ? "looking for hands…"
                            : "streaming · \(streamer.handsInfo)",
                            ok: streamer.handsTracked)
                    case .text:
                        row("Text", streamer.textInfo.isEmpty
                            ? "looking for readable text…"
                            : "streaming · \(streamer.textInfo)",
                            ok: streamer.textTracked)
                    case .markers:
                        row("Markers", streamer.markerInfo.isEmpty
                            ? "reading the folder…"
                            : streamer.markerInfo,
                            ok: streamer.markersFound)
                        markerLibrary
                    case .wand:
                        row("Wand", streamer.wandInfo.isEmpty
                            ? "looking around the room…"
                            : streamer.wandInfo,
                            ok: streamer.wandTracked)
                    case .room:
                        row("Surface", streamer.meshSupported
                            ? (streamer.meshInfo.isEmpty ? "walk around to build it…" : "streaming · \(streamer.meshInfo)")
                            : "needs LiDAR (Pro)",
                            ok: streamer.meshTracked)
                        row("Planes", streamer.planeInfo.isEmpty
                            ? "looking for flat surfaces…" : "streaming · \(streamer.planeInfo)",
                            ok: !streamer.planeInfo.isEmpty)
                    }
                    row("Light", streamer.mode == .selfie
                        ? "paused (Selfie runs no ARKit)"
                        : (streamer.lightLive ? streamer.lightInfo : "measuring…"),
                        ok: streamer.mode != .selfie && streamer.lightLive)
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

                if streamer.mode == .wand { wandPad }

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

    /// What the phone is looking for: one line per reference file, what it assumed
    /// about a picture with no size in its name, and the button that reads the
    /// folder again after somebody drops a file in.
    private var markerLibrary: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(streamer.markerReferences) { reference in
                row(reference.kind == .object ? "Object" : "Picture",
                    reference.kind == .object
                        ? reference.name
                        : String(format: "%@ · %.0f cm%@", reference.name,
                                 reference.width * 100, reference.statedWidth ? "" : " (assumed)"),
                    ok: true)
            }
            ForEach(streamer.markerNotes, id: \.self) { note in
                Text(note)
                    .font(.caption)
                    .foregroundStyle(.orange.opacity(0.85))
                    .fixedSize(horizontal: false, vertical: true)
            }
            Button("Read the folder again") { streamer.reloadMarkers() }
                .font(.system(.caption, design: .rounded).weight(.semibold))
                .foregroundStyle(.white.opacity(0.9))
                .padding(.vertical, 6)
                .padding(.horizontal, 14)
                .background(Color.white.opacity(0.12), in: Capsule())
        }
    }

    /// The wand's button, and its second control. A wand is held pointing away from
    /// the person, so the screen is under the thumb and out of sight: the pad is
    /// therefore large, takes a press anywhere on it, and needs no aim. Sliding
    /// while held reports where the thumb is, which is the one extra axis a wand
    /// gets for nothing.
    private var wandPad: some View {
        GeometryReader { geometry in
            let size = geometry.size
            ZStack {
                RoundedRectangle(cornerRadius: 22)
                    .fill(Color.white.opacity(padPressed ? 0.22 : 0.07))
                RoundedRectangle(cornerRadius: 22)
                    .strokeBorder(Color.white.opacity(padPressed ? 0.5 : 0.15), lineWidth: 1.5)
                if padPressed {
                    Circle()
                        .fill(Color.white.opacity(0.9))
                        .frame(width: 26, height: 26)
                        .position(padPoint)
                } else {
                    Text("HOLD AND SLIDE")
                        .font(.system(.caption, design: .rounded).weight(.semibold))
                        .tracking(3)
                        .foregroundStyle(.white.opacity(0.35))
                }
            }
            .contentShape(RoundedRectangle(cornerRadius: 22))
            .gesture(
                // A minimum distance of zero makes the first change the landing, so
                // one gesture carries the press, the slide, and the release.
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        padPoint = value.location
                        let point = Self.padPoint(value.location, in: size)
                        if padPressed {
                            streamer.wand.slide(to: point)
                        } else {
                            padPressed = true
                            streamer.wand.press(at: point)
                        }
                    }
                    .onEnded { _ in
                        padPressed = false
                        streamer.wand.release()
                    }
            )
        }
        .frame(height: 170)
        .padding(.horizontal, 28)
    }

    /// Where a touch sits on the pad, as -1 to 1 across and -1 to 1 up, the middle
    /// at zero. The screen measures down and the wire carries up, so the y is
    /// turned over here.
    private static func padPoint(_ location: CGPoint, in size: CGSize) -> SIMD2<Float> {
        guard size.width > 0, size.height > 0 else { return .zero }
        let x = min(max(Float(location.x / size.width) * 2 - 1, -1), 1)
        let y = min(max(1 - Float(location.y / size.height) * 2, -1), 1)
        return SIMD2<Float>(x, y)
    }

    /// One row of mode chips: the same one-of-many choice a segmented control
    /// gives, drawn as capsules so ten modes fit across four rows. A short row
    /// pads with empty space rather than stretching, so every chip keeps the same
    /// width down the whole list.
    private func modeRow(_ modes: [CaptureMode], padTo width: Int = 0) -> some View {
        HStack(spacing: 8) {
            ForEach(modes) { mode in
                let selected = streamer.mode == mode
                Button(mode.rawValue) { streamer.setMode(mode) }
                    .font(.system(.subheadline, design: .rounded).weight(.semibold))
                    .foregroundStyle(selected ? Color.black : Color.white.opacity(0.85))
                    .padding(.vertical, 8)
                    .frame(maxWidth: .infinity)
                    .background(selected ? Color.white : Color.white.opacity(0.08),
                                in: Capsule())
            }
            ForEach(modes.count..<max(modes.count, width), id: \.self) { _ in
                Color.clear.frame(maxWidth: .infinity, maxHeight: 1)
            }
        }
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
