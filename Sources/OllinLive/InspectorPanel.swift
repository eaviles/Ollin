import SwiftUI
import Ollin

/// Sidebar inspector for the live host: the shared monitor card (sketch
/// identity · frame counter · timecode clock · performance strip) over the
/// running sketch's `@Param` parameters. The card and parameter list are the same
/// views the standalone detached panel uses, so the two never drift. The
/// reload status lives in the window toolbar (see `LiveRootView`), and a compile
/// error shows in the canvas — neither is repeated here.
struct InspectorPanel: View {
    let session: LiveSession

    var body: some View {
        ScrollView {
            GlassEffectContainer(spacing: 16) {
                VStack(spacing: 16) {
                    MonitorCardView(
                        identity: MonitorIdentity(name: session.fileName, folder: session.folder),
                        stats: session.stats, reloads: session.reloadCount)
                    VariationCardView(stats: session.stats) { seed in
                        session.recordSeed(seed)
                    }
                    ParametersListView(parameters: session.params,
                                       sketchName: session.fileName,
                                       onChange: { name, value in
                                           session.recordParam(name, value)
                                       },
                                       save: session.saveAction)
                }
                .endsTypingOnBackgroundTap()
            }
            .padding(14)
        }
    }
}
