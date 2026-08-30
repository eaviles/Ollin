@preconcurrency import ColorSync
import Foundation
import os

// Print color management, part two: the soft proof.
//
// A soft proof answers the question that decides whether a piece survives
// printing: what will this look like once it is on that paper? The answer is
// a round trip. Carry every color from the canvas into the printer's space,
// which is where the colors it cannot hold are folded onto the ones it can,
// then carry the result back out to the screen. What comes home changed is
// exactly what the press will change.
//
// Two things move on that trip and both are worth seeing. Saturated colors
// come back duller, because ink covers less of the color space than a
// backlit screen does. Black comes back lighter, because ink on paper is not
// as dark as a black pixel: the trip is run without black point compensation
// on purpose, so a proof shows the real ceiling on contrast rather than
// hiding it. Paper color is the third, and it is opt-in (`simulatesPaper`),
// because a proof of cream stock reads as a wrong-looking white until you
// know that is what you asked for.
//
// The gamut check is a separate question with a crisper answer: for each
// pixel, is this color reproducible at all? ColorSync answers that one
// directly, so an out-of-gamut mask is a transform rather than a guess about
// how far apart two colors look.

/// A printing condition to preview against: which press profile, from which
/// canvas, under which rendering intent.
///
/// ```swift
/// let proof = SoftProof(.genericCMYK)               // the everyday case
/// drawImage(artwork.softProofed(proof), 0, 0)       // as the press will read it
/// postProcess(.softProof(proof, warning: .magenta)) // live, with the losses flagged
/// ```
///
/// The default source is `.sRGB`, which is what an Ollin canvas is unless the
/// sketch declares a wide `colorOutput`; pass `from: .displayP3` for one that
/// does. See `Docs/Output/PrintColor.md`.
public struct SoftProof: Sendable, Hashable {
    /// The profile being proofed against: the press, the paper, the printer.
    public var destination: ICCProfile
    /// What the canvas itself is in.
    public var source: ICCProfile
    /// How colors the destination cannot hold are brought inside it.
    public var intent: RenderingIntent
    /// Show the paper's own color rather than remapping it to white. Off by
    /// default: it is the honest picture of cream or newsprint stock, and it
    /// looks wrong until you are expecting it.
    public var simulatesPaper: Bool

    public init(_ destination: ICCProfile, from source: ICCProfile = .sRGB,
                intent: RenderingIntent = .relative, simulatesPaper: Bool = false) {
        self.destination = destination
        self.source = source
        self.intent = intent
        self.simulatesPaper = simulatesPaper
    }

    /// The intent the trip back to the screen runs under. Absolute is what
    /// keeps the paper's own color in the picture; relative is what maps it
    /// back to white.
    var returnIntent: RenderingIntent { simulatesPaper ? .absolute : .relative }

    /// Whether both ends carry usable profile bytes.
    var isUsable: Bool { source.isUsable && destination.isUsable }
}

// MARK: - The transforms

/// Which question a cached transform answers.
enum ProofRole: Hashable, Sendable {
    /// Canvas to press and back: the soft proof itself.
    case proof
    /// Canvas to the press's own channels: the separation.
    case toDevice
    /// The press's channels back to the canvas: reconstructing a preview from
    /// plates.
    case fromDevice
    /// Canvas to a single flag per pixel: 1 where the color is out of gamut.
    case gamut
}

/// A built ColorSync transform, held so the (expensive) build happens once per
/// printing condition. The CF object is immutable after creation and the
/// conversion call takes its buffers as arguments, so it is safe to share.
final class ProofTransform: @unchecked Sendable {
    private let transform: ColorSyncTransform
    /// Components per input pixel.
    let inputChannels: Int
    /// Components per output pixel.
    let outputChannels: Int

    init?(_ proof: SoftProof, role: ProofRole) {
        guard proof.isUsable,
              let source = proof.source.colorSyncProfile,
              let destination = proof.destination.colorSyncProfile else { return nil }

        func step(_ profile: ColorSyncProfile, _ tag: Unmanaged<CFString>?,
                  _ intent: RenderingIntent) -> [CFString: Any] {
            [ICCProfile.constant(kColorSyncProfile): profile,
             ICCProfile.constant(kColorSyncTransformTag): ICCProfile.constant(tag),
             ICCProfile.constant(kColorSyncRenderingIntent): intent.colorSyncValue]
        }
        let toPCS = kColorSyncTransformDeviceToPCS
        let fromPCS = kColorSyncTransformPCSToDevice

        let sequence: [[CFString: Any]]
        switch role {
        case .proof:
            sequence = [step(source, toPCS, proof.intent),
                        step(destination, fromPCS, proof.intent),
                        step(destination, toPCS, proof.returnIntent),
                        step(source, fromPCS, proof.returnIntent)]
            inputChannels = proof.source.channelCount
            outputChannels = proof.source.channelCount
        case .toDevice:
            sequence = [step(source, toPCS, proof.intent),
                        step(destination, fromPCS, proof.intent)]
            inputChannels = proof.source.channelCount
            outputChannels = proof.destination.channelCount
        case .fromDevice:
            sequence = [step(destination, toPCS, proof.returnIntent),
                        step(source, fromPCS, proof.returnIntent)]
            inputChannels = proof.destination.channelCount
            outputChannels = proof.source.channelCount
        case .gamut:
            sequence = [step(source, toPCS, proof.intent),
                        step(destination, kColorSyncTransformGamutCheck, proof.intent)]
            inputChannels = proof.source.channelCount
            outputChannels = 1
        }

        // Black point compensation stays off: a proof is supposed to show the
        // press's real black, and turning it on rescales the whole trip.
        let options: [CFString: Any] = [
            ICCProfile.constant(kColorSyncBlackPointCompensation): false,
            ICCProfile.constant(kColorSyncConvertQuality):
                ICCProfile.constant(kColorSyncBestQuality)]
        guard inputChannels > 0, outputChannels > 0,
              let built = ColorSyncTransformCreate(sequence as CFArray,
                                                   options as CFDictionary)?.takeRetainedValue()
        else { return nil }
        transform = built
    }

    /// Run `pixels` colors through, `inputChannels` floats in and
    /// `outputChannels` floats out, every component in `0...1` and encoded the
    /// way its profile encodes (so an sRGB value here is the ordinary
    /// gamma-encoded one, not linear light).
    func convert(_ source: [Float], pixels: Int) -> [Float]? {
        guard pixels > 0, source.count >= pixels * inputChannels else { return nil }
        var output = [Float](repeating: 0, count: pixels * outputChannels)
        let inRow = pixels * inputChannels * MemoryLayout<Float>.size
        let outRow = pixels * outputChannels * MemoryLayout<Float>.size
        // The source is read, never written, so it goes in as it stands: a
        // full-canvas proof would otherwise copy tens of megabytes to say so.
        let ok = source.withUnsafeBytes { inBytes in
            output.withUnsafeMutableBytes { outBytes in
                ColorSyncTransformConvert(
                    transform, pixels, 1,
                    outBytes.baseAddress!, kColorSync32BitFloat,
                    kColorSyncAlphaNone.rawValue, outRow,
                    inBytes.baseAddress!, kColorSync32BitFloat,
                    kColorSyncAlphaNone.rawValue, inRow, nil)
            }
        }
        return ok ? output : nil
    }
}

/// The transform cache. Building one costs milliseconds and a sketch asks for
/// the same printing condition every frame, so they are kept, failures
/// included (a profile pair that cannot be transformed will not start working
/// on the next frame).
enum ProofTransforms {
    private struct Key: Hashable {
        let proof: SoftProof
        let role: ProofRole
    }

    private static let cache = OSAllocatedUnfairLock(initialState: [Key: ProofTransform?]())

    static func transform(_ proof: SoftProof, _ role: ProofRole) -> ProofTransform? {
        let key = Key(proof: proof, role: role)
        if let cached = cache.withLock({ $0[key] }) { return cached }
        let built = ProofTransform(proof, role: role)
        cache.withLock { $0[key] = built }
        return built
    }
}

// MARK: - Proofing an image

public extension Image {

    /// This image as the printing condition will reproduce it: duller where
    /// the ink cannot reach, lighter in the blacks, and tinted with the paper
    /// when the proof asks for it. Alpha is left alone.
    ///
    /// ```swift
    /// let press = SoftProof(.genericCMYK)
    /// drawImage(artwork.softProofed(press), 0, 0)
    /// ```
    ///
    /// `warning`, when given, paints every color the press cannot hold in that
    /// color instead, which is the flat answer to "what am I about to lose?".
    /// `amount` blends between the image as drawn and the proof, so
    /// `amount: 0` with a warning leaves the colors alone and shows only the
    /// flag. The image comes back unchanged if the profiles cannot be
    /// transformed.
    func softProofed(_ proof: SoftProof, warning: Color? = nil,
                     amount: Double = 1) -> Image {
        guard let bytes = premultipliedPixels(),
              let transform = ProofTransforms.transform(proof, .proof),
              transform.inputChannels == 3, transform.outputChannels == 3 else { return self }
        let count = width * height
        var input = [Float](repeating: 0, count: count * 3)
        var alphas = [Double](repeating: 1, count: count)
        for p in 0 ..< count {
            let i = p * 4
            let a = Double(bytes[i + 3]) / 255
            alphas[p] = a
            let scale = a > 0 ? 1 / (255 * a) : 0
            input[p * 3] = Float(min(1, Double(bytes[i]) * scale))
            input[p * 3 + 1] = Float(min(1, Double(bytes[i + 1]) * scale))
            input[p * 3 + 2] = Float(min(1, Double(bytes[i + 2]) * scale))
        }
        guard let proofed = transform.convert(input, pixels: count) else { return self }

        var flags: [Float]?
        if warning != nil, let gamut = ProofTransforms.transform(proof, .gamut) {
            flags = gamut.convert(input, pixels: count)
        }

        let blend = min(max(amount, 0), 1)
        var out = [UInt8](repeating: 0, count: count * 4)
        for p in 0 ..< count {
            let a = alphas[p]
            var r = mix(Double(input[p * 3]), Double(proofed[p * 3]), blend)
            var g = mix(Double(input[p * 3 + 1]), Double(proofed[p * 3 + 1]), blend)
            var b = mix(Double(input[p * 3 + 2]), Double(proofed[p * 3 + 2]), blend)
            if let warning, let flags, flags[p] > 0.5 {
                r = warning.red; g = warning.green; b = warning.blue
            }
            let i = p * 4
            out[i] = premultipliedByte(r, a)
            out[i + 1] = premultipliedByte(g, a)
            out[i + 2] = premultipliedByte(b, a)
            out[i + 3] = UInt8((min(max(a, 0), 1) * 255).rounded())
        }
        return Image(width: width, height: height, premultipliedRGBA: out) ?? self
    }

    /// Where this image asks for colors the printing condition cannot make:
    /// white for out of gamut, black for reproducible, which is a mask ready
    /// to composite, threshold, or blur. Transparent pixels read as in gamut.
    func gamutMask(_ proof: SoftProof) -> Image {
        let blank = Image(width: max(1, width), height: max(1, height), color: .black)
        guard let bytes = premultipliedPixels(),
              let transform = ProofTransforms.transform(proof, .gamut) else { return blank }
        let count = width * height
        var input = [Float](repeating: 0, count: count * 3)
        for p in 0 ..< count {
            let i = p * 4
            let a = Double(bytes[i + 3]) / 255
            let scale = a > 0 ? 1 / (255 * a) : 0
            input[p * 3] = Float(min(1, Double(bytes[i]) * scale))
            input[p * 3 + 1] = Float(min(1, Double(bytes[i + 1]) * scale))
            input[p * 3 + 2] = Float(min(1, Double(bytes[i + 2]) * scale))
        }
        guard let flags = transform.convert(input, pixels: count) else { return blank }
        var out = [UInt8](repeating: 255, count: count * 4)
        for p in 0 ..< count {
            let opaque = bytes[p * 4 + 3] > 0
            let value: UInt8 = (opaque && flags[p] > 0.5) ? 255 : 0
            let i = p * 4
            out[i] = value; out[i + 1] = value; out[i + 2] = value
        }
        return Image(width: width, height: height, premultipliedRGBA: out) ?? blank
    }

    /// How much of the picture asks for colors the press cannot make, `0...1`,
    /// counting only pixels that are not fully transparent. The number to
    /// print while tuning a palette: under a few percent is ordinary, a third
    /// of the canvas means the piece is being drawn in colors that will not
    /// survive.
    func outOfGamutFraction(_ proof: SoftProof) -> Double {
        guard let bytes = gamutMask(proof).premultipliedPixels(),
              let source = premultipliedPixels() else { return 0 }
        var flagged = 0, counted = 0
        for p in 0 ..< (width * height) {
            guard source[p * 4 + 3] > 0 else { continue }
            counted += 1
            if bytes[p * 4] > 127 { flagged += 1 }
        }
        return counted > 0 ? Double(flagged) / Double(counted) : 0
    }
}

/// One component back to a premultiplied byte.
private func premultipliedByte(_ value: Double, _ alpha: Double) -> UInt8 {
    UInt8((min(max(value, 0), 1) * min(max(alpha, 0), 1) * 255).rounded())
}

/// A straight blend between the drawn value and the proofed one. Both are
/// encoded values rather than linear light, which is what a viewer comparing
/// the two sides of a fade expects to see move evenly.
private func mix(_ a: Double, _ b: Double, _ t: Double) -> Double {
    a + (b - a) * t
}

// MARK: - The baked lookup, for proofing live

/// A printing condition baked into a lattice the GPU can read: for every
/// color in a `size` by `size` by `size` grid, what the proof makes of it and
/// whether it was reproducible at all.
///
/// The full transform costs about 150 ms on a 1080 by 1080 canvas, which is
/// far too slow per frame, while baking the lattice costs about 4 ms once.
/// So the live filter samples the lattice instead, which is how a proofing
/// view in any color-managed application works.
final class ProofLUT: Sendable {
    /// Nodes along each axis.
    let size: Int
    /// `size ^ 3` entries, red fastest then green then blue, matching the
    /// memory order of a 3D texture. `rgb` is the proofed color in linear
    /// light (what the effect chain works in), `a` is 1 where the source color
    /// was out of gamut.
    let samples: [SIMD4<Float>]

    init(size: Int, samples: [SIMD4<Float>]) {
        self.size = size
        self.samples = samples
    }

    /// The proofed color for one encoded input, by trilinear interpolation,
    /// which is what the shader does in hardware. Used by the tests, and by
    /// anything on the CPU that wants the same answer the GPU will give.
    func lookup(_ red: Double, _ green: Double, _ blue: Double) -> SIMD4<Float> {
        func axis(_ v: Double) -> (Int, Int, Float) {
            let scaled = min(max(v, 0), 1) * Double(size - 1)
            let low = Int(scaled.rounded(.down))
            let high = min(low + 1, size - 1)
            return (low, high, Float(scaled - Double(low)))
        }
        let (r0, r1, fr) = axis(red), (g0, g1, fg) = axis(green), (b0, b1, fb) = axis(blue)
        func at(_ r: Int, _ g: Int, _ b: Int) -> SIMD4<Float> {
            samples[r + size * (g + size * b)]
        }
        func mix(_ a: SIMD4<Float>, _ b: SIMD4<Float>, _ t: Float) -> SIMD4<Float> {
            a + (b - a) * t
        }
        let c00 = mix(at(r0, g0, b0), at(r1, g0, b0), fr)
        let c10 = mix(at(r0, g1, b0), at(r1, g1, b0), fr)
        let c01 = mix(at(r0, g0, b1), at(r1, g0, b1), fr)
        let c11 = mix(at(r0, g1, b1), at(r1, g1, b1), fr)
        return mix(mix(c00, c10, fg), mix(c01, c11, fg), fb)
    }
}

enum ProofLUTCache {
    private struct Key: Hashable {
        let proof: SoftProof
        let size: Int
    }

    private static let cache = OSAllocatedUnfairLock(initialState: [Key: ProofLUT?]())

    /// The default lattice: 33 nodes an axis is the size color-managed tools
    /// settled on, fine enough that the interpolation error sits well under a
    /// quantization step, and small enough (about 570 KB) to hand the GPU
    /// without thinking about it.
    static let defaultSize = 33

    /// The lattice for a printing condition, baked once and then shared. The
    /// same call every frame hands back the same object, which is what lets
    /// the renderer keep one texture for it rather than uploading per frame.
    static func lut(for proof: SoftProof, size: Int = defaultSize) -> ProofLUT? {
        let key = Key(proof: proof, size: size)
        if let cached = cache.withLock({ $0[key] }) { return cached }
        let built = bake(proof, size: size)
        cache.withLock { $0[key] = built }
        return built
    }

    private static func bake(_ proof: SoftProof, size: Int) -> ProofLUT? {
        guard size >= 2,
              let transform = ProofTransforms.transform(proof, .proof),
              transform.inputChannels == 3, transform.outputChannels == 3 else { return nil }
        let count = size * size * size
        var lattice = [Float](repeating: 0, count: count * 3)
        let step = 1 / Float(size - 1)
        var index = 0
        for b in 0 ..< size {
            for g in 0 ..< size {
                for r in 0 ..< size {
                    lattice[index] = Float(r) * step
                    lattice[index + 1] = Float(g) * step
                    lattice[index + 2] = Float(b) * step
                    index += 3
                }
            }
        }
        guard let proofed = transform.convert(lattice, pixels: count) else { return nil }
        let flags = ProofTransforms.transform(proof, .gamut)?.convert(lattice, pixels: count)

        var samples = [SIMD4<Float>](repeating: .zero, count: count)
        for p in 0 ..< count {
            // The lattice is encoded (what a profile speaks); the effect chain
            // is linear light, so the answer is decoded on the way out.
            let r = Color.srgbToLinear(Double(min(max(proofed[p * 3], 0), 1)))
            let g = Color.srgbToLinear(Double(min(max(proofed[p * 3 + 1], 0), 1)))
            let b = Color.srgbToLinear(Double(min(max(proofed[p * 3 + 2], 0), 1)))
            samples[p] = SIMD4<Float>(Float(r), Float(g), Float(b),
                                      (flags?[p] ?? 0) > 0.5 ? 1 : 0)
        }
        return ProofLUT(size: size, samples: samples)
    }
}
