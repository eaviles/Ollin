import Foundation

// Print color management, part three: process separation.
//
// The spot-ink separation next door works backwards from a physical model of
// translucent inks over paper, because that is the only model there is for a
// shop's own ink line. Process color is the other tradition: four standard
// inks, one profile that has actually been measured on that press and paper,
// and a color engine that already knows how to invert it. So this file does
// not model anything. It asks the profile for the channel values, and hands
// each channel back as a plate.
//
// The convention is shared with the spot path so the two exports feel the
// same: a plate is a grayscale master where black is full ink and white is
// bare paper, and the screening (dither or rotated round dots) runs over the
// same coverage planes. What is different is the ordering: the plates come
// back in the profile's own channel order (cyan, magenta, yellow, black),
// and the screen angles follow the conventional rosette for those four rather
// than being ranked by ink darkness.
//
// Total area coverage is the number a shop asks for and a screen never shows.
// It is the sum of all four coverages at one spot: 400% means every ink solid
// on the same square millimeter, which sheet-fed presses hold at around 300%
// and newsprint at closer to 240% before the paper gives up. It is reported
// here rather than enforced, because the fix is in the artwork, not the file.

/// An image split into process-color printing plates through an ICC profile,
/// with the proof of the finished print alongside.
///
/// Build one with `Image.separated(into:)` (passing a profile or a whole
/// `SoftProof`), screen it if the press wants 1-bit films, and export with
/// `OllinApp.exportPlates` or the `--export-plates` flag:
///
/// ```swift
/// let plates = artwork.separated(into: .genericCMYK)
/// drawImage(plates.preview())            // the print, as the profile predicts it
/// drawImage(plates.plates[3].master)     // the black plate on its own
/// print(plates.peakTotalInk)             // 2.4 means 240% ink at the heaviest spot
/// ```
public struct ProcessSeparation {

    /// One channel's printing plate.
    public struct Plate {
        /// The channel this plate prints: "Cyan", "Magenta", "Yellow",
        /// "Black", or whatever the profile's own ink set is called.
        public let name: String
        /// The grayscale plate: black is full ink, white is bare paper. The
        /// byte value is the ink fraction directly (`0` is 100% ink), not a
        /// gamma-encoded tone.
        public let master: Image
        /// The mean ink coverage over the whole plate, `0...1`.
        public let averageInk: Double
    }

    /// The plates, in the profile's channel order (which is the order a
    /// four-color press lays them down).
    public let plates: [Plate]
    /// The printing condition these plates were made for.
    public let proof: SoftProof
    public let width: Int
    public let height: Int
    /// The heaviest total ink anywhere in the image, as a fraction where 1 is
    /// one ink solid: 2.4 is 240%. Compare it against what the press will
    /// take (around 3.0 for coated sheet-fed stock, 2.4 for newsprint).
    public let peakTotalInk: Double
    /// The mean total ink over the whole image, the number that tells you how
    /// thirsty the piece is overall.
    public let averageTotalInk: Double

    /// The finished print as the profile predicts it: the plates carried back
    /// through the profile into screen color. Run on screened plates it shows
    /// the actual dots, rosette and all.
    ///
    /// This reconstructs from the plates rather than proofing the original, so
    /// it is the honest preview of the files that would go to the press.
    public func preview() -> Image {
        let blank = Image(width: max(1, width), height: max(1, height), color: .white)
        guard !plates.isEmpty,
              let transform = ProofTransforms.transform(proof, .fromDevice),
              transform.inputChannels == plates.count, transform.outputChannels == 3
        else { return blank }
        let planes = plates.compactMap { $0.master.premultipliedPixels() }
        guard planes.count == plates.count else { return blank }

        let count = width * height
        var device = [Float](repeating: 0, count: count * plates.count)
        for p in 0 ..< count {
            for c in planes.indices {
                device[p * plates.count + c] = 1 - Float(planes[c][p * 4]) / 255
            }
        }
        guard let rgb = transform.convert(device, pixels: count) else { return blank }

        var out = [UInt8](repeating: 255, count: count * 4)
        for p in 0 ..< count {
            let i = p * 4
            out[i] = UInt8((min(max(Double(rgb[p * 3]), 0), 1) * 255).rounded())
            out[i + 1] = UInt8((min(max(Double(rgb[p * 3 + 1]), 0), 1) * 255).rounded())
            out[i + 2] = UInt8((min(max(Double(rgb[p * 3 + 2]), 0), 1) * 255).rounded())
        }
        return Image(width: width, height: height, premultipliedRGBA: out) ?? blank
    }

    /// The plates reduced to pure black and white by dithering, the same
    /// area-conserving pass the spot-ink masters use, including the 2%
    /// minimum-dot cutoff a press cannot print below.
    public func dithered(_ method: Dither = .blueNoise, serpentine: Bool = true) -> ProcessSeparation {
        screened { plane, _ in
            PrintSeparation.ditherPlane(&plane, width: width, height: height,
                                        method: method, serpentine: serpentine)
        }
    }

    /// The plates reduced to pure black and white by rotated round-dot
    /// screens, one angle per plate. The default angles are the conventional
    /// four-color rosette (cyan 15, magenta 75, yellow 0, black 45 degrees),
    /// which is what keeps the overlap from turning into moire.
    public func halftoned(pitch: Double = 8, angles: [Double]? = nil) -> ProcessSeparation {
        let cell = max(2, pitch)
        let assigned = angles ?? Self.screenAngles(count: plates.count)
        return screened { plane, index in
            let angle = index < assigned.count ? assigned[index] : Double(index) * .pi / 7
            PrintSeparation.halftonePlane(&plane, width: width, height: height,
                                          pitch: cell, angle: angle)
        }
    }

    /// The conventional process screen angles, in the profile's channel order.
    /// Yellow takes 0 degrees because it is the ink the eye least resents
    /// seeing as a pattern, and black takes 45 because it is the one that
    /// shows most.
    static func screenAngles(count: Int) -> [Double] {
        let cmyk: [Double] = [15, 75, 0, 45]
        if count == 4 { return cmyk.map { $0 * .pi / 180 } }
        if count == 1 { return [45 * .pi / 180] }
        return (0 ..< count).map { Double($0) * .pi / Double(max(count, 1)) }
    }

    /// Rebuild every plate by running `transform` over its coverage plane
    /// (`0...1`, ink fraction per pixel, row-major, with the plate's index).
    private func screened(_ transform: (inout [Double], Int) -> Void) -> ProcessSeparation {
        let count = width * height
        var rebuilt: [Plate] = []
        var coverages = [[Double]](repeating: [], count: plates.count)
        for (index, plate) in plates.enumerated() {
            guard let bytes = plate.master.premultipliedPixels() else {
                rebuilt.append(plate)
                coverages[index] = []
                continue
            }
            var plane = [Double](repeating: 0, count: count)
            for p in 0 ..< count { plane[p] = 1 - Double(bytes[p * 4]) / 255 }
            transform(&plane, index)
            coverages[index] = plane
            var out = [UInt8](repeating: 255, count: count * 4)
            for p in 0 ..< count {
                let byte = UInt8(((1 - min(max(plane[p], 0), 1)) * 255).rounded())
                out[p * 4] = byte
                out[p * 4 + 1] = byte
                out[p * 4 + 2] = byte
            }
            guard let master = Image(width: width, height: height, premultipliedRGBA: out) else {
                rebuilt.append(plate)
                continue
            }
            let mean = plane.reduce(0, +) / Double(max(count, 1))
            rebuilt.append(Plate(name: plate.name, master: master, averageInk: mean))
        }
        let (peak, average) = Self.totalInk(coverages, pixels: count)
        return ProcessSeparation(plates: rebuilt, proof: proof, width: width, height: height,
                                 peakTotalInk: peak, averageTotalInk: average)
    }

    /// The heaviest and mean sum of coverages over every pixel.
    static func totalInk(_ coverages: [[Double]], pixels: Int) -> (peak: Double, average: Double) {
        guard pixels > 0, !coverages.isEmpty else { return (0, 0) }
        var peak = 0.0
        var sum = 0.0
        for p in 0 ..< pixels {
            var total = 0.0
            for plane in coverages where p < plane.count { total += plane[p] }
            peak = max(peak, total)
            sum += total
        }
        return (peak, sum / Double(pixels))
    }
}

// MARK: - Separating an image into plates

public extension Image {

    /// Split this image into process-color printing plates through a printing
    /// condition: one grayscale plate per channel the profile describes, plus
    /// the total-ink figures a shop will ask for.
    ///
    /// Unlike the spot-ink separation, nothing is searched or modeled here.
    /// The profile already describes what that press does with color, so the
    /// channel values come straight from the color engine, which is also what
    /// makes the answer match what any other color-managed application would
    /// produce from the same profile.
    ///
    /// Translucent pixels are composited over white first, since paper has no
    /// alpha. A GPU-backed image has no CPU pixels and separates into nothing
    /// (`snapshot()` first), as does a source or destination profile the
    /// system cannot read. Deterministic, so a separation is safe to snapshot
    /// and export.
    func separated(into proof: SoftProof) -> ProcessSeparation {
        let channels = proof.destination.channelCount
        guard hasCPUPixels, channels > 0, let bytes = premultipliedPixels(),
              let transform = ProofTransforms.transform(proof, .toDevice),
              transform.inputChannels == 3, transform.outputChannels == channels
        else {
            return ProcessSeparation(plates: [], proof: proof, width: width, height: height,
                                     peakTotalInk: 0, averageTotalInk: 0)
        }

        let count = width * height
        var input = [Float](repeating: 0, count: count * 3)
        for p in 0 ..< count {
            let i = p * 4
            // Paper has no alpha, so anything translucent prints over white.
            let a = Double(bytes[i + 3]) / 255
            input[p * 3] = Float(min(1, Double(bytes[i]) / 255 + (1 - a)))
            input[p * 3 + 1] = Float(min(1, Double(bytes[i + 1]) / 255 + (1 - a)))
            input[p * 3 + 2] = Float(min(1, Double(bytes[i + 2]) / 255 + (1 - a)))
        }
        guard let device = transform.convert(input, pixels: count) else {
            return ProcessSeparation(plates: [], proof: proof, width: width, height: height,
                                     peakTotalInk: 0, averageTotalInk: 0)
        }

        let names = proof.destination.channelNames
        var plates: [ProcessSeparation.Plate] = []
        var coverages = [[Double]](repeating: [Double](repeating: 0, count: count),
                                   count: channels)
        for c in 0 ..< channels {
            var out = [UInt8](repeating: 255, count: count * 4)
            var sum = 0.0
            for p in 0 ..< count {
                let coverage = min(max(Double(device[p * channels + c]), 0), 1)
                coverages[c][p] = coverage
                sum += coverage
                let byte = UInt8(((1 - coverage) * 255).rounded())
                out[p * 4] = byte
                out[p * 4 + 1] = byte
                out[p * 4 + 2] = byte
            }
            guard let master = Image(width: width, height: height, premultipliedRGBA: out) else {
                continue
            }
            plates.append(ProcessSeparation.Plate(
                name: c < names.count ? names[c] : "Channel \(c + 1)",
                master: master, averageInk: sum / Double(max(count, 1))))
        }

        let (peak, average) = ProcessSeparation.totalInk(coverages, pixels: count)
        return ProcessSeparation(plates: plates, proof: proof, width: width, height: height,
                                 peakTotalInk: peak, averageTotalInk: average)
    }

    /// Split this image into plates for a printer profile, from an sRGB
    /// canvas, under the given intent. The short form of
    /// `separated(into: SoftProof(...))`.
    func separated(into profile: ICCProfile,
                   intent: RenderingIntent = .relative) -> ProcessSeparation {
        separated(into: SoftProof(profile, intent: intent))
    }
}
