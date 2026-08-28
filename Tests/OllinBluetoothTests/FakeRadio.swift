import Foundation
import os
@testable import OllinBluetooth

/// A radio the test drives.
///
/// It stands where CoreBluetooth stands, so everything above the seam runs
/// exactly as it ships: the same matching, the same connecting, the same
/// subscribing, the same cache and drain. A test says what the radio hears,
/// and reads back what the satellite asked the radio to do.
///
/// Events are delivered on the calling thread, which makes a test a plain
/// sequence with nothing to wait for. The two places the satellite waits on a
/// clock of its own (looking again after a device is lost, and polling) are
/// the only places a test waits, and both are shortened for it.
final class FakeRadio: BluetoothBackend, @unchecked Sendable {

    struct ScanRequest: Sendable, Equatable {
        var services: [BluetoothUUID]
        var repeats: Bool
    }
    struct NotifyRequest: Sendable, Equatable {
        var wanted: Bool
        var characteristic: BluetoothUUID
        var device: UUID
    }
    struct ReadRequest: Sendable, Equatable {
        var characteristic: BluetoothUUID
        var device: UUID
    }
    struct WriteRequest: Sendable, Equatable {
        var bytes: [UInt8]
        var characteristic: BluetoothUUID
        var device: UUID
    }

    struct Log: Sendable {
        var began = false
        var handler: (@Sendable (BluetoothBackendEvent) -> Void)?
        var scans: [ScanRequest] = []
        var stops = 0
        var connects: [UUID] = []
        var disconnects: [UUID] = []
        var notifies: [NotifyRequest] = []
        var reads: [ReadRequest] = []
        var writes: [WriteRequest] = []
    }

    let log = OSAllocatedUnfairLock(initialState: Log())

    // MARK: - The seam

    func begin(_ handler: @escaping @Sendable (BluetoothBackendEvent) -> Void) {
        log.withLock {
            $0.began = true
            $0.handler = handler
        }
    }

    func scan(for services: [BluetoothUUID], allowingRepeats: Bool) {
        log.withLock { $0.scans.append(ScanRequest(services: services, repeats: allowingRepeats)) }
    }

    func stopScan() {
        log.withLock { $0.stops += 1 }
    }

    func connect(_ device: UUID) {
        log.withLock { $0.connects.append(device) }
    }

    func disconnect(_ device: UUID) {
        log.withLock { $0.disconnects.append(device) }
    }

    func notify(_ wanted: Bool, _ characteristic: BluetoothUUID, on device: UUID) {
        log.withLock {
            $0.notifies.append(
                NotifyRequest(wanted: wanted, characteristic: characteristic, device: device))
        }
    }

    func read(_ characteristic: BluetoothUUID, on device: UUID) {
        log.withLock { $0.reads.append(ReadRequest(characteristic: characteristic, device: device)) }
    }

    func write(_ bytes: [UInt8], to characteristic: BluetoothUUID, on device: UUID) {
        log.withLock {
            $0.writes.append(
                WriteRequest(bytes: bytes, characteristic: characteristic, device: device))
        }
    }

    // MARK: - What the test says the radio heard

    /// Delivers one event. The handler is read under the lock and called
    /// outside it, because what it does next is ask this same radio for
    /// something.
    func emit(_ event: BluetoothBackendEvent) {
        let handler = log.withLock { $0.handler }
        handler?(event)
    }

    /// Turns the radio on, which is what a real one reports a moment after it
    /// is started.
    func powerOn() { emit(.radio(.on)) }

    /// Says a device is in range.
    func advertise(
        _ id: UUID,
        name: String = "unnamed",
        signal: Int = -50,
        services: [BluetoothService] = [],
        at moment: Date = Date()
    ) {
        emit(.found(BluetoothPeripheral(
            id: id, name: name, signal: signal, services: services, lastSeen: moment)))
    }

    /// Says a device is connected and lists what it carries.
    func present(
        _ id: UUID,
        name: String = "a device",
        _ characteristics: [BluetoothCharacteristicInfo]
    ) {
        emit(.ready(device: id, name: name, characteristics: characteristics))
    }

    /// Says a device sent a value.
    func send(_ bytes: [UInt8], of characteristic: BluetoothCharacteristic, from device: UUID) {
        emit(.value(device: device, characteristic: characteristic.id, bytes: bytes))
    }

    // MARK: - Reading the log back

    var scans: [ScanRequest] { log.withLock { $0.scans } }
    var connects: [UUID] { log.withLock { $0.connects } }
    var disconnects: [UUID] { log.withLock { $0.disconnects } }
    var notifies: [NotifyRequest] { log.withLock { $0.notifies } }
    var reads: [ReadRequest] { log.withLock { $0.reads } }
    var writes: [WriteRequest] { log.withLock { $0.writes } }
    var stops: Int { log.withLock { $0.stops } }
    var didBegin: Bool { log.withLock { $0.began } }

    func readCount(of characteristic: BluetoothCharacteristic) -> Int {
        reads.filter { $0.characteristic == characteristic.id }.count
    }
}

/// A value that tells about itself and can be read.
func telling(_ characteristic: BluetoothCharacteristic) -> BluetoothCharacteristicInfo {
    BluetoothCharacteristicInfo(
        id: characteristic.id, canNotify: true, canRead: true, canWrite: false, wantsReply: false)
}

/// A value that must be asked for.
func holding(_ characteristic: BluetoothCharacteristic) -> BluetoothCharacteristicInfo {
    BluetoothCharacteristicInfo(
        id: characteristic.id, canNotify: false, canRead: true, canWrite: false, wantsReply: false)
}

/// A value that is written and never read.
func taking(_ characteristic: BluetoothCharacteristic) -> BluetoothCharacteristicInfo {
    BluetoothCharacteristicInfo(
        id: characteristic.id, canNotify: false, canRead: false, canWrite: true, wantsReply: true)
}

/// Waits until `probe` is true, or gives up. Polls rather than parking a
/// thread, so nothing in the concurrency pool is held while it waits.
func waitUntil(
    _ seconds: Double = 3,
    _ probe: @Sendable () -> Bool
) async -> Bool {
    let deadline = Date().addingTimeInterval(seconds)
    while Date() < deadline {
        if probe() { return true }
        try? await Task.sleep(nanoseconds: 3_000_000)
    }
    return probe()
}
