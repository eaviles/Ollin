import SwiftUI
import Ollin

/// Sidebar inspector for the live host: the shared monitor card (sketch
/// identity · frame counter · timecode clock · performance strip) over the
/// running sketch's `@Param` knobs. The card and parameter list are the same
/// views the standalone detached panel uses, so the two never drift. The
/// reload status lives in the window toolbar (see `LiveRootView`), and a compile
/// error shows in the canvas — neither is repeated here.
struct InspectorPanel: View {
    let session: LiveSession

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                MonitorCardView(
                    identity: MonitorIdentity(name: session.fileName, folder: session.folder),
                    stats: session.stats)
                ParametersListView(params: session.params) { name, value in
                    session.recordParam(name, value)
                }
            }
            .padding(14)
        }
    }
}
