import AppKit
import Foundation
import Testing
@testable import Ollin

/// Probes for the host that keeps an unattended piece on screen: the hold on the
/// display and the hidden pointer, counted through the seam the host asks the
/// system through, since neither can be read back from inside the process.
///
/// The claim under test is one hold. A piece with hours takes over and reads
/// its schedule in the same breath, and each of those used to begin a hold of
/// its own: the second hold's timer wrote over the first, so the first kept
/// declaring activity every half minute with nothing left to invalidate it, and
/// a display that should have slept through the dark hours stayed lit all
/// night.
@Suite
@MainActor
struct InstallationHostTests {

    /// Counts what the host asked of the system.
    @MainActor
    final class Counted {
        var begun = 0
        var ended = 0
        var declared = 0
        var hidden = 0
        var shown = 0
        var timers: [Timer] = []

        var power: InstallationHost.Power {
            InstallationHost.Power(
                beginActivity: { [self] in
                    begun += 1
                    return NSObject()
                },
                endActivity: { [self] _ in ended += 1 },
                declareUserActivity: { [self] _ in declared += 1 },
                hidePointer: { [self] in hidden += 1 },
                unhidePointer: { [self] in shown += 1 },
                makeIdleTimer: { [self] interval, body in
                    // Never scheduled: a test fires nothing. Kept so the test can
                    // see which timers the host let go of without invalidating.
                    let timer = Timer(timeInterval: interval, repeats: true) { _ in
                        MainActor.assumeIsolated { body() }
                    }
                    timers.append(timer)
                    return timer
                })
        }
    }

    /// A window the host can take over without showing anything.
    private func window() -> NSWindow {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 200, height: 200),
                              styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        return window
    }

    /// Today at `hour`, in the machine's own time zone, which is what the
    /// schedule reads.
    private func today(at hour: Int) -> Date {
        Calendar.current.date(bySettingHour: hour, minute: 0, second: 0, of: Date())!
    }

    /// A piece open from nine to six, taken over at noon.
    private func openPiece() -> (InstallationHost, Counted, NSWindow, clock: ClockBox) {
        var settings = Installation()
        settings.fillsScreen = false
        settings.schedule = .open(from: 9, to: 18)
        let counted = Counted()
        let clock = ClockBox(today(at: 12))
        let host = InstallationHost(settings, power: counted.power, now: { clock.now })
        let window = window()
        host.take(over: window)
        return (host, counted, window, clock)
    }

    final class ClockBox: @unchecked Sendable {
        var now: Date
        init(_ now: Date) { self.now = now }
    }

    @Test func aPieceWithHoursHoldsTheDisplayOnce() {
        let (host, counted, _, _) = openPiece()
        defer { host.release() }
        #expect(counted.begun == 1)
        #expect(counted.ended == 0)
        #expect(counted.timers.count == 1)
        #expect(counted.hidden == 1)
        #expect(host.isHoldingAwake)
    }

    @Test func goingDarkEndsTheHoldAndItsTimer() {
        let (host, counted, _, clock) = openPiece()
        defer { host.release() }
        clock.now = today(at: 20)
        host.applySchedule()
        #expect(counted.ended == counted.begun)
        #expect(!host.isHoldingAwake)
        // Every timer the host made is stopped: one left valid is one that
        // declares activity every half minute through the dark hours.
        #expect(counted.timers.allSatisfy { !$0.isValid })
    }

    @Test func theMorningHoldsAgainOnce() {
        let (host, counted, _, clock) = openPiece()
        defer { host.release() }
        clock.now = today(at: 20)
        host.applySchedule()
        clock.now = today(at: 10)
        host.applySchedule()
        #expect(counted.begun == 2)
        #expect(counted.ended == 1)
        #expect(counted.timers.filter(\.isValid).count == 1)
        #expect(host.isHoldingAwake)
    }

    @Test func aWakeRenewsTheHoldRatherThanAddingOne() {
        let (host, counted, _, _) = openPiece()
        defer { host.release() }
        host.reassert()
        #expect(counted.begun == 2)
        #expect(counted.ended == 1)
        #expect(counted.timers.filter(\.isValid).count == 1)
        // Hidden once for the take-over and never again: the system counts
        // hides, and a second one needs a second show.
        #expect(counted.hidden == 1)
    }

    @Test func aWakeInTheDarkHoursHoldsNothing() {
        let (host, counted, _, clock) = openPiece()
        defer { host.release() }
        clock.now = today(at: 20)
        host.applySchedule()
        host.reassert()
        #expect(counted.begun == 1)
        #expect(!host.isHoldingAwake)
    }

    @Test func releasingShowsThePointerAsOftenAsItWasHidden() {
        let (host, counted, _, clock) = openPiece()
        clock.now = today(at: 20)
        host.applySchedule()
        clock.now = today(at: 10)
        host.applySchedule()
        host.reassert()
        host.release()
        #expect(counted.shown == counted.hidden)
        #expect(counted.ended == counted.begun)
        #expect(!host.pointerIsHidden)
    }

    @Test func aPieceWithNoHoursHoldsOnceToo() {
        var settings = Installation()
        settings.fillsScreen = false
        let counted = Counted()
        let host = InstallationHost(settings, power: counted.power)
        host.take(over: window())
        #expect(counted.begun == 1)
        #expect(counted.hidden == 1)
        host.release()
        #expect(counted.ended == 1)
        #expect(counted.shown == 1)
    }
}
