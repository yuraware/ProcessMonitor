import AppKit
import CProcessInfo
import Foundation

/// Samples the process table and turns it into `ProcessEntry` rows.
///
/// Not thread-safe: call it from a single serial queue. Consecutive calls are
/// needed for CPU% and energy, which are rates computed from the previous sample.
final class ProcessSampler: @unchecked Sendable {
    struct Result {
        var entries: [ProcessEntry]
        var icons: [pid_t: NSImage]
    }

    private struct Snapshot {
        var cpuTimeNs: UInt64
        var wakeups: UInt64
        var timestampNs: UInt64
    }

    private struct Identity: Hashable {
        var pid: pid_t
        var startSec: Int64
    }

    private struct NameInfo {
        var name: String
        var path: String
        var isApp: Bool
    }

    /// Weight applied to idle wake-ups per second when estimating energy impact.
    /// Roughly follows the weighting Activity Monitor uses (CPU dominates, wake-ups add a penalty).
    private let wakeupWeight = 0.5

    private var previous: [Identity: Snapshot] = [:]
    private var names: [Identity: NameInfo] = [:]
    private var icons: [Identity: NSImage] = [:]
    private var users: [uid_t: String] = [:]

    /// Forget the previous sample so the next call starts a fresh baseline.
    func reset() {
        previous.removeAll()
    }

    func sample() -> Result {
        var listPointer: UnsafeMutablePointer<pm_proc_basic>?
        let count = pm_list_processes(&listPointer)
        guard count >= 0, let list = listPointer else {
            return Result(entries: [], icons: [:])
        }
        defer { free(list) }

        let now = DispatchTime.now().uptimeNanoseconds
        var entries: [ProcessEntry] = []
        entries.reserveCapacity(Int(count))
        var seen = Set<Identity>()
        var iconsByPid: [pid_t: NSImage] = [:]

        for index in 0..<Int(count) {
            let basic = list[index]
            let identity = Identity(pid: basic.pid, startSec: basic.start_sec)
            seen.insert(identity)

            let comm = withUnsafePointer(to: basic.comm) { pointer in
                pointer.withMemoryRebound(to: CChar.self, capacity: 32) { String(cString: $0) }
            }
            let nameInfo = resolveName(identity: identity, fallback: comm)
            if let icon = resolveIcon(identity: identity, isApp: nameInfo.isApp) {
                iconsByPid[basic.pid] = icon
            }

            var usage = rusage_info_v4()
            let available = pm_pid_rusage_v4(basic.pid, &usage) == 0

            var cpu = 0.0
            var energy = 0.0
            var memory: UInt64 = 0

            if available {
                let cpuTimeNs = pm_mach_to_ns(usage.ri_user_time &+ usage.ri_system_time)
                let wakeups = usage.ri_pkg_idle_wkups &+ usage.ri_interrupt_wkups
                memory = usage.ri_phys_footprint

                if let prior = previous[identity], now > prior.timestampNs, cpuTimeNs >= prior.cpuTimeNs {
                    let elapsedNs = Double(now - prior.timestampNs)
                    cpu = Double(cpuTimeNs - prior.cpuTimeNs) / elapsedNs * 100
                    let wakeupsPerSecond = Double(wakeups &- prior.wakeups) / (elapsedNs / 1_000_000_000)
                    energy = cpu + wakeupWeight * max(0, wakeupsPerSecond)
                }
                previous[identity] = Snapshot(cpuTimeNs: cpuTimeNs, wakeups: wakeups, timestampNs: now)
            }

            entries.append(ProcessEntry(
                id: basic.pid,
                parentID: basic.ppid,
                name: nameInfo.name,
                path: nameInfo.path,
                user: userName(for: basic.uid),
                cpu: cpu,
                gpu: -1,
                memory: memory,
                energy: energy,
                isAvailable: available,
                isApp: nameInfo.isApp
            ))
        }

        // Drop state for processes that have exited (or whose pid was reused).
        previous = previous.filter { seen.contains($0.key) }
        names = names.filter { seen.contains($0.key) }
        icons = icons.filter { seen.contains($0.key) }

        return Result(entries: entries, icons: iconsByPid)
    }

    // MARK: - Helpers

    private func resolveName(identity: Identity, fallback: String) -> NameInfo {
        if let cached = names[identity] {
            return cached
        }

        var path = ""
        var name = fallback
        var isApp = false

        var buffer = [CChar](repeating: 0, count: 4 * Int(MAXPATHLEN))
        if pm_pid_path(identity.pid, &buffer, UInt32(buffer.count)) > 0 {
            path = String(cString: buffer)
            let last = (path as NSString).lastPathComponent
            if !last.isEmpty {
                name = last
            }
        } else {
            var nameBuffer = [CChar](repeating: 0, count: 256)
            if pm_pid_name(identity.pid, &nameBuffer, UInt32(nameBuffer.count)) > 0 {
                let kernelName = String(cString: nameBuffer)
                if !kernelName.isEmpty {
                    name = kernelName
                }
            }
        }

        if let app = NSRunningApplication(processIdentifier: identity.pid) {
            isApp = true
            if let localized = app.localizedName, !localized.isEmpty {
                name = localized
            }
            if path.isEmpty, let url = app.executableURL {
                path = url.path
            }
        }

        let info = NameInfo(name: name, path: path, isApp: isApp)
        names[identity] = info
        return info
    }

    private func resolveIcon(identity: Identity, isApp: Bool) -> NSImage? {
        guard isApp else { return nil }
        if let cached = icons[identity] {
            return cached
        }
        guard let icon = NSRunningApplication(processIdentifier: identity.pid)?.icon else {
            return nil
        }
        icon.size = NSSize(width: 16, height: 16)
        icons[identity] = icon
        return icon
    }

    private func userName(for uid: uid_t) -> String {
        if let cached = users[uid] {
            return cached
        }
        let name = if let entry = getpwuid(uid), let cName = entry.pointee.pw_name {
            String(cString: cName)
        } else {
            String(uid)
        }
        users[uid] = name
        return name
    }
}
