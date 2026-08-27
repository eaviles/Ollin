import Foundation

/// A scratch path under the temporary directory that no other process is
/// using, for the tests that write a file and read it back.
///
/// Several copies of this bundle can be running at once: two sessions working
/// in one checkout, or one run sharded across processes to get more than the
/// single main thread a process has. A literal name under
/// `NSTemporaryDirectory()` is the same file in all of them, so one run
/// deletes what another is still reading and both fail in ways that look like
/// anything but a shared path.
///
/// Keyed on the process, not on a fresh UUID per call, so a test that asks for
/// the same name twice still gets the same file. A test that wants a fresh
/// file every time asks for a name carrying its own `UUID()`.
func ollinTempPath(_ name: String) -> String {
    NSTemporaryDirectory() + "p\(ProcessInfo.processInfo.processIdentifier)-" + name
}

/// `ollinTempPath(_:)` as a file URL.
func ollinTempURL(_ name: String) -> URL {
    URL(fileURLWithPath: ollinTempPath(name))
}
