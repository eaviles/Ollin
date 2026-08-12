import Foundation

/// A named fixture: a start address plus the ordered roles of its channels, so
/// a sketch writes "this par, this color" instead of raw channel numbers.
///
/// ```swift
/// let par = DMXFixture.rgb(at: 1)                    // channels 1-3
/// let wash = DMXFixture.rgbw(at: par.nextAddress)    // channels 4-7
/// let head = DMXFixture(at: 20, .pan, .tilt, .dimmer, .red, .green, .blue)
///
/// rig.set(par, color: .red)
/// rig.set(head, .pan, level: 0.25)
/// ```
///
/// The layout is whatever the fixture's manual says its mode is, spelled as
/// roles in channel order; `.unused` holds a slot the sketch doesn't drive.
/// Writes go through `DMXUniverse.set(_:color:dimmer:)` and friends.
public struct DMXFixture: Equatable, Sendable {

    /// What a channel of a fixture does. The color and dimmer roles are the
    /// ones the `DMXUniverse` sugar drives; the rest are set by role
    /// explicitly (`set(_:_:level:)`).
    public enum Role: Equatable, Hashable, Sendable {
        case dimmer, red, green, blue, white, amber, uv
        case pan, tilt, strobe, unused
    }

    /// The fixture's first channel, numbered 1 to 512.
    public let address: Int

    /// The fixture's channels in order, starting at `address`.
    public let layout: [Role]

    public init(at address: Int, _ layout: [Role]) {
        self.address = address
        self.layout = layout
    }

    public init(at address: Int, _ layout: Role...) {
        self.init(at: address, layout)
    }

    /// How many channels the fixture occupies.
    public var channelCount: Int { layout.count }

    /// The first free channel after this fixture, for patching the next one
    /// right behind it.
    public var nextAddress: Int { address + layout.count }

    /// The absolute channel of the first occurrence of a role, or `nil` if the
    /// layout doesn't have it.
    public func channel(of role: Role) -> Int? {
        layout.firstIndex(of: role).map { address + $0 }
    }

    // MARK: Common layouts

    /// A single dimmer channel.
    public static func dimmer(at address: Int) -> DMXFixture {
        DMXFixture(at: address, .dimmer)
    }

    /// A three-channel RGB fixture.
    public static func rgb(at address: Int) -> DMXFixture {
        DMXFixture(at: address, .red, .green, .blue)
    }

    /// A four-channel RGBW fixture.
    public static func rgbw(at address: Int) -> DMXFixture {
        DMXFixture(at: address, .red, .green, .blue, .white)
    }

    /// A dimmer followed by RGB, the other common par mode.
    public static func drgb(at address: Int) -> DMXFixture {
        DMXFixture(at: address, .dimmer, .red, .green, .blue)
    }
}
