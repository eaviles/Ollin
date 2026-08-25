/// Assembles the incoming byte stream into text lines, tolerating every line
/// ending a device might send: LF, CRLF, or bare CR. Bytes are accumulated
/// until a terminator lands, so a line split across reads still comes out
/// whole (and a multi-byte character split across reads decodes intact,
/// because decoding happens per complete line, not per chunk).
struct LineAssembler {
    private var pending: [UInt8] = []
    private var lastByteWasCR = false

    /// A line that never terminates (a binary stream, a wedged device) is
    /// capped here; the oldest bytes fall off so memory stays bounded.
    private let pendingLimit = 4096

    /// Feeds a chunk of bytes in and returns every line it completed.
    mutating func ingest(_ bytes: some Sequence<UInt8>) -> [String] {
        var lines: [String] = []
        for byte in bytes {
            switch byte {
            case 0x0A:
                // The LF of a CRLF pair: the CR already ended the line.
                if lastByteWasCR { lastByteWasCR = false; continue }
                lines.append(complete())
            case 0x0D:
                lines.append(complete())
                lastByteWasCR = true
            default:
                lastByteWasCR = false
                pending.append(byte)
                if pending.count > pendingLimit {
                    pending.removeFirst(pending.count - pendingLimit)
                }
            }
        }
        return lines
    }

    /// Drops any partly assembled line, for a fresh start on reconnection.
    mutating func reset() {
        pending.removeAll(keepingCapacity: true)
        lastByteWasCR = false
    }

    private mutating func complete() -> String {
        defer { pending.removeAll(keepingCapacity: true) }
        return String(decoding: pending, as: UTF8.self)
    }
}
