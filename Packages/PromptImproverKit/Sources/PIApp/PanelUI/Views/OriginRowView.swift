import PICore
import PIDesign
import SwiftUI

/// The header of the result states: the draft the result was written from, collapsed to one
/// line (a click or ⌘O shows up to six), the refine instruction of the shown version, the version
/// stepper, and the status on the trailing edge.
struct OriginRowView: View {
    let controller: PanelController

    var body: some View {
        let state = controller.session.state
        let expanded = controller.model.isOriginalExpanded
        HStack(alignment: .firstTextBaseline, spacing: EmberDesign.Spacing.m) {
            Button { controller.perform(.toggleOriginal) } label: {
                HStack(alignment: .firstTextBaseline, spacing: EmberDesign.Spacing.s) {
                    Image(systemName: "quote.opening")
                        .font(EmberDesign.Typography.hint)
                        .foregroundStyle(.tertiary)
                        .accessibilityHidden(true)
                    Text(verbatim: originText(state, expanded: expanded))
                        .font(EmberDesign.Typography.menuItem)
                        .foregroundStyle(.secondary)
                        .lineLimit(expanded ? PanelLayout.originMaxLines : 1)
                        .truncationMode(.tail)
                        .multilineTextAlignment(.leading)
                        .layoutPriority(1)
                    if let instruction = instruction(state) {
                        // Short as a rule; the draft gives way first.
                        Text(verbatim: "· \(instruction)")
                            .font(EmberDesign.Typography.menuItem)
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                            .truncationMode(.tail)
                            .frame(maxWidth: PanelLayout.instructionMaxWidth, alignment: .leading)
                            .fixedSize(horizontal: true, vertical: false)
                            .layoutPriority(2)
                    }
                    Image(systemName: expanded ? "chevron.up" : "chevron.down")
                        .font(EmberDesign.Typography.hint.weight(.semibold))
                        .foregroundStyle(.tertiary)
                        .accessibilityHidden(true)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text(verbatim: PanelStrings.originalAccessibilityLabel))
            .accessibilityValue(Text(verbatim: state.origin ?? ""))
            .accessibilityHint(Text(verbatim: expanded ? PanelStrings.hideOriginal : PanelStrings.showOriginal))
            .accessibilityIdentifier(PanelAccessibilityID.originToggle)

            Spacer(minLength: EmberDesign.Spacing.s)

            if state.phase == .result, state.versions.count > 1 {
                VersionStepper(controller: controller, index: state.shownVersion, count: state.versions.count)
            }
            PanelStatusView(controller: controller)
        }
        .padding(.leading, PanelLayout.textLeadingInset)
        .padding(.trailing, PanelLayout.textLeadingInset)
        .padding(.vertical, EmberDesign.Spacing.m)
        .frame(minHeight: EmberDesign.Panel.headerHeight, alignment: .top)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(PanelAccessibilityID.originRow)
    }

    /// Collapsed, whitespace runs fold into single spaces so the one line shows as much as it can.
    private func originText(_ state: SessionState, expanded: Bool) -> String {
        let origin = state.origin ?? state.draft
        return expanded ? origin : origin.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    /// The refine instruction of the shown version, or of the refinement in flight.
    private func instruction(_ state: SessionState) -> String? {
        if state.isRunning { return state.pendingInstruction }
        guard state.phase == .result else { return nil }
        return state.shown?.instruction
    }
}

/// "‹ 2 of 3 ›" (⌘[ / ⌘]).
struct VersionStepper: View {
    let controller: PanelController
    let index: Int
    let count: Int

    var body: some View {
        HStack(spacing: 0) {
            Button(PanelStrings.previousVersion, systemImage: "chevron.left") {
                controller.perform(.previousVersion)
            }
            .labelStyle(.iconOnly)
            .buttonStyle(.emberIcon)
            .disabled(index == 0)
            Text(verbatim: PanelStrings.versionStepper(index + 1, of: count))
                .font(EmberDesign.Typography.hint)
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            Button(PanelStrings.nextVersion, systemImage: "chevron.right") {
                controller.perform(.nextVersion)
            }
            .labelStyle(.iconOnly)
            .buttonStyle(.emberIcon)
            .disabled(index >= count - 1)
        }
        // Small icon buttons: the row stays one line tall.
        .frame(height: PanelLayout.originLineHeight)
        .accessibilityElement(children: .contain)
        .accessibilityValue(Text(verbatim: PanelStrings.versionAccessibility(index + 1, of: count)))
        .accessibilityIdentifier(PanelAccessibilityID.versionStepper)
    }
}

/// "Thinking… 7 s", "Writing…", or the accent check and "Copied" (one bounce).
struct PanelStatusView: View {
    let controller: PanelController

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var bounce = 0

    var body: some View {
        Group {
            if case .thinking = controller.status(at: .now) {
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    label(controller.status(at: context.date))
                }
            } else {
                label(controller.status(at: .now))
            }
        }
        .font(EmberDesign.Typography.hint)
        .foregroundStyle(.secondary)
        .monospacedDigit()
        .lineLimit(1)
        .fixedSize()
        .help(controller.writtenByModel.map(PanelStrings.writtenBy) ?? "")
        .accessibilityIdentifier(PanelAccessibilityID.status)
    }

    @ViewBuilder
    private func label(_ status: PanelStatus) -> some View {
        switch status {
        case .none:
            EmptyView()
        case .thinking(let seconds):
            Text(verbatim: seconds.map { PanelStrings.thinking(seconds: $0) } ?? PanelStrings.thinking)
        case .retrying(let reason):
            Text(verbatim: PanelStrings.retrying(reason))
        case .writing:
            Text(verbatim: PanelStrings.writing)
        case .copied:
            HStack(spacing: EmberDesign.Spacing.xs) {
                Image(systemName: "checkmark")
                    .fontWeight(.bold)
                    .foregroundStyle(EmberDesign.Brand.accentMark)
                    .symbolEffect(.bounce, value: bounce)
                    .accessibilityHidden(true)
                Text(verbatim: PanelStrings.copied)
            }
            .onAppear { if !reduceMotion { bounce += 1 } }
            .onChange(of: controller.session.state.shown?.id) { if !reduceMotion { bounce += 1 } }
        }
    }
}
