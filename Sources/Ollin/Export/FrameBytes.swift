import CoreGraphics
import Foundation

// A wide-gamut frame comes off the renderer as half floats in linear Display
// P3, which is the right form for everything up to the file. The file is where
// it is quantized, so the quantization is done here rather than left to a color
// conversion, which rounds every pixel to the nearest code (a slow gradient in
// eight bits turns into a few flat bands) and may bend a frame that runs past
// white instead of clipping it.
//
// Two depths, chosen by what the file can hold. A PNG and the picture inside a
// HEIC keep sixteen bits, which the HEIC writer stores as ten, under the sRGB
// transfer curve (Display P3 shares it); at that depth the frame's own half
// floats are the limit and no dither is needed. A video's frames and a
// recording's are eight bits, and there the value is encoded the way the 8-bit
// present does it on the GPU: a triangular dither of up to one level each way,
// narrowed within a level of either end so exact black and exact white stay
// exact, then rounded. The dither is a function of the pixel's position, so an
// export is the same bytes every time it is made.

/// The stored bytes of a float frame in linear Display P3.
enum FrameBytes {

    /// The sRGB transfer curve for every half-float bit pattern, in eight-bit
    /// levels from 0 to 255, clamped to that range (a negative or a NaN reads
    /// 0, a value past white 255). Indexed by a half's bits, so encoding a
    /// component is a single read.
    private static let levels: [Float] = (0..<65_536).map { Float(encoded(halfBits: $0) * 255) }

    /// The same curve as sixteen-bit codes.
    private static let codes: [UInt16] = (0..<65_536).map { UInt16((encoded(halfBits: $0) * 65_535).rounded()) }

    /// One half's value through the sRGB transfer curve, clamped to `0...1`.
    private static func encoded(halfBits bits: Int) -> Double {
        let value = Float(Float16(bitPattern: UInt16(bits)))
        guard !value.isNaN else { return 0 }
        let c = Double(min(max(value, 0), 1))
        return c <= 0.003_130_8 ? c * 12.92 : 1.055 * pow(c, 1 / 2.4) - 0.055
    }

    // MARK: - Eight bits, dithered

    /// The triangular dither at a pixel, in `-1...1` levels: the difference of
    /// two uniform draws hashed from the position.
    @inline(__always)
    private static func dither(_ x: Int, _ y: Int) -> Float {
        @inline(__always) func mix(_ v: UInt32) -> UInt32 {
            var h = v &* 0x9E37_79B1
            h ^= h >> 16
            h = h &* 0x85EB_CA6B
            h ^= h >> 13
            h = h &* 0xC2B2_AE35
            return h ^ (h >> 16)
        }
        let key = (UInt32(truncatingIfNeeded: x) &* 0x8DA6_B343) ^ (UInt32(truncatingIfNeeded: y) &* 0xD816_3841)
        let a = mix(key), b = mix(key ^ 0x68E3_1DA4)
        return (Float(a >> 8) - Float(b >> 8)) * (1 / Float(1 << 24))
    }

    /// One encoded level, dithered and stored under `top`: the reach narrows
    /// within a level of 0 or `top` so both stay exact, as the shader's does.
    @inline(__always)
    private static func store(_ level: Float, _ noise: Float, top: Float) -> UInt8 {
        let reach = min(max(min(level, top - level) + 0.3, 0), 1)
        let out = reach >= 1 ? level + noise : level + noise * reach
        return UInt8(min(max(out, 0), top).rounded())
    }

    /// Fill `height` rows of B, G, R, A bytes (the layout of a 32-bit
    /// little-endian buffer with alpha first, a video encoder's) from half-float
    /// R, G, B, A rows in linear Display P3, the renderer's own read-back.
    /// `hasAlpha` says the fourth component is coverage under premultiplied
    /// color, and the bytes are premultiplied too: the straight color is
    /// encoded, scaled by the stored coverage, and dithered as the value the
    /// byte holds, so a channel never exceeds the alpha. Without it the alpha
    /// byte is 255.
    static func fillEightBit(_ destination: UnsafeMutableRawPointer, bytesPerRow: Int,
                             fromHalf source: UnsafeRawPointer, sourceBytesPerRow: Int,
                             width: Int, height: Int, hasAlpha: Bool) {
        for y in 0..<height {
            let row = source.advanced(by: y * sourceBytesPerRow).assumingMemoryBound(to: UInt16.self)
            let out = destination.advanced(by: y * bytesPerRow).assumingMemoryBound(to: UInt8.self)
            for x in 0..<width {
                let i = x * 4
                let noise = dither(x, y)
                let alpha = hasAlpha ? Float(Float16(bitPattern: row[i + 3])) : 1
                guard alpha < 1 else {
                    // The opaque case reads the curve by the half's own bits.
                    out[i] = store(levels[Int(row[i + 2])], noise, top: 255)
                    out[i + 1] = store(levels[Int(row[i + 1])], noise, top: 255)
                    out[i + 2] = store(levels[Int(row[i])], noise, top: 255)
                    out[i + 3] = 255
                    continue
                }
                let top = (max(alpha, 0) * 255).rounded()
                guard top > 0 else {
                    out[i] = 0; out[i + 1] = 0; out[i + 2] = 0; out[i + 3] = 0
                    continue
                }
                let unscale = 1 / alpha, scale = top / 255
                @inline(__always) func level(_ c: Int) -> Float {
                    levels[Int(Float16(Float(Float16(bitPattern: row[i + c])) * unscale).bitPattern)] * scale
                }
                out[i] = store(level(2), noise, top: top)
                out[i + 1] = store(level(1), noise, top: top)
                out[i + 2] = store(level(0), noise, top: top)
                out[i + 3] = UInt8(top)
            }
        }
    }

    /// Whether `image` is laid out as the renderer's float read-back: half-float
    /// R, G, B, A in extended linear Display P3, which the fills here read as
    /// it stands.
    static func isRendererFloat(_ image: CGImage) -> Bool {
        image.bitsPerComponent == 16 && image.bitsPerPixel == 64
            && image.bitmapInfo.contains(.floatComponents)
            && image.colorSpace?.name == CGColorSpace.extendedLinearDisplayP3
            && [.noneSkipLast, .premultipliedLast].contains(image.alphaInfo)
    }

    /// Fill a B, G, R, A buffer from a float frame in the renderer's layout,
    /// returning false for an image in any other form so the caller can take
    /// its own conversion instead.
    static func fillEightBit(_ destination: UnsafeMutableRawPointer, bytesPerRow: Int,
                             from image: CGImage) -> Bool {
        guard isRendererFloat(image), let data = image.dataProvider?.data as Data? else { return false }
        data.withUnsafeBytes { raw in
            guard let base = raw.baseAddress else { return }
            fillEightBit(destination, bytesPerRow: bytesPerRow, fromHalf: base,
                         sourceBytesPerRow: image.bytesPerRow, width: image.width, height: image.height,
                         hasAlpha: image.alphaInfo == .premultipliedLast)
        }
        return true
    }

    // MARK: - Sixteen bits

    /// A sixteen-bit Display P3 image of a float frame in the renderer's
    /// layout, clipped at white; nil for an image in any other form. A
    /// see-through frame's coverage is kept as straight alpha, the color
    /// divided out of it first, which is the form a PNG stores.
    static func sixteenBit(_ image: CGImage) -> CGImage? {
        guard isRendererFloat(image), let data = image.dataProvider?.data as Data? else { return nil }
        let width = image.width, height = image.height
        let hasAlpha = image.alphaInfo == .premultipliedLast
        var words = [UInt16](repeating: 0, count: width * height * 4)
        data.withUnsafeBytes { raw in
            guard let base = raw.baseAddress else { return }
            for y in 0..<height {
                let row = base.advanced(by: y * image.bytesPerRow).assumingMemoryBound(to: UInt16.self)
                for x in 0..<width {
                    let i = x * 4, o = (y * width + x) * 4
                    let alpha = hasAlpha ? Float(Float16(bitPattern: row[i + 3])) : 1
                    if alpha >= 1 {
                        words[o] = codes[Int(row[i])]
                        words[o + 1] = codes[Int(row[i + 1])]
                        words[o + 2] = codes[Int(row[i + 2])]
                        words[o + 3] = 65_535
                    } else if alpha > 0 {
                        for c in 0..<3 {
                            let straight = Float(Float16(bitPattern: row[i + c])) / alpha
                            words[o + c] = codes[Int(Float16(straight).bitPattern)]
                        }
                        words[o + 3] = UInt16((alpha * 65_535).rounded())
                    }
                }
            }
        }
        return sixteenBitImage(words, width: width, height: height, hasAlpha: hasAlpha)
    }

    /// A sixteen-bit Display P3 image of opaque 32-bit float R, G, B, A in
    /// linear Display P3, clipped at white: the picture inside a HEIC, whose
    /// components arrive that way.
    static func sixteenBit(fromFloat pixels: [Float], width: Int, height: Int) -> CGImage? {
        guard pixels.count >= width * height * 4 else { return nil }
        var words = [UInt16](repeating: 65_535, count: width * height * 4)
        for p in 0..<(width * height) {
            for c in 0..<3 {
                words[p * 4 + c] = codes[Int(Float16(pixels[p * 4 + c]).bitPattern)]
            }
        }
        return sixteenBitImage(words, width: width, height: height, hasAlpha: false)
    }

    private static func sixteenBitImage(_ words: [UInt16], width: Int, height: Int, hasAlpha: Bool) -> CGImage? {
        let bytes = words.withUnsafeBytes { Data($0) }
        guard let provider = CGDataProvider(data: bytes as CFData),
              let space = CGColorSpace(name: CGColorSpace.displayP3) else { return nil }
        let alpha: CGImageAlphaInfo = hasAlpha ? .last : .noneSkipLast
        return CGImage(width: width, height: height, bitsPerComponent: 16, bitsPerPixel: 64,
                       bytesPerRow: width * 8, space: space,
                       bitmapInfo: CGBitmapInfo(rawValue: alpha.rawValue | CGBitmapInfo.byteOrder16Little.rawValue),
                       provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)
    }
}
