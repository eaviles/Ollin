import Foundation
import ARKit
import UIKit
import simd

/// One reference file the phone knows: the name a sketch matches on, the file it
/// came from, and, for a picture, how wide it is printed.
struct MarkerReference: Identifiable, Sendable {
    var id: String { fileName }
    let name: String
    let fileName: String
    let kind: PhoneMarkerKind
    /// Printed width in meters (a picture only).
    let width: Double
    /// Whether the file name stated that width, or the fallback was used.
    let statedWidth: Bool
}

/// The pictures and objects the phone can look for, read from the app's own folder.
///
/// The folder is the app's Documents directory, which iOS shows in Finder and the
/// Files app, so somebody drops a picture in over the cable or by AirDrop with no
/// tool of ours in between. A picture needs its printed width in meters, which no
/// image file carries, so the file's own name states it: `poster@30cm.png`,
/// `card-50mm.jpg`, `plate 12in.heic`, `tile_0.4m.png`. A name that says nothing
/// gets the fallback width and the app says so on its screen, since a wrong width
/// puts the picture at the wrong distance rather than losing it.
///
/// A scanned solid object arrives as an `.arobject` file, which already carries its
/// own size and origin, so its name is only a name.
struct MarkerLibrary {
    var references: [MarkerReference] = []
    var images: Set<ARReferenceImage> = []
    var objects: Set<ARReferenceObject> = []
    /// What the phone could not read, and what it assumed, in plain sentences for
    /// the app's own screen.
    var notes: [String] = []

    var isEmpty: Bool { images.isEmpty && objects.isEmpty }

    /// The folder somebody drops reference files into: the app's Documents
    /// directory, created on first look so it appears in Finder even while empty.
    static var folder: URL {
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: documents, withIntermediateDirectories: true)
        return documents
    }

    /// Read every reference file in `folder` and below it. Files it cannot use are
    /// skipped with a note rather than failing the load, so one bad file never takes
    /// the whole library down.
    static func load(from folder: URL = MarkerLibrary.folder) -> MarkerLibrary {
        var library = MarkerLibrary()
        let manager = FileManager.default
        let files = manager.enumerator(at: folder,
                                       includingPropertiesForKeys: [.isRegularFileKey],
                                       options: [.skipsHiddenFiles, .skipsPackageDescendants])?
            .compactMap { $0 as? URL } ?? []

        for url in files.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
            let fileName = url.lastPathComponent
            let ext = url.pathExtension.lowercased()
            let name = PhoneWire.markerName(fromFileName: fileName)
            if ext == PhoneWire.markerObjectExtension {
                guard let object = try? ARReferenceObject(archiveURL: url) else {
                    library.notes.append("Could not read \(fileName) as a scanned object.")
                    continue
                }
                object.name = name
                library.objects.insert(object)
                library.references.append(MarkerReference(name: name, fileName: fileName,
                                                          kind: .object, width: 0,
                                                          statedWidth: true))
            } else if PhoneWire.markerImageExtensions.contains(ext) {
                guard let image = UIImage(contentsOfFile: url.path),
                      let cgImage = Self.upright(image) else {
                    library.notes.append("Could not read \(fileName) as a picture.")
                    continue
                }
                let measured = PhoneWire.markerWidth(fromName: fileName)
                let reference = ARReferenceImage(cgImage, orientation: .up,
                                                 physicalWidth: CGFloat(measured.meters))
                reference.name = name
                library.images.insert(reference)
                library.references.append(MarkerReference(name: name, fileName: fileName,
                                                          kind: .image, width: measured.meters,
                                                          statedWidth: measured.stated))
                if !measured.stated {
                    let centimeters = measured.meters * 100
                    library.notes.append(String(format: "%@ says no size, so it is taken as %.0f cm wide. Rename it like %@@30cm to say.",
                                                fileName, centimeters, name))
                }
            }
        }
        if library.isEmpty {
            library.notes.append("No reference files yet. Connect the cable, open the phone in Finder, and drop a picture into Ollin Capture's folder.")
        }
        return library
    }

    /// The picture's pixels the way a person sees them. A camera records which way it
    /// was held beside the pixels rather than turning them, so a photo's own bitmap
    /// is often on its side. Redrawing it once here means the reference is upright by
    /// construction, and ARKit is handed a plain bitmap it can always read.
    private static func upright(_ image: UIImage) -> CGImage? {
        guard image.imageOrientation != .up else { return image.cgImage }
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        format.opaque = true
        let renderer = UIGraphicsImageRenderer(size: image.size, format: format)
        return renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: image.size))
        }.cgImage
    }
}

/// Runs ARKit world tracking with a library of reference pictures and scanned
/// objects, and reports each one it finds as a `PhoneMarkerSample`: the reference's
/// name, whether the phone is following it right now, its placement in ARKit world
/// space, and its real size in meters.
///
/// ARKit does the recognizing itself on the Neural Engine, so this streamer only
/// loads the library, hands it to the session, and reads the anchors back. A picture
/// is *followed* while it stays in view (its anchor keeps moving with it); a scanned
/// object is *found* once and then stands still, which is what an object anchor
/// means, so it never follows something somebody picks up.
///
/// Sending is paced by what is happening: while the phone follows anything the
/// placements go out every frame, because a sketch draws on them; while it follows
/// nothing the set still goes out a few times a second, so the Mac learns that the
/// picture left the view. ARKit delivers its callbacks on the main thread, so
/// `onMarkers` fires on main like every other streamer. `@unchecked Sendable` under
/// the usual discipline: the handlers are wired on the main thread before `start()`,
/// the library is touched only on the main thread, and the one callback that arrives
/// from elsewhere (a picture being checked) carries a finished sentence home.
final class MarkerStreamer: NSObject, ARSessionDelegate, LightReporting, @unchecked Sendable {

    /// Fired (on the main thread) with every marker the phone can see, empty when it
    /// sees none, so the receiver clears itself.
    var onMarkers: (([PhoneMarkerSample]) -> Void)?

    /// Fired (on the main thread) whenever the library is read, so the screen can
    /// say what the phone is looking for.
    var onLibrary: ((MarkerLibrary) -> Void)?

    let lightSampler = LightSampler()

    private let session = ARSession()
    private(set) var library = MarkerLibrary()

    /// How long the stream may stay quiet while nothing is being followed.
    private let quietInterval: TimeInterval = 0.2
    private var lastSent: TimeInterval = -.greatestFiniteMagnitude

    func start() {
        session.delegate = self
        reload()
    }

    func stop() { session.pause() }

    /// Read the folder again and restart the session with what is in it. This is how
    /// a file dropped in while the app is running gets picked up.
    ///
    /// Reading is a one-shot on mode entry and on the button, and the session wants
    /// its library on the main thread anyway, so it stays here rather than gaining a
    /// queue whose only job is to hand the result back. A large picture takes a
    /// moment to decode, which shows as a pause on that one tap.
    func reload() {
        library = MarkerLibrary.load()
        onLibrary?(library)

        let config = ARWorldTrackingConfiguration()
        config.detectionImages = library.images
        // ARKit follows a few pictures at once; asking for more than the library
        // holds is refused, so this is the smaller of the two.
        config.maximumNumberOfTrackedImages = min(4, library.images.count)
        // Trust the room over the name: a picture printed at another size then
        // reports what it really measures through `estimatedScaleFactor`.
        config.automaticImageScaleEstimationEnabled = true
        config.detectionObjects = library.objects
        session.run(config, options: [.resetTracking, .removeExistingAnchors])

        checkPictures()
    }

    /// Ask ARKit whether each picture has enough detail to be found at all, and say
    /// so on the screen. A flat or blurry picture is refused here rather than being
    /// looked for in vain, which is the failure that otherwise reads as a broken app.
    private func checkPictures() {
        for reference in library.images {
            let name = reference.name ?? "a picture"
            reference.validate { [weak self] error in
                guard let error else { return }
                let note = "\(name) is hard to recognize: \(error.localizedDescription)"
                DispatchQueue.main.async {
                    guard let self else { return }
                    self.library.notes.append(note)
                    self.onLibrary?(self.library)
                }
            }
        }
    }

    // MARK: ARSessionDelegate

    func session(_ session: ARSession, didUpdate frame: ARFrame) {
        lightSampler.report(frame)

        var found: [PhoneMarkerSample] = []
        for anchor in frame.anchors {
            if let image = anchor as? ARImageAnchor {
                found.append(Self.sample(of: image, at: frame.timestamp))
            } else if let object = anchor as? ARObjectAnchor {
                found.append(Self.sample(of: object, at: frame.timestamp))
            }
        }

        let following = found.contains { $0.isTracked }
        guard following || frame.timestamp - lastSent >= quietInterval else { return }
        lastSent = frame.timestamp
        onMarkers?(found)
    }

    /// One found picture. The anchor sits at the middle of the print and lies in its
    /// own x-z plane; the Mac turns that quarter for drawing, so the wire carries
    /// ARKit's matrix untouched.
    private static func sample(of anchor: ARImageAnchor, at timestamp: TimeInterval) -> PhoneMarkerSample {
        let reference = anchor.referenceImage
        let size = SIMD3<Float>(Float(reference.physicalSize.width),
                                Float(reference.physicalSize.height), 0)
        return PhoneMarkerSample(isTracked: anchor.isTracked, timestamp: timestamp,
                                 id: anchor.identifier, name: reference.name ?? "picture",
                                 kind: .image, transform: anchor.transform, size: size,
                                 scaleFactor: Float(anchor.estimatedScaleFactor))
    }

    /// One found object. An object anchor is not trackable, so it reports as found
    /// and holds the place it was found in; its reference carries the size of the
    /// box the scan measured and where the middle of that box sits.
    private static func sample(of anchor: ARObjectAnchor, at timestamp: TimeInterval) -> PhoneMarkerSample {
        let reference = anchor.referenceObject
        return PhoneMarkerSample(isTracked: true, timestamp: timestamp,
                                 id: anchor.identifier, name: reference.name ?? "object",
                                 kind: .object, transform: anchor.transform,
                                 size: reference.extent, center: reference.center)
    }
}
