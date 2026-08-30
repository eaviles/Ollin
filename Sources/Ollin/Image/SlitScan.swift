import Foundation

/// Slit-scan time displacement: keep a rolling history of frames and rebuild
/// the image with every pixel read from a different moment, chosen by a delay
/// map. A left-to-right delay is the classic slit scan (each column a little
/// further into the past); a radial delay ripples time outward; a portrait's
/// own brightness can displace its history. Feed it a camera frame, a video
/// frame's snapshot, or an image you paint each frame.
///
/// ```swift
/// let history = SlitScan(capacity: 48)
///
/// // each frame:
/// history.append(frame)
/// if let warped = history.image(delay: { uv in uv.x }) {
///     drawImage(warped, in: canvasRectangle)
/// }
/// ```
///
/// Frames are held on the CPU at their own resolution, so memory is
/// `width x height x 4 x frames` bytes; push modest sizes (a camera feed or a
/// few-hundred-pixel painting) rather than full canvases. Deterministic given
/// the pushed frames, so a headless export that pushes per frame reproduces.
@MainActor
public final class SlitScan {
    /// How many frames of history the buffer holds once full.
    public let capacity: Int

    /// Frame pixel buffers, newest last; all `width x height`.
    private var frames: [[UInt8]] = []
    private var width = 0
    private var height = 0
    private var noted = Set<String>()

    /// How many frames have been added so far, up to `capacity`.
    public var count: Int { frames.count }

    /// A history `frames` deep. Depth times the source frame rate is the
    /// technique's reach into the past: 48 frames at 60 fps spans 0.8 seconds.
    public init(capacity: Int = 48) {
        self.capacity = Swift.max(capacity, 1)
    }

    /// Add the newest frame. The first push fixes the history's size; a frame
    /// of any other size is skipped (with a one-time note), as is a
    /// texture-backed image, which has no CPU pixels.
    public func append(_ frame: Image) {
        guard let pixels = frame.premultipliedPixels() else {
            note("SlitScan.push skipped a texture-backed image; it has no CPU pixels. Read a video frame through its snapshot first.")
            return
        }
        if frames.isEmpty {
            width = frame.width
            height = frame.height
        } else if frame.width != width || frame.height != height {
            note("SlitScan.push skipped a \(frame.width)x\(frame.height) frame; this history is \(width)x\(height).")
            return
        }
        frames.append(pixels)
        if frames.count > capacity { frames.removeFirst() }
    }

    /// Drop the history (the next push re-fixes the size).
    public func clear() {
        frames.removeAll()
        width = 0
        height = 0
    }

    /// The time-displaced image: each output pixel comes from the frame
    /// `delay` names at that spot. The closure gets the pixel's normalized
    /// position (`0...1` each way, top-left origin) and returns how far into
    /// the past to read: `0` is the newest frame, `1` the oldest held.
    /// `nil` until a first frame is pushed.
    public func image(delay: (Vector2) -> Double) -> Image? {
        compose { x, y, invWidth, invHeight in
            delay(Vector2((Double(x) + 0.5) * invWidth, (Double(y) + 0.5) * invHeight))
        }
    }

    /// The time-displaced image, delayed by a map: each output pixel reads
    /// the past at the map's brightness there (`0` black is the newest frame,
    /// `1` white the oldest held). The map may be any size; it is sampled
    /// across the frame. A texture-backed map reads as all zeros.
    public func image(delay map: Image) -> Image? {
        guard map.width > 0, map.height > 0,
              let mapPixels = map.premultipliedPixels() else {
            return image(delay: { _ in 0 })
        }
        let mapWidth = map.width, mapHeight = map.height
        return compose { x, y, invWidth, invHeight in
            let mx = Swift.min(Int((Double(x) + 0.5) * invWidth * Double(mapWidth)), mapWidth - 1)
            let my = Swift.min(Int((Double(y) + 0.5) * invHeight * Double(mapHeight)), mapHeight - 1)
            let i = (my * mapWidth + mx) * 4
            // Premultiplied luma: transparent map regions read as now.
            return (0.2126 * Double(mapPixels[i])
                  + 0.7152 * Double(mapPixels[i + 1])
                  + 0.0722 * Double(mapPixels[i + 2])) / 255
        }
    }

    private func compose(_ delayAt: (Int, Int, Double, Double) -> Double) -> Image? {
        guard !frames.isEmpty else { return nil }
        let newest = frames.count - 1
        var output = [UInt8](repeating: 0, count: width * height * 4)
        let invWidth = 1 / Double(width), invHeight = 1 / Double(height)
        for y in 0 ..< height {
            for x in 0 ..< width {
                let d = Swift.min(Swift.max(delayAt(x, y, invWidth, invHeight), 0), 1)
                let age = Int((d * Double(newest)).rounded())
                let frame = frames[newest - age]
                let i = (y * width + x) * 4
                output[i] = frame[i]
                output[i + 1] = frame[i + 1]
                output[i + 2] = frame[i + 2]
                output[i + 3] = frame[i + 3]
            }
        }
        return Image(width: width, height: height, premultipliedRGBA: output)
    }

    private func note(_ message: String) {
        guard !noted.contains(message) else { return }
        noted.insert(message)
        print("Ollin: \(message)")
    }
}
