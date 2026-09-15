import SwiftUI

// MARK: - AboutSection

/// Shared header + explanation used by both the settings and welcome screens.
struct AboutSection: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .frame(width: 56, height: 56)
                VStack(alignment: .leading, spacing: 2) {
                    Text(AppSettings.appName)
                        .font(.title2.weight(.semibold))
                    Text(AppSettings.tagline)
                        .foregroundStyle(.secondary)
                }
            }
            Text(AppSettings.description)
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

// MARK: - LaunchAtLoginToggle

struct LaunchAtLoginToggle: View {
    @ObservedObject var settings: AppSettings

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Toggle("Launch at login", isOn: $settings.launchAtLogin)
                .toggleStyle(.checkbox)
            Text(
                "Start ProcessMonitor automatically when you log in to your Mac. "
                    + "It only appears in the menu bar and uses no CPU until you open it."
            )
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
            if let error = settings.launchAtLoginError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

// MARK: - SettingsView

/// The Settings window.
struct SettingsView: View {
    @ObservedObject var settings: AppSettings

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            AboutSection()
            Divider()
            LaunchAtLoginToggle(settings: settings)
            HStack {
                Text("Refresh every")
                Picker("Refresh every", selection: $settings.refreshInterval) {
                    Text("1 second").tag(1.0)
                    Text("2 seconds").tag(2.0)
                    Text("5 seconds").tag(5.0)
                }
                .labelsHidden()
                .frame(width: 130)
            }
            Text("Sampling only happens while the panel is open.")
                .font(.caption)
                .foregroundStyle(.secondary)
            Divider()
            Text("Version \(AppSettings.version)")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(24)
        .frame(width: 460)
    }
}

// MARK: - WelcomeView

/// Shown once, on first launch.
struct WelcomeView: View {
    @ObservedObject var settings: AppSettings
    var onContinue: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            AboutSection()
            Divider()
            LaunchAtLoginToggle(settings: settings)
            Divider()
            HStack {
                Label("Look for the CPU icon in your menu bar.", systemImage: "cpu")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Get Started") {
                    onContinue()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 460)
    }
}
