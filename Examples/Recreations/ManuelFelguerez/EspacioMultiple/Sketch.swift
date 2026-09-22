//  Recreation after Manuel Felguerez - "El espacio multiple" (Museo de Arte
//  Moderno, Mexico City, December 1973 to February 1974): a small vocabulary
//  of forms cut from the circle, the triangle and the square, carried by
//  successive combinations from the painting to the relief to the free-standing
//  piece. A homage, not a reproduction, and not affiliated with or endorsed by
//  the artist or his estate.
//  https://libros.uanl.mx/index.php/u/catalog/book/3
//
//  An original Ollin interpretation, written from the work (the 1973 pairs of
//  ink drawing and acrylic in the catalog, the paintings of 1979, the reliefs
//  and maquettes of 1970 to 1975) and from his own account of the method.
//  Nothing was ported. The form-idea below is a reading of his vocabulary,
//  not one of his designs.

import Foundation
import Ollin

/// "El espacio multiple" (Manuel Felguerez, 1973): one form-idea, three states.
///
/// His recipe, in his own order. Start from a few simple geometric concepts,
/// the circle, the triangle, the square, and organize them into a form-idea.
/// Draw it in pencil and give it an order. Think of silver and surround it
/// with a few cold colors, or of gold and surround it with warm ones; give the
/// color an order too, and paint the drawing as a design made of planes. Every
/// plane holds infinitely many volumes: choose one and make a relief, and the
/// color takes that dimension with it. Then take the volume out into space,
/// and show that painting, relief and sculpture were never three things.
///
/// So this sketch keeps one vocabulary (a square with rounded corners, which
/// is the circle and the square at once; a rectangle; a disk; a half disk; and
/// a right triangle, which brings the diagonal) and one form-idea built from
/// it: a large rounded square with a displaced twin under it, a band crossing
/// it that ends in a half disk, a disk, and triangles cut into the corners.
/// What changes with `variation`, and from one cycle to the next, is the
/// combination: which plane wears which color of the silver or the gold
/// scheme, where the twin is displaced to, which row the band takes and which
/// way it leaves, which corners the triangles cut, and how tall each plane
/// stands.
///
/// The default run is the cycle. The painting; the planes rising into a
/// relief under a light that rakes across it; the relief coming apart into a
/// standing piece, where the sheet becomes the floor, the square and the disk
/// stand on it, the band becomes a shelf through the square and the
/// displacement becomes depth; and back down. A new combination arrives with
/// each cycle. `stage` holds one state still: `painting` is the flat design
/// (`--export-svg` gives the plan), `relief` the wall seen straight on with
/// the raking light circling, `sculpture` the piece on its floor with the
/// camera walking round. `depth` is how far the relief stands off the wall.
/// `unlit` turns the lights off, which is the demonstration: the relief seen
/// straight on with no light is the painting again.
@main
final class EspacioMultiple: Sketch {
    enum Stage: String, CaseIterable, ParamOption { case cycle, painting, relief, sculpture }

    @Param(icon: "square.stack.3d.up") var stage = Stage.cycle
    @Param(8 ... 60, icon: "clock") var seconds = 24.0
    @Param(0.3 ... 2.5, icon: "arrow.up.and.down") var depth = 1.0
    @Param(icon: "lightbulb.slash") var unlit = false

    /// The sheet is 36 by 30, the size in centimeters of the 1973 acrylics,
    /// and every measure below is in centimeters on it.
    private let sheet = Vector2(36, 30)

    override var canvasSize: CanvasSize { .size(1296, 1080) }
    /// One cycle is one lap: the fold ends flat, where the painting began.
    override var loopDuration: Double? { max(4.0, seconds) }

    // MARK: The vocabulary

    private enum Form { case square, rectangle, disk, halfDisk, triangle }

    /// One plane of the design: an outline about its own center, and what it
    /// becomes in the other two states.
    private struct Plane {
        var form: Form
        /// Sheet centimeters, y down, about `center`.
        var outline: [Vector2]
        var center: Vector2
        var color: Color
        var material = Material.matte
        /// How much higher its top stands than the plane painted before it.
        var step = 0.0
        /// The sheet and the field keep their own thickness whatever `depth` is.
        var base = false
        /// Its own thickness once it stands free.
        var thickness = 1.0
        /// In the piece: standing on the floor, or lying on it.
        var stands = false
        /// A lying plane's center height; a standing plane's foot, in z.
        var lift = 0.0
        var footZ = 0.0
    }

    private struct Combination {
        var planes: [Plane] = []
        var wall = Color(white: 0.45)
    }

    private var combination = Combination()
    private var onCycle = -1

    // MARK: Drawing

    override func draw() {
        let period = max(4.0, seconds)
        let cycle = stage == .cycle ? Int(floor(time / period)) : 0
        if cycle != onCycle {
            combination = combine(cycle)
            onCycle = cycle
        }
        let u = (time - Double(cycle) * period) / period

        // Where the run is: the heights (rise) and how far the piece has come
        // apart (free), each 0 to 1.
        var rise = 1.0, free = 0.0
        switch stage {
        case .painting:
            paintFlat()
            return
        case .relief:
            rise = 1; free = 0
        case .sculpture:
            rise = 1; free = 1
        case .cycle:
            if u < 0.125 { paintFlat(); return }
            rise = u < 0.25 ? ease((u - 0.125) / 0.125) : u < 0.95 ? 1 : 1 - ease((u - 0.95) / 0.05)
            free = u < 0.5 ? 0 : u < 0.625 ? ease((u - 0.5) / 0.125) : u < 0.875 ? 1 : 1 - ease((u - 0.875) / 0.075)
        }

        background(combination.wall)
        placeCamera(free: free, period: period)
        light(rise: rise, free: free, period: period)

        var top = 0.0
        for plane in combination.planes {
            top += plane.base ? plane.step : plane.step * depth

            // The relief: a slab from the wall up to its top. The piece: its own
            // thickness, standing at its foot or lying at its height.
            let local = Vector2(plane.center.x - sheet.x / 2, sheet.y / 2 - plane.center.y)
            let reliefDepth = max(0.02, top * rise)
            let reliefAt = Vector3(local.x, local.y, reliefDepth / 2)

            let freeDepth = plane.thickness
            let freeAt: Vector3
            var tilt = 0.0
            if plane.stands {
                freeAt = Vector3(local.x, 1.2 + halfHeight(of: plane), plane.footZ)
            } else {
                freeAt = Vector3(local.x, plane.lift, plane.footZ == 0 ? -local.y : plane.footZ)
                tilt = -.pi / 2
            }

            let e = ease(free)
            let at = reliefAt + (freeAt - reliefAt) * e
            let slab = reliefDepth + (freeDepth - reliefDepth) * e

            withState {
                translate(at.x, at.y, at.z)
                if tilt != 0 { rotateX(tilt * e) }
                fill(plane.color)
                material(plane.material)
                drawExtrude(raised(plane.outline), depth: slab)
            }
        }
    }

    /// The design as painted: every plane flat, in paint order.
    private func paintFlat() {
        background(combination.wall)
        noStroke()
        let unit = self.unit
        let origin = Vector2((width - sheet.x * unit) / 2, (height - sheet.y * unit) / 2)
        for plane in combination.planes {
            fill(plane.color)
            drawPolygon(plane.outline.map { origin + (plane.center + $0) * unit })
        }
    }

    /// Pixels per centimeter, the sheet filling most of the canvas.
    private var unit: Double { min(width * 0.86 / sheet.x, height * 0.86 / sheet.y) }

    private func placeCamera(free: Double, period: Double) {
        // Straight on, the sheet framed as the painting frames it: an
        // orthographic wall view for the relief, and in the cycle a long lens
        // at a distance, which frames a flat sheet the same way.
        let framed = height / unit
        // The shadow map is boxed to the eye's distance, so the eye stays as
        // near as the sheet's own size allows and the map's texels stay fine.
        if stage == .relief {
            ortho(eye: Vector3(0, 0, 25), target: .zero, height: framed)
            return
        }
        let distance = 55.0
        let straight = Vector3(0, 0, distance)
        let narrow = 2 * atan((framed / 2) / distance)

        // Walking round the piece.
        let around = time * 2 * .pi / period * 0.5
        let orbitTarget = Vector3(0, 5.5, 0)
        let orbit = orbitTarget + Vector3(cos(around) * 0.95, 0.31, sin(around) * 0.95) * 60

        let e = ease(free)
        let eye = straight + (orbit - straight) * e
        let target = orbitTarget * e
        perspective(eye: eye, target: target, fieldOfView: narrow + (0.55 - narrow) * e)
    }

    private func light(rise: Double, free: Double, period: Double) {
        if unlit {
            noLights()
            return
        }
        // Flat and full while the planes are still a painting, and a key that
        // arrives as they rise: raking across the wall, circling once a cycle,
        // then from above once the piece stands free.
        let lit = ease(rise)
        ambientLight(Color(white: 1 - 0.58 * lit))
        let rake = time * 2 * .pi / period
        let grazing = 0.5
        let acrossTheWall = Vector3(-cos(rake) * cos(grazing), -sin(rake) * cos(grazing), -sin(grazing))
        let fromAbove = Vector3(-0.45, -0.8, -0.4).normalized
        let e = ease(free)
        let direction = (acrossTheWall + (fromAbove - acrossTheWall) * e).normalized
        directionalLight(.white, direction: direction, intensity: lit)
        directionalLight(Color(white: 0.6), direction: (Vector3(0, -0.3, -0.4) - direction).normalized,
                         intensity: 0.22 * lit, castsShadow: false)
        if lit > 0.02 {
            castShadows()
            shadowSoftness(0.65)
        }
    }

    // MARK: Combining

    /// One combination of the form-idea: the scheme, the colors handed out,
    /// the twin's displacement, the band's row and exit, the corners, and the
    /// volume each plane chooses.
    private func combine(_ index: Int) -> Combination {
        randomSeed(variation &* 7919 &+ index &* 104_729)

        let silver = random(0, 1) < 0.5
        let metal = silver
            ? Color(red: 0.76, green: 0.77, blue: 0.78)
            : Color(red: 0.80, green: 0.64, blue: 0.30)
        // Silver among a few cold colors, or gold among warm ones, his own
        // rule for the color's order. The darkest is the ground; the rest are
        // dealt out without repeats.
        var palette = silver
            ? [Color(red: 0.16, green: 0.30, blue: 0.56), Color(red: 0.36, green: 0.44, blue: 0.58),
               Color(red: 0.44, green: 0.36, blue: 0.56), Color(red: 0.55, green: 0.66, blue: 0.72),
               Color(red: 0.22, green: 0.40, blue: 0.42), Color(red: 0.60, green: 0.68, blue: 0.62),
               Color(red: 0.13, green: 0.16, blue: 0.24)]
            : [Color(red: 0.80, green: 0.31, blue: 0.16), Color(red: 0.86, green: 0.16, blue: 0.14),
               Color(red: 0.93, green: 0.52, blue: 0.16), Color(red: 0.62, green: 0.45, blue: 0.28),
               Color(red: 0.90, green: 0.82, blue: 0.66), Color(red: 0.55, green: 0.12, blue: 0.20),
               Color(red: 0.32, green: 0.20, blue: 0.14)]
        let ground = palette.removeLast()
        let whole = palette
        func deal() -> Color {
            if palette.isEmpty { palette = whole }
            let pick = Int(random(0, Double(palette.count)))
            return palette.remove(at: min(pick, palette.count - 1))
        }

        var c = Combination()
        c.wall = silver ? Color(red: 0.40, green: 0.42, blue: 0.45) : Color(red: 0.42, green: 0.38, blue: 0.34)
        let paper = silver ? Color(red: 0.86, green: 0.87, blue: 0.88) : Color(red: 0.86, green: 0.83, blue: 0.78)

        // The sheet, then the field inside its margin. Both lie down in the
        // piece and become its floor.
        let margin = 2.5
        let field = Rectangle(x: margin, y: margin, width: sheet.x - 2 * margin, height: sheet.y - 2 * margin)
        c.planes.append(Plane(form: .rectangle, outline: rectangle(sheet.x, sheet.y), center: sheet / 2,
                              color: paper, step: 0.6, base: true, thickness: 0.6, lift: 0.3))
        c.planes.append(Plane(form: .rectangle, outline: rectangle(field.width, field.height), center: field.center,
                              color: ground, step: 0.6, base: true, thickness: 0.6, lift: 0.9))

        // The square with rounded corners, and its twin displaced along a
        // diagonal, painted first so it shows as a shadow of the square.
        let side = snap(random(15, 19)), radius = snap(random(2.5, 4))
        let square = Vector2(snap(random(field.corner.x + side / 2 + 5, field.corner.x + field.width - side / 2 - 5)),
                             snap(random(field.corner.y + side / 2 + 1, field.corner.y + field.height - side / 2 - 1)))
        let shift = snap(random(1.2, 2.2))
        let twin = square + Vector2(random(0, 1) < 0.5 ? shift : -shift, random(0, 1) < 0.5 ? shift : -shift)
        let foot = -(sheet.y / 2 - square.y) + side / 2
        c.planes.append(Plane(form: .square, outline: roundedSquare(side, radius: radius), center: twin,
                              color: deal(), step: random(0.7, 1.6), stands: true,
                              footZ: -(sheet.y / 2 - twin.y) + side / 2))
        c.planes.append(Plane(form: .square, outline: roundedSquare(side, radius: radius), center: square,
                              color: metal, material: .plastic, step: random(0.7, 1.6), stands: true, footZ: foot))

        // The band, from the field's edge across the square and out the other
        // side, ending in a half disk. In the piece it lies as a shelf through
        // the standing square, at the height it crossed.
        let bandHeight = snap(random(3, 4.5))
        let row = square.y + (random(0, 1) < 0.5 ? -1 : 1) * snap(random(0.3, 0.6) * (side / 2 - radius))
        let exitsRight = random(0, 1) < 0.5
        let reach = snap(random(2, exitsRight
            ? field.corner.x + field.width - bandHeight / 2 - (square.x + side / 2)
            : (square.x - side / 2) - (field.corner.x + bandHeight / 2)))
        let x0 = exitsRight ? field.corner.x : square.x - side / 2 - reach
        let x1 = exitsRight ? square.x + side / 2 + reach : field.corner.x + field.width
        let bandColor = deal()
        let crossing = 1.2 + (square.y + side / 2 - row)
        c.planes.append(Plane(form: .rectangle, outline: rectangle(x1 - x0, bandHeight),
                              center: Vector2((x0 + x1) / 2, row), color: bandColor,
                              step: random(0.7, 1.6), lift: crossing, footZ: foot))
        c.planes.append(Plane(form: .halfDisk, outline: halfDisk(bandHeight / 2, facing: exitsRight ? 1 : -1),
                              center: Vector2(exitsRight ? x1 : x0, row), color: bandColor,
                              lift: crossing, footZ: foot))

        // Triangles cut into two of the field's corners, lying as ramps in the
        // piece.
        var corners = [0, 1, 2, 3]
        for _ in 0 ..< 2 {
            let corner = corners.remove(at: Int(random(0, Double(corners.count))) % corners.count)
            let size = snap(random(4, 7))
            let (outline, center) = cornerTriangle(size, corner: corner, in: field)
            c.planes.append(Plane(form: .triangle, outline: outline, center: center, color: deal(),
                                  step: random(0.7, 1.6), lift: 1.2 + 0.5))
        }

        // The disk, in a corner of the field, standing on the floor in the piece.
        let radiusDisk = snap(random(2, 3))
        let corner = corners[Int(random(0, 2)) % 2]
        let inset = radiusDisk + 1.5
        let disk = Vector2(corner % 2 == 0 ? field.corner.x + inset : field.corner.x + field.width - inset,
                           corner < 2 ? field.corner.y + inset : field.corner.y + field.height - inset)
        c.planes.append(Plane(form: .disk, outline: self.disk(radiusDisk), center: disk, color: deal(),
                              step: random(0.7, 1.6), stands: true,
                              footZ: -(sheet.y / 2 - disk.y) + radiusDisk))

        // Now and then a small block beside the disk.
        if random(0, 1) < 0.5 {
            let block = disk + Vector2(corner % 2 == 0 ? radiusDisk + 2.5 : -(radiusDisk + 2.5), 0)
            c.planes.append(Plane(form: .rectangle, outline: rectangle(2.5, 2.5), center: block, color: deal(),
                                  step: random(0.7, 1.6), stands: true,
                                  footZ: -(sheet.y / 2 - block.y) + 1.25))
        }
        return c
    }

    // MARK: Outlines, about their own center, y down

    private func rectangle(_ w: Double, _ h: Double) -> [Vector2] {
        [Vector2(-w / 2, -h / 2), Vector2(w / 2, -h / 2), Vector2(w / 2, h / 2), Vector2(-w / 2, h / 2)]
    }

    private func roundedSquare(_ side: Double, radius: Double) -> [Vector2] {
        let inner = side / 2 - radius
        var points: [Vector2] = []
        for corner in 0 ..< 4 {
            let at = Vector2(corner == 1 || corner == 2 ? inner : -inner, corner >= 2 ? inner : -inner)
            let start = Double(corner) * .pi / 2 - .pi
            for step in 0 ... 10 {
                let angle = start + .pi / 2 * Double(step) / 10
                points.append(at + Vector2(cos(angle), sin(angle)) * radius)
            }
        }
        return points
    }

    private func disk(_ radius: Double) -> [Vector2] {
        (0 ..< 48).map { Vector2(cos(Double($0) / 48 * 2 * .pi), sin(Double($0) / 48 * 2 * .pi)) * radius }
    }

    /// A half disk whose flat side sits on its center, bulging toward `facing`.
    private func halfDisk(_ radius: Double, facing: Double) -> [Vector2] {
        (0 ... 24).map { step in
            let angle = -.pi / 2 + .pi * Double(step) / 24
            return Vector2(cos(angle) * facing, sin(angle)) * radius
        }
    }

    /// A right triangle in one corner of the field: 0 top-left, 1 top-right,
    /// 2 bottom-left, 3 bottom-right.
    private func cornerTriangle(_ size: Double, corner: Int, in field: Rectangle) -> ([Vector2], Vector2) {
        let sx = corner % 2 == 0 ? 1.0 : -1.0, sy = corner < 2 ? 1.0 : -1.0
        let apex = Vector2(corner % 2 == 0 ? field.corner.x : field.corner.x + field.width,
                           corner < 2 ? field.corner.y : field.corner.y + field.height)
        let center = apex + Vector2(sx, sy) * (size / 3)
        let points = [apex, apex + Vector2(sx * size, 0), apex + Vector2(0, sy * size)]
        return (points.map { $0 - center }, center)
    }

    /// The same outline in the 3D plane: y up, wound counter-clockwise.
    private func raised(_ outline: [Vector2]) -> [Vector2] {
        let flipped = outline.map { Vector2($0.x, -$0.y) }
        var area = 0.0
        for i in flipped.indices {
            let a = flipped[i], b = flipped[(i + 1) % flipped.count]
            area += a.x * b.y - b.x * a.y
        }
        return area < 0 ? flipped.reversed() : flipped
    }

    private func halfHeight(of plane: Plane) -> Double {
        let ys = plane.outline.map(\.y)
        return ((ys.max() ?? 0) - (ys.min() ?? 0)) / 2
    }

    private func snap(_ value: Double) -> Double { (value * 2).rounded() / 2 }

    private func ease(_ t: Double) -> Double {
        let x = min(1, max(0, t))
        return x * x * (3 - 2 * x)
    }
}
