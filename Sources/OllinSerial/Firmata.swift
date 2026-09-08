import Foundation
import Ollin
import os

/// A board running Firmata, driven over a `SerialPort` with no firmware of
/// your own. Firmata is the protocol behind StandardFirmata, the sketch the
/// board's own IDE ships under File > Examples > Firmata: upload that once,
/// and the board's pins answer to the Mac. Read analog and digital pins, write
/// digital, PWM, and servo values, and bind an analog pin to a `@Param`.
///
/// ```swift
/// let board = FirmataBoard(matching: "usbmodem")
/// override func setup() { board.open() }
/// override func draw() {
///     let level = board.analog(0, default: 0)     // A0, 0...1
///     let pressed = board.digital(2, default: false)
///     board.write(13, pressed)                     // the LED follows the button
///     board.write(9, level)                        // PWM on pin 9
///     board.write(10, angle: 90 + 90 * sin(time))  // a servo on pin 10
/// }
/// ```
///
/// Asking a pin is what turns it on: the first `analog(0)` puts A0 into
/// analog mode and asks the board to report it, the first `digital(2)` puts
/// pin 2 into input mode and asks for its port, and the first write to a pin
/// sets its mode. The board forgets everything when it resets (most hobby
/// boards reset when the port opens), so every mode and report asked so far is
/// restated whenever the board announces itself, and a replug just works.
///
/// The reads follow the port's own shape: the latest value, `nil` until one
/// arrives, or `messages()` for every decoded message since the last frame.
/// Bytes arrive on the port's background queue and the sketch reads on the
/// main thread, with the shared state behind a lock.
public final class FirmataBoard: @unchecked Sendable {

    /// The port under the board. Yours to inspect (`isOpen`) or close.
    public let port: SerialPort

    private struct AnalogBinding: Sendable {
        let param: Param<Double>
    }

    private struct State: Sendable {
        var parser = FirmataParser()
        var analog: [Int: Int] = [:]
        var digital: [Int: Bool] = [:]
        var modes: [Int: FirmataPinMode] = [:]
        var analogReports: Set<Int> = []
        var digitalReports: Set<Int> = []
        var messages: [FirmataMessage] = []
        var firmware: FirmataFirmware?
        var bindings: [Int: AnalogBinding] = [:]
        var samplingInterval: Int?
    }
    private let state = OSAllocatedUnfairLock(initialState: State())

    /// Decoded messages a sketch never drains are capped here.
    private static let messagesLimit = 4096

    /// The reading a 10-bit analog pin reports at full scale, which is what
    /// StandardFirmata sends.
    private static let analogScale = 1023.0

    // MARK: Lifecycle

    /// Wraps a port you built yourself.
    public init(port: SerialPort) {
        self.port = port
        port.byteSink = { [weak self] bytes in self?.ingest(bytes) }
        port.connectionSink = { [weak self] in self?.connected() }
    }

    /// The first device whose name or path contains `matching`, at
    /// StandardFirmata's own speed.
    public convenience init(matching name: String, baudRate: Int = 57600) {
        self.init(port: SerialPort(matching: name, baudRate: baudRate))
    }

    /// The device at `path`, at StandardFirmata's own speed.
    public convenience init(path: String, baudRate: Int = 57600) {
        self.init(port: SerialPort(path: path, baudRate: baudRate))
    }

    /// Opens the port (and keeps at it, as the port does) and asks the board
    /// to announce itself.
    public func open() { port.open() }

    /// Closes the port and stops reconnecting.
    public func close() { port.close() }

    /// Whether the port is open right now. The board itself has answered once
    /// `firmware` is set.
    public var isOpen: Bool { port.isOpen }

    /// What the board said it runs, once it has said so; `nil` until then.
    public var firmware: FirmataFirmware? { state.withLock { $0.firmware } }

    // MARK: Reading

    /// The latest reading of analog pin `pin` (A0 is 0) scaled to 0...1, or
    /// `nil` until one arrives. Asking puts the pin in analog mode and turns
    /// its reporting on.
    public func analog(_ pin: Int) -> Double? {
        wantAnalog(pin)
        return state.withLock { $0.analog[pin] }.map { Double($0) / Self.analogScale }
    }

    /// The latest reading of analog pin `pin`, or `fallback`.
    public func analog(_ pin: Int, default fallback: Double) -> Double {
        analog(pin) ?? fallback
    }

    /// The latest state of digital pin `pin`, or `nil` until its port has
    /// reported. The first ask puts the pin in input mode (`pullUp` for the
    /// board's own pull-up resistor, so a button to ground reads true when
    /// pressed) and turns its port's reporting on; a later ask leaves the
    /// mode as it is, so change it through `setMode` if you must.
    public func digital(_ pin: Int, pullUp: Bool = false) -> Bool? {
        wantDigital(pin, pullUp: pullUp)
        return state.withLock { $0.digital[pin] }
    }

    /// The latest state of digital pin `pin`, or `fallback`.
    public func digital(_ pin: Int, pullUp: Bool = false, default fallback: Bool) -> Bool {
        digital(pin, pullUp: pullUp) ?? fallback
    }

    /// Every message decoded since the last call, oldest first, and clears
    /// the queue: each analog reading, each digital pin that changed, text
    /// the firmware sent, the firmware announcement, and any other sysex.
    public func messages() -> [FirmataMessage] {
        state.withLock {
            let drained = $0.messages
            $0.messages.removeAll(keepingCapacity: true)
            return drained
        }
    }

    // MARK: Writing

    /// Sets digital pin `pin` high or low (its mode becomes output).
    public func write(_ pin: Int, _ value: Bool) {
        setMode(pin, .output)
        send(FirmataCodec.digitalWrite(pin: pin, value: value))
    }

    /// Sets the PWM duty of pin `pin`, 0...1 (its mode becomes PWM).
    public func write(_ pin: Int, _ level: Double) {
        setMode(pin, .pwm)
        let value = Int((min(max(level, 0), 1) * 255).rounded())
        send(FirmataCodec.analogWrite(pin: pin, value: value))
    }

    /// Moves a servo on pin `pin` to `angle` degrees, 0...180 (its mode
    /// becomes servo).
    public func write(_ pin: Int, angle: Double) {
        setMode(pin, .servo)
        let value = Int(min(max(angle, 0), 180).rounded())
        send(FirmataCodec.analogWrite(pin: pin, value: value))
    }

    /// Puts pin `pin` in `mode`. The reads and writes set modes on their own;
    /// this is for a mode they do not reach (a pull-up you want without
    /// reading yet, an output you will drive later).
    public func setMode(_ pin: Int, _ mode: FirmataPinMode) {
        let changed: Bool = state.withLock {
            guard $0.modes[pin] != mode else { return false }
            $0.modes[pin] = mode
            return true
        }
        if changed { send(FirmataCodec.setMode(pin: pin, mode: mode)) }
    }

    /// How often the board samples and reports its analog pins, in
    /// milliseconds (StandardFirmata's default is 19).
    public func setSamplingInterval(_ milliseconds: Int) {
        state.withLock { $0.samplingInterval = milliseconds }
        send(FirmataCodec.samplingInterval(milliseconds))
    }

    /// Sends text to the firmware as a string message.
    public func send(text: String) {
        send(FirmataCodec.string(text))
    }

    // MARK: Binding

    /// Drives a `@Param` from analog pin `pin`: each reading, 0...1, is mapped
    /// onto the parameter's own range and assigned.
    public func bind(analog pin: Int, to param: Param<Double>) {
        wantAnalog(pin)
        state.withLock { $0.bindings[pin] = AnalogBinding(param: param) }
    }

    /// Removes the binding on analog pin `pin`.
    public func unbind(analog pin: Int) {
        state.withLock { $0.bindings[pin] = nil }
    }

    // MARK: Asking for pins

    private func wantAnalog(_ pin: Int) {
        let fresh: Bool = state.withLock {
            guard !$0.analogReports.contains(pin) else { return false }
            $0.analogReports.insert(pin)
            $0.modes[pin] = nil   // the analog channel is not the digital pin number
            return true
        }
        if fresh { send(FirmataCodec.reportAnalog(pin: pin)) }
    }

    private func wantDigital(_ pin: Int, pullUp: Bool) {
        let port = pin / 8
        let (firstAsk, freshPort): (Bool, Bool) = state.withLock {
            let firstAsk = $0.modes[pin] == nil
            let freshPort = !$0.digitalReports.contains(port)
            $0.digitalReports.insert(port)
            return (firstAsk, freshPort)
        }
        if firstAsk { setMode(pin, pullUp ? .inputPullUp : .input) }
        if freshPort { send(FirmataCodec.reportDigital(port: port)) }
    }

    /// A fresh connection: ask the board what it runs, and restate every
    /// mode, report, and interval asked so far (a board that reset on open
    /// has forgotten them; one that did not is told again, harmlessly).
    private func connected() {
        send(FirmataCodec.firmwareQuery)
        restate()
    }

    private func restate() {
        let (modes, analogs, digitals, interval) = state.withLock {
            ($0.modes, $0.analogReports, $0.digitalReports, $0.samplingInterval)
        }
        for (pin, mode) in modes.sorted(by: { $0.key < $1.key }) {
            send(FirmataCodec.setMode(pin: pin, mode: mode))
        }
        for pin in analogs.sorted() { send(FirmataCodec.reportAnalog(pin: pin)) }
        for port in digitals.sorted() { send(FirmataCodec.reportDigital(port: port)) }
        if let interval { send(FirmataCodec.samplingInterval(interval)) }
    }

    private func send(_ bytes: [UInt8]) { port.write(bytes) }

    // MARK: The stream (port queue)

    private func ingest(_ chunk: [UInt8]) {
        let (updates, announced): ([(Param<Double>, Double)], Bool) = state.withLock { state in
            let decoded = state.parser.ingest(chunk)
            var updates: [(Param<Double>, Double)] = []
            var announced = false
            for message in decoded {
                switch message {
                case let .analog(pin, value):
                    state.analog[pin] = value
                    if let binding = state.bindings[pin] {
                        updates.append((binding.param, Double(value) / Self.analogScale))
                    }
                case let .digital(pin, value):
                    state.digital[pin] = value
                case let .firmware(firmware):
                    state.firmware = firmware
                    announced = true
                case .string, .sysex:
                    break
                }
            }
            state.messages.append(contentsOf: decoded)
            if state.messages.count > Self.messagesLimit {
                state.messages.removeFirst(state.messages.count - Self.messagesLimit)
            }
            return (updates, announced)
        }
        for (param, value) in updates {
            let range = param.range
            param.wrappedValue = range.lowerBound + value * (range.upperBound - range.lowerBound)
        }
        // The board just announced itself, so it just booted (or answered
        // the query): either way it should hear what has been asked of it.
        if announced { restate() }
    }
}

/// What a `FirmataBoard` heard, drained through `messages()`.
public enum FirmataMessage: Equatable, Sendable {
    /// Analog pin `pin` (A0 is 0) read `value`, 0...1023 on a 10-bit board.
    case analog(pin: Int, value: Int)
    /// Digital pin `pin` changed to `value`.
    case digital(pin: Int, value: Bool)
    /// Text the firmware sent.
    case string(String)
    /// The board announced what it runs.
    case firmware(FirmataFirmware)
    /// A sysex message the board does not decode: the command id and its
    /// 7-bit payload bytes.
    case sysex(command: UInt8, data: [UInt8])
}

/// What a board runs, as it reports it.
public struct FirmataFirmware: Equatable, Sendable {
    /// The firmware's name, "StandardFirmata.ino" for the stock sketch.
    public var name: String
    public var majorVersion: Int
    public var minorVersion: Int

    public init(name: String, majorVersion: Int, minorVersion: Int) {
        self.name = name
        self.majorVersion = majorVersion
        self.minorVersion = minorVersion
    }
}

/// A pin's mode, as Firmata numbers them.
public struct FirmataPinMode: RawRepresentable, Hashable, Sendable {
    public let rawValue: UInt8
    public init(rawValue: UInt8) { self.rawValue = rawValue }

    public static let input = FirmataPinMode(rawValue: 0x00)
    public static let output = FirmataPinMode(rawValue: 0x01)
    public static let analog = FirmataPinMode(rawValue: 0x02)
    public static let pwm = FirmataPinMode(rawValue: 0x03)
    public static let servo = FirmataPinMode(rawValue: 0x04)
    public static let inputPullUp = FirmataPinMode(rawValue: 0x0B)
}

/// The bytes of each message the board is sent, from the published protocol:
/// a command byte with the high bit set, then data bytes of seven bits, a
/// 14-bit value split low seven bits first.
enum FirmataCodec {
    static let startSysex: UInt8 = 0xF0
    static let endSysex: UInt8 = 0xF7

    static func setMode(pin: Int, mode: FirmataPinMode) -> [UInt8] {
        [0xF4, UInt8(pin & 0x7F), mode.rawValue]
    }

    static func reportAnalog(pin: Int, on: Bool = true) -> [UInt8] {
        [0xC0 | UInt8(pin & 0x0F), on ? 1 : 0]
    }

    static func reportDigital(port: Int, on: Bool = true) -> [UInt8] {
        [0xD0 | UInt8(port & 0x0F), on ? 1 : 0]
    }

    static func digitalWrite(pin: Int, value: Bool) -> [UInt8] {
        [0xF5, UInt8(pin & 0x7F), value ? 1 : 0]
    }

    /// The analog message for the first sixteen pins, and the extended form
    /// past them, which carries the pin number as data.
    static func analogWrite(pin: Int, value: Int) -> [UInt8] {
        let clamped = max(0, min(value, 0x3FFF))
        if pin < 16 {
            return [0xE0 | UInt8(pin), UInt8(clamped & 0x7F), UInt8((clamped >> 7) & 0x7F)]
        }
        return [startSysex, 0x6F, UInt8(pin & 0x7F),
                UInt8(clamped & 0x7F), UInt8((clamped >> 7) & 0x7F), endSysex]
    }

    static func samplingInterval(_ milliseconds: Int) -> [UInt8] {
        let clamped = max(1, min(milliseconds, 0x3FFF))
        return [startSysex, 0x7A, UInt8(clamped & 0x7F), UInt8((clamped >> 7) & 0x7F), endSysex]
    }

    static let firmwareQuery: [UInt8] = [startSysex, 0x79, endSysex]

    /// Text goes out as a string message, each byte as a low-seven, high-one
    /// pair.
    static func string(_ text: String) -> [UInt8] {
        var bytes: [UInt8] = [startSysex, 0x71]
        for byte in text.utf8 {
            bytes.append(byte & 0x7F)
            bytes.append((byte >> 7) & 0x7F)
        }
        bytes.append(endSysex)
        return bytes
    }

    /// Reassembles bytes sent as low-seven, high-one pairs.
    static func unpack7(_ data: some Collection<UInt8>) -> [UInt8] {
        var out: [UInt8] = []
        var pending: UInt8?
        for byte in data {
            if let low = pending {
                out.append(low | (byte << 7))
                pending = nil
            } else {
                pending = byte
            }
        }
        if let low = pending { out.append(low) }
        return out
    }
}

/// The board's side of the stream: a small state machine over the bytes, one
/// message at a time, that survives a chunk boundary anywhere and drops any
/// byte it cannot place (a stream joined mid-message resynchronizes at the
/// next command byte).
struct FirmataParser: Sendable {
    private var command: UInt8 = 0
    private var expected = 0
    private var data: [UInt8] = []
    private var inSysex = false
    /// Each digital port's last reported word, so a report becomes the pins
    /// that changed (and every pin, the first time a port reports).
    private var ports: [Int: Int] = [:]

    /// A sysex that never ends is capped here; the oldest bytes fall off.
    private let sysexLimit = 1024

    mutating func ingest(_ bytes: some Sequence<UInt8>) -> [FirmataMessage] {
        var messages: [FirmataMessage] = []
        for byte in bytes {
            if byte >= 0x80 {
                // A command byte ends whatever was pending.
                if inSysex {
                    if byte == FirmataCodec.endSysex, let message = sysex(data) {
                        messages.append(message)
                    }
                    inSysex = false
                    data.removeAll(keepingCapacity: true)
                    if byte == FirmataCodec.endSysex { continue }
                }
                data.removeAll(keepingCapacity: true)
                command = byte
                switch byte & 0xF0 {
                case 0xE0, 0x90: expected = 2
                case 0xC0, 0xD0: expected = 1
                default:
                    switch byte {
                    case 0xF0: inSysex = true; expected = 0
                    case 0xF4, 0xF5, 0xF9: expected = 2
                    default: expected = 0
                    }
                }
                continue
            }
            if inSysex {
                data.append(byte)
                if data.count > sysexLimit { data.removeFirst(data.count - sysexLimit) }
                continue
            }
            guard expected > 0 else { continue }
            data.append(byte)
            if data.count == expected {
                messages.append(contentsOf: complete())
                data.removeAll(keepingCapacity: true)
                expected = 0
            }
        }
        return messages
    }

    private mutating func complete() -> [FirmataMessage] {
        let value = Int(data[0]) | (Int(data[1]) << 7)
        switch command & 0xF0 {
        case 0xE0:
            return [.analog(pin: Int(command & 0x0F), value: value)]
        case 0x90:
            // A port's eight pins as bits: report the ones that changed, and
            // all of them the first time the port is heard from.
            let port = Int(command & 0x0F)
            let previous = ports[port]
            ports[port] = value
            var changes: [FirmataMessage] = []
            for bit in 0 ..< 8 {
                let now = value & (1 << bit) != 0
                if let previous, (previous & (1 << bit) != 0) == now { continue }
                changes.append(.digital(pin: port * 8 + bit, value: now))
            }
            return changes
        default:
            return []
        }
    }

    private func sysex(_ data: [UInt8]) -> FirmataMessage? {
        guard let id = data.first else { return nil }
        let payload = data.dropFirst()
        switch id {
        case 0x79:
            guard payload.count >= 2 else { return nil }
            let major = Int(payload[payload.startIndex]), minor = Int(payload[payload.startIndex + 1])
            let name = String(decoding: FirmataCodec.unpack7(payload.dropFirst(2)), as: UTF8.self)
            return .firmware(FirmataFirmware(name: name, majorVersion: major, minorVersion: minor))
        case 0x71:
            return .string(String(decoding: FirmataCodec.unpack7(payload), as: UTF8.self))
        case 0x6F:
            guard payload.count >= 2 else { return nil }
            var value = 0
            for (i, byte) in payload.dropFirst().enumerated() { value |= Int(byte & 0x7F) << (7 * i) }
            return .analog(pin: Int(payload[payload.startIndex]), value: value)
        default:
            return .sysex(command: id, data: Array(payload))
        }
    }
}
