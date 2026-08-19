import Foundation

/// The 3D choices, and which of them go together.
///
/// 3D is the one part of the framework where the pieces genuinely do not all
/// stack: a wireframe has no surface to light, a matcap paints the whole look
/// into an image so lights and shadows stop applying, and traced reflections
/// need an environment and a physically based finish before they do anything.
/// That map already exists in prose (`Docs/3D/Combining.md`); this is the same
/// map as data, so a generator can gray out what does not apply and say why
/// rather than leaving someone to find out by rendering.
///
/// A rule here should be traceable to a line in that page. If the two disagree,
/// the page is right and this is the bug.
public struct ThreeDOption: Sendable, Hashable, Identifiable {
    public enum Slot: String, Sendable, Hashable, CaseIterable {
        /// What is on screen. Exactly one.
        case geometry
        /// How its surface is finished. Exactly one.
        case finish
        /// Everything that can be added on top. Any number.
        case extra

        public var title: String {
            switch self {
            case .geometry: "Geometry"
            case .finish: "Finish"
            case .extra: "Extras"
            }
        }
    }

    public let id: String
    public let title: String
    public let slot: Slot
    public let summary: String
    /// Options this one needs before it does anything at all.
    public let requires: [String]
    /// Options this one cannot be combined with.
    public let conflicts: [String]
    /// Why it conflicts or what it needs, in one sentence, for the moment
    /// someone hovers a row that is grayed out.
    public let rule: String

    public init(id: String, title: String, slot: Slot, summary: String,
                requires: [String] = [], conflicts: [String] = [], rule: String = "") {
        self.id = id
        self.title = title
        self.slot = slot
        self.summary = summary
        self.requires = requires
        self.conflicts = conflicts
        self.rule = rule
    }
}

extension ThreeDOption {

    // MARK: Geometry

    public static let mesh = ThreeDOption(
        id: "mesh", title: "Solid mesh", slot: .geometry,
        summary: "The full-featured citizen: every finish, light, shadow, and reflection applies.",
        rule: "Solid meshes are the only geometry that takes the whole pipeline."
    )

    public static let wireframe = ThreeDOption(
        id: "wireframe", title: "Wireframe", slot: .geometry,
        summary: "Edges in the stroke color, outside lighting entirely.",
        rule: "A wireframe has no surface to shade, so it draws in the stroke color and takes no finish, no lighting, and no shadows."
    )

    public static let pointCloud = ThreeDOption(
        id: "point-cloud", title: "Point cloud", slot: .geometry,
        summary: "Camera-facing splats, each carrying its own color.",
        rule: "Points are unlit on purpose: each one carries its own color, and lighting them would fight the data they came from."
    )

    public static let field = ThreeDOption(
        id: "field", title: "Raymarched field", slot: .geometry,
        summary: "Merging, blobby shapes traced per pixel, which still take materials and shadows.",
        rule: "A field shades through the same lighting model as a mesh; the one finish it cannot take is a matcap."
    )

    // MARK: Finish

    public static let lit = ThreeDOption(
        id: "lit", title: "Lit material", slot: .finish,
        summary: "Lights plus the stylized material library.",
        conflicts: [wireframe.id, pointCloud.id],
        rule: "Needs a surface to light, so it applies to solid meshes and raymarched fields."
    )

    public static let physicallyBased = ThreeDOption(
        id: "pbr", title: "Physically based", slot: .finish,
        summary: "Metallic and roughness, the finish that responds correctly to an environment.",
        conflicts: [wireframe.id, pointCloud.id],
        rule: "Needs a surface, and shows its best with an environment to reflect."
    )

    public static let matcap = ThreeDOption(
        id: "matcap", title: "Matcap", slot: .finish,
        summary: "A whole look painted into one sphere image, with no lighting setup at all.",
        conflicts: [wireframe.id, pointCloud.id, field.id],
        rule: "A matcap replaces lighting for the mesh it wraps, so lights, shadows, and an environment stop applying to it, and a raymarched field cannot take one."
    )

    public static let unlit = ThreeDOption(
        id: "unlit", title: "None", slot: .finish,
        summary: "No surface finish: the geometry's own color is the whole look.",
        conflicts: [mesh.id, field.id],
        rule: "The finish a wireframe and a point cloud take, because neither has a surface to shade."
    )

    // MARK: On top

    public static let environment = ThreeDOption(
        id: "environment", title: "Environment", slot: .extra,
        summary: "A surrounding that lights the scene and comes with its own backdrop.",
        conflicts: [matcap.id, wireframe.id, pointCloud.id],
        rule: "Lights surfaces, so it does nothing for a wireframe, a point cloud, or a matcap'd mesh."
    )

    public static let shadows = ThreeDOption(
        id: "shadows", title: "Cast shadows", slot: .extra,
        summary: "Soft, contact-hardening shadows that ground everything.",
        conflicts: [matcap.id, wireframe.id, pointCloud.id],
        rule: "Wireframes, point clouds, and matcap'd meshes neither cast nor receive shadows."
    )

    public static let rayTraced = ThreeDOption(
        id: "ray-traced", title: "Ray-traced reflections", slot: .extra,
        summary: "Metals mirror the actual scene, off-screen parts included.",
        requires: [environment.id, physicallyBased.id],
        conflicts: [matcap.id, wireframe.id, pointCloud.id],
        rule: "Needs an environment to catch rays and a physically based finish to mirror with, and runs only on a ray-tracing GPU (it is a safe no-op elsewhere)."
    )

    public static let toneMap = ThreeDOption(
        id: "tone-map", title: "Filmic tone map", slot: .extra,
        summary: "Rolls bright highlights off instead of clipping them.",
        rule: "Applies to the whole frame, so it works with anything."
    )

    public static let fog = ThreeDOption(
        id: "fog", title: "Fog", slot: .extra,
        summary: "Distance haze, so depth reads without moving the camera.",
        rule: "Fogs surfaces to their own depth, so 2D drawing and the backdrop stay clear."
    )

    public static let all: [ThreeDOption] = [
        .mesh, .wireframe, .pointCloud, .field,
        .lit, .physicallyBased, .matcap, .unlit,
        .environment, .shadows, .rayTraced, .toneMap, .fog,
    ]

    public static func named(_ id: String) -> ThreeDOption? {
        all.first { $0.id == id }
    }

    public static func inSlot(_ slot: Slot) -> [ThreeDOption] {
        all.filter { $0.slot == slot }
    }
}

/// One 3D scene's worth of choices, and the rules that keep it coherent.
public struct ThreeDRecipe: Sendable, Hashable {
    public var geometry: ThreeDOption
    public var finish: ThreeDOption
    public var extras: Set<String>

    public init(geometry: ThreeDOption = .mesh,
                finish: ThreeDOption = .physicallyBased,
                extras: Set<String> = [ThreeDOption.environment.id, ThreeDOption.shadows.id]) {
        self.geometry = geometry
        self.finish = finish
        self.extras = extras
    }

    /// The stack from the realism recipe, which is what most people want first.
    public static let realistic = ThreeDRecipe(
        geometry: .mesh,
        finish: .physicallyBased,
        extras: [ThreeDOption.environment.id, ThreeDOption.shadows.id,
                 ThreeDOption.rayTraced.id, ThreeDOption.toneMap.id]
    )

    /// Everything currently chosen, geometry and finish included, as ids.
    public var chosen: Set<String> { extras.union([geometry.id, finish.id]) }

    /// Why `option` cannot be picked right now, or nil when it can.
    ///
    /// Two reasons only: something already chosen rules it out, or it needs
    /// something that is not chosen. Both answer with the rule that says so,
    /// since a grayed-out row with no reason is worse than no row.
    public func objection(to option: ThreeDOption) -> String? {
        // The choices are a hierarchy, not a flat set: what is on screen decides
        // what can finish it, and those two together decide what can go on top.
        // So geometry is never blocked (picking it settles everything under it),
        // which is the difference between a panel you can navigate and one that
        // refuses the first thing you click.
        switch option.slot {
        case .geometry:
            return nil
        case .finish:
            return clash(option, geometry) ?? unmet(option, picked: [geometry.id, option.id])
        case .extra:
            return clash(option, geometry)
                ?? clash(option, finish)
                ?? unmet(option, picked: chosen.union([option.id]))
        }
    }

    /// Which chosen option is blocking `option`, or nil when nothing is (or
    /// when what is missing is a requirement rather than a clash).
    ///
    /// The edge of the constraint graph, named. It lets a blocked choice carry
    /// its cause where it can be seen, instead of the reason living only in a
    /// tooltip on the thing that cannot be clicked.
    public func blocker(of option: ThreeDOption) -> ThreeDOption? {
        switch option.slot {
        case .geometry:
            return nil
        case .finish:
            return clash(option, geometry) == nil ? nil : geometry
        case .extra:
            if clash(option, geometry) != nil { return geometry }
            if clash(option, finish) != nil { return finish }
            return nil
        }
    }

    /// How many other options this one currently rules out. What a chip needs
    /// to report its own reach.
    public func blocks(_ option: ThreeDOption) -> Int {
        ThreeDOption.all.filter { blocker(of: $0)?.id == option.id }.count
    }

    /// What `option` needs before it can be chosen, for the same reason.
    public func missingRequirements(of option: ThreeDOption) -> [ThreeDOption] {
        option.requires.filter { !chosen.contains($0) }.compactMap(ThreeDOption.named)
    }

    private func clash(_ option: ThreeDOption, _ other: ThreeDOption) -> String? {
        if option.conflicts.contains(other.id) { return option.rule }
        if other.conflicts.contains(option.id) { return other.rule }
        return nil
    }

    private func unmet(_ option: ThreeDOption, picked: Set<String>) -> String? {
        let missing = option.requires.filter { !picked.contains($0) }
        guard !missing.isEmpty else { return nil }
        let names = missing.compactMap { ThreeDOption.named($0)?.title.lowercased() }
        return "Needs \(names.joined(separator: " and ")) first. \(option.rule)"
    }

    /// Everything wrong with the recipe as it stands, empty when it holds
    /// together.
    public var objections: [String] {
        ([geometry, finish] + extras.sorted().compactMap(ThreeDOption.named))
            .compactMap { objection(to: $0) }
    }

    /// Drop whatever the current geometry or finish rules out, so changing one
    /// choice leaves a recipe that still holds together rather than a quietly
    /// broken one.
    public mutating func settle() {
        if objection(to: finish) != nil {
            finish = ThreeDOption.inSlot(.finish).first { objection(to: $0) == nil } ?? .unlit
        }
        for id in extras.sorted() {
            guard let option = ThreeDOption.named(id) else { extras.remove(id); continue }
            if objection(to: option) != nil { extras.remove(id) }
        }
    }
}
