import Foundation
@testable import PIApp
import Testing

/// "Open at login" as Settings › General shows it, with the system replaced by a fake.
struct LaunchAtLoginModelTests {
    @Test func itStartsFromWhatTheSystemSays() {
        #expect(LaunchAtLoginModel(service: FakeLoginItems(status: .enabled)).isEnabled)
        #expect(!LaunchAtLoginModel(service: FakeLoginItems(status: .notRegistered)).isEnabled)
        #expect(!LaunchAtLoginModel(service: FakeLoginItems(status: .notFound)).isEnabled)
    }

    @Test func turningItOnRegistersTheApp() {
        let service = FakeLoginItems(status: .notRegistered)
        let model = LaunchAtLoginModel(service: service)

        model.setEnabled(true)

        #expect(service.requests == [true])
        #expect(model.isEnabled)
        #expect(!model.requiresApproval)
        #expect(model.errorMessage == nil)
    }

    @Test func turningItOffUnregistersTheApp() {
        let service = FakeLoginItems(status: .enabled)
        let model = LaunchAtLoginModel(service: service)

        model.setEnabled(false)

        #expect(service.requests == [false])
        #expect(!model.isEnabled)
    }

    @Test func aRegistrationWaitingForTheUserIsReported() {
        let service = FakeLoginItems(status: .notRegistered)
        service.statusAfterEnabling = .requiresApproval
        let model = LaunchAtLoginModel(service: service)

        model.setEnabled(true)

        #expect(!model.isEnabled)
        #expect(model.requiresApproval)
    }

    @Test func aFailureIsKeptForTheSettingAndClearedByTheNextChange() {
        let service = FakeLoginItems(status: .notRegistered)
        service.failure = FakeLoginItems.Failure()
        let model = LaunchAtLoginModel(service: service)

        model.setEnabled(true)
        #expect(model.errorMessage == "The system said no.")
        #expect(!model.isEnabled)

        service.failure = nil
        model.setEnabled(true)
        #expect(model.errorMessage == nil)
        #expect(model.isEnabled)
    }

    @Test func refreshPicksUpAChangeMadeInSystemSettings() {
        let service = FakeLoginItems(status: .enabled)
        let model = LaunchAtLoginModel(service: service)

        service.status = .requiresApproval
        model.refresh()

        #expect(!model.isEnabled)
        #expect(model.requiresApproval)
    }

    @Test func systemSettingsOpensThroughTheService() {
        let service = FakeLoginItems(status: .requiresApproval)

        LaunchAtLoginModel(service: service).openSystemSettings()

        #expect(service.openedSystemSettings)
    }
}

/// Records what is asked of it instead of registering anything with the system.
private final class FakeLoginItems: LoginItemServicing {
    struct Failure: LocalizedError {
        var errorDescription: String? { "The system said no." }
    }

    var status: LoginItemStatus
    var statusAfterEnabling: LoginItemStatus = .enabled
    var failure: (any Error)?
    private(set) var requests: [Bool] = []
    private(set) var openedSystemSettings = false

    init(status: LoginItemStatus) {
        self.status = status
    }

    func setEnabled(_ isEnabled: Bool) throws {
        requests.append(isEnabled)
        if let failure { throw failure }
        status = isEnabled ? statusAfterEnabling : .notRegistered
    }

    func openSystemSettings() {
        openedSystemSettings = true
    }
}
