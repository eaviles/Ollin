import Foundation
import Ollin
import OllinVision

/// The camera through *your own* style-transfer model — a live painted mirror.
/// Nothing to download for this one: one script command trains a style-transfer
/// model from a single style image in a couple of minutes, and the model is
/// yours — no license to check, no weights to fetch. The
/// surface doing the work is `outputImage`: where `DepthRelief` reads its
/// model's output as a gray value *map*, a style model *paints a picture*, and
/// `outputImage` hands it over in full color, drawn like any image. Slide the
/// mouse left and right to crossfade between the camera and the painting.
///
/// To train a model (a couple of minutes, one command — the Create ML app no
/// longer offers its Style Transfer template, but the CreateML framework still
/// trains them, and `Scripts/train-style-model.swift` wraps it):
///
///     swift Scripts/train-style-model.swift path/to/any-image.jpg
///
/// Any image works as the style — a painting, a texture, an export of one of
/// your own sketches. Relaunch — or train while this runs; the sketch is
/// watching for the file. Details and options in `Examples/Vision/README.md`.
@main
final class StyleMirror: Sketch {
    static let modelPaths = ["Models/StyleTransfer.mlmodel",
                             "Models/StyleTransfer.mlpackage"]
    static var modelPath: String? {
        modelPaths.first { FileManager.default.fileExists(atPath: $0) }
    }

    let camera = Camera()
    var styler: ModelTracker?

    override func setup() {
        try? camera.start()
    }

    override func draw() {
        background(Color(white: 0.04))

        // The model is trained, not fetched — keep looking for it, so saving
        // the Create ML export while the sketch runs picks it up live.
        if styler == nil, let path = Self.modelPath {
            styler = ModelTracker(camera, modelAt: URL(fileURLWithPath: path))
        }

        // While a notice sits over the feed, dim the feed so the text reads.
        let showsNotice = styler == nil || styler?.unavailableReason != nil
            || styler?.isLoaded == false
        if showsNotice { tint(Color(white: 0.25)) }
        guard let rect = drawFrame(camera) else { return noTint() }
        noTint()

        guard let styler else {
            return drawStatus("No style model yet — train your own from any " +
                              "image (a couple of minutes):\n" +
                              "swift Scripts/train-style-model.swift your-image.jpg\n" +
                              "Train while this runs — the sketch is watching for\n" +
                              Self.modelPaths[0] + ".",
                              style: .warning)
        }
        if let reason = styler.unavailableReason {
            return drawStatus(reason, style: .warning)
        }
        if !styler.isLoaded {
            return drawStatus("Loading the style model…\n" +
                              "The first run prepares it for this Mac; " +
                              "after that it starts instantly.")
        }

        if let painting = styler.outputImage {
            // Crossfade by mouse: camera at the left edge, painting at the right.
            let blend = map(mouseX, rect.x, rect.x + rect.width, 0, 1, clamp: true)
            tint(Color(white: 1, alpha: blend))
            drawImage(painting, in: rect)
            noTint()
        }

        drawCaption("StyleMirror — slide the mouse: camera ↔ painting")
    }
}
