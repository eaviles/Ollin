import Foundation
import Network

/// Sends DMX universes to lighting rigs over the network, as Art-Net or sACN.
/// Create one in `setup()`, fill a `DMXUniverse` each frame, and `send` it;
/// the sender takes care of the wire cadence both specs ask for (changed data
/// plus keep-alives, capped near DMX's own refresh rate), so calling it every
/// frame at 60 fps is exactly right.
///
/// ```swift
/// let dmx = DMXSender()                          // sACN multicast: zero config
/// let dmx = DMXSender(sACN: "192.168.1.20")      // sACN unicast to one node
/// let dmx = DMXSender(artNet: "192.168.1.60")    // Art-Net unicast to a node
///
/// var rig = DMXUniverse()
/// override func draw() {
///     rig.set(par, color: .red, dimmer: pulse)
///     dmx.send(rig)                              // universe 1
/// }
/// ```
///
/// Art-Net 4 sends DMX unicast (the node's IP is the one thing to configure);
/// sACN with no host multicasts, which any listening node picks up with no
/// addressing at all. Reaching hardware on the local network makes macOS ask
/// for Local Network permission once, attributed to the launching terminal;
/// `127.0.0.1` loopback needs nothing.
public final class DMXSender {

    /// Which wire protocol this sender speaks.
    public let dmxProtocol: DMXProtocol

    /// The unicast destination, or `nil` when multicasting (sACN only).
    public let host: String?

    /// The destination UDP port.
    public let port: Int

    /// The source name sACN packets carry (shows up in rig monitors).
    public var sourceName = "Ollin"

    /// The sACN source priority, 0 to 200; receivers pick the highest when
    /// several sources drive one universe.
    public var priority = 100

    /// The transmit ceiling in packets per second per universe. 44 matches
    /// what a DMX512 gateway can put on the wire; raise it only for pure
    /// network rigs that declare a higher rate.
    public var maximumRate = 44.0

    private let cid = UUID()
    private var pacers: [Int: DMXPacer] = [:]
    private var sequences: [Int: UInt8] = [:]
    private var connections: [Int: NWConnection] = [:]
    private var noted = Set<String>()
    private var closed = false

    /// An sACN sender that multicasts each universe to its standard group;
    /// any sACN node on the network listening to that universe receives it.
    public init() {
        dmxProtocol = .sACN
        host = nil
        port = SACNDataPacket.port
    }

    /// An sACN sender pointed at one receiver's IP or hostname.
    public init(sACN host: String, port: Int = SACNDataPacket.port) {
        dmxProtocol = .sACN
        self.host = host
        self.port = port
    }

    /// An Art-Net sender pointed at a node's IP or hostname. Art-Net 4 sends
    /// DMX unicast, so the node's address is the one thing to name.
    public init(artNet host: String, port: Int = ArtDmxPacket.port) {
        dmxProtocol = .artNet
        self.host = host
        self.port = port
    }

    // MARK: Sending

    /// Sends a universe of channels, on `universe` number 1 by default.
    /// Call it every frame; the sender throttles the wire on its own.
    public func send(_ data: DMXUniverse, universe: Int = 1) {
        send(channels: data.channels, universe: universe)
    }

    /// Sends raw channel bytes (1 to 512 of them) on a universe.
    public func send(channels: [UInt8], universe: Int = 1) {
        guard !closed else { return }
        let universe = validated(universe)
        var pacer = pacers[universe] ?? DMXPacer()
        pacer.maximumRate = maximumRate
        let now = ProcessInfo.processInfo.systemUptime
        let sending = pacer.shouldSend(channels, now: now)
        pacers[universe] = pacer
        guard sending else { return }
        transmit(encode(channels: channels, universe: universe), universe: universe)
    }

    /// Closes the sender. An sACN sender says goodbye first (three
    /// stream-terminated packets per universe, the standard's clean ending,
    /// so receivers drop the look at once instead of waiting out a timeout).
    public func close() {
        guard !closed else { return }
        closed = true
        if dmxProtocol == .sACN, !pacers.isEmpty {
            // Wait (briefly) for the goodbyes to reach the wire; cancelling
            // right away would drop sends still queued on the connection.
            let inFlight = DispatchGroup()
            for universe in pacers.keys.sorted() {
                for _ in 0..<3 {
                    inFlight.enter()
                    let goodbye = encode(channels: [], universe: universe, terminated: true)
                    connection(universe: universe).send(
                        content: goodbye,
                        completion: .contentProcessed { _ in inFlight.leave() }
                    )
                }
            }
            _ = inFlight.wait(timeout: .now() + .milliseconds(500))
        }
        connections.values.forEach { $0.cancel() }
        connections.removeAll()
    }

    deinit { close() }

    // MARK: Wire

    private func encode(channels: [UInt8], universe: Int, terminated: Bool = false) -> Data {
        switch dmxProtocol {
        case .artNet:
            return ArtDmxPacket(
                universe: universe,
                channels: channels.isEmpty ? [0, 0] : channels,
                sequence: nextSequence(universe: universe)
            ).encode()
        case .sACN:
            return SACNDataPacket(
                universe: universe,
                channels: channels,
                sequence: nextSequence(universe: universe),
                priority: UInt8(clamping: min(max(priority, 0), 200)),
                sourceName: sourceName,
                cid: cid,
                isTerminated: terminated
            ).encode()
        }
    }

    private func nextSequence(universe: Int) -> UInt8 {
        let next: UInt8
        switch dmxProtocol {
        case .artNet:
            // 1 to 255, wrapping past 255 back to 1; 0 would mean "disabled".
            let last = sequences[universe] ?? 0
            next = last >= 255 ? 1 : last + 1
        case .sACN:
            next = (sequences[universe] ?? 255) &+ 1
        }
        sequences[universe] = next
        return next
    }

    private func transmit(_ data: Data, universe: Int) {
        connection(universe: universe).send(content: data, completion: .contentProcessed { _ in })
    }

    private func connection(universe: Int) -> NWConnection {
        // Unicast shares one connection; sACN multicast needs one per
        // universe, since the group address carries the universe number.
        let key = host == nil ? universe : -1
        if let existing = connections[key] { return existing }
        let destination = host ?? SACNDataPacket.multicastGroup(universe: universe)
        let connection = NWConnection(
            host: NWEndpoint.Host(destination),
            port: NWEndpoint.Port(rawValue: UInt16(clamping: port)) ?? 0,
            using: .udp
        )
        connection.start(queue: DMXSender.queue)
        connections[key] = connection
        return connection
    }

    private func validated(_ universe: Int) -> Int {
        let range = dmxProtocol == .artNet ? 0...32767 : 1...63999
        guard !range.contains(universe) else { return universe }
        noteOnce("universe \(universe) is outside \(dmxProtocol.rawValue)'s range \(range); clamping")
        return min(max(universe, range.lowerBound), range.upperBound)
    }

    private func noteOnce(_ message: String) {
        guard noted.insert(message).inserted else { return }
        FileHandle.standardError.write(Data("OllinDMX: \(message)\n".utf8))
    }

    // One shared queue drives every sender's connection callbacks; sends are
    // brief and serialized, so they don't need a queue each.
    private static let queue = DispatchQueue(label: "com.ollin.dmx.sender")
}
