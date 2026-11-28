import AVFoundation
import Foundation
import Testing
import Ollin
@testable import OllinVision

/// A camera's start may wait on the system's prompt. What the sketch does
/// meanwhile decides what the answer starts: nothing, after a `stop()`, and
/// the camera once, however many times `start()` was called.
@MainActor
@Suite(.serialized) struct CameraLifecycleTests {

    /// The answers the system's prompt has been asked for and has not given.
    final class Prompt: @unchecked Sendable {
        var pending: [@Sendable (Bool) -> Void] = []
        func answer(_ granted: Bool) {
            let all = pending
            for answer in all { answer(granted) }
        }
    }

    final class Opens { var count = 0 }

    /// Run `body` on a machine never asked for the camera, with the prompt
    /// replaced by `prompt` and the device by a count. The seams are back in
    /// place before this returns, except the device's: the answer opens it
    /// later, so it is the caller's to put back.
    private func neverAsked(_ prompt: Prompt, _ body: () throws -> Void) rethrows {
        let kept = (Camera.authorizationStatus, Camera.requestAccess, Camera.photoOnly)
        defer { (Camera.authorizationStatus, Camera.requestAccess, Camera.photoOnly) = kept }
        Camera.photoOnly = false
        Camera.authorizationStatus = { .notDetermined }
        Camera.requestAccess = { prompt.pending.append($0) }
        try body()
    }

    /// Let the main actor run what an answer queued on it.
    private func settle() async {
        for _ in 0..<8 { await Task { @MainActor in }.value }
    }

    @Test func stoppingWhileThePromptIsUpCallsTheStartOff() async throws {
        let opens = Opens(), prompt = Prompt()
        let keptDevice = Camera.openDevice
        defer { Camera.openDevice = keptDevice }
        Camera.openDevice = { _ in opens.count += 1 }

        let camera = Camera()
        try neverAsked(prompt) { try camera.start() }
        #expect(prompt.pending.count == 1 && !camera.isRunning)

        camera.stop()
        prompt.answer(true)
        await settle()
        #expect(opens.count == 0, "the camera opened after stop() was called")
        #expect(!camera.isRunning)
        #expect(camera.unavailableReason == nil)
    }

    @Test func aSecondStartWhileThePromptIsUpOpensTheCameraOnce() async throws {
        let opens = Opens(), prompt = Prompt()
        let keptDevice = Camera.openDevice
        defer { Camera.openDevice = keptDevice }
        Camera.openDevice = { _ in opens.count += 1 }

        let camera = Camera()
        try neverAsked(prompt) {
            try camera.start()
            try camera.start()
            camera.stop()
            try camera.start()
        }
        #expect(prompt.pending.count == 2, "asked \(prompt.pending.count) times: once, and once more after the stop")
        prompt.answer(true)
        await settle()
        #expect(camera.isRunning)
        #expect(opens.count == 1, "the camera was opened \(opens.count) times")
    }

    /// A refusal still says so, and starts nothing.
    @Test func aRefusalStartsNothing() async throws {
        let opens = Opens(), prompt = Prompt()
        let keptDevice = Camera.openDevice
        defer { Camera.openDevice = keptDevice }
        Camera.openDevice = { _ in opens.count += 1 }

        let camera = Camera()
        try neverAsked(prompt) { try camera.start() }
        prompt.answer(false)
        await settle()
        #expect(opens.count == 0 && !camera.isRunning)
        #expect(camera.unavailableReason?.contains("refused") == true)
    }
}
