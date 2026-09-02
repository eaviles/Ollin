import Foundation
import Ollin
import os

/// One value that arrived from a device.
public struct BluetoothReading: Sendable {

    /// Which value it is. A value the catalog names knows how to read itself;
    /// anything else comes back raw.
    public let characteristic: BluetoothCharacteristic
    /// The bytes exactly as the device sent them.
    public let bytes: [UInt8]
    /// When it arrived.
    public let time: Date

    public init(characteristic: BluetoothCharacteristic, bytes: [UInt8], time: Date = Date()) {
        self.characteristic = characteristic
        self.bytes = bytes
        self.time = time
    }

    /// The bytes as `Data`, for anything that wants them that way.
    public var data: Data { Data(bytes) }

    /// The value as a number, read the way its characteristic says, or `nil`
    /// when the bytes do not carry one.
    public var number: Double? { characteristic.format.number(from: bytes) }
    /// The value as a whole number.
    public var int: Int? { number.flatMap { Int(exactly: $0.rounded()) } }
    /// The value as text.
    public var text: String? { characteristic.format.text(from: bytes) }
    /// The value as on or off: any number above zero, or a first byte above
    /// zero when the value is raw bytes.
    public var isOn: Bool? {
        if let number { return number != 0 }
        return bytes.first.map { $0 != 0 }
    }
}

/// A Bluetooth device, read in `draw()`.
///
/// Say which device to look for, connect once in `setup()`, then read it every
/// frame. The three ways to read match how OSC, MIDI, and the serial port
/// already read:
///
/// ```swift
/// let strap = BluetoothDevice(named: "Strap")
///
/// override func setup() { strap.connect() }
///
/// override func draw() {
///     // 1. Continuous value: the latest reading, every frame.
///     let beats = strap.number(.heartRateMeasurement, default: 60)
///
///     // 2. Events: everything that arrived since the last frame.
///     for reading in strap.readings() { print(reading.characteristic, reading.number ?? 0) }
///
///     drawCircle(width / 2, height / 2, beats)
/// }
/// ```
///
/// Or bind a value straight onto a `@Param`, so a sensor drives the same
/// parameter a slider turns:
///
/// ```swift
/// @Param(20...400) var radius = 120.0
/// override func setup() {
///     strap.connect()
///     strap.bind(.heartRateMeasurement, to: $radius, from: 50...180)
/// }
/// ```
///
/// `connect()` never gives up. A device that is out of range, off, or carried
/// out of the room is waited for, and it is picked up again by itself when it
/// comes back. `isConnected` says where things stand, and `unavailableReason`
/// says why nothing is happening when the radio itself is the problem.
///
/// Values arrive on a background queue and the sketch reads them on the main
/// thread. Everything shared is held behind a lock, which is what makes that
/// safe.
public final class BluetoothDevice: @unchecked Sendable {

    /// Which device to look for.
    public enum Target: Sendable, Hashable {
        /// Any device whose advertised name contains this text, ignoring case.
        case name(String)
        /// The exact device, by the identifier this Mac gave it. Stable across
        /// runs on this Mac, and different on another one.
        case id(UUID)
        /// The first device that advertises this service, whatever it is
        /// called. The right choice for standard gear: any heart rate strap.
        case service(BluetoothService)
    }

    // MARK: - Stored state

    private let target: Target
    private let backend: BluetoothBackend
    private let queue = DispatchQueue(label: "com.ollin.bluetooth.device")

    private struct ParamBinding: Sendable {
        let param: Param<Double>
        let input: ClosedRange<Double>
    }

    private struct State: Sendable {
        var wantsConnection = false
        /// Bumped by `connect()` and `disconnect()`, so a late answer from a
        /// previous attempt falls through and changes nothing.
        var generation = 0
        var began: Date?
        var radio: BluetoothRadioState = .waiting
        var connectedTo: UUID?
        /// The device being connected to, before it has said what it carries.
        /// Held separately because a connection that fails must be noticed
        /// and looked for again, and a failure arrives before there is
        /// anything connected to compare it against.
        var connectingTo: UUID?
        var deviceName: String?
        var signal: Int?
        var offered: [BluetoothCharacteristicInfo] = []
        var latest: [BluetoothUUID: BluetoothReading] = [:]
        var arrivals: [BluetoothReading] = []
        var bindings: [BluetoothUUID: ParamBinding] = [:]
        /// What the sketch asked to be told about. Empty means everything the
        /// device offers to tell about.
        var wanted: Set<BluetoothUUID> = []
        var polls: [BluetoothUUID: Double] = [:]
        var noted = false
        /// Noted when the connection starts, on the main thread, so the reason
        /// can be read from anywhere afterwards.
        var headless = false
    }
    private let state = OSAllocatedUnfairLock(initialState: State())

    /// A cap on undrained readings, so a sketch that never calls `readings()`
    /// does not grow one buffer forever. The oldest go first.
    static let arrivalsLimit = 4096

    /// How long to wait before looking again after a device is lost. Short and
    /// constant: coming back quickly from a device carried out of range is the
    /// whole point. Set before `connect()`; the tests shorten it.
    var retryInterval: Double = 1

    /// How long the system may take to answer about Bluetooth before the wait
    /// is called out. It answers in well under a second when it is going to.
    /// Set before `connect()`; the tests shorten it.
    var radioGrace: Double = 3

    // MARK: - Lifecycle

    /// Looks for a device whose advertised name contains `named`, ignoring
    /// case, e.g. `BluetoothDevice(named: "Strap")`.
    public convenience init(named: String) {
        self.init(target: .name(named))
    }

    /// Looks for one exact device, by the identifier this Mac gave it (see
    /// `BluetoothScan`, or a `BluetoothPeripheral`'s `id`).
    public convenience init(id: UUID) {
        self.init(target: .id(id))
    }

    /// Looks for the first device that offers `service`, whatever it is
    /// called: any heart rate strap, any environment sensor.
    public convenience init(service: BluetoothService) {
        self.init(target: .service(service))
    }

    /// Looks for a device a scan already found.
    public convenience init(_ peripheral: BluetoothPeripheral) {
        self.init(target: .id(peripheral.id))
    }

    public convenience init(target: Target) {
        self.init(target: target, backend: CoreBluetoothBackend())
    }

    /// The one initializer everything else goes through. Tests hand it a
    /// backend of their own, which is how the whole reading path is proved
    /// with no radio and no second device in the room.
    init(target: Target, backend: BluetoothBackend) {
        self.target = target
        self.backend = backend
    }

    /// Starts looking for the device, and keeps looking. A device that is
    /// absent, out of range, or off is waited for, and one that goes away
    /// later is picked up again the same way. Safe to call twice.
    @MainActor
    public func connect() {
        if OllinApp.isRenderingHeadless {
            state.withLock {
                $0.radio = .unsupported
                $0.headless = true
            }
            return
        }
        let started: Int? = state.withLock {
            guard !$0.wantsConnection else { return nil }
            $0.wantsConnection = true
            $0.generation += 1
            $0.began = Date()
            return $0.generation
        }
        guard let started else { return }
        backend.begin { [weak self] event in
            self?.handle(event, generation: started)
        }
    }

    /// Lets the device go and stops looking for it. Safe to call when it was
    /// never connected.
    public func disconnect() {
        let connected: UUID? = state.withLock {
            $0.wantsConnection = false
            $0.generation += 1
            let id = $0.connectedTo ?? $0.connectingTo
            $0.connectedTo = nil
            $0.connectingTo = nil
            $0.offered = []
            return id
        }
        backend.stopScan()
        if let connected { backend.disconnect(connected) }
    }

    // MARK: - Where things stand

    /// Whether the device is connected right now. `connect()` keeps trying
    /// while this is false, so a sketch can draw a waiting state from it.
    public var isConnected: Bool { state.withLock { $0.connectedTo != nil } }

    /// The connected device's own name, or `nil` when nothing is connected.
    public var name: String? { state.withLock { $0.deviceName } }

    /// How strong the last advertisement was, in dBm. Closer to zero is
    /// closer to the Mac. `nil` until the device has been heard from.
    public var signal: Int? { state.withLock { $0.signal } }

    /// What the Mac's radio is doing.
    public var radioState: BluetoothRadioState { state.withLock { $0.radio } }

    /// Whether the radio can be used at all. This is about the Mac, not about
    /// the device: it stays `true` while a device is merely out of range.
    public var isAvailable: Bool { radioState == .on }

    /// Why the radio cannot be used, in a sentence a sketch can draw, or
    /// `nil` when nothing is wrong. It is about the Mac, not about the
    /// device, so it stays `nil` while a device is merely out of range.
    public var unavailableReason: String? {
        let read = state.withLock { ($0.radio, $0.began, $0.headless) }
        return bluetoothReason(read.0, began: read.1, grace: radioGrace, headless: read.2)
    }

    /// What the connected device offers, once it has said. Empty before that.
    /// Values the catalog names come back named and ready to read; anything
    /// else comes back raw, under its own number.
    public var characteristics: [BluetoothCharacteristic] {
        state.withLock { $0.offered }.map { BluetoothCharacteristic.standard(for: $0.id) }
    }

    // MARK: - Reading, the latest value

    /// The most recent reading of one value, or `nil` before the first one.
    public func latest(_ characteristic: BluetoothCharacteristic) -> BluetoothReading? {
        noteIfUnavailable()
        return state.withLock { $0.latest[characteristic.id] }
    }

    /// The most recent bytes of one value.
    public func bytes(_ characteristic: BluetoothCharacteristic) -> [UInt8]? {
        latest(characteristic)?.bytes
    }

    /// The most recent bytes of one value, as `Data`.
    public func data(_ characteristic: BluetoothCharacteristic) -> Data? {
        latest(characteristic)?.data
    }

    /// The most recent value as a number, read the way the characteristic
    /// given says. Pass a characteristic of your own with its own format to
    /// read a device the catalog does not name.
    public func number(_ characteristic: BluetoothCharacteristic) -> Double? {
        guard let reading = latest(characteristic) else { return nil }
        // Read by the format the caller asked for, which may differ from the
        // one the value arrived under.
        return characteristic.format.number(from: reading.bytes)
    }

    /// The most recent value as a whole number.
    public func int(_ characteristic: BluetoothCharacteristic) -> Int? {
        number(characteristic).flatMap { Int(exactly: $0.rounded()) }
    }

    /// The most recent value as text.
    public func text(_ characteristic: BluetoothCharacteristic) -> String? {
        guard let reading = latest(characteristic) else { return nil }
        return characteristic.format.text(from: reading.bytes)
    }

    /// The most recent value as on or off.
    public func bool(_ characteristic: BluetoothCharacteristic) -> Bool? {
        latest(characteristic)?.isOn
    }

    /// The most recent number, or `fallback` when nothing has arrived yet.
    public func number(_ characteristic: BluetoothCharacteristic, default fallback: Double) -> Double {
        number(characteristic) ?? fallback
    }

    /// The most recent whole number, or `fallback` when nothing has arrived.
    public func int(_ characteristic: BluetoothCharacteristic, default fallback: Int) -> Int {
        int(characteristic) ?? fallback
    }

    /// The most recent text, or `fallback` when nothing has arrived.
    public func text(_ characteristic: BluetoothCharacteristic, default fallback: String) -> String {
        text(characteristic) ?? fallback
    }

    // MARK: - Reading, the arrivals since the last frame

    /// Every value that arrived since the last call, oldest first, and clears
    /// the list. Call it once a frame to handle each reading in turn, rather
    /// than only the newest.
    public func readings() -> [BluetoothReading] {
        noteIfUnavailable()
        return state.withLock {
            let drained = $0.arrivals
            $0.arrivals.removeAll(keepingCapacity: true)
            return drained
        }
    }

    // MARK: - Adjusting a parameter

    /// Drives a `@Param` parameter from a value the device sends: each reading is
    /// mapped from `from` into the parameter's own range.
    ///
    /// ```swift
    /// strap.bind(.heartRateMeasurement, to: $radius, from: 50...180)
    /// ```
    public func bind(
        _ characteristic: BluetoothCharacteristic,
        to param: Param<Double>,
        from input: ClosedRange<Double> = 0...1
    ) {
        state.withLock {
            $0.bindings[characteristic.id] = ParamBinding(param: param, input: input)
        }
    }

    /// Removes a binding made with `bind(_:to:from:)`.
    public func unbind(_ characteristic: BluetoothCharacteristic) {
        state.withLock { $0.bindings[characteristic.id] = nil }
    }

    // MARK: - Asking and telling

    /// Asks to be told about one value whenever it changes.
    ///
    /// Nothing needs this: a connected device is asked about everything it
    /// offers to tell about. Name one or more values here to be told about
    /// those only, which is worth doing for a device that talks a lot.
    public func subscribe(to characteristic: BluetoothCharacteristic) {
        let target = state.withLock { state -> UUID? in
            state.wanted.insert(characteristic.id)
            return state.connectedTo
        }
        guard let target else { return }
        backend.notify(true, characteristic.id, on: target)
    }

    /// Stops being told about one value.
    public func unsubscribe(from characteristic: BluetoothCharacteristic) {
        let target = state.withLock { state -> UUID? in
            state.wanted.remove(characteristic.id)
            return state.connectedTo
        }
        guard let target else { return }
        backend.notify(false, characteristic.id, on: target)
    }

    /// Asks for one value once, now. The answer arrives a moment later, like
    /// every other reading. Use this for a value a device holds but does not
    /// announce, such as its battery level.
    public func read(_ characteristic: BluetoothCharacteristic) {
        guard let target = state.withLock({ $0.connectedTo }) else { return }
        backend.read(characteristic.id, on: target)
    }

    /// Asks for one value again and again, every `seconds`. The right way to
    /// watch a value a device holds but never announces.
    public func poll(_ characteristic: BluetoothCharacteristic, every seconds: Double) {
        let generation: Int = state.withLock {
            $0.polls[characteristic.id] = max(0.1, seconds)
            return $0.generation
        }
        schedulePoll(characteristic.id, generation: generation)
    }

    /// Sends bytes to the device.
    public func write(_ bytes: [UInt8], to characteristic: BluetoothCharacteristic) {
        guard !bytes.isEmpty, let target = state.withLock({ $0.connectedTo }) else { return }
        backend.write(bytes, to: characteristic.id, on: target)
    }

    /// Sends text to the device as UTF-8, which is what a serial-over-
    /// Bluetooth board reads.
    public func write(_ text: String, to characteristic: BluetoothCharacteristic) {
        write(Array(text.utf8), to: characteristic)
    }

    // MARK: - What the radio says

    private func handle(_ event: BluetoothBackendEvent, generation: Int) {
        guard state.withLock({ $0.wantsConnection && $0.generation == generation }) else { return }

        switch event {
        case .radio(let radio):
            state.withLock { $0.radio = radio }
            if radio == .on { beginLooking() }

        case .found(let peripheral):
            guard matches(peripheral) else { return }
            let busy = state.withLock { state -> Bool in
                state.signal = peripheral.signal
                guard state.connectedTo == nil, state.connectingTo == nil else { return true }
                state.connectingTo = peripheral.id
                return false
            }
            guard !busy else { return }
            backend.stopScan()
            backend.connect(peripheral.id)

        case .ready(let device, let name, let offered):
            state.withLock {
                $0.connectedTo = device
                $0.connectingTo = nil
                $0.deviceName = name
                $0.offered = offered
            }
            settle(device, offered: offered, generation: generation)

        case .lost(let device, _):
            let wasOurs = state.withLock { state -> Bool in
                guard state.connectedTo == device || state.connectingTo == device else { return false }
                state.connectedTo = nil
                state.connectingTo = nil
                state.offered = []
                return true
            }
            guard wasOurs else { return }
            queue.asyncAfter(deadline: .now() + retryInterval) { [weak self] in
                guard let self,
                      self.state.withLock({ $0.wantsConnection && $0.generation == generation })
                else { return }
                self.beginLooking()
            }

        case .value(let device, let id, let bytes):
            store(bytes, of: id, from: device)
        }
    }

    /// Starts a scan shaped by what is being looked for. Asking the radio for
    /// one service filters at the radio, which is cheaper and finds gear that
    /// advertises no name at all.
    private func beginLooking() {
        switch target {
        case .service(let service):
            backend.scan(for: [service.id], allowingRepeats: false)
        case .name, .id:
            backend.scan(for: [], allowingRepeats: false)
        }
    }

    private func matches(_ peripheral: BluetoothPeripheral) -> Bool {
        switch target {
        case .name(let text):
            return peripheral.name.lowercased().contains(text.lowercased())
        case .id(let id):
            return peripheral.id == id
        case .service(let service):
            // A radio-side filter already narrowed this, but a device found
            // by an earlier scan can still arrive, so it is checked again.
            return peripheral.services.contains(service)
        }
    }

    /// Asks the device for everything worth having, once it is connected:
    /// tell me about what you announce, and let me see what you hold.
    private func settle(_ device: UUID, offered: [BluetoothCharacteristicInfo], generation: Int) {
        let (wanted, polls) = state.withLock { ($0.wanted, $0.polls) }
        for characteristic in offered {
            let asked = wanted.isEmpty || wanted.contains(characteristic.id)
            if characteristic.canNotify && asked {
                backend.notify(true, characteristic.id, on: device)
            }
            // One read of everything readable fills the cache, so a value a
            // device never announces is there for the first frame that asks.
            if characteristic.canRead && asked {
                backend.read(characteristic.id, on: device)
            }
        }
        for id in polls.keys {
            schedulePoll(id, generation: generation)
        }
    }

    private func schedulePoll(_ id: BluetoothUUID, generation: Int) {
        let interval = state.withLock { $0.polls[id] }
        guard let interval else { return }
        queue.asyncAfter(deadline: .now() + interval) { [weak self] in
            guard let self else { return }
            // Still wanted? A poll that was removed, or a session that ended,
            // simply stops rescheduling itself.
            let alive: (live: Bool, target: UUID?) = self.state.withLock {
                let live = $0.wantsConnection && $0.generation == generation && $0.polls[id] != nil
                return (live, $0.connectedTo)
            }
            guard alive.live else { return }
            if let target = alive.target { self.backend.read(id, on: target) }
            self.schedulePoll(id, generation: generation)
        }
    }

    private func store(_ bytes: [UInt8], of id: BluetoothUUID, from device: UUID) {
        let reading = BluetoothReading(
            characteristic: BluetoothCharacteristic.standard(for: id), bytes: bytes)

        // Stash under the lock, then adjust any bound parameter outside it, so the
        // parameter's own lock never nests under this one.
        let binding: ParamBinding? = state.withLock { state in
            guard state.connectedTo == device else { return nil }
            state.latest[id] = reading
            state.arrivals.append(reading)
            if state.arrivals.count > BluetoothDevice.arrivalsLimit {
                state.arrivals.removeFirst(state.arrivals.count - BluetoothDevice.arrivalsLimit)
            }
            return state.bindings[id]
        }
        guard let binding, let value = reading.number else { return }
        binding.param.wrappedValue = BluetoothDevice.map(
            value, from: binding.input, to: binding.param.range)
    }

    static func map(
        _ value: Double, from input: ClosedRange<Double>, to output: ClosedRange<Double>
    ) -> Double {
        let span = input.upperBound - input.lowerBound
        guard span != 0 else { return output.lowerBound }
        let t = (value - input.lowerBound) / span
        let mapped = output.lowerBound + t * (output.upperBound - output.lowerBound)
        return min(max(mapped, output.lowerBound), output.upperBound)
    }

    /// Says once, on the error output, why a sketch that is reading is
    /// getting nothing. A sketch reads every frame, so this must never repeat.
    private func noteIfUnavailable() {
        let shouldNote: Bool = state.withLock { state in
            guard state.wantsConnection, !state.noted, state.radio != .on else { return false }
            guard let began = state.began,
                  Date().timeIntervalSince(began) > radioGrace else { return false }
            state.noted = true
            return true
        }
        guard shouldNote, let reason = unavailableReason else { return }
        FileHandle.standardError.write(Data(
            "⚠️ OllinBluetooth: \(reason) The sketch runs, and reads nothing.\n".utf8))
    }

    deinit { disconnect() }
}
