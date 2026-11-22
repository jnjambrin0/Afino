import AppKit

/// Where this copy of the app runs from, as far as updating it goes.
@MainActor
enum InstallState: Equatable {
    /// In `/Applications` or `~/Applications`, on a writable volume: an update can replace it.
    case updatable
    /// Anywhere else (a disk image, Downloads), on a read-only volume, or translocated by
    /// Gatekeeper's App Translocation, which runs a quarantined app from a randomised read-only
    /// path.
    case notInApplications(readOnly: Bool, translocated: Bool)
}

/// Checks where the app runs from and moves it to Applications.
@MainActor
protocol InstallLocationManaging {
    func evaluateInstallState() -> InstallState
    /// Copies the app to Applications (falling back to `~/Applications` when the system folder
    /// cannot be written), opens the copy and terminates this one. Returns the copy's location,
    /// or this copy's when it is already updatable.
    func moveAndRelaunchIfNeeded() async throws -> URL
}

/// Opens an application through `NSWorkspace`; a seam for tests.
@MainActor
protocol WorkspaceApplicationLaunching {
    func openApplication(
        at url: URL,
        configuration: NSWorkspace.OpenConfiguration,
        completionHandler: @escaping @Sendable (NSRunningApplication?, (any Error)?) -> Void
    )
}

/// `NSWorkspace.shared`.
struct SystemWorkspaceApplicationLauncher: WorkspaceApplicationLaunching {
    func openApplication(
        at url: URL,
        configuration: NSWorkspace.OpenConfiguration,
        completionHandler: @escaping @Sendable (NSRunningApplication?, (any Error)?) -> Void
    ) {
        NSWorkspace.shared.openApplication(at: url, configuration: configuration, completionHandler: completionHandler)
    }
}

/// Opens a new instance of an application with `open -n`; a seam for tests.
@MainActor
protocol OpenCommandLaunching {
    func openNewInstance(at destination: URL) throws
}

/// Runs `/usr/bin/open -n` and waits for it.
struct SystemOpenCommandLauncher: OpenCommandLaunching {
    func openNewInstance(at destination: URL) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        process.arguments = ["-n", destination.path]

        try process.run()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            throw InstallLocationManager.Error.relaunchFailed("Fallback relaunch with /usr/bin/open failed (status \(process.terminationStatus)).")
        }
    }
}

/// Decides whether this copy can be updated where it is and, when it cannot, copies it to
/// Applications and hands over to the copy.
///
/// A copy already in the destination is replaced only when it has the same bundle identifier, so
/// another app that happens to share the name is never deleted. The copy is opened through
/// `NSWorkspace` as a new instance; when that does not report the copy as running, `open -n` is
/// tried before giving up, and this copy terminates only once one of them succeeded.
///
/// Every collaborator can be injected, so the tests run against temporary folders and fake
/// launchers instead of the real bundle and `/Applications`.
@MainActor
final class InstallLocationManager: InstallLocationManaging {
    enum Error: LocalizedError {
        case missingBundleIdentifier
        /// The destination holds an app with another bundle identifier, which is left alone.
        case destinationBundleIdentifierMismatch(expected: String, found: String?)
        case relaunchFailed(String)

        var errorDescription: String? {
            switch self {
            case .missingBundleIdentifier:
                return "Could not determine the running app's bundle identifier."
            case let .destinationBundleIdentifierMismatch(expected, found):
                let actual = found ?? "(missing)"
                return "Existing destination app has bundle id \(actual), expected \(expected)."
            case let .relaunchFailed(message):
                return message
            }
        }
    }

    private let fileManager: FileManager
    private let workspaceLauncher: any WorkspaceApplicationLaunching
    private let openCommandLauncher: any OpenCommandLaunching
    private let appBundleURL: URL
    private let expectedBundleIdentifier: String?
    private let terminateCurrentApp: () -> Void
    private let systemApplicationsDirectoryURL: URL?
    private let userApplicationsDirectoryURL: URL?
    private let volumeReadOnlyEvaluator: (URL) -> Bool
    private let launchedApplicationVerifier: (NSRunningApplication, URL) -> Bool

    /// - Parameters:
    ///   - systemApplicationsDirectoryURL: Stands in for `/Applications`; nil uses the real one.
    ///   - userApplicationsDirectoryURL: Stands in for `~/Applications`; nil uses the real one.
    ///   - volumeReadOnlyEvaluator: Whether a URL is on a read-only volume.
    ///   - launchedApplicationVerifier: Whether the application `NSWorkspace` opened runs from the
    ///     copy, not from somewhere else.
    init(
        fileManager: FileManager = .default,
        workspaceLauncher: (any WorkspaceApplicationLaunching)? = nil,
        openCommandLauncher: (any OpenCommandLaunching)? = nil,
        appBundleURL: URL = Bundle.main.bundleURL,
        expectedBundleIdentifier: String? = Bundle.main.bundleIdentifier,
        terminateCurrentApp: (() -> Void)? = nil,
        systemApplicationsDirectoryURL: URL? = nil,
        userApplicationsDirectoryURL: URL? = nil,
        volumeReadOnlyEvaluator: ((URL) -> Bool)? = nil,
        launchedApplicationVerifier: ((NSRunningApplication, URL) -> Bool)? = nil
    ) {
        self.fileManager = fileManager
        self.workspaceLauncher = workspaceLauncher ?? SystemWorkspaceApplicationLauncher()
        self.openCommandLauncher = openCommandLauncher ?? SystemOpenCommandLauncher()
        self.appBundleURL = appBundleURL
        self.expectedBundleIdentifier = expectedBundleIdentifier
        self.terminateCurrentApp = terminateCurrentApp ?? { NSApplication.shared.terminate(nil) }
        self.systemApplicationsDirectoryURL = systemApplicationsDirectoryURL
        self.userApplicationsDirectoryURL = userApplicationsDirectoryURL
        self.volumeReadOnlyEvaluator = volumeReadOnlyEvaluator ?? InstallLocationManager.defaultVolumeReadOnlyEvaluator
        self.launchedApplicationVerifier = launchedApplicationVerifier ?? InstallLocationManager.defaultLaunchedApplicationVerifier
    }

    func evaluateInstallState() -> InstallState {
        let translocated = appBundleURL.path.contains("/AppTranslocation/")
        let readOnly = volumeReadOnlyEvaluator(appBundleURL)

        if isInsideSystemApplicationsDirectory(appBundleURL) || isInsideUserApplicationsDirectory(appBundleURL) {
            if !readOnly && !translocated {
                return .updatable
            }
        }

        return .notInApplications(readOnly: readOnly, translocated: translocated)
    }

    func moveAndRelaunchIfNeeded() async throws -> URL {
        if case .updatable = evaluateInstallState() {
            return appBundleURL
        }

        let expectedID = try requireExpectedBundleIdentifier()
        let appName = appBundleURL.lastPathComponent

        let destination = try copyToPreferredDestination(
            appName: appName,
            expectedBundleIdentifier: expectedID
        )

        try await relaunchMovedApp(at: destination)
        terminateCurrentApp()
        return destination
    }

    private func copyToPreferredDestination(appName: String, expectedBundleIdentifier: String) throws -> URL {
        let systemDestination = try systemApplicationsDirectory().appendingPathComponent(appName, isDirectory: true)
        do {
            return try copyReplacingExistingAppIfAllowed(
                destination: systemDestination,
                expectedBundleIdentifier: expectedBundleIdentifier
            )
        } catch {
            if shouldFallbackToUserApplications(for: error) {
                let userApplications = try userApplicationsDirectory(createIfMissing: true)
                let fallbackDestination = userApplications.appendingPathComponent(appName, isDirectory: true)
                return try copyReplacingExistingAppIfAllowed(
                    destination: fallbackDestination,
                    expectedBundleIdentifier: expectedBundleIdentifier
                )
            }
            throw error
        }
    }

    private func copyReplacingExistingAppIfAllowed(
        destination: URL,
        expectedBundleIdentifier: String
    ) throws -> URL {
        if fileManager.fileExists(atPath: destination.path) {
            let destinationBundleID = Bundle(url: destination)?.bundleIdentifier
            guard destinationBundleID == expectedBundleIdentifier else {
                throw Error.destinationBundleIdentifierMismatch(expected: expectedBundleIdentifier, found: destinationBundleID)
            }
            try fileManager.removeItem(at: destination)
        }

        try fileManager.copyItem(at: appBundleURL, to: destination)
        return destination
    }

    private func relaunchMovedApp(at destination: URL) async throws {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        configuration.createsNewApplicationInstance = true

        let launchResult = await launchApplicationWithWorkspace(at: destination, configuration: configuration)
        if let runningApp = launchResult.runningApp,
           launchedApplicationVerifier(runningApp, destination) {
            return
        }

        do {
            try openCommandLauncher.openNewInstance(at: destination)
        } catch {
            if let workspaceError = launchResult.error {
                let message = "Workspace relaunch failed (\(workspaceError.localizedDescription)); fallback relaunch failed (\(error.localizedDescription))."
                throw Error.relaunchFailed(message)
            }

            throw Error.relaunchFailed(error.localizedDescription)
        }
    }

    private func launchApplicationWithWorkspace(
        at destination: URL,
        configuration: NSWorkspace.OpenConfiguration
    ) async -> (runningApp: NSRunningApplication?, error: (any Swift.Error)?) {
        await withCheckedContinuation { continuation in
            workspaceLauncher.openApplication(at: destination, configuration: configuration) { runningApp, error in
                continuation.resume(returning: (runningApp: runningApp, error: error))
            }
        }
    }

    private func requireExpectedBundleIdentifier() throws -> String {
        guard let id = expectedBundleIdentifier, !id.isEmpty else {
            throw Error.missingBundleIdentifier
        }
        return id
    }

    private func shouldFallbackToUserApplications(for error: any Swift.Error) -> Bool {
        let nsError = error as NSError
        guard nsError.domain == NSCocoaErrorDomain else {
            return false
        }

        return nsError.code == CocoaError.fileWriteNoPermission.rawValue
            || nsError.code == CocoaError.fileWriteVolumeReadOnly.rawValue
            || nsError.code == CocoaError.fileNoSuchFile.rawValue
    }

    private func isInsideSystemApplicationsDirectory(_ url: URL) -> Bool {
        guard let systemApplications = try? systemApplicationsDirectory() else {
            return false
        }
        return relationshipContainsOrMatches(directory: systemApplications, item: url)
    }

    private func isInsideUserApplicationsDirectory(_ url: URL) -> Bool {
        guard let userApplications = try? userApplicationsDirectory(createIfMissing: false) else {
            return false
        }
        return relationshipContainsOrMatches(directory: userApplications, item: url)
    }

    private func relationshipContainsOrMatches(directory: URL, item: URL) -> Bool {
        var relationship: FileManager.URLRelationship = .other
        do {
            try fileManager.getRelationship(&relationship, ofDirectoryAt: directory, toItemAt: item)
            return relationship == .same || relationship == .contains
        } catch {
            return false
        }
    }

    private func systemApplicationsDirectory() throws -> URL {
        if let systemApplicationsDirectoryURL {
            return systemApplicationsDirectoryURL
        }
        return try fileManager.url(
            for: .applicationDirectory,
            in: .localDomainMask,
            appropriateFor: nil,
            create: false
        )
    }

    private func userApplicationsDirectory(createIfMissing: Bool) throws -> URL {
        if let userApplicationsDirectoryURL {
            if createIfMissing && !fileManager.fileExists(atPath: userApplicationsDirectoryURL.path) {
                try fileManager.createDirectory(at: userApplicationsDirectoryURL, withIntermediateDirectories: true)
            }
            return userApplicationsDirectoryURL
        }

        let url = try fileManager.url(
            for: .applicationDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: createIfMissing
        )

        if createIfMissing && !fileManager.fileExists(atPath: url.path) {
            try fileManager.createDirectory(at: url, withIntermediateDirectories: true)
        }

        return url
    }

    nonisolated private static func defaultVolumeReadOnlyEvaluator(_ url: URL) -> Bool {
        (try? url.resourceValues(forKeys: [.volumeIsReadOnlyKey]))?.volumeIsReadOnly ?? false
    }

    nonisolated private static func defaultLaunchedApplicationVerifier(_ runningApp: NSRunningApplication, destination: URL) -> Bool {
        guard let runningURL = runningApp.bundleURL else {
            return false
        }

        let lhs = runningURL.resolvingSymlinksInPath().standardizedFileURL
        let rhs = destination.resolvingSymlinksInPath().standardizedFileURL
        return lhs == rhs
    }
}
