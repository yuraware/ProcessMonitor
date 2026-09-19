import AppKit
import Combine
import Foundation
import SwiftUI

/// Drives the process table. Sampling runs only between `start()` and `stop()`,
/// which the app ties to the popover being visible.
@MainActor
final class ProcessListModel: ObservableObject {
    @Published private(set) var entries: [ProcessEntry] = []
    @Published var selection = Set<pid_t>()
    /// Processes ticked in the checkbox column, i.e. the ones to quit.
    @Published var checked = Set<pid_t>()
    @Published private(set) var quitProgress: String?
    @Published var sortOrder: [KeyPathComparator<ProcessRow>] = [KeyPathComparator(\.cpu, order: .reverse)]
    @Published var filter = ""
    /// Group roots whose members are currently shown. Groups start collapsed.
    @Published var expanded = Set<pid_t>()
    @Published private(set) var lastUpdated: Date?
    @Published private(set) var isRunning = false

    private(set) var icons: [pid_t: NSImage] = [:]
    private(set) var tree = ProcessTree(entries: [])

    let settings: AppSettings

    private let sampler = ProcessSampler()
    private let queue = DispatchQueue(label: "com.yuraware.ProcessMonitor.sampler", qos: .utility)
    private var timer: Timer?
    private var quitTask: Task<Void, Never>?
    private var cancellables = Set<AnyCancellable>()
    private lazy var genericIcon: NSImage = {
        let icon = NSWorkspace.shared.icon(for: .unixExecutable)
        icon.size = NSSize(width: 16, height: 16)
        return icon
    }()

    init(settings: AppSettings) {
        self.settings = settings
        // `@Published` emits from `willSet`, so use the incoming value rather than re-reading the setting.
        settings.$refreshInterval
            .dropFirst()
            .sink { [weak self] interval in
                guard let self, isRunning else { return }
                scheduleTimer(interval: interval)
            }
            .store(in: &cancellables)
        settings.$groupByParent
            .dropFirst()
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)
    }

    /// Whether the table is showing groups right now. Searching always shows a flat list.
    var isGrouped: Bool {
        settings.groupByParent && filter.trimmingCharacters(in: .whitespaces).isEmpty
    }

    /// The table rows: groups with their expanded members, or a flat sorted list when searching.
    var rows: [ProcessRow] {
        if isGrouped {
            return tree.rows(expanded: expanded, sortOrder: sortOrder)
        }
        return ProcessRow.flat(filteredEntries, sortOrder: sortOrder)
    }

    /// Entries matching the search filter, unsorted.
    var filteredEntries: [ProcessEntry] {
        let trimmed = filter.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty {
            return entries
        }
        if let pid = pid_t(trimmed) {
            return entries.filter { $0.id == pid || $0.name.localizedCaseInsensitiveContains(trimmed) }
        }
        return entries.filter {
            $0.name.localizedCaseInsensitiveContains(trimmed)
                || $0.user.localizedCaseInsensitiveContains(trimmed)
                || $0.path.localizedCaseInsensitiveContains(trimmed)
        }
    }

    var selectedEntries: [ProcessEntry] {
        entries.filter { selection.contains($0.id) }
    }

    func icon(for pid: pid_t) -> NSImage {
        icons[pid] ?? genericIcon
    }

    // MARK: - Lifecycle

    /// Begin sampling. Takes a baseline immediately, a real sample shortly after
    /// (so CPU% is populated quickly), then continues at the configured interval.
    func start() {
        guard !isRunning else { return }
        isRunning = true
        sampler.reset()
        refresh()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
            guard let self, isRunning else { return }
            refresh()
        }
        scheduleTimer()
    }

    /// Stop sampling entirely. No timers or work remain after this returns.
    func stop() {
        timer?.invalidate()
        timer = nil
        isRunning = false
    }

    private func scheduleTimer(interval: Double? = nil) {
        timer?.invalidate()
        let interval = max(0.5, interval ?? settings.refreshInterval)
        let timer = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
        timer.tolerance = interval * 0.1
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func refresh() {
        let sampler = sampler
        queue.async { [weak self] in
            let result = sampler.sample()
            DispatchQueue.main.async {
                guard let self, self.isRunning else { return }
                self.icons = result.icons
                self.tree = ProcessTree(entries: result.entries)
                self.entries = result.entries
                self.lastUpdated = Date()
                let live = Set(result.entries.map(\.id))
                let liveExpanded = self.expanded.intersection(live)
                if liveExpanded != self.expanded {
                    self.expanded = liveExpanded
                }
                let liveSelection = self.selection.intersection(live)
                if liveSelection != self.selection {
                    self.selection = liveSelection
                }
                let liveChecked = self.checked.intersection(live)
                if liveChecked != self.checked {
                    self.checked = liveChecked
                }
            }
        }
    }

    // MARK: - Process control

    /// Processes the quit buttons act on: the checked rows, or the highlighted rows when nothing is checked.
    var quitTargets: [ProcessEntry] {
        let pids = checked.isEmpty ? selection : checked
        return entries.filter { pids.contains($0.id) }
    }

    var isQuitting: Bool {
        quitTask != nil
    }

    func isChecked(_ pid: pid_t) -> Bool {
        checked.contains(pid)
    }

    /// A group row counts as checked only when the root and every member are checked.
    func isChecked(_ row: ProcessRow) -> Bool {
        pids(for: row).allSatisfy(checked.contains)
    }

    func setChecked(_ pid: pid_t, _ value: Bool) {
        if value {
            checked.insert(pid)
        } else {
            checked.remove(pid)
        }
    }

    /// Checking a group row checks the root together with all of its members.
    func setChecked(_ row: ProcessRow, _ value: Bool) {
        for pid in pids(for: row) {
            setChecked(pid, value)
        }
    }

    /// Group-aware version of `setChecked` for a set of selected rows.
    func setChecked(_ pids: Set<pid_t>, _ value: Bool) {
        for row in rows where pids.contains(row.id) {
            setChecked(row, value)
        }
        // Selected pids that are not visible rows (e.g. members of a collapsed group) are left alone.
    }

    /// Group-aware version of `isChecked` for a set of selected rows.
    func areChecked(_ pids: Set<pid_t>) -> Bool {
        let visible = rows.filter { pids.contains($0.id) }
        return !visible.isEmpty && visible.allSatisfy(isChecked)
    }

    private func pids(for row: ProcessRow) -> [pid_t] {
        row.isGroup && isGrouped ? tree.members(of: row.id) : [row.id]
    }

    // MARK: - Grouping

    func isExpandable(_ pid: pid_t) -> Bool {
        isGrouped && !tree.descendants(of: pid).isEmpty
    }

    func toggleExpanded(_ pid: pid_t) {
        if expanded.contains(pid) {
            expanded.remove(pid)
        } else {
            expanded.insert(pid)
        }
    }

    func expandAll() {
        expanded = Set(tree.groupRoots)
    }

    func collapseAll() {
        expanded.removeAll()
    }

    func uncheckAll() {
        checked.removeAll()
    }

    /// Quits the target processes one by one. Each process gets SIGTERM (or SIGKILL when `force`)
    /// and the next one is only signalled after the previous one has exited or timed out.
    func quitTargets(force: Bool) {
        guard quitTask == nil else { return }
        let targets = quitTargets
        guard !targets.isEmpty, confirmQuit(targets, force: force) else { return }

        let total = targets.count
        quitTask = Task { @MainActor [weak self] in
            var failures: [String] = []
            await ProcessTerminator.quit(
                targets.map { ProcessTerminator.Target(pid: $0.id, name: $0.name) },
                force: force,
                willQuit: { index, target in
                    self?.quitProgress = "Quitting \(target.name) (\(index + 1) of \(total))…"
                },
                didQuit: { target, outcome in
                    switch outcome {
                    case .exited:
                        self?.checked.remove(target.pid)
                        self?.selection.remove(target.pid)
                    case .timedOut:
                        failures.append("\(target.name) (PID \(target.pid)): did not exit in time")
                    case let .failed(reason):
                        failures.append("\(target.name) (PID \(target.pid)): \(reason)")
                    }
                    if self?.isRunning == true {
                        self?.refresh()
                    }
                }
            )
            guard let self else { return }
            quitProgress = nil
            quitTask = nil
            if !failures.isEmpty {
                showFailures(failures)
            }
        }
    }

    private func confirmQuit(_ targets: [ProcessEntry], force: Bool) -> Bool {
        let alert = NSAlert()
        let verb = force ? "Force quit" : "Quit"
        if targets.count == 1 {
            alert.messageText = "\(verb) “\(targets[0].name)”?"
        } else {
            alert.messageText = "\(verb) \(targets.count) processes?"
        }
        let names = targets.prefix(10).map { "• \($0.name) (PID \($0.id))" }
        var details = names.joined(separator: "\n")
        if targets.count > names.count {
            details += "\n…and \(targets.count - names.count) more"
        }
        alert.informativeText = details + "\n\nThey will be quit one at a time."
            + (force ? " Force quitting kills immediately and unsaved changes will be lost." : "")
        alert.alertStyle = force ? .critical : .warning
        alert.addButton(withTitle: verb)
        alert.addButton(withTitle: "Cancel")
        NSApp.activate(ignoringOtherApps: true)
        return alert.runModal() == .alertFirstButtonReturn
    }

    private func showFailures(_ failures: [String]) {
        let alert = NSAlert()
        alert.messageText = "Some processes could not be quit"
        alert.informativeText = failures.joined(separator: "\n")
            + "\n\nProcesses owned by other users or the system require administrator privileges."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "OK")
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }
}
