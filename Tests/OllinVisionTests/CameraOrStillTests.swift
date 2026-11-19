import Testing
import AVFoundation
import CoreGraphics
import Foundation
import os
import Ollin
@testable import OllinVision
import OllinTestSupport

/// `Camera.orStill` on a machine where the camera has never been asked for:
/// the picture stands in while the system's prompt is up, the camera takes
/// over at its first frame, and a run with no window never asks. No test here
/// touches a capture device or puts a prompt on the screen: the permission's
/// state and the prompt are the seams `Camera` keeps for exactly this, and
/// the hand-over itself is driven through a feed delivered by hand.
@MainActor
@Suite struct CameraOrStillTests {

    /// A feed the test delivers by hand, standing in for a camera.
    final class ManualFeed: FrameSource, VideoFeed {
        var frameTap: FrameTap?
        var frame: Image?
        var frameSize: Vector2? { frame?.size }

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

    /// The lines written for the developer, in order.
    final class Notes {
        var lines: [String] = []
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
