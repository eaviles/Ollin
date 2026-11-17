//  Ported from "face-align" by Edgardo Avilés-López —
//  https://github.com/eaviles/rtp-sfpc-f21-p5 (week-6), his p5.js take on the
//  faceAlign example from Zach Lieberman's Recreating the Past class at SFPC
//  (Fall 2021). Original license: MIT. Reworked for Ollin's API (FaceTracker,
//  @Smoothed, withState).

import Ollin
import OllinSamplePhotos
import OllinVision

/// The overlay idea turned inside out: instead of drawing results *on* the
/// feed, the *picture* is transformed: translated, rotated, and scaled every
/// frame so the eyes sit level at the canvas center at a constant spread. Tilt
/// your head and the room counter-rotates; lean in and it zooms out; your face
/// stays put while the world does the moving.
///
/// Eye centers are the centroids of the `FaceTracker`'s eye landmark loops.
/// Raw detections jitter, and a whole-picture transform amplifies every
/// wobble, most of all in the turn and the zoom: a pixel of noise between the
/// eyes swings the edges of the picture by several. So the three things the
/// transform reads (where the eyes are, how far their line tilts, how far
/// apart they sit) are each steadied by a `@Smoothed` of their own (the 1€
/// filter), the tilt and the spread harder than the position. The alignment
/// itself is three lines of transform stack inside `withState`.
@main
final class FaceAlign: Sketch {
    // A camera where this Mac has one, and a bundled photograph where it does
    // not, so there is always a face to square up. `--photo` takes the picture even
    // where a camera would have worked, which is how a still of this sketch is made.
    let feed = Camera.orStill(SamplePhoto.portrait.load())
    lazy var faces = FaceTracker(feed)

    /// What the alignment reads, in canvas coordinates: the point midway
    /// between the eyes, the tilt of the line through them in radians, and the
    /// distance between them. Lower `minCutoff` smooths harder at rest, and
    /// `beta` loosens the filter as the head moves faster, counted in the
    /// value's own units a second (pixels for the first and the last, radians
    /// for the tilt, which is why its `beta` is the large one).
    @Smoothed(minCutoff: 0.35, beta: 0.05) var eyeCenter = Vector2.zero
    @Smoothed(minCutoff: 0.07, beta: 3) var tilt = 0.0
    @Smoothed(minCutoff: 0.07, beta: 0.03) var spread = 1.0
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
            // The landmark names are image-space (`leftEye` is the eye on the
            // image's left), so `right - left` points picture-right on an
            // upright face, and its angle is how far the head tilts.
            let across = right - left
            let angle = atan2(across.y, across.x)
            if hasLock {
                eyeCenter = (left + right) / 2
                tilt = angle
                spread = across.length
            } else {
                // No glide in from zero on the first lock.
                $eyeCenter.jump(to: (left + right) / 2)
                $tilt.jump(to: angle)
                $spread.jump(to: across.length)
                hasLock = true
            }
        }

        guard hasLock else {
            drawFrame(feed)
            drawCaption("FaceAlign — looking for a face…")
            return
        }

        // Eye midpoint to the canvas center, eye line to horizontal, eye
        // spread to a fixed share of the canvas. Rotating by the negated tilt
        // levels the eyes without flipping.
        withState {
            translate(center)
            rotate(-tilt)
            scale(width * 0.19 / max(spread, 1))
            translate(-eyeCenter.x, -eyeCenter.y)
            drawFrame(feed, in: bounds)
        }

        drawCaption("FaceAlign — eyes locked level; the room does the moving")
    }
}
