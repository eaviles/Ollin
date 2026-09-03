import Foundation
import OllinRuntime
import OllinUSBMux

// OllinTether: `ollin phone <Sketch.swift>`, the edit loop against a phone.
//
//   swift run OllinTether <path/to/Sketch.swift> [--device <name>] [--once] [--fresh]
//   ollin phone <path/to/Sketch.swift>
//
// A phone loads no code pushed from outside its app bundle, so the live host's
// dylib swap cannot run there. What a phone does allow is an app installed
// again, and that turns out to be fast: the framework builds once, then a
// save recompiles the sketch, relinks the app, re-signs it, and puts it on the
// phone in well under ten seconds. The app writes its state down every second
// (the clock, the seed, the parameters, every `@Saved` property) and reads it
// back at launch, so each reinstall carries on mid-motion rather than starting
// over. That is the whole trick. Everything else here is plumbing: a project
// written around the sketch file where it already is, the device found by
// name, the build's errors shown at the author's own line, and the phone's
// parameters reached from the Mac, over the cable when there is one.
@main
enum OllinTether {

    static let usage = """
    usage: ollin phone <path/to/Sketch.swift> [options]

      --device <name or id>   which paired phone or tablet (default: the first)
      --team <id>             the signing team (default: OLLIN_TEAM, then the
                              reference app's)
      --once                  build, install, launch, and stop watching
      --fresh                 start the sketch over instead of carrying its state
      --port <n>              the local port the parameters are proxied to over
                              the cable (default 9330)
      --devices               list the paired devices and stop
      --verbose               show every build line
    """

    static func main() {
        setvbuf(stdout, nil, _IONBF, 0)   // unbuffered: a piped log keeps every line
        let arguments = Array(CommandLine.arguments.dropFirst())
        if arguments.contains("--help") || arguments.contains("-h") { print(usage); exit(0) }
        if arguments.contains("--devices") {
            for device in Device.paired() { print("\(device.name)  \(device.transportLabel)  \(device.identifier)") }
            exit(0)
        }
        do {
            let options = try Options(arguments)
            let tether = try Tether(options)
            tether.run()
        } catch {
            fail("ollin phone: \(error)", code: 2)
        }
    }

    static func fail(_ message: String, code: Int32) -> Never {
        FileHandle.standardError.write(Data((message + "\n").utf8))
        exit(code)
    }
}

// MARK: - Options

struct Options {
    var sketchPath: String
    var deviceQuery: String?
    var team: String?
    var once = false
    var fresh = false
    var verbose = false
    var localPort: UInt16 = UInt16(PhoneProject.remotePort)

    enum OptionError: Error, CustomStringConvertible {
        case missingSketch, missingValue(String), notAFile(String), badPort(String)
        var description: String {
            switch self {
            case .missingSketch: return "no sketch given\n" + OllinTether.usage
            case .missingValue(let flag): return "\(flag) needs a value"
            case .notAFile(let path): return "file not found: \(path)"
            case .badPort(let text): return "not a port: \(text)"
            }
        }
    }

    init(_ arguments: [String]) throws {
        var path: String?
        var index = 0
        func value(for flag: String) throws -> String {
            index += 1
            guard index < arguments.count else { throw OptionError.missingValue(flag) }
            return arguments[index]
        }
        while index < arguments.count {
            let argument = arguments[index]
            switch argument {
            case "--device": deviceQuery = try value(for: argument)
            case "--team": team = try value(for: argument)
            case "--port":
                let text = try value(for: argument)
                guard let port = UInt16(text), port > 0 else { throw OptionError.badPort(text) }
                localPort = port
            case "--once": once = true
            case "--fresh": fresh = true
            case "--verbose": verbose = true
            default:
                if argument.hasPrefix("-") { break }   // a flag meant for the sketch; ignored here
                path = argument
            }
            index += 1
        }
        guard let path else { throw OptionError.missingSketch }
        let absolute = (path as NSString).isAbsolutePath
            ? path
            : (FileManager.default.currentDirectoryPath as NSString).appendingPathComponent(path)
        guard FileManager.default.fileExists(atPath: absolute) else { throw OptionError.notAFile(absolute) }
        sketchPath = URL(fileURLWithPath: absolute).resolvingSymlinksInPath().path
    }
}

// MARK: - The paired devices

struct Device {
    let identifier: String
    let udid: String?
    let name: String
    let transport: String
    let osVersion: String?

    var transportLabel: String {
        switch transport {
        case "wired": return "USB"
        case "localNetwork": return "Wi-Fi"
        case "unknown": return "not reachable right now"
        default: return transport
        }
    }

    /// Every physical device paired with this Mac, as `devicectl` lists them.
    static func paired() -> [Device] {
        let file = FileManager.default.temporaryDirectory
            .appendingPathComponent("ollin-phone-devices-\(getpid()).json")
        defer { try? FileManager.default.removeItem(at: file) }
        let result = Shell.run(["xcrun", "devicectl", "list", "devices", "--json-output", file.path])
        guard result.status == 0,
              let data = try? Data(contentsOf: file),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let top = json["result"] as? [String: Any],
              let devices = top["devices"] as? [[String: Any]] else { return [] }
        return devices.compactMap { entry in
            let hardware = entry["hardwareProperties"] as? [String: Any] ?? [:]
            let properties = entry["deviceProperties"] as? [String: Any] ?? [:]
            let connection = entry["connectionProperties"] as? [String: Any] ?? [:]
            guard hardware["reality"] as? String == "physical",
                  connection["pairingState"] as? String == "paired",
                  let identifier = entry["identifier"] as? String else { return nil }
            return Device(identifier: identifier,
                          udid: hardware["udid"] as? String,
                          name: properties["name"] as? String ?? identifier,
                          transport: connection["transportType"] as? String ?? "unknown",
                          osVersion: properties["osVersionNumber"] as? String)
        }
    }

    /// The device a query names, or the first one when there is no query.
    static func pick(_ query: String?) throws -> Device {
        let devices = paired()
        guard !devices.isEmpty else { throw DeviceError.nonePaired }
        guard let query else {
            if devices.count > 1 {
                print("ollin phone: \(devices.count) devices are paired; using \(devices[0].name) "
                      + "(pick another with --device)")
            }
            return devices[0]
        }
        let needle = query.lowercased()
        if let match = devices.first(where: {
            $0.name.lowercased().contains(needle) || $0.identifier.lowercased().hasPrefix(needle)
                || ($0.udid?.lowercased().hasPrefix(needle) ?? false)
        }) { return match }
        throw DeviceError.noMatch(query, devices.map(\.name))
    }

    enum DeviceError: Error, CustomStringConvertible {
        case nonePaired, noMatch(String, [String])
        var description: String {
            switch self {
            case .nonePaired:
                return "no paired device; connect the phone, trust this Mac, and turn on Developer Mode"
            case .noMatch(let query, let names):
                return "no paired device matches \"\(query)\"; paired: \(names.joined(separator: ", "))"
            }
        }
    }
}

// MARK: - The loop

/// Unchecked because its mutable state is touched on `queue` alone once the
/// watch starts; the first pass runs before the watcher exists.
final class Tether: @unchecked Sendable {
    private let options: Options
    private let device: Device
    private let team: String
    private let frameworkPath: String
    private let projectFolder: URL
    private let derivedData: URL
    private let sketchFolder: String

    /// Builds run one at a time on this queue; a save during a build sets
    /// `dirty` and one more build follows, so the last save always wins.
    private let queue = DispatchQueue(label: "dev.ollin.phone")
    private var building = false
    private var dirty = false
    private var watcher: FileWatcher?
    private var proxy: USBProxy?
    private var announcedURL = false

    init(_ options: Options) throws {
        self.options = options
        device = try Device.pick(options.deviceQuery)
        frameworkPath = try Self.findFramework()
        team = try Self.findTeam(options.team, frameworkPath: frameworkPath)
        sketchFolder = (options.sketchPath as NSString).deletingLastPathComponent
        let caches = try FileManager.default.url(for: .cachesDirectory, in: .userDomainMask,
                                                 appropriateFor: nil, create: true)
        let root = caches.appendingPathComponent("Ollin/Phone", isDirectory: true)
        let plan = try PhoneProject.plan(sketchPath: options.sketchPath, frameworkPath: frameworkPath, team: team)
        projectFolder = root.appendingPathComponent(plan.typeName, isDirectory: true)
        // One derived-data folder for every sketch, so the framework compiles
        // for the phone once rather than once per sketch.
        derivedData = root.appendingPathComponent("DerivedData", isDirectory: true)
    }

    func run() {
        print("ollin phone: \(options.sketchPath)")
        print("  phone     \(device.name)" + (device.osVersion.map { ", iOS \($0)" } ?? "")
              + ", \(device.transportLabel)")
        print("  project   \(projectFolder.path)")
        let ok = cycle(first: true)
        if options.once {
            if ok { Thread.sleep(forTimeInterval: 2) }   // long enough for the surface to open
            exit(ok ? 0 : 1)
        }
        startWatching()
        print("watching \(sketchFolder) (^C stops; the app stays on the phone)")
        dispatchMain()
    }

    // MARK: One pass

    /// Plan, write, generate, build, install, launch. Returns whether the
    /// sketch reached the phone.
    @discardableResult
    private func cycle(first: Bool) -> Bool {
        let plan: PhoneProject
        do {
            plan = try PhoneProject.plan(sketchPath: options.sketchPath, frameworkPath: frameworkPath, team: team)
            try plan.write(to: projectFolder)
        } catch {
            print("  \(error)")
            return false
        }
        if first {
            if !plan.untried.isEmpty {
                print("  note      \(plan.untried.joined(separator: ", ")) untried on a phone; "
                      + "if the build fails, start there")
            }
            if !plan.assets.isEmpty {
                print("  assets    \(plan.assets.count) file(s) beside the sketch ride along")
            }
        }

        // The project. xcodegen is quick, and running it every time is what
        // lets a file dropped beside the sketch join the app on the next save.
        let generated = Shell.run(["xcodegen", "generate", "--quiet"], directory: projectFolder.path)
        guard generated.status == 0 else {
            if generated.output.contains("No such file") || generated.output.contains("not found") {
                print("  xcodegen is not installed: brew install xcodegen")
            } else {
                print("  xcodegen: \(generated.output.trimmingCharacters(in: .whitespacesAndNewlines))")
            }
            return false
        }

        // The build. The sketch is referenced by its own path, so a diagnostic
        // names the file the author has open.
        let buildStart = Date()
        let build = Shell.run([
            "xcodebuild",
            "-project", projectFolder.appendingPathComponent("\(PhoneProject.targetName).xcodeproj").path,
            "-scheme", PhoneProject.targetName,
            // Generic, not the phone by id: the build then never waits on the
            // phone being awake and on the network, only the install does.
            "-destination", "generic/platform=iOS",
            "-allowProvisioningUpdates",
            "-derivedDataPath", derivedData.path,
            "-quiet", "build",
        ])
        if options.verbose { print(build.output) }
        guard build.status == 0 else {
            print("  build     failed after \(Self.seconds(since: buildStart))")
            // The compiler saw the sketch through the project's link; the
            // author is looking at the real file, so say that path.
            let linked = projectFolder.appendingPathComponent(PhoneProject.sketchLink).path + "/"
            Self.printDiagnostics(build.output.replacingOccurrences(of: linked, with: sketchFolder + "/"))
            return false
        }
        print("  build     \(Self.seconds(since: buildStart))")

        // Onto the phone. Installing over a running copy replaces it, and the
        // state it wrote a second ago is what the next launch reads.
        let app = derivedData.appendingPathComponent("Build/Products/Debug-iphoneos/\(PhoneProject.targetName).app").path
        let installStart = Date()
        let install = Shell.run(["xcrun", "devicectl", "device", "install", "app",
                                 "--device", device.identifier, app])
        guard install.status == 0 else {
            print("  install   failed after \(Self.seconds(since: installStart))")
            if install.output.contains("usage assertion") || install.output.contains("not connected") {
                // devicectl's words for a phone that is paired but not here:
                // asleep, off this network, or unplugged.
                print("  the phone is not reachable: wake it on this network, or plug in the cable, then save again")
            } else {
                print(Self.lastLines(install.output, 6))
            }
            return false
        }
        print("  install   \(Self.seconds(since: installStart))")

        var launchArguments = ["xcrun", "devicectl", "device", "process", "launch", "--terminate-existing",
                               "--device", device.identifier, PhoneProject.bundleIdentifier]
        if first, options.fresh { launchArguments.append("--fresh") }
        let launch = Shell.run(launchArguments)
        if launch.status == 0 {
            print("  launch    \(first ? (options.fresh ? "fresh start" : "ok") : "reloaded, clock carried")")
        } else if launch.output.contains("unlock") {
            print("  launch    the phone is locked; unlock it and tap \(plan.typeName), or save again")
        } else {
            print("  launch    failed")
            print(Self.lastLines(launch.output, 6))
            return false
        }
        if !announcedURL {
            announcedURL = true
            announceParameters(for: plan)
        }
        return true
    }

    // MARK: The parameters on the Mac

    /// Where the phone's parameters are. Over the cable the surface is proxied
    /// to a local port, which needs no network at all; otherwise the phone's
    /// own name on the local network is the address.
    private func announceParameters(for plan: PhoneProject) {
        var urls: [String] = []
        if let udid = device.udid,
           let usb = try? USBMux.listDevices(), usb.contains(where: { $0.serialNumber == udid }) {
            do {
                proxy = try USBProxy(localPort: options.localPort, phonePort: UInt16(PhoneProject.remotePort))
                urls.append("http://localhost:\(options.localPort)")
            } catch {
                print("  proxy     could not listen on port \(options.localPort): \(error)")
            }
        }
        urls.append("http://\(Self.localHostname(for: device.name)):\(PhoneProject.remotePort)")
        print("  parameters  " + urls.joined(separator: "  or  "))
        // Opened once the app has had a moment to bind its port.
        if let url = urls.first {
            DispatchQueue.global().asyncAfter(deadline: .now() + 1.5) {
                _ = Shell.run(["open", url])
            }
        }
    }

    /// The Bonjour name a phone called "Edgardo’s iPhone" answers to on the
    /// local network: the letters and digits kept, everything else a hyphen.
    static func localHostname(for name: String) -> String {
        var out = ""
        var pendingHyphen = false
        for scalar in name.unicodeScalars {
            if scalar.properties.isAlphabetic || scalar.properties.numericType != nil {
                if pendingHyphen, !out.isEmpty { out.append("-") }
                pendingHyphen = false
                out.unicodeScalars.append(scalar)
            } else if scalar == "'" || scalar == "\u{2019}" {
                continue   // “Edgardo’s” keeps its s
            } else {
                pendingHyphen = true
            }
        }
        return out + ".local"
    }

    // MARK: Watching

    private func startWatching() {
        let sketchPath = options.sketchPath
        let watcher = FileWatcher(paths: [sketchFolder]) { [weak self] changed in
            guard let self else { return }
            let relevant = changed.contains { path in
                let standard = URL(fileURLWithPath: path).resolvingSymlinksInPath().path
                if standard == sketchPath { return true }
                let ext = (standard as NSString).pathExtension.lowercased()
                return (standard as NSString).deletingLastPathComponent == self.sketchFolder
                    && PhoneProject.assetExtensions.contains(ext)
            }
            guard relevant else { return }
            self.scheduleBuild()
        }
        watcher.start()
        self.watcher = watcher
    }

    private func scheduleBuild() {
        queue.async {
            if self.building { self.dirty = true; return }
            self.building = true
            repeat {
                self.dirty = false
                print("saved")
                self.cycle(first: false)
            } while self.dirty
            self.building = false
        }
    }

    // MARK: Finding things

    /// The checkout this command was built from, found by walking up from the
    /// binary, the way the other commands find it.
    static func findFramework() throws -> String {
        var url = URL(fileURLWithPath: CommandLine.arguments[0]).resolvingSymlinksInPath()
        if !url.path.hasPrefix("/") {
            url = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent(url.path)
        }
        while url.path != "/" {
            url.deleteLastPathComponent()
            let manifest = url.appendingPathComponent("Package.swift").path
            let core = url.appendingPathComponent("Sources/Ollin").path
            if FileManager.default.fileExists(atPath: manifest), FileManager.default.fileExists(atPath: core) {
                return url.path
            }
        }
        throw SetupError.noFramework
    }

    /// The signing team: the flag, then `OLLIN_TEAM`, then the one the
    /// reference phone app in the checkout is signed with.
    static func findTeam(_ given: String?, frameworkPath: String) throws -> String {
        if let given, !given.isEmpty { return given }
        if let env = ProcessInfo.processInfo.environment["OLLIN_TEAM"], !env.isEmpty { return env }
        let reference = (frameworkPath as NSString).appendingPathComponent("Apps/OllinSketchApp/project.yml")
        if let spec = try? String(contentsOfFile: reference, encoding: .utf8) {
            for line in spec.split(separator: "\n") where line.contains("DEVELOPMENT_TEAM:") {
                let value = line.split(separator: ":", maxSplits: 1).last.map(String.init) ?? ""
                let team = value.trimmingCharacters(in: CharacterSet(charactersIn: " \"'"))
                if !team.isEmpty { return team }
            }
        }
        throw SetupError.noTeam
    }

    enum SetupError: Error, CustomStringConvertible {
        case noFramework, noTeam
        var description: String {
            switch self {
            case .noFramework: return "could not find the Ollin checkout from this binary"
            case .noTeam: return "no signing team: pass --team <id> or set OLLIN_TEAM"
            }
        }
    }

    // MARK: Output

    static func seconds(since start: Date) -> String {
        String(format: "%.1f s", Date().timeIntervalSince(start))
    }

    /// The build's errors, once each, at the author's own file and line; the
    /// tail of the log when it failed without one.
    static func printDiagnostics(_ output: String) {
        var seen = Set<String>()
        var shown = 0
        for line in output.split(separator: "\n") where line.contains("error:") {
            let text = String(line).trimmingCharacters(in: .whitespaces)
            if seen.insert(text).inserted {
                print("  " + text)
                shown += 1
            }
        }
        if shown == 0 { print(lastLines(output, 15)) }
    }

    static func lastLines(_ output: String, _ count: Int) -> String {
        output.split(separator: "\n").suffix(count).map { "  " + $0 }.joined(separator: "\n")
    }
}

// MARK: - Running a command

enum Shell {
    struct Result {
        let status: Int32
        let output: String
    }

    /// Run a command and wait, its output (both streams) collected. The pipe is
    /// drained before the wait, or a chatty build fills it and both sides stall.
    static func run(_ command: [String], directory: String? = nil) -> Result {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = command
        if let directory { process.currentDirectoryURL = URL(fileURLWithPath: directory) }
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        do {
            try process.run()
        } catch {
            return Result(status: 127, output: "\(command[0]): \(error)")
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return Result(status: process.terminationStatus, output: String(decoding: data, as: UTF8.self))
    }
}

// MARK: - The cable

/// A local port forwarded to a port on the phone through usbmuxd, so the
/// phone's parameter surface opens at `localhost` with no network between the
/// two. Plain bytes both ways, one pair of threads per connection; the
/// WebSocket the surface upgrades to rides through untouched.
final class USBProxy {
    private let listener: Int32
    private let phonePort: UInt16

    enum ProxyError: Error, CustomStringConvertible {
        case socket(String)
        var description: String {
            if case .socket(let why) = self { return why }
            return "proxy"
        }
    }

    init(localPort: UInt16, phonePort: UInt16) throws {
        self.phonePort = phonePort
        listener = socket(AF_INET, SOCK_STREAM, 0)
        guard listener >= 0 else { throw ProxyError.socket("socket: \(String(cString: strerror(errno)))") }
        var one: Int32 = 1
        setsockopt(listener, SOL_SOCKET, SO_REUSEADDR, &one, socklen_t(MemoryLayout<Int32>.size))
        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = localPort.bigEndian
        address.sin_addr.s_addr = inet_addr("127.0.0.1")
        let bound = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(listener, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) }
        }
        guard bound == 0, listen(listener, 8) == 0 else {
            let why = String(cString: strerror(errno))
            close(listener)
            throw ProxyError.socket(why)
        }
        let thread = Thread { [self] in acceptLoop() }
        thread.name = "dev.ollin.phone.proxy"
        thread.start()
    }

    private func acceptLoop() {
        while true {
            let client = accept(listener, nil, nil)
            guard client >= 0 else { return }
            guard let phone = try? USBMux.connect(toPort: phonePort) else {
                close(client)
                continue
            }
            Self.pump(from: client, to: phone)
            Self.pump(from: phone, to: client)
        }
    }

    /// Copy bytes one way until either side closes, then close both.
    private static func pump(from source: Int32, to sink: Int32) {
        let thread = Thread {
            var buffer = [UInt8](repeating: 0, count: 64 * 1024)
            while true {
                let count = read(source, &buffer, buffer.count)
                guard count > 0 else { break }
                var written = 0
                while written < count {
                    let n = write(sink, Array(buffer[written..<count]), count - written)
                    guard n > 0 else { return }
                    written += n
                }
            }
            shutdown(sink, SHUT_WR)
            shutdown(source, SHUT_RD)
        }
        thread.start()
    }
}
