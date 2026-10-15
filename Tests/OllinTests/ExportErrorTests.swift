import Foundation
import ImageIO
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

    // MARK: - The headless calls that hand back a picture

    /// A renderer that will not start (in a real run, a shader that stopped
    /// compiling) stops every headless call with the one shape: an
    /// `.unrendered` error carrying the renderer's own message, where the
    /// calls that hand back a picture used to answer `nil` and print a line.
    /// Those have no file, so their `path` is empty; the export beside them
    /// names its file. Nothing is left marked as rendering headless.
    @Test(.enabled(if: Snapshot.hasMetal))
    func aRendererThatWillNotStartStopsEveryHeadlessCallTheSameWay() throws {
        OllinApp.plantedRendererRefusal = "a planted shader error"
        defer { OllinApp.plantedRendererRefusal = nil }
        let path = ollinTempPath("ollin-refused-still.png")
        let failures: [(String, ExportError?)] = [
            ("image(of:)", error { _ = try OllinApp.image(of: Tick()) }),
            ("contactSheet(of:seeds:)", error { _ = try OllinApp.contactSheet(of: { Tick() }, seeds: [1, 2]) }),
            ("contactSheet(of:sweeping:)", error {
                _ = try OllinApp.contactSheet(of: { Swept() }, sweeping: \.$radius, values: [4, 8])
            }),
            ("plates(of:)", error { _ = try OllinApp.plates(of: Tick(), profile: .genericCMYK) }),
            ("separations(of:)", error { _ = try OllinApp.separations(of: Tick(), inks: [.blue]) }),
            ("export", error { try OllinApp.export(Tick(), to: path) }),
        ]
        for (call, refused) in failures {
            #expect(refused?.kind == .unrendered, "\(call)")
            #expect(refused?.problem.contains("a planted shader error") == true, "\(call)")
            #expect(refused?.path == (call == "export" ? path : ""), "\(call)")
        }
        #expect(!FileManager.default.fileExists(atPath: path))
        #expect(!OllinApp.isRenderingHeadless)
    }

    /// The separations ask for what they separate into before anything draws,
    /// and say how to name it.
    @Test func separationsWithNothingToSeparateIntoAreRefused() throws {
        let plates = try #require(error { _ = try OllinApp.plates(of: Tick()) })
        #expect(plates.kind == .unsupported)
        #expect(plates.problem.contains("printProfile"))
        let spots = try #require(error { _ = try OllinApp.separations(of: Tick()) })
        #expect(spots.kind == .unsupported)
        #expect(spots.problem.contains("printInks"))
    }

    /// A sweep over a parameter the sketch declares.
    final class Swept: Sketch {
        @Param(1 ... 20) var radius = 6.0
        override var canvasSize: CanvasSize { .square(32) }
        override func draw() { background(.black); drawCircle(16, 16, radius) }
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

    // MARK: - A frame the GPU threw away

    /// A picture that piles up: each frame adds a translucent mark onto the
    /// last, so a frame that never ran leaves its mark missing for good.
    final class Pile: Sketch {
        override var canvasSize: CanvasSize { .square(64) }
        override func setup() { noClear(); background(.black) }
        override func draw() {
            fill(Color.white.withAlpha(0.25))
            noStroke()
            drawCircle(8 + Double(frameCount) * 12, 32, 6)
        }
    }

    /// The frames an export of `sketch` writes, read back as bytes, with the
    /// commits in `discards` thrown away by the GPU.
    private func exportedFrames(_ sketch: Sketch, frames: Int, discards: Set<Int>) throws -> [[UInt8]] {
        OllinApp.plantedDiscards = discards
        defer { OllinApp.plantedDiscards = [] }
        let folder = ollinTempPath("ollin-discard-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(atPath: folder) }
        try OllinApp.exportSequence(sketch, to: folder, frames: frames, fps: 30)
        return try (1...frames).map { index in
            let path = (folder as NSString).appendingPathComponent(String(format: "frame-%05d.png", index))
            let source = try #require(CGImageSourceCreateWithURL(URL(fileURLWithPath: path) as CFURL, nil))
            return pixels(of: try #require(CGImageSourceCreateImageAtIndex(source, 0, nil)))
        }
    }

    /// Another program's fault can make the GPU throw away a command buffer
    /// that was only waiting its turn. A frame whose picture builds on nothing
    /// from the frame before is drawn again, so the file holds the frame it
    /// would have held: the still and every frame of a sequence come out byte
    /// for byte as they do when nothing was thrown away.
    ///
    /// Until 2026-10-15 the export wrote the frame anyway, half drawn, with
    /// one line on standard error: a peer's nine-hour render kept a frame of
    /// green blocks that way.
    @Test(.enabled(if: Snapshot.hasMetal))
    func aFrameTheGPUThrewAwayIsDrawnAgain() throws {
        let clean = pixels(of: try OllinApp.image(of: Tick(), frame: 3))
        OllinApp.plantedDiscards = [0]
        let redrawn = pixels(of: try OllinApp.image(of: Tick(), frame: 3))
        OllinApp.plantedDiscards = []
        #expect(redrawn == clean)

        let sequence = try exportedFrames(Tick(), frames: 3, discards: [])
        #expect(try exportedFrames(Tick(), frames: 3, discards: [1]) == sequence)
        #expect(try exportedFrames(Tick(), frames: 3, discards: [0, 2, 4]) == sequence)
    }

    /// A frame the GPU keeps throwing away stops the export with the GPU's
    /// own reason, naming the frame, and writes nothing for it.
    @Test(.enabled(if: Snapshot.hasMetal))
    func aFrameTheGPUKeepsThrowingAwayStopsTheExport() throws {
        OllinApp.plantedDiscards = Set(0...MetalRenderer.headlessRedraws)
        defer { OllinApp.plantedDiscards = [] }
        let still = try #require(error { _ = try OllinApp.image(of: Tick()) })
        #expect(still.kind == .unrendered)
        #expect(still.problem.contains("frame 0 did not come back from the GPU"))
        #expect(still.problem.contains("victim of GPU error/recovery"))

        let folder = ollinTempPath("ollin-discarded-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(atPath: folder) }
        OllinApp.plantedDiscards = Set(1...(1 + MetalRenderer.headlessRedraws))
        let sequence = try #require(error { try OllinApp.exportSequence(Tick(), to: folder, frames: 3, fps: 30) })
        #expect(sequence.kind == .unrendered)
        #expect(sequence.frame == 1)
        #expect(sequence.problem.contains("victim of GPU error/recovery"))
        #expect(FileManager.default.fileExists(atPath: folder + "/frame-00001.png"))
        #expect(!FileManager.default.fileExists(atPath: folder + "/frame-00002.png"))
    }

    /// A picture that builds on the frame before cannot be drawn again,
    /// since the buffer thrown away may have left part of its frame behind,
    /// so the export stops at that frame rather than write a pile with a mark
    /// missing or doubled. A still past the lost frame stops too, though its
    /// own frame came back.
    @Test(.enabled(if: Snapshot.hasMetal))
    func aPileTheGPUThrewAwayStopsTheExport() throws {
        let folder = ollinTempPath("ollin-pile-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(atPath: folder) }
        OllinApp.plantedDiscards = [1]
        defer { OllinApp.plantedDiscards = [] }
        let sequence = try #require(error { try OllinApp.exportSequence(Pile(), to: folder, frames: 3, fps: 30) })
        #expect(sequence.kind == .unrendered)
        #expect(sequence.frame == 1)
        #expect(!FileManager.default.fileExists(atPath: folder + "/frame-00002.png"))

        let still = try #require(error { _ = try OllinApp.image(of: Pile(), frame: 3) })
        #expect(still.kind == .unrendered)
        #expect(still.problem.contains("builds on the frame before"))
    }
}
