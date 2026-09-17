import AVFoundation
import CoreMedia
import SwiftUI
import UIKit
import os

/// The phone as the screen of a sketch running on the Mac.
///
/// In **Sketch** mode the Mac sends its rendered frames as HEVC on a connection of
/// their own (`PhoneWire.picturePort`), and this shows each one the moment it
/// arrives. The phone decodes on its media engine through a sample-buffer display
/// layer, so a picture never passes through the CPU as pixels here either. The
/// fingers on the picture go back through the touch streamer, measured against
/// the picture rather than the screen, so -1 to 1 is the sketch's canvas.
///
/// Pictures arrive on the server's queue and are handed to the layer there; only
/// the size, which the layout reads, crosses to the main thread.
final class PictureSink: @unchecked Sendable {

    private struct Binding {
        var layer: AVSampleBufferDisplayLayer?
        var format: PhonePictureFormat?
        /// A layer that has not had a keyframe cannot decode anything else, so
        /// until one arrives the pictures built on older ones are skipped.
        var needsKeyframe = true
        var size: CGSize?
        var received = 0
    }
    private let binding = OSAllocatedUnfairLock(uncheckedState: Binding())

    /// Called on the main thread when the picture's size changes, and with each
    /// hundredth picture, for the screen's layout and its status line.
    var onSize: (@MainActor @Sendable (CGSize) -> Void)?
    var onCount: (@MainActor @Sendable (Int) -> Void)?

    /// Show pictures on this layer from now on, starting at the next keyframe.
    func attach(_ layer: AVSampleBufferDisplayLayer?) {
        binding.withLockUnchecked { binding in
            binding.layer = layer
            binding.needsKeyframe = true
        }
    }

    /// Forget the picture: the phone has left Sketch mode, and whatever comes back
    /// must start from a keyframe.
    func reset() {
        let layer = binding.withLockUnchecked { binding -> AVSampleBufferDisplayLayer? in
            binding.needsKeyframe = true
            binding.format = nil
            return binding.layer
        }
        if let layer { Self.renderer(of: layer).flush(removingDisplayedImage: true, completionHandler: nil) }
    }

    /// Take one picture off the wire and show it.
    func receive(_ picture: PhonePicture) {
        let (layer, sample, sizeChanged, count) = binding.withLockUnchecked {
            binding -> (AVSampleBufferDisplayLayer?, CMSampleBuffer?, CGSize?, Int) in
            guard let layer = binding.layer else { return (nil, nil, nil, 0) }
            if binding.needsKeyframe, !picture.isKeyframe { return (nil, nil, nil, 0) }
            guard let sample = picture.sampleBuffer(reusing: &binding.format) else {
                binding.needsKeyframe = true
                return (nil, nil, nil, 0)
            }
            binding.needsKeyframe = false
            binding.received += 1
            let size = CGSize(width: picture.width, height: picture.height)
            let changed = binding.size != size ? size : nil
            binding.size = size
            return (layer, sample, changed, binding.received)
        }
        guard let layer, let sample else { return }

        let renderer = Self.renderer(of: layer)
        if renderer.status == .failed || renderer.requiresFlushToResumeDecoding {
            // The decoder gave up on something; it starts again at a keyframe.
            renderer.flush()
            guard picture.isKeyframe else {
                binding.withLockUnchecked { $0.needsKeyframe = true }
                return
            }
        }
        renderer.enqueue(sample)

        if let sizeChanged, let onSize {
            DispatchQueue.main.async { onSize(sizeChanged) }
        }
        if count % 100 == 1, let onCount {
            DispatchQueue.main.async { onCount(count) }
        }
    }

    private static func renderer(of layer: AVSampleBufferDisplayLayer) -> AVSampleBufferVideoRenderer {
        layer.sampleBufferRenderer
    }
}

/// What the screen shows about the sketch: its picture's size, for the layout,
/// and how many pictures have arrived.
@MainActor
@Observable
final class SketchScreen {
    /// The size of the pictures arriving, or `nil` before the first.
    private(set) var pictureSize: CGSize?
    private(set) var received = 0

    @ObservationIgnored let sink = PictureSink()

    init() {
        sink.onSize = { [weak self] size in self?.pictureSize = size }
        sink.onCount = { [weak self] count in self?.received = count }
    }

    /// Clear the picture when the phone leaves Sketch mode.
    func end() {
        sink.reset()
        pictureSize = nil
        received = 0
    }
}

/// The picture, full screen and fitted, with every finger on it reported.
struct SketchScreenView: View {
    let screen: SketchScreen
    let touch: TouchStreamer
    let onLeave: () -> Void

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            // One view whatever the size, so the layer is never rebuilt when the
            // first picture says how wide it is; only the proportion changes.
            PictureSurface(sink: screen.sink, touch: touch)
                .aspectRatio(screen.pictureSize.map { $0.width / $0.height } ?? 9 / 19.5,
                             contentMode: .fit)
                .ignoresSafeArea()
            if screen.pictureSize == nil {
                VStack(spacing: 10) {
                    Text("WAITING FOR THE SKETCH")
                        .font(.system(.caption, design: .rounded).weight(.semibold))
                        .tracking(3)
                        .foregroundStyle(.white.opacity(0.55))
                    Text("Run a sketch on the Mac that calls device.show(self)")
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.35))
                }
                .allowsHitTesting(false)
            }
            VStack {
                HStack {
                    Button(action: onLeave) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.8))
                            .frame(width: 36, height: 36)
                            .background(Color.black.opacity(0.35), in: Circle())
                    }
                    .accessibilityLabel("Modes")
                    Spacer()
                }
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.top, 4)
        }
        .statusBarHidden(true)
        .persistentSystemOverlays(.hidden)
    }
}

/// The display layer, in a view that also takes every finger.
struct PictureSurface: UIViewRepresentable {
    let sink: PictureSink
    let touch: TouchStreamer

    func makeUIView(context: Context) -> PictureView {
        let view = PictureView()
        view.streamer = touch
        view.displayLayer.videoGravity = .resizeAspect
        view.displayLayer.backgroundColor = UIColor.black.cgColor
        sink.attach(view.displayLayer)
        return view
    }

    func updateUIView(_ view: PictureView, context: Context) {
        view.streamer = touch
    }

    static func dismantleUIView(_ view: PictureView, coordinator: ()) {
        view.streamer = nil
    }
}

/// A touch pad whose layer is the picture.
final class PictureView: TouchPadView {
    override class var layerClass: AnyClass { AVSampleBufferDisplayLayer.self }

    var displayLayer: AVSampleBufferDisplayLayer {
        guard let display = layer as? AVSampleBufferDisplayLayer else {
            preconditionFailure("the layer class is a sample-buffer display layer")
        }
        return display
    }
}
