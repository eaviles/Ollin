import Foundation

/// A mirrored cylinder standing on the page, and the map that spreads a picture
/// around it so the mirror gathers it back together.
///
/// The drawing on the page is unreadable: a smear that runs away from the
/// mirror and stretches as it goes. Stand the cylinder on its circle, put your
/// eye where the map was told you would be, and the smear straightens into the
/// picture, standing upright on the mirror's face. Nothing is undone in
/// software. The reflection does the work, and it has done it since the 1600s.
///
/// The rule is one ray, run backwards. Wrap the picture around the mirror like
/// a label. For each point of that label, take the ray from the eye to it,
/// bounce it off the mirror, and follow the bounce down to the page. Wherever
/// it lands is where the mark goes. A mark drawn there sends light back along
/// the same path, so the eye receives it from the direction of the label, and
/// the label is where the picture appears to be.
///
/// Two things follow from that rule, and both are visible in any finished
/// plate. The marks land on the **near** side of the mirror, between the glass
/// and the viewer, because a ray that strikes the face turned toward you comes
/// back toward you. So you read the plate by looking over it at the mirror. And
/// the marks spread as they go, because a point higher up the label is reached
/// by a shallower bounce, which travels farther before it meets the page. The
/// lowest edge of the picture does not move at all: it sits on the mirror's own
/// circle.
///
/// ```swift
/// let mirror = Anamorphosis(
///     center: Vector2(540, 540), radius: 110,
///     eye: Vector3(540, 980, 430),
///     picture: Rectangle(center: Vector2(540, 540), width: 300, height: 150)
/// )
/// let plate = mirror.plate(of: letters)      // letters is an ordinary Shape
/// drawShape(plate)
/// drawCircle(mirror.footprint)               // where to stand the mirror
/// ```
///
/// The picture is carried at its own size: a picture 300 wide wraps 300 of arc
/// around the mirror, so nothing is squeezed before the reflection gets to it.
/// That also sets the limit. The eye can only see the near half of the mirror,
/// and less than half once it stands at a finite distance, so a picture wider
/// than ``widestPicture`` runs past what the mirror can show and the part that
/// runs past is dropped. ``fits`` says so before you draw.
///
/// Written from the reflection construction for catoptric anamorphosis (see
/// `ATTRIBUTION.md`).
public struct Anamorphosis: Equatable, Sendable {
    /// Where the mirror stands on the page.
    public var center: Vector2

    /// The mirror's radius. The circle it occupies is ``footprint``.
    public var radius: Double

    /// The one place the plate reads from. `x` and `y` are where the viewer
    /// stands on the page's own coordinates, and `z` is how high the eye is
    /// above the page. Moving it moves every mark.
    public var eye: Vector3

    /// The box the picture is drawn in. Its width becomes arc around the
    /// mirror and its height becomes height up the mirror, both at true size.
    public var picture: Rectangle

    /// How far up the mirror the picture's lower edge sits. Zero puts it on the
    /// page, where marks land on the mirror's own circle and the picture looks
    /// planted. Lifting it clears the plate away from the glass.
    public var lift: Double

    /// The direction the middle of the picture is wrapped to, as an angle on
    /// the page. `nil` (the default) points it at the eye, which is the only
    /// direction that puts the whole picture in view.
    public var facing: Double?

    /// - Parameters:
    ///   - center: where the mirror stands.
    ///   - radius: the mirror's radius.
    ///   - eye: the viewing spot, `z` measured up from the page.
    ///   - picture: the box the picture is drawn in.
    ///   - lift: how far up the mirror the picture's lower edge sits.
    ///   - facing: which way the middle of the picture is wrapped, or `nil` to
    ///     aim it at the eye.
    public init(
        center: Vector2,
        radius: Double,
        eye: Vector3,
        picture: Rectangle,
        lift: Double = 0,
        facing: Double? = nil
    ) {
        self.center = center
        self.radius = radius
        self.eye = eye
        self.picture = picture
        self.lift = lift
        self.facing = facing
    }
}

// MARK: - What the setup implies

public extension Anamorphosis {
    /// The circle to stand the mirror on. Draw it as a guide, then take it off
    /// the finished plate.
    var footprint: Circle { Circle(center: center, radius: radius) }

    /// Where the viewer stands, read on the page alone.
    var eyeSpot: Vector2 { Vector2(eye.x, eye.y) }

    /// How far the viewer stands from the mirror's axis, across the page.
    var eyeDistance: Double { eyeSpot.distance(to: center) }

    /// The direction the middle of the picture is wrapped to, with `facing`
    /// resolved: the angle from the mirror toward the eye when it is `nil`.
    var facingAngle: Double {
        if let facing { return facing }
        return (eyeSpot - center).angle
    }

    /// Half the arc of the mirror the eye can see, in radians.
    ///
    /// An eye at an infinite distance sees half the cylinder, a quarter turn
    /// each way. Standing closer takes some of that away, since the sides curve
    /// out of sight, and standing inside the mirror leaves nothing at all.
    var visibleHalfAngle: Double {
        guard eyeDistance > radius else { return 0 }
        return acos(radius / eyeDistance)
    }

    /// The widest picture this setup can show whole, measured in the picture's
    /// own units. Anything wider runs off the sides of what the eye can see.
    var widestPicture: Double { 2 * visibleHalfAngle * radius }

    /// Whether the whole picture reaches the eye: narrow enough for the arc in
    /// view, and low enough to stay under the eye.
    ///
    /// The height matters because a mark leaves the mirror on a bounce that
    /// falls as steeply as the ray arrived, so a point of the picture level
    /// with the eye never comes down at all. Keeping the top of the picture
    /// under about a third of the eye's height keeps the plate a size you can
    /// print.
    var fits: Bool {
        radius > 0 && picture.width > 0 && picture.height > 0
            && picture.width <= widestPicture
            && lift >= 0 && lift + picture.height < eye.z
    }
}

// MARK: - The picture, wrapped on the mirror

public extension Anamorphosis {
    /// Where a point of the picture sits on the mirror: around it by the
    /// picture's own width, up it by the picture's own height.
    ///
    /// This is the point the finished plate is *seen* at. It is also the only
    /// place the two coordinate systems meet, so both the map and the map back
    /// run through it.
    func mirrorPoint(of picturePoint: Vector2) -> Vector3? {
        guard radius > 0, picture.width > 0, picture.height > 0 else { return nil }
        let uv = picture.uv(of: picturePoint)
        let along = (uv.x - 0.5) * picture.width          // arc from the middle
        let angle = facingAngle - along / radius          // the viewer's left stays left
        let height = lift + (1 - uv.y) * picture.height
        return Vector3(center.x + radius * cos(angle), center.y + radius * sin(angle), height)
    }

    /// The picture point a place on the mirror carries, undoing
    /// ``mirrorPoint(of:)``. Points outside the wrapped band come back outside
    /// the picture's box, which is how a caller knows they are off the label.
    func picturePoint(ofMirrorPoint point: Vector3) -> Vector2 {
        let angle = (Vector2(point.x, point.y) - center).angle
        let turned = shortestTurn(from: facingAngle, to: angle)
        let along = -turned * radius
        let u = 0.5 + (picture.width > 0 ? along / picture.width : 0)
        let v = picture.height > 0 ? 1 - (point.z - lift) / picture.height : 0
        return picture.point(u: u, v: v)
    }
}

// MARK: - The map onto the page

public extension Anamorphosis {
    /// Where a point of the picture must be drawn on the page.
    ///
    /// `nil` when no light path exists: the point sits on the far side of the
    /// mirror where the eye cannot reach it, or the bounce leaves level or
    /// rising and never comes down to the page.
    func plate(of picturePoint: Vector2) -> Vector2? {
        guard let seen = mirrorPoint(of: picturePoint) else { return nil }
        return plate(ofMirrorPoint: seen)
    }

    /// Where a place on the mirror throws its reflection down onto the page.
    func plate(ofMirrorPoint point: Vector3) -> Vector2? {
        let outward = Vector3(point.x - center.x, point.y - center.y, 0)
        guard outward.lengthSquared > 0, point.z >= 0 else { return nil }
        let normal = outward.normalized
        let arriving = point - eye
        let facingness = arriving.dot(normal)
        guard facingness < 0 else { return nil }           // the far side of the glass
        let leaving = arriving - normal * (2 * facingness)
        guard leaving.z < 0 else { return nil }            // never reaches the page
        let travel = -point.z / leaving.z
        guard travel.isFinite, travel >= 0 else { return nil }
        return Vector2(point.x + leaving.x * travel, point.y + leaving.y * travel)
    }

    /// A whole contour spread onto the page.
    ///
    /// The map bends straight lines, so the contour is walked at an even
    /// `spacing` first and the bend is carried by the extra points. A contour
    /// that runs off the arc the mirror can show comes back in pieces, one per
    /// stretch that survives, and a closed one that survives whole stays
    /// closed.
    func plate(of contour: Contour, spacing: Double = 3) -> [Contour] {
        let walked = contour.resampled(spacing: spacing)
        var points = walked.points
        guard points.count >= 2 else { return [] }
        if contour.isClosed { points.append(points[0]) }   // walk the closing edge too

        var runs: [[Vector2]] = []
        var run: [Vector2] = []
        var dropped = false
        for point in points {
            if let mark = plate(of: point) {
                run.append(mark)
            } else {
                dropped = true
                if run.count >= 2 { runs.append(run) }
                run = []
            }
        }
        if run.count >= 2 { runs.append(run) }

        if !dropped, contour.isClosed, runs.count == 1 {
            var whole = runs[0]
            whole.removeLast()                             // the repeated first point
            return [Contour(whole, closed: true)]
        }
        return runs.map { Contour($0, closed: false) }
    }

    /// A whole shape spread onto the page, ready to fill and stroke.
    ///
    /// A shape is a region, so a contour that only partly survives would leave
    /// a fill with no boundary. Those are dropped rather than opened, and a
    /// shape that runs entirely off the mirror comes back with no contours at
    /// all. ``fits`` is the check that says this beforehand.
    func plate(of shape: Shape, spacing: Double = 3) -> Shape {
        var kept: [Contour] = []
        for contour in shape.contours {
            let pieces = plate(of: contour, spacing: spacing)
            if pieces.count == 1, pieces[0].isClosed { kept.append(pieces[0]) }
        }
        return Shape(contours: kept, winding: shape.winding)
    }
}

// MARK: - The map back

public extension Anamorphosis {
    /// The picture point a mark on the page carries, undoing ``plate(of:)``.
    ///
    /// There is no formula for this one. Finding where a ray from the eye
    /// bounces to a given spot is the circle problem al-Haytham posed a
    /// thousand years ago, and it has no answer in ordinary algebra, so the
    /// bounce point is searched for along the arc the eye can see and then
    /// sharpened. The height comes out of it for free: the path's fall is the
    /// same before and after the bounce, so the bounce point's height is the
    /// eye's height shared between the two horizontal legs.
    ///
    /// `nil` when no light path exists, and slow enough that it belongs in
    /// `setup()` rather than in a per-frame loop.
    func picturePoint(of platePoint: Vector2) -> Vector2? {
        guard let seen = mirrorPoint(of: platePoint, asSeenBy: eye) else { return nil }
        return picturePoint(ofMirrorPoint: seen)
    }

    /// Where on the mirror a mark on the page is seen, for a viewer at `eye`.
    ///
    /// The search runs on the page alone. A bounce off a standing cylinder
    /// keeps the sideways part of the path and turns only the part facing the
    /// glass, so the path seen from above is an ordinary bounce off a circle,
    /// and the height rides along with it.
    func mirrorPoint(of platePoint: Vector2, asSeenBy viewer: Vector3) -> Vector3? {
        guard radius > 0, viewer.z > 0 else { return nil }
        let from = Vector2(viewer.x, viewer.y) - center
        let to = platePoint - center
        guard from.length > radius, to.length > radius else { return nil }

        // The bounce point must face both ends of the path, so only the arc
        // both can see is worth searching.
        let fromHalf = acos(min(1, radius / from.length))
        let toHalf = acos(min(1, radius / to.length))
        guard let arc = overlap(
            of: (from.angle - fromHalf, from.angle + fromHalf),
            and: (to.angle - toHalf, to.angle + toHalf)
        ) else { return nil }

        // How far the bounce misses by, as a signed turn. It crosses zero
        // exactly where the two angles match.
        func miss(_ angle: Double) -> Double {
            let normal = Vector2(cos(angle), sin(angle))
            let point = normal * radius
            let arriving = (point - from).normalized
            let leaving = (to - point).normalized
            let bounced = arriving - normal * (2 * arriving.dot(normal))
            return bounced.cross(leaving)
        }

        let steps = 256
        var previousAngle = arc.0
        var previousMiss = miss(previousAngle)
        var best: Double?
        for step in 1...steps {
            let angle = arc.0 + (arc.1 - arc.0) * Double(step) / Double(steps)
            let value = miss(angle)
            if previousMiss == 0 { best = previousAngle; break }
            if (previousMiss < 0) != (value < 0) {
                var low = previousAngle, high = angle, lowMiss = previousMiss
                for _ in 0..<80 {                          // bisect to the last bit
                    let middle = (low + high) / 2
                    let middleMiss = miss(middle)
                    if (lowMiss < 0) != (middleMiss < 0) { high = middle }
                    else { low = middle; lowMiss = middleMiss }
                }
                best = (low + high) / 2
                break
            }
            previousAngle = angle
            previousMiss = value
        }
        guard let angle = best else { return nil }

        let normal = Vector2(cos(angle), sin(angle))
        let bounce = normal * radius
        let coming = (bounce - from).length
        let going = (to - bounce).length
        guard coming + going > 0 else { return nil }
        let height = viewer.z * going / (coming + going)
        return Vector3(center.x + bounce.x, center.y + bounce.y, height)
    }
}

// MARK: - Angles

/// The turn from one angle to another, taken the short way, in `-pi...pi`.
private func shortestTurn(from: Double, to: Double) -> Double {
    var turn = (to - from).truncatingRemainder(dividingBy: 2 * .pi)
    if turn > .pi { turn -= 2 * .pi }
    if turn < -.pi { turn += 2 * .pi }
    return turn
}

/// The stretch of angle two arcs share, as absolute angles around the second
/// arc's middle. `nil` when they share nothing.
private func overlap(
    of first: (Double, Double),
    and second: (Double, Double)
) -> (Double, Double)? {
    let middle = (second.0 + second.1) / 2
    let firstMiddle = middle + shortestTurn(from: middle, to: (first.0 + first.1) / 2)
    let firstHalf = (first.1 - first.0) / 2
    let secondHalf = (second.1 - second.0) / 2
    let low = max(firstMiddle - firstHalf, middle - secondHalf)
    let high = min(firstMiddle + firstHalf, middle + secondHalf)
    guard high > low else { return nil }
    return (low, high)
}
