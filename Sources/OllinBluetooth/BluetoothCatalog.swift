import Foundation

// MARK: - Services

/// A group of related values on a device: its heart rate, its battery, its
/// weather readings. A device advertises the services it has, which is how a
/// sketch finds the right device without knowing its name.
public struct BluetoothService: Hashable, Sendable, CustomStringConvertible {

    public let id: BluetoothUUID
    /// A plain name for the group, used only in what a sketch prints or draws.
    public let name: String

    public init(_ uuid: String, name: String = "") {
        id = BluetoothUUID(uuid)
        self.name = name.isEmpty ? id.description : name
    }

    public init(_ uuid: BluetoothUUID, name: String = "") {
        id = uuid
        self.name = name.isEmpty ? uuid.description : name
    }

    public var description: String { name }

    // The standard's own groups, by their assigned numbers.

    /// A heart rate strap or a watch band. Carries `heartRateMeasurement`.
    public static let heartRate = BluetoothService("180D", name: "Heart rate")
    /// How much charge the device has left. Carries `batteryLevel`.
    public static let battery = BluetoothService("180F", name: "Battery")
    /// Who made the device and which model it is.
    public static let deviceInformation = BluetoothService("180A", name: "Device information")
    /// Weather and room readings: temperature, humidity, pressure.
    public static let environmentalSensing = BluetoothService("181A", name: "Environment")
    /// The de facto serial line over Bluetooth, the one most maker boards
    /// speak. Read `uartIn`, write `uartOut`.
    public static let uart = BluetoothService(
        "6E400001-B5A3-F393-E0A9-E50E24DCCA9E", name: "Serial over Bluetooth")

    /// Every service this catalog names.
    public static let standard: [BluetoothService] = [
        .heartRate, .battery, .deviceInformation, .environmentalSensing, .uart,
    ]
}

// MARK: - Formats

/// How to read a characteristic's bytes as a number or as text.
///
/// Bluetooth sends a value as bytes and says nothing about what they mean, so
/// each characteristic carries the shape of its own value. The standard ones
/// in the catalog already know theirs; a device of your own says it once:
///
/// ```swift
/// let level = BluetoothCharacteristic("2A19", as: .uint8)
/// ```
///
/// Numbers arrive smallest byte first, which is what Bluetooth always uses.
public enum BluetoothFormat: Hashable, Sendable {
    /// Bytes only. `number` reads nothing; `bytes` and `data` still work.
    case raw
    /// A whole number that is never negative, `bytes` long, times `scale`.
    case unsigned(bytes: Int, scale: Double)
    /// A whole number that may be negative, `bytes` long, times `scale`.
    case signed(bytes: Int, scale: Double)
    /// A 32-bit decimal number.
    case float32
    /// UTF-8 text, e.g. a maker's name.
    case text
    /// The heart rate reading, whose first byte says how wide the rest is.
    case heartRate

    public static let uint8 = BluetoothFormat.unsigned(bytes: 1, scale: 1)
    public static let uint16 = BluetoothFormat.unsigned(bytes: 2, scale: 1)
    public static let uint32 = BluetoothFormat.unsigned(bytes: 4, scale: 1)
    public static let int8 = BluetoothFormat.signed(bytes: 1, scale: 1)
    public static let int16 = BluetoothFormat.signed(bytes: 2, scale: 1)
    public static let int32 = BluetoothFormat.signed(bytes: 4, scale: 1)

    /// Reads `bytes` as this format, or `nil` when there are too few of them.
    public func number(from bytes: [UInt8]) -> Double? {
        switch self {
        case .raw, .text:
            return nil

        case .unsigned(let width, let scale):
            guard let raw = BluetoothFormat.whole(bytes, width: width) else { return nil }
            return Double(raw) * scale

        case .signed(let width, let scale):
            // Eight signed bytes have no room left for the sign to fold into,
            // and Bluetooth does not use that width, so it is refused here.
            guard width < 8, let raw = BluetoothFormat.whole(bytes, width: width) else { return nil }
            // Fold the top bit back into a negative number for this width.
            let span = UInt64(1) << UInt64(width * 8)
            let half = span / 2
            let signed = raw >= half ? Double(raw) - Double(span) : Double(raw)
            return signed * scale

        case .float32:
            guard let raw = BluetoothFormat.whole(bytes, width: 4) else { return nil }
            return Double(Float(bitPattern: UInt32(truncatingIfNeeded: raw)))

        case .heartRate:
            // The first byte is a set of flags; its lowest bit says whether
            // the rate that follows is one byte wide or two. A narrow reading
            // is two bytes in total, so it must not be read as a wide one.
            guard bytes.count >= 2 else { return nil }
            let rest = Array(bytes.dropFirst())
            if bytes[0] & 0x01 == 1 {
                return BluetoothFormat.uint16.number(from: rest)
            }
            return Double(rest[0])
        }
    }

    /// Reads `bytes` as text, for the formats that carry any.
    public func text(from bytes: [UInt8]) -> String? {
        guard case .text = self else { return nil }
        return String(bytes: bytes, encoding: .utf8)
    }

    /// The first `width` bytes as one whole number, smallest byte first.
    private static func whole(_ bytes: [UInt8], width: Int) -> UInt64? {
        guard width > 0, width <= 8, bytes.count >= width else { return nil }
        var value: UInt64 = 0
        for index in stride(from: width - 1, through: 0, by: -1) {
            value = (value << 8) | UInt64(bytes[index])
        }
        return value
    }
}

// MARK: - Characteristics

/// One value on a device: the heart rate it measures, the level of its
/// battery, a line of text from a board of your own.
///
/// The catalog below names the standard ones, each already knowing how to
/// read itself. Anything else takes its identifier and its format:
///
/// ```swift
/// let angle = BluetoothCharacteristic("2A0F-...", as: .float32, name: "Angle")
/// ```
public struct BluetoothCharacteristic: Hashable, Sendable, CustomStringConvertible {

    public let id: BluetoothUUID
    /// How to read the bytes. `.raw` keeps them as bytes.
    public let format: BluetoothFormat
    /// A plain name, used in what a sketch prints or draws.
    public let name: String

    public init(_ uuid: String, as format: BluetoothFormat = .raw, name: String = "") {
        id = BluetoothUUID(uuid)
        self.format = format
        self.name = name.isEmpty ? id.description : name
    }

    public init(_ uuid: BluetoothUUID, as format: BluetoothFormat = .raw, name: String = "") {
        id = uuid
        self.format = format
        self.name = name.isEmpty ? uuid.description : name
    }

    /// Two characteristics are the same value when they have the same
    /// identifier, whatever a sketch chose to call one of them. This is what
    /// lets `device.number(.batteryLevel)` find a value the device stored
    /// under a characteristic it discovered for itself.
    public static func == (lhs: Self, rhs: Self) -> Bool { lhs.id == rhs.id }
    public func hash(into hasher: inout Hasher) { hasher.combine(id) }

    public var description: String { name }

    /// The same value, read a different way.
    public func read(as format: BluetoothFormat) -> BluetoothCharacteristic {
        BluetoothCharacteristic(id, as: format, name: name)
    }

    // The standard's own values, by their assigned numbers and formats.

    /// Beats per minute, from a strap or a watch.
    public static let heartRateMeasurement = BluetoothCharacteristic(
        "2A37", as: .heartRate, name: "Heart rate")
    /// Where on the body the strap sits, as a number the standard defines.
    public static let bodySensorLocation = BluetoothCharacteristic(
        "2A38", as: .uint8, name: "Sensor position")
    /// Charge left, from 0 to 100.
    public static let batteryLevel = BluetoothCharacteristic(
        "2A19", as: .uint8, name: "Battery")
    /// Degrees Celsius.
    public static let temperature = BluetoothCharacteristic(
        "2A6E", as: .signed(bytes: 2, scale: 0.01), name: "Temperature")
    /// Relative humidity, as a percentage.
    public static let humidity = BluetoothCharacteristic(
        "2A6F", as: .unsigned(bytes: 2, scale: 0.01), name: "Humidity")
    /// Air pressure, in pascals.
    public static let pressure = BluetoothCharacteristic(
        "2A6D", as: .unsigned(bytes: 4, scale: 0.1), name: "Pressure")
    /// Who made the device.
    public static let manufacturerName = BluetoothCharacteristic(
        "2A29", as: .text, name: "Maker")
    /// Which model it is.
    public static let modelNumber = BluetoothCharacteristic(
        "2A24", as: .text, name: "Model")
    /// Which firmware it runs.
    public static let firmwareRevision = BluetoothCharacteristic(
        "2A26", as: .text, name: "Firmware")
    /// What a serial-over-Bluetooth board sends to the Mac.
    public static let uartIn = BluetoothCharacteristic(
        "6E400003-B5A3-F393-E0A9-E50E24DCCA9E", as: .text, name: "Serial in")
    /// What the Mac sends to a serial-over-Bluetooth board.
    public static let uartOut = BluetoothCharacteristic(
        "6E400002-B5A3-F393-E0A9-E50E24DCCA9E", as: .text, name: "Serial out")

    /// Every characteristic this catalog names.
    public static let standard: [BluetoothCharacteristic] = [
        .heartRateMeasurement, .bodySensorLocation, .batteryLevel,
        .temperature, .humidity, .pressure,
        .manufacturerName, .modelNumber, .firmwareRevision,
        .uartIn, .uartOut,
    ]

    /// The catalog entry for an identifier a device reported, so a value
    /// found by discovery still knows its name and its format. Anything not
    /// in the catalog comes back as raw bytes under its own number.
    public static func standard(for id: BluetoothUUID) -> BluetoothCharacteristic {
        standard.first { $0.id == id } ?? BluetoothCharacteristic(id)
    }
}
