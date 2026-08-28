import Foundation
import Testing
@testable import OllinBluetooth

/// The value layer: how an identifier is spelled, and how bytes become a
/// number. No radio, no device, no GPU, so these run everywhere.
@Suite
struct BluetoothValueTests {

    // MARK: - Identifiers

    @Test func aShortNumberIsTheLongOneWithTheStandardBaseAroundIt() {
        let short = BluetoothUUID("180D")
        #expect(short.isWellFormed)
        #expect(short.string == "0000180D-0000-1000-8000-00805F9B34FB")
        #expect(short == BluetoothUUID("0000180D-0000-1000-8000-00805F9B34FB"))
        #expect(short.shortNumber == 0x180D)
        // The short form is what it prints as, since that is how the standard
        // writes it and how a datasheet quotes it.
        #expect(short.description == "180D")
    }

    @Test func everySpellingOfOneIdentifierMeansTheSameThing() {
        let forms = ["180d", "0x180D", " 180D ", BluetoothUUID(short: 0x180D).string]
        for form in forms {
            #expect(BluetoothUUID(form) == BluetoothUUID("180D"), "\(form) should match")
        }
    }

    @Test func aLongIdentifierKeepsItsOwnDigits() {
        let uart = BluetoothUUID("6E400001-B5A3-F393-E0A9-E50E24DCCA9E")
        #expect(uart.isWellFormed)
        #expect(uart.shortNumber == nil)
        #expect(uart.description == "6E400001-B5A3-F393-E0A9-E50E24DCCA9E")
        // Dashes are punctuation, not information.
        #expect(BluetoothUUID("6e400001b5a3f393e0a9e50e24dcca9e") == uart)
    }

    @Test func textThatIsNotAnIdentifierSaysSo() {
        // Each of these is a real mistake: a character short, a letter that is
        // not a digit, dashes in the wrong places, and nothing at all.
        let wrong = [
            "180",
            "180Z",
            "6E4000-01B5A3-F393-E0A9-E50E24DCCA9E",
            "",
        ]
        for text in wrong {
            #expect(!BluetoothUUID(text).isWellFormed, "\"\(text)\" should not be well formed")
        }
        // And it matches nothing real, so a mistyped identifier is a device
        // that never answers rather than the wrong device answering.
        #expect(BluetoothUUID("180") != BluetoothUUID("180D"))
    }

    // MARK: - Formats

    @Test func wholeNumbersAreReadSmallestByteFirst() {
        #expect(BluetoothFormat.uint8.number(from: [0x64]) == 100)
        #expect(BluetoothFormat.uint16.number(from: [0x2C, 0x01]) == 300)
        #expect(BluetoothFormat.uint32.number(from: [0x01, 0x00, 0x00, 0x00]) == 1)
        // Bytes past the width are somebody else's field and are left alone.
        #expect(BluetoothFormat.uint8.number(from: [0x05, 0xFF]) == 5)
    }

    @Test func aNegativeNumberFoldsBackAtItsOwnWidth() {
        // -12.34 degrees, the standard's own temperature: a signed 16-bit
        // number of hundredths.
        #expect(BluetoothCharacteristic.temperature.format.number(from: [0x2E, 0xFB]) == -12.34)
        #expect(BluetoothFormat.int8.number(from: [0xFF]) == -1)
        #expect(BluetoothFormat.int16.number(from: [0xFF, 0xFF]) == -1)
        // A positive number near the top of its width stays positive.
        #expect(BluetoothFormat.int16.number(from: [0xFF, 0x7F]) == 32767)
    }

    @Test func theStandardScalesAreCarried() {
        #expect(BluetoothCharacteristic.humidity.format.number(from: [0x95, 0x15]) == 55.25)
        // Ordinary air, in tenths of a pascal: 1,013,250 of them.
        let pressure = BluetoothCharacteristic.pressure.format
            .number(from: [0x02, 0x76, 0x0F, 0x00])
        #expect(abs((pressure ?? 0) - 101325) < 0.001)
        #expect(BluetoothCharacteristic.batteryLevel.format.number(from: [0x64]) == 100)
    }

    @Test func aDecimalNumberIsReadAsOne() {
        #expect(BluetoothFormat.float32.number(from: [0x00, 0x00, 0xC0, 0x3F]) == 1.5)
    }

    @Test func theHeartRateSaysHowWideItIs() {
        // The lowest bit of the first byte is the whole trick: clear means the
        // rate is one byte, set means two. Reading a narrow one as wide is the
        // mistake this pins, and it would read a resting heart as hundreds.
        #expect(BluetoothCharacteristic.heartRateMeasurement.format.number(from: [0x00, 72]) == 72)
        #expect(BluetoothCharacteristic.heartRateMeasurement.format
            .number(from: [0x01, 0x2C, 0x01]) == 300)
        // Flags plus nothing is not a reading.
        #expect(BluetoothCharacteristic.heartRateMeasurement.format.number(from: [0x00]) == nil)

        // The case that separates a right reading from a lucky one: a narrow
        // rate with more fields after it. A strap that also sends the beat
        // intervals (flag 0x10) puts them straight after a one-byte rate, so
        // reading two bytes here would fold the first interval into the rate
        // and report 626 beats a minute for a resting 114.
        #expect(BluetoothCharacteristic.heartRateMeasurement.format
            .number(from: [0x10, 114, 0x02, 0x03]) == 114)
    }

    @Test func tooFewBytesIsNothingRatherThanAGuess() {
        #expect(BluetoothFormat.uint16.number(from: [0x01]) == nil)
        #expect(BluetoothFormat.uint32.number(from: [0x01, 0x02]) == nil)
        #expect(BluetoothFormat.float32.number(from: []) == nil)
        #expect(BluetoothFormat.raw.number(from: [0x01, 0x02]) == nil)
    }

    @Test func textIsReadOnlyWhereTextIsMeant() {
        let bytes = Array("Bright Wire Co".utf8)
        #expect(BluetoothCharacteristic.manufacturerName.format.text(from: bytes) == "Bright Wire Co")
        #expect(BluetoothFormat.uint8.text(from: bytes) == nil)
        #expect(BluetoothFormat.text.number(from: bytes) == nil)
    }

    // MARK: - The catalog

    @Test func aValueIsTheSameValueWhateverItIsCalled() {
        let mine = BluetoothCharacteristic("2A37", as: .uint8, name: "My own reading")
        // Same identifier, so it finds the same stored value, even though it
        // is named differently and read differently.
        #expect(mine == .heartRateMeasurement)
        #expect(mine.hashValue == BluetoothCharacteristic.heartRateMeasurement.hashValue)
        #expect(mine.format.number(from: [0x00, 72]) == 0)
    }

    @Test func aDiscoveredIdentifierComesBackNamedWhenTheStandardNamesIt() {
        let known = BluetoothCharacteristic.standard(for: BluetoothUUID("2A19"))
        #expect(known.name == "Battery")
        #expect(known.format == .uint8)

        // Anything else keeps its number and its bytes.
        let mine = BluetoothCharacteristic.standard(for: BluetoothUUID("ABCD"))
        #expect(mine.name == "ABCD")
        #expect(mine.format == .raw)
    }

    @Test func readingAValueADifferentWayKeepsItTheSameValue() {
        let asRaw = BluetoothCharacteristic.heartRateMeasurement.read(as: .raw)
        #expect(asRaw == .heartRateMeasurement)
        #expect(asRaw.name == "Heart rate")
        #expect(asRaw.format == .raw)
    }

    @Test func aReadingReadsItselfEveryWayItCan() {
        let beats = BluetoothReading(characteristic: .heartRateMeasurement, bytes: [0x00, 72])
        #expect(beats.number == 72)
        #expect(beats.int == 72)
        #expect(beats.isOn == true)
        #expect(beats.text == nil)
        #expect(beats.data == Data([0x00, 72]))

        // A raw value has no number, so on or off falls back to its first byte.
        let raw = BluetoothReading(characteristic: BluetoothCharacteristic("ABCD"), bytes: [0x00])
        #expect(raw.number == nil)
        #expect(raw.isOn == false)
    }

    @Test func everyCatalogEntryIsWellFormedAndDistinct() {
        let services = BluetoothService.standard.map(\.id)
        let characteristics = BluetoothCharacteristic.standard.map(\.id)
        let servicesAreWellFormed = services.allSatisfy(\.isWellFormed)
        let valuesAreWellFormed = characteristics.allSatisfy(\.isWellFormed)
        #expect(servicesAreWellFormed)
        #expect(valuesAreWellFormed)
        #expect(Set(services).count == services.count)
        #expect(Set(characteristics).count == characteristics.count)
    }
}
