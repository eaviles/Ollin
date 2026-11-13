import Foundation
import os

/// What a sketch's target imports besides the framework: other targets of its
/// package, and targets of other packages, found from the manifests and put in
/// the order a build needs them.
///
/// A live compile reaches the framework and its libraries because the host
/// carries them. Anything else a target imports has to be built first, and the
/// host builds it itself: each dependency's Swift files compile against the
/// framework this process runs, into a library of its own that the sketch then
/// links (`SketchLoader.buildDependencies`). The package build is not asked.
/// Measured on a two-target project, `swift build --target` in the project's
/// own build folder took 37 s and 498 MB the first time, since it builds the
/// framework again, 1.4 s on every save to learn nothing had changed, and
/// waited whenever another build held the folder; and its module is compiled
/// against the project's framework, which need not be the one this process
/// runs. The host's own compile took 0.7 s for a small library, wrote nothing
/// into the project, and has one framework to agree with.
///
/// What that route cannot build, it refuses by name (`DependencyError`): a
/// target with sources in a C-family language, a system library, a binary, a
/// macro, a plugin.
extension SketchTarget {
    /// A target to build before the one that asked, with the modules its own
    /// compile imports.
    package struct Dependency: Sendable, Equatable {
        package let target: SketchTarget
        /// The module names of everything it depends on in turn, nearest
        /// last, each built before it.
        package let needs: [String]
    }

    /// Everything this target needs built, each entry after all it needs
    /// itself, so compiling down the list never meets a module not yet there.
    ///
    /// - Parameters:
    ///   - carried: Whether the host already holds a module of this name. The
    ///     framework and its libraries are, and are left out: the sketch
    ///     binds to the copies this process runs.
    ///   - workspace: Where the packages SwiftPM fetched for this target's
    ///     package are found.
    ///   - reading: Reads the manifest of the package at a folder.
    package func dependencyOrder(
        carried: @escaping (String) -> Bool,
        workspace: PackageWorkspace,
        reading: @escaping (String) throws(ManifestError) -> Manifest = { root throws(ManifestError) in
            try Manifest.read(root: root)
        }
    ) throws(DependencyError) -> [Dependency] {
        var walk = DependencyWalk(carried: carried, workspace: workspace, reading: reading)
        let own: Manifest
        do {
            own = try reading(packageRoot)
        } catch {
            throw .manifest(error)
        }
        try walk.visit(self, in: own)
        return walk.order
    }
}

/// The depth-first walk behind `dependencyOrder`. How deep a package graph
/// goes is the manifests' to say, so the targets still open are kept on a
/// list rather than on the call stack.
private struct DependencyWalk {
    let carried: (String) -> Bool
    let workspace: PackageWorkspace
    let reading: (String) throws(ManifestError) -> SketchTarget.Manifest

    var order: [SketchTarget.Dependency] = []
    /// What each finished target needs, by its key.
    private var settled: [String: [String]] = [:]
    /// The key of the target that claimed each module name.
    private var owners: [String: String] = [:]

    init(carried: @escaping (String) -> Bool, workspace: PackageWorkspace,
         reading: @escaping (String) throws(ManifestError) -> SketchTarget.Manifest) {
        self.carried = carried
        self.workspace = workspace
        self.reading = reading
    }

    /// A target being walked: what it depends on, how far through that list
    /// the walk is, and the modules it has gathered so far.
    private struct Open {
        let target: SketchTarget
        let key: String
        let children: [(SketchTarget, SketchTarget.Manifest)]
        var next = 0
        /// The modules gathered so far, nearest last, and the same names as
        /// a set, so a wide or deep graph is not searched once per module.
        private(set) var needs: [String] = []
        private var gathered: Set<String> = []

        init(target: SketchTarget, key: String, children: [(SketchTarget, SketchTarget.Manifest)]) {
            self.target = target
            self.key = key
            self.children = children
        }

        mutating func gather(_ modules: [String]) {
            for module in modules where gathered.insert(module).inserted { needs.append(module) }
        }
    }

    private func key(_ target: SketchTarget) -> String { target.packageRoot + "\u{0}" + target.name }

    private func open(_ target: SketchTarget,
                      in manifest: SketchTarget.Manifest) throws(DependencyError) -> Open {
        var children: [(SketchTarget, SketchTarget.Manifest)] = []
        for link in target.links where link.appliesHere {
            children += try targets(for: link, of: target, in: manifest)
        }
        return Open(target: target, key: key(target), children: children)
    }

    /// Walk everything `root` depends on, filling `order`.
    mutating func visit(_ root: SketchTarget, in manifest: SketchTarget.Manifest) throws(DependencyError) {
        var stack = [try open(root, in: manifest)]
        while let top = stack.last {
            guard top.next < top.children.count else {
                // Everything it needs is in the list, so it goes in next and
                // hands what it gathered to the target that asked for it.
                stack.removeLast()
                guard !stack.isEmpty else { break }
                settled[top.key] = top.needs
                order.append(.init(target: top.target, needs: top.needs))
                stack[stack.count - 1].gather(top.needs + [top.target.moduleName])
                continue
            }
            let (child, home) = top.children[top.next]
            stack[stack.count - 1].next += 1
            let childKey = key(child)
            if let known = settled[childKey] {
                stack[stack.count - 1].gather(known + [child.moduleName])
                continue
            }
            if stack.contains(where: { $0.key == childKey }) {
                throw .cycle(target: child.name, from: top.target.name)
            }
            if let claimed = owners[child.moduleName], claimed != childKey {
                throw .twoModules(named: child.moduleName)
            }
            owners[child.moduleName] = childKey
            let foreign = child.foreignSource()
            if foreign != nil || child.swiftSources().isEmpty {
                throw .notSwift(target: child.name, file: foreign)
            }
            stack.append(try open(child, in: home))
        }
    }

    /// The targets one dependency stands for, each with the manifest of the
    /// package it is in; none for a module the host carries.
    private func targets(
        for link: SketchTarget.Link, of target: SketchTarget, in manifest: SketchTarget.Manifest
    ) throws(DependencyError) -> [(SketchTarget, SketchTarget.Manifest)] {
        switch link.kind {
        case .target:
            return [(try local(link.name, of: target, in: manifest), manifest)]
        case .byName:
            if manifest.targets.contains(where: { $0.name == link.name })
                || manifest.otherTargets[link.name] != nil {
                return [(try local(link.name, of: target, in: manifest), manifest)]
            }
            if carried(link.name) { return [] }
            // The package the convention names first, then the others.
            let conventional = link.name.lowercased()
            let named = manifest.packages.filter { $0.identity == conventional }
                + manifest.packages.filter { $0.identity != conventional }
            for package in named {
                let home = try self.manifest(of: package)
                if home.products[link.name] != nil {
                    return try members(of: link.name, in: home)
                }
            }
            throw .unknown(name: link.name, from: target.name)
        case .product(let packageName):
            if carried(link.name) { return [] }
            if link.renamesModules { throw .renamed(product: link.name, from: target.name) }
            guard let package = manifest.packages.first(where: {
                $0.identity == packageName.lowercased()
            }) else {
                throw .unknown(name: "\(link.name) of \(packageName)", from: target.name)
            }
            let home = try self.manifest(of: package)
            guard home.products[link.name] != nil else {
                throw .unknown(name: "\(link.name) of \(packageName)", from: target.name)
            }
            return try members(of: link.name, in: home)
        }
    }

    private func local(_ name: String, of target: SketchTarget,
                       in manifest: SketchTarget.Manifest) throws(DependencyError) -> SketchTarget {
        if let found = manifest.targets.first(where: { $0.name == name }) { return found }
        if let kind = manifest.otherTargets[name] { throw .unbuildable(target: name, kind: kind) }
        throw .unknown(name: name, from: target.name)
    }

    /// The targets a product is made of.
    private func members(
        of product: String, in home: SketchTarget.Manifest
    ) throws(DependencyError) -> [(SketchTarget, SketchTarget.Manifest)] {
        var found: [(SketchTarget, SketchTarget.Manifest)] = []
        for name in home.products[product] ?? [] {
            if let target = home.targets.first(where: { $0.name == name }) {
                found.append((target, home))
            } else if let kind = home.otherTargets[name] {
                throw .unbuildable(target: name, kind: kind)
            }
        }
        return found
    }

    private func manifest(of package: SketchTarget.PackageReference) throws(DependencyError) -> SketchTarget.Manifest {
        let folder: String
        if let path = package.path {
            folder = path
        } else {
            folder = try workspace.folder(of: package.identity)
        }
        do {
            return try reading(folder)
        } catch {
            throw .manifest(error)
        }
    }
}

// MARK: - Where fetched packages are

/// The packages SwiftPM fetched for a root package, read from the record it
/// keeps in the package's build folder (`.build/workspace-state.json`): every
/// package of the resolved graph with the folder it was checked out to.
///
/// A package the record does not list has not been fetched yet, and a record
/// older than `Package.swift` may list the version an earlier manifest asked
/// for; `swift package resolve` settles both. That is the one place a live
/// compile asks SwiftPM to do work in the project's own build folder, so it
/// waits there behind a build that holds the folder. It runs once for a
/// manifest as it stands: the next compile finds the record, and this process
/// remembers the manifest it resolved, since a resolve that changes nothing
/// leaves the record's date where it was.
package struct PackageWorkspace: Sendable {
    /// The root package's folder.
    package let root: String
    /// Whether SwiftPM may be asked to fetch. Off for a read that must stay
    /// quick and quiet (deciding what to watch).
    package var mayResolve: Bool

    package init(root: String, mayResolve: Bool = true) {
        self.root = root
        self.mayResolve = mayResolve
    }

    private var record: String {
        ((root as NSString).appendingPathComponent(".build") as NSString)
            .appendingPathComponent("workspace-state.json")
    }

    private static func written(_ path: String) -> Date? {
        (try? FileManager.default.attributesOfItem(atPath: path))?[.modificationDate] as? Date
    }

    /// The date of each root's `Package.swift` when this process last
    /// resolved it.
    private static let resolved = OSAllocatedUnfairLock<[String: Date]>(initialState: [:])

    /// The folder holding the package's checkout.
    package func folder(of identity: String) throws(DependencyError) -> String {
        let manifest = Self.written((root as NSString).appendingPathComponent("Package.swift"))
        let settled = Self.resolved.withLock { $0[root] } == manifest
        if mayResolve, !settled {
            // The record is missing, or the manifest was saved after it.
            let recordDate = Self.written(record)
            if recordDate == nil || (manifest.map { $0 > recordDate! } ?? false) {
                try resolve(for: identity, manifest: manifest)
            }
        }
        if let found = recorded(identity) { return found }
        guard mayResolve else { throw .unresolved(package: identity, detail: "") }
        if Self.resolved.withLock({ $0[root] }) != manifest {
            try resolve(for: identity, manifest: manifest)
            if let found = recorded(identity) { return found }
        }
        throw .unresolved(package: identity, detail: "`swift package resolve` ran, and the package is "
            + "still not among the ones it fetched.")
    }

    private func resolve(for identity: String, manifest: Date?) throws(DependencyError) {
        let result = SketchLoader.run("/usr/bin/xcrun", ["swift", "package", "--package-path", root, "resolve"])
        guard result.status == 0 else {
            let log = result.stderr.isEmpty ? result.stdout : result.stderr
            throw .unresolved(package: identity, detail: log.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        Self.resolved.withLock { $0[root] = manifest }
    }

    /// The folder the record gives for a package, when the record lists it
    /// and a manifest is there.
    package func recorded(_ identity: String) -> String? {
        let build = (root as NSString).appendingPathComponent(".build")
        guard let data = FileManager.default.contents(atPath: record),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let object = json["object"] as? [String: Any],
              let entries = object["dependencies"] as? [[String: Any]] else { return nil }
        for entry in entries {
            guard let reference = entry["packageRef"] as? [String: Any],
                  reference["identity"] as? String == identity else { continue }
            let state = entry["state"] as? [String: Any]
            let subpath = entry["subpath"] as? String ?? identity
            let folder: String?
            switch state?["name"] as? String {
            case "sourceControlCheckout":
                folder = ((build as NSString).appendingPathComponent("checkouts") as NSString)
                    .appendingPathComponent(subpath)
            case "registryDownload":
                folder = ((build as NSString).appendingPathComponent("registry/downloads") as NSString)
                    .appendingPathComponent(subpath)
            case "edited":
                folder = state?["path"] as? String
                    ?? ((root as NSString).appendingPathComponent("Packages") as NSString)
                        .appendingPathComponent(subpath)
            case "fileSystem":
                folder = state?["path"] as? String ?? reference["location"] as? String
            default:
                folder = nil
            }
            guard let folder else { return nil }
            let manifest = (folder as NSString).appendingPathComponent("Package.swift")
            return FileManager.default.fileExists(atPath: manifest) ? SketchTarget.resolved(folder) : nil
        }
        return nil
    }
}

// MARK: - What the live route refuses

/// Why something a target depends on cannot be built for the live window,
/// each a sentence that names it.
package enum DependencyError: Error, CustomStringConvertible, Sendable, Equatable {
    /// The target holds sources in a C-family language (the first found), or
    /// no Swift source at all.
    case notSwift(target: String, file: String?)
    /// The target is a system library, a binary, a macro, or a plugin.
    case unbuildable(target: String, kind: String)
    /// The manifest names something that is no target of the package and no
    /// product of a package it depends on.
    case unknown(name: String, from: String)
    /// The product is declared with `moduleAliases:`.
    case renamed(product: String, from: String)
    /// A fetched package is not in the workspace and could not be fetched;
    /// SwiftPM's words when it had any.
    case unresolved(package: String, detail: String)
    /// Two targets of the graph would make modules of one name.
    case twoModules(named: String)
    /// A target depends on itself through others.
    case cycle(target: String, from: String)
    case manifest(ManifestError)

    package var description: String {
        switch self {
        case .notSwift(let target, let file):
            let what = file.map { "holds \(($0 as NSString).lastPathComponent), which is not Swift" }
                ?? "holds no Swift source"
            return "The target \(target) \(what). \(Self.limit)"
        case .unbuildable(let target, let kind):
            let what = ["system": "a system library", "binary": "a prebuilt binary",
                        "macro": "a macro", "plugin": "a plugin"][kind] ?? "a \(kind) target"
            return "The target \(target) is \(what). \(Self.limit)"
        case .unknown(let name, let from):
            return "The target \(from) depends on \(name) in Package.swift, and that is no target of "
                + "its package and no product of a package it depends on."
        case .renamed(let product, let from):
            return "The target \(from) renames the modules of \(product) (`moduleAliases:`), which a "
                + "live run does not carry. \(Self.limit)"
        case .unresolved(let package, let detail):
            return "The package \(package) has not been fetched into this project's build folder"
                + (detail.isEmpty ? "." : ":\n\(detail)")
        case .twoModules(let name):
            return "Two targets this sketch depends on would both be the module \(name)."
        case .cycle(let target, let from):
            return "The target \(from) depends on \(target), which depends back on it."
        case .manifest(let error):
            return error.description
        }
    }

    /// What every refusal of the route ends on.
    private static let limit = "A live run builds the Swift targets a sketch depends on and "
        + "nothing else, so this sketch runs through `swift run`."
}
