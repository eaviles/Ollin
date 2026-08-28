// LocalNetworkTransport: the room over the local network, with no server.
//
// Each machine both advertises the room and looks for it, so any two of them
// find each other on the same Wi-Fi (or a cable, or the direct radio link the
// system sets up when there is no network at all). Two rules keep that
// symmetry from working against itself:
//
//   1. Only the machine whose name sorts first invites the other. Both sides
//      see the other appear, and if both invite, two connections race and one of
//      them drops, which reads as a peer that joins and leaves forever.
//   2. The room name travels twice, in what is advertised and in the invitation,
//      and both sides check it. The service name the system advertises is capped
//      at 15 characters, so two long room names can share one, and without this
//      check two different pieces in one building would join each other.
//
// The name is the only thing a room asks for, so anyone on the network who knows
// it can join. A passcode is available for a venue where that matters; it never
// travels in the clear (only a hash of it does), and the session itself is
// encrypted.

import Foundation
import CryptoKit
@preconcurrency import MultipeerConnectivity
import os

/// The room over Multipeer Connectivity: zero configuration, no server, and no
/// address for anyone to type.
public final class LocalNetworkTransport: NSObject, RoomTransport, @unchecked Sendable {

    private let roomName: String
    private let serviceType: String
    private let passcodeToken: String
    private let identity: MCPeerID

    private struct Wiring {
        var session: MCSession?
        var advertiser: MCNearbyServiceAdvertiser?
        var browser: MCNearbyServiceBrowser?
        var peers: [String: MCPeerID] = [:]
        var handler: RoomTransportHandler?
    }
    private let wiring = OSAllocatedUnfairLock<Wiring>(uncheckedState: Wiring())

    /// The name this machine goes by in the room.
    public var peerName: String { identity.displayName }

    /// The peers currently connected.
    public var connectedPeers: [String] { wiring.withLock { Array($0.peers.keys) } }

    /// Creates the transport for a room name, optionally gated by a passcode.
    /// `as` overrides the name this machine shows, which otherwise is the
    /// computer's name plus a few characters that keep two sketches on one Mac
    /// apart.
    public init(room: String, as displayName: String? = nil, passcode: String? = nil) {
        roomName = room
        serviceType = RoomWire.serviceType(for: room)
        passcodeToken = LocalNetworkTransport.token(for: passcode)
        let name = displayName ?? RoomWire.peerName(
            host: ProcessInfo.processInfo.hostName,
            suffix: LocalNetworkTransport.randomSuffix()
        )
        identity = MCPeerID(displayName: String(name.prefix(60)))
        super.init()
    }

    // MARK: Lifecycle

    public func start(_ handler: RoomTransportHandler) {
        stop()

        let session = MCSession(peer: identity, securityIdentity: nil, encryptionPreference: .required)
        session.delegate = self

        let advertiser = MCNearbyServiceAdvertiser(
            peer: identity,
            discoveryInfo: ["room": roomName],
            serviceType: serviceType
        )
        advertiser.delegate = self

        let browser = MCNearbyServiceBrowser(peer: identity, serviceType: serviceType)
        browser.delegate = self

        wiring.withLock {
            $0.session = session
            $0.advertiser = advertiser
            $0.browser = browser
            $0.peers = [:]
            $0.handler = handler
        }

        advertiser.startAdvertisingPeer()
        browser.startBrowsingForPeers()
    }

    public func stop() {
        let old = wiring.withLock { current -> Wiring in
            let previous = current
            current = Wiring()
            return previous
        }
        old.advertiser?.stopAdvertisingPeer()
        old.browser?.stopBrowsingForPeers()
        old.session?.disconnect()
    }

    deinit { stop() }

    // MARK: Sending

    public func send(_ data: Data, reliable: Bool, to peers: [String]) {
        let ready = wiring.withLock { wiring -> (MCSession, [MCPeerID])? in
            guard let session = wiring.session else { return nil }
            let connected = Set(session.connectedPeers.map(\.displayName))
            let wanted = peers.isEmpty ? connected : Set(peers).intersection(connected)
            let targets = session.connectedPeers.filter { wanted.contains($0.displayName) }
            return targets.isEmpty ? nil : (session, targets)
        }
        guard let ready else { return }
        // An unreliable send is for a value repeated every frame, where the next
        // one is already on its way; a failure there is not worth reporting.
        try? ready.0.send(data, toPeers: ready.1, with: reliable ? .reliable : .unreliable)
    }

    // MARK: Helpers

    private func report(_ problem: String?) {
        wiring.withLock { $0.handler }?.problem(problem)
    }

    private func announcePeers() {
        let (handler, names) = wiring.withLock { wiring -> (RoomTransportHandler?, [String]) in
            (wiring.handler, Array(wiring.peers.keys))
        }
        handler?.peersChanged(names)
    }

    /// The invitation a joining machine sends: the room it means, and proof it
    /// knows the passcode when there is one.
    private func invitation() -> Data? {
        try? JSONSerialization.data(withJSONObject: ["room": roomName, "pass": passcodeToken])
    }

    private func invitationIsValid(_ context: Data?) -> Bool {
        // Our own invitations always carry the room name, so one that arrives
        // without it came from something else on this service name.
        guard let context,
              let fields = try? JSONSerialization.jsonObject(with: context) as? [String: String]
        else { return false }
        return fields["room"] == roomName && fields["pass"] == passcodeToken
    }

    /// A passcode never travels: this is what does.
    static func token(for passcode: String?) -> String {
        guard let passcode, !passcode.isEmpty else { return "" }
        let digest = SHA256.hash(data: Data(passcode.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    /// Four characters that keep two sketches on one machine apart.
    static func randomSuffix() -> String {
        let alphabet = Array("abcdefghijklmnopqrstuvwxyz0123456789")
        return String((0..<4).map { _ in alphabet[Int.random(in: 0..<alphabet.count)] })
    }
}

// MARK: - Session

extension LocalNetworkTransport: MCSessionDelegate {

    public func session(_ session: MCSession, peer peerID: MCPeerID, didChange state: MCSessionState) {
        switch state {
        case .connected:
            wiring.withLock { $0.peers[peerID.displayName] = peerID }
            report(nil)
            announcePeers()
        case .notConnected:
            wiring.withLock { $0.peers[peerID.displayName] = nil }
            announcePeers()
        case .connecting:
            break
        @unknown default:
            break
        }
    }

    public func session(_ session: MCSession, didReceive data: Data, fromPeer peerID: MCPeerID) {
        wiring.withLock { $0.handler }?.received(data, peerID.displayName)
    }

    public func session(_ session: MCSession, didReceive stream: InputStream, withName streamName: String, fromPeer peerID: MCPeerID) {}

    public func session(_ session: MCSession, didStartReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, with progress: Progress) {}

    public func session(_ session: MCSession, didFinishReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, at localURL: URL?, withError error: Error?) {}
}

// MARK: - Advertising

extension LocalNetworkTransport: MCNearbyServiceAdvertiserDelegate {

    public func advertiser(
        _ advertiser: MCNearbyServiceAdvertiser,
        didReceiveInvitationFromPeer peerID: MCPeerID,
        withContext context: Data?,
        invitationHandler: @escaping (Bool, MCSession?) -> Void
    ) {
        guard invitationIsValid(context) else {
            invitationHandler(false, nil)
            return
        }
        let session = wiring.withLock { $0.session }
        invitationHandler(session != nil, session)
    }

    public func advertiser(_ advertiser: MCNearbyServiceAdvertiser, didNotStartAdvertisingPeer error: Error) {
        report("cannot advertise the room: \(error.localizedDescription)")
    }
}

// MARK: - Browsing

extension LocalNetworkTransport: MCNearbyServiceBrowserDelegate {

    public func browser(_ browser: MCNearbyServiceBrowser, foundPeer peerID: MCPeerID, withDiscoveryInfo info: [String: String]?) {
        // The room name is checked here as well as in the invitation, because the
        // advertised service name is capped at 15 characters and two long room
        // names can share one.
        guard info?["room"] == roomName else { return }
        // Both machines see each other. Only the lower name invites, or the two
        // connections race and one of them drops.
        guard identity.displayName < peerID.displayName else { return }
        let session = wiring.withLock { $0.session }
        guard let session else { return }
        browser.invitePeer(peerID, to: session, withContext: invitation(), timeout: 30)
    }

    public func browser(_ browser: MCNearbyServiceBrowser, lostPeer peerID: MCPeerID) {
        // The session reports the disconnection itself, which is the event that
        // matters; a peer can be lost by the browser and still be connected.
    }

    public func browser(_ browser: MCNearbyServiceBrowser, didNotStartBrowsingForPeers error: Error) {
        report("cannot look for the room: \(error.localizedDescription)")
    }
}
