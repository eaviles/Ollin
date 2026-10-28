import Foundation
import Ollin

/// A 3D model that ships with Ollin for its examples and the Guide's figures,
/// and for any sketch that wants a real object to light, texture, or turn
/// before it has one of its own.
///
/// One model so far: a rubber `duck`, the bath toy, with its paint and its
/// shading in one texture. It is the model a
/// sketch reaches for when the lesson is the light, the material, the camera,
/// or the shadow rather than the shape itself, since everyone already knows
/// what a rubber duck looks like. Each model carries its `credit`: who made
/// it, where it came from, and the terms it is used under, so a sketch can
/// draw the line the artist is owed.
///
///     let duck = SampleModel.duck.load().normalized(scale: 3)
///     drawMesh(duck)
///
/// A model comes back as it was saved, in its author's units, so
/// `normalized(scale:)` fits it to a scene. The models live in their own
/// library so that an app which never imports it ships none of them.
public struct SampleModel: Hashable, Sendable {
    /// The file name inside the bundle, without its extension.
    public let name: String
    /// A few words on what the model is.
    public let subject: String
    /// Who made the model, where it came from, and under which terms.
    public let credit: Credit

    /// The artist, the page, and the license a sample model is used under.
    public struct Credit: Hashable, Sendable {
        public let artist: String
        /// The page the model came from.
        public let source: String
        public let license: String
        public let licenseURL: String

        /// The credit as one line: "Model by Alexandr (CC BY 4.0)".
        public var line: String { "Model by \(artist) (\(license))" }
    }

    /// Where the file is, inside this library's own bundle, for a loader that
    /// takes a path or a URL (`loadScene`, or a tool outside the framework).
    public var url: URL {
        guard let url = Bundle.module.url(forResource: name, withExtension: "glb") else {
            preconditionFailure("OllinSampleModels: \(name).glb is missing from the bundle")
        }
        return url
    }

    /// Reads the model. The file is read on every call, so keep the result in
    /// a property rather than calling this from `draw()`. The mesh comes back
    /// as saved, material and textures included; `normalized(scale:)` fits it
    /// to a scene.
    public func load() -> Mesh {
        guard let mesh = try? Mesh(contentsOf: url) else {
            preconditionFailure("OllinSampleModels: \(name).glb did not load")
        }
        return mesh
    }

    /// A rubber duck, the bath toy: a smooth yellow body with an orange beak
    /// and a painted eye, under two thousand triangles, its paint and its
    /// shading in one texture. It shows a material, a light, or an environment
    /// the way a photograph shows a filter. Saved standing on its base, a
    /// little over one unit tall, facing +z.
    public static let duck = SampleModel(
        name: "duck",
        subject: "a yellow rubber duck with an orange beak, the bath toy",
        credit: Credit(artist: "Alexandr",
                       source: "https://sketchfab.com/3d-models/yellow-rubber-duck-1990cda4c97e400f852d2b4078ebb958",
                       license: "CC BY 4.0", licenseURL: "https://creativecommons.org/licenses/by/4.0/"))

    /// Every bundled model.
    public static let all: [SampleModel] = [.duck]
}
