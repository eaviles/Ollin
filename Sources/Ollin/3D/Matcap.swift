import Foundation

/// A *matcap* (material capture): a sphere texture that bakes a whole surface look —
/// the lighting included — into one image, sampled by the **view-space normal**. Drop
/// one in with `matcap(_:)` and it shades a mesh independent of the scene lights, so a
/// clay, chrome, or toon finish comes for almost free (one texture lookup per pixel,
/// no light evaluation):
///
/// ```swift
/// matcap(.chrome)
/// drawSphere(radius: 200)
/// ```
///
/// Reach for a built-in by name, bring your own matcap PNG, or generate one:
///
/// ```swift
/// matcap(.clay)                                   // a bundled built-in
/// matcap(loadImage("my-matcap.png"))              // any matcap image
/// matcap(Matcap.shaded(baseColor: .teal,          // rolled-your-own, no asset
///                      metallic: true))
/// ```
///
/// Because the look is painted into the texture, a matcap **doesn't** respond to
/// `directionalLight`/`material(_:)`/`castShadows()` — it's a self-contained finish, a
/// separate axis from the lit material model. The surface is tinted by the current
/// `fill` (`.white` shows the matcap as-is; other fills recolor it). `noMatcap()`
/// returns to the lit path.
///
/// The built-ins are real baked studio captures (CC0, derived from the Blender
/// community's matcaps — see `THIRD-PARTY-NOTICES.md`); `shaded(...)` renders an
/// analytic sphere on the CPU for a quick custom or recolored matcap with no asset.
/// Like `Material` and `LightingPreset`, it's a plain value, so the built-in set is
/// also the extension surface — pass a built-in, wrap any `Image`, or generate one.
public struct Matcap {

    /// The sphere texture this matcap samples (by the view-space normal). Tinted by the
    /// current `fill` at draw time.
    public let image: Image

    /// Wrap any matcap sphere image as a `Matcap` — e.g. to keep a loaded PNG in a
    /// typed collection. (`matcap(_:)` also takes a bare `Image` directly.)
    public init(_ image: Image) { self.image = image }

    // MARK: - Built-in matcaps (CC0, bundled)
    //
    // Loaded once from the bundled PNGs and shared. `@MainActor` because `Image` is a
    // reference type that isn't `Sendable` (it caches a GPU texture), and all drawing
    // is main-actor — the matcap is only ever read on the main actor, so this is the
    // sound home for the shared constants (matching where `matcap(_:)` is called).

    // Metals
    /// Bright polished chrome.
    @MainActor public static let chrome = Matcap(bundled("chrome"))
    /// Dark bronze metal.
    @MainActor public static let bronze = Matcap(bundled("bronze"))
    /// Glossy candy car paint (a clear-coat metallic red).
    @MainActor public static let carpaint = Matcap(bundled("carpaint"))
    /// Machined hard-surface metal, neutral grey.
    @MainActor public static let hardSurfaceGrey = Matcap(bundled("hardSurfaceGrey"))
    /// Machined hard-surface metal, red.
    @MainActor public static let hardSurfaceRed = Matcap(bundled("hardSurfaceRed"))

    // Clays / earths
    /// Neutral studio clay — matte, the everyday sculpt look.
    @MainActor public static let clay = Matcap(bundled("clay"))
    /// Warm earthy terracotta clay.
    @MainActor public static let terracotta = Matcap(bundled("terracotta"))
    /// Muted sage-green clay.
    @MainActor public static let sage = Matcap(bundled("sage"))
    /// Warm beige clay.
    @MainActor public static let clayWarm = Matcap(bundled("clayWarm"))

    // Whites / ceramics
    /// Pearlescent off-white.
    @MainActor public static let pearl = Matcap(bundled("pearl"))
    /// Bright glazed ceramic.
    @MainActor public static let ceramic = Matcap(bundled("ceramic"))
    /// Darker, cooler ceramic.
    @MainActor public static let ceramicDark = Matcap(bundled("ceramicDark"))

    // Translucent
    /// Red translucent wax.
    @MainActor public static let wax = Matcap(bundled("wax"))
    /// Amber translucent resin.
    @MainActor public static let resin = Matcap(bundled("resin"))

    // Neutral studio greys
    /// A clean neutral-grey reference sphere — the plain "show me the form" finish.
    @MainActor public static let studio = Matcap(bundled("studio"))
    /// Bright, evenly-lit neutral grey.
    @MainActor public static let basicBright = Matcap(bundled("basicBright"))
    /// Dim neutral grey.
    @MainActor public static let basicDark = Matcap(bundled("basicDark"))
    /// Side-lit neutral grey (strong directional modeling).
    @MainActor public static let basicSide = Matcap(bundled("basicSide"))

    // Toon / cel
    /// Light cel shading — hard bands, the cartoon look.
    @MainActor public static let toon = Matcap(bundled("toon"))
    /// Dark cel shading with a cool rim.
    @MainActor public static let toonDark = Matcap(bundled("toonDark"))

    // Diagnostic (not material looks — useful for inspecting 3D geometry)
    /// Surface-normal visualization: orientation shown as RGB (a debugging matcap).
    @MainActor public static let checkNormal = Matcap(bundled("checkNormal"))
    /// A smooth tonal gradient, for reading surface curvature.
    @MainActor public static let checkGradient = Matcap(bundled("checkGradient"))
    /// Horizontal reflection stripes, for spotting surface ripples.
    @MainActor public static let checkReflectionHorizontal = Matcap(bundled("checkReflectionHorizontal"))
    /// Vertical reflection stripes, for spotting surface ripples.
    @MainActor public static let checkReflectionVertical = Matcap(bundled("checkReflectionVertical"))
    /// A dark sphere with a bright silhouette rim — checks edges against a dark scene.
    @MainActor public static let checkRimDark = Matcap(bundled("checkRimDark"))
    /// A light sphere with a dark silhouette rim — checks edges against a light scene.
    @MainActor public static let checkRimLight = Matcap(bundled("checkRimLight"))

    /// Load a bundled matcap PNG by name from the framework bundle, falling back to a
    /// generated neutral sphere if it can't be found (so a built-in is never absent).
    @MainActor private static func bundled(_ name: String) -> Image {
        if let url = Bundle.module.url(forResource: name, withExtension: "png", subdirectory: "Matcaps"),
           let image = Image(contentsOf: url) {
            return image
        }
        return shaded(baseColor: Color(white: 0.7)).image
    }

    // MARK: - Generator

    /// Render a matcap as an analytic shaded sphere on the CPU — a quick custom or
    /// recolored look with no bundled asset. The sphere is lit by a baked key + fill
    /// with a Blinn-Phong highlight and a Fresnel rim; `metallic` tints the highlight
    /// by the base color (a metal) instead of leaving it white (a dielectric), and
    /// `roughness` (`0` mirror-sharp … `1` broad/matte) sets the highlight tightness.
    ///
    /// ```swift
    /// matcap(Matcap.shaded(baseColor: Color(hex: 0x4488FF)))            // a blue plastic
    /// matcap(Matcap.shaded(baseColor: .gold, metallic: true, roughness: 0.1))
    /// ```
    public static func shaded(size: Int = 256,
                              baseColor: Color,
                              metallic: Bool = false,
                              roughness: Double = 0.5,
                              ambient: Double = 0.12) -> Matcap {
        let n = max(8, size)
        let rough = min(1, max(0, roughness))
        let shininess = 2 + (1 - rough) * (1 - rough) * 220   // 2 (matte) … 222 (mirror)
        let specStrength = 0.04 + (1 - rough) * 0.96
        let amb = min(1, max(0, ambient))
        let base = (Color.srgbToLinear(baseColor.red),
                    Color.srgbToLinear(baseColor.green),
                    Color.srgbToLinear(baseColor.blue))

        func normalize(_ v: (Double, Double, Double)) -> (Double, Double, Double) {
            let len = (v.0 * v.0 + v.1 * v.1 + v.2 * v.2).squareRoot()
            return len > 0 ? (v.0 / len, v.1 / len, v.2 / len) : v
        }
        // Baked lights in view space: +x right, +y up, +z toward the camera.
        let key = normalize((-0.5, 0.55, 0.66))    // upper-left, front
        let fill = normalize((0.55, -0.25, 0.5))   // lower-right, front (dim)
        // Half vector for the key highlight (view dir is +z).
        let half = normalize((key.0, key.1, key.2 + 1))

        func encode(_ c: Double) -> UInt8 {
            UInt8(min(1, max(0, Color.linearToSrgb(min(1, max(0, c))))) * 255 + 0.5)
        }

        var bytes = [UInt8](repeating: 0, count: n * n * 4)
        for py in 0..<n {
            let w = (Double(py) + 0.5) / Double(n) * 2 - 1   // top row → +y
            for px in 0..<n {
                let u = (Double(px) + 0.5) / Double(n) * 2 - 1
                var nx = u, ny = -w
                let r2 = nx * nx + ny * ny
                let nz: Double
                if r2 <= 1 {
                    nz = (1 - r2).squareRoot()
                } else {                              // outside the disk: extend the rim
                    let len = r2.squareRoot(); nx /= len; ny /= len; nz = 0
                }
                let dKey = max(0, nx * key.0 + ny * key.1 + nz * key.2)
                let dFill = max(0, nx * fill.0 + ny * fill.1 + nz * fill.2) * 0.35
                let diffuse = dKey + dFill
                let spec = pow(max(0, nx * half.0 + ny * half.1 + nz * half.2), shininess) * specStrength
                let fres = pow(1 - max(0, nz), 4)

                let r, g, b: Double
                if metallic {
                    let lit = amb + diffuse * 0.25
                    r = base.0 * lit + base.0 * spec + base.0 * fres * 0.5
                    g = base.1 * lit + base.1 * spec + base.1 * fres * 0.5
                    b = base.2 * lit + base.2 * spec + base.2 * fres * 0.5
                } else {
                    let lit = amb + (1 - amb) * diffuse
                    r = base.0 * lit + spec + fres * 0.12
                    g = base.1 * lit + spec + fres * 0.12
                    b = base.2 * lit + spec + fres * 0.12
                }
                let i = (py * n + px) * 4
                bytes[i] = encode(r); bytes[i + 1] = encode(g)
                bytes[i + 2] = encode(b); bytes[i + 3] = 255
            }
        }
        let image = Image(width: n, height: n, premultipliedRGBA: bytes)
            ?? Image(width: 1, height: 1, color: baseColor)
        return Matcap(image)
    }
}
