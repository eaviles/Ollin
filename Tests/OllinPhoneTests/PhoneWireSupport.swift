import Foundation
@testable import OllinPhone

/// Encodes a message and reads the framed bytes back the way the reader thread
/// does: the header first, then the payload it announces. `nil` where either
/// half refuses, which is what a round-trip test is asking about.
func roundTrip(_ message: PhoneMessage) -> PhoneMessage? {
    let data = PhoneWire.encode(message)
    guard let header = PhoneHeader.parse(data) else { return nil }
    let start = data.startIndex + PhoneWire.headerByteCount
    return PhoneWire.decode(header: header, payload: data.subdata(in: start ..< data.endIndex))
}

/// The same trip for a request going the other way, through its own header.
func roundTrip(_ request: PhoneRequest) -> PhoneRequest? {
    let data = PhoneWire.encode(request)
    guard let header = PhoneRequestHeader.parse(data) else { return nil }
    let start = data.startIndex + PhoneWire.headerByteCount
    return PhoneWire.decode(header: header, payload: data.subdata(in: start ..< data.endIndex))
}
