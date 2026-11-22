import PIDesign
import SwiftUI

/// Running, result, failed and stopped: the origin row, the well (the result sits on a solid
/// sheet, where the draft floated on the glass), and the notice row when partial text is kept.
struct ResultContentView: View {
    let controller: PanelController

    var body: some View {
        let problem = controller.problemPresentation(at: .now)
        let notice = problem?.placement == .notice ? problem : nil
        VStack(spacing: 0) {
            OriginRowView(controller: controller)
                .onGeometryChange(for: CGFloat.self, of: \.size.height) { height in
                    controller.headerHeightDidChange(height)
                }

            ResultWellView(controller: controller, block: problem?.placement == .block ? problem : nil)
                .padding(.horizontal, EmberDesign.Panel.contentInset)
                .frame(maxHeight: .infinity)

            if let notice {
                NoticeRowView(controller: controller, presentation: notice)
                    .frame(height: EmberDesign.Panel.noticeRowHeight)
                    .transition(.opacity)
            }
        }
        .animation(EmberDesign.Motion.contentCrossfade, value: notice)
    }
}

/// The well: the result text, or — when a run failed before writing anything — a glyph and one
/// line saying what happened and what to do. Errors crossfade in; no shake, no red panel.
struct ResultWellView: View {
    let controller: PanelController
    let block: PanelProblemPresentation?

    var body: some View {
        EWell {
            ZStack {
                if let block {
                    ProblemBlockView(controller: controller, presentation: block)
                        .transition(.opacity)
                } else {
                    HostedView(view: controller.streamView)
                        .transition(.opacity)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .animation(EmberDesign.Motion.contentCrossfade, value: block)
    }
}

/// A failure without text, inside the well.
struct ProblemBlockView: View {
    let controller: PanelController
    let presentation: PanelProblemPresentation

    var body: some View {
        Group {
            if controller.problemHasCountdown {
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    content(controller.problemPresentation(at: context.date) ?? presentation)
                }
            } else {
                content(presentation)
            }
        }
        .padding(.horizontal, EmberDesign.Panel.wellHorizontalPadding)
        .padding(.vertical, EmberDesign.Panel.wellVerticalPadding)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier(PanelAccessibilityID.errorBlock)
    }

    private func content(_ presentation: PanelProblemPresentation) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: EmberDesign.Spacing.m) {
            Image(systemName: presentation.symbol)
                .font(PanelLayout.errorGlyphFont)
                .foregroundStyle(presentation.tint.style)
                .accessibilityHidden(true)
            Text(verbatim: presentation.line.text)
                .font(EmberDesign.Typography.resultBody)
                .foregroundStyle(.primary)
                .monospacedDigit()
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// The 36 pt row under kept text: why it stopped, and that it was not copied.
struct NoticeRowView: View {
    let controller: PanelController
    let presentation: PanelProblemPresentation

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: EmberDesign.Spacing.s) {
            Image(systemName: presentation.symbol)
                .font(EmberDesign.Typography.messageGlyph)
                .foregroundStyle(presentation.tint.style)
                .accessibilityHidden(true)
            Text(verbatim: presentation.line.text)
                .font(EmberDesign.Typography.message)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, PanelLayout.textLeadingInset)
        .frame(maxHeight: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier(PanelAccessibilityID.notice)
    }
}

extension PanelProblemTint {
    /// The design system's status colour for the tint.
    var style: AnyShapeStyle {
        switch self {
        case .red: AnyShapeStyle(EmberDesign.Status.negative)
        case .orange: AnyShapeStyle(EmberDesign.Status.caution)
        case .secondary: AnyShapeStyle(.secondary)
        }
    }
}
