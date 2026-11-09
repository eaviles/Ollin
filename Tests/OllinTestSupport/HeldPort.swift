import Foundation

/// A port held by a plain socket with no reuse flag, so a listener asked for
/// the same number fails to bind the way it does when another program owns it.
///
/// Network.framework's listeners set reuse on their own sockets, which is why
/// two of them share a port happily; a socket bound without it is what makes
/// the second bind fail (measured: `.failed(POSIXErrorCode 48)` then
/// `.cancelled`, on UDP and TCP alike). `close()` gives the port back, so a
/// test can watch the same receiver come up on its next `start()`.
package final class HeldPort {

    /// The number the system handed out.
    package let port: Int
    private var descriptor: Int32

    /// Holds a free port, or `port` when one is named, over UDP or TCP.
    package init(udp: Bool = false, port requested: Int = 0) throws {
        let fd = socket(AF_INET, udp ? SOCK_DGRAM : SOCK_STREAM, 0)
        guard fd >= 0 else { throw Failure.socket(errno) }
        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = UInt16(clamping: requested).bigEndian
        address.sin_addr.s_addr = INADDR_ANY.bigEndian
        let bound = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard bound == 0 else {
            let code = errno
            Darwin.close(fd)
            throw Failure.bind(code)
        }
        if !udp { listen(fd, 1) }
        var assigned = sockaddr_in()
        var length = socklen_t(MemoryLayout<sockaddr_in>.size)
        withUnsafeMutablePointer(to: &assigned) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                _ = getsockname(fd, $0, &length)
            }
        }
        descriptor = fd
        port = Int(UInt16(bigEndian: assigned.sin_port))
    }

    /// Gives the port back. Safe to call twice.
    package func close() {
        guard descriptor >= 0 else { return }
        Darwin.close(descriptor)
        descriptor = -1
    }

    deinit { close() }

    package enum Failure: Error {
        case socket(Int32)
        case bind(Int32)
    }
}
