import Foundation

// Slopes of any function a sketch writes, by central differences: the
// function read a small step to either side, and the rise divided by the run.
// The error falls with the square of the step, so the result is exact for any
// quadratic and close for anything smooth; a step much smaller than the
// automatic one loses digits to rounding instead.

/// How fast `function` changes at `x`: its slope there, read by central
/// differences.
///
/// ```swift
/// let speed = derivative(at: t) { t in Easing.easeInOut(t) }
/// let tilt = atan(derivative(at: x) { x in 200 * sin(x * 0.01) })   // a curve's angle
/// ```
///
/// - Parameters:
///   - x: where to read the slope.
///   - step: how far to either side to read. Leave it `nil` for a step sized
///     from `x` itself (about six millionths of its magnitude, or of 1 near
///     zero), which suits a smooth function computed in `Double`. Give a larger
///     one for a function with fine grain of its own (noise over many octaves,
///     a sampled image), at about the size of the detail to ignore. A step of
///     zero or less takes the automatic one.
///   - function: the function to differentiate.
public func derivative(at x: Double, step: Double? = nil,
                       function: (Double) -> Double) -> Double {
    let h = differenceStep(step, scale: abs(x))
    // Divided by the run the coordinates actually hold, so a step that rounds
    // on the way in is divided by the distance it really covers.
    let ahead = x + h, behind = x - h
    return (function(ahead) - function(behind)) / (ahead - behind)
}

/// The direction a field over the plane climbs fastest at `point`, its length
/// the rate of that climb, read by central differences along each axis.
///
/// The perpendicular runs along the field's contour, so a particle can climb a
/// hill of noise or circle on it:
///
/// ```swift
/// let uphill = gradient(at: p) { q in noise(q.x * 0.004, q.y * 0.004) }
/// p += uphill.perpendicular.normalized * 1.5
/// ```
///
/// `step` works as in `derivative(at:step:function:)`, sized from the larger of
/// the point's two coordinates when left `nil`. It is the same step on both
/// axes, so the field is read at four points.
public func gradient(at point: Vector2, step: Double? = nil,
                     field: (Vector2) -> Double) -> Vector2 {
    let h = differenceStep(step, scale: Swift.max(abs(point.x), abs(point.y)))
    let right = point.x + h, left = point.x - h
    let down = point.y + h, up = point.y - h
    return Vector2((field(Vector2(right, point.y)) - field(Vector2(left, point.y))) / (right - left),
                   (field(Vector2(point.x, down)) - field(Vector2(point.x, up))) / (down - up))
}

/// The direction a field over space climbs fastest at `point`, its length the
/// rate of that climb, read by central differences along each axis: the
/// normal of an implicit surface, or the push down a potential. The field is
/// read at six points; `step` works as in the plane's form.
///
/// ```swift
/// let normal = gradient(at: hit) { q in sdf(q) }.normalized
/// ```
public func gradient(at point: Vector3, step: Double? = nil,
                     field: (Vector3) -> Double) -> Vector3 {
    let h = differenceStep(step, scale: Swift.max(abs(point.x), abs(point.y), abs(point.z)))
    let (x, y, z) = (point.x, point.y, point.z)
    let right = x + h, left = x - h
    let down = y + h, up = y - h
    let far = z + h, near = z - h
    return Vector3((field(Vector3(right, y, z)) - field(Vector3(left, y, z))) / (right - left),
                   (field(Vector3(x, down, z)) - field(Vector3(x, up, z))) / (down - up),
                   (field(Vector3(x, y, far)) - field(Vector3(x, y, near))) / (far - near))
}

/// The step a central difference takes: the one asked for, or the cube root of
/// the machine epsilon times the magnitude being differentiated at (at least
/// 1), which balances the truncation error, falling with the step squared,
/// against rounding, which grows as the step shrinks.
private func differenceStep(_ asked: Double?, scale: Double) -> Double {
    if let asked, asked > 0, asked.isFinite { return asked }
    let scale = scale.isFinite ? Swift.max(scale, 1) : 1
    return Foundation.cbrt(Double.ulpOfOne) * scale
}
