import Foundation
import Darwin

/// A last-gasp crash reporter for the examples gallery.
///
/// A sketch runs *in-process* — the gallery `dlopen`s its compiled dylib and
/// embeds it as a live view — so a runtime fault arrives as a native **signal**
/// (a bad memory access, a Swift trap) or an **uncaught Objective-C exception**.
/// Neither is a Swift `Error` the app can catch and recover from: once a fault
/// fires the process state is undefined. So this can't keep the gallery alive —
/// what it does is *surface* the fault. Instead of the window silently vanishing,
/// it prints which example was running and a backtrace, then lets the OS take its
/// normal course (which still produces the standard crash report). True
/// containment — a crashing sketch leaving the app running — would need
/// out-of-process rendering, worth it for untrusted/user sketches, not the
/// curated examples.
enum CrashReporter {
    private static let nameCapacity = 256
    /// The running example's name in a fixed C buffer, so the signal handler can
    /// read it without touching Swift `String` internals or the allocator (which
    /// aren't safe from a signal context).
    private nonisolated(unsafe) static var nameBuffer = [CChar](repeating: 0, count: nameCapacity)
    private static let nameLock = NSLock()
    /// Guards against a fault *inside* the handler turning into an infinite loop.
    private nonisolated(unsafe) static var handling = false

    /// Install the handlers. Call once, early, before any sketch loads.
    static func install() {
        setCurrentExample(nil)
        NSSetUncaughtExceptionHandler { exception in
            CrashReporter.report(exception: exception)
        }
        // SIGTRAP is left to the debugger; the rest are the fault signals a sketch
        // (or the host machinery it drives) can raise. SIGABRT covers Swift traps
        // (force-unwrap, out-of-bounds, fatalError), which abort.
        let handler: @convention(c) (Int32) -> Void = { sig in CrashReporter.handleSignal(sig) }
        for sig in [SIGSEGV, SIGABRT, SIGILL, SIGBUS, SIGFPE] {
            signal(sig, handler)
        }
    }

    /// Record which example is currently loaded, so a fault can name it. Pass
    /// `nil` when nothing is running.
    static func setCurrentExample(_ name: String?) {
        nameLock.lock(); defer { nameLock.unlock() }
        (name ?? "(none)").withCString { src in
            _ = strlcpy(&nameBuffer, src, nameCapacity)
        }
    }

    // MARK: Signal path (must stay close to async-signal-safe)

    private static func handleSignal(_ sig: Int32) {
        if handling { _exit(1) }        // a fault while reporting — bail hard
        handling = true

        write(STDERR_FILENO, "\n*** Ollin Examples faulted: ")
        write(STDERR_FILENO, name(of: sig))
        write(STDERR_FILENO, "\n    while running example: ")
        writeCurrentExampleName()
        write(STDERR_FILENO, "\n    backtrace:\n")

        var frames = [UnsafeMutableRawPointer?](repeating: nil, count: 128)
        let count = backtrace(&frames, Int32(frames.count))
        backtrace_symbols_fd(&frames, count, STDERR_FILENO)
        write(STDERR_FILENO, "\n")

        // Restore the default and re-raise so the OS still records the crash.
        signal(sig, SIG_DFL)
        raise(sig)
    }

    /// A human name for a fault signal, as a `StaticString` (no allocation).
    private static func name(of sig: Int32) -> StaticString {
        switch sig {
        case SIGSEGV: return "SIGSEGV (bad memory access)"
        case SIGABRT: return "SIGABRT (abort / Swift trap)"
        case SIGILL:  return "SIGILL (illegal instruction)"
        case SIGBUS:  return "SIGBUS (bus error)"
        case SIGFPE:  return "SIGFPE (arithmetic error)"
        default:      return "a fatal signal"
        }
    }

    /// Write a `StaticString`'s bytes straight to a file descriptor.
    private static func write(_ fd: Int32, _ text: StaticString) {
        text.withUTF8Buffer { _ = Darwin.write(fd, $0.baseAddress, $0.count) }
    }

    /// Write the current-example C buffer (read without the lock — locks aren't
    /// signal-safe; a torn read is a harmless cosmetic risk at crash time).
    private static func writeCurrentExampleName() {
        nameBuffer.withUnsafeBufferPointer { buffer in
            guard let base = buffer.baseAddress else { return }
            _ = Darwin.write(STDERR_FILENO, base, strnlen(base, nameCapacity))
        }
    }

    // MARK: Exception path (ordinary code — a full Swift backtrace is fine here)

    private static func report(exception: NSException) {
        let name = currentExampleName()
        var message = "\n*** Ollin Examples faulted: uncaught \(exception.name.rawValue)\n"
        message += "    while running example: \(name)\n"
        if let reason = exception.reason { message += "    reason: \(reason)\n" }
        message += "    backtrace:\n"
        message += exception.callStackSymbols.map { "      \($0)" }.joined(separator: "\n")
        message += "\n"
        FileHandle.standardError.write(Data(message.utf8))
    }

    private static func currentExampleName() -> String {
        nameLock.lock(); defer { nameLock.unlock() }
        return nameBuffer.withUnsafeBufferPointer { buffer in
            buffer.baseAddress.map { String(cString: $0) } ?? "(none)"
        }
    }
}
