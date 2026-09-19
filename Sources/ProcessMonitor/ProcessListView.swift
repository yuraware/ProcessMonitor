import AppKit
import SwiftUI

/// The main panel: an Activity Monitor–style table of processes.
struct ProcessListView: View {
    @ObservedObject var model: ProcessListModel
    var openSettings: () -> Void
    var quitApp: () -> Void

    private static let byteFormatter: ByteCountFormatter = {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .memory
        formatter.allowedUnits = [.useKB, .useMB, .useGB]
        return formatter
    }()

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.timeStyle = .medium
        formatter.dateStyle = .none
        return formatter
    }()

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            table
            Divider()
            footer
        }
        .frame(minWidth: 640, minHeight: 360)
    }

    // MARK: - Sections

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: "cpu")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.secondary)
            Text(AppSettings.appName)
                .font(.headline)
            Spacer()
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Search by name, PID or user", text: $model.filter)
                    .textFieldStyle(.plain)
                if !model.filter.isEmpty {
                    Button {
                        model.filter = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(RoundedRectangle(cornerRadius: 7).fill(Color(nsColor: .controlBackgroundColor)))
            .overlay(RoundedRectangle(cornerRadius: 7).stroke(Color(nsColor: .separatorColor)))
            .frame(width: 240)
            Toggle(isOn: Binding(
                get: { model.settings.groupByParent },
                set: { model.settings.groupByParent = $0 }
            )) {
                Image(systemName: "list.bullet.indent")
            }
            .toggleStyle(.button)
            .help("Group processes with their child processes")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private var table: some View {
        Table(model.rows, selection: $model.selection, sortOrder: $model.sortOrder) {
            TableColumn("") { row in
                Toggle("", isOn: Binding(
                    get: { model.isChecked(row) },
                    set: { model.setChecked(row, $0) }
                ))
                .toggleStyle(.checkbox)
                .labelsHidden()
                .help(row.isGroup ? "Select the whole group to quit" : "Select to quit")
            }
            .width(22)

            TableColumn("Process Name", value: \.name) { row in
                nameCell(row)
            }
            .width(min: 180, ideal: 240)

            TableColumn("% CPU", value: \.cpu) { entry in
                numeric(entry.isAvailable ? String(format: "%.1f", entry.cpu) : "—")
            }
            .width(min: 60, ideal: 70)

            TableColumn("% GPU", value: \.gpu) { entry in
                numeric(entry.hasGPU ? String(format: "%.1f", entry.gpu) : "—")
                    .help("Per-process GPU usage is not exposed by public macOS APIs.")
            }
            .width(min: 60, ideal: 70)

            TableColumn("Memory", value: \.memory) { entry in
                numeric(entry.isAvailable ? Self.byteFormatter.string(fromByteCount: Int64(entry.memory)) : "—")
            }
            .width(min: 80, ideal: 90)

            TableColumn("Energy", value: \.energy) { entry in
                numeric(entry.isAvailable ? String(format: "%.1f", entry.energy) : "—")
                    .help("Approximate energy impact: CPU usage plus a penalty for idle wake-ups.")
            }
            .width(min: 60, ideal: 70)

            TableColumn("PID", value: \.id) { entry in
                numeric(String(entry.id))
            }
            .width(min: 60, ideal: 70)

            TableColumn("User", value: \.user) { entry in
                Text(entry.user)
                    .foregroundStyle(entry.isAvailable ? .primary : .secondary)
            }
            .width(min: 80, ideal: 100)
        }
        .contextMenu(forSelectionType: pid_t.self) { pids in
            if !pids.isEmpty {
                Button(model.areChecked(pids) ? "Uncheck" : "Check") {
                    model.setChecked(pids, !model.areChecked(pids))
                }
            }
            let expandable = pids.filter(model.isExpandable)
            if !expandable.isEmpty {
                Button(expandable.allSatisfy(model.expanded.contains) ? "Collapse" : "Expand") {
                    let expand = !expandable.allSatisfy(model.expanded.contains)
                    for pid in expandable where model.expanded.contains(pid) != expand {
                        model.toggleExpanded(pid)
                    }
                }
            }
            if model.isGrouped {
                Divider()
                Button("Expand All") {
                    model.expandAll()
                }
                Button("Collapse All") {
                    model.collapseAll()
                }
            }
        }
    }

    /// Name plus icon, indented for group members, with a disclosure chevron and member count for groups.
    private func nameCell(_ row: ProcessRow) -> some View {
        HStack(spacing: 6) {
            if model.isGrouped {
                if row.isGroup {
                    Button {
                        model.toggleExpanded(row.id)
                    } label: {
                        Image(systemName: row.isExpanded ? "chevron.down" : "chevron.right")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .frame(width: 12, height: 16)
                    }
                    .buttonStyle(.plain)
                    .help(row.isExpanded ? "Collapse" : "Expand \(row.memberCount) child processes")
                } else {
                    Color.clear.frame(width: 12 + CGFloat(row.depth) * 16, height: 16)
                }
            }
            Image(nsImage: model.icon(for: row.id))
                .resizable()
                .frame(width: 16, height: 16)
            Text(row.name)
                .lineLimit(1)
                .truncationMode(.middle)
            if row.isGroup, model.isGrouped {
                Text("\(row.memberCount + 1)")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .background(Capsule().fill(Color(nsColor: .quaternaryLabelColor)))
                    .help(row.isExpanded ? "Showing own usage" : "Combined usage of \(row.memberCount + 1) processes")
            }
        }
        .help(row.path.isEmpty ? row.name : row.path)
    }

    private var footer: some View {
        HStack(spacing: 12) {
            Text(statusText)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Spacer()
            if !model.checked.isEmpty {
                Button("Uncheck All") {
                    model.uncheckAll()
                }
                .disabled(model.isQuitting)
            }
            Button(quitTitle("Quit")) {
                model.quitTargets(force: false)
            }
            .disabled(model.quitTargets.isEmpty || model.isQuitting)
            Button(quitTitle("Force Quit")) {
                model.quitTargets(force: true)
            }
            .disabled(model.quitTargets.isEmpty || model.isQuitting)
            Divider().frame(height: 16)
            Button {
                openSettings()
            } label: {
                Image(systemName: "gearshape")
            }
            .help("Settings")
            Button {
                quitApp()
            } label: {
                Image(systemName: "power")
            }
            .help("Quit \(AppSettings.appName)")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    // MARK: - Helpers

    private func quitTitle(_ verb: String) -> String {
        let count = model.quitTargets.count
        return count > 1 ? "\(verb) \(count)" : verb
    }

    private var statusText: String {
        if let progress = model.quitProgress {
            return progress
        }
        let total = model.entries.count
        let shown = model.filteredEntries.count
        var parts: [String] = []
        parts.append(shown == total ? "\(total) processes" : "\(shown) of \(total) processes")
        if !model.checked.isEmpty {
            parts.append("\(model.checked.count) checked")
        }
        if let updated = model.lastUpdated {
            parts.append("updated \(Self.timeFormatter.string(from: updated))")
        }
        return parts.joined(separator: " · ")
    }

    private func numeric(_ text: String) -> some View {
        Text(text)
            .monospacedDigit()
            .frame(maxWidth: .infinity, alignment: .trailing)
    }
}
