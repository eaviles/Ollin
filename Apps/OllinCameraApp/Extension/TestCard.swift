//
//  Ollin Camera — the "no signal" test card.
//
//  What the camera shows when no sketch is feeding the sink stream: a classic
//  broadcast-style circle test card (in the genre of the Philips PM5544 and its
//  kin — an original layout, not a reproduction) with a live clock and a
//  ping-ponging dot so it's obviously a moving picture, plus a NO SIGNAL
//  station band so the state reads at a glance.
//
//  The static card is computed once per pixel at init; each frame copies it
//  into the destination buffer and draws the two animated elements on top.
//

import Foundation
import CoreVideo

struct TestCard {

    let width: Int
    let height: Int

    // Geometry of the central circle and its inner bands.
    private let centerX: Int
    private let centerY: Int
    private let outerRadius: Double
    private let innerRadius: Double
    /// Horizontal span of the band content: the circle's widest chord.
    private let chordLeft: Int
    private let chordWidth: Int

    /// The precomputed static card, `width * height` BGRA pixels.
    private let card: [UInt32]

    // 32BGRA in memory is B,G,R,A; little-endian that packs as A<<24|R<<16|G<<8|B.
    private static func rgb(_ r: UInt32, _ g: UInt32, _ b: UInt32) -> UInt32 {
        (0xFF << 24) | (r << 16) | (g << 8) | b
    }

    private static let white = rgb(255, 255, 255)
    private static let black = rgb(0, 0, 0)

    init(width: Int, height: Int) {
        self.width = width
        self.height = height
        centerX = width / 2
        centerY = height / 2
        outerRadius = Double(min(width, height)) / 2 - 30
        innerRadius = outerRadius - 4
        chordLeft = centerX - Int(innerRadius)
        chordWidth = Int(innerRadius) * 2

        var pixels = [UInt32](repeating: 0, count: width * height)

        // Band edges, proportional to the circle's vertical extent.
        let circleTop = centerY - Int(outerRadius)
        let circleH = Int(outerRadius) * 2
        let bandY: (Double) -> Int = { circleTop + Int($0 * Double(circleH)) }
        let splitEnd = bandY(0.12)
        let stationEnd = bandY(0.21)
        let barsEnd = bandY(0.38)
        let grayEnd = bandY(0.50)
        let gratingsEnd = bandY(0.62)
        let messageEnd = bandY(0.74)
        let clockEnd = bandY(0.86)

        // 75% color bars, the broadcast order.
        let bars: [UInt32] = [
            Self.rgb(191, 191, 191), Self.rgb(191, 191, 0), Self.rgb(0, 191, 191),
            Self.rgb(0, 191, 0), Self.rgb(191, 0, 191), Self.rgb(191, 0, 0),
            Self.rgb(0, 0, 191),
        ]
        var graySteps = [UInt32]()
        for step in 0..<6 {
            let level = UInt32(step * 51)
            graySteps.append(Self.rgb(level, level, level))
        }
        // Vertical gratings of rising frequency: half-period in pixels per zone.
        let gratingHalfPeriods = [16, 10, 6, 4, 2]

        let surround = Self.rgb(128, 128, 128)
        let gridLine = Self.white
        let bottomField = Self.rgb(64, 64, 64)

        for y in 0..<height {
            for x in 0..<width {
                let dx = Double(x - centerX) + 0.5
                let dy = Double(y - centerY) + 0.5
                let dist = (dx * dx + dy * dy).squareRoot()

                var color: UInt32
                if dist <= innerRadius {
                    // Inside the circle: horizontal bands, clipped by the circle.
                    let u = x - chordLeft
                    switch y {
                    case ..<splitEnd:
                        color = x < centerX ? Self.rgb(191, 191, 0) : Self.rgb(0, 191, 191)
                    case ..<stationEnd:
                        color = Self.black
                    case ..<barsEnd:
                        let index = min(bars.count - 1, max(0, u * bars.count / chordWidth))
                        color = bars[index]
                    case ..<grayEnd:
                        let index = min(graySteps.count - 1, max(0, u * graySteps.count / chordWidth))
                        color = graySteps[index]
                    case ..<gratingsEnd:
                        let zoneWidth = chordWidth / gratingHalfPeriods.count
                        let zone = min(gratingHalfPeriods.count - 1, max(0, u / zoneWidth))
                        let phase = (u % zoneWidth) / gratingHalfPeriods[zone]
                        color = phase % 2 == 0 ? Self.white : Self.black
                    case ..<clockEnd:
                        // The NO SIGNAL and clock bands share a black field.
                        color = Self.black
                    default:
                        color = bottomField
                    }
                } else if dist <= outerRadius {
                    color = Self.white
                } else if x < 16 || x >= width - 16 || y < 16 || y >= height - 16 {
                    // Border castellations: alternating white/black blocks.
                    let along = (y < 16 || y >= height - 16) ? x : y
                    color = (along / 40) % 2 == 0 ? Self.white : Self.black
                } else if x % 80 < 2 || y % 80 < 2 {
                    color = gridLine
                } else {
                    color = surround
                }
                pixels[y * width + x] = color
            }
        }

        // Station identity and state, baked into the static card.
        Self.drawText("OLLIN", into: &pixels, width: width,
                      centerX: centerX, top: stationEnd - (stationEnd - splitEnd) / 2 - 21, scale: 6)
        Self.drawText("NO SIGNAL", into: &pixels, width: width,
                      centerX: centerX, top: messageEnd - (messageEnd - gratingsEnd) / 2 - 17, scale: 5)

        card = pixels
        clockBandCenterY = clockEnd - (clockEnd - messageEnd) / 2
        dotCenterY = (clockEnd + (centerY + Int(innerRadius))) / 2
    }

    /// Vertical centers for the two animated elements, fixed at init.
    private let clockBandCenterY: Int
    private let dotCenterY: Int

    /// Copy the card into `pixelBuffer` and draw the animated elements:
    /// a wall-clock readout and a dot ping-ponging across the bottom field.
    func render(into pixelBuffer: CVPixelBuffer, frame: UInt64, frameRate: Int) {
        CVPixelBufferLockBaseAddress(pixelBuffer, [])
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, []) }
        guard let base = CVPixelBufferGetBaseAddress(pixelBuffer) else { return }

        let bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)
        let copyWidth = min(width, CVPixelBufferGetWidth(pixelBuffer))
        let copyHeight = min(height, CVPixelBufferGetHeight(pixelBuffer))
        card.withUnsafeBufferPointer { source in
            for y in 0..<copyHeight {
                memcpy(base.advanced(by: y * bytesPerRow),
                       source.baseAddress!.advanced(by: y * width),
                       copyWidth * 4)
            }
        }

        let pixels = base.assumingMemoryBound(to: UInt8.self)
        let writePixel: (Int, Int, UInt32) -> Void = { x, y, color in
            guard x >= 0, x < copyWidth, y >= 0, y < copyHeight else { return }
            pixels.advanced(by: y * bytesPerRow + x * 4)
                .withMemoryRebound(to: UInt32.self, capacity: 1) { $0.pointee = color }
        }

        // Live clock, the classic proof a test card is not a still.
        var now = time(nil)
        var parts = tm()
        localtime_r(&now, &parts)
        let clock = String(format: "%02d:%02d:%02d", parts.tm_hour, parts.tm_min, parts.tm_sec)
        Self.drawText(clock, plot: writePixel,
                      centerX: centerX, top: clockBandCenterY - 17, scale: 5)

        // A dot ping-ponging across the bottom field, clipped to the circle.
        let t = Double(frame) / Double(frameRate)
        let amplitude = 130.0
        let dotX = Double(centerX) + sin(t * .pi / 3) * amplitude
        let radius = 14
        for oy in -radius...radius {
            for ox in -radius...radius where ox * ox + oy * oy <= radius * radius {
                let x = Int(dotX) + ox
                let y = dotCenterY + oy
                let dx = Double(x - centerX) + 0.5
                let dy = Double(y - centerY) + 0.5
                if (dx * dx + dy * dy).squareRoot() <= innerRadius - 2 {
                    writePixel(x, y, Self.white)
                }
            }
        }
    }

    // MARK: Text

    /// A 5×7 pixel font covering just the card's character set.
    private static let glyphs: [Character: [UInt8]] = [
        "A": [0b01110, 0b10001, 0b10001, 0b11111, 0b10001, 0b10001, 0b10001],
        "G": [0b01110, 0b10001, 0b10000, 0b10111, 0b10001, 0b10001, 0b01111],
        "I": [0b11111, 0b00100, 0b00100, 0b00100, 0b00100, 0b00100, 0b11111],
        "L": [0b10000, 0b10000, 0b10000, 0b10000, 0b10000, 0b10000, 0b11111],
        "N": [0b10001, 0b11001, 0b11001, 0b10101, 0b10011, 0b10011, 0b10001],
        "O": [0b01110, 0b10001, 0b10001, 0b10001, 0b10001, 0b10001, 0b01110],
        "S": [0b01111, 0b10000, 0b10000, 0b01110, 0b00001, 0b00001, 0b11110],
        "0": [0b01110, 0b10001, 0b10011, 0b10101, 0b11001, 0b10001, 0b01110],
        "1": [0b00100, 0b01100, 0b00100, 0b00100, 0b00100, 0b00100, 0b01110],
        "2": [0b01110, 0b10001, 0b00001, 0b00010, 0b00100, 0b01000, 0b11111],
        "3": [0b11111, 0b00010, 0b00100, 0b00010, 0b00001, 0b10001, 0b01110],
        "4": [0b00010, 0b00110, 0b01010, 0b10010, 0b11111, 0b00010, 0b00010],
        "5": [0b11111, 0b10000, 0b11110, 0b00001, 0b00001, 0b10001, 0b01110],
        "6": [0b00110, 0b01000, 0b10000, 0b11110, 0b10001, 0b10001, 0b01110],
        "7": [0b11111, 0b00001, 0b00010, 0b00100, 0b01000, 0b01000, 0b01000],
        "8": [0b01110, 0b10001, 0b10001, 0b01110, 0b10001, 0b10001, 0b01110],
        "9": [0b01110, 0b10001, 0b10001, 0b01111, 0b00001, 0b00010, 0b01100],
        ":": [0b00000, 0b01100, 0b01100, 0b00000, 0b01100, 0b01100, 0b00000],
        " ": [0b00000, 0b00000, 0b00000, 0b00000, 0b00000, 0b00000, 0b00000],
    ]

    /// Draw `text` centered on `centerX` with its top edge at `top`, each font
    /// pixel scaled to a `scale`-sized square, through a per-pixel `plot`.
    private static func drawText(_ text: String, plot: (Int, Int, UInt32) -> Void,
                                 centerX: Int, top: Int, scale: Int) {
        let advance = 6 * scale
        let textWidth = text.count * advance - scale
        var penX = centerX - textWidth / 2
        for character in text {
            guard let rows = glyphs[character] else { penX += advance; continue }
            for (rowIndex, row) in rows.enumerated() {
                for column in 0..<5 where row & (0b10000 >> column) != 0 {
                    for sy in 0..<scale {
                        for sx in 0..<scale {
                            plot(penX + column * scale + sx, top + rowIndex * scale + sy, white)
                        }
                    }
                }
            }
            penX += advance
        }
    }

    /// `drawText` into a plain pixel array (the static-card build path).
    private static func drawText(_ text: String, into pixels: inout [UInt32], width: Int,
                                 centerX: Int, top: Int, scale: Int) {
        let height = pixels.count / width
        // Local copy so the closure doesn't capture the inout parameter.
        var scratch = pixels
        drawText(text, plot: { x, y, color in
            guard x >= 0, x < width, y >= 0, y < height else { return }
            scratch[y * width + x] = color
        }, centerX: centerX, top: top, scale: scale)
        pixels = scratch
    }
}
