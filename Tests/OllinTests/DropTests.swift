@testable import Ollin
import AppKit
import Testing

/// Files dropped on the window. The laws: a drop moves the pointer to where it
/// landed, queues the paths, and fires the hook once; the draining read hands
/// every path over once, oldest first, and then nothing; drops that nobody
/// read pile up in order; an empty drop is not a drop; and the canvas view
/// registers for file URLs and reads only those off a pasteboard.
@Suite
@MainActor
struct DropTests {

    private final class Catcher: Sketch {
        var drops = 0
        var seenAtDrop: [String] = []
        var pointerAtDrop = Vector2(0, 0)
        override func filesDropped() {
            drops += 1
            pointerAtDrop = mouse
            // Read at the drop, or leave them for a poll: this catcher reads
            // only when told to, so both paths can be checked.
            if readsAtDrop { seenAtDrop = droppedFiles() }
        }
        var readsAtDrop = false
    }

    @Test func aDropMovesThePointerQueuesThePathsAndFiresTheHookOnce() {
        let sketch = Catcher()
        sketch.handleDroppedFiles(["/pictures/a.png", "/notes/b.txt"], at: Vector2(120, 340))
        #expect(sketch.drops == 1)
        #expect(sketch.mouseX == 120 && sketch.mouseY == 340)
        #expect(sketch.pointerAtDrop == Vector2(120, 340), "the pointer has moved by the time the hook runs")
        #expect(sketch.droppedFiles() == ["/pictures/a.png", "/notes/b.txt"])
        #expect(sketch.droppedFiles().isEmpty, "reading empties the list")
    }

    @Test func theHookCanReadAtTheDrop() {
        let sketch = Catcher()
        sketch.readsAtDrop = true
        sketch.handleDroppedFiles(["/a.jpg"], at: Vector2(1, 2))
        #expect(sketch.seenAtDrop == ["/a.jpg"])
        #expect(sketch.droppedFiles().isEmpty, "the hook took them")
    }

    @Test func unreadDropsPileUpInOrder() {
        let sketch = Catcher()
        sketch.handleDroppedFiles(["/one"], at: Vector2(0, 0))
        sketch.handleDroppedFiles(["/two", "/three"], at: Vector2(5, 5))
        #expect(sketch.drops == 2)
        #expect(sketch.droppedFiles() == ["/one", "/two", "/three"])
    }

    @Test func anEmptyDropIsNotADrop() {
        let sketch = Catcher()
        sketch.handleDroppedFiles([], at: Vector2(9, 9))
        #expect(sketch.drops == 0)
        #expect(sketch.mouseX == 0 && sketch.mouseY == 0)
    }

    @Test func theCanvasRegistersForFilesAndReadsOnlyThose() throws {
        let device = try #require(MTLCreateSystemDefaultDevice())
        let sketch = Catcher()
        let view = makeOllinMTKView(device: device, size: CGSize(width: 200, height: 100), sketch: sketch)
        #expect(view.registeredDraggedTypes.contains(.fileURL))

        let files = NSPasteboard(name: NSPasteboard.Name("ollin-drop-test-files"))
        files.clearContents()
        let url = URL(fileURLWithPath: "/tmp/ollin-drop-test.png")
        files.writeObjects([url as NSURL])
        #expect(OllinMTKView.fileURLs(on: files)?.map(\.path) == [url.path])

        let words = NSPasteboard(name: NSPasteboard.Name("ollin-drop-test-words"))
        words.clearContents()
        words.setString("not a file", forType: .string)
        #expect(OllinMTKView.fileURLs(on: words) == nil, "text is not a drop the canvas takes")
    }
}
