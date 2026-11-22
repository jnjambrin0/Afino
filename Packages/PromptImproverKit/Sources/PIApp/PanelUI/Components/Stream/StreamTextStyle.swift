import AppKit
import PIDesign

/// The well's text attributes. Everything metric-related is decided here; colour-only styles
/// (markup tint) never change layout.
enum StreamTextStyle {
    static var bodyFont: NSFont { EmberDesign.Typography.resultBodyNSFont }

    static var headingFont: NSFont {
        .systemFont(ofSize: EmberDesign.Typography.resultBodySize, weight: .semibold)
    }

    static var codeFont: NSFont { EmberDesign.Typography.resultCodeNSFont }

    static let paragraphStyle: NSParagraphStyle = {
        let style = NSMutableParagraphStyle()
        style.lineSpacing = EmberDesign.Typography.resultLineSpacing
        return style
    }()

    /// Body text: the body font, the label colour and the well's line spacing.
    static var baseAttributes: [NSAttributedString.Key: Any] {
        [
            .font: bodyFont,
            .foregroundColor: NSColor.labelColor,
            .paragraphStyle: paragraphStyle,
        ]
    }

    /// Restyles `range` of `storage` from `spans` (relative to `range.location`). Call inside
    /// `beginEditing()` / `endEditing()`.
    static func apply(_ spans: [PromptSyntaxStyler.Span], to storage: NSTextStorage, in range: NSRange) {
        guard range.length > 0 else { return }
        storage.setAttributes(baseAttributes, range: range)
        for span in spans {
            let target = NSRange(location: range.location + span.range.location, length: span.range.length)
            guard NSMaxRange(target) <= NSMaxRange(range) else { continue }
            switch span.kind {
            case .markup:
                storage.addAttribute(.foregroundColor, value: NSColor.secondaryLabelColor, range: target)
            case .heading:
                storage.addAttribute(.font, value: headingFont, range: target)
            case .codeBlock:
                storage.addAttribute(.font, value: codeFont, range: target)
            case .inlineCode:
                // Left as body text: the backticks around it are already tinted as markup, and
                // a font change would alter the line's metrics.
                break
            }
        }
    }

    /// The height of one line of body text (the empty well's caret and line height).
    static var bodyLineHeight: CGFloat {
        let font = bodyFont
        return ceil(font.ascender - font.descender + font.leading)
    }
}
