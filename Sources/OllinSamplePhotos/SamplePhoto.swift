import Foundation
import Ollin

/// A photograph that ships with Ollin for its examples and the Guide's figures,
/// and for any sketch that wants a real picture to work on before it has one of
/// its own.
///
/// Ten pictures, 1600 pixels on the long side. Four faces, each a square: a
/// frontal `portrait`, an older face in a `scarf`, a `profile` on a plain
/// ground, and a woman before a wall of `marigolds`. Four whole figures, framed
/// so no limb runs off the edge: someone `reaching` up a concrete wall, a
/// masked `wrestler` with both arms raised, a `dancer` on white, and a
/// breakdancer holding a `handstand`. And two tables seen from above, for the
/// readers that want things to name and print to read: a `breakfast` and a
/// `desk`. Each carries its `credit`: who made it, where, and the terms it is
/// used under, so a sketch can draw the line the photographer is owed.
///
///     let picture = SamplePhoto.portrait.load()
///     drawImage(picture, in: canvasRectangle, fit: .cover)
///
/// They live in their own library so that an app which never imports it ships
/// none of them.
public struct SamplePhoto: Hashable, Sendable {
    /// The file name inside the bundle, without its extension.
    public let name: String
    /// A few words on what the picture shows.
    public let subject: String
    /// Who made the photograph, where, and under which terms.
    public let credit: Credit

    /// The photographer, the place, and the license a sample photograph is used under.
    public struct Credit: Hashable, Sendable {
        public let photographer: String
        public let place: String
        /// The page the photograph came from.
        public let source: String
        public let license: String
        public let licenseURL: String

        /// The credit as one line: "Photograph by Jhovani Morales, Oaxaca de Juárez (Pexels License)".
        public var line: String { "Photograph by \(photographer), \(place) (\(license))" }
    }

    /// Decodes the picture. Decoding happens on every call, so keep the result
    /// in a property rather than calling this from `draw()`.
    public func load() -> Image {
        guard let image = Image(resource: name, withExtension: "jpg", in: .module) else {
            preconditionFailure("OllinSamplePhotos: \(name).jpg is missing from the bundle")
        }
        return image
    }

    /// A young woman in a lace headdress and an embroidered blouse, smiling at
    /// the camera. The frontal face: what the face and eye trackers, the person
    /// matte, and the mosaics read best.
    public static let portrait = SamplePhoto(
        name: "portrait",
        subject: "a young woman in a lace headdress and an embroidered blouse, smiling",
        credit: Credit(photographer: "Jhovani Morales", place: "Oaxaca de Juárez, Mexico",
                       source: "https://www.pexels.com/photo/13402074/",
                       license: "Pexels License", licenseURL: "https://www.pexels.com/license/"))

    /// An elderly woman in a yellow scarf, looking straight at the camera. The
    /// face with the most in it: what the ink drawing, the brushwork, the
    /// stipple, and the dithers show best.
    public static let scarf = SamplePhoto(
        name: "scarf",
        subject: "an elderly woman in a yellow scarf, looking at the camera",
        credit: Credit(photographer: "Matthew Stephenson", place: "Oaxaca, Mexico",
                       source: "https://unsplash.com/photos/j6OYgSMVuiI",
                       license: "Unsplash License", licenseURL: "https://unsplash.com/license"))

    /// A woman in profile against a plain tan ground. The silhouette: what the
    /// single line, the string art, and the halftone read best.
    public static let profile = SamplePhoto(
        name: "profile",
        subject: "a woman in profile against a plain tan ground",
        credit: Credit(photographer: "Jessica Felicio", place: "Berrien County, United States",
                       source: "https://unsplash.com/photos/QS9ZX5UnS14",
                       license: "Unsplash License", licenseURL: "https://unsplash.com/license"))

    /// A woman before a wall of cempasúchil, the marigolds of Día de Muertos.
    /// The color and texture picture: what palette extraction, the color-vision
    /// simulation, the shock filter, and the frequency domain show best.
    public static let marigolds = SamplePhoto(
        name: "marigolds",
        subject: "a woman before a wall of cempasúchil marigolds",
        credit: Credit(photographer: "Fernando Paleta", place: "Mexico City, Mexico",
                       source: "https://www.pexels.com/photo/29302608/",
                       license: "Pexels License", licenseURL: "https://www.pexels.com/license/"))

    /// A dancer reaching up the face of a concrete wall, whole body, feet on a
    /// paved floor. Every one of the nineteen joints reads, so it is the
    /// straightforward one for body pose.
    public static let reaching = SamplePhoto(
        name: "reaching",
        subject: "a dancer reaching up a concrete wall, whole body",
        credit: Credit(photographer: "Los Muertos Crew", place: "Mexico",
                       source: "https://www.pexels.com/photo/8854016/",
                       license: "Pexels License", licenseURL: "https://www.pexels.com/license/"))

    /// A masked luchador with both fists raised over a full arena. Both arms
    /// read, and so do the crowd behind him: a person and a scene at once. The
    /// mask means the face trackers have nothing to find, which is the point of
    /// having him here beside the faces.
    public static let wrestler = SamplePhoto(
        name: "wrestler",
        subject: "a masked luchador with both arms raised over an arena",
        credit: Credit(photographer: "Juan TM", place: "Santiago de Querétaro, Mexico",
                       source: "https://www.pexels.com/photo/30098566/",
                       license: "Pexels License", licenseURL: "https://www.pexels.com/license/"))

    /// A contemporary dancer on a white ground, one arm reaching up and a long
    /// black skirt around the legs. The cleanest figure to matte, since nothing
    /// stands behind her.
    public static let dancer = SamplePhoto(
        name: "dancer",
        subject: "a contemporary dancer reaching, on a white ground",
        credit: Credit(photographer: "Gustavo Fring", place: "location not given",
                       source: "https://www.pexels.com/photo/7447230/",
                       license: "Pexels License", licenseURL: "https://www.pexels.com/license/"))

    /// A breakdancer upside down on one hand against a stone wall. The hard
    /// pose: a body the wrong way up, which the joint model reads as well as
    /// any other, and a good test that a sketch never assumed a head is on top.
    public static let handstand = SamplePhoto(
        name: "handstand",
        subject: "a breakdancer holding a one-handed handstand against a stone wall",
        credit: Credit(photographer: "Gabriel Jiménez", place: "location not given",
                       source: "https://www.pexels.com/photo/26870547/",
                       license: "Pexels License", licenseURL: "https://www.pexels.com/license/"))

    /// An Oaxacan breakfast from above: plates, bowls, cups, cutlery, a napkin,
    /// glasses, a phone. The densest table here for anything that names things.
    /// The object detector finds five (two cups, two bowls, a sandwich) where a
    /// person in a scene gives it three.
    public static let breakfast = SamplePhoto(
        name: "breakfast",
        subject: "an Oaxacan breakfast seen from above, plates and bowls on a wooden table",
        credit: Credit(photographer: "Jorge Acre", place: "Oaxaca de Juárez, Mexico",
                       source: "https://www.pexels.com/photo/17061842/",
                       license: "Pexels License", licenseURL: "https://www.pexels.com/license/"))

    /// A desk from above: a laptop, earbuds, a plant, a watch, a cup of coffee,
    /// and a notebook whose cover is printed. The one with text small enough to
    /// be real and large enough to read, so it is what the text recognizer and
    /// the rectangle detector are pointed at.
    public static let desk = SamplePhoto(
        name: "desk",
        subject: "a desk seen from above, a laptop and a printed notebook among other things",
        credit: Credit(photographer: "Ben Kolde", place: "Oxford, United States",
                       source: "https://unsplash.com/photos/H29h6a8j8QM",
                       license: "Unsplash License", licenseURL: "https://unsplash.com/license"))

    /// Every bundled photograph: the four faces, then the four figures, then the
    /// two tables.
    public static let all: [SamplePhoto] = [.portrait, .scarf, .profile, .marigolds,
                                            .reaching, .wrestler, .dancer, .handstand,
                                            .breakfast, .desk]
}
