import AppKit
import SwiftUI

public nonisolated extension EmberDesign {
    /// The three brand colours of the "Aquamarine" palette (`docs/BRAND.md`). The accent is the
    /// app's voice: it marks only the Return action (`EButtonStyle` `.primary`) and writing (the
    /// caret, the copied check). Selection and focus follow the system accent colour. The accent
    /// is never used for text.
    enum Brand {
        /// sRGB hex values per appearance.
        struct Variants: Hashable, Sendable {
            let light: UInt32
            let dark: UInt32
            let highContrastLight: UInt32
            let highContrastDark: UInt32

            /// The Increase Contrast values default to the standard ones.
            init(light: UInt32, dark: UInt32, highContrastLight: UInt32? = nil, highContrastDark: UInt32? = nil) {
                self.light = light
                self.dark = dark
                self.highContrastLight = highContrastLight ?? light
                self.highContrastDark = highContrastDark ?? dark
            }

            func hex(isDark: Bool, isHighContrast: Bool) -> UInt32 {
                switch (isDark, isHighContrast) {
                case (false, false): light
                case (true, false): dark
                case (false, true): highContrastLight
                case (true, true): highContrastDark
                }
            }
        }

        /// The primary action's fill.
        static let accentVariants = Variants(light: 0x006459, dark: 0x51D7C2)
        /// The label on the accent fill, at least 7:1 against both accent variants: white on the
        /// deep light-mode fill, near-black teal on the bright dark-mode fill.
        static let onAccentVariants = Variants(light: 0xFFFFFF, dark: 0x02201E)
        /// Thin marks (the caret, the copied check): darker in light mode and stronger under
        /// Increase Contrast.
        static let accentMarkVariants = Variants(
            light: 0x007467,
            dark: 0x6BE6D2,
            highContrastLight: 0x00534A,
            highContrastDark: 0xA5F3E4
        )

        /// The primary action's fill, for AppKit drawing.
        public static let nsAccent = dynamicColor(named: "EmberAccent", accentVariants)
        /// The label on the accent fill, for AppKit drawing.
        public static let nsOnAccent = dynamicColor(named: "EmberOnAccent", onAccentVariants)
        /// Thin marks, for AppKit drawing (the compose view's insertion point, layer carets).
        public static let nsAccentMark = dynamicColor(named: "EmberAccentMark", accentMarkVariants)

        /// The primary action's fill.
        public static var accent: Color { Color(nsColor: nsAccent) }
        /// The primary action's label and the caps drawn on the accent fill.
        public static var onAccent: Color { Color(nsColor: nsOnAccent) }
        /// Thin marks: the caret and the copied check.
        public static var accentMark: Color { Color(nsColor: nsAccentMark) }

        /// Whether `appearance` is dark and whether it is an Increase Contrast variant (vibrant
        /// appearances included).
        static func traits(of appearance: NSAppearance) -> (isDark: Bool, isHighContrast: Bool) {
            let match = appearance.bestMatch(from: [
                .aqua, .darkAqua, .vibrantLight, .vibrantDark,
                .accessibilityHighContrastAqua, .accessibilityHighContrastDarkAqua,
                .accessibilityHighContrastVibrantLight, .accessibilityHighContrastVibrantDark,
            ])
            switch match {
            case .darkAqua?, .vibrantDark?:
                return (true, false)
            case .accessibilityHighContrastAqua?, .accessibilityHighContrastVibrantLight?:
                return (false, true)
            case .accessibilityHighContrastDarkAqua?, .accessibilityHighContrastVibrantDark?:
                return (true, true)
            default:
                return (false, false)
            }
        }

        /// An opaque sRGB colour from `0xRRGGBB`.
        static func color(hex: UInt32) -> NSColor {
            NSColor(
                srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
                green: CGFloat((hex >> 8) & 0xFF) / 255,
                blue: CGFloat(hex & 0xFF) / 255,
                alpha: 1
            )
        }

        /// A dynamic colour resolved from the drawing appearance. The provider is nonisolated
        /// because AppKit may resolve colours off the main thread.
        static func dynamicColor(named name: String, _ variants: Variants) -> NSColor {
            NSColor(name: NSColor.Name(name)) { appearance in
                let traits = traits(of: appearance)
                return color(hex: variants.hex(isDark: traits.isDark, isHighContrast: traits.isHighContrast))
            }
        }
    }
}
