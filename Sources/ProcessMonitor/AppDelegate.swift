import AppKit
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private var statusItem: NSStatusItem?
    private let settings = AppSettings()
    private lazy var model = ProcessListModel(settings: settings)

    private var panel: NSPanel?
    private var settingsWindow: NSWindow?
    private var welcomeWindow: NSWindow?
    private var outsideClickMonitor: Any?

    private static let panelSize = NSSize(width: 800, height: 520)

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        configureStatusItem()

        if !settings.didCompleteOnboarding {
            showWelcome()
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    // MARK: - Status item

    private func configureStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = item.button {
            let image = NSImage(systemSymbolName: "cpu", accessibilityDescription: AppSettings.appName)
            image?.isTemplate = true
            button.image = image
            button.toolTip = "\(AppSettings.appName) — \(AppSettings.tagline)"
            button.target = self
            button.action = #selector(statusItemClicked(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
        statusItem = item
    }

    @objc private func statusItemClicked(_ sender: Any?) {
        if NSApp.currentEvent?.type == .rightMouseUp {
            showStatusMenu()
        } else {
            togglePanel()
        }
    }

    private func showStatusMenu() {
        guard let item = statusItem else { return }
        let menu = NSMenu()
        menu.addItem(withTitle: "Open \(AppSettings.appName)", action: #selector(openPanel), keyEquivalent: "")
        menu.addItem(withTitle: "Settings…", action: #selector(showSettings), keyEquivalent: ",")
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit \(AppSettings.appName)", action: #selector(quit), keyEquivalent: "q")
        for menuItem in menu.items {
            menuItem.target = self
        }

        // Temporarily attach the menu so the button shows it, then detach so
        // left-clicks keep toggling the panel.
        item.menu = menu
        item.button?.performClick(nil)
        item.menu = nil
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }

    // MARK: - Main panel

    private var isPanelVisible: Bool {
        panel?.isVisible ?? false
    }

    @objc private func openPanel() {
        guard !isPanelVisible else { return }
        togglePanel()
    }

    @objc private func closePanel() {
        panel?.close()
    }

    private func togglePanel() {
        if isPanelVisible {
            closePanel()
            return
        }

        let panel = panel ?? makePanel()
        position(panel)
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: Self.panelSize),
            styleMask: [.titled, .closable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        panel.title = AppSettings.appName
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        panel.isMovableByWindowBackground = true
        panel.animationBehavior = .utilityWindow
        panel.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        panel.minSize = NSSize(width: 640, height: 360)
        panel.standardWindowButton(.closeButton)?.isHidden = true
        panel.standardWindowButton(.miniaturizeButton)?.isHidden = true
        panel.standardWindowButton(.zoomButton)?.isHidden = true
        panel.delegate = self

        let root = ProcessListView(
            model: model,
            openSettings: { [weak self] in self?.showSettings() },
            quitApp: { NSApp.terminate(nil) }
        )
        .onExitCommand { [weak self] in self?.closePanel() }
        panel.contentViewController = NSHostingController(rootView: root)
        panel.setContentSize(Self.panelSize)
        self.panel = panel
        return panel
    }

    /// Centers the panel horizontally under the status item, clamped to the screen.
    private func position(_ panel: NSPanel) {
        guard let button = statusItem?.button, let buttonWindow = button.window else {
            panel.center()
            return
        }
        let anchor = buttonWindow.convertToScreen(button.convert(button.bounds, to: nil))
        let screen = buttonWindow.screen ?? NSScreen.main
        let visible = screen?.visibleFrame ?? anchor
        let size = panel.frame.size

        var x = anchor.midX - size.width / 2
        x = min(max(x, visible.minX + 8), visible.maxX - size.width - 8)
        let y = max(anchor.minY - size.height - 6, visible.minY + 8)
        panel.setFrameOrigin(NSPoint(x: x, y: y))
    }

    /// Sampling is tied to visibility: it runs only while the panel is on screen.
    func windowDidBecomeKey(_ notification: Notification) {
        guard (notification.object as? NSPanel) === panel else { return }
        model.start()
        installDismissMonitors()
    }

    func windowWillClose(_ notification: Notification) {
        guard (notification.object as? NSPanel) === panel else { return }
        model.stop()
        removeDismissMonitors()
    }

    /// Close the panel when the user clicks anywhere outside it,
    /// mirroring popover behaviour while keeping a real key window for the table.
    private func installDismissMonitors() {
        removeDismissMonitors()
        outsideClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [
            .leftMouseDown,
            .rightMouseDown
        ]) { [weak self] _ in
            Task { @MainActor in self?.closePanel() }
        }
    }

    private func removeDismissMonitors() {
        if let monitor = outsideClickMonitor {
            NSEvent.removeMonitor(monitor)
            outsideClickMonitor = nil
        }
    }

    // MARK: - Auxiliary windows

    @objc private func showSettings() {
        if settingsWindow == nil {
            settingsWindow = makeWindow(
                title: "\(AppSettings.appName) Settings",
                rootView: SettingsView(settings: settings)
            )
        }
        present(settingsWindow)
    }

    private func showWelcome() {
        if welcomeWindow == nil {
            let view = WelcomeView(settings: settings) { [weak self] in
                guard let self else { return }
                settings.didCompleteOnboarding = true
                welcomeWindow?.close()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                    self.openPanel()
                }
            }
            welcomeWindow = makeWindow(title: "Welcome to \(AppSettings.appName)", rootView: view)
        }
        present(welcomeWindow)
    }

    private func makeWindow(title: String, rootView: some View) -> NSWindow {
        let window = NSWindow(
            contentRect: .zero,
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = title
        window.isReleasedWhenClosed = false
        let controller = NSHostingController(rootView: rootView)
        window.contentViewController = controller
        window.setContentSize(controller.view.fittingSize)
        window.center()
        return window
    }

    private func present(_ window: NSWindow?) {
        guard let window else { return }
        closePanel()
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }
}
