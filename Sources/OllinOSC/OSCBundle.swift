import Foundation

/// A wire-level OSC packet: either a single message or a bundle. This is what a
/// datagram carries and what `encode()` / `init(data:)` round-trip.
public enum OSCPacket: Sendable, Equatable {
    case message(OSCMessage)
    case bundle(OSCBundle)
}

/// An OSC bundle: a time tag plus a group of elements (messages, or nested
/// bundles) that belong together. The time tag says when they take effect —
/// usually `.immediate`.
///
/// ```swift
/// let frame = OSCBundle(.immediate, [
///     .message(OSCMessage("/x", 0.5)),
///     .message(OSCMessage("/y", 0.5)),
/// ])
/// sender.send(frame)
/// ```
public struct OSCBundle: Sendable, Equatable {
    /// When the contained elements should take effect.
    public var timeTag: OSCTimeTag
    /// The bundled elements, in order.
    public var elements: [OSCPacket]

    public init(_ timeTag: OSCTimeTag = .immediate, _ elements: [OSCPacket] = []) {
        self.timeTag = timeTag
        self.elements = elements
    }

    /// Builds a bundle of messages (the common case), all taking effect at
    /// `timeTag`.
    public init(_ timeTag: OSCTimeTag = .immediate, messages: [OSCMessage]) {
        self.timeTag = timeTag
        self.elements = messages.map { .message($0) }
    }
}
