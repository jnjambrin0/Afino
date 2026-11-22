import PIDesign
import SwiftUI

/// The panel's SwiftUI content. The panel owns its size; this view fills it. Content swaps are
/// 160 ms crossfades (opacity only, so Reduce Motion keeps them); nothing animates on a key,
/// a hover or a selection.
struct PanelRootView: View {
    let controller: PanelController

    private enum Family: Hashable {
        /// Compose, running, result, failed, stopped: the footer stays, the content above swaps.
        case main
        case setup
        case history
        case confirmation
    }

    var body: some View {
        let family = family
        ZStack(alignment: .top) {
            switch family {
            case .main:
                PanelMainView(controller: controller)
                    .transition(.opacity)
            case .setup:
                SetupCardView(controller: controller)
                    .transition(.opacity)
            case .history:
                HistoryView(controller: controller)
                    .transition(.opacity)
            case .confirmation:
                CopiedPillView()
                    .transition(.opacity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .animation(EmberDesign.Motion.contentCrossfade, value: family)
        .emberFloatingLayer()
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(PanelAccessibilityID.panel)
    }

    private var family: Family {
        if controller.model.isConfirmingCopy { return .confirmation }
        switch controller.screen {
        case .compose, .running, .result, .failed, .stopped: return .main
        case .setup: return .setup
        case .history: return .history
        }
    }
}

/// Compose and the result states. The compose input is an AppKit view the controller lays over
/// this content; here it is just room above the footer.
struct PanelMainView: View {
    let controller: PanelController

    var body: some View {
        let isCompose = controller.screen == .compose
        VStack(spacing: 0) {
            ZStack(alignment: .top) {
                if isCompose {
                    Color.clear
                        .transition(.opacity)
                } else {
                    ResultContentView(controller: controller)
                        .transition(.opacity)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .animation(EmberDesign.Motion.contentCrossfade, value: isCompose)

            PanelFooterView(controller: controller)
                .frame(height: EmberDesign.Panel.footerHeight)
        }
    }
}
