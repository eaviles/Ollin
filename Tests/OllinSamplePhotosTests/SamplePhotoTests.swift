import Testing
@testable import OllinSamplePhotos

/// The bundled photographs: each decodes at its declared size, and each carries
/// a credit that names the photographer, the place, the page it came from, and
/// the license it is used under.
@Suite struct SamplePhotoTests {
    @Test func everyPhotographDecodesAsA1600Square() {
        for photo in SamplePhoto.all {
            let image = photo.load()
            #expect(image.width == 1600, "\(photo.name)")
            #expect(image.height == 1600, "\(photo.name)")
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

    @Test func theNamesAreDistinct() {
        #expect(Set(SamplePhoto.all.map(\.name)).count == SamplePhoto.all.count)
        #expect(SamplePhoto.all.count == 4)
    }
}
