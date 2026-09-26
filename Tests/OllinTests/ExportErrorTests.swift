import Foundation
@testable import Ollin
import Testing

/// What an export does when it cannot finish: it throws an `ExportError`
/// naming the file, the frame it reached, and what went wrong, and it leaves
/// the process running and the path clear of a partial file. Before this, each
/// of these was a `fatalError`, so one frame an encoder refused (which a CI
/// runner's did, on a test that passed on the next run) ended the whole test
/// process rather than one test.
///
/// Serialized because the planted refusal is a process-wide setting and the
/// exports share the GPU; gated on a Metal device where an export has to draw.
@Suite(.serialized)
@MainActor
struct ExportErrorTests {

    /// A small moving picture that counts what it was asked to do, so a test
    /// can say an export was refused before anything drew.
    final class Tick: Sketch {
        var setups = 0
        var draws = 0
        override var canvasSize: CanvasSize { .square(64) }
        override func setup() { setups += 1 }
        override func draw() {
            draws += 1
            background(.black)
            fill(.white)
            drawCircle(8 + time * 120, 32, 6)
        }
    }

    private func error(_ export: () throws -> Void) -> ExportError? {
        do {
            try export()
            return nil
        } catch let error as ExportError {
            return error
        } catch {
            Issue.record("an export threw something other than an ExportError: \(error)")
            return nil
        }
    }

    private var missingFolder: String {
        ollinTempPath("ollin-no-such-folder-\(UUID().uuidString)")
    }

    // MARK: - The request itself

    /// A file name no writer takes is refused before the sketch is even set
    /// up, so asking for the impossible costs nothing.
    @Test func anExtensionNoWriterTakesIsRefusedBeforeAnythingDraws() throws {
        let path = ollinTempPath("ollin-export-error.avi")
        let sketch = Tick()
        let refused = try #require(error { try OllinApp.exportVideo(sketch, to: path, frames: 4, fps: 30) })
        #expect(refused.kind == .unsupported)
        #expect(refused.path == path)
        #expect(refused.frame == nil)
        #expect(refused.problem.contains(".avi"))
        #expect(refused.description == "\(path): \(refused.problem)")
        #expect(sketch.setups == 0 && sketch.draws == 0)
        #expect(!FileManager.default.fileExists(atPath: path))
    }

    @Test func aCodecTheContainerCannotCarryIsRefused() throws {
        let path = ollinTempPath("ollin-export-error-prores.mp4")
        let refused = try #require(error {
            try OllinApp.exportVideo(Tick(), to: path, frames: 4, fps: 30, codec: .proRes422)
        })
        #expect(refused.kind == .unsupported)
        #expect(refused.problem.contains(".mov"))
    }

    /// Asking for no frames at all was a silent return; it is a request the
    /// call can see is wrong, so it says so, for every export that counts
    /// frames.
    @Test func askingForNoFramesIsRefused() throws {
        let kinds: [ExportError.Kind?] = [
            error { try OllinApp.exportVideo(Tick(), to: ollinTempPath("ollin-zero.mp4"), frames: 0) }?.kind,
            error { try OllinApp.exportGIF(Tick(), to: ollinTempPath("ollin-zero.gif"), frames: 0) }?.kind,
            error { try OllinApp.exportSequence(Tick(), to: ollinTempPath("ollin-zero-seq"), frames: 0) }?.kind,
        ]
        #expect(kinds == [.unsupported, .unsupported, .unsupported])
    }

    /// A sweep over a parameter the sketch never declared names what it does
    /// declare, rather than failing to draw.
    @Test func sweepingAParameterTheSketchLacksNamesTheOnesItHas() throws {
        let refused = try #require(error {
            try OllinApp.exportContactSheet({ Tick() }, to: ollinTempPath("ollin-sweep.png"),
                                            sweeping: "radius", values: [1, 2])
        })
        #expect(refused.kind == .unsupported)
        #expect(refused.problem.contains("'radius'"))
        #expect(refused.problem.contains("none"))
    }

    // MARK: - The writer

    /// A folder that is not there stops the writer, and the export says so
    /// rather than ending the process. The drive is left clean: the next
    /// export in the same process writes a whole clip.
    @Test(.enabled(if: Snapshot.hasMetal))
    func aFolderThatIsNotThereStopsTheVideoAndTheNextExportStillWorks() throws {
        let path = missingFolder + "/clip.mp4"
        let refused = try #require(error { try OllinApp.exportVideo(Tick(), to: path, frames: 4, fps: 30) })
        #expect(refused.kind == .unwritable)
        #expect(refused.path == path)
        #expect(!FileManager.default.fileExists(atPath: path))
        #expect(!OllinApp.isRenderingHeadless)

        let next = ollinTempPath("ollin-export-after-failure.mp4")
        defer { try? FileManager.default.removeItem(atPath: next) }
        try OllinApp.exportVideo(Tick(), to: next, frames: 4, fps: 30)
        #expect(FileManager.default.fileExists(atPath: next))
    }

    /// The failure that started this: an encoder that refuses a frame partway
    /// through. The refusal is planted on frame 5 of 12; the export throws
    /// naming that frame, and the half-written clip is gone.
    @Test(.enabled(if: Snapshot.hasMetal))
    func aFrameTheEncoderRefusesStopsTheClipAtThatFrame() throws {
        let path = ollinTempPath("ollin-export-refused.mp4")
        defer { try? FileManager.default.removeItem(atPath: path) }
        let sketch = Tick()
        OllinApp.plantedVideoRefusal = 5
        defer { OllinApp.plantedVideoRefusal = nil }
        let refused = try #require(error { try OllinApp.exportVideo(sketch, to: path, frames: 12, fps: 30) })
        #expect(refused.kind == .unwritable)
        #expect(refused.frame == 5)
        #expect(refused.problem.contains("refused frame 5"))
        #expect(sketch.draws == 6, "the export stops at the refused frame, not after the run")
        #expect(!FileManager.default.fileExists(atPath: path), "a clip stopped partway is removed")
    }

    @Test(.enabled(if: Snapshot.hasMetal))
    func aGIFThatCannotBeMadeSaysSoAndLeavesNoFile() throws {
        let path = missingFolder + "/loop.gif"
        let refused = try #require(error { try OllinApp.exportGIF(Tick(), to: path, frames: 4, fps: 25) })
        #expect(refused.kind == .unwritable)
        #expect(!FileManager.default.fileExists(atPath: path))
    }

    /// A sequence's folder that is a file already cannot be made into a folder.
    @Test func aSequenceFolderThatIsAFileIsRefused() throws {
        let path = ollinTempPath("ollin-sequence-is-a-file")
        FileManager.default.createFile(atPath: path, contents: Data("x".utf8))
        defer { try? FileManager.default.removeItem(atPath: path) }
        let refused = try #require(error { try OllinApp.exportSequence(Tick(), to: path, frames: 2, fps: 30) })
        #expect(refused.kind == .unwritable)
        #expect(refused.path == path)
    }

    /// The one-frame exports report a file they cannot write the same way.
    @Test(.enabled(if: Snapshot.hasMetal))
    func theStillsReportAFileTheyCannotWrite() throws {
        let folder = missingFolder
        let failures = [
            error { try OllinApp.export(Tick(), to: folder + "/still.png") },
            error { try OllinApp.exportSVG(Tick(), to: folder + "/still.svg") },
            error { try OllinApp.exportPDF(Tick(), to: folder + "/still.pdf") },
        ]
        #expect(failures.map(\.?.kind) == [.unwritable, .unwritable, .unwritable])
        #expect(failures.map(\.?.frame) == [0, 0, 0])
    }
}
