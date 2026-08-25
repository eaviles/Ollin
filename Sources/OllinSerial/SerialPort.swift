import Foundation
import Ollin
import os

/// Opens a serial device (a USB microcontroller, most anything under
/// `/dev/cu.*`) and surfaces what arrives as values a sketch reads in
/// `draw()`. Create one in `setup()`, `open()` it, then poll it.
///
/// Three ways to read, matching how OSC and MIDI already read:
///
/// ```swift
/// let serial = SerialPort(matching: "usbmodem", baudRate: 9600)
/// override func setup() { serial.open() }
/// override func draw() {
///     // 1. Continuous control: read the latest value each frame.
///     let level = serial.float(default: 0)
///
///     // 2. Discrete events: drain every line since the last frame.
///     for line in serial.lines() where line == "pressed" { trigger() }
/// }
/// ```
///
/// Or bind the stream straight onto a `@Param` knob (the third way), so a
/// sensor drives the same parameter a live-inspector slider does:
///
/// ```swift
/// @Param(20...400) var radius = 120.0
/// override func setup() {
///     serial.open()
///     serial.bind(to: $radius)   // numeric lines 0...1023 mapped into 20...400
/// }
/// ```
///
/// `open()` never gives up: a device that is missing, busy (mid-flash), or
/// unplugged later is simply waited for, and the port reconnects on its own
/// the moment it comes back. `isOpen` says where things stand. Framing stays
/// at text lines and raw bytes; higher protocols layer on top in sketch code
/// or an extension.
///
/// Bytes arrive on a background queue and the sketch reads on the main
/// thread; all shared state is held behind locks, which is what makes this
/// safe.
public final class SerialPort: @unchecked Sendable {

    // MARK: Stored state

    /// Which device to open: a fixed path, or a match re-resolved on every
    /// attempt, so a board plugged in later (or re-enumerating under a new
    /// number after a replug) is still found.
    private enum Target {
        case path(String)
        case match(String)
    }

    private let target: Target
    private let baudRate: Int
    private let queue = DispatchQueue(label: "com.ollin.serial.port")

    private struct ParamBinding: Sendable {
        let param: Param<Double>
        let input: ClosedRange<Double>
    }

    private struct State: Sendable {
        var wantsOpen = false
        /// Bumped by `open()` and `close()` so a stale retry or a stale read
        /// from a previous session falls through harmlessly.
        var generation = 0
        var latest: String?
        var lines: [String] = []
        var raw: [UInt8] = []
        var binding: ParamBinding?
    }
    private let state = OSAllocatedUnfairLock(initialState: State())

    /// The open descriptor and its read source. Non-Sendable, so it lives
    /// behind an unchecked lock; `nil` whenever the device is not open.
    private struct IO {
        var descriptor: Int32
        var source: DispatchSourceRead
    }
    private let io = OSAllocatedUnfairLock<IO?>(uncheckedState: nil)

    /// Reassembles lines on `queue` only; replaced on every (re)connection so
    /// a partial line from the previous session never leaks into the next.
    private var assembler = LineAssembler()

    /// Caps on undrained data, so a sketch that never calls `lines()` or
    /// `bytes()` doesn't grow the buffers without bound; the oldest entries
    /// are dropped past them.
    private static let linesLimit = 4096
    private static let rawLimit = 1 << 16

    /// How long a failed open waits before the next try. Short and constant,
    /// no backoff: the device is local, and coming back quickly from a cable
    /// bump or a firmware flash is the point.
    private static let retryInterval: Double = 1

    // MARK: Discovery

    /// Every serial device on this Mac right now, USB devices first. Pick one
    /// and pass its `path` (or the device itself) to the initializer.
    public static func availableDevices() -> [SerialDevice] {
        SerialDevice.discover()
    }

    // MARK: Lifecycle

    /// Creates a port for the device at `path`, e.g. `/dev/cu.usbmodem101`
    /// (see `availableDevices()`).
    public init(path: String, baudRate: Int = 9600) {
        self.target = .path(path)
        self.baudRate = baudRate
    }

    /// Creates a port for the first available device whose name or path
    /// contains `matching`, case-insensitively, e.g. `"usbmodem"`. The match
    /// re-runs on every connection attempt, so the board can be plugged in
    /// after `open()` or come back under a different device number.
    public init(matching: String, baudRate: Int = 9600) {
        self.target = .match(matching)
        self.baudRate = baudRate
    }

    /// Creates a port for a discovered device.
    public convenience init(device: SerialDevice, baudRate: Int = 9600) {
        self.init(path: device.path, baudRate: baudRate)
    }

    /// Whether the device is open right now. `open()` keeps trying while this
    /// is false, so a sketch can draw a waiting state from it.
    public var isOpen: Bool { io.withLock { $0 != nil } }

    /// Begins opening the device, and keeps at it: a device that is absent or
    /// busy is retried every second until it appears, and one that goes away
    /// later is reconnected the same way. Safe to call when already open.
    public func open() {
        let generation: Int? = state.withLock {
            guard !$0.wantsOpen else { return nil }
            $0.wantsOpen = true
            $0.generation += 1
            return $0.generation
        }
        guard let generation else { return }
        queue.async { [weak self] in self?.attempt(generation) }
    }

    /// Closes the device and stops reconnecting. Safe to call when not open.
    public func close() {
        state.withLock {
            $0.wantsOpen = false
            $0.generation += 1
        }
        dropDescriptor()
    }

    // MARK: Reading, polling cache

    /// The most recent complete line received, or `nil` before the first one.
    public var latestLine: String? {
        state.withLock { $0.latest }
    }

    /// The latest line as a `Float`, for the classic one-number-per-line
    /// sensor stream, or `nil` when nothing numeric has arrived.
    public func float() -> Float? { number().map(Float.init) }
    /// The latest line as an `Int`.
    public func int() -> Int? {
        guard let value = number() else { return nil }
        return Int(exactly: value.rounded())
    }
    /// The latest line as a `Bool`: `1`/`0`, `true`/`false`, or `on`/`off`.
    public func bool() -> Bool? {
        switch latestLine?.trimmingCharacters(in: .whitespaces).lowercased() {
        case "1", "true", "on": return true
        case "0", "false", "off": return false
        default: return nil
        }
    }

    /// The latest `Float`, or `fallback` if nothing numeric has arrived.
    public func float(default fallback: Float) -> Float { float() ?? fallback }
    /// The latest `Int`, or `fallback` if nothing numeric has arrived.
    public func int(default fallback: Int) -> Int { int() ?? fallback }
    /// The latest `Bool`, or `fallback` if nothing boolean has arrived.
    public func bool(default fallback: Bool) -> Bool { bool() ?? fallback }

    private func number() -> Double? {
        latestLine.flatMap(SerialPort.number(in:))
    }

    // MARK: Reading, event drain

    /// Returns every complete line received since the last call, oldest
    /// first, and clears the queue. Call it once per frame in `draw()` to
    /// handle discrete events in arrival order.
    public func lines() -> [String] {
        state.withLock {
            let drained = $0.lines
            $0.lines.removeAll(keepingCapacity: true)
            return drained
        }
    }

    /// Returns every raw byte received since the last call and clears the
    /// queue, for devices that speak a binary framing instead of text lines.
    /// Independent of `lines()`: draining one leaves the other alone.
    public func bytes() -> [UInt8] {
        state.withLock {
            let drained = $0.raw
            $0.raw.removeAll(keepingCapacity: true)
            return drained
        }
    }

    // MARK: Parameter binding

    /// Drives a `@Param` from the incoming stream: each line that parses as a
    /// number is mapped from `input` into the parameter's own range and
    /// assigned. The default input range is the classic 10-bit analog read.
    ///
    /// ```swift
    /// serial.bind(to: $radius)                 // 0...1023 into the param's range
    /// serial.bind(to: $level, from: 0...4095)  // a 12-bit sensor
    /// ```
    public func bind(to param: Param<Double>, from input: ClosedRange<Double> = 0...1023) {
        state.withLock { $0.binding = ParamBinding(param: param, input: input) }
    }

    /// Removes a binding previously set with `bind(to:from:)`.
    public func unbind() {
        state.withLock { $0.binding = nil }
    }

    // MARK: Writing

    /// Sends text to the device as UTF-8, exactly as given (no newline).
    public func write(_ text: String) { write(Array(text.utf8)) }

    /// Sends text followed by a newline, the same framing `lines()` reads on
    /// the way in.
    public func writeLine(_ text: String) { write(Array((text + "\n").utf8)) }

    /// Sends raw bytes. Writes go out on the port's background queue, so the
    /// frame never waits on the wire; bytes sent while the device is away are
    /// dropped (the reconnect path owns the device's comings and goings).
    public func write(_ bytes: [UInt8]) {
        guard !bytes.isEmpty else { return }
        queue.async { [weak self] in
            guard let self, let descriptor = self.io.withLock({ $0?.descriptor }) else { return }
            bytes.withUnsafeBufferPointer { buffer in
                guard var cursor = buffer.baseAddress else { return }
                var remaining = buffer.count
                var stalls = 0
                while remaining > 0 {
                    let written = Darwin.write(descriptor, cursor, remaining)
                    if written > 0 {
                        cursor += written
                        remaining -= written
                        stalls = 0
                        continue
                    }
                    if errno == EINTR { continue }
                    // A full kernel buffer gets a short, bounded grace; past
                    // it (or on any other error) the rest is dropped rather
                    // than wedging the read queue behind a blocked write.
                    if errno == EAGAIN, stalls < 50 {
                        stalls += 1
                        usleep(1000)
                        continue
                    }
                    return
                }
            }
        }
    }

    // MARK: Connecting (background queue)

    private func attempt(_ generation: Int) {
        guard state.withLock({ $0.wantsOpen && $0.generation == generation }) else { return }
        guard let path = resolvePath(),
              let descriptor = SerialPort.openDescriptor(path, baudRate: baudRate) else {
            scheduleRetry(generation)
            return
        }

        assembler.reset()
        let source = DispatchSource.makeReadSource(fileDescriptor: descriptor, queue: queue)
        source.setEventHandler { [weak self] in
            self?.readAvailable(descriptor, generation: generation)
        }
        // The descriptor closes when the source cancels (and only then), so
        // no read event can ever fire on an already-closed descriptor.
        source.setCancelHandler { _ = Darwin.close(descriptor) }
        io.withLock { $0 = IO(descriptor: descriptor, source: source) }
        source.activate()

        // `close()` may have landed between the check above and the store;
        // re-checking here closes that window.
        if !state.withLock({ $0.wantsOpen && $0.generation == generation }) {
            dropDescriptor()
        }
    }

    private func resolvePath() -> String? {
        switch target {
        case .path(let path):
            return path
        case .match(let needle):
            return SerialPort.firstPath(matching: needle, in: SerialDevice.discover())
        }
    }

    /// The path of the first device whose name or path contains `needle`,
    /// case-insensitively. Factored for the tests; `discover()` feeds it live.
    static func firstPath(matching needle: String, in devices: [SerialDevice]) -> String? {
        let lowered = needle.lowercased()
        return devices.first {
            $0.name.lowercased().contains(lowered) || $0.path.lowercased().contains(lowered)
        }?.path
    }

    /// Opens and configures the device: exclusive access (two readers on one
    /// port each get half the bytes, so a second open is refused instead),
    /// raw 8N1 at the requested speed, non-blocking. The termios application
    /// is best-effort: some drivers and pty pairs refuse parts of it, and a
    /// partly configured port still reads.
    private static func openDescriptor(_ path: String, baudRate: Int) -> Int32? {
        let descriptor = Darwin.open(path, O_RDWR | O_NOCTTY | O_NONBLOCK)
        guard descriptor >= 0 else { return nil }
        _ = ioctl(descriptor, TIOCEXCL)
        var settings = termios()
        if tcgetattr(descriptor, &settings) == 0 {
            cfmakeraw(&settings)
            settings.c_cflag |= tcflag_t(CLOCAL | CREAD)
            cfsetspeed(&settings, speed_t(baudRate))
            _ = tcsetattr(descriptor, TCSANOW, &settings)
        }
        tcflush(descriptor, TCIOFLUSH)
        return descriptor
    }

    private func readAvailable(_ descriptor: Int32, generation: Int) {
        var buffer = [UInt8](repeating: 0, count: 4096)
        while true {
            let count = read(descriptor, &buffer, buffer.count)
            if count > 0 {
                ingest(Array(buffer[..<count]), generation)
                continue
            }
            if count == 0 {
                // End of file: the device went away. Drop it and start
                // waiting for it to come back.
                disconnect(generation)
                return
            }
            if errno == EINTR { continue }
            if errno == EAGAIN { return }
            disconnect(generation)
            return
        }
    }

    private func ingest(_ chunk: [UInt8], _ generation: Int) {
        let newLines = assembler.ingest(chunk)
        // Stash under the lock and read out any binding, then apply the
        // binding outside the lock so the param's own lock never nests under
        // this one.
        let binding: ParamBinding? = state.withLock { state in
            guard state.generation == generation else { return nil }
            state.raw.append(contentsOf: chunk)
            if state.raw.count > Self.rawLimit {
                state.raw.removeFirst(state.raw.count - Self.rawLimit)
            }
            if !newLines.isEmpty {
                state.lines.append(contentsOf: newLines)
                if state.lines.count > Self.linesLimit {
                    state.lines.removeFirst(state.lines.count - Self.linesLimit)
                }
                state.latest = newLines.last
            }
            return newLines.isEmpty ? nil : state.binding
        }
        if let binding {
            for line in newLines {
                if let value = SerialPort.number(in: line) {
                    binding.param.wrappedValue = SerialPort.map(value, from: binding.input, to: binding.param.range)
                }
            }
        }
    }

    private func disconnect(_ generation: Int) {
        dropDescriptor()
        scheduleRetry(generation)
    }

    private func dropDescriptor() {
        let current = io.withLock { stored -> IO? in
            let value = stored
            stored = nil
            return value
        }
        current?.source.cancel()
    }

    private func scheduleRetry(_ generation: Int) {
        guard state.withLock({ $0.wantsOpen && $0.generation == generation }) else { return }
        queue.asyncAfter(deadline: .now() + SerialPort.retryInterval) { [weak self] in
            self?.attempt(generation)
        }
    }

    // MARK: Values

    /// The whole trimmed line as a number, or `nil`. One number per line is
    /// the framing the cache readers and `bind(to:from:)` understand.
    static func number(in line: String) -> Double? {
        Double(line.trimmingCharacters(in: .whitespaces))
    }

    private static func map(_ value: Double, from input: ClosedRange<Double>, to output: ClosedRange<Double>) -> Double {
        let span = input.upperBound - input.lowerBound
        guard span != 0 else { return output.lowerBound }
        let t = (value - input.lowerBound) / span
        return output.lowerBound + t * (output.upperBound - output.lowerBound)
    }

    deinit { close() }
}
