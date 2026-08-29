import Foundation

/// One line on stdout, stamped, because the log is the only witness a piece
/// running for a week has. Flushed on the spot: stdout piped to a file is
/// buffered, so an unflushed line would reach the file hours later, or never if
/// the run is killed, which is exactly when the log is wanted.
func ollinInstallationLog(_ message: String) {
    let stamp = ollinLogStamp.string(from: Date())
    print("Ollin installation [\(stamp)]: \(message)")
    fflush(stdout)
}

private let ollinLogStamp: DateFormatter = {
    let formatter = DateFormatter()
    formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
    return formatter
}()
