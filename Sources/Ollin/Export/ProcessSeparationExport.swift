import CoreGraphics
import Foundation

// The process-color plate export: render one frame headlessly, separate it
// through a printer profile (see `Image.separated(into:)`), and write one
// grayscale plate per channel plus the proof of the finished print.
//
// The files are shaped exactly like the spot-ink masters next door, down to
// the registration band and the marks in the corners, because they go to the
// same place: a shop, on paper, to be stacked in register. What is added is
// the total-ink line, which is the one number a press operator will ask about
// before anything is mounted.

extension OllinApp {

    /// Render `frame` of `sketch` headlessly and separate it into process
    /// plates. `profile` falls back to the sketch's declared `printProfile`;
    /// returns `nil` with no profile to separate through, no Metal device, or
    /// a failed render.
    @MainActor
    public static func plates(of sketch: Sketch, profile: ICCProfile? = nil,
                              intent: RenderingIntent = .relative,
                              frame: Int = 0, fps: Double = 60,
                              quality: RenderQuality = .detail) -> ProcessSeparation? {
        guard let press = profile ?? sketch.printProfile else { return nil }
        guard let cgImage = image(of: sketch, frame: frame, fps: fps, quality: quality) else {
            return nil
        }
        let proof = SoftProof(press, from: ICCProfile.canvas(sketch.colorOutput), intent: intent)
        return Image(cgImage: cgImage).separated(into: proof)
    }

    /// Render one frame, separate it through a printer profile, and write the
    /// print files: one grayscale plate per channel (`art-1-cyan.png`,
    /// `art-2-magenta.png`, ...) plus the proof of the finished print
    /// (`art-preview.png`), each carrying the reproduction recipe.
    ///
    /// `screen` transforms the separation before writing (pass
    /// `{ $0.halftoned(pitch: 8) }` for 1-bit films at the conventional
    /// rosette angles); `registrationMarks` adds the white margin band with
    /// corner targets and the plate label, identical on every file.
    ///
    /// ```swift
    /// OllinApp.exportPlates(sketch, to: "poster.png", profile: press)
    /// ```
    ///
    /// From the command line: `--export-plates poster.png` (see
    /// `handleCommandLine`).
    @MainActor
    public static func exportPlates(_ sketch: Sketch, to path: String,
                                    profile: ICCProfile? = nil,
                                    intent: RenderingIntent = .relative,
                                    simulatePaper: Bool = false,
                                    frame: Int = 0, fps: Double = 60,
                                    registrationMarks: Bool = true,
                                    quality: RenderQuality = .detail,
                                    screen: (ProcessSeparation) -> ProcessSeparation = { $0 }) {
        guard let press = profile ?? sketch.printProfile else {
            FileHandle.standardError.write(Data("""
                --export-plates splits a sketch into process-color printing plates.
                Declare the printing condition in the sketch:
                    override var printProfile: ICCProfile? { .genericCMYK }
                or name a profile on the command line:
                    --export-plates out.png --profile "US Web Coated (SWOP) v2"
                    --export-plates out.png --profile ~/Profiles/press.icc

                """.utf8))
            return
        }
        print("Ollin: rendering plates for \(press.name) (\(press.channelCount) channels, \(intent.rawValue))")
        guard let cgImage = image(of: sketch, frame: frame, fps: fps, quality: quality) else {
            fatalError("Ollin: failed to render the frame for separation (no Metal device?)")
        }
        var proof = SoftProof(press, from: ICCProfile.canvas(sketch.colorOutput), intent: intent)
        proof.simulatePaper = simulatePaper
        let separation = screen(Image(cgImage: cgImage).separated(into: proof))
        guard !separation.plates.isEmpty else {
            fatalError("Ollin: the separation produced no plates (is \(press.name) readable?)")
        }

        var metadata = ExportMetadata.capture(from: sketch, frame: frame, fps: fps)
        metadata.inks = separation.plates.map(\.name)
        metadata.printingCondition = "\(press.name) / \(intent.rawValue)"
        let recipe = metadata.recipe

        let stem = (path as NSString).deletingPathExtension
        let band = registrationMarks ? max(24, min(separation.width, separation.height) / 24) : 0

        for (index, plate) in separation.plates.enumerated() {
            let file = platePath(stem: stem, index: index, name: plate.name)
            let label = "\(index + 1)/\(separation.plates.count)  \(plate.name)  " +
                        "\(Int((plate.averageInk * 100).rounded()))% ink"
            guard let sheet = separationSheet(plate.master.cgImage, band: band, label: label),
                  writePNG(sheet, to: file, recipe: recipe) else {
                fatalError("Ollin: failed to write \(file)")
            }
            print("  \(label) → \(file)")
        }

        let inkLabel = "\(Int((separation.peakTotalInk * 100).rounded()))% peak ink"
        let previewLabel = "proof  \(press.name)  \(inkLabel)"
        guard let sheet = separationSheet(separation.preview().cgImage, band: band,
                                          label: previewLabel),
              writePNG(sheet, to: "\(stem)-preview.png", recipe: recipe) else {
            fatalError("Ollin: failed to write \(stem)-preview.png")
        }
        print("Ollin: exported \(separation.plates.count) plates + proof → \(stem)-*.png " +
              "(\(separation.width)×\(separation.height)" +
              (band > 0 ? " + \(band)px marks band, " : ", ") +
              "\(inkLabel), \(Int((separation.averageTotalInk * 100).rounded()))% average)")
    }

    /// The file a plate is written to: the base path with the plate number and
    /// the channel's name slugged in (`art-1-cyan.png`).
    static func platePath(stem: String, index: Int, name: String) -> String {
        let slug = name.lowercased()
            .map { $0.isLetter || $0.isNumber ? String($0) : "-" }
            .joined()
        return "\(stem)-\(index + 1)-\(slug).png"
    }
}
