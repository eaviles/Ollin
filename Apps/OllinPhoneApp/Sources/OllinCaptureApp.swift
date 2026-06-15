import SwiftUI
import ARKit
import simd

/// **Ollin Capture** — Ollin's own iPhone sensor app. The phone runs ARKit body
/// tracking on its Neural Engine and CoreMotion device motion, and streams both to
/// a tethered Mac over USB (usbmuxd → `PhoneWire.streamPort`), where an Ollin sketch
/// reads them in `draw()` via `OllinPhone`'s `PhoneDevice`. This is the own-app
/// successor to borrowing Record3D's RGBD feed — the sensor stream is ours end to end.
@main
struct OllinCaptureApp: App {
    var body: some Scene {
        WindowGroup { ContentView() }
    }
}

/// Owns the network server and the two sensor streamers, and publishes the live
/// status the screen shows. `@MainActor` — the AR/motion callbacks land on main.
@MainActor
final class SensorStreamer: ObservableObject {

    @Published var clientCount = 0
    @Published var bodyTracked = false
    @Published var jointCount = 0
    @Published var gravity = SIMD3<Float>(0, 0, 0)
    @Published var motionLive = false
    @Published var status = "Starting…"

    let bodySupported = ARBodyTrackingConfiguration.isSupported

    private var server: SensorServer?
    private let ar = ARStreamer()
    private let motion = MotionStreamer()
    private var started = false

    func start() {
        guard !started else { return }
        started = true
        UIApplication.shared.isIdleTimerDisabled = true   // keep streaming while idle

        do {
            let server = try SensorServer(port: PhoneWire.streamPort)
            server.onClientCountChange = { [weak self] count in
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
        ar.start()

        status = bodySupported ? "Streaming" : "This device doesn't support ARKit body tracking"
    }
}

struct ContentView: View {
    @StateObject private var streamer = SensorStreamer()

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

                // Status rows
                VStack(alignment: .leading, spacing: 12) {
                    row("Body", streamer.bodySupported
                        ? (streamer.bodyTracked ? "tracking · \(streamer.jointCount) joints" : "searching…")
                        : "unsupported on this device",
                        ok: streamer.bodyTracked)
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
