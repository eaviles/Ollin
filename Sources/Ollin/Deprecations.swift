// Every deprecated public declaration in the module, kept together so the
// shims are easy to audit and to drop after their grace cycle. A shim keeps
// the old spelling, marks it deprecated with the full selector of the new one
// (labels and arity included, so Xcode offers the one-click fix-it), and
// forwards to the new declaration rather than duplicating it.
// Scripts/api-diff.sh reads for this: a shim anywhere else in the module fails
// preflight, and so does one with no `renamed:` or `message:`.

public extension CameraView {
    /// Former name for `isometric` (the same three-quarter angle).
    @available(*, deprecated, renamed: "isometric")
    static var corner: CameraView { .isometric }
}
