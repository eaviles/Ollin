import Foundation
import Testing
import Ollin
@testable import OllinSampleModels

/// The bundled models: each loads from the bundle with triangles and a
/// material, fits its stated size budget, and carries a credit that names the
/// artist, the page it came from, and the license it is used under.
@Suite struct SampleModelTests {
    @Test func everyModelLoadsWithTriangles() {
        for model in SampleModel.all {
            let mesh = model.load()
            #expect(mesh.triangleCount > 0, "\(model.name)")
            #expect(mesh.positions.count > 0, "\(model.name)")
        }
    }

    /// A sample model is here to show a material under a light, so it carries
    /// one with a base-color texture; a model with no material would draw in
    /// the fill alone and teach nothing a primitive does not.
    @Test func everyModelBringsItsOwnMaterialAndTexture() {
        for model in SampleModel.all {
            let mesh = model.load()
            #expect(mesh.material != nil, "\(model.name)")
            #expect(mesh.material?.texture != nil, "\(model.name)")
            #expect(mesh.uvs.count == mesh.positions.count, "\(model.name)")
        }
    }

    /// Each file stays under a megabyte: the textures are held to 1K and packed
    /// into one `.glb`, the way the photographs are held to 1600 on their long
    /// side, so the library ships small.
    @Test func everyFileStaysUnderAMegabyte() throws {
        for model in SampleModel.all {
            let size = try FileManager.default.attributesOfItem(atPath: model.url.path)[.size] as? Int ?? 0
            #expect(size > 0 && size < 1_000_000, "\(model.name): \(size) bytes")
        }
    }

    /// `normalized(scale:)` is how a sketch fits a model to its scene, so each
    /// one must arrive with a finite, non-degenerate size for it to work on.
    @Test func everyModelNormalizesToItsScale() {
        for model in SampleModel.all {
            let mesh = model.load().normalized(scale: 2)
            let bounds = mesh.bounds
            let extent = bounds.max - bounds.min
            let longest = max(extent.x, extent.y, extent.z)
            #expect(abs(longest - 2) < 0.01, "\(model.name): \(longest)")
        }
    }

    @Test func everyCreditIsComplete() {
        for model in SampleModel.all {
            let credit = model.credit
            #expect(!credit.artist.isEmpty, "\(model.name)")
            #expect(credit.source.hasPrefix("https://"), "\(model.name)")
            #expect(credit.licenseURL.hasPrefix("https://"), "\(model.name)")
            #expect(credit.line.contains(credit.artist))
            #expect(credit.line.contains(credit.license))
        }
    }

    @Test func theNamesAreDistinct() {
        let names = SampleModel.all.map(\.name)
        #expect(Set(names).count == names.count)
    }
}
