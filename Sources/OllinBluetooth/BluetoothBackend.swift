import Foundation

/// What the Mac's Bluetooth radio is doing.
public enum BluetoothRadioState: Sendable, Hashable {
    /// The system has not answered yet. It answers within a moment when it is
    /// going to, so a long wait here means the question about permission is
    /// still open. See `BluetoothDevice.unavailableReason`.
    case waiting
    /// This Mac has no Bluetooth Low Energy radio.
    case unsupported
    /// The system refuses Bluetooth to the app that started the sketch.
    case unauthorized
    /// The radio is turned off.
    case off
    /// The radio is on and usable.
    case on
}

/// A device the Mac can see.
public struct BluetoothPeripheral: Sendable, Hashable, Identifiable {

    /// The identifier this Mac uses for the device. It is the same on every
    /// run on this Mac, and different on another Mac, so it is worth storing
    /// once a sketch has found the right device.
    public let id: UUID
    /// The name the device advertises, or `"unnamed"` when it advertises none.
    public let name: String
    /// Signal strength in dBm. It is a negative number, and the closer to
    /// zero the closer the device: -40 is in your hand, -90 is across a room.
    public let signal: Int
    /// The services the device advertises. A device usually advertises only
    /// some of what it has, so this says what it wants to be found by.
    public let services: [BluetoothService]
    /// Whether the device is offering to be connected to at all.
    public let isConnectable: Bool
    /// When it was last heard from.
    public let lastSeen: Date

    public init(
        id: UUID,
        name: String,
        signal: Int,
        services: [BluetoothService] = [],
        isConnectable: Bool = true,
        lastSeen: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.signal = signal
        self.services = services
        self.isConnectable = isConnectable
        self.lastSeen = lastSeen
    }
}

/// What a connected device says one of its values can do.
struct BluetoothCharacteristicInfo: Sendable, Hashable {
    let id: BluetoothUUID
    /// The device can send this value on its own whenever it changes.
    let canNotify: Bool
    /// The value can be asked for.
    let canRead: Bool
    /// The value can be written.
    let canWrite: Bool
    /// Whether a write is acknowledged. A device that takes writes without
    /// an answer is faster and drops one under load.
    let wantsReply: Bool
}

/// Everything the radio tells the satellite.
enum BluetoothBackendEvent: Sendable {
    case radio(BluetoothRadioState)
    case found(BluetoothPeripheral)
    case ready(device: UUID, name: String, characteristics: [BluetoothCharacteristicInfo])
    case lost(device: UUID, reason: String?)
    case value(device: UUID, characteristic: BluetoothUUID, bytes: [UInt8])
}

/// The radio, behind a seam.
///
/// Everything above this line is ordinary Swift that a test can drive. Below
/// it sits CoreBluetooth, which needs a radio, a permission the system grants
/// once, and a second device in the room. Keeping the seam here is what lets
/// the whole reading path be proved with nothing switched on, the same way
/// the game-controller satellite reads a controller that is not plugged in.
protocol BluetoothBackend: AnyObject, Sendable {
    /// Starts the radio and takes the handler every event goes to. The
    /// handler is called on the backend's own queue, never on the main one.
    func begin(_ handler: @escaping @Sendable (BluetoothBackendEvent) -> Void)
    /// Looks for devices. An empty list looks for everything.
    func scan(for services: [BluetoothUUID], allowingRepeats: Bool)
    func stopScan()
    func connect(_ device: UUID)
    func disconnect(_ device: UUID)
    /// Asks the device to send a value whenever it changes.
    func notify(_ wanted: Bool, _ characteristic: BluetoothUUID, on device: UUID)
    /// Asks for a value once, now.
    func read(_ characteristic: BluetoothUUID, on device: UUID)
    func write(_ bytes: [UInt8], to characteristic: BluetoothUUID, on device: UUID)
}
