import AppKit
import Foundation
import Ollin
import OllinRuntime

/// `swift run OllinGuideFigures [--only <substring>]` renders every Guide
/// figure sketch (`Guide/Figures/**/*.swift`) to its committed image
/// (`Guide/Images/<chapter>/<name>.jpg`, `.png`, or `.gif`), and exits nonzero
/// if any figure fails to compile or render. This is the Guide's verification
/// gate: a listing that no longer builds fails here before it can mislead a
/// reader.
///
/// Stills default to JPEG (quality 0.85): the renderer's anti-banding dither
/// is per-pixel noise, so a PNG of even a flat diagram weighs hundreds of
/// kilobytes while the JPEG is a fraction of it and looks identical at the
/// Guide's display widths. `format=png` opts a figure back into lossless.
///
/// Each figure is an ordinary sketch file, compiled through `SketchLoader`
/// (the live host's loader) and rendered through the same off-screen path as
/// `--export`, so the committed image is exactly what a reader's own run of
/// the listing produces. Figure conventions and the directive format live in
/// `Guide/AUTHORING.md`.
@main
enum GuideFigures {

    /// Render configuration parsed from a figure's `// figure:` comment,
    /// scanned in the file's first lines. `frame=N` picks the still's frame
    /// and `format=png` makes it lossless; `gif` (plus optional `duration=`,
    /// `fps=`, `width=`) renders an animated loop instead.
    struct Directive {
        var frame = 0
        var gif = false
        var png = false
        var duration = 3.0
        var fps = 25.0
        var width: Int?

        init(source: String) {
            let head = source.split(separator: "\n", omittingEmptySubsequences: false).prefix(8)
            guard let line = head.first(where: {
                $0.trimmingCharacters(in: .whitespaces).hasPrefix("// figure:")
            }) else { return }
            let body = line.trimmingCharacters(in: .whitespaces).dropFirst("// figure:".count)
            for token in body.split(separator: " ") {
                let pair = token.split(separator: "=", maxSplits: 1)
                let key = String(pair[0])
                let value = pair.count > 1 ? String(pair[1]) : nil
                switch (key, value) {
                case ("gif", _): gif = true
                case ("format", "png"): png = true
                case ("format", "jpg"), ("format", "jpeg"): png = false
                case ("frame", let v?): frame = Int(v) ?? frame
                case ("duration", let v?): duration = Double(v) ?? duration
                case ("fps", let v?): fps = Double(v) ?? fps
                case ("width", let v?): width = Int(v)
                default:
                    warn("ignoring unknown directive token '\(token)'")
                }
            }
        }

        var stillExtension: String { png ? ".png" : ".jpg" }
    }

    @MainActor
    static func main() {
        var only: String?
        var arguments = Array(CommandLine.arguments.dropFirst())
        while let argument = arguments.first {
            arguments.removeFirst()
            switch argument {
            case "--only":
                guard let value = arguments.first else { die("--only needs a value") }
                only = value
                arguments.removeFirst()
            default:
                die("unknown argument '\(argument)' (usage: OllinGuideFigures [--only <substring>])")
            }
        }

        let root = FileManager.default.currentDirectoryPath
        let figuresDir = root + "/Guide/Figures"
        let imagesDir = root + "/Guide/Images"
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: figuresDir, isDirectory: &isDirectory),
              isDirectory.boolValue else {
            die("Guide/Figures not found under \(root); run from the repository root")
        }

        // Deterministic order so runs (and their logs) are comparable.
        var figures: [String] = []
        let enumerator = FileManager.default.enumerator(atPath: figuresDir)
        while let relative = enumerator?.nextObject() as? String {
            if relative.hasSuffix(".swift") { figures.append(relative) }
        }
        figures.sort()
        if let only {
            figures = figures.filter { $0.range(of: only, options: .caseInsensitive) != nil }
            if figures.isEmpty { die("no figure matches --only \(only)") }
        }
        guard !figures.isEmpty else {
            print("guide-figures: no figures under Guide/Figures yet, nothing to render")
            exit(0)
        }

        var failures: [String] = []
        for relative in figures {
            let sourcePath = figuresDir + "/" + relative
            guard let source = try? String(contentsOfFile: sourcePath, encoding: .utf8) else {
                warn("FAILED \(relative): unreadable")
                failures.append(relative)
                continue
            }
            let directive = Directive(source: source)
            let stem = (relative as NSString).deletingPathExtension
            let outPath = imagesDir + "/" + stem
                + (directive.gif ? ".gif" : directive.stillExtension)
            try? FileManager.default.createDirectory(
                atPath: (outPath as NSString).deletingLastPathComponent,
                withIntermediateDirectories: true)

            print("guide-figures: \(relative)")
            switch SketchLoader(sketchPath: sourcePath).load() {
            case .success(let sketch):
                if directive.gif {
                    let frames = max(1, Int((directive.duration * directive.fps).rounded()))
                    OllinApp.exportGIF(sketch, to: outPath, frames: frames,
                                       fps: directive.fps, width: directive.width)
                } else if directive.png {
                    OllinApp.export(sketch, to: outPath, frame: directive.frame)
                } else {
                    exportJPEG(sketch, to: outPath, frame: directive.frame)
                }
                if !FileManager.default.fileExists(atPath: outPath) {
                    warn("FAILED \(relative): no output written")
                    failures.append(relative)
                }
            case .failure(let error):
                warn("FAILED \(relative)\n\(error)")
                failures.append(relative)
            }
        }

        if failures.isEmpty {
            print("guide-figures: \(figures.count) figure\(figures.count == 1 ? "" : "s") rendered")
            exit(0)
        }
        warn("\(failures.count) of \(figures.count) figures failed: \(failures.joined(separator: ", "))")
        exit(1)
    }

    /// The still-figure writer: the same headless render `--export` uses,
    /// encoded as JPEG at quality 0.85 (see the type comment for why).
    @MainActor
    private static func exportJPEG(_ sketch: Sketch, to path: String, frame: Int) {
        guard let cgImage = OllinApp.image(of: sketch, frame: frame) else {
            warn("render produced no image (no Metal device?)")
            return
        }
        let rep = NSBitmapImageRep(cgImage: cgImage)
        guard let data = rep.representation(using: .jpeg,
                                            properties: [.compressionFactor: 0.85]) else {
            warn("JPEG encode failed for \(path)")
            return
        }
        do {
            try data.write(to: URL(fileURLWithPath: path))
            print("Ollin: exported frame \(frame) → \(path) (\(cgImage.width)×\(cgImage.height))")
        } catch {
            warn("failed to write \(path): \(error)")
        }
    }

    private static func warn(_ message: String) {
        FileHandle.standardError.write(Data("guide-figures: \(message)\n".utf8))
    }

    private static func die(_ message: String) -> Never {
        warn(message)
        exit(2)
    }
}
