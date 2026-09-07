import Foundation

/// A sketch as an app for the phone and the tablet.
///
/// An app is installed onto a device, never run from the command line, so
/// what this kind writes is an Xcode project rather than a package: the spec
/// the `xcodegen` tool turns into one, a property list, a host that owns the
/// entry point and puts the sketch in a `SketchView`, and the sketch itself.
/// It is the shape of the reference app in the checkout, written around the
/// sketch chosen here.
///
/// Two facts shape the spec. The framework is named by its absolute path, as
/// the manifest kinds name it, and the spec tool takes that as it is; only a
/// *source* on another root trips its relative-path routine, and every source
/// here sits inside the project folder. And a `.metal` file rides as a
/// resource by name, because a Metal file under a source group is compiled
/// into a library, while the framework reads a shader's source at run time.
extension ProjectGenerator {

    static func planIOSApp(_ request: ProjectRequest) throws -> GeneratedProject {
        // A capability that wraps a Mac service cannot reach a device, and
        // the build would fail somewhere inside the satellite; say so here.
        for capability in request.resolvedCapabilities where capability.staysOnTheDesk != nil {
            throw ProjectGeneratorError.staysOnTheDesk(capability, request.kind)
        }
        for module in request.example?.modules ?? [] {
            if let capability = Capability.satellites.first(where: { $0.module == module }),
               capability.staysOnTheDesk != nil {
                throw ProjectGeneratorError.staysOnTheDesk(capability, request.kind)
            }
        }

        let root = request.destination.appendingPathComponent(request.folderName)
        let target = request.typeName
        let sourceDir = "Sources/\(target)"
        var (files, _) = sketchFiles(request, sourceDir: sourceDir)

        files.append(GeneratedFile(path: "\(sourceDir)/\(target)App.swift",
                                   contents: iOSHostSource(request, target: target)))
        files.append(GeneratedFile(path: "project.yml",
                                   contents: iOSProjectSpec(request, target: target, files: files)))
        files.append(GeneratedFile(path: "Info.plist",
                                   contents: iOSInfoPlist(request, target: target)))
        files.append(GeneratedFile(path: "README.md",
                                   contents: iOSReadme(request, target: target)))
        files.append(GeneratedFile(path: ".gitignore", contents: iOSGitignore))

        var steps = [
            "Write the Xcode project:  cd \(root.path) && xcodegen generate   (brew install xcodegen, once)",
            "Open it and run it on the phone:  open \(root.path)/\(target).xcodeproj",
        ]
        if request.team == nil {
            steps.append("No signing team was given: pick yours in Xcode under Signing & Capabilities, and write it into project.yml to keep it.")
        }
        steps += [
            "Edit while it reinstalls on every save:  ollin phone \(root.path)/\(sourceDir)/Sketch.swift",
            "Try it in a window on this Mac:  ollin \(root.path)/\(sourceDir)/Sketch.swift",
            "Hand it to somebody: README.md, under Giving it to somebody else.",
        ]

        return GeneratedProject(
            root: root,
            files: files.sorted { $0.path < $1.path },
            runCommand: "cd \(root.path) && xcodegen generate && open \(target).xcodeproj",
            nextSteps: steps
        )
    }

    // MARK: - The spec

    /// The framework products the app links: the core, whatever the wired
    /// capabilities bring, and whatever an example's own imports name, as a
    /// union so a library the catalog has never heard of is still linked.
    static func iOSLinkedModules(_ request: ProjectRequest) -> [String] {
        let known = request.resolvedCapabilities.compactMap(\.module)
        let fromExample = (request.example?.modules ?? []).filter { !known.contains($0) }
        return ["Ollin"] + (known + fromExample).sorted()
    }

    /// The spec `xcodegen generate` reads.
    ///
    /// The sources are one group, the sketch's folder, which is what makes a
    /// second `.swift` file dropped in there compile on the next generate.
    /// Everything in that folder that is not source is named first, on its
    /// own, and excluded from the group, so a folder of pictures lands flat
    /// in the bundle, where a name-and-extension lookup finds it. The order
    /// is load-bearing: named after the group, a folder entry adds nothing.
    ///
    /// A shader goes through a copy-files phase rather than the resources
    /// phase, because Xcode runs its build rules over the resources phase too
    /// and compiles a `.metal` there into a library, while the framework reads
    /// a shader's source at run time. A copy-files phase only copies.
    static func iOSProjectSpec(_ request: ProjectRequest, target: String,
                               files: [GeneratedFile]) -> String {
        let sourceDir = "Sources/\(target)"
        let resources = iOSResources(files, sourceDir: sourceDir)

        var sources = ""
        for resource in resources {
            sources += "      - path: \(yamlQuoted("\(sourceDir)/\(resource)"))\n"
            if resource.hasSuffix(".metal") {
                sources += "        buildPhase:\n          copyFiles:\n            destination: resources\n"
            } else {
                sources += "        buildPhase: resources\n"
            }
        }
        sources += "      - path: \(sourceDir)\n"
        if !resources.isEmpty {
            sources += "        excludes:\n"
            for resource in resources {
                sources += "          - \(yamlQuoted(resource))\n"
            }
        }

        var dependencies = ""
        for module in iOSLinkedModules(request) {
            dependencies += "      - package: Ollin\n        product: \(module)\n"
        }

        let team: String
        if let given = request.team, !given.isEmpty {
            team = "    DEVELOPMENT_TEAM: \(yamlQuoted(given))\n"
        } else {
            team = """
                # Your Apple Developer team, which signs the app onto a device. Xcode
                # asks for it under Signing & Capabilities, but what it writes there is
                # lost the next time the project is generated, so put it here:
                # DEVELOPMENT_TEAM: ABCDE12345

            """
        }

        return """
        # \(request.folderName): an Ollin sketch as an app for the phone and the tablet.
        #
        # Write the Xcode project:   xcodegen generate     (brew install xcodegen, once)
        # Open it:                   open \(target).xcodeproj, pick the phone, press Run
        #
        # Or from the terminal, onto a paired phone:
        #   xcodebuild -project \(target).xcodeproj -scheme \(target) \\
        #     -destination 'platform=iOS,id=<device id>' -allowProvisioningUpdates build
        #   xcrun devicectl device install app --device <device id> <path to \(request.folderName).app>
        #
        # The framework is reached by path, so this builds against the copy of
        # Ollin already on this machine. Point `packages` somewhere else to move
        # the project to another one.

        name: \(target)

        options:
          bundleIdPrefix: com.example
          deploymentTarget:
            iOS: "26.0"
          createIntermediateGroups: true

        settings:
          base:
        \(team)    CODE_SIGN_STYLE: Automatic
            SWIFT_VERSION: "6.0"
            MARKETING_VERSION: "1.0"
            CURRENT_PROJECT_VERSION: "1"
            GENERATE_INFOPLIST_FILE: NO

        packages:
          Ollin:
        \(request.framework.projectSpecEntry)

        targets:
          \(target):
            type: application
            platform: iOS
            sources:
        \(sources)    dependencies:
        \(dependencies)    settings:
              base:
                # Yours to change before you hand this to anybody. Two apps with
                # one identifier are one app as far as a phone is concerned.
                PRODUCT_BUNDLE_IDENTIFIER: com.example.\(target.lowercased())
                PRODUCT_NAME: \(yamlQuoted(request.folderName))
                INFOPLIST_FILE: Info.plist
                TARGETED_DEVICE_FAMILY: "1,2"   # iPhone and iPad
                ENABLE_USER_SCRIPT_SANDBOXING: YES

        """
    }

    /// What in the sketch's folder is carried rather than compiled: a loose
    /// file that is not Swift (a shader, a scene, an example's picture) by
    /// name, and an asset folder as a whole. Relative to the folder, sorted.
    static func iOSResources(_ files: [GeneratedFile], sourceDir: String) -> [String] {
        var resources: Set<String> = []
        for file in files where file.path.hasPrefix(sourceDir + "/") {
            let relative = String(file.path.dropFirst(sourceDir.count + 1))
            let parts = relative.split(separator: "/", maxSplits: 1)
            if parts.count > 1 {
                resources.insert(String(parts[0]))
            } else if !relative.hasSuffix(".swift") {
                resources.insert(relative)
            }
        }
        return resources.sorted()
    }

    // MARK: - The property list

    /// The app's name tag. The display name is the project's, the piece takes
    /// the whole screen in either orientation, and the usage lines ride the
    /// wired capabilities, because an app that opens the camera or the
    /// microphone without one is killed rather than asked.
    static func iOSInfoPlist(_ request: ProjectRequest, target: String) -> String {
        var usageKeys = ""
        let capabilities = request.resolvedCapabilities.map(\.id)
        if capabilities.contains(Capability.vision.id) {
            usageKeys += """

            \t<!-- Shown the first time the app opens the camera. Without this
            \t     line the system kills the app instead of asking. -->
            \t<key>NSCameraUsageDescription</key>
            \t<string>\(xmlEscaped(request.folderName)) draws with what the camera sees.</string>
            """
        }
        if capabilities.contains(Capability.bluetooth.id) {
            usageKeys += """

            \t<!-- Shown the first time the app uses Bluetooth. Without this line
            \t     the system kills the app instead of asking. -->
            \t<key>NSBluetoothAlwaysUsageDescription</key>
            \t<string>\(xmlEscaped(request.folderName)) draws with what a Bluetooth sensor reads.</string>
            """
        }
        if capabilities.contains(Capability.audio.id) {
            usageKeys += """

            \t<!-- Shown the first time the app opens the microphone. Without this
            \t     line the system kills the app instead of asking. -->
            \t<key>NSMicrophoneUsageDescription</key>
            \t<string>\(xmlEscaped(request.folderName)) listens and draws what it hears.</string>
            """
        }

        return """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
        \t<key>CFBundleDevelopmentRegion</key>
        \t<string>en</string>
        \t<!-- The name under the icon. -->
        \t<key>CFBundleDisplayName</key>
        \t<string>\(xmlEscaped(request.folderName))</string>
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
        \t<!-- A piece takes the whole screen, so the tablet's split view is off and
        \t     the orientations below are all it has to answer for. -->
        \t<key>UIRequiresFullScreen</key>
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
        \t<key>UIRequiredDeviceCapabilities</key>
        \t<array>
        \t\t<string>arm64</string>
        \t\t<string>metal</string>
        \t</array>\(usageKeys)
        </dict>
        </plist>

        """
    }

    // MARK: - The host

    /// The app around the sketch: the reference app's shape. The system owns
    /// an app's launch, so the entry point lives here rather than on the
    /// sketch, and the sketch sits in a `SketchView`, the view the desk hosts
    /// use. `Bundle.module` is the app, because the sketch is compiled into it
    /// and the files beside the sketch are its resources.
    static func iOSHostSource(_ request: ProjectRequest, target: String) -> String {
        """
        import SwiftUI
        import Ollin

        // \(request.folderName): the app around the sketch.
        //
        // On the desk a sketch is its own program, and `Sketch.main()` opens the
        // window for it. An app cannot work that way: the system owns the launch,
        // so the app declares the entry point and puts the sketch inside a
        // `SketchView`, the same view the desk hosts use. Everything else is the
        // sketch, in Sketch.swift beside this file.

        extension Bundle {
            /// The sketch is compiled into the app itself, and the files beside it
            /// are the app's own resources, so the bundle the sketch asks for with
            /// `in: .module` is the app.
            static var module: Bundle { .main }
        }

        @main
        struct \(target)App: App {
            // `Scene` is spelled out, because the framework has a 3D scene of its
            // own and the bare name is then two types.
            var body: some SwiftUI.Scene {
                WindowGroup {
                    // To carry the clock, the seed, and every tuned parameter across
                    // a relaunch, hand the runner a checkpoint:
                    //   SketchView(\(target)(), onRunner: { runner in
                    //       runner.beginInstallation(Installation(checkpoint: .every(seconds: 30)))
                    //   })
                    SketchView(\(target)())
                        // The canvas takes the whole screen, edges included, because
                        // a piece has no chrome to leave room for.
                        .ignoresSafeArea()
                        .background(.black)
                        .statusBarHidden()
                        .persistentSystemOverlays(.hidden)
                }
            }
        }

        """
    }

    // MARK: - The README

    static func iOSReadme(_ request: ProjectRequest, target: String) -> String {
        let teamLine = request.team == nil
            ? "No signing team was given, so Xcode asks for yours the first time you press Run. What it writes is lost when the project is generated again, so put the team into `project.yml` under `DEVELOPMENT_TEAM` to keep it."
            : "The signing team in `project.yml` is the one given when the project was made. Change it there, not in Xcode, because the project is written again from that file."

        return """
        # \(request.folderName)

        \(request.template.summary)

        An Ollin sketch wrapped as an app for the phone and the tablet. The framework does the drawing exactly as it does on the desk: the same Metal renderer, the same `draw()` loop at the display's refresh rate, the same shaders compiled from source at launch. A finger is the pointer, so `mouseX`, `mouseY`, and `mouseIsPressed` read the touch, and a stylus or a screen that measures force fills `pressure`.

        ## Making the app

        The project is written by `xcodegen` from `project.yml`, so the `.xcodeproj` is never edited by hand and is not kept in git.

        ```sh
        brew install xcodegen        # once
        xcodegen generate
        open \(target).xcodeproj     # pick the phone in the toolbar, press Run
        ```

        \(teamLine)

        From the terminal, onto a paired phone (`xcrun devicectl list devices` names them):

        ```sh
        xcodebuild -project \(target).xcodeproj -scheme \(target) \\
            -destination 'platform=iOS,id=<device id>' -allowProvisioningUpdates build
        xcrun devicectl device install app --device <device id> <path to \(request.folderName).app>
        ```

        ## Working on it

        Rebuilding an app is a slow way to see a change. Two faster loops:

        ```sh
        ollin phone Sources/\(target)/Sketch.swift    # on the phone, installed again on every save
        ollin Sources/\(target)/Sketch.swift          # in a window on this Mac, reloaded on every save
        ```

        The first writes its own small app around the same sketch file and reinstalls it under ten seconds after each save, with the clock and the tuned parameters carried across. The second is the desk's live window, where the touch is the mouse. Either way the file you edit is the one this project builds.

        ## What comes along

        Files beside the sketch in `Sources/\(target)/` that are not Swift are carried into the app as resources: a `.metal` shader, pictures, sounds, a mesh. They are named in `project.yml`, so after dropping a new one in, run `xcodegen generate` again. Inside the app `Bundle.module` is the app itself, so `loadImage(resource: "photo", withExtension: "jpg", in: .module)` finds on the phone what it finds on the desk.

        A `.metal` file is carried as a file, never compiled by Xcode, because the framework reads a shader's source at run time. That is what its `copyFiles` entry in the spec does: the resources phase would compile it into a library the framework never reads.

        ## The simulator does not run it

        It builds for the simulator and stops on the first frame. The simulated GPU reports itself as an older family with neither MetalFX nor cube-array textures, and the renderer binds a cube array on every frame. Use a device: iOS 26, paired with this Mac and trusted, with Developer Mode on.

        ## Giving it to somebody else

        An app reaches another phone through TestFlight or the App Store, both of which take a paid Apple Developer account and an archive from Xcode (Product, Archive, then Distribute App). Before that, change `PRODUCT_BUNDLE_IDENTIFIER` in `project.yml` from `com.example.*` to something of yours: two apps with one identifier are one app as far as a phone is concerned.

        ## Where things go

        The sketch and everything it loads live in `Sources/\(target)/`, with `\(target)App.swift` beside it as the host that owns the entry point. `Info.plist` is the app's name tag and `project.yml` is the whole project: the three are self-contained, so they can be copied into any sketch folder of this shape to make an app of it too.
        """
    }

    /// The project file is written by the spec, and the build folders are
    /// Xcode's, so none of them are kept.
    static let iOSGitignore = """
    *.xcodeproj/
    DerivedData/
    .build/
    .swiftpm/
    xcuserdata/
    .DS_Store
    """

    // MARK: - Quoting

    static func yamlQuoted(_ text: String) -> String {
        "\"" + text.replacingOccurrences(of: "\\", with: "\\\\")
                   .replacingOccurrences(of: "\"", with: "\\\"") + "\""
    }

    static func xmlEscaped(_ text: String) -> String {
        text.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }
}
