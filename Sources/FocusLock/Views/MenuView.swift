import FocusLockCore
import SwiftUI

struct MenuView: View {
    @EnvironmentObject private var controller: BlockController
    /// Setting up one more block while others run.
    @State private var addingBlock = false

    var body: some View {
        Group {
            if controller.sessions.isEmpty {
                SetupView()
            } else if addingBlock {
                SetupView(close: { addingBlock = false })
            } else {
                ActiveView(onAdd: { addingBlock = true })
            }
        }
        .padding(.horizontal, 18)
        .padding(.top, 16)
        .padding(.bottom, 16 + Deep.floor)
        .frame(width: 320)
        // Always the water, whatever the system appearance: white type on deep teal, like the block page.
        .background(WaterBackground())
        .environment(\.colorScheme, .dark)
        .onAppear { controller.refreshSafariAccess() }
        .onChange(of: controller.sessions.isEmpty) { addingBlock = false }
    }
}
