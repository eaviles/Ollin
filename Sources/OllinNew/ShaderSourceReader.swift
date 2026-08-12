import Foundation
import OllinProjects

/// Gets the GLSL to translate, from wherever the caller pointed at.
///
/// Reading a file or standard input is the plain case. A web address is the
/// other one, and it goes through the site's own published interface with a key
/// the caller supplies, so nothing here keeps a copy of anybody's shader and the
/// author's own terms travel with what comes back.
enum ShaderSourceReader {

    struct Fetched {
        var glsl: String
        var provenance: ShaderImport.Provenance
    }

    enum Failure: Error, CustomStringConvertible {
        case cannotRead(String)
        case needsKey(String)
        case siteRefused(String)
        case noImagePass

        var description: String {
            switch self {
            case .cannotRead(let path):
                return "cannot read \(path)."
            case .needsKey(let id):
                return """
                    reading shader \(id) from the web needs a key of your own, and none is set.
                      1. Sign in on the site and ask for an API key in your profile.
                      2. Put it in the environment:  export SHADERTOY_API_KEY=yourkey
                    Or open the shader, copy its code, save it to a file, and pass the file instead.
                    Note that the site only serves a shader whose author marked it public and shared through the API.
                    """
            case .siteRefused(let why):
                return "the site did not return that shader: \(why)"
            case .noImagePass:
                return "that shader has no image pass to bring over."
            }
        }
    }

    /// Whether the caller named a web address rather than a file.
    static func looksLikeAddress(_ text: String) -> Bool {
        text.hasPrefix("http://") || text.hasPrefix("https://")
    }

    static func read(_ source: String) throws -> Fetched {
        if source == "-" {
            let data = FileHandle.standardInput.readDataToEndOfFile()
            guard let text = String(data: data, encoding: .utf8), !text.isEmpty else {
                throw Failure.cannotRead("standard input")
            }
            return Fetched(glsl: text, provenance: .init())
        }
        if looksLikeAddress(source) { return try fetch(source) }

        let url = URL(fileURLWithPath: source)
        guard let text = try? String(contentsOf: url, encoding: .utf8) else {
            throw Failure.cannotRead(source)
        }
        return Fetched(glsl: text, provenance: .init(title: url.deletingPathExtension().lastPathComponent))
    }

    // MARK: - The web

    /// The shader's identifier is the last part of the address.
    static func identifier(in address: String) -> String {
        (address.split(separator: "?").first.map(String.init) ?? address)
            .split(separator: "/").last.map(String.init) ?? address
    }

    private static func fetch(_ address: String) throws -> Fetched {
        let id = identifier(in: address)
        guard let key = ProcessInfo.processInfo.environment["SHADERTOY_API_KEY"], !key.isEmpty else {
            throw Failure.needsKey(id)
        }
        guard let endpoint = URL(string: "https://www.shadertoy.com/api/v1/shaders/\(id)?key=\(key)") else {
            throw Failure.siteRefused("that address does not read as a shader.")
        }

        // A command reads one address and then stops, so it waits for the reply
        // where it stands rather than handing the work to another thread.
        let payload: Data
        do {
            payload = try Data(contentsOf: endpoint)
        } catch {
            throw Failure.siteRefused(error.localizedDescription)
        }
        guard let root = (try? JSONSerialization.jsonObject(with: payload)) as? [String: Any]
        else { throw Failure.siteRefused("the reply did not read as a shader.") }

        if let complaint = root["Error"] as? String {
            throw Failure.siteRefused(complaint)
        }
        guard let shader = root["Shader"] as? [String: Any],
              let passes = shader["renderpass"] as? [[String: Any]]
        else { throw Failure.siteRefused("the reply carried no shader.") }

        // Only the image pass draws what is on screen. A shader built on several
        // passes needs the others by hand, and the translation says so.
        guard let image = passes.first(where: { ($0["type"] as? String) == "image" }) ?? passes.first,
              let code = image["code"] as? String
        else { throw Failure.noImagePass }

        let info = shader["info"] as? [String: Any]
        return Fetched(
            glsl: code,
            provenance: .init(title: info?["name"] as? String,
                              author: info?["username"] as? String,
                              url: address))
    }
}
