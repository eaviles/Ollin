@testable import Ollin
import Testing
import Foundation

/// CPU checks on the IES photometric-profile parser and sampler: the LM-63
/// tokenized read (header fields, TILT handling, candela ordering), the
/// lateral-symmetry folds, normalization, the GPU bake, and how a profiled
/// or cookied light packs its shaping slots. No Metal device, so these run
/// in CI. All fixtures are authored here (our own data, not manufacturer
/// files).
@Suite
struct IESProfileTests {

    private func close(_ a: Double, _ b: Double, _ eps: Double = 1e-9) -> Bool { abs(a - b) <= eps }

    private func deg(_ d: Double) -> Double { d * .pi / 180 }

    /// An axially-symmetric downlight: peak 1000 on axis, dark past 90°.
    private let axial = """
    IESNA:LM-63-2002
    [TEST] Ollin authored fixture
    [MANUFAC] Ollin
    TILT=NONE
    1 1000 1 4 1 1 2 0.1 0.1 0.1
    1.0 1.0 100
    0 30 60 90
    0
    1000 800 300 0
    """

    /// A 2x2 grid with distinct values pinning the candela ordering:
    /// one block per horizontal angle, vertical varying fastest.
    private let ordered = """
    IESNA:LM-63-2002
    TILT=NONE
    1 1000 1 2 2 1 2 0.1 0.1 0.1
    1.0 1.0 100
    0 90
    0 180
    10 20
    30 40
    """

    // MARK: - Parsing

    @Test func parsesAndNormalizesAnAxialFile() throws {
        let p = try #require(IESProfile(string: axial))
        #expect(p.symmetry == .axial)
        #expect(p.verticalAngles == [0, 30, 60, 90])
        // Normalized to peak 1, sampled at the measured angles.
        #expect(close(p.intensity(vertical: 0), 1.0))
        #expect(close(p.intensity(vertical: deg(30)), 0.8))
        #expect(close(p.intensity(vertical: deg(60)), 0.3))
        // Midway between measured angles interpolates linearly.
        #expect(close(p.intensity(vertical: deg(45)), 0.55, 1e-6))
        // Beyond the measured range the fixture emits nothing.
        #expect(p.intensity(vertical: deg(135)) == 0)
        // Azimuth is irrelevant under axial symmetry.
        #expect(close(p.intensity(vertical: deg(30), horizontal: deg(123)), 0.8))
    }

    @Test func candelaBlocksArePerHorizontalAngle() throws {
        let p = try #require(IESProfile(string: ordered))
        // values[h][v], normalized by the peak 40.
        #expect(close(p.intensity(vertical: 0, horizontal: 0), 0.25))
        #expect(close(p.intensity(vertical: deg(90), horizontal: 0), 0.5))
        #expect(close(p.intensity(vertical: 0, horizontal: deg(180)), 0.75))
        #expect(close(p.intensity(vertical: deg(90), horizontal: deg(180)), 1.0))
    }

    @Test func tiltIncludeBlockIsConsumed() throws {
        let tilted = """
        IESNA:LM-63-1995
        TILT=INCLUDE
        1
        2
        0 90
        1.0 0.9
        1 1000 1 2 1 1 2 0.1 0.1 0.1
        1.0 1.0 100
        0 90
        0
        500 1000
        """
        let p = try #require(IESProfile(string: tilted))
        #expect(close(p.intensity(vertical: 0), 0.5))
        #expect(close(p.intensity(vertical: deg(90)), 1.0))
    }

    @Test func commasAndLooseLinesParse() throws {
        // Real files break the 132-column rule and sprinkle commas; the
        // tokenizer shrugs.
        let loose = """
        IESNA:LM-63-2002
        TILT=NONE
        1 1000 1
        4 1 1 2
        0.1 0.1 0.1 1.0 1.0 100
        0, 30, 60, 90
        0
        1000, 800,
        300, 0
        """
        let p = try #require(IESProfile(string: loose))
        #expect(close(p.intensity(vertical: deg(30)), 0.8))
    }

    @Test func malformedFilesFailWithoutTrapping() {
        #expect(IESProfile(string: "not an ies file") == nil)          // no TILT
        #expect(IESProfile(string: axial.replacingOccurrences(of: "1000 800 300 0",
                                                              with: "1000 800")) == nil)  // truncated
        #expect(IESProfile(string: axial.replacingOccurrences(of: "4 1 1 2",
                                                              with: "4 1 2 2")) == nil)   // Type B
        #expect(IESProfile(string: axial.replacingOccurrences(of: "1000 800 300 0",
                                                              with: "1000 800 x 0")) == nil)  // non-numeric
        #expect(IESProfile(string: axial.replacingOccurrences(of: "0 30 60 90",
                                                              with: "0 60 30 90")) == nil)    // not ascending
        #expect(IESProfile(string: axial.replacingOccurrences(of: "4 1 1 2",
                                                              with: "4e20 1 1 2")) == nil)    // absurd count
        #expect(IESProfile(string: "") == nil)
    }

    // MARK: - Symmetry folds

    /// Quadrant symmetry (horizontal angles 0-90): every quadrant mirrors
    /// the first.
    @Test func quadrantSymmetryFoldsAllFourWays() throws {
        let quadrant = """
        IESNA:LM-63-2002
        TILT=NONE
        1 1000 1 2 3 1 2 0.1 0.1 0.1
        1.0 1.0 100
        0 90
        0 45 90
        100 200
        100 400
        100 800
        """
        let p = try #require(IESProfile(string: quadrant))
        #expect(p.symmetry == .quadrant)
        let v = deg(90)
        let at45 = p.intensity(vertical: v, horizontal: deg(45))
        #expect(close(at45, 0.5))
        // 135°, 225°, 315° all fold onto 45°.
        #expect(close(p.intensity(vertical: v, horizontal: deg(135)), at45))
        #expect(close(p.intensity(vertical: v, horizontal: deg(225)), at45))
        #expect(close(p.intensity(vertical: v, horizontal: deg(315)), at45))
        // 180° folds onto 0°.
        #expect(close(p.intensity(vertical: v, horizontal: deg(180)),
                      p.intensity(vertical: v, horizontal: 0)))
    }

    /// Bilateral symmetry (0-180): the far half mirrors across the 0-180 plane.
    @Test func bilateralSymmetryMirrors() throws {
        let bilateral = """
        IESNA:LM-63-2002
        TILT=NONE
        1 1000 1 2 3 1 2 0.1 0.1 0.1
        1.0 1.0 100
        0 90
        0 90 180
        100 200
        100 400
        100 800
        """
        let p = try #require(IESProfile(string: bilateral))
        #expect(p.symmetry == .bilateral)
        let v = deg(90)
        // 270° mirrors onto 90°.
        #expect(close(p.intensity(vertical: v, horizontal: deg(270)),
                      p.intensity(vertical: v, horizontal: deg(90))))
        // 350° mirrors onto 10°.
        #expect(close(p.intensity(vertical: v, horizontal: deg(350)),
                      p.intensity(vertical: v, horizontal: deg(10))))
    }

    /// The rare 90-270 lateral case mirrors across the 90-270 plane.
    @Test func bilateral90SymmetryMirrors() throws {
        let lateral = """
        IESNA:LM-63-2002
        TILT=NONE
        1 1000 1 2 3 1 2 0.1 0.1 0.1
        1.0 1.0 100
        0 90
        90 180 270
        100 200
        100 400
        100 800
        """
        let p = try #require(IESProfile(string: lateral))
        #expect(p.symmetry == .bilateral90)
        let v = deg(90)
        // 0° reflects to 180°, 45° to 135°.
        #expect(close(p.intensity(vertical: v, horizontal: 0),
                      p.intensity(vertical: v, horizontal: deg(180))))
        #expect(close(p.intensity(vertical: v, horizontal: deg(45)),
                      p.intensity(vertical: v, horizontal: deg(135))))
    }

    /// A full 0-360 file wraps; a spec-violating file that stops short of 360
    /// still interpolates across the seam.
    @Test func fullCircleWrapsAcrossTheSeam() throws {
        let full = """
        IESNA:LM-63-2002
        TILT=NONE
        1 1000 1 2 4 1 2 0.1 0.1 0.1
        1.0 1.0 100
        0 90
        0 90 180 270
        100 800
        100 200
        100 400
        100 600
        """
        let p = try #require(IESProfile(string: full))
        #expect(p.symmetry == .full)
        let v = deg(90)
        // Halfway across the 270 → 0(+360) seam: between 0.75 and 1.0.
        #expect(close(p.intensity(vertical: v, horizontal: deg(315)), 0.875, 1e-6))
        // Negative azimuths wrap.
        #expect(close(p.intensity(vertical: v, horizontal: deg(-45)),
                      p.intensity(vertical: v, horizontal: deg(315))))
    }

    // MARK: - GPU bake

    @Test func bakedTableMatchesTheSampler() throws {
        let p = try #require(IESProfile(string: axial))
        let w = 64, h = 8
        let table = p.bakedTable(width: w, height: h)
        #expect(table.count == w * h)
        // Every texel is the sampler evaluated at that texel's center.
        for (row, col) in [(0, 0), (3, 10), (7, 63)] {
            let theta = (Double(col) + 0.5) / Double(w) * .pi
            let phi = (Double(row) + 0.5) / Double(h) * 2 * .pi
            #expect(close(Double(table[row * w + col]),
                          p.intensity(vertical: theta, horizontal: phi), 1e-6))
        }
        // The peak texel is near 1 (texel centers straddle the exact axis).
        #expect(table.max()! > 0.99)
        #expect(table.min()! >= 0)
    }

    // MARK: - Light packing

    @Test func shapingSlotsDefaultToNone() {
        let d = Drawer()
        d.beginFrame()
        d.camera(Camera3D(eye: Vector3(0, 0, 5), target: .zero))
        d.addLight(.point(.white, at: .zero))
        let l = d.makeLighting().lights.0
        #expect(l.shaping.x == -1 && l.shaping.y == -1 && l.shaping.z == 0)
        #expect(d.usedIESProfiles.isEmpty && d.usedLightCookies.isEmpty)
    }

    @Test func profiledLightsShareLayersByContent() throws {
        let p = try #require(IESProfile(string: axial))
        let q = try #require(IESProfile(string: ordered))
        let d = Drawer()
        d.beginFrame()
        d.camera(Camera3D(eye: Vector3(0, 0, 5), target: .zero))
        d.addLight(.point(.white, at: .zero, profile: p))
        d.addLight(.spot(.white, at: .zero, direction: Vector3(0, -1, 0), profile: q))
        d.addLight(.point(.white, at: Vector3(1, 0, 0), profile: p))   // same content → same layer
        let u = d.makeLighting()
        #expect(u.lights.0.shaping.x == 0)
        #expect(u.lights.1.shaping.x == 1)
        #expect(u.lights.2.shaping.x == 0)
        #expect(d.usedIESProfiles.count == 2)
        // A repeated makeLighting call rebuilds the same lists.
        _ = d.makeLighting()
        #expect(d.usedIESProfiles.count == 2)
    }

    @Test func pointAxisAndRollPack() throws {
        let p = try #require(IESProfile(string: axial))
        let d = Drawer()
        d.beginFrame()
        d.camera(Camera3D(eye: Vector3(0, 0, 5), target: .zero))
        d.addLight(.point(.white, at: .zero, profile: p,
                          axis: Vector3(2, 0, 0), roll: 1.5))
        let l = d.makeLighting().lights.0
        #expect(abs(l.direction.x - 1) < 1e-6)   // axis normalized into direction
        #expect(abs(l.shaping.z - 1.5) < 1e-6)
    }

    @Test func cookiePacksOnSpotsOnly() {
        let img = Image(width: 8, height: 8, color: .white)
        let cookie = LightCookie(img)
        #expect(cookie != nil)
        guard let cookie else { return }
        let d = Drawer()
        d.beginFrame()
        d.camera(Camera3D(eye: Vector3(0, 0, 5), target: .zero))
        d.addLight(.spot(.white, at: .zero, direction: Vector3(0, -1, 0), cookie: cookie))
        var light = Light.point(.white, at: .zero)
        light.cookie = cookie   // a cookie on a non-spot kind packs as none
        d.addLight(light)
        let u = d.makeLighting()
        #expect(u.lights.0.shaping.y == 0)
        #expect(u.lights.1.shaping.y == -1)
        #expect(d.usedLightCookies.count == 1)
    }

    @Test func cookieResamplesAndCompares() {
        // A 2x2 quadrant image: the resampled 512² buffer keeps each quadrant's
        // color, and equality follows content.
        var img = Image(width: 2, height: 2, color: .black)
        img[0, 0] = .white
        let a = LightCookie(img)
        let b = LightCookie(img)
        #expect(a == b)
        guard let a else { return }
        // Top-left texel is white, bottom-right black (top-down row order).
        #expect(a.pixels[0] > 250)
        let last = (LightCookie.resolution * LightCookie.resolution - 1) * 4
        #expect(a.pixels[last] < 5)
        var other = Image(width: 2, height: 2, color: .black)
        other[1, 1] = .white
        #expect(LightCookie(other) != a)
    }
}
