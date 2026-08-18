/// A named non-printing key, the typed companion to a `Sketch`'s `key`. Ordinary
/// character keys (letters, digits, punctuation, space) arrive as `key` (a
/// `Character`); keys with no useful character — arrows, return, the function
/// row — arrive as `keyCode` instead, so a sketch reads `keyCode == .leftArrow`
/// rather than matching a magic number.
public enum KeyCode: Hashable, Sendable, Codable {
    case upArrow, downArrow, leftArrow, rightArrow
    /// The main Return key.
    case `return`
    /// The numeric keypad's Enter key (distinct from `return`).
    case enter
    case tab
    case escape
    /// The Delete (Backspace) key — deletes the character before the cursor.
    case delete
    /// Forward Delete (Fn+Delete) — deletes the character after the cursor.
    case forwardDelete
    case home, end, pageUp, pageDown
    /// A function-row key, numbered from 1 (`F1` is `.function(1)`).
    case function(Int)
}

/// What the pressed-key set tracks, so `isKeyDown` can answer for either a
/// character or a named key through one store. Internal — the public surface is
/// the `key`/`keyCode` properties and the `isKeyDown` overloads.
enum KeyToken: Hashable {
    case character(Character)
    case code(KeyCode)
}

/// The modifier keys held during an input event (shift, option (alt), command,
/// and control), as an `OptionSet`, so a sketch reads `modifiers.contains(.shift)`
/// or tests `modifiers == [.command, .shift]`. Platform-neutral; the live view
/// maps the system's modifier flags onto it. Read it through `Sketch.modifiers`.
public struct ModifierKeys: OptionSet, Sendable, Codable {
    public let rawValue: Int
    public init(rawValue: Int) { self.rawValue = rawValue }

    /// The Shift key.
    public static let shift = ModifierKeys(rawValue: 1 << 0)
    /// The Option (Alt) key.
    public static let option = ModifierKeys(rawValue: 1 << 1)
    /// The Command key.
    public static let command = ModifierKeys(rawValue: 1 << 2)
    /// The Control key.
    public static let control = ModifierKeys(rawValue: 1 << 3)
}
