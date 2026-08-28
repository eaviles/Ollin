import CoreBluetooth
import Foundation

/// The real radio, over CoreBluetooth.
///
/// One of these owns one system central manager. Everything happens on its
/// own queue, and everything it learns leaves through the one handler, so the
/// rest of the satellite never sees a CoreBluetooth type.
///
/// Two facts about the framework shape this file, and both cost a working
/// day when they are forgotten:
///
/// - **A peripheral must be held onto.** CoreBluetooth does not retain the
///   `CBPeripheral` it hands over, and a released one drops its connection
///   without saying anything. `found` keeps every one seen.
/// - **A short identifier does not print like a long one.** `CBUUID` gives
///   back `"180D"` for a standard value and the full 128-bit text for
///   anything else, so both are read through `BluetoothUUID`, which expands
///   the short form and makes the two spellings compare equal.
final class CoreBluetoothBackend: NSObject, BluetoothBackend, @unchecked Sendable {

    private let queue = DispatchQueue(label: "com.ollin.bluetooth")
    private var central: CBCentralManager?
    private var handler: (@Sendable (BluetoothBackendEvent) -> Void)?

    /// Every peripheral seen, held so a connection survives.
    private var found: [UUID: CBPeripheral] = [:]
    /// The characteristics of each connected peripheral, by identifier.
    private var characteristics: [UUID: [BluetoothUUID: CBCharacteristic]] = [:]
    /// How many services are still being looked through, per peripheral, so
    /// `ready` is announced once, when the last one has reported.
    private var pendingServices: [UUID: Int] = [:]

    /// A scan asked for before the radio was ready, replayed once it is.
    private var wantedScan: (services: [BluetoothUUID], repeats: Bool)?
    /// Connections asked for before the radio was ready.
    private var wantedConnections: Set<UUID> = []

    // MARK: - Backend

    func begin(_ handler: @escaping @Sendable (BluetoothBackendEvent) -> Void) {
        queue.async {
            guard self.central == nil else { return }
            self.handler = handler
            // Passing our own queue keeps every callback off the main thread,
            // which is the one the sketch draws on.
            self.central = CBCentralManager(delegate: self, queue: self.queue)
        }
    }

    func scan(for services: [BluetoothUUID], allowingRepeats: Bool) {
        queue.async {
            self.wantedScan = (services, allowingRepeats)
            self.applyScan()
        }
    }

    func stopScan() {
        queue.async {
            self.wantedScan = nil
            self.central?.stopScan()
        }
    }

    func connect(_ device: UUID) {
        queue.async {
            self.wantedConnections.insert(device)
            self.applyConnections()
        }
    }

    func disconnect(_ device: UUID) {
        queue.async {
            self.wantedConnections.remove(device)
            self.characteristics[device] = nil
            self.pendingServices[device] = nil
            guard let peripheral = self.found[device] else { return }
            self.central?.cancelPeripheralConnection(peripheral)
        }
    }

    func notify(_ wanted: Bool, _ characteristic: BluetoothUUID, on device: UUID) {
        queue.async {
            guard let peripheral = self.found[device],
                  let target = self.characteristics[device]?[characteristic] else { return }
            peripheral.setNotifyValue(wanted, for: target)
        }
    }

    func read(_ characteristic: BluetoothUUID, on device: UUID) {
        queue.async {
            guard let peripheral = self.found[device],
                  let target = self.characteristics[device]?[characteristic] else { return }
            peripheral.readValue(for: target)
        }
    }

    func write(_ bytes: [UInt8], to characteristic: BluetoothUUID, on device: UUID) {
        queue.async {
            guard let peripheral = self.found[device],
                  let target = self.characteristics[device]?[characteristic] else { return }
            // A device that acknowledges a write is told to; one that does not
            // takes the faster form, which is all it offers.
            let kind: CBCharacteristicWriteType =
                target.properties.contains(.write) ? .withResponse : .withoutResponse
            peripheral.writeValue(Data(bytes), for: target, type: kind)
        }
    }

    // MARK: - Applying what was asked for

    private func applyScan() {
        guard let central, central.state == .poweredOn, let wantedScan else { return }
        let services = wantedScan.services.isEmpty
            ? nil
            : wantedScan.services.map { CBUUID(string: $0.string) }
        central.scanForPeripherals(
            withServices: services,
            options: [CBCentralManagerScanOptionAllowDuplicatesKey: wantedScan.repeats])
    }

    private func applyConnections() {
        guard let central, central.state == .poweredOn else { return }
        for id in wantedConnections {
            guard let peripheral = found[id] else { continue }
            guard peripheral.state == .disconnected else { continue }
            central.connect(peripheral, options: nil)
        }
    }

    private func send(_ event: BluetoothBackendEvent) {
        handler?(event)
    }

    private static func state(of raw: CBManagerState) -> BluetoothRadioState {
        switch raw {
        case .poweredOn: return .on
        case .poweredOff: return .off
        case .unauthorized: return .unauthorized
        case .unsupported: return .unsupported
        case .unknown, .resetting: return .waiting
        @unknown default: return .waiting
        }
    }
}

// MARK: - Central manager

extension CoreBluetoothBackend: CBCentralManagerDelegate {

    func centralManagerDidUpdateState(_ manager: CBCentralManager) {
        send(.radio(CoreBluetoothBackend.state(of: manager.state)))
        guard manager.state == .poweredOn else { return }
        applyScan()
        applyConnections()
    }

    func centralManager(
        _ manager: CBCentralManager,
        didDiscover peripheral: CBPeripheral,
        advertisementData: [String: Any],
        rssi RSSI: NSNumber
    ) {
        found[peripheral.identifier] = peripheral

        let advertised = (advertisementData[CBAdvertisementDataServiceUUIDsKey] as? [CBUUID]) ?? []
        // The name in the advertisement is the one being broadcast now; the
        // peripheral's own name is a remembered one, so the advertised name
        // wins when both are there.
        let advertisedName = advertisementData[CBAdvertisementDataLocalNameKey] as? String
        let connectable = (advertisementData[CBAdvertisementDataIsConnectable] as? NSNumber)?.boolValue ?? true

        send(.found(BluetoothPeripheral(
            id: peripheral.identifier,
            name: advertisedName ?? peripheral.name ?? "unnamed",
            signal: RSSI.intValue,
            services: advertised.map { BluetoothService(BluetoothUUID($0.uuidString)) },
            isConnectable: connectable)))

        // A device asked for before it was ever seen can be connected now.
        if wantedConnections.contains(peripheral.identifier) { applyConnections() }
    }

    func centralManager(_ manager: CBCentralManager, didConnect peripheral: CBPeripheral) {
        peripheral.delegate = self
        characteristics[peripheral.identifier] = [:]
        pendingServices[peripheral.identifier] = nil
        // Nil asks for every service, which is what a sketch wants: it has no
        // list of what the device carries until the device says.
        peripheral.discoverServices(nil)
    }

    func centralManager(
        _ manager: CBCentralManager,
        didFailToConnect peripheral: CBPeripheral,
        error: Error?
    ) {
        send(.lost(device: peripheral.identifier, reason: error?.localizedDescription ?? "could not connect"))
    }

    func centralManager(
        _ manager: CBCentralManager,
        didDisconnectPeripheral peripheral: CBPeripheral,
        error: Error?
    ) {
        characteristics[peripheral.identifier] = nil
        pendingServices[peripheral.identifier] = nil
        send(.lost(device: peripheral.identifier, reason: error?.localizedDescription))
    }
}

// MARK: - One peripheral

extension CoreBluetoothBackend: CBPeripheralDelegate {

    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        let services = peripheral.services ?? []
        guard !services.isEmpty else {
            announceReady(peripheral)
            return
        }
        pendingServices[peripheral.identifier] = services.count
        for service in services {
            peripheral.discoverCharacteristics(nil, for: service)
        }
    }

    func peripheral(
        _ peripheral: CBPeripheral,
        didDiscoverCharacteristicsFor service: CBService,
        error: Error?
    ) {
        for characteristic in service.characteristics ?? [] {
            let id = BluetoothUUID(characteristic.uuid.uuidString)
            characteristics[peripheral.identifier, default: [:]][id] = characteristic
        }
        let remaining = (pendingServices[peripheral.identifier] ?? 1) - 1
        pendingServices[peripheral.identifier] = remaining
        guard remaining <= 0 else { return }
        pendingServices[peripheral.identifier] = nil
        announceReady(peripheral)
    }

    func peripheral(
        _ peripheral: CBPeripheral,
        didUpdateValueFor characteristic: CBCharacteristic,
        error: Error?
    ) {
        guard error == nil, let value = characteristic.value else { return }
        send(.value(
            device: peripheral.identifier,
            characteristic: BluetoothUUID(characteristic.uuid.uuidString),
            bytes: [UInt8](value)))
    }

    private func announceReady(_ peripheral: CBPeripheral) {
        let known = characteristics[peripheral.identifier] ?? [:]
        let described = known.map { id, characteristic in
            BluetoothCharacteristicInfo(
                id: id,
                canNotify: characteristic.properties.contains(.notify)
                    || characteristic.properties.contains(.indicate),
                canRead: characteristic.properties.contains(.read),
                canWrite: characteristic.properties.contains(.write)
                    || characteristic.properties.contains(.writeWithoutResponse),
                wantsReply: characteristic.properties.contains(.write))
        }
        send(.ready(
            device: peripheral.identifier,
            name: peripheral.name ?? "unnamed",
            characteristics: described))
    }
}
