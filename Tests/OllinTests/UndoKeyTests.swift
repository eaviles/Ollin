import AppKit
import Metal
import Testing
@testable import Ollin

/// The undo pair, Command-Z and Shift-Command-Z, never reaches a sketch's key
/// hooks. A host with nothing to undo leaves the key unclaimed, and AppKit
/// then hands it to the canvas as a plain key press, where `keyPressed()`
/// used to read a `z` (a preset menu advanced under an undo the inspector
/// never offered). Every other key, Command with another letter included,
/// still arrives as it did.
@Suite
@MainActor
struct UndoKeyTests {
    private final class KeyCountingSketch: Sketch {
        var presses: [Character?] = []
        var releases = 0
        override func keyPressed() { presses.append(key) }
        override func keyReleased() { releases += 1 }
    }

    private func event(_ type: NSEvent.EventType, _ characters: String,
                       _ flags: NSEvent.ModifierFlags) throws -> NSEvent {
        try #require(NSEvent.keyEvent(
            with: type, location: .zero, modifierFlags: flags, timestamp: 0, windowNumber: 0,
            context: nil, characters: characters, charactersIgnoringModifiers: characters,
            isARepeat: false, keyCode: 6))
    }

    @Test func theUndoPairStopsAtTheCanvas() throws {
        let device = try #require(MTLCreateSystemDefaultDevice())
        let sketch = KeyCountingSketch()
        let view = makeOllinMTKView(device: device, size: CGSize(width: 64, height: 64), sketch: sketch)

        view.keyDown(with: try event(.keyDown, "z", .command))
        view.keyUp(with: try event(.keyUp, "z", .command))
        view.keyDown(with: try event(.keyDown, "Z", [.command, .shift]))
        view.keyUp(with: try event(.keyUp, "Z", [.command, .shift]))
        #expect(sketch.presses.isEmpty, "Command-Z reached keyPressed")
        #expect(sketch.releases == 0, "Command-Z reached keyReleased")

        // A plain z, and Command with another letter, still reach the sketch.
        view.keyDown(with: try event(.keyDown, "z", []))
        view.keyUp(with: try event(.keyUp, "z", []))
        view.keyDown(with: try event(.keyDown, "k", .command))
        #expect(sketch.presses == ["z", "k"])
        #expect(sketch.releases == 1)
    }
}
