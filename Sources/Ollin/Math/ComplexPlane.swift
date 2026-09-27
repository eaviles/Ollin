import Foundation

/// The piece of the complex plane a picture shows, and where its points land.
///
/// Every generator that paints the plane (`.mandelbrot`, `.julia`,
/// `.orbitTrap`, `.domainColoring`, `.newton`) and the shader library's
/// `complexPlane` frame it the same way: `center` sits in the middle of the
/// picture, `span` units run across its shorter side (the longer side shows
/// more, so nothing stretches), and the imaginary axis rises up the picture,
/// as it is written on paper. A generator's `plane` is that framing as a value,
/// so a sketch can mark a root or a zero on the picture, read the number under
/// the pointer, or zoom toward it, without writing the arithmetic itself:
///
/// ```swift
/// let julia = Generator.julia(c: c, zoom: 2)
/// drawImage(generate(julia).image, 0, 0)
/// if let plane = julia.plane {
///     let z = plane.planePoint(at: mouse, in: bounds)            // the number under the pointer
///     drawCircle(center: plane.canvasPoint(of: c, in: bounds), radius: 6)
/// }
/// ```
///
/// `in:` is the rectangle the picture was drawn into, undistorted: the whole
/// canvas (`bounds`) for a full-canvas layer, or the tile a smaller layer was
/// drawn in. The generators take `zoom` rather than a span, and the two are one
/// rule: zoom 1 is 3 units across, so `span` is `3 / zoom`.
public struct ComplexPlane: Hashable, Sendable {

    /// The number in the middle of the picture.
    public var center: Vector2

    /// How many units of the plane the picture's shorter side shows.
    public var span: Double

    /// A framing by its span: `center` in the middle, `span` units across the
    /// shorter side, imaginary axis up. The default is the generators' own at
    /// zoom 1: the origin in the middle and 3 units across.
    public init(center: Vector2 = .zero, span: Double = 3) {
        self.center = center
        self.span = max(span, 1e-12)
    }

    /// A framing by a generator's `zoom`: zoom 1 shows 3 units across the
    /// shorter side, zoom 2 shows 1.5, and so on.
    public init(center: Vector2 = .zero, zoom: Double) {
        self.init(center: center, span: 3 / max(zoom, 1e-12))
    }

    /// The `zoom` a generator takes for this framing, `3 / span`.
    public var zoom: Double { 3 / span }

    /// The number under a canvas point, for a picture drawn undistorted in
    /// `rect`. A point outside the rectangle is read the same way, past the
    /// picture's edge.
    public func planePoint(at canvas: Vector2, in rect: Rectangle) -> Vector2 {
        let unit = span / max(min(rect.width, rect.height), 1e-12)
        let mid = rect.center
        return Vector2(center.x + (canvas.x - mid.x) * unit,
                       center.y - (canvas.y - mid.y) * unit)
    }

    /// Where a number lands on a picture drawn undistorted in `rect`. The
    /// imaginary axis rises, so a number above the real axis lands above the
    /// rectangle's middle.
    public func canvasPoint(of point: Vector2, in rect: Rectangle) -> Vector2 {
        let pixels = max(min(rect.width, rect.height), 1e-12) / span
        let mid = rect.center
        return Vector2(mid.x + (point.x - center.x) * pixels,
                       mid.y - (point.y - center.y) * pixels)
    }
}

extension Generator {

    /// The framing a complex-plane generator paints with, or `nil` for a
    /// generator that paints no plane (a checkerboard, a noise, a shader).
    ///
    /// The value is the generator's own `center` and `zoom`, after the clamps
    /// the factory applies, so a mark placed through it lands on the picture.
    public var plane: ComplexPlane? {
        switch kind {
        case let .escapeTime(_, _, _, _, center, zoom, _, _, _):
            return ComplexPlane(center: center, zoom: zoom)
        case let .orbitTrap(_, _, _, _, center, zoom, _, _, _):
            return ComplexPlane(center: center, zoom: zoom)
        case let .domainColoring(_, _, _, _, _, _, _, center, zoom, _):
            return ComplexPlane(center: center, zoom: zoom)
        case let .newton(_, _, _, _, _, center, zoom, _, _):
            return ComplexPlane(center: center, zoom: zoom)
        default:
            return nil
        }
    }
}
