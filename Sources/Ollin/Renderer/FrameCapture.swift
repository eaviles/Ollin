import Foundation
import Metal

/// Metal's own frame debugger, aimed at one frame of a running sketch.
///
/// The profiler answers "which side of the frame is the bottleneck, and how much
/// work is in it". When the answer is "the GPU, and I need to know which pass",
/// this hands the frame to Xcode: `captureGPUFrame()` writes a `.gputrace` file
/// holding every command the frame issued, which opens in Xcode's GPU debugger
/// with per-pass timings, the pipeline state, and every bound resource.
///
/// Two things are worth knowing before reaching for it:
///
/// - The process must be launched with `MTL_CAPTURE_ENABLED=1` in its
///   environment. Metal refuses to capture otherwise, and the refusal is
///   reported here with the line to run rather than a silent no-op.
/// - The trace holds one frame and can be large. It is written where you ask,
///   defaulting to the current directory.
extension Sketch {

    /// Capture the next frame this sketch renders and write it as a `.gputrace`
    /// file. Call it from `draw()` (on a key press, say), or use the host's
    /// Capture GPU Frame command.
    ///
    /// - Parameter path: where to write the trace. A relative path is resolved
    ///   against the current directory. Defaults to the sketch's own name plus
    ///   the frame number.
    ///
    /// The frame you ask from is the frame you get: the request is taken between
    /// your `draw()` and the render it feeds, so the trace holds exactly the
    /// commands that drew what you were looking at.
    public func captureGPUFrame(to path: String? = nil) {
        let name = path ?? "\(String(describing: type(of: self)))-frame-\(frameCount).gputrace"
        pendingGPUCapture = URL(fileURLWithPath: name,
                                relativeTo: URL(fileURLWithPath: FileManager.default.currentDirectoryPath))
    }
}

/// Whether Metal will allow a programmatic capture in this process, with the
/// reason when it will not. Read once and reported to the console, so a sketch
/// that asks for a capture is told why nothing appeared.
enum GPUCaptureAvailability {
    case ready
    case notEnabled
    case unsupported

    static var current: GPUCaptureAvailability {
        guard ProcessInfo.processInfo.environment["MTL_CAPTURE_ENABLED"] == "1" else {
            return .notEnabled
        }
        guard MTLCaptureManager.shared().supportsDestination(.gpuTraceDocument) else {
            return .unsupported
        }
        return .ready
    }

    var advice: String {
        switch self {
        case .ready:
            return ""
        case .notEnabled:
            return """
                Ollin: a GPU frame capture was asked for, and Metal will not capture \
                unless the process is launched with capture enabled. Run the sketch again as:
                    MTL_CAPTURE_ENABLED=1 ollin <your sketch>.swift
                """
        case .unsupported:
            return "Ollin: this device cannot write a GPU trace document, so the frame was not captured."
        }
    }
}

extension MetalRenderer {

    /// Begin capturing the frame that is about to be encoded. Returns whether
    /// the capture started, so the caller knows whether to stop one.
    func beginGPUCapture(to url: URL) -> Bool {
        let availability = GPUCaptureAvailability.current
        guard availability == .ready else {
            print(availability.advice)
            return false
        }
        let manager = MTLCaptureManager.shared()
        guard !manager.isCapturing else { return false }
        // A capture refuses to overwrite, so clear a trace of the same name
        // rather than failing on the second capture of a session.
        try? FileManager.default.removeItem(at: url)
        let descriptor = MTLCaptureDescriptor()
        descriptor.captureObject = device
        descriptor.destination = .gpuTraceDocument
        descriptor.outputURL = url
        do {
            try manager.startCapture(with: descriptor)
        } catch {
            print("Ollin: the GPU frame capture could not start: \(error.localizedDescription)")
            return false
        }
        // The pass list of the captured frame, printed beside it: it answers
        // "what is this frame made of" without opening the trace at all.
        passLog.removeAll(keepingCapacity: true)
        logsPassNames = true
        return true
    }

    /// Finish the capture started for this frame and report where it went.
    func endGPUCapture(at url: URL) {
        logsPassNames = false
        let manager = MTLCaptureManager.shared()
        guard manager.isCapturing else { return }
        manager.stopCapture()
        let passes = passLog.isEmpty ? "no passes" : passLog.joined(separator: ", ")
        print("""
            Ollin: wrote a GPU frame capture to \(url.path)
            Open it in Xcode to step through the frame. Its \(passLog.count) passes, in order: \(passes)
            """)
        passLog.removeAll(keepingCapacity: true)
    }
}
