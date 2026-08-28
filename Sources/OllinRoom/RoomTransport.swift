// RoomTransport: the seam between the room and the wire under it.
//
// The room itself only knows how to keep members, decode frames, and hold
// values. Everything about *how* the bytes travel lives behind this protocol, so
// the local-network transport is one implementation and a test (or a sketch that
// wants two rooms in one process) can supply another with no socket at all.

import Foundation

/// What a transport tells the room, always from its own queue and never from the
/// main thread.
public struct RoomTransportHandler: Sendable {
    /// One message arrived from a named peer.
    public var received: @Sendable (Data, String) -> Void
    /// The set of connected peers changed.
    public var peersChanged: @Sendable ([String]) -> Void
    /// Something went wrong, or `nil` when the trouble cleared.
    public var problem: @Sendable (String?) -> Void

    public init(
        received: @escaping @Sendable (Data, String) -> Void,
        peersChanged: @escaping @Sendable ([String]) -> Void,
        problem: @escaping @Sendable (String?) -> Void
    ) {
        self.received = received
        self.peersChanged = peersChanged
        self.problem = problem
    }
}

/// A way for one room to reach the others.
public protocol RoomTransport: AnyObject, Sendable {
    /// The name this machine goes by.
    var peerName: String { get }
    /// The peers currently connected, in no particular order.
    var connectedPeers: [String] { get }
    /// Starts looking for the room and answering others who look for it.
    func start(_ handler: RoomTransportHandler)
    /// Stops, and drops every connection.
    func stop()
    /// Sends one message. An empty `peers` means everybody.
    /// `reliable` false is for a value sent every frame, where the newest one
    /// matters more than the one that went missing.
    func send(_ data: Data, reliable: Bool, to peers: [String])
}
