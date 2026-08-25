import Foundation
import IOKit
import IOKit.serial

/// A serial device present on this Mac, as listed by
/// `SerialPort.availableDevices()`.
public struct SerialDevice: Hashable, Identifiable, Sendable {
    /// The callout device path a `SerialPort` opens, e.g. `/dev/cu.usbmodem101`.
    public let path: String
    /// A human-readable name: the USB product name when the device carries one
    /// (as microcontroller boards do), otherwise the path's last component.
    public let name: String

    public var id: String { path }

    public init(path: String, name: String) {
        self.path = path
        self.name = name
    }
}

extension SerialDevice {
    /// Walks the IOKit registry for serial callout devices. USB devices sort
    /// first (they are almost always the ones a sketch wants), the built-in
    /// Bluetooth ports and the rest after, each group by path.
    static func discover() -> [SerialDevice] {
        var iterator: io_iterator_t = 0
        let matching = IOServiceMatching(kIOSerialBSDServiceValue)
        guard IOServiceGetMatchingServices(kIOMainPortDefault, matching, &iterator) == KERN_SUCCESS else {
            return []
        }
        defer { IOObjectRelease(iterator) }

        var found: [(device: SerialDevice, usb: Bool)] = []
        while true {
            let service = IOIteratorNext(iterator)
            guard service != 0 else { break }
            defer { IOObjectRelease(service) }
            guard let path = registryString(service, key: kIOCalloutDeviceKey) else { continue }
            let usbName = searchedString(service, key: "USB Product Name")
            let name = usbName ?? String(path.split(separator: "/").last ?? Substring(path))
            found.append((SerialDevice(path: path, name: name), usbName != nil))
        }
        return found
            .sorted { a, b in
                if a.usb != b.usb { return a.usb }
                return a.device.path < b.device.path
            }
            .map(\.device)
    }

    /// A property stored on the service entry itself (the device path lives there).
    private static func registryString(_ service: io_object_t, key: String) -> String? {
        IORegistryEntryCreateCFProperty(service, key as CFString, kCFAllocatorDefault, 0)?
            .takeRetainedValue() as? String
    }

    /// A property found by walking up the registry from the service (the USB
    /// product name lives on an ancestor entry, not on the serial client).
    private static func searchedString(_ service: io_object_t, key: String) -> String? {
        IORegistryEntrySearchCFProperty(
            service, kIOServicePlane, key as CFString, kCFAllocatorDefault,
            IOOptionBits(kIORegistryIterateRecursively | kIORegistryIterateParents)
        ) as? String
    }
}
