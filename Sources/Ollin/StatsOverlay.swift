import SwiftUI

/// The on-canvas debug readout: a compact, draggable chip that overlays the
/// sketch in the bottom-right corner when "Show FPS" is on. It's a SwiftUI
/// sibling of the Metal view, not drawn into the canvas, so it never appears in
/// exported frames and needs no text rendering of our own. Toggled by the
/// `OllinHUDCommands` menu item; works the same in every run mode because it
/// rides on `SketchView`, which all hosts embed.
struct StatsOverlay: View {
    let stats: FrameStats

    /// Accumulated drag, so the user can move the chip out of the way. Resets
    /// each launch (kept in-memory by design — it's debug chrome).
    @State private var offset: CGSize = .zero
    @GestureState private var drag: CGSize = .zero

    var body: some View {
        GeometryReader { geo in
            chip
                .offset(x: offset.width + drag.width,
                        y: offset.height + drag.height)
                .gesture(
                    DragGesture()
                        .updating($drag) { value, state, _ in state = value.translation }
                        .onEnded { value in
                            offset.width += value.translation.width
                            offset.height += value.translation.height
                            offset = clamp(offset, in: geo.size)
                        }
                )
                // Inset *before* filling the canvas, so the chip sits 12pt off the
                // corner — padding after the full-size frame overflows and clips it.
                .padding(12)
                .frame(width: geo.size.width, height: geo.size.height,
                       alignment: .bottomTrailing)
        }
    }

    private var chip: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(stats.hasData ? String(format: "%.0f", stats.fps) : "—")
                    .font(.system(.title3, design: .monospaced).weight(.semibold))
                Text("fps")
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
            line(stats.hasData ? String(format: "%.1f ms/frame", stats.frameTimeMS) : "—")
            line("verts \(stats.vertexCount) · sdf \(stats.sdfCount)")
            line("frame \(stats.frameCount) · \(String(format: "%.1f", stats.time))s")
            line("\(Int(stats.canvasWidth.rounded()))×\(Int(stats.canvasHeight.rounded()))")
        }
        .monospacedDigit()
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(.white.opacity(0.12))
        )
        .shadow(radius: 6, y: 2)
        .help("Drag to move. Toggle from View ▸ Show FPS (⌘/).")
    }

    private func line(_ text: String) -> some View {
        Text(text)
            .font(.system(.caption2, design: .monospaced))
            .foregroundStyle(.secondary)
    }

    /// Keep the chip on screen: it's anchored bottom-right, so only up/left drags
    /// (negative) move it into view; clamp the travel to the canvas, leaving a
    /// sliver visible so it can always be grabbed back.
    private func clamp(_ o: CGSize, in size: CGSize) -> CGSize {
        let margin: CGFloat = 40
        return CGSize(
            width: min(margin, max(-(size.width - margin), o.width)),
            height: min(margin, max(-(size.height - margin), o.height)))
    }
}

/// The "Show FPS" menu command that toggles the overlay. Add it to a host's
/// scene with `.commands { OllinHUDCommands() }`; it binds to the same shared
/// preference the overlay reads, so the menu and overlay stay in sync across
/// every run mode (standalone, gallery, live).
public struct OllinHUDCommands: Commands {
    @AppStorage(OllinHUD.showStatsKey) private var showStats = false

    public init() {}

    public var body: some Commands {
        CommandGroup(after: .toolbar) {
            Toggle("Show FPS", isOn: $showStats)
                .keyboardShortcut("/", modifiers: .command)
        }
    }
}
