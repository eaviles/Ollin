import Foundation

/// The path to a file kept in a folder beside (or above) the calling sketch:
/// `sketchResource("Depth.mlmodel")` finds the nearest `Models` folder walking
/// up from the sketch's own source file and answers the file's path inside it,
/// or `nil` when no such folder exists on the way up.
///
/// The current directory is wherever the sketch was launched from, so a path
/// relative to it breaks the moment the sketch runs from somewhere else; this
/// walk is anchored to the source file instead, which stays put. A free
/// function rather than a `Sketch` method so a `static let` can call it.
///
/// ```swift
/// static let modelPath = sketchResource("StyleTransfer.mlmodel")
/// let dataPath = sketchResource("quakes.csv", in: "Data")
/// ```
///
/// Leave `from` alone: it defaults to the caller's own file, which is the
/// anchor the walk wants. (For a file *bundled into a target*, use
/// `Bundle.module` and the loaders' `resource:in:` forms instead; this is for
/// the loose folder-next-to-the-sketch arrangement.)
public func sketchResource(_ name: String, in folder: String = "Models",
                           from file: String = #filePath) -> String? {
    var dir = (file as NSString).deletingLastPathComponent
    while dir.count > 1 {
        let candidate = (dir as NSString).appendingPathComponent(folder)
        if FileManager.default.fileExists(atPath: candidate) {
            return (candidate as NSString).appendingPathComponent(name)
        }
        dir = (dir as NSString).deletingLastPathComponent
    }
    return nil
}

/// Where the framework's own bundled files come from: the shader segments, the
/// built-in fonts, the matcap images, the area-light tables.
///
/// The package manager writes a `Bundle.module` accessor for every target that
/// carries resources, and that accessor looks in two places: beside the running
/// executable, and at the absolute path the machine built at. Both are right for
/// a sketch you run, and both are wrong for a plug-in. A plug-in is loaded by a
/// program somebody else wrote, so the executable beside it belongs to that
/// program, and the build path belongs to whoever compiled it. A screen saver is
/// the first host in that shape, and it will not be the last.
///
/// So the lookup is done here instead, over a longer list of candidates, with the
/// generated accessor kept as the last of them. The first candidate is the one
/// the accessor tries first, which is why an ordinary run resolves to exactly the
/// bundle it always did.
///
/// A satellite with resources of its own calls ``resolve(_:fallback:)`` with its
/// own bundle name and its own `Bundle.module`. The class token below lives in
/// this module, but every module in a plug-in is linked into the one binary, so
/// the plug-in it finds is the same plug-in for all of them.
package enum OllinResources {

    /// The `Ollin` module's own resources.
    package static let bundle: Bundle = resolve("Ollin_Ollin.bundle", fallback: Bundle.module)

    /// Find a resource bundle by name, or fall back to the generated accessor.
    ///
    /// - Parameters:
    ///   - name: the bundle's file name, as the package manager writes it
    ///     (`<package>_<target>.bundle`).
    ///   - fallback: the module's own `Bundle.module`. It is an autoclosure
    ///     because that accessor stops the program when it finds nothing, so it
    ///     must not be touched while a candidate is still in hand.
    package static func resolve(_ name: String, fallback: @autoclosure () -> Bundle) -> Bundle {
        // The bundle that holds Ollin's own code: the plug-in itself when this is
        // a plug-in, and the program itself when it is not.
        let host = Bundle(for: ResourceToken.self)
        let candidates = [
            Bundle.main.bundleURL,      // beside the executable: a `swift run`, or an app's MacOS dir
            Bundle.main.resourceURL,    // an app's Resources
            host.resourceURL,           // a plug-in's Resources: the screen-saver case
            host.bundleURL,             // a plug-in's own directory
        ]
        for directory in candidates.compactMap({ $0 }) {
            if let found = Bundle(url: directory.appendingPathComponent(name)) { return found }
        }
        return fallback()
    }
}

/// A class to ask `Bundle(for:)` about. It carries no behavior; its only job is
/// to name the binary this code was linked into.
private final class ResourceToken {}
