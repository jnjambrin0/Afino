import AppKit
import Foundation
import Testing
@testable import PIDesign

/// The brand colours resolve per appearance, and `onAccent` on `accent` reads at AAA
/// (≥ 7:1, WCAG 2.x relative luminance from the sRGB components).
///
/// Increase Contrast appearances can't be built with `NSAppearance(named:)`
/// (AppKit hands back the base appearance; the system applies them only as
/// effective appearances), so those variants are checked through
/// `Brand.Variants`, the table the dynamic provider resolves from.
struct BrandColorTests {
    nonisolated static let appearances: [NSAppearance.Name] = [.aqua, .darkAqua, .vibrantLight, .vibrantDark]

    @Test(arguments: appearances)
    func onAccentIsAtLeastSevenToOne(_ name: NSAppearance.Name) throws {
        let accent = try resolve(EmberDesign.Brand.nsAccent, in: name)
        let onAccent = try resolve(EmberDesign.Brand.nsOnAccent, in: name)
        let ratio = Self.contrastRatio(accent, onAccent)
        #expect(ratio >= 7, "\(name.rawValue): \(ratio)")
    }

    @Test(arguments: [(false, false), (true, false), (false, true), (true, true)])
    func onAccentIsAtLeastSevenToOneInEveryVariant(_ isDark: Bool, _ isHighContrast: Bool) {
        let accent = Self.color(EmberDesign.Brand.accentVariants.hex(isDark: isDark, isHighContrast: isHighContrast))
        let onAccent = Self.color(EmberDesign.Brand.onAccentVariants.hex(isDark: isDark, isHighContrast: isHighContrast))
        #expect(Self.contrastRatio(accent, onAccent) >= 7)
    }

    @Test
    func contrastMathMatchesKnownValues() {
        let white = Self.color(0xFFFFFF)
        let black = Self.color(0x000000)
        #expect(abs(Self.contrastRatio(white, black) - 21) < 0.001)
        #expect(abs(Self.contrastRatio(white, white) - 1) < 0.001)
        // #767676 on white is the classic 4.54:1.
        #expect(abs(Self.contrastRatio(Self.color(0x767676), white) - 4.54) < 0.01)
    }

    @Test
    func accentResolvesPerAppearance() throws {
        #expect(try hex(EmberDesign.Brand.nsAccent, in: .aqua) == 0x006459)
        #expect(try hex(EmberDesign.Brand.nsAccent, in: .darkAqua) == 0x51D7C2)
        #expect(try hex(EmberDesign.Brand.nsOnAccent, in: .aqua) == 0xFFFFFF)
        #expect(try hex(EmberDesign.Brand.nsOnAccent, in: .darkAqua) == 0x02201E)
    }

    @Test
    func accentMarkStrengthensUnderIncreaseContrast() throws {
        #expect(try hex(EmberDesign.Brand.nsAccentMark, in: .aqua) == 0x007467)
        #expect(try hex(EmberDesign.Brand.nsAccentMark, in: .darkAqua) == 0x6BE6D2)
        #expect(try hex(EmberDesign.Brand.nsAccentMark, in: .vibrantDark) == 0x6BE6D2)

        let mark = EmberDesign.Brand.accentMarkVariants
        #expect(mark.hex(isDark: false, isHighContrast: false) == 0x007467)
        #expect(mark.hex(isDark: true, isHighContrast: false) == 0x6BE6D2)
        #expect(mark.hex(isDark: false, isHighContrast: true) == 0x00534A)
        #expect(mark.hex(isDark: true, isHighContrast: true) == 0xA5F3E4)
        // The accent fill doesn't change under Increase Contrast.
        #expect(EmberDesign.Brand.accentVariants.hex(isDark: false, isHighContrast: true) == 0x006459)
        #expect(EmberDesign.Brand.accentVariants.hex(isDark: true, isHighContrast: true) == 0x51D7C2)
    }

    @Test
    func appearanceTraits() throws {
        let traits = EmberDesign.Brand.traits(of:)
        #expect(traits(try #require(NSAppearance(named: .aqua))) == (false, false))
        #expect(traits(try #require(NSAppearance(named: .darkAqua))) == (true, false))
        #expect(traits(try #require(NSAppearance(named: .vibrantLight))) == (false, false))
        #expect(traits(try #require(NSAppearance(named: .vibrantDark))) == (true, false))
    }

    // MARK: Helpers

    private func resolve(_ color: NSColor, in name: NSAppearance.Name) throws -> NSColor {
        let appearance = try #require(NSAppearance(named: name))
        var resolved: NSColor?
        appearance.performAsCurrentDrawingAppearance {
            resolved = color.usingColorSpace(.sRGB)
        }
        return try #require(resolved)
    }

    private func hex(_ color: NSColor, in name: NSAppearance.Name) throws -> UInt32 {
        let resolved = try resolve(color, in: name)
        let red = UInt32((resolved.redComponent * 255).rounded())
        let green = UInt32((resolved.greenComponent * 255).rounded())
        let blue = UInt32((resolved.blueComponent * 255).rounded())
        return red << 16 | green << 8 | blue
    }

    static func color(_ hex: UInt32) -> NSColor {
        EmberDesign.Brand.color(hex: hex)
    }

    /// WCAG 2.x relative luminance of an sRGB colour.
    static func relativeLuminance(_ color: NSColor) -> Double {
        let srgb = color.usingColorSpace(.sRGB) ?? color
        func linear(_ component: CGFloat) -> Double {
            let value = Double(component)
            return value <= 0.04045 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * linear(srgb.redComponent) + 0.7152 * linear(srgb.greenComponent) + 0.0722 * linear(srgb.blueComponent)
    }

    static func contrastRatio(_ first: NSColor, _ second: NSColor) -> Double {
        let a = relativeLuminance(first)
        let b = relativeLuminance(second)
        return (max(a, b) + 0.05) / (min(a, b) + 0.05)
    }
}
