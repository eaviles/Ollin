import Testing
import AVFoundation
import CoreGraphics
import Foundation
import os
import Ollin
@testable import OllinVision
import OllinTestSupport

/// `Camera.orStill` and `Camera.or` on a machine where the camera has never
/// been asked for: the picture, or a feed of any kind, stands in while the
/// system's prompt is up, the camera takes over at its first frame, and a run
/// with no window never asks. No test here
/// touches a capture device or puts a prompt on the screen: the permission's
/// state and the prompt are the seams `Camera` keeps for exactly this, and
/// the hand-over itself is driven through a feed delivered by hand.
@MainActor
@Suite struct CameraOrStillTests {

    /// A feed the test delivers by hand, standing in for a camera or for a
    /// film. It counts the steps of an export's clock it is handed.
    final class ManualFeed: FrameSource, VideoFeed {
        var frameTap: FrameTap?
        var frame: Image?
        var frameSize: Vector2? { frame?.size }
        var isLive = false
        var waitingMessage = "Waiting for the manual feed…"
        var steps: [Double] = []
        var clock: [Double] = []

        func deliver(_ image: Image) {
            frame = image
            frameTap?(image.currentCGImage())
        }

    }

    /// The widths of the frames a tap was handed, in order. The picture and
    /// the live frame differ in width, so a width says which feed spoke.
    final class Seen: Sendable {
        private let widths = OSAllocatedUnfairLock(initialState: [Int]())
        func add(_ image: CGImage) { widths.withLock { $0.append(image.width) } }
        var all: [Int] { widths.withLock { $0 } }
    }

    /// Formed off the main actor, like any tap a source's own thread calls.
    nonisolated static func tap(into seen: Seen) -> FrameTap {
        { seen.add($0) }
    }

    let picture = Image(width: 40, height: 30, color: .white)
    let liveFrame = Image(width: 64, height: 48, color: .black)

    @Test func thePictureStandsInUntilTheFirstLiveFrame() {
        let live = ManualFeed()
        var begun = 0
        let feed = StandInFeed(live, standIn: StillFrames(picture)) { begun += 1 }

        #expect(feed.frame?.size == Vector2(40, 30))
        #expect(feed.frameSize == Vector2(40, 30))
        // The first read in a window asks the live feed to begin, once.
        _ = feed.frame
        #expect(begun == 1)

        live.deliver(liveFrame)
        // The size is the size of the picture last handed out, so the two
        // agree within a frame for a reader that takes the frame first.
        #expect(feed.frameSize == Vector2(40, 30))
        #expect(feed.frame?.size == Vector2(64, 48))
        #expect(feed.frameSize == Vector2(64, 48))
        #expect(feed.standIn == nil)
    }

    @Test func aTapIsHandedThePictureAndThenOnlyTheLiveFrames() throws {
        let live = ManualFeed()
        // Never started, so the only pictures are the ones handed over here.
        let still = StillFrames(picture)
        let feed = StandInFeed(live, standIn: still) {}
        let seen = Seen()

        // Installing a tap hands the picture over at once.
        feed.frameTap = Self.tap(into: seen)
        #expect(seen.all == [40])
        let picturesSide = try #require(still.frameTap)
        picturesSide(picture.currentCGImage())
        #expect(seen.all == [40, 40])

        live.deliver(liveFrame)
        #expect(seen.all == [40, 40, 64])
        // A picture still on its way from the picture's thread is stopped.
        picturesSide(picture.currentCGImage())
        #expect(seen.all == [40, 40, 64])

        // The next read lets the picture go, and the live frames keep coming.
        _ = feed.frame
        #expect(still.frameTap == nil)
        live.deliver(liveFrame)
        #expect(seen.all == [40, 40, 64, 64])
    }

    @Test func aTapInstalledAfterTheLiveFeedDeliversNeverSeesThePicture() {
        let live = ManualFeed()
        let feed = StandInFeed(live, standIn: StillFrames(picture)) {}
        live.deliver(liveFrame)

        let seen = Seen()
        feed.frameTap = Self.tap(into: seen)
        #expect(seen.all.isEmpty)
        live.deliver(liveFrame)
        #expect(seen.all == [64])
    }

    /// The headless flag is put back before the test returns, with no
    /// suspension in between, so no other test runs while it is up.
    @Test func aRunWithNoWindowNeverAsks() {
        let live = ManualFeed()
        var begun = 0
        let feed = StandInFeed(live, standIn: StillFrames(picture)) { begun += 1 }

        let headless = OllinApp.isRenderingHeadless
        OllinApp.isRenderingHeadless = true
        let size = feed.frame?.size
        feed.frameTap = Self.tap(into: Seen())
        OllinApp.isRenderingHeadless = headless

        #expect(size == Vector2(40, 30))
        #expect(begun == 0)
        // The same feed in a window asks at its first read.
        _ = feed.frame
        #expect(begun == 1)
    }

    // MARK: A stand-in that is not a still

    let filmFrame = Image(width: 52, height: 36, color: .gray)

    @Test func aFeedOfAnyKindStandsInUntilTheFirstLiveFrame() {
        let live = ManualFeed()
        let film = ManualFeed()
        let feed = StandInFeed(live, standIn: film) {}

        // A film still opening has no frame, and says so in its own words.
        #expect(feed.frame == nil)
        #expect(feed.waitingMessage == film.waitingMessage)
        film.deliver(filmFrame)
        #expect(feed.frame?.size == Vector2(52, 36))
        #expect(feed.frameSize == Vector2(52, 36))

        // The film's frames reach a tap, and the live feed's first one ends that.
        let seen = Seen()
        feed.frameTap = Self.tap(into: seen)
        film.deliver(filmFrame)
        #expect(seen.all == [52])
        live.deliver(liveFrame)
        film.deliver(filmFrame)
        #expect(seen.all == [52, 64])

        #expect(feed.frame?.size == Vector2(64, 48))
        #expect(feed.frameSize == Vector2(64, 48))
        #expect(feed.standIn == nil)
        #expect(film.frameTap == nil)
    }

    @Test func theStandInIsLetGoAtTheHandOver() {
        let live = ManualFeed()
        weak var film: ManualFeed?
        let feed: StandInFeed = {
            let made = ManualFeed()
            film = made
            return StandInFeed(live, standIn: made) {}
        }()
        #expect(film != nil)
        live.deliver(liveFrame)
        _ = feed.frame
        // Nothing else holds it, so a film stops playing here.
        #expect(film == nil)
    }

    @Test func isLiveSaysWhichOfTheTwoAFrameReads() {
        let live = ManualFeed()
        let film = ManualFeed()
        let feed = StandInFeed(live, standIn: film) {}
        // The camera is running behind the prompt's answer and has no frame
        // yet: the sketch is still reading the film.
        live.isLive = true
        #expect(!feed.isLive)
        film.deliver(filmFrame)
        _ = feed.frame
        #expect(!feed.isLive)

        live.deliver(liveFrame)
        // The answer changes with the frame that changes, not before it.
        #expect(!feed.isLive)
        #expect(feed.frame?.size == Vector2(64, 48))
        #expect(feed.isLive)

        // A stand-in that is itself live says so while it stands in.
        let screen = ManualFeed()
        screen.isLive = true
        #expect(StandInFeed(ManualFeed(), standIn: screen) {}.isLive)
    }

    @Test func aStandInFollowsAnExportsClockThroughTheFeed() {
        let live = ManualFeed()
        let film = ManualFeed()
        let feed = StandInFeed(live, standIn: film) {}
        let advancing: any FrameAdvancing = feed
        advancing.advance(by: 0.25)
        advancing.advance(to: 1.5)
        #expect(film.steps == [0.25])
        #expect(film.clock == [1.5])
        // The live feed keeps its own time and is never stepped from here.
        #expect(live.steps.isEmpty && live.clock.isEmpty)

        live.deliver(liveFrame)
        _ = feed.frame
        advancing.advance(by: 0.25)
        advancing.advance(to: 1.75)
        #expect(film.steps == [0.25] && film.clock == [1.5])
        #expect(live.steps.isEmpty && live.clock.isEmpty)
    }

    /// The lines written for the developer, in order.
    final class Notes {
        var lines: [String] = []
    }

    /// What `Camera.or` hands back for a machine in `status`, with the seams
    /// put back before this returns, and how many times the stand-in was
    /// built. Nothing here suspends.
    private func feedOr(status: AVAuthorizationStatus, photoOnly: Bool = false, notes: Notes = Notes(),
                        standIn: ManualFeed, asked: inout Int)
        -> (feed: any FrameSource & VideoFeed, built: Int) {
        let kept = (Camera.authorizationStatus, Camera.requestAccess, Camera.photoOnly, Camera.note)
        defer { (Camera.authorizationStatus, Camera.requestAccess, Camera.photoOnly, Camera.note) = kept }
        Camera.photoOnly = photoOnly
        Camera.authorizationStatus = { status }
        var requests = 0
        Camera.requestAccess = { _ in requests += 1 }
        Camera.note = { notes.lines.append($0) }
        var built = 0
        let feed = Camera.or {
            built += 1
            return standIn
        }
        _ = feed.frame
        asked = requests
        return (feed, built)
    }

    @Test func orOnAMachineNeverAskedWaitsBehindTheStandIn() throws {
        let film = ManualFeed()
        film.deliver(filmFrame)
        var asked = 0
        let notes = Notes()
        let (feed, built) = feedOr(status: .notDetermined, notes: notes, standIn: film, asked: &asked)
        let waiting = try #require(feed as? StandInFeed)
        #expect(waiting.live is Camera)
        #expect(waiting.standIn === film)
        #expect(built == 1)
        // The first read in a window is what asks, once.
        #expect(asked == 1)
        #expect(feed.frame?.size == Vector2(52, 36))
        #expect(!feed.isLive)
        #expect(notes.lines.isEmpty)
    }

    @Test func orOnAMachineThatRefusedHandsBackTheStandInItselfAndSaysWhy() {
        let film = ManualFeed()
        var asked = 0
        let notes = Notes()
        let (feed, built) = feedOr(status: .denied, notes: notes, standIn: film, asked: &asked)
        #expect(feed === film)
        #expect(built == 1)
        #expect(asked == 0)
        #expect(notes.lines.count == 1)
        #expect(notes.lines.first?.contains("its stand-in") == true)
        #expect(notes.lines.first?.contains("Privacy & Security") == true)
    }

    @Test func orUnderThePhotoFlagNeverTouchesTheCamera() {
        let film = ManualFeed()
        var asked = 0
        let notes = Notes()
        // Even on a machine never asked, where the camera would have prompted.
        let (feed, built) = feedOr(status: .notDetermined, photoOnly: true, notes: notes,
                                   standIn: film, asked: &asked)
        #expect(feed === film)
        #expect(built == 1)
        #expect(asked == 0)
        #expect(notes.lines.isEmpty)
    }

    /// The headless flag is put back before the test returns, with no
    /// suspension in between.
    @Test func orInARunWithNoWindowNeverAsks() throws {
        let film = ManualFeed()
        film.deliver(filmFrame)
        let kept = (Camera.authorizationStatus, Camera.requestAccess, Camera.photoOnly)
        defer { (Camera.authorizationStatus, Camera.requestAccess, Camera.photoOnly) = kept }
        Camera.photoOnly = false
        Camera.authorizationStatus = { .notDetermined }
        var asked = 0
        Camera.requestAccess = { _ in asked += 1 }

        let headless = OllinApp.isRenderingHeadless
        OllinApp.isRenderingHeadless = true
        let feed = Camera.or { film }
        let size = feed.frame?.size
        feed.frameTap = Self.tap(into: Seen())
        let live = feed.isLive
        OllinApp.isRenderingHeadless = headless

        #expect(size == Vector2(52, 36))
        #expect(!live)
        #expect(asked == 0)
    }

    /// What a never-asked camera hands back, with the seams put back before
    /// this returns: nothing here suspends, so no other test sees them. The
    /// feed keeps the note's destination it was made with, so a line written
    /// after an answer still lands in `notes`.
    private func feedOnAMachineNeverAsked(
        status: AVAuthorizationStatus = .notDetermined,
        notes: Notes = Notes(),
        request: @escaping (@escaping @Sendable (Bool) -> Void) -> Void
    ) -> any FrameSource & VideoFeed {
        let kept = (Camera.authorizationStatus, Camera.requestAccess, Camera.photoOnly, Camera.note)
        defer { (Camera.authorizationStatus, Camera.requestAccess, Camera.photoOnly, Camera.note) = kept }
        Camera.photoOnly = false
        Camera.authorizationStatus = { status }
        Camera.requestAccess = request
        Camera.note = { notes.lines.append($0) }
        let feed = Camera.orStill(picture)
        // The first read is what asks.
        _ = feed.frame
        return feed
    }

    @Test func aCameraNeverAskedForWaitsBehindThePicture() {
        var asked = 0
        let notes = Notes()
        let feed = feedOnAMachineNeverAsked(notes: notes) { _ in asked += 1 }
        #expect(feed is StandInFeed)
        #expect(asked == 1)
        #expect(feed.frame?.size == Vector2(40, 30))
        #expect(asked == 1)
        // Waiting on an answer is not a refusal, and nothing is said.
        #expect(notes.lines.isEmpty)
    }

    @Test func aRefusalLeavesThePictureAndSaysSoOnce() async throws {
        let answer = OSAllocatedUnfairLock<Held<(@Sendable (Bool) -> Void)?>>(initialState: Held(nil))
        let notes = Notes()
        let feed = feedOnAMachineNeverAsked(notes: notes) { handler in answer.withLock { $0.value = handler } }
        let camera = try #require((feed as? StandInFeed)?.live as? Camera)

        let refuse = try #require(answer.withLock { $0.value })
        refuse(false)
        let reason = try await OllinTestSupport.waitFor(timeout: 30) { camera.unavailableReason }
        #expect(reason.contains("refused"))
        #expect(!camera.isRunning)

        // The picture stays, and the frame that finds the refusal says why,
        // once, with the place to allow the camera.
        #expect(feed.frame?.size == Vector2(40, 30))
        _ = feed.frame
        #expect(notes.lines.count == 1)
        #expect(notes.lines.first?.contains("refused") == true)
        #expect(notes.lines.first?.contains("its picture") == true)
        #expect(notes.lines.first?.contains("Privacy & Security") == true)
    }

    @Test func aCameraAlreadyDeniedGivesThePictureAsksNothingAndSaysWhy() {
        var asked = 0
        let notes = Notes()
        let feed = feedOnAMachineNeverAsked(status: .denied, notes: notes) { _ in asked += 1 }
        #expect(feed is StillFrames)
        #expect(asked == 0)
        #expect(notes.lines.count == 1)
        #expect(notes.lines.first?.contains("Privacy & Security") == true)
    }
}

extension CameraOrStillTests.ManualFeed: @MainActor FrameAdvancing {
    func advance(by dt: Double) { steps.append(dt) }
    func advance(to time: Double) { clock.append(time) }
}
