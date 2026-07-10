import Foundation

/// One spot ink on a physical press: a name for the drum or screen it prints
/// from, and the color it lays down at full coverage on white paper.
///
/// A print separation (see `Image.separated(into:paper:)`) splits an image
/// into one grayscale master per ink, so an `Ink` is the unit a separation is
/// asked for in. The built-in catalog below carries the standard risograph
/// ink line, named the way a print shop stocks them; the color of each is the
/// community-measured screen approximation (soy inks do not conform exactly
/// to any color standard), so treat it as a preview, not a promise.
///
/// ```swift
/// let sep = image.separated(into: [.black, .fluorescentPink])
/// let custom = Ink(name: "Shop Blue", color: Color(hex: 0x2B5DD7))
/// ```
public struct Ink: Hashable, Sendable {
    /// The ink's display name, used to label and file its exported master.
    public var name: String
    /// The color the ink prints at full coverage on white stock.
    public var color: Color

    public init(name: String, color: Color) {
        self.name = name
        self.color = color
    }

    /// The catalog ink whose name matches, ignoring case, spaces, and
    /// hyphens: `Ink.named("fluorescent pink")`, `Ink.named("Flat-Gold")`.
    /// `nil` when no built-in ink matches.
    public static func named(_ name: String) -> Ink? {
        let key = fold(name)
        return catalog.first { fold($0.name) == key }
    }

    private static func fold(_ name: String) -> String {
        name.lowercased().filter { !$0.isWhitespace && $0 != "-" }
    }
}

// MARK: - The built-in ink catalog

// The standard risograph ink line as stocked by print shops, with the
// community-measured screen values (sourced from the stencil.wiki color list;
// credited in ATTRIBUTION.md).
public extension Ink {
    static let black = Ink(name: "Black", color: Color(hex: 0x000000))
    static let burgundy = Ink(name: "Burgundy", color: Color(hex: 0x914E72))
    static let blue = Ink(name: "Blue", color: Color(hex: 0x0078BF))
    static let green = Ink(name: "Green", color: Color(hex: 0x00A95C))
    static let mediumBlue = Ink(name: "Medium Blue", color: Color(hex: 0x3255A4))
    static let brightRed = Ink(name: "Bright Red", color: Color(hex: 0xF15060))
    static let federalBlue = Ink(name: "Federal Blue", color: Color(hex: 0x3D5588))
    static let purple = Ink(name: "Purple", color: Color(hex: 0x765BA7))
    static let teal = Ink(name: "Teal", color: Color(hex: 0x00838A))
    static let flatGold = Ink(name: "Flat Gold", color: Color(hex: 0xBB8B41))
    static let hunterGreen = Ink(name: "Hunter Green", color: Color(hex: 0x407060))
    static let red = Ink(name: "Red", color: Color(hex: 0xFF665E))
    static let brown = Ink(name: "Brown", color: Color(hex: 0x925F52))
    static let yellow = Ink(name: "Yellow", color: Color(hex: 0xFFE800))
    static let marineRed = Ink(name: "Marine Red", color: Color(hex: 0xD2515E))
    static let orange = Ink(name: "Orange", color: Color(hex: 0xFF6C2F))
    static let fluorescentPink = Ink(name: "Fluorescent Pink", color: Color(hex: 0xFF48B0))
    static let lightGray = Ink(name: "Light Gray", color: Color(hex: 0x88898A))
    static let metallicGold = Ink(name: "Metallic Gold", color: Color(hex: 0xAC936E))
    static let crimson = Ink(name: "Crimson", color: Color(hex: 0xE45D50))
    static let fluorescentOrange = Ink(name: "Fluorescent Orange", color: Color(hex: 0xFF7477))
    static let cornflower = Ink(name: "Cornflower", color: Color(hex: 0x62A8E5))
    static let skyBlue = Ink(name: "Sky Blue", color: Color(hex: 0x4982CF))
    static let seaBlue = Ink(name: "Sea Blue", color: Color(hex: 0x0074A2))
    static let lake = Ink(name: "Lake", color: Color(hex: 0x235BA8))
    static let indigo = Ink(name: "Indigo", color: Color(hex: 0x484D7A))
    static let midnight = Ink(name: "Midnight", color: Color(hex: 0x435060))
    static let mist = Ink(name: "Mist", color: Color(hex: 0xD5E4C0))
    static let granite = Ink(name: "Granite", color: Color(hex: 0xA5AAA8))
    static let charcoal = Ink(name: "Charcoal", color: Color(hex: 0x70747C))
    static let smokyTeal = Ink(name: "Smoky Teal", color: Color(hex: 0x5F8289))
    static let steel = Ink(name: "Steel", color: Color(hex: 0x375E77))
    static let slate = Ink(name: "Slate", color: Color(hex: 0x5E695E))
    static let turquoise = Ink(name: "Turquoise", color: Color(hex: 0x00AA93))
    static let emerald = Ink(name: "Emerald", color: Color(hex: 0x19975D))
    static let grass = Ink(name: "Grass", color: Color(hex: 0x397E58))
    static let forest = Ink(name: "Forest", color: Color(hex: 0x516E5A))
    static let spruce = Ink(name: "Spruce", color: Color(hex: 0x4A635D))
    static let moss = Ink(name: "Moss", color: Color(hex: 0x68724D))
    static let seaFoam = Ink(name: "Sea Foam", color: Color(hex: 0x62C2B1))
    static let kellyGreen = Ink(name: "Kelly Green", color: Color(hex: 0x67B346))
    static let lightTeal = Ink(name: "Light Teal", color: Color(hex: 0x009DA5))
    static let ivy = Ink(name: "Ivy", color: Color(hex: 0x169B62))
    static let pine = Ink(name: "Pine", color: Color(hex: 0x237E74))
    static let lagoon = Ink(name: "Lagoon", color: Color(hex: 0x2F6165))
    static let violet = Ink(name: "Violet", color: Color(hex: 0x9D7AD2))
    static let orchid = Ink(name: "Orchid", color: Color(hex: 0xAA60BF))
    static let plum = Ink(name: "Plum", color: Color(hex: 0x845991))
    static let raisin = Ink(name: "Raisin", color: Color(hex: 0x775D7A))
    static let grape = Ink(name: "Grape", color: Color(hex: 0x6C5D80))
    static let scarlet = Ink(name: "Scarlet", color: Color(hex: 0xF65058))
    static let tomato = Ink(name: "Tomato", color: Color(hex: 0xD2515E))
    static let cranberry = Ink(name: "Cranberry", color: Color(hex: 0xD1517A))
    static let maroon = Ink(name: "Maroon", color: Color(hex: 0x9E4C6E))
    static let raspberryRed = Ink(name: "Raspberry Red", color: Color(hex: 0xD1517A))
    static let brick = Ink(name: "Brick", color: Color(hex: 0xA75154))
    static let lightLime = Ink(name: "Light Lime", color: Color(hex: 0xE3ED55))
    static let sunflower = Ink(name: "Sunflower", color: Color(hex: 0xFFB511))
    static let melon = Ink(name: "Melon", color: Color(hex: 0xFFAE3B))
    static let apricot = Ink(name: "Apricot", color: Color(hex: 0xF6A04D))
    static let paprika = Ink(name: "Paprika", color: Color(hex: 0xEE7F4B))
    static let pumpkin = Ink(name: "Pumpkin", color: Color(hex: 0xFF6F4C))
    static let brightOliveGreen = Ink(name: "Bright Olive Green", color: Color(hex: 0xB49F29))
    static let brightGold = Ink(name: "Bright Gold", color: Color(hex: 0xBA8032))
    static let copper = Ink(name: "Copper", color: Color(hex: 0xBD6439))
    static let mahogany = Ink(name: "Mahogany", color: Color(hex: 0x8E595A))
    static let bisque = Ink(name: "Bisque", color: Color(hex: 0xF2CDCF))
    static let bubbleGum = Ink(name: "Bubble Gum", color: Color(hex: 0xF984CA))
    static let lightMauve = Ink(name: "Light Mauve", color: Color(hex: 0xE6B5C9))
    static let darkMauve = Ink(name: "Dark Mauve", color: Color(hex: 0xBD8CA6))
    static let wine = Ink(name: "Wine", color: Color(hex: 0x914E72))
    static let gray = Ink(name: "Gray", color: Color(hex: 0x928D88))
    static let white = Ink(name: "White", color: Color(hex: 0xFFFFFF))
    static let aqua = Ink(name: "Aqua", color: Color(hex: 0x5EC8E5))
    static let mint = Ink(name: "Mint", color: Color(hex: 0x82D8D5))
    static let fluorescentYellow = Ink(name: "Fluorescent Yellow", color: Color(hex: 0xFFE900))
    static let fluorescentRed = Ink(name: "Fluorescent Red", color: Color(hex: 0xFF4C65))
    static let fluorescentGreen = Ink(name: "Fluorescent Green", color: Color(hex: 0x44D62C))

    /// Every built-in ink, in catalog order.
    static let catalog: [Ink] = [
        .black, .burgundy, .blue, .green, .mediumBlue, .brightRed,
        .federalBlue, .purple, .teal, .flatGold, .hunterGreen, .red,
        .brown, .yellow, .marineRed, .orange, .fluorescentPink, .lightGray,
        .metallicGold, .crimson, .fluorescentOrange, .cornflower, .skyBlue, .seaBlue,
        .lake, .indigo, .midnight, .mist, .granite, .charcoal,
        .smokyTeal, .steel, .slate, .turquoise, .emerald, .grass,
        .forest, .spruce, .moss, .seaFoam, .kellyGreen, .lightTeal,
        .ivy, .pine, .lagoon, .violet, .orchid, .plum,
        .raisin, .grape, .scarlet, .tomato, .cranberry, .maroon,
        .raspberryRed, .brick, .lightLime, .sunflower, .melon, .apricot,
        .paprika, .pumpkin, .brightOliveGreen, .brightGold, .copper, .mahogany,
        .bisque, .bubbleGum, .lightMauve, .darkMauve, .wine, .gray,
        .white, .aqua, .mint, .fluorescentYellow, .fluorescentRed, .fluorescentGreen,
    ]
}
