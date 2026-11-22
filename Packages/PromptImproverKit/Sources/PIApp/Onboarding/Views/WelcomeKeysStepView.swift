import AppKit
import PIDesign
import SwiftUI

/// Step 4: the keys that work in the panel, three groups of four, keys first; then the two things
/// worth knowing (the result is already copied; target and engine are different things) and where
/// the rest lives.
struct WelcomeKeysStepView: View {
    let groups: [WelcomeKeyGroup]

    var body: some View {
        WelcomeStepLayout(
            step: .keys,
            subtitle: OnboardingStrings.text("welcome.keys.subtitle"),
            contentInset: OnboardingLayout.wideContentInset
        ) {
            VStack(alignment: .leading, spacing: EmberDesign.Spacing.l) {
                guide
                VStack(alignment: .leading, spacing: EmberDesign.Spacing.s) {
                    WelcomeNote(symbol: "doc.on.clipboard", text: OnboardingStrings.text("welcome.keys.clipboard"))
                    WelcomeNote(symbol: "scope", text: OnboardingStrings.text("welcome.keys.targetEngine"))
                    menuBarNote
                }
                .padding(.horizontal, EmberDesign.Card.padding - EmberDesign.Spacing.xs)
            }
            .fixedSize(horizontal: true, vertical: false)
        }
    }

    // MARK: The keys

    private var guide: some View {
        Grid(
            alignment: .leadingFirstTextBaseline,
            horizontalSpacing: OnboardingLayout.guideColumnSpacing,
            verticalSpacing: OnboardingLayout.guideRowSpacing
        ) {
            ForEach(Array(groups.enumerated()), id: \.element.id) { index, group in
                if index > 0 {
                    // As wide as the rows, never widening a column.
                    Divider()
                        .gridCellUnsizedAxes(.horizontal)
                        .padding(.vertical, EmberDesign.Spacing.xxs)
                }
                ForEach(Array(Self.lines(of: group.rows).enumerated()), id: \.offset) { lineIndex, line in
                    GridRow {
                        Text(verbatim: lineIndex == 0 ? group.title : "")
                            .font(OnboardingLayout.guideGroupFont)
                            .foregroundStyle(.secondary)
                            .frame(width: OnboardingLayout.guideGroupColumnWidth, alignment: .leading)
                        cells(line.first)
                        if let second = line.second {
                            cells(second, leading: OnboardingLayout.guidePairSpacing)
                        }
                    }
                }
            }
        }
        .padding(EmberDesign.Card.padding)
        // As wide as the notes under it when they are wider, the keys in the middle.
        .frame(maxWidth: .infinity)
        .welcomeCard()
        // One element per shortcut, in reading order, each saying its words and its keys.
        .accessibilityElement(children: .ignore)
        .accessibilityChildren {
            ForEach(groups) { group in
                Text(verbatim: group.title)
                    .accessibilityAddTraits(.isHeader)
                ForEach(group.rows) { row in
                    Text(verbatim: row.spoken)
                }
            }
        }
    }

    @ViewBuilder
    private func cells(_ row: WelcomeKeyRow, leading: CGFloat = 0) -> some View {
        // The caps sit against their words: the column is aligned on its trailing edge.
        WelcomeKeyTokens(tokens: row.tokens)
            .padding(.leading, leading)
            .gridColumnAlignment(.trailing)
        // A few words each, on one line: the list is laid out for its longest label.
        VStack(alignment: .leading, spacing: EmberDesign.Spacing.xxs) {
            Text(verbatim: row.label)
                .font(OnboardingLayout.guideLabelFont)
                .foregroundStyle(.primary)
            if let note = row.note {
                Text(verbatim: note)
                    .font(EmberDesign.Typography.fieldHelp)
                    .foregroundStyle(.secondary)
            }
        }
        .lineLimit(1)
        .fixedSize()
    }

    /// A group's rows two to a line, in reading order.
    static func lines(of rows: [WelcomeKeyRow]) -> [(first: WelcomeKeyRow, second: WelcomeKeyRow?)] {
        stride(from: 0, to: rows.count, by: 2).map { index in
            (rows[index], rows.indices.contains(index + 1) ? rows[index + 1] : nil)
        }
    }

    // MARK: Where the rest lives

    private var menuBarNote: some View {
        HStack(alignment: .firstTextBaseline, spacing: EmberDesign.Spacing.s) {
            Group {
                if let glyph = StatusIconRenderer.glyph() {
                    Image(nsImage: glyph)
                        .renderingMode(.template)
                        .resizable()
                        .scaledToFit()
                        .frame(width: OnboardingLayout.menuBarGlyphSize, height: OnboardingLayout.menuBarGlyphSize)
                        .alignmentGuide(.firstTextBaseline) { $0[.bottom] - EmberDesign.Spacing.xxs }
                } else {
                    Image(systemName: "menubar.rectangle")
                }
            }
            .foregroundStyle(.tertiary)
            .frame(width: EmberDesign.Card.menuGlyphColumn)
            .accessibilityHidden(true)
            Text(verbatim: OnboardingStrings.text("welcome.keys.footer"))
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .font(OnboardingLayout.noteFont)
        .accessibilityElement(children: .combine)
    }
}
