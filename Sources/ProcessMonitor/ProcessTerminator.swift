import Darwin
import Foundation

/// Quits processes strictly one after another: each target is signalled and the
/// next one is only touched once the previous one has exited (or timed out).
enum ProcessTerminator {
    struct Target {
        var pid: pid_t
        var name: String
    }

    enum Outcome {
        case exited
        case timedOut
        case failed(String)
    }

    /// - Parameters:
    ///   - force: send SIGKILL instead of SIGTERM.
    ///   - willQuit: called before each target is signalled (index, target).
    ///   - didQuit: called after each target finished (target, outcome).
    static func quit(
        _ targets: [Target],
        force: Bool,
        willQuit: @MainActor (Int, Target) -> Void = { _, _ in },
        didQuit: @MainActor (Target, Outcome) -> Void = { _, _ in }
    ) async {
        let ownPid = getpid()
        // Never kill ourselves before the others are done.
        let ordered = targets.filter { $0.pid != ownPid } + targets.filter { $0.pid == ownPid }

        for (index, target) in ordered.enumerated() {
            await willQuit(index, target)
            let outcome: Outcome = if kill(target.pid, force ? SIGKILL : SIGTERM) != 0 {
                .failed(String(cString: strerror(errno)))
            } else if await waitForExit(of: target.pid, timeout: force ? 2 : 5) {
                .exited
            } else {
                .timedOut
            }
            await didQuit(target, outcome)
        }
    }

    /// Polls until `pid` no longer exists. Returns `false` if it is still alive after `timeout` seconds.
    static func waitForExit(of pid: pid_t, timeout: TimeInterval) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        repeat {
            if !isAlive(pid) {
                return true
            }
            try? await Task.sleep(nanoseconds: 50_000_000)
        } while Date() < deadline
        return !isAlive(pid)
    }

    /// A pid counts as gone when it no longer exists or is a zombie waiting to be reaped.
    static func isAlive(_ pid: pid_t) -> Bool {
        var info = proc_bsdinfo()
        let size = Int32(MemoryLayout<proc_bsdinfo>.size)
        guard proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, size) == size else {
            return kill(pid, 0) == 0 || errno == EPERM
        }
        return info.pbi_status != UInt32(SZOMB)
    }
}
