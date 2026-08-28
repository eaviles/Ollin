import Foundation
import Ollin
import os

/// Why the radio cannot be used, in a sentence a sketch can draw.
///
/// Shared by the device and the scan, because the answer is about the Mac
/// rather than about either of them.
///
/// The long wait is the one worth explaining. macOS asks the person once, per
/// app, before a program may use Bluetooth. Until that question is answered
/// the radio reports nothing at all, and the question cannot be shown while
/// the screen is locked, so a sketch left running on a locked Mac waits for
/// as long as it is left there.
func bluetoothReason(
    _ radio: BluetoothRadioState, began: Date?, grace: Double, headless: Bool
) -> String? {
    switch radio {
    case .on:
        return nil
    case .off:
        return "Bluetooth is turned off. Turn it on in Control Center."
    case .unsupported:
        return headless
            ? "A Bluetooth device is live input, so an export reads nothing from it."
            : "This Mac has no Bluetooth Low Energy radio."
    case .unauthorized:
        return "This Mac refuses Bluetooth to the app running the sketch. "
            + "Allow it in System Settings, under Privacy & Security, then Bluetooth."
    case .waiting:
        let waited = began.map { Date().timeIntervalSince($0) } ?? 0
        guard waited > grace else { return "Bluetooth has not answered yet." }
        return "Bluetooth has not answered in \(Int(waited)) seconds. macOS asks once, "
            + "per app, before a program may use Bluetooth, and it cannot ask while the "
            + "screen is locked. Unlock the screen and answer the question, or allow "
            + "Bluetooth for the app running the sketch in System Settings."
    }
}

/// What Bluetooth devices are in the room.
///
/// Start it once and read the list every frame. It is how a sketch finds the
/// name or the identifier to give a `BluetoothDevice`, and it draws well on
/// its own: a room full of signals, each one moving as somebody walks past.
///
/// ```swift
/// let scan = BluetoothScan()
///
/// override func setup() { scan.start() }
///
/// override func draw() {
///     background(.black)
///     for (row, device) in scan.devices.enumerated() {
///         drawText("\(device.name)  \(device.signal)", 40, 60 + Double(row) * 28)
///     }
/// }
/// ```
///
/// A device is dropped from the list when it has not been heard from for
/// `forgetAfter` seconds, so the list is what is here now rather than what
/// has ever been here.
public final class BluetoothScan: @unchecked Sendable {

    private let backend: BluetoothBackend

    private struct State: Sendable {
        var running = false
        var generation = 0
        var began: Date?
        var radio: BluetoothRadioState = .waiting
        var seen: [UUID: BluetoothPeripheral] = [:]
        /// Noted when the scan starts, on the main thread, so the reason can
        /// be read from anywhere afterwards.
        var headless = false
    }
    private let state = OSAllocatedUnfairLock(initialState: State())

    /// How long a device stays in the list after it was last heard from.
    /// A device advertises every second or two, so a few seconds of silence
    /// means it has gone.
    public var forgetAfter: Double = 10

    /// Only devices offering this service, or `nil` for everything around.
    /// Asking for one filters at the radio, which is cheaper and finds gear
    /// that advertises no name.
    private let service: BluetoothService?

    private static let radioGrace: Double = 3

    /// Looks for every device in range.
    public convenience init() {
        self.init(service: nil, backend: CoreBluetoothBackend())
    }

    /// Looks only for devices that offer one service.
    public convenience init(service: BluetoothService) {
        self.init(service: service, backend: CoreBluetoothBackend())
    }

    /// The one initializer everything else goes through. Tests hand it a
    /// backend of their own.
    init(service: BluetoothService?, backend: BluetoothBackend) {
        self.service = service
        self.backend = backend
    }

    /// Starts looking. Safe to call twice.
    ///
    /// An export has no room to look at, so a headless run reports the radio
    /// as absent instead of asking for a permission it cannot use.
    @MainActor
    public func start() {
        if OllinApp.isRenderingHeadless {
            state.withLock {
                $0.radio = .unsupported
                $0.headless = true
            }
            return
        }
        let started: Int? = state.withLock {
            guard !$0.running else { return nil }
            $0.running = true
            $0.generation += 1
            $0.began = Date()
            return $0.generation
        }
        guard let started else { return }
        backend.begin { [weak self] event in
            self?.handle(event, generation: started)
        }
    }

    /// Stops looking and forgets what was found.
    public func stop() {
        state.withLock {
            $0.running = false
            $0.generation += 1
            $0.seen = [:]
        }
        backend.stopScan()
    }

    /// Whether the scan is running.
    public var isScanning: Bool { state.withLock { $0.running } }

    /// Every device heard from lately, the strongest signal first.
    public var devices: [BluetoothPeripheral] {
        let cutoff = Date().addingTimeInterval(-forgetAfter)
        return state.withLock { $0.seen.values }
            .filter { $0.lastSeen > cutoff }
            .sorted { left, right in
                // Strongest first, and a stable order under equal signals so
                // the list does not shuffle while it is being read.
                left.signal == right.signal ? left.id.uuidString < right.id.uuidString
                    : left.signal > right.signal
            }
    }

    /// What the Mac's radio is doing.
    public var radioState: BluetoothRadioState { state.withLock { $0.radio } }

    /// Whether the radio can be used at all.
    public var isAvailable: Bool { radioState == .on }

    /// Why the radio cannot be used, in a sentence a sketch can draw.
    public var unavailableReason: String? {
        let read = state.withLock { ($0.radio, $0.began, $0.headless) }
        return bluetoothReason(
            read.0, began: read.1, grace: BluetoothScan.radioGrace, headless: read.2)
    }

    private func handle(_ event: BluetoothBackendEvent, generation: Int) {
        guard state.withLock({ $0.running && $0.generation == generation }) else { return }
        switch event {
        case .radio(let radio):
            state.withLock { $0.radio = radio }
            guard radio == .on else { return }
            // Repeats are wanted here and nowhere else: without them the
            // radio reports each device once and its signal never moves.
            backend.scan(for: service.map { [$0.id] } ?? [], allowingRepeats: true)

        case .found(let peripheral):
            state.withLock { $0.seen[peripheral.id] = peripheral }

        case .ready, .lost, .value:
            break
        }
    }

    deinit { stop() }
}
