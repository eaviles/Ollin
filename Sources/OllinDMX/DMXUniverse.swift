import Foundation
import Ollin

/// One DMX universe: 512 channels, each a byte. This is the value a sketch
/// fills every frame and hands to a `DMXSender`, and the value a `DMXReceiver`
/// hands back.
///
/// Channels are numbered 1 to 512, the way every console, dimmer, and fixture
/// manual numbers them. Reading outside that range returns 0 and writing
/// outside it does nothing, so an off-by-one never traps mid-performance.
///
/// ```swift
/// var rig = DMXUniverse()
/// rig[1] = 255                       // channel 1 to full
/// rig.set(2, level: 0.5)             // channel 2 to half, as a 0…1 level
/// rig.set(10, color: .red)           // channels 10, 11, 12 = R, G, B
/// ```
///
/// The fixture sugar writes through a named layout instead of raw numbers; see
/// `DMXFixture`.
public struct DMXUniverse: Equatable, Sendable {

    /// Channels per universe, fixed by DMX512.
    public static let channelCount = 512

    /// The raw channel bytes, always exactly 512. Index 0 is channel 1.
    public private(set) var channels: [UInt8]

    /// A universe with every channel at 0 (all dark).
    public init() {
        channels = [UInt8](repeating: 0, count: Self.channelCount)
    }

    /// A universe from raw bytes. Shorter input is padded with 0; longer input
    /// is truncated to 512.
    public init(channels: [UInt8]) {
        var bytes = Array(channels.prefix(Self.channelCount))
        if bytes.count < Self.channelCount {
            bytes.append(contentsOf: repeatElement(0, count: Self.channelCount - bytes.count))
        }
        self.channels = bytes
    }

    // MARK: Raw channel access

    /// The value of a channel, numbered 1 to 512. Out of range reads 0;
    /// out-of-range writes are ignored.
    public subscript(channel: Int) -> UInt8 {
        get {
            guard (1...Self.channelCount).contains(channel) else { return 0 }
            return channels[channel - 1]
        }
        set {
            guard (1...Self.channelCount).contains(channel) else { return }
            channels[channel - 1] = newValue
        }
    }

    /// Sets a channel from a 0…1 level (clamped), the natural unit when a
    /// value comes from an animation or a `@Param`.
    public mutating func set(_ channel: Int, level: Double) {
        self[channel] = DMXUniverse.byte(level)
    }

    /// Sets a channel to a raw byte.
    public mutating func set(_ channel: Int, to value: UInt8) {
        self[channel] = value
    }

    /// A channel read back as a 0…1 level.
    public func level(_ channel: Int) -> Double {
        Double(self[channel]) / 255
    }

    /// Writes a color as three consecutive channels: red at `channel`, green
    /// and blue on the next two.
    public mutating func set(_ channel: Int, color: Color) {
        self[channel] = DMXUniverse.byte(color.red)
        self[channel + 1] = DMXUniverse.byte(color.green)
        self[channel + 2] = DMXUniverse.byte(color.blue)
    }

    /// Three consecutive channels read back as a color (red at `channel`).
    public func color(_ channel: Int) -> Color {
        Color(red: level(channel), green: level(channel + 1), blue: level(channel + 2))
    }

    /// Every channel back to 0.
    public mutating func clear() {
        channels = [UInt8](repeating: 0, count: Self.channelCount)
    }

    // MARK: Fixture sugar

    /// Lights a fixture: the color lands on its red/green/blue channels (plus
    /// white, split out as the shared part of the color, on an RGBW layout)
    /// and `dimmer` on its dimmer channel. A fixture with no dimmer channel
    /// scales the color instead, so `dimmer` means brightness either way.
    public mutating func set(_ fixture: DMXFixture, color: Color, dimmer: Double = 1) {
        var r = min(max(color.red, 0), 1)
        var g = min(max(color.green, 0), 1)
        var b = min(max(color.blue, 0), 1)
        var w = 0.0
        if fixture.layout.contains(.white) {
            // The classic RGB-to-RGBW split: the shared part moves to white.
            w = min(r, min(g, b))
            r -= w; g -= w; b -= w
        }
        let gain = fixture.layout.contains(.dimmer) ? 1.0 : min(max(dimmer, 0), 1)
        for (offset, role) in fixture.layout.enumerated() {
            let channel = fixture.address + offset
            switch role {
            case .dimmer: set(channel, level: dimmer)
            case .red: set(channel, level: r * gain)
            case .green: set(channel, level: g * gain)
            case .blue: set(channel, level: b * gain)
            case .white: set(channel, level: w * gain)
            default: break
            }
        }
    }

    /// Sets one role of a fixture (every channel of its layout holding that
    /// role) from a 0…1 level.
    public mutating func set(_ fixture: DMXFixture, _ role: DMXFixture.Role, level: Double) {
        for (offset, r) in fixture.layout.enumerated() where r == role {
            set(fixture.address + offset, level: level)
        }
    }

    /// Sets one role of a fixture to a raw byte.
    public mutating func set(_ fixture: DMXFixture, _ role: DMXFixture.Role, to value: UInt8) {
        for (offset, r) in fixture.layout.enumerated() where r == role {
            self[fixture.address + offset] = value
        }
    }

    private static func byte(_ level: Double) -> UInt8 {
        UInt8((min(max(level, 0), 1) * 255).rounded())
    }
}
