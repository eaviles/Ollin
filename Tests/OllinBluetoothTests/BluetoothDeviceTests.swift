import Foundation
import Testing
import Ollin
@testable import OllinBluetooth

/// The whole reading path, driven by a stand-in radio: finding the right
/// device, connecting, asking about what it carries, the value cache, the
/// drain, a bound knob, writing, polling, and coming back after a device is
/// carried out of the room. No radio, no second device, no GPU.
@Suite @MainActor
struct BluetoothDeviceTests {

    /// A device already connected and telling about its heart rate, which is
    /// where most of these tests start.
    func connectedStrap() -> (BluetoothDevice, FakeRadio, UUID) {
        let radio = FakeRadio()
        let device = BluetoothDevice(target: .name("strap"), backend: radio)
        let id = UUID()
        device.connect()
        radio.powerOn()
        radio.advertise(id, name: "Heart Strap 7")
        radio.present(id, name: "Heart Strap 7", [telling(.heartRateMeasurement)])
        return (device, radio, id)
    }

    // MARK: - Finding the right device

    @Test func nothingHappensUntilTheRadioSaysItIsOn() {
        let radio = FakeRadio()
        let device = BluetoothDevice(target: .name("strap"), backend: radio)
        device.connect()
        #expect(radio.didBegin)
        #expect(radio.scans.isEmpty)

        radio.powerOn()
        #expect(radio.scans.count == 1)
        #expect(device.radioState == .on)
    }

    @Test func onlyTheDeviceWithTheRightNameIsConnectedTo() {
        let radio = FakeRadio()
        let device = BluetoothDevice(target: .name("strap"), backend: radio)
        device.connect()
        radio.powerOn()

        let other = UUID()
        radio.advertise(other, name: "Somebody's headphones")
        #expect(radio.connects.isEmpty)

        let strap = UUID()
        // Case does not matter, and a part of the name is enough.
        radio.advertise(strap, name: "Heart Strap 7")
        #expect(radio.connects == [strap])
        // Looking stops once there is something to connect to.
        #expect(radio.stops == 1)
    }

    @Test func aServiceFindsGearThatAdvertisesNoUsefulName() {
        let radio = FakeRadio()
        let device = BluetoothDevice(target: .service(.heartRate), backend: radio)
        device.connect()
        radio.powerOn()

        // Asking the radio for one service is what finds a strap that
        // advertises itself as "unnamed".
        #expect(radio.scans.first?.services == [BluetoothService.heartRate.id])

        let strap = UUID()
        radio.advertise(strap, services: [.battery])
        #expect(radio.connects.isEmpty)
        radio.advertise(strap, services: [.heartRate])
        #expect(radio.connects == [strap])
    }

    @Test func oneExactDeviceIsFoundByItsIdentifier() {
        let radio = FakeRadio()
        let wanted = UUID()
        let device = BluetoothDevice(target: .id(wanted), backend: radio)
        device.connect()
        radio.powerOn()

        radio.advertise(UUID(), name: "Heart Strap 7")
        #expect(radio.connects.isEmpty)
        radio.advertise(wanted, name: "unnamed")
        #expect(radio.connects == [wanted])
    }

    @Test func onlyOneConnectionIsStartedHoweverOftenADeviceAdvertises() {
        let radio = FakeRadio()
        let device = BluetoothDevice(target: .name("strap"), backend: radio)
        device.connect()
        radio.powerOn()
        let strap = UUID()
        for _ in 0..<5 { radio.advertise(strap, name: "Heart Strap 7", signal: -55) }
        #expect(radio.connects == [strap])
        #expect(device.signal == -55)
    }

    // MARK: - Asking a connected device about itself

    @Test func aConnectedDeviceIsAskedAboutEverythingItOffers() {
        let radio = FakeRadio()
        let device = BluetoothDevice(target: .name("board"), backend: radio)
        device.connect()
        radio.powerOn()
        let board = UUID()
        radio.advertise(board, name: "My board")
        radio.present(board, name: "My board", [
            telling(.heartRateMeasurement),   // announces itself
            holding(.batteryLevel),           // must be asked
            taking(.uartOut),                 // written, never read
        ])

        #expect(device.isConnected)
        #expect(device.name == "My board")
        // Told about what announces itself.
        #expect(radio.notifies == [.init(
            wanted: true, characteristic: BluetoothCharacteristic.heartRateMeasurement.id,
            device: board)])
        // Read once, so a value the device never announces is there for the
        // first frame that asks for it.
        #expect(radio.readCount(of: .batteryLevel) == 1)
        #expect(radio.readCount(of: .heartRateMeasurement) == 1)
        #expect(radio.readCount(of: .uartOut) == 0)

        #expect(Set(device.characteristics.map(\.id)) == Set([
            BluetoothCharacteristic.heartRateMeasurement.id,
            BluetoothCharacteristic.batteryLevel.id,
            BluetoothCharacteristic.uartOut.id,
        ]))
    }

    @Test func namingOneValueNarrowsWhatTheDeviceIsAskedAbout() {
        let radio = FakeRadio()
        let device = BluetoothDevice(target: .name("board"), backend: radio)
        // Asked for before there is anything connected, which is where a
        // sketch says it: in `setup()`.
        device.subscribe(to: .batteryLevel)
        device.connect()
        radio.powerOn()
        let board = UUID()
        radio.advertise(board, name: "My board")
        radio.present(board, name: "My board", [
            telling(.heartRateMeasurement), telling(.batteryLevel),
        ])

        #expect(radio.notifies.map(\.characteristic) == [BluetoothCharacteristic.batteryLevel.id])
        #expect(radio.readCount(of: .heartRateMeasurement) == 0)
    }

    // MARK: - Reading

    @Test func theLatestValueIsThereEveryFrame() {
        let (device, radio, strap) = connectedStrap()
        radio.send([0x00, 72], of: .heartRateMeasurement, from: strap)

        #expect(device.number(.heartRateMeasurement) == 72)
        #expect(device.int(.heartRateMeasurement) == 72)
        #expect(device.bytes(.heartRateMeasurement) == [0x00, 72])
        #expect(device.bool(.heartRateMeasurement) == true)

        // Reading it again gives the same answer: the cache is not a queue.
        #expect(device.number(.heartRateMeasurement) == 72)

        radio.send([0x00, 61], of: .heartRateMeasurement, from: strap)
        #expect(device.number(.heartRateMeasurement) == 61)

        // Nothing has arrived for a value the device never sent.
        #expect(device.number(.batteryLevel) == nil)
        #expect(device.number(.batteryLevel, default: 100) == 100)
    }

    @Test func aValueCanBeReadADifferentWayThanItArrived() {
        let (device, radio, strap) = connectedStrap()
        radio.send([0x00, 72], of: .heartRateMeasurement, from: strap)
        // The same bytes, read as a plain first byte rather than as a heart
        // rate: the flags byte, which is zero.
        #expect(device.number(.heartRateMeasurement.read(as: .uint8)) == 0)
    }

    @Test func everythingSinceTheLastFrameDrainsInOrder() {
        let (device, radio, strap) = connectedStrap()
        for beats in [70, 71, 73] as [UInt8] {
            radio.send([0x00, beats], of: .heartRateMeasurement, from: strap)
        }

        let drained = device.readings()
        #expect(drained.map(\.int) == [70, 71, 73])
        #expect(drained.first?.characteristic.name == "Heart rate")
        // Drained means emptied.
        #expect(device.readings().isEmpty)
        // And the cache is untouched by the drain.
        #expect(device.number(.heartRateMeasurement) == 73)
    }

    @Test func aValueFromBeforeTheDeviceWasConnectedIsIgnored() {
        let radio = FakeRadio()
        let device = BluetoothDevice(target: .name("strap"), backend: radio)
        device.connect()
        radio.powerOn()
        let strap = UUID()
        radio.advertise(strap, name: "Heart Strap 7")

        // Nothing has said what this device carries yet.
        radio.send([0x00, 72], of: .heartRateMeasurement, from: strap)
        #expect(device.readings().isEmpty)
        #expect(device.number(.heartRateMeasurement) == nil)
    }

    @Test func undrainedReadingsAreCappedAndTheOldestGoFirst() {
        let (device, radio, strap) = connectedStrap()
        let total = BluetoothDevice.arrivalsLimit + 50
        for index in 0..<total {
            radio.send([0x00, UInt8(index % 200)], of: .heartRateMeasurement, from: strap)
        }
        let drained = device.readings()
        #expect(drained.count == BluetoothDevice.arrivalsLimit)
        // The newest survives; the first fifty are the ones dropped.
        #expect(drained.last?.int == (total - 1) % 200)
        #expect(drained.first?.int == 50 % 200)
    }

    // MARK: - Turning a knob

    @Test func aBoundKnobFollowsTheDeviceAndStaysInsideItsRange() {
        let (device, radio, strap) = connectedStrap()
        let knob = Param(wrappedValue: 0.0, 20...400)
        device.bind(.heartRateMeasurement, to: knob, from: 50...180)

        radio.send([0x00, 115], of: .heartRateMeasurement, from: strap)
        // Halfway along 50...180 is halfway along 20...400.
        #expect(abs(knob.wrappedValue - 210) < 1)

        // A reading past the range given stops at the knob's own end rather
        // than running out of it.
        radio.send([0x00, 220], of: .heartRateMeasurement, from: strap)
        #expect(knob.wrappedValue == 400)
        radio.send([0x00, 20], of: .heartRateMeasurement, from: strap)
        #expect(knob.wrappedValue == 20)

        device.unbind(.heartRateMeasurement)
        radio.send([0x00, 115], of: .heartRateMeasurement, from: strap)
        #expect(knob.wrappedValue == 20)
    }

    @Test func aValueWithNoNumberInItTurnsNoKnob() {
        let (device, radio, strap) = connectedStrap()
        let knob = Param(wrappedValue: 7.0, 0...10)
        let raw = BluetoothCharacteristic("ABCD")
        device.bind(raw, to: knob, from: 0...255)
        radio.send([0x01, 0x02], of: raw, from: strap)
        #expect(knob.wrappedValue == 7)
    }

    // MARK: - Writing

    @Test func writingReachesTheDevice() {
        let (device, radio, strap) = connectedStrap()
        device.write("led on\n", to: .uartOut)
        device.write([0x01, 0x02], to: .uartOut)
        // Nothing is a write of nothing.
        device.write([], to: .uartOut)

        #expect(radio.writes.count == 2)
        #expect(radio.writes.first?.bytes == Array("led on\n".utf8))
        #expect(radio.writes.first?.device == strap)
        #expect(radio.writes.last?.bytes == [0x01, 0x02])
    }

    @Test func writingWithNothingConnectedIsDroppedRatherThanQueued() {
        let radio = FakeRadio()
        let device = BluetoothDevice(target: .name("board"), backend: radio)
        device.connect()
        device.write("hello", to: .uartOut)
        #expect(radio.writes.isEmpty)
    }

    // MARK: - Asking again

    @Test func askingAgainOnATimerKeepsAskingByItself() async {
        let (device, radio, _) = connectedStrap()
        let before = radio.readCount(of: .batteryLevel)
        device.poll(.batteryLevel, every: 0.02)

        let asked = await waitUntil { radio.readCount(of: .batteryLevel) >= before + 3 }
        #expect(asked, "a poll should ask again on its own")
    }

    @Test func askingOnceAsksOnce() {
        let (device, radio, _) = connectedStrap()
        let before = radio.readCount(of: .batteryLevel)
        device.read(.batteryLevel)
        #expect(radio.readCount(of: .batteryLevel) == before + 1)
    }

    // MARK: - Coming and going

    @Test func aDeviceCarriedOutOfTheRoomIsLookedForAgain() async {
        let radio = FakeRadio()
        let device = BluetoothDevice(target: .name("strap"), backend: radio)
        device.retryInterval = 0.02
        device.connect()
        radio.powerOn()
        let strap = UUID()
        radio.advertise(strap, name: "Heart Strap 7")
        radio.present(strap, name: "Heart Strap 7", [telling(.heartRateMeasurement)])
        #expect(device.isConnected)

        radio.emit(.lost(device: strap, reason: "out of range"))
        #expect(!device.isConnected)

        let lookingAgain = await waitUntil { radio.scans.count >= 2 }
        #expect(lookingAgain, "a lost device should be looked for again")

        // And it connects again when it comes back.
        radio.advertise(strap, name: "Heart Strap 7")
        radio.present(strap, name: "Heart Strap 7", [telling(.heartRateMeasurement)])
        #expect(device.isConnected)
    }

    @Test func aConnectionThatNeverCompletesIsLookedForAgain() async {
        let radio = FakeRadio()
        let device = BluetoothDevice(target: .name("strap"), backend: radio)
        device.retryInterval = 0.02
        device.connect()
        radio.powerOn()
        let strap = UUID()
        radio.advertise(strap, name: "Heart Strap 7")
        #expect(radio.connects.count == 1)

        // The device was found and connecting was started, then it failed.
        // Nothing was ever connected, so this is the case a check against the
        // connected device alone would miss, and the sketch would wait for
        // ever without it.
        radio.emit(.lost(device: strap, reason: "could not connect"))
        let lookingAgain = await waitUntil { radio.scans.count >= 2 }
        #expect(lookingAgain, "a failed connection should be looked for again")

        radio.advertise(strap, name: "Heart Strap 7")
        #expect(radio.connects.count == 2)
    }

    @Test func lettingGoStopsEverythingAndLateNewsChangesNothing() {
        let (device, radio, strap) = connectedStrap()
        device.disconnect()

        #expect(!device.isConnected)
        #expect(radio.disconnects == [strap])

        // News from the session that just ended is dropped.
        radio.send([0x00, 72], of: .heartRateMeasurement, from: strap)
        #expect(device.readings().isEmpty)
        radio.emit(.radio(.off))
        #expect(device.radioState == .on)
    }

    // MARK: - When the radio is the problem

    @Test func theReasonSaysWhatIsWrongWithTheRadio() {
        let radio = FakeRadio()
        let device = BluetoothDevice(target: .name("strap"), backend: radio)
        device.connect()

        radio.emit(.radio(.off))
        #expect(device.unavailableReason?.contains("turned off") == true)
        #expect(!device.isAvailable)

        radio.emit(.radio(.unauthorized))
        #expect(device.unavailableReason?.contains("System Settings") == true)

        radio.emit(.radio(.unsupported))
        #expect(device.unavailableReason?.contains("no Bluetooth Low Energy radio") == true)

        radio.powerOn()
        #expect(device.unavailableReason == nil)
        #expect(device.isAvailable)
    }

    @Test func aRadioThatNeverAnswersSaysSoRatherThanWaitingInSilence() async {
        let radio = FakeRadio()
        let device = BluetoothDevice(target: .name("strap"), backend: radio)
        device.radioGrace = 0.02
        device.connect()

        // The first moment is an ordinary wait.
        #expect(device.unavailableReason == "Bluetooth has not answered yet.")

        // Past the grace it names the thing that is almost always the cause:
        // the question about permission has not been answered, and it cannot
        // be asked while the screen is locked.
        let said = await waitUntil {
            device.unavailableReason?.contains("screen is locked") == true
        }
        #expect(said)
        #expect(device.radioState == .waiting)
    }
}
