import CoreMIDI
import Foundation

/// A MIDI port on the system — a source you can receive from or a destination you
/// can send to. List them with `MIDIInput.sources` / `MIDIOutput.destinations` to
/// see what's connected and pick one by `name`.
///
/// ```swift
/// for endpoint in midi.sources { print(endpoint.name) }   // "Intech Studio: Grid", …
/// ```
public struct MIDIEndpoint: Sendable, Identifiable, Hashable {
    /// The endpoint's display name, e.g. `"Intech Studio: Grid"`.
    public let name: String
    /// The maker, when the device reports one.
    public let manufacturer: String?
    /// The underlying Core MIDI object reference (used internally to connect/send).
    let ref: MIDIEndpointRef

    /// A stable identity for the endpoint within a session.
    public var id: UInt32 { ref }

    init(_ ref: MIDIEndpointRef) {
        self.ref = ref
        self.name = MIDIEndpoint.stringProperty(ref, kMIDIPropertyDisplayName)
            ?? MIDIEndpoint.stringProperty(ref, kMIDIPropertyName)
            ?? "MIDI"
        self.manufacturer = MIDIEndpoint.stringProperty(ref, kMIDIPropertyManufacturer)
    }

    /// Reads a Core MIDI string property, or `nil` if it isn't set.
    static func stringProperty(_ object: MIDIObjectRef, _ property: CFString) -> String? {
        var value: Unmanaged<CFString>?
        guard MIDIObjectGetStringProperty(object, property, &value) == noErr,
              let value else { return nil }
        return value.takeRetainedValue() as String
    }

    public static func == (lhs: MIDIEndpoint, rhs: MIDIEndpoint) -> Bool { lhs.ref == rhs.ref }
    public func hash(into hasher: inout Hasher) { hasher.combine(ref) }
}

/// Errors thrown while opening Core MIDI.
public enum MIDIError: Error, Sendable {
    /// A Core MIDI call failed; carries the underlying `OSStatus`.
    case coreMIDI(OSStatus)
}
