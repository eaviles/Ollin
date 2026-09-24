import Foundation

public extension StrokeFont {
    /// Load a stroke font bundled as a resource — the common case for a Hershey
    /// `.jhf` dropped in beside a sketch. `name` is the resource's filename
    /// *including* its extension. Throws a `FileError`: `missing` when the bundle
    /// holds no such resource, `unreadable` when it can't be parsed.
    ///
    /// Pass the bundle the resource lives in: `.module` for a SwiftPM target's own
    /// resources (a `swift run` sketch, the usual case) — it can't be the default,
    /// since a default argument would resolve to Ollin's bundle rather than yours —
    /// or the default `.main` for an app's main bundle.
    ///
    /// ```swift
    /// let font = (try? StrokeFont(resource: "rowmans.jhf", in: .module)) ?? .builtIn
    /// textFont(font)
    /// ```
    init(resource name: String, in bundle: Bundle = .main) throws {
        let reference = URL(fileURLWithPath: name)
        let base = reference.deletingPathExtension().lastPathComponent
        let ext = reference.pathExtension
        try self.init(jhfContentsOf: FileError.resource(base, withExtension: ext.isEmpty ? nil : ext,
                                                        in: bundle))
    }
}
