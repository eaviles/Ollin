/// What the runner has told its host about the user shaders, and whether the
/// next frame has to tell it again.
///
/// The renderer records a user shader's compile error afresh every frame, and
/// the runner reads it after each one. The host hears a change: an error once,
/// and `nil` once when every shader compiles again. That is the whole machine
/// but for one more state. After the shaders are dropped to be compiled again
/// (a `.metal` file saved, the framework's library reloaded), the next frame's
/// answer is forwarded whatever it is, because the host may have cleared its own
/// copy in the meantime. Without that state, a shader saved with the same
/// mistake matches the last report and is never reported again, and a host that
/// cleared its copy on the save shows a clean stage over a broken shader.
struct ShaderErrorRelay {
    /// The last message forwarded (`nil` once "every shader compiles" was).
    private(set) var forwarded: String?
    /// Whether the next answer is forwarded even when it matches `forwarded`.
    private(set) var isStale = false

    /// The shaders are about to compile again: the next frame's answer is news.
    mutating func invalidate() { isStale = true }

    /// Whether `current`, the message the frame just recorded (`nil` for none),
    /// has to reach the host. Records it as forwarded when it does.
    mutating func shouldForward(_ current: String?) -> Bool {
        guard isStale || current != forwarded else { return false }
        forwarded = current
        isStale = false
        return true
    }
}
