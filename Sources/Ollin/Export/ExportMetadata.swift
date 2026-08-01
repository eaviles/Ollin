import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

// Reproducibility metadata: every export carries the recipe to regenerate
// itself (the seeds, the current @Param values, the git commit of the working
// directory, and the frame/fps that produced it) as one compact JSON line.
// PNGs carry it in their text chunks (Software + Description), SVGs as a
// comment after the opening tag, PDFs in the document's Subject field, and
// videos as a QuickTime/MP4 description metadata item. GIF is the one format
// left out (it has no writable comment slot on this path).

/// The reproduction recipe captured from a sketch at export time. Assembled
/// after the sketch has run (so `setup()`-applied seeds and tuned parameter
/// values are in), serialized by `recipe`.
struct ExportMetadata {
    var randomSeed: Int?
    var noiseSeed: Int?
    var params: [(name: String, value: ParamStored)]
    var gitHash: String?
    var frame: Int?
    var fps: Double?
    /// The ink names of a print-separation export, in print order; `nil`
    /// everywhere else.
    var inks: [String]? = nil

    /// Capture the recipe from `sketch` as it stands: the last seeds applied,
    /// every `@Param`'s current value, and the working tree's git commit.
    @MainActor
    static func capture(from sketch: Sketch, frame: Int? = nil, fps: Double? = nil) -> ExportMetadata {
        ExportMetadata(randomSeed: sketch.recordedRandomSeed,
                       noiseSeed: sketch.recordedNoiseSeed,
                       params: sketch.parameters().map { ($0.name, $0.param.stored) },
                       gitHash: ExportMetadata.workingTreeHash,
                       frame: frame, fps: fps)
    }

    /// The recipe as one compact JSON line, e.g.
    /// `{"tool":"Ollin","seed":42,"params":{"radius":120},"git":"8167de3","frame":0,"fps":60}`.
    /// A single `seed` field appears when both generators share one (the
    /// `seed(_:)` path); separately-set seeds appear as `randomSeed`/`noiseSeed`.
    /// Field order is fixed so the same state always serializes identically.
    var recipe: String {
        var fields: [String] = ["\"tool\":\"Ollin\""]
        if let randomSeed, randomSeed == noiseSeed {
            fields.append("\"seed\":\(randomSeed)")
        } else {
            if let randomSeed { fields.append("\"randomSeed\":\(randomSeed)") }
            if let noiseSeed { fields.append("\"noiseSeed\":\(noiseSeed)") }
        }
        if !params.isEmpty {
            let entries = params.map { "\(jsonString($0.name)):\(jsonValue($0.value))" }
            fields.append("\"params\":{\(entries.joined(separator: ","))}")
        }
        if let inks, !inks.isEmpty {
            fields.append("\"inks\":[\(inks.map(jsonString).joined(separator: ","))]")
        }
        if let gitHash { fields.append("\"git\":\(jsonString(gitHash))") }
        if let frame { fields.append("\"frame\":\(frame)") }
        if let fps { fields.append("\"fps\":\(jsonNumber(fps))") }
        return "{\(fields.joined(separator: ","))}"
    }

    /// The recipe for a contact sheet, which reproduces from its seed list
    /// rather than a single sketch state: any tile re-renders at full
    /// resolution with `--export --seed N` at the recorded frame.
    static func sheetRecipe(seeds: [Int], frame: Int, fps: Double) -> String {
        var fields: [String] = ["\"tool\":\"Ollin\""]
        fields.append("\"seeds\":[\(seeds.map(String.init).joined(separator: ","))]")
        if let hash = workingTreeHash { fields.append("\"git\":\(jsonString(hash))") }
        fields.append("\"frame\":\(frame)")
        fields.append("\"fps\":\(jsonNumber(fps))")
        return "{\(fields.joined(separator: ","))}"
    }

    /// The recipe for a parameter sweep: the swept `@Param`'s name, its
    /// values, and the seed every tile was pinned to, so any tile re-renders
    /// at full resolution by setting that knob at that seed.
    static func sheetRecipe(sweep name: String, values: [Double], seed: Int,
                            frame: Int, fps: Double) -> String {
        var fields: [String] = ["\"tool\":\"Ollin\""]
        fields.append("\"sweep\":\(jsonString(name))")
        fields.append("\"values\":[\(values.map { jsonNumber($0) }.joined(separator: ","))]")
        fields.append("\"seed\":\(seed)")
        if let hash = workingTreeHash { fields.append("\"git\":\(jsonString(hash))") }
        fields.append("\"frame\":\(frame)")
        fields.append("\"fps\":\(jsonNumber(fps))")
        return "{\(fields.joined(separator: ","))}"
    }

    /// The short git commit of the process's working directory, with a
    /// `-dirty` suffix when the tree has uncommitted changes; `nil` outside a
    /// repository (or without git). Looked up once per process, so a sequence
    /// or video export reuses the answer for every frame.
    static let workingTreeHash: String? = {
        func git(_ arguments: [String]) -> String? {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            process.arguments = ["git"] + arguments
            let out = Pipe()
            process.standardOutput = out
            process.standardError = Pipe()   // a non-repo directory stays quiet
            guard (try? process.run()) != nil else { return nil }
            let data = out.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else { return nil }
            return String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        guard let hash = git(["rev-parse", "--short", "HEAD"]), !hash.isEmpty else { return nil }
        let dirty = git(["status", "--porcelain"]).map { !$0.isEmpty } ?? false
        return dirty ? hash + "-dirty" : hash
    }()
}

// MARK: - Compact JSON encoding

/// A parameter value as a compact JSON value: numbers bare, composites as
/// arrays in their natural component order.
private func jsonValue(_ stored: ParamStored) -> String {
    switch stored {
    case .number(let v): return jsonNumber(v)
    case .boolean(let v): return v ? "true" : "false"
    case .option(let name): return jsonString(name)
    case .text(let text): return jsonString(text)
    case let .color(r, g, b, a): return jsonArray([r, g, b, a])
    case let .vector(x, y): return jsonArray([x, y])
    case let .vector3(x, y, z): return jsonArray([x, y, z])
    case let .rect(x, y, w, h): return jsonArray([x, y, w, h])
    case let .insets(top, right, bottom, left): return jsonArray([top, right, bottom, left])
    case let .range(lower, upper): return jsonArray([lower, upper])
    }
}

private func jsonArray(_ values: [Double]) -> String {
    "[" + values.map(jsonNumber).joined(separator: ",") + "]"
}

/// A whole number prints bare (`120`, not `120.0`); anything else uses Swift's
/// shortest round-trip form, so the recipe reads back exactly.
private func jsonNumber(_ value: Double) -> String {
    if value.isFinite, value.rounded() == value, abs(value) < 1e15 {
        return String(Int64(value))
    }
    return "\(value)"
}

private func jsonString(_ text: String) -> String {
    var out = "\""
    for scalar in text.unicodeScalars {
        switch scalar {
        case "\"": out += "\\\""
        case "\\": out += "\\\\"
        case "\n": out += "\\n"
        case "\r": out += "\\r"
        case "\t": out += "\\t"
        case let c where c.value < 0x20: out += String(format: "\\u%04x", c.value)
        default: out.unicodeScalars.append(scalar)
        }
    }
    return out + "\""
}

// MARK: - PNG writing

extension OllinApp {
    /// Encode `image` as a PNG carrying the recipe in its text chunks (the
    /// `Software` and `Description` keywords) and write it to `path`. Returns
    /// `false` when encoding or writing fails.
    static func writePNG(_ image: CGImage, to path: String, recipe: String?) -> Bool {
        let url = URL(fileURLWithPath: path)
        guard let destination = CGImageDestinationCreateWithURL(
            url as CFURL, UTType.png.identifier as CFString, 1, nil) else { return false }
        var png: [CFString: Any] = [kCGImagePropertyPNGSoftware: "Ollin"]
        if let recipe { png[kCGImagePropertyPNGDescription] = recipe }
        let properties = [kCGImagePropertyPNGDictionary: png] as CFDictionary
        CGImageDestinationAddImage(destination, image, properties)
        return CGImageDestinationFinalize(destination)
    }
}
