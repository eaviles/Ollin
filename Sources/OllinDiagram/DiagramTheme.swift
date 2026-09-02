import Ollin

/// The shared palette every Guide diagram and Docs catalog figure renders
/// against, in a light and a dark variant. One definition here is what keeps
/// four hundred figures on the same colors: before it existed each figure
/// carried its own hex copies, and they had drifted.
///
/// The values are the page's own: the figures are read on rendered Markdown
/// pages, so `paper`, `ink`, `muted`, `border`, and `card` take the exact
/// colors those pages use for their background, text, secondary text, rules,
/// and inset panels, in both variants. A figure on `paper` then sits on the
/// page as part of it rather than as a pasted picture. `accent` stays the
/// book's own highlight orange, one hue tuned per variant, so the thing a
/// diagram points at never reads as a link.
///
/// A figure declares its `darkTheme` parameter and builds the theme from it:
///
/// ```swift
/// @Param var darkTheme = false
/// var theme: DiagramTheme { DiagramTheme(dark: darkTheme) }
/// ```
public struct DiagramTheme: Sendable {

    /// Whether this is the dark variant.
    public let dark: Bool

    /// The page background the figure sits on.
    public let paper: Color
    /// Primary marks and text.
    public let ink: Color
    /// Secondary text: notes, de-emphasized labels.
    public let muted: Color
    /// Rules and panel borders, at the page's own border color.
    public let border: Color
    /// An inset panel's fill, one quiet step off the paper.
    public let card: Color
    /// The highlight: what the diagram is pointing at.
    public let accent: Color

    public init(dark: Bool) {
        self.dark = dark
        paper = Color(hex: dark ? 0x0D1117 : 0xFFFFFF)
        ink = Color(hex: dark ? 0xF0F6FC : 0x1F2328)
        muted = Color(hex: dark ? 0x9198A1 : 0x59636E)
        border = Color(hex: dark ? 0x3D444D : 0xD1D9E0)
        card = Color(hex: dark ? 0x151B23 : 0xF6F8FA)
        accent = Color(hex: dark ? 0xEF6A3E : 0xE4572E)
    }

    /// The ink at an opacity: the one call behind every figure's washes and
    /// faint guides, so a figure names its own strength without naming a hex.
    public func ink(_ alpha: Double) -> Color {
        ink.withAlpha(alpha)
    }

    /// The accent at an opacity, for glows and soft highlights.
    public func accent(_ alpha: Double) -> Color {
        accent.withAlpha(alpha)
    }
}

public extension Sketch {
    /// A diagram panel: the rectangle stroked in the theme's border color,
    /// with an optional title on the line above its top-left corner. The
    /// frame dozens of figures used to carry as a private copy each.
    ///
    /// ```swift
    /// diagramFrame(panel, title: "before", theme: theme)
    /// ```
    func diagramFrame(_ rect: Rectangle, title: String? = nil, theme: DiagramTheme) {
        withState {
            noFill()
            stroke(theme.border)
            strokeWeight(2)
            drawRect(rect)
        }
        if let title {
            drawText(title, rect.x, rect.y - 20,
                     size: 17, color: theme.ink, align: .left, .middle)
        }
    }

    /// The one-line summary a diagram ends with, centered under the panels.
    ///
    /// ```swift
    /// diagramCaption("the same field, three zooms", at: 364, theme: theme)
    /// ```
    func diagramCaption(_ text: String, at y: Double, theme: DiagramTheme) {
        drawText(text, width / 2, y, size: 21, color: theme.ink, align: .center, .top)
    }
}
