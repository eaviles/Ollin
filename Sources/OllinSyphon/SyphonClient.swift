import Foundation
import Metal
import Ollin
import CSyphon

/// A Syphon source currently published on the system — what
/// ``SyphonClient/availableServers()`` returns. Carries the displayable name and
/// host-app name, and the underlying description used to open a client.
public struct SyphonServerInfo {
    /// The source's human-readable name (may be empty or absent).
    public let name: String?
    /// The name of the app publishing the source (e.g. `"Ollin"`, or another app's name).
    public let appName: String?
    /// The raw Syphon server description, used to open a ``SyphonClient``.
    let description: [String: Any]

    init(description: [String: Any]) {
        self.description = description
        self.name = description[SyphonServerDescriptionNameKey] as? String
        self.appName = description[SyphonServerDescriptionAppNameKey] as? String
    }

    /// A friendly one-line label, e.g. `"Composition (SomeApp)"`.
    public var label: String {
        let n = (name?.isEmpty == false) ? name : nil
        switch (n, appName) {
        case let (n?, a?): return "\(n) (\(a))"
        case let (n?, nil): return n
        case let (nil, a?): return a
        default: return "Syphon source"
        }
    }
}

/// Receives live visuals from a **Syphon source**, meaning any Syphon-capable
/// app on the Mac or another Ollin sketch, as an `Image` you draw with
/// `drawImage`.
///
/// ```swift
/// final class Viewer: Sketch {
///     let feed = SyphonClient()                  // first available source
///     override func draw() {
///         background(.black)
///         if let frame = feed.frame {
///             drawImage(frame, 0, 0, width, height)
///         }
///     }
/// }
/// ```
///
/// `frame` is a texture-backed `Image` that wraps the source's live GPU
/// texture directly (no copy). It connects on the system's default Metal device,
/// which matches the sketch's renderer on a single-GPU Mac.
@MainActor
public final class SyphonClient {

    private let device: MTLDevice?
    private var client: SyphonMetalClient?

    /// The connected source's name, if any.
    public private(set) var serverName: String?
    /// The connected source's host-app name, if any.
    public private(set) var appName: String?

    /// Connect to the first available Syphon source on the system.
    public convenience init() {
        self.init(named: nil, appName: nil)
    }

    /// Connect to a source matching `name` and/or `appName` (pass `nil` to leave
    /// either unspecified; both `nil` takes the first available source).
    public init(named name: String? = nil, appName: String? = nil) {
        device = MTLCreateSystemDefaultDevice()
        open(named: name, appName: appName)
    }

    /// Connect to a specific source discovered via ``availableServers()``.
    public init(source: SyphonServerInfo) {
        device = MTLCreateSystemDefaultDevice()
        open(to: source.description)
    }

    /// Whether the client has a live connection to a source. Once `false`, no
    /// further frames will arrive (the source went away); call
    /// ``connect(named:appName:)``.
    public var isActive: Bool { client?.isValid ?? false }

    /// Whether a new frame has arrived since the last read of ``frame``.
    public var hasNewFrame: Bool { client?.hasNewFrame ?? false }

    /// The latest frame as a texture-backed `Image`, or `nil` if not connected
    /// or no frame has arrived yet. Read it each frame in `draw()` and `drawImage`
    /// the result; don't hold the returned image across frames.
    public var frame: Image? {
        guard let texture = client?.newFrameImage() else { return nil }
        // The surface holds display-ready (sRGB-encoded) bytes, but Syphon hands it
        // over as a non-sRGB texture. Ollin's image pipeline shades in linear and
        // expects an sRGB texture to decode on sample, so read it through an sRGB
        // view (falling back to the raw texture if a view can't be made).
        let srgb = texture.makeTextureView(pixelFormat: .bgra8Unorm_srgb) ?? texture
        // Syphon textures follow the GL/Syphon bottom-left origin convention, so
        // flip vertically to land upright in Ollin's top-left image space.
        return Image(texture: srgb, flippedVertically: true)
    }

    /// Drop the current connection and look for a source again (e.g. after the
    /// source app restarts, or to switch sources).
    public func connect(named name: String? = nil, appName: String? = nil) {
        client?.stop()
        client = nil
        open(named: name, appName: appName)
    }

    /// Stop receiving frames and release the connection. Optional — releasing the
    /// client has the same effect.
    public func stop() {
        client?.stop()
        client = nil
    }

    /// Every Syphon source currently available on the system.
    public static func availableServers() -> [SyphonServerInfo] {
        SyphonServerDirectory.shared().servers.compactMap { entry in
            coerceStringDict(entry).map(SyphonServerInfo.init(description:))
        }
    }

    // MARK: Private

    private func open(named name: String?, appName: String?) {
        let match = SyphonClient.availableServers().first { info in
            (name == nil || info.name == name) && (appName == nil || info.appName == appName)
        }
        guard let match else { return }
        open(to: match.description)
    }

    private func open(to description: [String: Any]) {
        guard let device else { return }
        serverName = description[SyphonServerDescriptionNameKey] as? String
        appName = description[SyphonServerDescriptionAppNameKey] as? String
        client = SyphonMetalClient(serverDescription: description, device: device,
                                   options: nil, newFrameHandler: nil)
    }

    /// Bridge a Syphon description (an `NSDictionary` of `id<NSCoding>` values) to
    /// a `[String: Any]` the client init and info struct can use.
    private static func coerceStringDict(_ value: Any) -> [String: Any]? {
        value as? [String: Any]
    }
}
