//  Ported from "face-align" by Edgardo Avilés-López —
//  https://github.com/eaviles/rtp-sfpc-f21-p5 (week-6), his p5.js take on the
//  faceAlign example from Zach Lieberman's Recreating the Past class at SFPC
//  (Fall 2021). Original license: MIT. Reworked for Ollin's API (FaceTracker,
//  @Smoothed, withState).

import Ollin
import OllinSamplePhotos
import OllinVision

/// The overlay idea turned inside out: instead of drawing results *on* the
/// feed, the *picture* is transformed — translated, rotated, and scaled every
/// frame so the eyes sit level at the canvas center at a constant spread. Tilt
/// your head and the room counter-rotates; lean in and it zooms out; your face
/// stays put while the world does the moving.
///
/// Eye centers are the centroids of the `FaceTracker`'s eye landmark loops,
/// steadied by `@Smoothed` (the 1€ filter) — raw detections jitter, and a
/// whole-picture transform amplifies every wobble. The alignment itself is
/// three lines of transform stack inside `withState`.
@main
final class FaceAlign: Sketch {
    // A camera where this Mac has one, and a bundled photograph where it does
    // not, so there is always a face to square up. `--photo` takes the picture even
    // where a camera would have worked, which is how a still of this sketch is made.
    let feed = Camera.orStill(SamplePhoto.portrait.load())
    lazy var faces = FaceTracker(feed)

    /// Eye centers in canvas coordinates. Lower `minCutoff` smooths harder at
    /// rest; the filter loosens on its own when the head moves fast.
    @Smoothed(minCutoff: 0.5) var leftEye = Vector2.zero
    @Smoothed(minCutoff: 0.5) var rightEye = Vector2.zero
    var hasLock = false

    override func draw() {
        background(Color(white: 0.06))

        // The rectangle the feed would land in un-aligned — eyes and picture
        // are both placed in this one space, so the math stays consistent.
        guard let rect = feed.fittedRectangle(in: bounds) else {
            drawFrame(feed)
            return
        }

        if let face = faces.faces.first, face.hasLandmarks,
           let left = face.landmarks(.leftEye, in: rect).centroid,
           let right = face.landmarks(.rightEye, in: rect).centroid {
            if hasLock {
                leftEye = left
                rightEye = right
            } else {
                $leftEye.set(left)      // jump on first lock — no glide in from zero
                $rightEye.set(right)
                hasLock = true
            }
        }

        guard hasLock else {
            drawFrame(feed)
            drawCaption("FaceAlign — looking for a face…")
            return
        }

        // Eye midpoint to the canvas center, eye line to horizontal, eye
        // spread to a fixed share of the canvas. The landmark names are
        // image-space (`leftEye` is the eye on the image's left), so
        // `rightEye - leftEye` points picture-right on an upright face and
        // rotating by its negated angle levels the eyes without flipping.
        let across = rightEye - leftEye
        let mid = (leftEye + rightEye) / 2

        withState {
            translate(center)
            rotate(-atan2(across.y, across.x))
            scale(width * 0.19 / max(across.length, 1))
            translate(-mid.x, -mid.y)
            drawFrame(feed, in: bounds)
        }

        drawCaption("FaceAlign — eyes locked level; the room does the moving")
    }
}
