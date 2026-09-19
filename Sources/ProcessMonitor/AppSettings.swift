import Combine
import Foundation
import ServiceManagement

// MARK: - AppSettings

/// User-facing preferences, persisted in `UserDefaults`.
final class AppSettings: ObservableObject {
    private enum Keys {
        static let didCompleteOnboarding = "didCompleteOnboarding"
        static let refreshInterval = "refreshInterval"
        static let groupByParent = "groupByParent"
    }

    static let appName = "ProcessMonitor"
    static let tagline = "Discover and control processes on Mac"
    static let description = """
    ProcessMonitor lives in your menu bar and gives you an Activity Monitor–style view of \
    everything running on your Mac: CPU, GPU, memory and energy usage for each process, \
    along with its PID and the user it belongs to. Search for a process, sort by any column, \
    and quit or force-quit anything that misbehaves.

    It is designed to stay out of the way. The process list is only sampled while the panel \
    is open; when it is closed, ProcessMonitor does no work at all.
    """

    static var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev"
    }

    private let defaults: UserDefaults

    @Published var didCompleteOnboarding: Bool {
        didSet { defaults.set(didCompleteOnboarding, forKey: Keys.didCompleteOnboarding) }
    }

    /// Seconds between samples while the panel is visible.
    @Published var refreshInterval: Double {
        didSet { defaults.set(refreshInterval, forKey: Keys.refreshInterval) }
    }

    /// Show each process together with its child processes as one collapsible group.
    @Published var groupByParent: Bool {
        didSet { defaults.set(groupByParent, forKey: Keys.groupByParent) }
    }

    @Published var launchAtLogin: Bool {
        didSet {
            guard launchAtLogin != LaunchAtLogin.isEnabled else { return }
            do {
                try LaunchAtLogin.set(enabled: launchAtLogin)
                launchAtLoginError = nil
            } catch {
                launchAtLoginError = error.localizedDescription
                // Revert to the real state without re-triggering this observer.
                DispatchQueue.main.async { [weak self] in
                    self?.launchAtLogin = LaunchAtLogin.isEnabled
                }
            }
        }
    }

    @Published private(set) var launchAtLoginError: String?

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        didCompleteOnboarding = defaults.bool(forKey: Keys.didCompleteOnboarding)
        let storedInterval = defaults.double(forKey: Keys.refreshInterval)
        refreshInterval = storedInterval > 0 ? storedInterval : 2.0
        groupByParent = defaults.object(forKey: Keys.groupByParent) as? Bool ?? true
        launchAtLogin = LaunchAtLogin.isEnabled
    }
}

// MARK: - LaunchAtLogin

/// Thin wrapper over `SMAppService` for the "Launch at login" preference.
enum LaunchAtLogin {
    static var isAvailable: Bool {
        // SMAppService needs a real .app bundle. When run via `swift run` there is none.
        Bundle.main.bundleIdentifier != nil && Bundle.main.bundleURL.pathExtension == "app"
    }

    static var isEnabled: Bool {
        guard isAvailable else { return false }
        return SMAppService.mainApp.status == .enabled
    }

    static func set(enabled: Bool) throws {
        guard isAvailable else {
            throw LaunchAtLoginError.notInBundle
        }
        if enabled {
            try SMAppService.mainApp.register()
        } else {
            try SMAppService.mainApp.unregister()
        }
    }

    enum LaunchAtLoginError: LocalizedError {
        case notInBundle

        var errorDescription: String? {
            "Launch at login is only available when ProcessMonitor is installed as an app (e.g. in /Applications)."
        }
    }
}
