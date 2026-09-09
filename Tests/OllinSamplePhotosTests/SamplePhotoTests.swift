import Testing
@testable import OllinSamplePhotos

/// The bundled photographs: each decodes at its declared size, and each carries
/// a credit that names the photographer, the place, the page it came from, and
/// the license it is used under.
@Suite struct SamplePhotoTests {
    /// The two surfaces are textures rather than pictures, so they are sized
    /// for a GPU rather than for a page.
    static let surfaces: [SamplePhoto] = [.talavera, .stone]

    @Test func everyPhotographDecodesAt1600OnItsLongSide() {
        for photo in SamplePhoto.all where !SamplePhotoTests.surfaces.contains(photo) {
            let image = photo.load()
            #expect(max(image.width, image.height) == 1600, "\(photo.name)")
            #expect(min(image.width, image.height) >= 1000, "\(photo.name)")
        }
    }

    /// A texture is magnified on a surface and repeats, so it is a square of a
    /// power of two rather than 1600 on its long side: that is the size a GPU
    /// mips evenly, and at 1600 neither of these fits the size budget without
    /// artifacts a magnified surface would show.
    @Test func theSurfacesAreSquarePowersOfTwo() {
        for photo in SamplePhotoTests.surfaces {
            let image = photo.load()
            #expect(image.width == image.height, "\(photo.name)")
            #expect(image.width == 1024, "\(photo.name)")
        }
    }

    /// The faces are square, so a sketch can crop one to the canvas without
    /// choosing what to lose. A figure keeps whatever frame holds its whole
    /// body, upright where a raised arm and a foot would not fit a square.
    @Test func theFacesAreSquare() {
        for photo in [SamplePhoto.portrait, .scarf, .profile, .marigolds] {
            let image = photo.load()
            #expect(image.width == image.height, "\(photo.name)")
        }
    }

    /// The tables and the streets are square too: a table shot from above has
    /// no upright to keep, and a street was cut to the largest square its own
    /// frame held rather than trimmed on all four sides.
    @Test func theTablesAndStreetsAreSquare() {
        for photo in [SamplePhoto.breakfast, .desk, .alley, .street, .textiles, .city] {
            let image = photo.load()
            #expect(image.width == image.height, "\(photo.name)")
        }
    }

    @Test func everyCreditIsComplete() {
        for photo in SamplePhoto.all {
            let credit = photo.credit
            #expect(!credit.photographer.isEmpty, "\(photo.name)")
            #expect(!credit.place.isEmpty, "\(photo.name)")
            #expect(credit.source.hasPrefix("https://"), "\(photo.name)")
            #expect(credit.licenseURL.hasPrefix("https://"), "\(photo.name)")
            #expect(credit.line.contains(credit.photographer))
        }
    }

    /// The two landscapes are the only wide pictures here, and they share one
    /// shape so a sketch can put either into the same box. Cropping one of them
    /// to match cost eleven percent of its height, all of it dark foreground.
    @Test func theLandscapesShareOneWideShape() {
        let shapes = [SamplePhoto.headland, .boats].map { photo -> (Int, Int) in
            let image = photo.load()
            return (image.width, image.height)
        }
        #expect(shapes.allSatisfy { $0 == shapes[0] })
        let aspect = Double(shapes[0].0) / Double(shapes[0].1)
        #expect(abs(aspect - 1.5) < 0.01, "\(aspect)")
    }

    @Test func theNamesAreDistinct() {
        #expect(Set(SamplePhoto.all.map(\.name)).count == SamplePhoto.all.count)
        #expect(SamplePhoto.all.count == 19)
    }
}
