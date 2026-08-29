import Testing
import CoreGraphics
import Foundation
import Ollin
@testable import OllinScreen

/// The rules a sketch actually writes: which application a written name picks,
/// which window a title picks, which of several matching windows wins, and which
/// display a window is captured against.
///
/// These run everywhere. They are pure functions over plain values precisely
/// because the system's own `SCShareableContent` can never be constructed by a
/// test, so a screen holding the windows a case needs cannot be staged; keeping
/// the decisions out of the filter building is what leaves anything to check.
@Suite struct ScreenMatchTests {

    // MARK: Naming an application

    @Test func anAppIsFoundByTheNameAPersonSees() {
        #expect(ScreenMatch.app(name: "Safari", bundleIdentifier: "com.apple.Safari",
                                matches: "Safari"))
    }

    @Test func anAppIsFoundByItsBundleIdentifier() {
        #expect(ScreenMatch.app(name: "Safari", bundleIdentifier: "com.apple.Safari",
                                matches: "com.apple.Safari"))
    }

    @Test func matchingAnAppIgnoresCase() {
        #expect(ScreenMatch.app(name: "Safari", bundleIdentifier: "com.apple.Safari",
                                matches: "sAfArI"))
        #expect(ScreenMatch.app(name: "Safari", bundleIdentifier: "com.apple.Safari",
                                matches: "COM.APPLE.SAFARI"))
    }

    /// A name has to match the whole thing. Substring matching an application
    /// would make `"Mail"` also pick "MailMate", and there is no title bar to
    /// disambiguate by, unlike a window.
    @Test func anAppNameMatchesWholeAndNotInPart() {
        #expect(!ScreenMatch.app(name: "MailMate", bundleIdentifier: "com.freron.MailMate",
                                 matches: "Mail"))
    }

    /// The counterfactual that matters on this platform: a sketch run from the
    /// terminal has no bundle identifier at all, so an empty search must not
    /// silently match every such process, which is what a plain equality test on
    /// two empty strings would do.
    @Test func anEmptyNameMatchesNothingEvenThoughIdentifiersCanBeEmpty() {
        #expect(!ScreenMatch.app(name: "Sketch", bundleIdentifier: "", matches: ""))
        #expect(ScreenMatch.app(name: "Sketch", bundleIdentifier: "", matches: "Sketch"))
    }

    // MARK: Naming a window

    @Test func aWindowIsFoundByPartOfItsTitle() {
        #expect(ScreenMatch.window(title: "Notes: Shopping list", matches: "Shopping"))
    }

    @Test func matchingAWindowIgnoresCase() {
        #expect(ScreenMatch.window(title: "Untitled Document", matches: "untitled"))
    }

    @Test func aWindowWithNoTitleMatchesNothing() {
        #expect(!ScreenMatch.window(title: nil, matches: "anything"))
    }

    @Test func anEmptyTitleSearchMatchesNothing() {
        #expect(!ScreenMatch.window(title: "Untitled", matches: ""))
    }

    // MARK: Which of several

    /// The repeatability rule: given several matching windows, the same one is
    /// picked every run. Lowest id wins, and the answer must not depend on the
    /// order the system happened to list them in, so the counterfactual is the
    /// same set reversed.
    @Test func theSameWindowIsPickedWhateverOrderTheyArriveIn() {
        let ids: [CGWindowID] = [812, 44, 907, 130]
        let forwards = ScreenMatch.preferred(ids, id: { $0 })
        let backwards = ScreenMatch.preferred(ids.reversed().map { $0 }, id: { $0 })
        #expect(forwards == 44)
        #expect(forwards == backwards)
    }

    @Test func pickingFromNothingFindsNothing() {
        #expect(ScreenMatch.preferred([CGWindowID](), id: { $0 }) == nil)
    }

    // MARK: Which display

    @Test func aWindowIsCapturedAgainstTheDisplayItSitsOn() {
        let displays = [CGRect(x: 0, y: 0, width: 1440, height: 900),
                        CGRect(x: 1440, y: 0, width: 1920, height: 1080)]
        let onSecond = CGRect(x: 1600, y: 100, width: 400, height: 300)
        #expect(ScreenMatch.displayHolding(onSecond, among: displays) == 1)
    }

    /// A window dragged across the seam belongs to whichever display holds more
    /// of it, not to the first one it touches.
    @Test func aWindowStraddlingTwoDisplaysGoesWithTheLargerShare() {
        let displays = [CGRect(x: 0, y: 0, width: 1440, height: 900),
                        CGRect(x: 1440, y: 0, width: 1920, height: 1080)]
        // 100 points wide on the left display, 300 on the right.
        let straddling = CGRect(x: 1340, y: 100, width: 400, height: 300)
        #expect(ScreenMatch.displayHolding(straddling, among: displays) == 1)
        // Mirrored, so the test cannot pass by always answering 1.
        let mostlyLeft = CGRect(x: 1140, y: 100, width: 400, height: 300)
        #expect(ScreenMatch.displayHolding(mostlyLeft, among: displays) == 0)
    }

    @Test func aWindowOnNoDisplayHasNoHome() {
        let displays = [CGRect(x: 0, y: 0, width: 1440, height: 900)]
        let offscreen = CGRect(x: 5000, y: 5000, width: 100, height: 100)
        #expect(ScreenMatch.displayHolding(offscreen, among: displays) == nil)
    }
}

// MARK: The source value

@Suite struct ScreenSourceTests {

    @Test func aTitleOnlyWindowNamesNoApp() {
        #expect(ScreenSource.window(title: "Untitled") == .window(title: "Untitled", app: nil))
    }

    /// The waiting notice says what is being waited for, so a sketch pointed at
    /// a window that is not open yet reads as waiting rather than broken.
    @Test func everySourceCanSayWhatItNames() {
        #expect(ScreenSource.app("Safari").label == "Safari")
        #expect(ScreenSource.window(title: "Shopping list").label == "Shopping list")
        #expect(ScreenSource.mainDisplay.label == "the main display")
        #expect(ScreenSource.display(7).label.contains("7"))
        #expect(ScreenSource.windowID(41).label.contains("41"))
    }

    @Test func sourcesCompareByWhatTheyName() {
        #expect(ScreenSource.app("Safari") == .app("Safari"))
        #expect(ScreenSource.app("Safari") != .app("Notes"))
        #expect(ScreenSource.window(title: "a", app: "X") != .window(title: "a", app: "Y"))
    }
}

// MARK: Permission and capture

/// The permission surface always answers, and the end-to-end capture runs only
/// where the screen-recording permission is actually in place. It is a consent a
/// machine cannot grant itself, so this soft-skips rather than failing CI.
@MainActor
@Suite struct ScreenCaptureTests {

    nonisolated static var isPermitted: Bool { ScreenCapture.isAvailable }

    /// Always on: asking whether capture is available must be safe, and the two
    /// answers must agree with each other.
    @Test func thePermissionSurfaceAlwaysAnswers() {
        let available = ScreenCapture.isAvailable
        #expect(available == (ScreenCapture.unavailableReason == nil))
    }

    /// Always on: a capture with no permission must say so on the canvas rather
    /// than sit blank. Without permission `start()` fills the reason in; with it,
    /// the notice names what is being waited for.
    @Test func aCaptureAlwaysHasSomethingToSay() {
        let capture = ScreenCapture(.app("A Window That Is Not Open"))
        #expect(!capture.waitingMessage.isEmpty)
        #expect(capture.frame == nil)
        #expect(!capture.isRunning)
    }

    /// Always on: the size multiplier is clamped into a range that can produce a
    /// texture at all, since a sketch can set it from a knob.
    @Test func theSizeMultiplierStaysInRange() {
        let capture = ScreenCapture(.mainDisplay)
        capture.scale = 4
        #expect(capture.scale == 1)
        capture.scale = -1
        #expect(capture.scale == 0.05)
        capture.scale = 0.5
        #expect(capture.scale == 0.5)
    }

    @Test(.enabled(if: ScreenCaptureTests.isPermitted))
    func theScreenIsListedAndCapturable() async {
        let displays = await ScreenCapture.displays()
        #expect(!displays.isEmpty)
        #expect(displays.contains { $0.isMain })
        // Listings are ordered, so reading them twice reads the same.
        let again = await ScreenCapture.displays()
        #expect(displays == again)
    }

    /// The claim is that a listing comes back in a settled order, so naming a
    /// window picks the same one twice.
    ///
    /// It deliberately compares only what both readings saw. Windows open and
    /// close on a live machine, and demanding two identical listings makes this
    /// fail whenever anything on the Mac opens a window mid-test, which is a
    /// property of the machine rather than of the code under test.
    @Test(.enabled(if: ScreenCaptureTests.isPermitted))
    func windowsAndAppsAreListedInAStableOrder() async {
        let windows = await ScreenCapture.windows()
        let windowsAgain = await ScreenCapture.windows()
        #expect(sharedOrder(windows, windowsAgain, by: \.id)
            == sharedOrder(windowsAgain, windows, by: \.id))
        #expect(windows.sorted { $0.id < $1.id } == windows)

        let apps = await ScreenCapture.apps()
        let appsAgain = await ScreenCapture.apps()
        #expect(sharedOrder(apps, appsAgain, by: \.id)
            == sharedOrder(appsAgain, apps, by: \.id))
    }

    /// The ids `first` and `second` both saw, left in `first`'s order.
    ///
    /// Ids rather than whole entries, because a window can be retitled or moved
    /// between two readings and still be the same window in the same place in
    /// the list, which is all this is claiming.
    private func sharedOrder<Element, ID: Hashable>(
        _ first: [Element], _ second: [Element], by id: KeyPath<Element, ID>
    ) -> [ID] {
        let shared = Set(second.map { $0[keyPath: id] })
        return first.map { $0[keyPath: id] }.filter { shared.contains($0) }
    }

    /// The end-to-end run: point a capture at the main display, and frames must
    /// arrive as drawable images at the display's true backing size.
    @Test(.enabled(if: ScreenCaptureTests.isPermitted))
    func capturingTheMainDisplayDeliversFrames() async throws {
        let capture = ScreenCapture(.mainDisplay)
        capture.start()
        defer { capture.stop() }
        #expect(capture.isRunning)

        let frame = await waitForFrame(capture)
        let image = try #require(frame, "no frame arrived within the timeout")
        #expect(image.width > 0 && image.height > 0)
        let size = try #require(capture.frameSize)
        #expect(Int(size.x) == image.width)
        #expect(Int(size.y) == image.height)
    }

    /// Halving the multiplier halves the captured texture, which is the whole
    /// point of it: the same picture at a quarter of the pixels.
    @Test(.enabled(if: ScreenCaptureTests.isPermitted))
    func theSizeMultiplierScalesTheCapturedTexture() async throws {
        let full = ScreenCapture(.mainDisplay)
        full.start()
        defer { full.stop() }
        _ = await waitForFrame(full)
        let fullSize = try #require(full.frameSize)

        let half = ScreenCapture(.mainDisplay)
        half.scale = 0.5
        half.start()
        defer { half.stop() }
        _ = await waitForFrame(half)
        let halfSize = try #require(half.frameSize)

        #expect(abs(halfSize.x - fullSize.x / 2) <= 1)
        #expect(abs(halfSize.y - fullSize.y / 2) <= 1)
    }

    /// A source naming something that is not on screen is a waiting state, not a
    /// failure: the capture stays wanted and keeps looking, so opening the window
    /// later starts it.
    @Test(.enabled(if: ScreenCaptureTests.isPermitted))
    func anAbsentSourceIsWaitedForRatherThanFailed() async {
        let capture = ScreenCapture(.window(title: "\(UUID())"))
        capture.start()
        defer { capture.stop() }
        try? await Task.sleep(for: .milliseconds(600))
        #expect(capture.isRunning)
        #expect(capture.frame == nil)
        #expect(capture.waitingMessage.contains("Waiting"))
    }

    /// The frame source seam: installing a tap must deliver CPU frames, which is
    /// what lets a vision tracker read the screen.
    @Test(.enabled(if: ScreenCaptureTests.isPermitted))
    func aTapReceivesFramesForAnalysis() async throws {
        let capture = ScreenCapture(.mainDisplay)
        let counter = TapCounter()
        capture.frameTap = { _ in counter.bump() }
        capture.start()
        defer { capture.stop(); capture.frameTap = nil }

        let deadline = Date().addingTimeInterval(6)
        while Date() < deadline, counter.count == 0 {
            try? await Task.sleep(for: .milliseconds(50))
        }
        #expect(counter.count > 0, "the analysis tap received no frames")
    }

    /// The read comes before the clock: a starved task can wake past its own
    /// deadline having never looked once, and returning `nil` then reports a
    /// frame that never arrived while the frame is sitting there.
    private func waitForFrame(_ capture: ScreenCapture,
                              timeout: Double = 6) async -> Image? {
        let deadline = Date().addingTimeInterval(timeout)
        while true {
            if let frame = capture.frame { return frame }
            if Date() >= deadline { return nil }
            try? await Task.sleep(for: .milliseconds(50))
        }
    }
}

/// Counts tap deliveries from the capture queue.
private final class TapCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var value = 0
    var count: Int { lock.withLock { value } }
    func bump() { lock.withLock { value += 1 } }
}
