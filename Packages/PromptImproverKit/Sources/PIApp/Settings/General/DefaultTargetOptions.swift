import PICore
import PIDesign
import PIPrompts

/// A target as Settings lists it: its id, its name and its monogram.
struct TargetSummary: Hashable, Sendable {
    let id: String
    let name: String
    let monogram: EMonogram

    init(id: String, name: String, monogram: EMonogram) {
        self.id = id
        self.name = name
        self.monogram = monogram
    }

    init(pack: TargetPack) {
        let monogram: EMonogram = switch pack.badge {
        case .monogram(let letters): .letters(letters)
        case .symbol(let symbol): .symbol(symbol)
        }
        self.init(id: pack.id, name: pack.displayName, monogram: monogram)
    }
}

/// The "Default target" select: "Last used", then every target in picker order.
enum DefaultTargetOptions {
    static func options(targets: [TargetSummary]) -> [DefaultTarget] {
        [.lastUsed] + targets.map { .fixed(id: $0.id) }
    }

    /// What the select shows for the stored setting: a fixed target that no longer exists (a pack
    /// removed in an update) reads as "Last used", which is also how the panel treats it.
    static func selection(for stored: DefaultTarget, targets: [TargetSummary]) -> DefaultTarget {
        guard case .fixed(let id) = stored, !targets.contains(where: { $0.id == id }) else { return stored }
        return .lastUsed
    }

    static func title(for option: DefaultTarget, targets: [TargetSummary]) -> String {
        switch option {
        case .lastUsed:
            SettingsStrings.text("settings.general.defaultTarget.lastUsed")
        case .fixed(let id):
            targets.first { $0.id == id }?.name ?? id
        }
    }

    static func monogram(for option: DefaultTarget, targets: [TargetSummary]) -> EMonogram? {
        switch option {
        case .lastUsed: .symbol("clock.arrow.circlepath")
        case .fixed(let id): targets.first { $0.id == id }?.monogram
        }
    }
}
