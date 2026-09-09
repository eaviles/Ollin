import Ollin
import OllinSamplePhotos
import OllinVision

/// Where the eye goes, made visible: a `SaliencyTracker` maps each frame's
/// visual salience — the heat map drawn as a warm glow over the dimmed feed,
/// the salient regions boxed, and a marker gliding toward the hottest spot
/// (found by sampling `salience(at:in:)` on a grid). Click to switch flavors:
/// **attention** predicts where a person would look, **objectness** where the
/// discrete objects are.
@main
final class EyeCatcher: Sketch {
    // A camera where this Mac has one, and a bundled photograph where it does
    // not, so there is always a face whose gaze can be read. `--photo` takes the picture even
    // where a camera would have worked, which is how a still of this sketch is made.
    let feed = Camera.orStill(SamplePhoto.portrait.load())
    lazy var attention = SaliencyTracker(feed, mode: .attention)
    lazy var objectness = SaliencyTracker(feed, mode: .objectness)
    var showingAttention = true

    var active: SaliencyTracker { showingAttention ? attention : objectness }

    /// The marker's displayed position, eased toward the hottest sampled spot
    /// so it glides instead of jumping.
    var marker: Vector2?

    override func mousePressed() {
        showingAttention.toggle()
    }

    override func draw() {
        background(Color(white: 0.04))

        // The room, dimmed — the heat is the bright thing here.
        tint(Color(white: 0.4))
        guard let rect = drawFrame(feed) else { return noTint() }
        noTint()

        // If the model can't run on this Mac (no compute device), say so on the
        // canvas instead of silently never glowing.
        if let reason = active.unavailableReason {
            return drawStatus(reason, style: .warning)
        }

        // The heat map, stretched over the picture and tinted warm: salience
        // as a glow.
        if let heat = active.heatMap {
            tint(Color(red: 1.0, green: 0.62, blue: 0.12, alpha: 0.85))
            drawImage(heat, in: rect)
            noTint()
        }

        // The salient regions, boxed.
        noFill()
        stroke(Color(red: 1.0, green: 0.85, blue: 0.5, alpha: 0.9))
        strokeWeight(2 * scale)
        for region in active.regions {
            drawRect(region.bounds(in: rect), cornerRadius: 10 * scale)
        }
        noStroke()

        // The hottest spot: sample the field on a grid and glide the marker
        // toward the peak.
        var peak: (position: Vector2, heat: Double)?
        let step = 24 * scale
        var y = rect.y + step / 2
        while y < rect.y + rect.height {
            var x = rect.x + step / 2
            while x < rect.x + rect.width {
                let p = Vector2(x, y)
                let s = active.salience(at: p, in: rect)
                if s > (peak?.heat ?? 0) { peak = (p, s) }
                x += step
            }
            y += step
        }
        if let peak, peak.heat > 0.1 {
            let eased = marker.map { $0 + (peak.position - $0) * min(1, deltaTime * 8) }
            marker = eased ?? peak.position
        }
        if let marker {
            stroke(.white)
            strokeWeight(2.5 * scale)
            noFill()
            drawCircle(center: marker, radius: 26 * scale)
            noStroke()
            fill(.white)
            drawCircle(center: marker, radius: 4 * scale)
        }

        let mode = showingAttention ? "attention (where the eye goes)"
                                    : "objectness (where the objects are)"
        drawCaption("EyeCatcher — \(mode) · click to switch")
    }
}
