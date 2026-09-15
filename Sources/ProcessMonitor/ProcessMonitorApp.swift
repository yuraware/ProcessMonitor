import AppKit

@main
enum ProcessMonitorApp {
    @MainActor
    static func main() {
        let arguments = CommandLine.arguments
        if arguments.contains("--dump") {
            dumpProcessTable()
            return
        }
        if let index = arguments.firstIndex(where: { $0 == "--quit" || $0 == "--force-quit" }) {
            quitFromCommandLine(
                pids: arguments[(index + 1)...].compactMap { pid_t($0) },
                force: arguments[index] == "--force-quit"
            )
            return
        }
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.run()
    }

    /// Headless diagnostic: samples twice and prints the busiest processes.
    /// Usage: ProcessMonitor --dump
    private static func dumpProcessTable() {
        let sampler = ProcessSampler()
        _ = sampler.sample()
        Thread.sleep(forTimeInterval: 1.0)
        let result = sampler.sample()
        let rows = result.entries.sorted { $0.cpu > $1.cpu }
        let available = rows.filter(\.isAvailable).count

        func pad(_ text: String, _ width: Int, left: Bool = false) -> String {
            let padding = String(repeating: " ", count: max(0, width - text.count))
            return left ? text + padding : padding + text
        }
        func value(_ show: Bool, _ text: @autoclosure () -> String) -> String {
            show ? text() : "—"
        }

        let columns = ["Process Name", "% CPU", "% GPU", "Memory", "Energy", "PID", "User"]
        let widths = [36, 7, 7, 10, 8, 7]
        print(zip(columns, widths).map { pad($0, $1, left: $0 == "Process Name") }.joined(separator: " ") + "  User")
        for row in rows.prefix(20) {
            let memory = ByteCountFormatter.string(fromByteCount: Int64(row.memory), countStyle: .memory)
            let cells = [
                pad(String(row.name.prefix(36)), 36, left: true),
                pad(value(row.isAvailable, String(format: "%.1f", row.cpu)), 7),
                pad(value(row.hasGPU, String(format: "%.1f", row.gpu)), 7),
                pad(value(row.isAvailable, memory), 10),
                pad(value(row.isAvailable, String(format: "%.1f", row.energy)), 8),
                pad(String(row.id), 7)
            ]
            print(cells.joined(separator: " ") + "  " + row.user)
        }
        print("\n\(rows.count) processes, \(available) inspectable, \(result.icons.count) with app icons")
    }

    /// Headless diagnostic: quits the given pids one by one, exactly like the UI does.
    /// Usage: ProcessMonitor --quit <pid> [<pid> ...]   (or --force-quit)
    private static func quitFromCommandLine(pids: [pid_t], force: Bool) {
        let targets = pids.map { ProcessTerminator.Target(pid: $0, name: "PID \($0)") }
        let start = Date()
        let done = DispatchSemaphore(value: 0)
        Task.detached {
            await ProcessTerminator.quit(
                targets,
                force: force,
                willQuit: { index, target in
                    print(String(
                        format: "%6.2fs  signalling %@ (%d of %d)",
                        Date().timeIntervalSince(start),
                        target.name,
                        index + 1,
                        targets.count
                    ))
                },
                didQuit: { target, outcome in
                    print(String(format: "%6.2fs  %@: %@", Date().timeIntervalSince(start), target.name, "\(outcome)"))
                }
            )
            done.signal()
        }
        while done.wait(timeout: .now() + 0.01) == .timedOut {
            RunLoop.main.run(until: Date().addingTimeInterval(0.01))
        }
    }
}
