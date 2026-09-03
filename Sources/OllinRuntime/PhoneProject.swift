import Foundation

/// The small app `ollin phone` wraps around one sketch file so a phone can run
/// it: an Xcode project spec, an `Info.plist`, and a host file that puts the
/// sketch in a `SketchView`, writes its state down as it runs, and serves its
/// parameters to the Mac. The sketch file is *referenced* where it is, never
/// copied, so a save on the Mac is what the next build compiles.
///
/// The reference goes through two links inside the project folder, `Sketch`
/// (the sketch's own folder) and `Ollin` (the checkout), and the spec names
/// everything by a short path under them. Not for tidiness: xcodegen's
/// relative-path routine loops forever when a source path and the project
/// folder share nothing but the root, so an absolute path to a sketch on
/// another volume, or a project folder under `/var`, never came back.
///
/// The plan is pure text: nothing here touches a device, a compiler, or the
/// network, which is what lets the tests read it without either. Only
/// `write(to:)` touches the disk.
package struct PhoneProject: Sendable, Equatable {

    /// The satellites known to build for the phone. An `import` outside this
    /// list is not refused, since most of the rest have simply never been
    /// tried, but the plan names it so a build that fails on it is no mystery.
    package static let satellitesOnThePhone: Set<String> = [
        "OllinRemote", "OllinPhysics", "OllinOSC", "OllinMIDI", "OllinController",
        "OllinVideo", "OllinBluetooth", "OllinAudio", "OllinVision", "OllinHaptics",
    ]

    /// The satellites that cannot reach a phone by nature: each wraps a service
    /// that lives on the Mac (a camera extension, Syphon, the displays, or the
    /// Mac end of the phone link itself), so the import is refused with its
    /// reason rather than failing somewhere inside the build.
    package static let satellitesDeskOnly: [String: String] = [
        "OllinCamera": "a virtual camera is a Mac camera extension",
        "OllinSyphon": "Syphon shares frames between Mac apps",
        "OllinScreen": "screen capture reads the Mac's displays",
        "OllinRecord3D": "the phone link runs on the Mac end of the cable",
        "OllinPhone": "the phone link runs on the Mac end of the cable",
    ]

    /// Files beside the sketch that ride along as the app's own resources, so
    /// what `Bundle.module` finds on the desk it finds on the phone too.
    package static let assetExtensions: Set<String> = [
        "png", "jpg", "jpeg", "heic", "gif", "tif", "tiff", "hdr", "exr",
        "mov", "mp4", "m4v", "m4a", "mp3", "wav", "aif", "aiff", "caf",
        "json", "csv", "txt", "svg", "ttf", "otf", "metal",
        "obj", "mtl", "gltf", "glb", "usdz", "usd", "usdc", "usda", "sfz",
    ]

    package static let bundleIdentifier = "dev.ollin.OllinPhone"
    package static let targetName = "OllinPhone"
    /// The link inside the project folder that stands for the sketch's folder.
    package static let sketchLink = "Sketch"
    /// The link inside the project folder that stands for the checkout.
    package static let frameworkLink = "Ollin"
    package static let hostFileName = "OllinPhoneHost.swift"
    package static let remotePort = 9330
    /// How often the app writes its state down, so a reinstall from the Mac
    /// loses at most this much of the clock.
    package static let checkpointSeconds = 1.0

    /// The sketch file, absolute.
    package let sketchPath: String
    /// The `Sketch` subclass the host makes.
    package let typeName: String
    /// The checkout the app builds the framework from.
    package let frameworkPath: String
    /// The signing team the project is built under.
    package let team: String
    /// The satellite products the sketch imports, sorted. `OllinRemote` is
    /// always among them: the host serves the parameters through it.
    package let satellites: [String]
    /// Imports outside `satellitesOnThePhone`, named so a failed build has a
    /// first suspect.
    package let untried: [String]
    /// Sibling files copied in as resources, absolute, sorted.
    package let assets: [String]

    package enum PlanError: Error, CustomStringConvertible, Equatable {
        case unreadable(String)
        case noSketch(String)
        case deskOnly([String])

        package var description: String {
            switch self {
            case .unreadable(let path):
                return "could not read \(path)"
            case .noSketch(let path):
                return "no `class …: Sketch` in \(path)"
            case .deskOnly(let imports):
                let reasons = imports.sorted().map { name in
                    "\(name) (\(PhoneProject.satellitesDeskOnly[name] ?? "desk only"))"
                }
                return "the sketch imports a satellite that stays on the desk: "
                    + reasons.joined(separator: ", ")
            }
        }
    }

    // MARK: Planning

    /// Read the sketch and its folder, and work out what the app needs.
    package static func plan(sketchPath: String, frameworkPath: String, team: String) throws -> PhoneProject {
        guard let source = try? String(contentsOfFile: sketchPath, encoding: .utf8) else {
            throw PlanError.unreadable(sketchPath)
        }
        let folder = (sketchPath as NSString).deletingLastPathComponent
        let siblings = ((try? FileManager.default.contentsOfDirectory(atPath: folder)) ?? [])
            .map { (folder as NSString).appendingPathComponent($0) }
        return try plan(source: source, sketchPath: sketchPath, siblings: siblings,
                        frameworkPath: frameworkPath, team: team)
    }

    /// The pure half: the same plan from text already read.
    package static func plan(source: String, sketchPath: String, siblings: [String],
                             frameworkPath: String, team: String) throws -> PhoneProject {
        guard let typeName = SketchLoader.sketchClassName(in: source) else {
            throw PlanError.noSketch(sketchPath)
        }
        let imports = importedSatellites(in: source)
        let deskOnly = imports.filter { satellitesDeskOnly[$0] != nil }
        guard deskOnly.isEmpty else { throw PlanError.deskOnly(deskOnly) }
        let satellites = Set(imports).union(["OllinRemote"]).sorted()
        let untried = imports.filter { !satellitesOnThePhone.contains($0) }.sorted()
        let assets = siblings
            .filter { $0 != sketchPath }
            .filter { assetExtensions.contains(($0 as NSString).pathExtension.lowercased()) }
            .filter { !(($0 as NSString).lastPathComponent).hasPrefix(".") }
            .sorted()
        return PhoneProject(sketchPath: sketchPath, typeName: typeName, frameworkPath: frameworkPath,
                            team: team, satellites: satellites, untried: untried, assets: assets)
    }

    /// Every `import Ollin…` line's module, in file order, the core itself left out.
    package static func importedSatellites(in source: String) -> [String] {
        let pattern = #"(?m)^\s*import\s+(Ollin\w+)\b"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        var seen = Set<String>()
        var found: [String] = []
        for match in regex.matches(in: source, range: NSRange(source.startIndex..., in: source)) {
            guard let range = Range(match.range(at: 1), in: source) else { continue }
            let name = String(source[range])
            if name != "Ollin", seen.insert(name).inserted { found.append(name) }
        }
        return found
    }

    // MARK: The files

    /// The sketch folder's name inside the project: the file, through the link.
    package var sketchReference: String {
        Self.sketchLink + "/" + (sketchPath as NSString).lastPathComponent
    }

    /// The xcodegen spec. The sketch and its assets are named through the
    /// `Sketch` link and the framework through the `Ollin` link, so every
    /// path stays short and inside the project folder.
    package var projectSpec: String {
        var sources = "      - path: Sources\n"
        sources += "      - path: \(yamlQuoted(sketchReference))\n"
        for asset in assets {
            let name = (asset as NSString).lastPathComponent
            sources += "      - path: \(yamlQuoted(Self.sketchLink + "/" + name))\n"
            sources += "        buildPhase: resources\n"
        }
        var dependencies = "      - package: Ollin\n        product: Ollin\n"
        for satellite in satellites {
            dependencies += "      - package: Ollin\n        product: \(satellite)\n"
        }
        return """
        # Written by `ollin phone` for \(typeName). Edit the sketch, not this file:
        # it is written again on every run.
        name: \(Self.targetName)

        options:
          bundleIdPrefix: dev.ollin
          deploymentTarget:
            iOS: "26.0"
          createIntermediateGroups: true

        settings:
          base:
            DEVELOPMENT_TEAM: \(yamlQuoted(team))
            CODE_SIGN_STYLE: Automatic
            SWIFT_VERSION: "6.0"
            MARKETING_VERSION: "0.1"
            CURRENT_PROJECT_VERSION: "1"
            GENERATE_INFOPLIST_FILE: NO

        packages:
          Ollin:
            path: \(Self.frameworkLink)

        targets:
          \(Self.targetName):
            type: application
            platform: iOS
            sources:
        \(sources)    dependencies:
        \(dependencies)    settings:
              base:
                PRODUCT_BUNDLE_IDENTIFIER: \(Self.bundleIdentifier)
                PRODUCT_NAME: \(Self.targetName)
                INFOPLIST_FILE: Info.plist
                TARGETED_DEVICE_FAMILY: "1,2"
                ENABLE_USER_SCRIPT_SANDBOXING: YES

        """
    }

    /// The app's property list. The display name is the sketch's type, so the
    /// icon on the phone says which sketch is loaded.
    package var infoPlist: String {
        """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
        \t<key>CFBundleDevelopmentRegion</key>
        \t<string>en</string>
        \t<key>CFBundleDisplayName</key>
        \t<string>\(xmlEscaped(typeName))</string>
        \t<key>CFBundleExecutable</key>
        \t<string>$(EXECUTABLE_NAME)</string>
        \t<key>CFBundleIdentifier</key>
        \t<string>$(PRODUCT_BUNDLE_IDENTIFIER)</string>
        \t<key>CFBundleInfoDictionaryVersion</key>
        \t<string>6.0</string>
        \t<key>CFBundleName</key>
        \t<string>$(PRODUCT_NAME)</string>
        \t<key>CFBundlePackageType</key>
        \t<string>APPL</string>
        \t<key>CFBundleShortVersionString</key>
        \t<string>$(MARKETING_VERSION)</string>
        \t<key>CFBundleVersion</key>
        \t<string>$(CURRENT_PROJECT_VERSION)</string>
        \t<key>LSRequiresIPhoneOS</key>
        \t<true/>
        \t<key>UILaunchScreen</key>
        \t<dict/>
        \t<key>UIApplicationSceneManifest</key>
        \t<dict>
        \t\t<key>UIApplicationSupportsMultipleScenes</key>
        \t\t<false/>
        \t</dict>
        \t<key>UISupportedInterfaceOrientations</key>
        \t<array>
        \t\t<string>UIInterfaceOrientationPortrait</string>
        \t\t<string>UIInterfaceOrientationLandscapeLeft</string>
        \t\t<string>UIInterfaceOrientationLandscapeRight</string>
        \t</array>
        \t<key>UISupportedInterfaceOrientations~ipad</key>
        \t<array>
        \t\t<string>UIInterfaceOrientationPortrait</string>
        \t\t<string>UIInterfaceOrientationPortraitUpsideDown</string>
        \t\t<string>UIInterfaceOrientationLandscapeLeft</string>
        \t\t<string>UIInterfaceOrientationLandscapeRight</string>
        \t</array>
        </dict>
        </plist>

        """
    }

    /// The host: the app around the sketch. It is the reference app's shape
    /// with three things added, each of which is what makes the tether read as
    /// a reload rather than a launch: the checkpoint, so the clock, the seed,
    /// and the parameters come back after a reinstall; the remote surface, so
    /// the Mac sees the parameters; and `Bundle.module` as the app, so a file
    /// beside the sketch is found where the desk found it.
    package var hostSource: String {
        """
        import SwiftUI
        import Ollin
        import OllinRemote

        // Written by `ollin phone` for \(typeName). Edit the sketch, not this file:
        // it is written again on every run.

        extension Bundle {
            /// The sketch is compiled into the app itself, and the files beside it
            /// were copied in as the app's own resources, so the bundle the sketch
            /// asks for is the app.
            static var module: Bundle { .main }
        }

        @main
        struct OllinPhoneHost: App {
            /// Made once for the life of the app. Its state (the clock, the seed,
            /// the parameters, every `@Saved` property) is written down as it runs
            /// and read back at launch, so a reinstall from the Mac carries on
            /// mid-motion; `--fresh` starts it over.
            private let sketch: Sketch

            init() {
                let sketch = \(typeName)()
                if CommandLine.arguments.contains("--fresh") { sketch.forgetCheckpoint() }
                sketch.extend(RemoteInspector(port: \(Self.remotePort)))
                self.sketch = sketch
            }

            // `Scene` is spelled out, because the framework has a 3D scene of its
            // own and the bare name is then two types.
            var body: some SwiftUI.Scene {
                WindowGroup {
                    SketchView(sketch, onRunner: { runner in
                        runner.beginInstallation(Installation(checkpoint: .every(seconds: \(Self.checkpointSeconds))))
                    })
                    .ignoresSafeArea()
                    .background(.black)
                    .statusBarHidden()
                    .persistentSystemOverlays(.hidden)
                }
            }
        }

        """
    }

    /// Put the three files and the two links down in `folder`, made if
    /// needed. They are the tool's own, so an older set is written over.
    package func write(to folder: URL) throws {
        let files = FileManager.default
        let sources = folder.appendingPathComponent("Sources", isDirectory: true)
        try files.createDirectory(at: sources, withIntermediateDirectories: true)
        try projectSpec.write(to: folder.appendingPathComponent("project.yml"), atomically: true, encoding: .utf8)
        try infoPlist.write(to: folder.appendingPathComponent("Info.plist"), atomically: true, encoding: .utf8)
        try hostSource.write(to: sources.appendingPathComponent(Self.hostFileName), atomically: true, encoding: .utf8)
        try Self.link(folder.appendingPathComponent(Self.sketchLink),
                      to: (sketchPath as NSString).deletingLastPathComponent)
        try Self.link(folder.appendingPathComponent(Self.frameworkLink), to: frameworkPath)
    }

    /// A symbolic link at `at` pointing at `destination`, replacing whatever
    /// was there.
    private static func link(_ at: URL, to destination: String) throws {
        let files = FileManager.default
        if (try? files.destinationOfSymbolicLink(atPath: at.path)) != nil || files.fileExists(atPath: at.path) {
            try files.removeItem(at: at)
        }
        try files.createSymbolicLink(at: at, withDestinationURL: URL(fileURLWithPath: destination, isDirectory: true))
    }

    // MARK: Quoting

    private func yamlQuoted(_ text: String) -> String {
        "\"" + text.replacingOccurrences(of: "\\", with: "\\\\")
                   .replacingOccurrences(of: "\"", with: "\\\"") + "\""
    }

    private func xmlEscaped(_ text: String) -> String {
        text.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }
}
