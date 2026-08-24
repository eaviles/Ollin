@testable import Ollin
import Testing
import Foundation

/// Pure-CPU checks on the mirror map. A plate is unreadable by construction, so
/// no picture of one can be judged by eye: the only way to know a mark is in
/// the right place is to send light back along its path and see where the light
/// arrives.
///
/// Three laws carry the suite, and each one is derived away from the code that
/// is being checked. `lightRunsBackToTheEye` is the reflection law itself,
/// measured on the finished mark rather than assumed from the formula that made
/// it. `heightIsSharedBetweenTheTwoLegs` reaches the same mirror point by a
/// route the map never takes, since a bounce off a standing cylinder keeps the
/// path's fall, so the bounce height is the eye's height split between the two
/// legs on the page. `theViewersLeftStaysLeft` pins the one error this
/// technique invites, which is a picture that comes out reversed and looks
/// perfectly plausible until somebody reads a word in it.
@Suite
struct AnamorphosisTests {

    /// A setup with round numbers: a mirror in the middle of a 1080 canvas, a
    /// viewer a little south of it and well above it.
    private func setup(
        radius: Double = 110,
        lift: Double = 0,
        pictureWidth: Double = 260,
        pictureHeight: Double = 120,
        facing: Double? = nil
    ) -> Anamorphosis {
        Anamorphosis(
            center: Vector2(540, 540),
            radius: radius,
            eye: Vector3(540, 1000, 430),
            picture: Rectangle(center: Vector2(540, 540), width: pictureWidth, height: pictureHeight),
            lift: lift,
            facing: facing
        )
    }

    /// A spread of picture points that covers the box, corners included.
    private func probes(_ mirror: Anamorphosis) -> [Vector2] {
        var points: [Vector2] = []
        for i in 0...6 {
            for j in 0...6 {
                points.append(mirror.picture.point(u: Double(i) / 6, v: Double(j) / 6))
            }
        }
        return points
    }

    // MARK: - The reflection itself

    /// The load-bearing law. Take the finished mark, aim it at the place on the
    /// mirror it is supposed to be seen at, bounce it off the glass, and the
    /// light must arrive at the eye. Nothing here reuses the map's own
    /// arithmetic: it measures the path that was produced.
    @Test func lightRunsBackToTheEye() {
        // Lifted off the page on purpose: a planted lower edge puts the mark
        // exactly under its own bounce, and a path of no length has no
        // direction to measure. That edge is pinned by its own law below.
        let mirror = setup(lift: 8)
        var checked = 0
        for point in probes(mirror) {
            guard let seen = mirror.mirrorPoint(of: point),
                  let mark = mirror.plate(of: point) else { continue }
            checked += 1

            let outward = Vector3(seen.x - mirror.center.x, seen.y - mirror.center.y, 0).normalized
            let arriving = (seen - Vector3(mark.x, mark.y, 0)).normalized
            let leaving = arriving - outward * (2 * arriving.dot(outward))
            let toEye = (mirror.eye - seen).normalized

            #expect(abs(leaving.x - toEye.x) < 1e-9)
            #expect(abs(leaving.y - toEye.y) < 1e-9)
            #expect(abs(leaving.z - toEye.z) < 1e-9)
        }
        #expect(checked == 49)
    }

    /// The same mirror point, worked out a second way. The bounce turns only
    /// the part of the path facing the glass, so the path's fall per step
    /// across the page is the same before and after it. That makes the bounce
    /// height the eye's height shared between the two legs, measured flat.
    @Test func heightIsSharedBetweenTheTwoLegs() {
        let mirror = setup(lift: 12)
        for point in probes(mirror) {
            guard let seen = mirror.mirrorPoint(of: point),
                  let mark = mirror.plate(of: point) else { continue }
            let flat = Vector2(seen.x, seen.y)
            let coming = flat.distance(to: mirror.eyeSpot)
            let going = flat.distance(to: mark)
            let expected = mirror.eye.z * going / (coming + going)
            #expect(abs(seen.z - expected) < 1e-9)
        }
    }

    /// A mark always lands outside the glass, so the mirror never stands on its
    /// own picture. The bounce leaves the surface pointing away from the axis,
    /// so distance from the axis can only grow along it.
    @Test func everyMarkLandsOutsideTheMirror() {
        let mirror = setup(lift: 5)
        for point in probes(mirror) {
            guard let mark = mirror.plate(of: point) else { continue }
            #expect(mark.distance(to: mirror.center) >= mirror.radius - 1e-9)
        }
    }

    /// The lower edge of a planted picture does not move at all. A point at
    /// height zero is already on the page, so its bounce has nowhere to travel
    /// and the mark sits on the mirror's own circle.
    @Test func theLowestEdgeSitsOnTheCircle() {
        let mirror = setup(lift: 0)
        for i in 0...8 {
            let bottom = mirror.picture.point(u: Double(i) / 8, v: 1)
            guard let mark = mirror.plate(of: bottom) else {
                Issue.record("the lower edge must always reach the page")
                continue
            }
            #expect(abs(mark.distance(to: mirror.center) - mirror.radius) < 1e-9)
        }
    }

    /// Higher up the picture is farther out on the page. This is the stretch
    /// that makes a plate unreadable, and it is monotone: no two heights ever
    /// swap places.
    @Test func higherPicturePointsLandFartherOut() {
        let mirror = setup()
        for i in 0...6 {
            let u = Double(i) / 6
            var previous = -Double.infinity
            for j in stride(from: 1.0, through: 0.0, by: -0.1) {   // bottom to top
                guard let mark = mirror.plate(of: mirror.picture.point(u: u, v: j)) else { continue }
                let out = mark.distance(to: mirror.center)
                #expect(out > previous)
                previous = out
            }
        }
    }

    // MARK: - Which way round

    /// The error this technique invites. A picture point left of the middle
    /// must be seen on the viewer's left, and a reversed wrap produces a plate
    /// that is wrong in a way no other check here would notice.
    @Test func theViewersLeftStaysLeft() {
        let mirror = setup()
        let toMirror = (mirror.center - mirror.eyeSpot).normalized
        let viewersRight = Vector2(-toMirror.y, toMirror.x)

        let left = mirror.picture.point(u: 0.1, v: 0.5)
        let right = mirror.picture.point(u: 0.9, v: 0.5)
        guard let seenLeft = mirror.mirrorPoint(of: left),
              let seenRight = mirror.mirrorPoint(of: right) else {
            Issue.record("both sides of the picture must sit on the mirror")
            return
        }
        let leftOffset = (Vector2(seenLeft.x, seenLeft.y) - mirror.center).dot(viewersRight)
        let rightOffset = (Vector2(seenRight.x, seenRight.y) - mirror.center).dot(viewersRight)
        #expect(leftOffset < 0)
        #expect(rightOffset > 0)
    }

    /// A picture point on the middle line is seen straight ahead, so its mark
    /// sits on the line through the eye and the mirror. Symmetry, and the
    /// cheapest check that the facing direction is resolved correctly.
    @Test func theMiddleOfThePictureStaysOnTheLineOfSight() {
        // Wherever the viewer stands, since the wrap is aimed at them. A wrap
        // turned away from the eye keeps no such symmetry, which is why the
        // law is stated for the aimed case only.
        for spot in [Vector3(540, 1000, 430), Vector3(120, 300, 380), Vector3(900, 200, 500)] {
            let mirror = Anamorphosis(
                center: Vector2(540, 540), radius: 110, eye: spot,
                picture: Rectangle(center: Vector2(540, 540), width: 200, height: 100)
            )
            let aim = (mirror.eyeSpot - mirror.center).normalized
            var checked = 0
            for v in [0.0, 0.25, 0.5, 0.75, 1.0] {
                guard let mark = mirror.plate(of: mirror.picture.point(u: 0.5, v: v)) else { continue }
                checked += 1
                #expect(abs((mark - mirror.center).cross(aim)) < 1e-8)
                // And it lies between the mirror and the viewer, never behind.
                #expect((mark - mirror.center).dot(aim) > 0)
            }
            #expect(checked == 5)
        }
    }

    /// The picture rides on the mirror at its own size, so two points a known
    /// distance apart across the picture are that far apart along the arc. This
    /// is what keeps the perceived picture from being squeezed before the
    /// mirror ever gets to it.
    @Test func thePictureKeepsItsSizeOnTheGlass() {
        let mirror = setup(radius: 90, pictureWidth: 200, pictureHeight: 80)
        guard let left = mirror.mirrorPoint(of: mirror.picture.point(u: 0, v: 1)),
              let right = mirror.mirrorPoint(of: mirror.picture.point(u: 1, v: 1)),
              let top = mirror.mirrorPoint(of: mirror.picture.point(u: 0, v: 0)) else {
            Issue.record("the corners must sit on the mirror")
            return
        }
        let leftAngle = (Vector2(left.x, left.y) - mirror.center).angle
        let rightAngle = (Vector2(right.x, right.y) - mirror.center).angle
        var swept = abs(leftAngle - rightAngle)
        if swept > .pi { swept = 2 * .pi - swept }
        #expect(abs(swept * mirror.radius - mirror.picture.width) < 1e-9)
        #expect(abs((top.z - left.z) - mirror.picture.height) < 1e-9)
    }

    // MARK: - The map back

    /// Every mark leads back to the picture point that made it. The way back is
    /// a search rather than a formula, so this is the check that the search
    /// finds the true bounce and not a neighboring one.
    @Test func theMapBackRecoversThePicture() {
        let mirror = setup(lift: 20)
        var checked = 0
        for point in probes(mirror) {
            guard let mark = mirror.plate(of: point) else { continue }
            guard let back = mirror.picturePoint(of: mark) else {
                Issue.record("a mark that exists must lead back")
                continue
            }
            checked += 1
            #expect(back.distance(to: point) < 1e-6)
        }
        #expect(checked == 49)
    }

    /// The search must refuse a spot no light can reach, rather than answering
    /// with the nearest thing it found. A point under the glass has no path.
    @Test func theMapBackRefusesAnImpossibleMark() {
        let mirror = setup()
        #expect(mirror.picturePoint(of: mirror.center) == nil)
        #expect(mirror.picturePoint(of: mirror.center + Vector2(mirror.radius / 2, 0)) == nil)
    }

    // MARK: - The limits of a setup

    /// The eye sees less than half the mirror, and less again the closer it
    /// stands. A picture wider than that arc cannot be shown whole, and `fits`
    /// says so without drawing anything.
    @Test func aTooWidePictureIsRefusedBeforeItIsDrawn() {
        let narrow = setup(pictureWidth: 200)
        #expect(narrow.fits)
        #expect(narrow.picture.width < narrow.widestPicture)

        let wide = setup(pictureWidth: narrow.widestPicture + 10)
        #expect(!wide.fits)

        // The arc in view is the tangent line's, so a distant eye approaches
        // half the cylinder and a close one loses ground fast.
        let distant = Anamorphosis(
            center: Vector2(540, 540), radius: 110,
            eye: Vector3(540, 540 + 100_000, 430),
            picture: Rectangle(center: Vector2(540, 540), width: 200, height: 100)
        )
        #expect(abs(distant.visibleHalfAngle - .pi / 2) < 2e-3)
        let close = Anamorphosis(
            center: Vector2(540, 540), radius: 110,
            eye: Vector3(540, 540 + 120, 430),
            picture: Rectangle(center: Vector2(540, 540), width: 200, height: 100)
        )
        #expect(close.visibleHalfAngle < 0.5)
    }

    /// A picture level with the eye never comes down to the page, so `fits`
    /// refuses it. The height limit is a real one, not a matter of taste: the
    /// plate runs to infinity as the top of the picture reaches the eye.
    @Test func aPictureAsHighAsTheEyeIsRefused() {
        let mirror = setup(lift: 380, pictureWidth: 200, pictureHeight: 100)
        #expect(!mirror.fits)
        let top = mirror.picture.point(u: 0.5, v: 0)
        #expect(mirror.plate(of: top) == nil)

        // And approaching it stretches without bound, which is why the check
        // exists at all.
        var previous = 0.0
        for height in [200.0, 300, 380, 420, 429] {
            let tall = Anamorphosis(
                center: Vector2(540, 540), radius: 110,
                eye: Vector3(540, 1000, 430),
                picture: Rectangle(center: Vector2(540, 540), width: 100, height: 1),
                lift: height
            )
            guard let mark = tall.plate(of: tall.picture.point(u: 0.5, v: 1)) else { continue }
            let out = mark.distance(to: tall.center)
            #expect(out > previous)
            previous = out
        }
        #expect(previous > 10_000)
    }

    // MARK: - Contours and shapes

    /// A closed contour that survives whole stays closed, and the map bends it:
    /// a straight edge of the picture must not come back straight, or the
    /// resampling is being thrown away.
    @Test func aClosedContourSurvivesClosedAndBent() {
        let mirror = setup(lift: 10)
        let box = mirror.picture
        let square = Contour([
            box.point(u: 0.2, v: 0.25), box.point(u: 0.8, v: 0.25),
            box.point(u: 0.8, v: 0.75), box.point(u: 0.2, v: 0.75),
        ], closed: true)

        let pieces = mirror.plate(of: square, spacing: 4)
        #expect(pieces.count == 1)
        #expect(pieces[0].isClosed)
        #expect(pieces[0].points.count > 40)

        // The top edge was dead straight going in. Measure how far its middle
        // sits off the line between its ends: a map that forgot to walk the
        // edge would hand back the two ends and a straight line between them.
        let edge = Contour([box.point(u: 0.2, v: 0.25), box.point(u: 0.8, v: 0.25)], closed: false)
        let mapped = mirror.plate(of: edge, spacing: 4)
        #expect(mapped.count == 1)
        let marks = mapped[0].points
        #expect(marks.count > 30)
        let line = (marks[marks.count - 1] - marks[0]).normalized
        let sag = abs((marks[marks.count / 2] - marks[0]).cross(line))
        #expect(sag > 100)
    }

    /// A contour that runs off the arc the mirror shows comes back as the
    /// pieces that survived, opened, rather than as one contour with a wrong
    /// edge closing the gap.
    @Test func aContourRunningOffTheMirrorIsCutToWhatTheEyeSees() {
        let mirror = setup(pictureWidth: 600, pictureHeight: 120)
        #expect(!mirror.fits)
        let band = Contour([
            mirror.picture.point(u: 0, v: 0.5), mirror.picture.point(u: 1, v: 0.5),
        ], closed: false)
        let pieces = mirror.plate(of: band, spacing: 3)

        // The band walks around the mirror one way, so the stretch in view is
        // one stretch, and it is exactly as long as the eye can see.
        #expect(pieces.count == 1)
        #expect(!pieces[0].isClosed)
        let survived = Double(pieces[0].points.count - 1) * 3
        #expect(abs(survived - mirror.widestPicture) < 6)

        // Two pieces when the gap is in the middle rather than at the ends.
        // This picture is hung so high that its upper third is level with the
        // eye, and nothing up there ever comes down to the page, so a line that
        // rises through that band and falls again is cut in two.
        let hung = Anamorphosis(
            center: Vector2(540, 540), radius: 110,
            eye: Vector3(540, 1000, 430),
            picture: Rectangle(center: Vector2(540, 540), width: 200, height: 200),
            lift: 300
        )
        let arch = Contour([
            hung.picture.point(u: 0.05, v: 1), hung.picture.point(u: 0.5, v: 0.1),
            hung.picture.point(u: 0.95, v: 1),
        ], closed: false)
        let cut = hung.plate(of: arch, spacing: 3)
        #expect(cut.count == 2)
        #expect(cut.allSatisfy { !$0.isClosed })
    }

    /// A shape is a region, so a contour that only partly survives is dropped
    /// rather than left open with nothing to fill.
    @Test func aShapeDropsAContourItCannotCarryWhole() {
        let mirror = setup(pictureWidth: 600, pictureHeight: 120)
        let inside = Contour([
            mirror.picture.point(u: 0.45, v: 0.3), mirror.picture.point(u: 0.55, v: 0.3),
            mirror.picture.point(u: 0.55, v: 0.7), mirror.picture.point(u: 0.45, v: 0.7),
        ], closed: true)
        let across = Contour([
            mirror.picture.point(u: 0.02, v: 0.3), mirror.picture.point(u: 0.98, v: 0.3),
            mirror.picture.point(u: 0.98, v: 0.7), mirror.picture.point(u: 0.02, v: 0.7),
        ], closed: true)

        let plate = mirror.plate(of: Shape(contours: [inside, across]), spacing: 4)
        #expect(plate.contours.count == 1)
        #expect(plate.contours[0].isClosed)
    }

    /// A degenerate setup answers nothing rather than a page full of
    /// not-a-numbers.
    @Test func adegenerateSetupIsRefused() {
        let flat = Anamorphosis(
            center: Vector2(540, 540), radius: 0,
            eye: Vector3(540, 1000, 430),
            picture: Rectangle(center: Vector2(540, 540), width: 200, height: 100)
        )
        #expect(flat.mirrorPoint(of: Vector2(540, 540)) == nil)
        #expect(flat.plate(of: Vector2(540, 540)) == nil)
        #expect(!flat.fits)

        let sunk = Anamorphosis(
            center: Vector2(540, 540), radius: 110,
            eye: Vector3(540, 1000, -5),
            picture: Rectangle(center: Vector2(540, 540), width: 200, height: 100)
        )
        #expect(sunk.plate(of: sunk.picture.center) == nil)
    }
}
