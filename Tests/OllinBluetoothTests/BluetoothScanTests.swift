import Foundation
import Testing
@testable import OllinBluetooth

/// What is in the room: the list a sketch reads to find a device, and to draw
/// the signals around it.
@Suite @MainActor
struct BluetoothScanTests {

    @Test func theRoomIsListedStrongestFirst() {
        let radio = FakeRadio()
        let scan = BluetoothScan(service: nil, backend: radio)
        scan.start()
        radio.powerOn()

        radio.advertise(UUID(), name: "far", signal: -88)
        radio.advertise(UUID(), name: "near", signal: -41)
        radio.advertise(UUID(), name: "middle", signal: -60)

        #expect(scan.peripherals.map(\.name) == ["near", "middle", "far"])
        #expect(scan.isScanning)
        #expect(scan.isAvailable)
    }

    @Test func aDeviceHeardTwiceIsOneDeviceWithItsNewestSignal() {
        let radio = FakeRadio()
        let scan = BluetoothScan(service: nil, backend: radio)
        scan.start()
        radio.powerOn()

        let one = UUID()
        radio.advertise(one, name: "a strap", signal: -70)
        radio.advertise(one, name: "a strap", signal: -45)

        #expect(scan.peripherals.count == 1)
        #expect(scan.peripherals.first?.signal == -45)
    }

    @Test func aDeviceNotHeardFromIsForgotten() {
        let radio = FakeRadio()
        let scan = BluetoothScan(service: nil, backend: radio)
        scan.forgetAfter = 5
        scan.start()
        radio.powerOn()

        radio.advertise(UUID(), name: "here now", signal: -50)
        radio.advertise(
            UUID(), name: "gone", signal: -50, at: Date().addingTimeInterval(-30))

        #expect(scan.peripherals.map(\.name) == ["here now"])
    }

    @Test func theScanAsksForRepeatsSoASignalCanMove() {
        let radio = FakeRadio()
        let scan = BluetoothScan(service: nil, backend: radio)
        scan.start()
        radio.powerOn()

        // Without repeats the radio reports each device once and its signal
        // never changes again, which is the whole point of the list.
        #expect(scan.isScanning)
        #expect(radio.scans.count == 1)
        #expect(radio.scans.first?.repeats == true)
        #expect(radio.scans.first?.services.isEmpty == true)
    }

    @Test func lookingForOneKindOfGearFiltersAtTheRadio() {
        let radio = FakeRadio()
        let scan = BluetoothScan(service: .heartRate, backend: radio)
        scan.start()
        radio.powerOn()
        #expect(radio.scans.first?.services == [BluetoothService.heartRate.id])
    }

    @Test func stoppingForgetsTheRoom() {
        let radio = FakeRadio()
        let scan = BluetoothScan(service: nil, backend: radio)
        scan.start()
        radio.powerOn()
        radio.advertise(UUID(), name: "a strap", signal: -50)
        #expect(scan.peripherals.count == 1)

        scan.stop()
        #expect(!scan.isScanning)
        #expect(scan.peripherals.isEmpty)
        #expect(radio.stops == 1)

        // News from the scan that just ended changes nothing.
        radio.advertise(UUID(), name: "late", signal: -50)
        #expect(scan.peripherals.isEmpty)
    }

    @Test func theReasonIsAboutTheMacRatherThanAboutADevice() {
        let radio = FakeRadio()
        let scan = BluetoothScan(service: nil, backend: radio)
        scan.start()
        radio.emit(.radio(.off))
        #expect(scan.unavailableReason?.contains("turned off") == true)
        radio.powerOn()
        // On, and nothing found yet, is not a problem to report.
        #expect(scan.unavailableReason == nil)
        #expect(scan.peripherals.isEmpty)
    }
}
