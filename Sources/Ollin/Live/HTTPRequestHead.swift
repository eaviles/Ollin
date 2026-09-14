import Foundation

/// The head of an HTTP/1.1 request as the small servers in the satellites read
/// it: the method, the request target (the path with any query), and the
/// headers with lowercased names. Two satellites speak HTTP (the remote surface
/// and the OSCQuery namespace), and a satellite cannot depend on another one,
/// so the parser they share lives here.
package struct HTTPRequestHead: Equatable, Sendable {
    package var method: String
    package var path: String
    package var headers: [String: String]

    package init(method: String, path: String, headers: [String: String]) {
        self.method = method
        self.path = path
        self.headers = headers
    }

    /// Finds and parses a complete request head in `bytes`. Returns the head
    /// plus how many bytes it consumed (through the blank line), or `nil` while
    /// the head is still incomplete or malformed.
    package static func parse(_ bytes: [UInt8]) -> (head: HTTPRequestHead, consumed: Int)? {
        guard let end = headEnd(bytes) else { return nil }
        guard let text = String(bytes: bytes[..<end], encoding: .utf8) else { return nil }
        var lines = text.split(separator: "\r\n", omittingEmptySubsequences: false)[...]
        guard let requestLine = lines.popFirst() else { return nil }
        let parts = requestLine.split(separator: " ")
        guard parts.count >= 2 else { return nil }
        var headers: [String: String] = [:]
        for line in lines {
            guard let colon = line.firstIndex(of: ":") else { continue }
            let name = line[..<colon].trimmingCharacters(in: .whitespaces).lowercased()
            let value = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
            headers[name] = value
        }
        let head = HTTPRequestHead(method: String(parts[0]), path: String(parts[1]), headers: headers)
        return (head, end + 4)
    }

    private static func headEnd(_ bytes: [UInt8]) -> Int? {
        guard bytes.count >= 4 else { return nil }
        for i in 0...(bytes.count - 4)
        where bytes[i] == 13 && bytes[i + 1] == 10 && bytes[i + 2] == 13 && bytes[i + 3] == 10 {
            return i
        }
        return nil
    }
}
