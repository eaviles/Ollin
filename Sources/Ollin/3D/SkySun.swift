import Foundation
import CHosekWilkie    // ollin_hosek_rgb_configs, ollin_hosek_solar_irradiance
import CSpectralData   // the CIE 1931 2-degree observer

/// The sun of a procedural `.sky`, worked out on the CPU from the same model the bake
/// fills the sky from, so the light a scene receives and the sky it sees agree.
///
/// The sky model gives radiance in its own physical unit (watts per square meter per
/// steradian, weighed by the CIE observer and turned into linear sRGB); the beam is
/// that model's solar radiance function, published in spectral form, integrated over
/// the solar disc and through the same observer, so the two share one unit and their
/// ratio is the model's. The renderer scales the sky by an auto-exposure; `exposure`
/// is that scale, and the drawer multiplies the beam by it, so the light arrives in
/// the units the sky's own image is drawn in.
struct SkySun: Equatable {
    /// The sky's haze, ground reflectance, and sun height, clamped as the bake clamps
    /// them.
    let turbidity: Double
    let groundAlbedo: Double
    let elevation: Double

    /// The beam's irradiance on a surface facing the sun, linear sRGB, in the sky
    /// model's unit. No cloud is in it; `beam(coverage:)` takes a cloudscape's share out.
    let beam: SIMD3<Double>
    /// The sky's mean luminance over the whole sphere, the ground hemisphere read as
    /// the bake without a sun reads it (the sky's dimmed mirror). The auto-exposure's
    /// average while the sun is not a light.
    let skyAverage: Float
    /// The sky hemisphere's mean luminance on its own, solid-angle weighted: the upper
    /// half of the average above, for the bake whose ground is lit.
    let skyHemisphereAverage: Float
    /// The sky's irradiance on a level surface, linear sRGB in the model's unit (the
    /// closed form over the upper hemisphere, cosine weighted), with no sun in it.
    let levelIrradiance: SIMD3<Double>
    /// The sky's radiance along the horizon, averaged over every compass direction,
    /// linear sRGB in the model's unit: what the air far away converges to.
    let horizon: SIMD3<Double>

    /// The model's terrestrial sun: half of 0.51 degrees, in radians.
    static let solarRadius = (0.51 * Double.pi / 180) / 2
    /// The solid angle the solar disc covers, in steradians.
    static let solarSolidAngle = 2 * Double.pi * (1 - cos(solarRadius))

    /// The bake's auto-exposure target: the average luminance an environment is
    /// scaled to.
    static let targetLuminance: Float = 0.4

    init(turbidity: Double, elevation: Double, groundAlbedo: Double) {
        let turb = min(max(turbidity, 1), 10)
        let albedo = min(max(groundAlbedo, 0), 1)
        let e = min(max(elevation, 0.001), Double.pi / 2 - 0.001)
        self.turbidity = turb
        self.groundAlbedo = albedo
        self.elevation = e
        let (configs, radiances) = SkySun.configurations(turbidity: turb, albedo: albedo,
                                                         elevation: e)
        let sunDir = SkySun.bakedDirection(elevation: e)
        skyAverage = SkySun.averageLuminance(configs: configs, radiances: radiances,
                                             albedo: albedo, sunDir: sunDir)
        skyHemisphereAverage = SkySun.skyHemisphereLuminance(configs: configs, radiances: radiances,
                                                             sunDir: sunDir)
        levelIrradiance = SkySun.levelIrradiance(configs: configs, radiances: radiances, sunDir: sunDir)
        beam = SkySun.beamIrradiance(turbidity: turb, elevation: e)
        horizon = SkySun.horizonRadiance(configs: configs, radiances: radiances, elevation: e)
    }

    /// The beam with a cloudscape's share taken out. The share of the sky the clouds
    /// claim is the chance the sun stands behind one, so the beam keeps the rest of it
    /// (a thick cloud passes next to nothing of the direct light; its glow is in the
    /// baked sky).
    func beam(coverage: Double?) -> SIMD3<Double> {
        beam * (1 - min(max(coverage ?? 0, 0), 1))
    }

    /// The beam's irradiance on level ground, the share the clouds leave of it: the
    /// beam at normal incidence times the sine of the sun's elevation.
    func levelBeam(coverage: Double?) -> SIMD3<Double> {
        beam(coverage: coverage) * sin(elevation)
    }

    /// The radiance of the ground under a sky whose sun lights the scene, linear sRGB
    /// in the model's unit: a level matte ground of the sky's albedo, lit by the sky's
    /// irradiance and the share of the beam the clouds leave, one radiance in every
    /// direction (a matte surface's radiance is its albedo times its irradiance over
    /// pi). The bake fills the lower hemisphere of a sun-lit sky with it, with the
    /// sky's irradiance read from the baked sky itself (clouds included); this is the
    /// clear-sky value, for the exposure.
    func groundRadiance(coverage: Double?) -> SIMD3<Double> {
        (levelIrradiance + levelBeam(coverage: coverage)) * (groundAlbedo / Double.pi)
    }

    /// The exposure the bake scales this sky by. When the sun lights the scene its beam
    /// joins the average, as a photographed sun's pixels do in a loaded map: the sun's
    /// light spread over the whole sphere is its irradiance over 4 pi.
    func exposure(sunLit: Bool, coverage: Double?) -> Float {
        SkySun.exposure(average: sunLit ? litAverage(coverage: coverage) : skyAverage)
    }

    /// The average the exposure is set from while the sun lights the scene: the sky
    /// hemisphere's, the sun-lit ground's over the other half, and the beam's
    /// luminance spread over the sphere. The ground is the clear-sky value and the
    /// beam's share is the clouds' expected one (1 minus the coverage), so an exposure
    /// never swings as the sun passes behind a cloud; the light on the scene follows
    /// the clouds, the exposure does not.
    func litAverage(coverage: Double?) -> Float {
        let b = beam(coverage: coverage)
        let luminance = 0.2126 * b.x + 0.7152 * b.y + 0.0722 * b.z
        let g = groundRadiance(coverage: coverage)
        let ground = Float(0.2126 * g.x + 0.7152 * g.y + 0.0722 * g.z)
        return (skyHemisphereAverage + ground) / 2 + Float(luminance / (4 * Double.pi))
    }

    /// The auto-exposure for an average luminance: the target over the average, held
    /// between 0.01 and 12 so a near-black night or a blinding noon stays sane, and 1
    /// for an average too dark to measure.
    static func exposure(average: Float) -> Float {
        average > 1e-5 ? min(max(targetLuminance / average, 0.01), 12) : 1
    }

    /// The unit direction toward the sun in the sky's own frame (+Y up, rising in the
    /// +Z compass direction), rounded to single precision as the bake packs it.
    static func bakedDirection(elevation: Double) -> SIMD3<Float> {
        SIMD3<Float>(0, Float(sin(elevation)), Float(cos(elevation)))
    }

    /// The world direction toward the sun of a sky turned by `rotation` about the
    /// vertical: the backdrop reads the sky at R_y(rotation) times the view ray, so the
    /// sky's content stands at R_y(-rotation) in the world.
    static func worldDirection(elevation: Double, rotation: Double) -> Vector3 {
        let ce = cos(elevation)
        return Vector3(-sin(rotation) * ce, sin(elevation), cos(rotation) * ce)
    }

    /// The model's nine coefficients per channel and the three radiance scales.
    static func configurations(turbidity: Double, albedo: Double,
                               elevation: Double) -> (configs: [Double], radiances: [Double]) {
        var configs = [Double](repeating: 0, count: 27)
        var radiances = [Double](repeating: 0, count: 3)
        configs.withUnsafeMutableBufferPointer { cp in
            radiances.withUnsafeMutableBufferPointer { rp in
                ollin_hosek_rgb_configs(turbidity, albedo, elevation, cp.baseAddress, rp.baseAddress)
            }
        }
        return (configs, radiances)
    }

    /// The sky model's radiance in one channel for a view at cosine `cosTheta` from the
    /// zenith and `gamma` radians from the sun; the shader's closed form, in double.
    static func radiance(configs: [Double], radiances: [Double],
                         cosTheta: Double, gamma: Double, channel c: Int) -> Double {
        let b = c * 9
        let A = configs[b], B = configs[b + 1], C = configs[b + 2], D = configs[b + 3], E = configs[b + 4]
        let F = configs[b + 5], G = configs[b + 6], H = configs[b + 7], I = configs[b + 8]
        let cg = cos(gamma)
        let mieM = (1 + cg * cg) / pow(max(1 + I * I - 2 * I * cg, 1e-4), 1.5)
        let zenith = cosTheta > 0 ? sqrt(cosTheta) : 0
        let v = (1 + A * exp(B / (cosTheta + 0.01)))
              * (C + D * exp(E * gamma) + F * cg * cg + G * mieM + H * zenith)
        return max(v, 0) * radiances[c]
    }

    /// The solid-angle-weighted average luminance of the sky over a coarse sphere, the
    /// upper hemisphere the sky and the lower its mirror dimmed by the ground albedo, as
    /// the shader fills it. Coarse is fine: it only sets the exposure scale.
    static func averageLuminance(configs: [Double], radiances: [Double],
                                 albedo: Double, sunDir: SIMD3<Float>) -> Float {
        let sx = Double(sunDir.x), sy = Double(sunDir.y), sz = Double(sunDir.z)
        let rows = 32, cols = 16
        var lumSum = 0.0, weightSum = 0.0
        for y in 0..<rows {
            let lat = (Double(y) + 0.5) / Double(rows) * Double.pi   // 0 top .. pi bottom
            let rowWeight = sin(lat)
            var rowLum = 0.0
            for x in 0..<cols {
                let lon = (Double(x) + 0.5) / Double(cols) * 2 * Double.pi
                var dy = cos(lat)
                let dxz = sin(lat)
                let dx = dxz * cos(lon), dz = dxz * sin(lon)
                var ground = 1.0
                if dy < 0 { dy = -dy; ground = albedo }              // ground = dimmed mirror sky
                let gamma = acos(max(-1, min(1, dx * sx + dy * sy + dz * sz)))
                rowLum += (0.2126 * radiance(configs: configs, radiances: radiances,
                                             cosTheta: dy, gamma: gamma, channel: 0)
                         + 0.7152 * radiance(configs: configs, radiances: radiances,
                                             cosTheta: dy, gamma: gamma, channel: 1)
                         + 0.0722 * radiance(configs: configs, radiances: radiances,
                                             cosTheta: dy, gamma: gamma, channel: 2)) * ground
            }
            lumSum += rowLum / Double(cols) * rowWeight
            weightSum += rowWeight
        }
        return weightSum > 0 ? Float(lumSum / weightSum) : 1
    }

    /// The solid-angle-weighted mean luminance of the sky hemisphere alone, on the same
    /// coarse grid as `averageLuminance`'s upper half.
    static func skyHemisphereLuminance(configs: [Double], radiances: [Double],
                                       sunDir: SIMD3<Float>) -> Float {
        let sx = Double(sunDir.x), sy = Double(sunDir.y), sz = Double(sunDir.z)
        let rows = 16, cols = 16
        var lumSum = 0.0, weightSum = 0.0
        for y in 0..<rows {
            let lat = (Double(y) + 0.5) / Double(rows) * (Double.pi / 2)   // 0 top .. pi/2 horizon
            let rowWeight = sin(lat)
            var rowLum = 0.0
            for x in 0..<cols {
                let lon = (Double(x) + 0.5) / Double(cols) * 2 * Double.pi
                let dy = cos(lat)
                let dxz = sin(lat)
                let dx = dxz * cos(lon), dz = dxz * sin(lon)
                let gamma = acos(max(-1, min(1, dx * sx + dy * sy + dz * sz)))
                rowLum += 0.2126 * radiance(configs: configs, radiances: radiances,
                                            cosTheta: dy, gamma: gamma, channel: 0)
                        + 0.7152 * radiance(configs: configs, radiances: radiances,
                                            cosTheta: dy, gamma: gamma, channel: 1)
                        + 0.0722 * radiance(configs: configs, radiances: radiances,
                                            cosTheta: dy, gamma: gamma, channel: 2)
            }
            lumSum += rowLum / Double(cols) * rowWeight
            weightSum += rowWeight
        }
        return weightSum > 0 ? Float(lumSum / weightSum) : 1
    }

    /// The sky's irradiance on a level surface: the closed form over the upper
    /// hemisphere, weighted by the cosine from the zenith and the solid angle, on a
    /// grid fine enough for the sun's halo (64 rows by 128 columns reads within half a
    /// percent of a far finer one).
    static func levelIrradiance(configs: [Double], radiances: [Double],
                                sunDir: SIMD3<Float>) -> SIMD3<Double> {
        let sx = Double(sunDir.x), sy = Double(sunDir.y), sz = Double(sunDir.z)
        let rows = 64, cols = 128
        let dTheta = (Double.pi / 2) / Double(rows), dPhi = 2 * Double.pi / Double(cols)
        var sum = SIMD3<Double>.zero
        for y in 0..<rows {
            let theta = (Double(y) + 0.5) * dTheta
            let cosTheta = cos(theta), sinTheta = sin(theta)
            let weight = cosTheta * sinTheta * dTheta * dPhi
            for x in 0..<cols {
                let phi = (Double(x) + 0.5) * dPhi
                let dx = sinTheta * cos(phi), dz = sinTheta * sin(phi)
                let gamma = acos(max(-1, min(1, dx * sx + cosTheta * sy + dz * sz)))
                sum += SIMD3<Double>(
                    radiance(configs: configs, radiances: radiances, cosTheta: cosTheta, gamma: gamma, channel: 0),
                    radiance(configs: configs, radiances: radiances, cosTheta: cosTheta, gamma: gamma, channel: 1),
                    radiance(configs: configs, radiances: radiances, cosTheta: cosTheta, gamma: gamma, channel: 2)
                ) * weight
            }
        }
        return sum
    }

    /// The sky's horizon radiance averaged over 64 compass directions.
    static func horizonRadiance(configs: [Double], radiances: [Double],
                                elevation: Double) -> SIMD3<Double> {
        let n = 64
        var sum = SIMD3<Double>.zero
        for i in 0..<n {
            let azimuth = (Double(i) + 0.5) / Double(n) * 2 * Double.pi
            // The horizon ray (cos azimuth, 0, sin azimuth) against the sun (0, sin e, cos e).
            let gamma = acos(max(-1, min(1, sin(azimuth) * cos(elevation))))
            sum += SIMD3<Double>(
                radiance(configs: configs, radiances: radiances, cosTheta: 0, gamma: gamma, channel: 0),
                radiance(configs: configs, radiances: radiances, cosTheta: 0, gamma: gamma, channel: 1),
                radiance(configs: configs, radiances: radiances, cosTheta: 0, gamma: gamma, channel: 2))
        }
        return sum / Double(n)
    }

    /// The beam's irradiance at normal incidence: the solar radiance function's disc
    /// integral at each 5 nm sample of the observer (held at its last band, 720 nm,
    /// past the model's range, where the observer is nearly blind), summed through the
    /// CIE 1931 curves to XYZ and turned into linear sRGB (D65, the matrix the shader
    /// library uses).
    static func beamIrradiance(turbidity: Double, elevation: Double) -> SIMD3<Double> {
        var xyz = SIMD3<Double>.zero
        let step = OLLIN_SPECTRAL_LAMBDA_STEP
        for (k, bar) in observer.enumerated() {
            let wavelength = min(OLLIN_SPECTRAL_LAMBDA_MIN + Double(k) * step, 720)
            let e = max(0, ollin_hosek_solar_irradiance(turbidity, elevation, wavelength))
            xyz += bar * (e * step)
        }
        let red = 3.2404542 * xyz.x - 1.5371385 * xyz.y - 0.4985314 * xyz.z
        let green = -0.9692660 * xyz.x + 1.8760108 * xyz.y + 0.0415560 * xyz.z
        let blue = 0.0556434 * xyz.x - 0.2040259 * xyz.y + 1.0572252 * xyz.z
        return SIMD3<Double>(red, green, blue)
    }

    /// The CIE 1931 2-degree observer at each 5 nm sample, x-bar, y-bar, z-bar.
    static let observer: [SIMD3<Double>] = {
        func load<T>(_ tuple: T) -> [Double] {
            withUnsafeBytes(of: tuple) { Array($0.bindMemory(to: Double.self)) }
        }
        let x = load(ollin_spectral_xbar), y = load(ollin_spectral_ybar), z = load(ollin_spectral_zbar)
        return (0..<x.count).map { SIMD3(x[$0], y[$0], z[$0]) }
    }()
}
