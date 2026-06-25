import Foundation
import CoreGraphics
import ImageIO

/// An environment that lights a 3D scene through *image-based lighting* (IBL): every
/// surface picks up the color and brightness of its surroundings, metals reflect them,
/// and a rough surface gathers a soft average of them. It's how modern real-time 3D gets
/// its photographic look, and it's what makes the physically-based `Material.metal`
/// finishes read as metal rather than dark.
///
/// Set one with `environment(_:)` and draw a physically-based mesh into it:
///
/// ```swift
/// environment(.studio)            // a soft photo-studio light
/// fill(.white)
/// material(.polishedMetal)
/// drawSphere(radius: 1)           // a chrome ball reflecting the studio
/// ```
///
/// Pick a built-in CC0 environment (a daylight sky, a sunset, a studio, a night, …), load
/// your own equirectangular HDRI (`Environment.hdri(path:)`), or download one from a URL
/// (`Environment.hdri(downloadURL:)`). The built-ins ship at 1K for instant, offline use;
/// `highRes(_:)` fetches a sharper 2K/4K/8K version on demand (cached after the first run,
/// the 1K shown meanwhile). `intensity` scales the brightness; `rotated(_:)` spins it to
/// move the key light and the reflections. The environment lights the shaded materials in
/// addition to any `directionalLight`/`pointLight`/`spotLight`; with no lights at all, the
/// environment alone lights the scene.
public struct Environment: Equatable, Hashable, Sendable {

    /// A bundled / download resolution. (The lighting itself never needs more than 1K; a
    /// higher resolution only sharpens the *backdrop*.) Cases are spelled out because a
    /// Swift identifier can't begin with a digit (`.2K` won't compile).
    public enum Resolution: String, Sendable, CaseIterable {
        case oneK = "1k", twoK = "2k", fourK = "4k", eightK = "8k"
        var longEdge: Int { [.oneK: 1024, .twoK: 2048, .fourK: 4096, .eightK: 8192][self]! }
    }

    /// Where an environment's lighting comes from.
    public enum Source: Equatable, Hashable, Sendable {
        /// A bundled equirectangular HDRI resource (`.exr` / `.hdr`).
        case resource(name: String, bundleID: String?)
        /// An equirectangular HDRI at a local file URL.
        case url(URL)
        /// An equirectangular HDRI downloaded from a remote URL and cached. `fallbackResource`
        /// is a bundled resource shown instantly while the download runs (nil = none).
        case remote(url: URL, fallbackResource: String?)
        /// A procedural physically-based sky (no asset): `turbidity` haze, `sunElevation`
        /// in radians above the horizon, `groundAlbedo` reflectance.
        case sky(turbidity: Double, sunElevation: Double, groundAlbedo: Double)
    }

    /// Where the lighting comes from (a bundled / loaded / downloaded HDRI or a procedural sky).
    public var source: Source
    /// A brightness multiplier on the whole environment (`1` is the source as authored).
    public var intensity: Double
    /// Rotation about the vertical (Y) axis, in radians: spins the surroundings, moving
    /// the key light and the reflections without re-baking the image.
    public var rotation: Double
    /// Whether the environment also shows as the scene's backdrop (a skybox behind the
    /// geometry, matching the reflections), `true` by default. `lightingOnly()` turns it
    /// off so the surfaces are lit by the environment over your own `background(_:)`.
    public var showsBackground: Bool
    /// How softly the backdrop is focused, `0…1`, or `nil` (the default) for **auto**: a
    /// gentle soft focus at 1K easing to sharp at 4K/8K (the backdrop is one narrow slice
    /// of the environment magnified to fill the window, so a low-res one wants a touch of
    /// softening; it's reconstructed bicubically either way, so it's never blocky). It
    /// doesn't affect the lighting or the reflections, only the backdrop.
    public var backgroundBlur: Double?
    /// The Poly Haven slug a built-in came from, so `highRes(_:)` can fetch a sharper
    /// version; nil for a loaded file or a user URL.
    public var polyHavenSlug: String?
    /// The bundled resource name for a built-in (the 1K placeholder); nil for the
    /// download-on-demand built-ins, loaded files, and user URLs.
    public var bundledResource: String?

    public init(source: Source, intensity: Double = 1, rotation: Double = 0,
                showsBackground: Bool = true, backgroundBlur: Double? = nil,
                polyHavenSlug: String? = nil, bundledResource: String? = nil) {
        self.source = source
        self.intensity = max(0, intensity)
        self.rotation = rotation
        self.showsBackground = showsBackground
        self.backgroundBlur = backgroundBlur.map { min(1, max(0, $0)) }
        self.polyHavenSlug = polyHavenSlug
        self.bundledResource = bundledResource
    }

    // MARK: - Adjustments

    /// A copy with the brightness scaled.
    public func intensity(_ value: Double) -> Environment {
        var e = self; e.intensity = max(0, value); return e
    }

    /// A copy spun about the vertical axis by `radians`.
    public func rotated(_ radians: Double) -> Environment {
        var e = self; e.rotation = radians; return e
    }

    /// A copy that lights the scene but does *not* draw itself as the backdrop, so your
    /// own `background(_:)` shows behind the environment-lit objects.
    public func lightingOnly() -> Environment {
        var e = self; e.showsBackground = false; return e
    }

    /// A copy with the backdrop focus set explicitly (`0` sharp … `1` strongly defocused),
    /// overriding the auto default.
    public func backgroundBlur(_ amount: Double) -> Environment {
        var e = self; e.backgroundBlur = min(1, max(0, amount)); return e
    }

    /// A copy of a built-in at a higher resolution, downloaded from Poly Haven on first use
    /// and cached (the bundled 1K is shown meanwhile). Only the backdrop gets sharper; the
    /// lighting is the same. No-op for a loaded file or a user URL (they're already at their
    /// own resolution).
    public func highRes(_ resolution: Resolution) -> Environment {
        guard let slug = polyHavenSlug else { return self }
        var e = self
        if resolution == .oneK, let bundled = bundledResource {
            e.source = .resource(name: bundled, bundleID: nil)
        } else {
            e.source = .remote(url: Environment.polyHavenURL(slug: slug, resolution: resolution),
                               fallbackResource: bundledResource)
        }
        return e
    }

    // MARK: - Sources

    /// A bundled equirectangular HDRI (`.exr` or `.hdr`). Pass the caller's `bundle`
    /// explicitly (a default would resolve to Ollin's bundle, not yours).
    public static func hdri(resource name: String, in bundle: Bundle) -> Environment {
        Environment(source: .resource(name: name, bundleID: bundle.bundleIdentifier))
    }

    /// A local equirectangular HDRI (`.exr` or `.hdr`) at a file URL.
    public static func hdri(url: URL) -> Environment {
        Environment(source: .url(url))
    }

    /// A local equirectangular HDRI (`.exr` or `.hdr`) at a file path.
    public static func hdri(path: String) -> Environment {
        Environment(source: .url(URL(fileURLWithPath: path)))
    }

    /// An equirectangular HDRI (`.exr` or `.hdr`) downloaded from a remote URL on first use
    /// and cached (e.g. a Poly Haven asset). The scene is unlit until the download lands;
    /// pass a bundled `placeholder` to show one of the built-ins meanwhile.
    public static func hdri(downloadURL url: URL, placeholder: String? = nil) -> Environment {
        Environment(source: .remote(url: url, fallbackResource: placeholder))
    }

    /// An equirectangular HDRI downloaded from a URL string (the convenience form, so a
    /// sketch needn't import Foundation for `URL`).
    public static func hdri(downloadURL string: String, placeholder: String? = nil) -> Environment {
        Environment(source: .remote(url: URL(string: string) ?? URL(fileURLWithPath: "/"),
                                    fallbackResource: placeholder))
    }

    /// A procedural physically-based sky, generated with no asset: a clear-to-hazy daylight
    /// dome. `sunElevation` is the sun's height above the horizon in radians, `turbidity`
    /// the atmospheric haze, `groundAlbedo` the bounce from below.
    public static func sky(turbidity: Double = 3, sunElevation: Double = 0.4,
                           groundAlbedo: Double = 0.3) -> Environment {
        Environment(source: .sky(turbidity: turbidity, sunElevation: sunElevation,
                                 groundAlbedo: groundAlbedo))
    }

    /// The download URL for a Poly Haven HDRI slug at a resolution (PIZ EXR, which ImageIO
    /// decodes directly).
    static func polyHavenURL(slug: String, resolution: Resolution) -> URL {
        let r = resolution.rawValue
        return URL(string: "https://dl.polyhaven.org/file/ph-assets/HDRIs/exr/\(r)/\(slug)_\(r).exr")!
    }

    // MARK: - Built-ins (CC0)

    /// A built-in bundled at 1K (instant, offline). `name` is the bundled resource; `slug`
    /// is its Poly Haven origin, so `highRes(_:)` can fetch a sharper version.
    private static func bundled(_ name: String, _ slug: String) -> Environment {
        Environment(source: .resource(name: name, bundleID: nil),
                    polyHavenSlug: slug, bundledResource: name)
    }

    /// A built-in that downloads on first use (1K by default; not bundled, so no offline
    /// placeholder).
    private static func remote(_ slug: String) -> Environment {
        Environment(source: .remote(url: polyHavenURL(slug: slug, resolution: .oneK),
                                    fallbackResource: nil),
                    polyHavenSlug: slug)
    }

    // Bundled at 1K (provenance + credits in the resource LICENSE file).
    /// A soft, even photo-studio light.
    public static let studio = bundled("studio", "studio_small_01")
    /// An outdoor landing pad under a bright sky.
    public static let city = bundled("city", "portland_landing_pad")
    /// A walled courtyard with sky above.
    public static let courtyard = bundled("courtyard", "courtyard")
    /// Dappled light in a Japanese garden.
    public static let forest = bundled("forest", "ninomaru_teien")
    /// A warm hotel-room interior.
    public static let interior = bundled("interior", "hotel_room")
    /// A dark, moonless outdoor night.
    public static let night = bundled("night", "moonless_golf")
    /// A cool early-morning sunrise.
    public static let sunrise = bundled("sunrise", "spruit_sunrise")
    /// A warm Venice sunset over water.
    public static let sunset = bundled("sunset", "venice_sunset")

    // Download-on-demand at 1K (cached after first use), higher res via `highRes(_:)`.
    /// A clean, large neutral photo studio (soft, near-shadowless).
    public static let photoStudio = remote("brown_photostudio_02")
    /// A bright partly-cloudy midday sky with a strong sun.
    public static let day = remote("kloofendal_48d_partly_cloudy_puresky")
    /// A clear high-noon sun, crisp shadows.
    public static let noon = remote("qwantani_noon")
    /// A dramatic, colorful seaside twilight.
    public static let dusk = remote("the_sky_is_on_fire")
    /// Warm golden-hour sun over a hill.
    public static let goldenHour = remote("kloppenheim_06")
    /// An overcast, snowy winter park (soft, diffuse).
    public static let snow = remote("snowy_park_01")
    /// A warm city night with bridge and street lights.
    public static let cityNight = remote("golden_bay")
    /// A clear starry night, very low light.
    public static let starryNight = remote("dikhololo_night")
    /// A soft architectural interior hall.
    public static let hall = remote("st_fagans_interior")
    /// A bright clear autumn field.
    public static let field = remote("autumn_field")
    /// A skylit industrial warehouse (good for product looks).
    public static let warehouse = remote("empty_warehouse_01")
    /// A soft pink dawn.
    public static let dawn = remote("kiara_1_dawn")

    /// Every built-in paired with its name and whether it's bundled (offline) or downloads
    /// on demand, in a sensible order for browsing. Handy for a gallery that steps through them.
    public static let allBuiltins: [(name: String, environment: Environment)] = [
        ("studio", .studio), ("photoStudio", .photoStudio), ("interior", .interior),
        ("hall", .hall), ("warehouse", .warehouse), ("courtyard", .courtyard),
        ("city", .city), ("forest", .forest), ("field", .field),
        ("day", .day), ("noon", .noon), ("dawn", .dawn),
        ("sunrise", .sunrise), ("goldenHour", .goldenHour), ("sunset", .sunset),
        ("dusk", .dusk), ("snow", .snow), ("cityNight", .cityNight),
        ("night", .night), ("starryNight", .starryNight),
    ]

    /// The eight built-ins **bundled at 1K** (instant, offline, no download), the subset of
    /// `allBuiltins` that ships with the framework, in browse order.
    public static let bundledBuiltins: [(name: String, environment: Environment)] =
        allBuiltins.filter { $0.environment.bundledResource != nil }
}

// MARK: - Loading (CPU)

extension Environment {

    /// Resolve a `.resource` or local-file source to an equirectangular `CGImage` of
    /// linear-light HDR pixels, or `nil` for `.sky` / `.remote` (the renderer resolves those
    /// to a cached file or a fallback first) and on load failure.
    func loadEquirectImage() -> CGImage? {
        switch source {
        case .sky, .remote:
            return nil   // resolved to a cached `.url` or a `.resource` fallback by the renderer
        case .url(let url):
            return Environment.decodeHDR(at: url)
        case .resource(let name, let bundleID):
            let bundle = bundleID.flatMap { Bundle(identifier: $0) } ?? .module
            for ext in ["exr", "hdr"] {
                if let url = bundle.url(forResource: name, withExtension: ext, subdirectory: "Environments")
                    ?? bundle.url(forResource: name, withExtension: ext) {
                    if let img = Environment.decodeHDR(at: url) { return img }
                }
            }
            return nil
        }
    }

    static func decodeHDR(at url: URL) -> CGImage? {
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(src, 0, nil)
    }
}
