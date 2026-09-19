@testable import ProcessMonitor
import XCTest

// MARK: - ProcessTreeTests

final class ProcessTreeTests: XCTestCase {
    private func entry(
        _ pid: pid_t,
        parent: pid_t,
        name: String,
        cpu: Double = 0,
        memory: UInt64 = 0,
        energy: Double = 0,
        available: Bool = true
    ) -> ProcessEntry {
        ProcessEntry(
            id: pid,
            parentID: parent,
            name: name,
            path: "",
            user: "me",
            cpu: cpu,
            gpu: -1,
            memory: memory,
            energy: energy,
            isAvailable: available,
            isApp: false
        )
    }

    /// kernel_task(0) ─ launchd(1) ─ Chrome(10) ─ Helper(11) ─ Sub-helper(12)
    ///                            └ Terminal(20) ─ zsh(21)
    ///                            └ orphan(30, parent missing)
    private lazy var sample: [ProcessEntry] = [
        entry(0, parent: 0, name: "kernel_task", cpu: 5, energy: 5, available: false),
        entry(1, parent: 0, name: "launchd", cpu: 1, energy: 1, available: false),
        entry(10, parent: 1, name: "Chrome", cpu: 10, memory: 100, energy: 10),
        entry(11, parent: 10, name: "Helper", cpu: 20, memory: 200, energy: 20),
        entry(12, parent: 11, name: "Sub-helper", cpu: 30, memory: 300, energy: 30),
        entry(20, parent: 1, name: "Terminal", cpu: 2, memory: 50, energy: 2),
        entry(21, parent: 20, name: "zsh", cpu: 1, memory: 5, energy: 1),
        entry(30, parent: 999, name: "orphan", memory: 1)
    ]

    private let byCPU = [KeyPathComparator(\ProcessRow.cpu, order: .reverse)]

    func testRootsAreKernelLaunchdDirectChildrenOfLaunchdAndOrphans() {
        let tree = ProcessTree(entries: sample)
        XCTAssertEqual(Set(tree.roots.map(\.id)), [0, 1, 10, 20, 30])
    }

    func testDescendantsIncludeEveryDepth() {
        let tree = ProcessTree(entries: sample)
        XCTAssertEqual(Set(tree.descendants(of: 10).map(\.id)), [11, 12])
        XCTAssertEqual(tree.descendants(of: 12).map(\.id), [])
        XCTAssertEqual(tree.descendants(of: 1).map(\.id), [], "children of launchd are roots, not members")
    }

    func testCollapsedGroupRowShowsTotalsAndSortsByThem() {
        let rows = ProcessTree(entries: sample).rows(expanded: [], sortOrder: byCPU)
        XCTAssertEqual(rows.map(\.id), [10, 0, 20, 1, 30], "Chrome's 60% total outranks kernel_task's 5%")

        let chrome = rows[0]
        XCTAssertTrue(chrome.isGroup)
        XCTAssertFalse(chrome.isExpanded)
        XCTAssertEqual(chrome.memberCount, 2)
        XCTAssertEqual(chrome.depth, 0)
        XCTAssertEqual(chrome.cpu, 60)
        XCTAssertEqual(chrome.memory, 600)
        XCTAssertEqual(chrome.energy, 60)

        let terminal = rows[2]
        XCTAssertEqual(terminal.cpu, 3)
        XCTAssertEqual(terminal.memberCount, 1)

        XCTAssertFalse(rows[4].isGroup)
        XCTAssertEqual(rows[4].memberCount, 0)
    }

    func testExpandedGroupRowShowsOwnValuesWithMembersIndentedBelow() {
        let rows = ProcessTree(entries: sample).rows(expanded: [10], sortOrder: byCPU)
        XCTAssertEqual(
            rows.map(\.id),
            [10, 12, 11, 0, 20, 1, 30],
            "expanded group keeps its position, members sorted inside"
        )

        let chrome = rows[0]
        XCTAssertTrue(chrome.isExpanded)
        XCTAssertEqual(chrome.cpu, 60, "group position is by total even when expanded")
        XCTAssertEqual(chrome.memberCount, 2)
        XCTAssertEqual(rows[1].depth, 1)
        XCTAssertEqual(rows[2].depth, 1)
        XCTAssertEqual(rows[1].cpu, 30)
        XCTAssertFalse(rows[1].isGroup)
    }

    func testTotalsSkipUnavailableMembersButGroupIsAvailableIfAnyMemberIs() {
        let entries = [
            entry(1, parent: 0, name: "launchd", available: false),
            entry(10, parent: 1, name: "root", cpu: 0, memory: 0, available: false),
            entry(11, parent: 10, name: "child", cpu: 4, memory: 40)
        ]
        let rows = ProcessTree(entries: entries).rows(expanded: [], sortOrder: byCPU)
        let group = rows.first { $0.id == 10 }
        XCTAssertEqual(group?.isAvailable, true)
        XCTAssertEqual(group?.cpu, 4)
        XCTAssertEqual(group?.memory, 40)
    }

    func testFlatRowsKeepOwnValues() {
        let rows = ProcessRow.flat(sample, sortOrder: byCPU)
        XCTAssertEqual(rows.map(\.id), [12, 11, 10, 0, 20, 1, 21, 30])
        XCTAssertTrue(rows.allSatisfy { !$0.isGroup && $0.depth == 0 })
    }

    func testGroupRootsWithMembers() {
        let tree = ProcessTree(entries: sample)
        XCTAssertEqual(Set(tree.groupRoots), [10, 20])
        XCTAssertEqual(Set(tree.members(of: 10)), [10, 11, 12])
        XCTAssertEqual(tree.members(of: 30), [30])
    }
}

// MARK: - ProcessTreeLiveTests

final class ProcessTreeLiveTests: XCTestCase {
    /// Sanity check against the real process table: every process is either a root or a member
    /// of exactly one group, and the flat and grouped views agree on the totals.
    func testLiveProcessTablePartitionsCleanly() {
        let entries = ProcessSampler().sample().entries
        XCTAssertGreaterThan(entries.count, 10)
        let tree = ProcessTree(entries: entries)

        var seen: [pid_t] = []
        for root in tree.roots {
            seen.append(contentsOf: tree.members(of: root.id))
        }
        XCTAssertEqual(seen.count, Set(seen).count, "no process belongs to two groups")
        XCTAssertEqual(Set(seen), Set(entries.map(\.id)), "every process is reachable")

        let rows = tree.rows(expanded: [], sortOrder: [KeyPathComparator(\.memory, order: .reverse)])
        XCTAssertEqual(rows.count, tree.roots.count)
        XCTAssertEqual(rows.reduce(0) { $0 + $1.memory }, entries.filter(\.isAvailable).reduce(0) { $0 + $1.memory })
        XCTAssertFalse(tree.groupRoots.isEmpty, "at least one app with helpers is expected on a live system")
    }
}
