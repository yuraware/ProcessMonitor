import Foundation

// MARK: - ProcessRow

/// One row as displayed in the table: a process plus its place in the parent/child grouping.
///
/// The numeric columns are copied from the entry so the table can sort on them; for a
/// collapsed group they hold the totals of the whole group instead of the root's own usage.
struct ProcessRow: Identifiable, Hashable {
    let id: pid_t
    var entry: ProcessEntry
    /// `0` for a top-level row, `1` for a member listed under its group.
    var depth: Int
    /// Number of descendants when this row is the root of a group; `0` for a plain row.
    var memberCount: Int
    var isExpanded: Bool
    var cpu: Double
    var memory: UInt64
    var energy: Double
    var isAvailable: Bool

    var name: String {
        entry.name
    }

    var path: String {
        entry.path
    }

    var user: String {
        entry.user
    }

    var gpu: Double {
        entry.gpu
    }

    var hasGPU: Bool {
        entry.hasGPU
    }

    var isGroup: Bool {
        memberCount > 0
    }

    init(entry: ProcessEntry, depth: Int = 0, memberCount: Int = 0, isExpanded: Bool = false) {
        id = entry.id
        self.entry = entry
        self.depth = depth
        self.memberCount = memberCount
        self.isExpanded = isExpanded
        cpu = entry.cpu
        memory = entry.memory
        energy = entry.energy
        isAvailable = entry.isAvailable
    }

    /// Ungrouped rows, one per entry, sorted.
    static func flat(_ entries: [ProcessEntry], sortOrder: [KeyPathComparator<ProcessRow>]) -> [ProcessRow] {
        entries.map { ProcessRow(entry: $0) }.sorted(using: sortOrder)
    }
}

// MARK: - ProcessTree

/// Groups processes under their top-most ancestor.
///
/// A process is a root when its parent is the kernel or launchd (pids 0 and 1), or when its
/// parent is not in the table. Everything else is a member of the group of its nearest root,
/// whatever the depth. Treating launchd's children as roots keeps system daemons as separate
/// rows instead of one enormous launchd group.
struct ProcessTree {
    private(set) var roots: [ProcessEntry] = []
    private var children: [pid_t: [ProcessEntry]] = [:]
    private var descendantsByRoot: [pid_t: [ProcessEntry]] = [:]

    init(entries: [ProcessEntry]) {
        let byPid = Dictionary(entries.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        for entry in entries {
            let parent = entry.parentID
            if parent <= 1 || parent == entry.id || byPid[parent] == nil {
                roots.append(entry)
            } else {
                children[parent, default: []].append(entry)
            }
        }
        for root in roots {
            descendantsByRoot[root.id] = collectDescendants(of: root.id)
        }
    }

    /// Every process below `root`, at any depth. Empty for non-roots.
    func descendants(of root: pid_t) -> [ProcessEntry] {
        descendantsByRoot[root] ?? []
    }

    /// The root itself followed by its descendants. A plain process is its own only member.
    func members(of root: pid_t) -> [pid_t] {
        [root] + descendants(of: root).map(\.id)
    }

    /// Roots that actually have descendants, i.e. the ones that can be expanded.
    var groupRoots: [pid_t] {
        roots.filter { !descendants(of: $0.id).isEmpty }.map(\.id)
    }

    /// Builds the table rows: one row per root, sorted by the group's totals, with the
    /// members of expanded groups listed (sorted) underneath their root.
    func rows(expanded: Set<pid_t>, sortOrder: [KeyPathComparator<ProcessRow>]) -> [ProcessRow] {
        let groupRows = roots.map { root -> ProcessRow in
            let members = descendants(of: root.id)
            var row = ProcessRow(
                entry: root,
                memberCount: members.count,
                isExpanded: !members.isEmpty && expanded.contains(root.id)
            )
            for member in members where member.isAvailable {
                row.cpu += member.cpu
                row.memory += member.memory
                row.energy += member.energy
                row.isAvailable = true
            }
            return row
        }
        .sorted(using: sortOrder)

        var rows: [ProcessRow] = []
        rows.reserveCapacity(groupRows.count)
        for row in groupRows {
            rows.append(row)
            if row.isExpanded {
                let members = descendants(of: row.id).map { ProcessRow(entry: $0, depth: 1) }
                rows.append(contentsOf: members.sorted(using: sortOrder))
            }
        }
        return rows
    }

    private func collectDescendants(of root: pid_t) -> [ProcessEntry] {
        var result: [ProcessEntry] = []
        var visited: Set<pid_t> = [root]
        var stack = children[root] ?? []
        while let next = stack.popLast() {
            guard visited.insert(next.id).inserted else { continue }
            result.append(next)
            stack.append(contentsOf: children[next.id] ?? [])
        }
        return result
    }
}
