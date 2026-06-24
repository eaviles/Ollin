#!/usr/bin/env swift
// Trains the style-transfer model the StyleMirror example runs — from any
// image you pick. The Create ML *app* no longer offers a Style Transfer
// template (gone as of macOS 26), but the CreateML *framework* still trains
// them; this script is that path, kept as friendly as the template was:
//
//     swift Scripts/train-style-model.swift path/to/style.jpg
//
// Writes Models/StyleTransfer.mlmodel (gitignored — the model is your own
// work, trained on your Mac; nothing is downloaded). The StyleMirror sketch
// watches for the file, so training while it runs starts the painting live.
//
// Options:
//     --content <folder>    your own photos as training content (default:
//                           frames pulled from the repo's sample clip)
//     --out <path>          output path (default Models/StyleTransfer.mlmodel)
//     --iterations <n>      training iterations (default 200 — a couple of
//                           minutes; raise it for a finer style)
//     --strength <1-10>     style strength (default 5)
//     --quality             train the heavier "image" network instead of the
//                           lighter real-time one StyleMirror wants

import AVFoundation
import CoreGraphics
import CreateML
import Foundation
import ImageIO
import UniformTypeIdentifiers

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data("error: \(message)\n".utf8))
    exit(1)
}

// MARK: Arguments

var arguments = Array(CommandLine.arguments.dropFirst())
func option(_ flag: String) -> String? {
    guard let i = arguments.firstIndex(of: flag) else { return nil }
    guard i + 1 < arguments.count else { fail("\(flag) needs a value") }
    let value = arguments[i + 1]
    arguments.removeSubrange(i...(i + 1))
    return value
}
func has(_ flag: String) -> Bool {
    guard let i = arguments.firstIndex(of: flag) else { return false }
    arguments.remove(at: i)
    return true
}

let contentOption = option("--content")
let outPath = option("--out") ?? "Models/StyleTransfer.mlmodel"
let iterations = option("--iterations").flatMap(Int.init) ?? 200
let strength = option("--strength").flatMap(Int.init) ?? 5
let wantsQuality = has("--quality")

guard arguments.count == 1 else {
    print("""
    usage: swift Scripts/train-style-model.swift <style-image> \
    [--content <folder>] [--out <path>] [--iterations <n>] [--strength <1-10>] [--quality]
    """)
    exit(arguments.isEmpty ? 0 : 1)
}
let styleURL = URL(fileURLWithPath: arguments[0])
guard FileManager.default.fileExists(atPath: styleURL.path) else {
    fail("no style image at \(styleURL.path)")
}

// MARK: Content images

// Style transfer needs a folder of ordinary photos as *content* — they teach
// the model what pictures look like so it preserves structure. Any varied
// photos of yours beat the default; the fallback pulls frames from the repo's
// bundled sample clip so the script works with zero setup.
let contentDir: URL
if let contentOption {
    contentDir = URL(fileURLWithPath: contentOption, isDirectory: true)
    guard FileManager.default.fileExists(atPath: contentDir.path) else {
        fail("no content folder at \(contentDir.path)")
    }
} else {
    let clip = URL(fileURLWithPath: "Examples/Video/VideoPlayback/voladores.mp4")
    guard FileManager.default.fileExists(atPath: clip.path) else {
        fail("run from the repo root (looked for \(clip.path)), or pass --content <folder>")
    }
    let temp = FileManager.default.temporaryDirectory
        .appendingPathComponent("ollin-style-content", isDirectory: true)
    try? FileManager.default.removeItem(at: temp)
    try FileManager.default.createDirectory(at: temp, withIntermediateDirectories: true)
    print("pulling content frames from the sample clip…")
    let generator = AVAssetImageGenerator(asset: AVURLAsset(url: clip))
    generator.appliesPreferredTrackTransform = true
    let semaphore = DispatchSemaphore(value: 0)
    Task {
        do {
            for (i, seconds) in stride(from: 1.0, through: 25.0, by: 3.0).enumerated() {
                let (frame, _) = try await generator.image(
                    at: CMTime(seconds: seconds, preferredTimescale: 600))
                let url = temp.appendingPathComponent("frame\(i).png")
                guard let sink = CGImageDestinationCreateWithURL(
                    url as CFURL, UTType.png.identifier as CFString, 1, nil) else {
                    fail("couldn't write \(url.path)")
                }
                CGImageDestinationAddImage(sink, frame, nil)
                CGImageDestinationFinalize(sink)
            }
        } catch {
            fail("couldn't decode content frames: \(error.localizedDescription)")
        }
        semaphore.signal()
    }
    semaphore.wait()
    contentDir = temp
}

let contentImages = (try? FileManager.default.contentsOfDirectory(
    at: contentDir, includingPropertiesForKeys: nil))?
    .filter { ["png", "jpg", "jpeg", "heic", "tiff"].contains($0.pathExtension.lowercased()) }
    ?? []
guard let validationImage = contentImages.first else {
    fail("no images in \(contentDir.path)")
}

// MARK: Train

print("training (\(iterations) iterations, strength \(strength), " +
      "\(wantsQuality ? "image-quality" : "real-time") network)…")
let start = Date()
let parameters = MLStyleTransfer.ModelParameters(
    algorithm: wantsQuality ? .cnn : .cnnLite,
    validation: .content(validationImage),
    maxIterations: iterations,
    styleStrength: strength)
let model: MLStyleTransfer
do {
    model = try MLStyleTransfer(
        trainingData: .images(styleImage: styleURL, contentDirectory: contentDir),
        parameters: parameters)
} catch {
    fail("training failed: \(error.localizedDescription)")
}

let outURL = URL(fileURLWithPath: outPath)
try? FileManager.default.createDirectory(
    at: outURL.deletingLastPathComponent(), withIntermediateDirectories: true)
do {
    try model.write(to: outURL,
                    metadata: MLModelMetadata(
                        author: "Trained locally with Ollin's train-style-model script",
                        shortDescription: "Style transfer learned from \(styleURL.lastPathComponent)"))
} catch {
    fail("couldn't write \(outURL.path): \(error.localizedDescription)")
}
print("✓ trained in \(Int(Date().timeIntervalSince(start)))s → \(outURL.path)")
print("  swift run Example-Vision-StyleMirror   (or keep it running — it picks the file up live)")
