import Foundation

/// The two ways DMX travels over Ethernet. Both carry the same 512-channel
/// universes; they differ in wire format, port, and how packets find a node.
///
/// - `artNet`: the Artistic Licence protocol most lighting nodes and consoles
///   speak. Sent unicast to a node's IP on UDP port 6454.
/// - `sACN`: streaming ACN (ANSI E1.31), the open industry standard. Sent
///   multicast (any listening node picks it up, no addresses to configure) or
///   unicast, on UDP port 5568.
public enum DMXProtocol: String, Equatable, Sendable {
    case artNet = "Art-Net"
    case sACN = "sACN"

    /// The UDP port the protocol standardizes on.
    public var defaultPort: Int {
        switch self {
        case .artNet: return ArtDmxPacket.port
        case .sACN: return SACNDataPacket.port
        }
    }
}
