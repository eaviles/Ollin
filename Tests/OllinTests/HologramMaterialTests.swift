@testable import Ollin
import Testing
import CoreGraphics
import Foundation
import COllinShaders

/// CPU checks on the hologram finish: the clamps, the packing, the rule that
/// no groove spacing is no grating, the preset, and the source writer.
@Suite
struct HologramMaterialTests {

    @Test func clampsAndPacks() {
        let m = Material(shading: .physicallyBased, hologram: 3, gratingSpacing: -5, gratingRotation: 0.4)
        #expect(m.hologram == 1)
        #expect(m.gratingSpacing == 0)
        #expect(m.gratingRotation == 0.4)
        let g = Material(shading: .physicallyBased, hologram: 0.5, gratingSpacing: 1600,
                         gratingRotation: .pi / 3).gpuMaterial()
        #expect(abs(g.grating.x - 0.5) < 1e-6)
        #expect(abs(g.grating.y - 1600) < 1e-3)
        #expect(abs(g.grating.z - Float(cos(Double.pi / 3))) < 1e-6)
        #expect(abs(g.grating.w - Float(sin(Double.pi / 3))) < 1e-6)
    }

    @Test func noSpacingShipsAsNoGrating() {
        // Grooves no distance apart are no grooves, so the strength is zeroed on
        // the way to the GPU: that zero is the shader's gate.
        let g = Material(shading: .physicallyBased, hologram: 1, gratingSpacing: 0).gpuMaterial()
        #expect(g.grating.x == 0)
        #expect(Material().gpuMaterial().grating.x == 0)
        #expect(Material.anodized.gpuMaterial().grating.x == 0)
    }

    @Test func thePresetIsAGratedMetal() {
        #expect(Material.hologram.shading == .physicallyBased)
        #expect(Material.hologram.metallic == 1)
        #expect(Material.hologram.hologram == 1 && Material.hologram.gratingSpacing == 1000)
        // The source writer names what differs from the defaults: the strength,
        // and not the spacing, which is the default 1,000.
        #expect(Material.hologram.swiftSource.contains("hologram: 1"))
        #expect(!Material.hologram.swiftSource.contains("gratingSpacing"))
        var disc = Material.hologram
        disc.gratingSpacing = 1600
        #expect(disc.swiftSource.contains("gratingSpacing: 1600"))
        #expect(!Material.anodized.swiftSource.contains("hologram"))
    }
}

/// Rendered probes for the hologram: that it is inert until asked for, that the
/// color at a point follows the grating equation (the three angles that put the
/// first order at blue, green, and red come back blue, green, and red), that the
/// hue walks one way as the light swings, and that turning the grooves a quarter
/// turn takes the rainbow out of the plane of the light.
@Suite
@MainActor
struct HologramRenderProbes {

    /// The mean color over a disc of the canvas, as three 0…255 channels.
    private func mean(_ image: CGImage, radius: Double, at center: (Double, Double) = (0.5, 0.5))
        -> SIMD3<Double> {
        let d = pixels(of: image)
        let w = image.width, h = image.height
        let cx = center.0 * Double(w), cy = center.1 * Double(h)
        let r = radius * Double(w)
        var sum = SIMD3<Double>(), count = 0.0
        for py in 0..<h {
            for px in 0..<w {
                let dx = Double(px) - cx, dy = Double(py) - cy
                guard dx * dx + dy * dy <= r * r else { continue }
                let i = (py * w + px) * 4
                sum += SIMD3(Double(d[i]), Double(d[i + 1]), Double(d[i + 2]))
                count += 1
            }
        }
        return sum / max(count, 1)
    }

    private func dominant(_ c: SIMD3<Double>) -> Int {
        var best = 0
        for i in 1...2 where c[i] > c[best] { best = i }
        return best
    }

    /// The light's tilt from the eye, in the groove direction, that puts the
    /// first order of `nm` at the middle of the plate: sin θ = λ / d.
    private func tilt(forFirstOrder nm: Double, spacing: Double) -> Double {
        asin(nm / spacing)
    }

    @Test(.enabled(if: Snapshot.hasMetal))
    func withoutAGratingTheSurfaceIsUntouched() throws {
        let plain = try OllinApp.image(of: HologramProbe.make(.plain, tilt: 0.55), frame: 1)
        let none = try OllinApp.image(of: HologramProbe.make(.strengthZero, tilt: 0.55), frame: 1)
        let flat = try OllinApp.image(of: HologramProbe.make(.spacingZero, tilt: 0.55), frame: 1)
        #expect(pixels(of: none) == pixels(of: plain))
        #expect(pixels(of: flat) == pixels(of: plain))
        // The gate can open: the grating is another picture.
        let grated = try OllinApp.image(of: HologramProbe.make(.grating(rotation: 0), tilt: 0.55), frame: 1)
        #expect(pixels(of: grated) != pixels(of: plain))
    }

    /// The grating equation at three angles: with the eye straight on, the
    /// light tilted by θ along the grooves sends first-order light of
    /// wavelength d · sin θ to the middle of the plate. Three tilts chosen for
    /// 450, 550, and 650 nm read as blue, green, and red.
    @Test(.enabled(if: Snapshot.hasMetal))
    func theColorFollowsTheGratingEquation() throws {
        let spacing = 1000.0
        var seen: [(Double, SIMD3<Double>)] = []
        for (nm, channel) in [(450.0, 2), (550.0, 1), (650.0, 0)] {
            let image = try OllinApp.image(of: HologramProbe.make(.grating(rotation: 0),
                                                                  tilt: tilt(forFirstOrder: nm, spacing: spacing)),
                                           frame: 1)
            let c = mean(image, radius: 0.04)
            seen.append((nm, c))
            #expect(c.max() > 40, "at \(nm) nm the plate is dark: \(c)")
            #expect(dominant(c) == channel, "at \(nm) nm the plate reads \(c), not the channel the grating equation picks")
        }
        print("grating equation at three angles: \(seen)")
    }

    /// As the light swings through the first order the hue walks one way,
    /// from violet through green to red, with no step back.
    @Test(.enabled(if: Snapshot.hasMetal))
    func theHueWalksOneWayWithTheAngle() throws {
        var hues: [Double] = []
        for nm in stride(from: 430.0, through: 650, by: 30) {
            let image = try OllinApp.image(of: HologramProbe.make(.grating(rotation: 0),
                                                                  tilt: tilt(forFirstOrder: nm, spacing: 1000)),
                                           frame: 1)
            let c = mean(image, radius: 0.04)
            let color = Color(red: c.x / 255, green: c.y / 255, blue: c.z / 255)
            #expect(color.saturation > 0.3, "at \(nm) nm the plate is not colored: \(c)")
            // A red that leans a hair toward magenta wraps to just under 1: read it
            // as just under 0 so the walk stays one line.
            hues.append(color.hue > 0.9 ? color.hue - 1 : color.hue)
        }
        // Hue on the wheel runs blue (about 0.67) down through green (0.33) to
        // red (0): the sequence must fall at every step.
        for i in 1..<hues.count {
            #expect(hues[i] < hues[i - 1], "the hue stepped back between samples \(i - 1) and \(i): \(hues)")
        }
        #expect(hues.first! > 0.55 && hues.last! < 0.08, "the sweep does not run violet to red: \(hues)")
    }

    /// Turning the grooves a quarter turn puts the rainbow across the plane
    /// the light swings in, so the same geometry reads as plain metal.
    @Test(.enabled(if: Snapshot.hasMetal))
    func turningTheGroovesTurnsTheRainbowAway() throws {
        let t = tilt(forFirstOrder: 550, spacing: 1000)
        let along = mean(try OllinApp.image(of: HologramProbe.make(.grating(rotation: 0), tilt: t), frame: 1),
                         radius: 0.04)
        let across = mean(try OllinApp.image(of: HologramProbe.make(.grating(rotation: .pi / 2), tilt: t), frame: 1),
                          radius: 0.04)
        #expect(along.max() - along.min() > 40, "the grating along the light is not colored: \(along)")
        #expect(across.max() - across.min() < 6, "the grating across the light should read gray: \(across)")
        // A half turn is the same grating again.
        let back = mean(try OllinApp.image(of: HologramProbe.make(.grating(rotation: .pi), tilt: t), frame: 1),
                        radius: 0.04)
        #expect(abs(back.x - along.x) + abs(back.y - along.y) + abs(back.z - along.z) < 6)
    }

    /// A crumpled normal map turns the grooves with every facet, so one light
    /// and one angle give many colors across the plate, where the flat plate
    /// gives one.
    @Test(.enabled(if: Snapshot.hasMetal))
    func aCrumpledMapBreaksTheRainbowIntoFacets() throws {
        let t = tilt(forFirstOrder: 550, spacing: 1000)
        func spread(_ image: CGImage) -> Double {
            // The hue spread over a grid of samples across the plate's middle.
            var hues: [Double] = []
            for i in 0..<6 {
                for j in 0..<6 {
                    let c = mean(image, radius: 0.012, at: (0.3 + 0.08 * Double(i), 0.3 + 0.08 * Double(j)))
                    let color = Color(red: c.x / 255, green: c.y / 255, blue: c.z / 255)
                    if color.saturation > 0.25 && color.brightness > 0.15 { hues.append(color.hue) }
                }
            }
            guard hues.count > 4 else { return 0 }
            return (hues.max() ?? 0) - (hues.min() ?? 0)
        }
        let flat = spread(try OllinApp.image(of: HologramProbe.make(.grating(rotation: 0), tilt: t), frame: 1))
        let crumpled = spread(try OllinApp.image(of: HologramProbe.make(.crumpled, tilt: t), frame: 1))
        #expect(flat < 0.12, "the flat plate should be close to one hue: spread \(flat)")
        #expect(crumpled > 0.3, "the crumpled plate should show many hues: spread \(crumpled)")
    }
}

/// The probe scene: a plate square to the camera, lit by one white directional
/// light tilted by `tilt` radians from the eye within the plane of the grooves
/// (the plate's x axis), with no environment, so the middle of the plate is
/// the surface's own answer to one known geometry.
private final class HologramProbe: Sketch {
    enum Kind: Equatable {
        case plain
        case strengthZero
        case spacingZero
        case grating(rotation: Double)
        case crumpled
    }

    var kind: Kind = .plain
    var tilt = 0.0
    private var crumple: Image?

    static func make(_ kind: Kind, tilt: Double) -> HologramProbe {
        let probe = HologramProbe()
        probe.kind = kind
        probe.tilt = tilt
        return probe
    }

    override var canvasSize: CanvasSize { .square(192) }

    override func setup() {
        guard kind == .crumpled else { return }
        // A sheet of flat facets as a green-up normal map, from a FacetField.
        let size = 256
        let field = FacetField.crumpled(in: Rectangle(x: 0, y: 0, width: Double(size), height: Double(size)),
                                        spacing: 40, crinkle: 1.0, seed: 5)
        var bytes = [UInt8](repeating: 255, count: size * size * 4)
        for y in 0..<size {
            for x in 0..<size {
                let p = Vector2(Double(x) + 0.5, Double(y) + 0.5)
                var n = Vector3(0, 0, 1)
                if let f = field.facet(containing: p) { n = f.normal }
                let i = (y * size + x) * 4
                bytes[i] = UInt8((n.x * 0.5 + 0.5) * 255)
                bytes[i + 1] = UInt8((n.y * 0.5 + 0.5) * 255)
                bytes[i + 2] = UInt8((n.z * 0.5 + 0.5) * 255)
            }
        }
        crumple = Image(width: size, height: size, premultipliedRGBA: bytes)
    }

    override func draw() {
        background(Color(white: 0.02))
        // The eye far back behind a narrow field, so the view direction is nearly
        // the same across the whole plate and one tilt means one geometry.
        camera(.orbiting(target: .zero, radius: 60, azimuth: 0, elevation: 0,
                         fieldOfView: 0.062, near: 1, far: 200))
        // The light toward the eye, tilted along the plate's x axis: the half
        // vector sum's component along the grooves is then sin(tilt) everywhere.
        directionalLight(.white, direction: Vector3(-sin(tilt), 0, -cos(tilt)), intensity: 1.0)
        fill(Color(white: 0.8))
        material(finish())
        rotateX(.pi / 2)
        if kind == .crumpled, let crumple {
            drawMesh(Mesh.plane(width: 3.2, depth: 3.2).normalMapped(crumple, scale: 1))
        } else {
            drawPlane(width: 3.2, depth: 3.2)
        }
    }

    private func finish() -> Material {
        let metal = Material(shading: .physicallyBased, metallic: 1, roughness: 0.3)
        switch kind {
        case .plain:
            return metal
        case .strengthZero:
            var m = metal; m.gratingSpacing = 1000; return m
        case .spacingZero:
            var m = metal; m.hologram = 1; m.gratingSpacing = 0; return m
        case .grating(let rotation):
            var m = metal; m.hologram = 1; m.gratingSpacing = 1000; m.gratingRotation = rotation; return m
        case .crumpled:
            var m = metal; m.hologram = 1; m.gratingSpacing = 1000; return m
        }
    }
}
