@testable import PIApp
import PICore
import PIDesign
import PIPrompts
import Testing

/// The "Default target" select, built from the target packs.
struct DefaultTargetOptionsTests {
    private static let packs = (try? TargetPackLibrary.bundled().packs) ?? []
    private static var targets: [TargetSummary] { packs.map(TargetSummary.init(pack:)) }

    @Test func lastUsedComesFirstThenEveryPackInPickerOrder() throws {
        try #require(!Self.packs.isEmpty)
        let options = DefaultTargetOptions.options(targets: Self.targets)
        #expect(options.first == .lastUsed)
        #expect(options.dropFirst() == ArraySlice(Self.packs.map { DefaultTarget.fixed(id: $0.id) }))
        #expect(options.count == Self.packs.count + 1)
    }

    @Test func eachOptionIsTitledByItsPack() throws {
        try #require(!Self.packs.isEmpty)
        for pack in Self.packs {
            #expect(DefaultTargetOptions.title(for: .fixed(id: pack.id), targets: Self.targets) == pack.displayName)
        }
        #expect(DefaultTargetOptions.title(for: .lastUsed, targets: Self.targets) != "settings.general.defaultTarget.lastUsed")
    }

    @Test func packsKeepTheirMonograms() throws {
        let claude = try #require(Self.packs.first { $0.id == "claude" })
        #expect(TargetSummary(pack: claude).monogram == .letters("Cl"))
        let generic = try #require(Self.packs.first { $0.id == "generic" })
        #expect(TargetSummary(pack: generic).monogram == .symbol("circle.dotted"))
        #expect(DefaultTargetOptions.monogram(for: .lastUsed, targets: Self.targets) != nil)
    }

    @Test func aRemovedPackReadsAsLastUsed() {
        let targets = SettingsSamples.targets
        #expect(DefaultTargetOptions.selection(for: .fixed(id: "gpt"), targets: targets) == .fixed(id: "gpt"))
        #expect(DefaultTargetOptions.selection(for: .fixed(id: "retired"), targets: targets) == .lastUsed)
        #expect(DefaultTargetOptions.selection(for: .lastUsed, targets: targets) == .lastUsed)
    }
}
