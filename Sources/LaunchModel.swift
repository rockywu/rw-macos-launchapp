import AppKit
import SwiftUI

@MainActor final class LaunchModel: ObservableObject {
    @Published var query = "" { didSet { if oldValue != query { resetPage() } } }
    @Published private(set) var page = 0
    @Published private(set) var folderID: String?
    @Published private(set) var layout = LaunchLayout()
    @Published var editingName = false
    @Published var needsGesturePermission = false
    @Published var isExpanded = false
    @Published private(set) var swipeOffset: CGFloat = 0
    var close: () -> Void = {}
    var openApp: (URL) -> Void = { _ in }
    private var apps: [InstalledApp] = []
    private var indexed: [String: InstalledApp] = [:]
    private var available: Set<String> = []
    private let prefs: UserDefaults
    private let layoutKey = "applicationGrid.v1"
    private var previousPage = 0
    static let rootCapacity = 35
    nonisolated static let folderColumns = 4
    static let folderCapacity = folderColumns * folderColumns
    var capacity: Int { folderID == nil ? Self.rootCapacity : Self.folderCapacity }
    var rootPage: Int { folderID == nil ? page : previousPage }

    init() {
        if let testSuite = ProcessInfo.processInfo.environment["RWLAUNCH_LAYOUT_TEST_SUITE"],
           testSuite.hasPrefix("local.pinchlaunch.layout-test."), let suite = UserDefaults(suiteName: testSuite) {
            prefs = suite
        } else { prefs = .standard }
    }

    var folderName: String { folderID.flatMap { layout.folders[$0]?.name } ?? "" }
    var searching: Bool { !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    var visibleItems: [GridItemValue] {
        if let folderID { return (layout.folders[folderID]?.apps ?? []).compactMap { indexed[$0] }.map(GridItemValue.app) }
        return rootItems
    }
    var rootItems: [GridItemValue] {
        if searching {
            let term = query.trimmingCharacters(in: .whitespacesAndNewlines)
            return apps.filter { app in
                [app.name, app.originalName, app.bundleID].contains { $0.localizedStandardContains(term) }
            }.map(GridItemValue.app)
        }
        return rootItems(in: layout)
    }
    private func rootItems(in layout: LaunchLayout) -> [GridItemValue] {
        layout.root.compactMap {
            switch $0 {
            case .app(let id): return indexed[id].map(GridItemValue.app)
            case .folder(let id):
                guard let group = layout.folders[id] else { return nil }
                let members = group.apps.compactMap { indexed[$0] }
                return members.isEmpty ? nil : .folder(id, group.name, members)
            }
        }
    }
    var pageCount: Int { max(1, (visibleItems.count + capacity - 1) / capacity) }
    var currentItems: [GridItemValue] { Array(visibleItems.dropFirst(page * capacity).prefix(capacity)) }
    func load(_ installed: [InstalledApp], defaultItems: [GridItemValue]) {
        apps = installed
        indexed = Dictionary(uniqueKeysWithValues: apps.map { ($0.bundleID, $0) })
        available = Set(indexed.keys)
        let decoded = prefs.data(forKey: layoutKey).flatMap { try? JSONDecoder().decode(LaunchLayout.self, from: $0) }
        var new = decoded ?? LaunchLayout()
        var baseline = LaunchLayout()
        baseline.root = defaultItems.map(\.entry)
        for case .folder(let id, let name, let children) in defaultItems {
            baseline.folders[id] = LaunchFolder(name: name, apps: children.map(\.bundleID))
        }
        new.include(baseline)
        if new.dissolveSmallFolders(available: available) { save(new) }
        else { layout = new }
        query = ""; folderID = nil; editingName = false; resetPage()
    }
    func move(_ by: Int) { go(page + by) }
    func go(_ new: Int) {
        let next = min(max(0, new), pageCount - 1)
        guard page != next else { return }
        withAnimation(.easeInOut(duration: 0.25)) { page = next; swipeOffset = 0 }
    }
    func trackSwipe(_ distance: CGFloat) {
        let atEdge = (distance > 0 && page == 0) || (distance < 0 && page == pageCount - 1)
        swipeOffset = atEdge ? distance * 0.17 : distance
    }
    func finishSwipe(by move: Int) {
        if move != 0 && (0..<pageCount).contains(page + move) { self.move(move) }
        else { withAnimation(.easeOut(duration: 0.19)) { swipeOffset = 0 } }
    }
    func resetPage(_ new: Int = 0) {
        swipeOffset = 0
        page = min(max(0, new), pageCount - 1)
    }
    func clearFolder() { editingName = false; folderID = nil; resetPage(previousPage) }
    private func openFolder(_ id: String) {
        previousPage = page
        folderID = id
        resetPage()
    }
    private func save(_ new: LaunchLayout) {
        guard new != layout, let data = try? JSONEncoder().encode(new) else { return }
        prefs.set(data, forKey: layoutKey)
        layout = new
    }
    @discardableResult
    func place(_ source: Entry, onto target: Entry?, placement: DropPlacement) -> Entry? {
        var updated = layout
        let suggestedName: String?
        if placement == .center, folderID == nil, case .app(let first) = target {
            suggestedName = indexed[first]?.suggestedFolderName
        } else { suggestedName = nil }
        let created = updated.drop(source, onto: target, placement: placement, in: folderID,
                                   newFolderName: suggestedName)
        let changed = updated != layout
        save(updated)
        resetPage(page)
        guard changed, placement == .center, folderID == nil else { return nil }
        return created.map(Entry.folder) ?? target
    }
    func shift(_ entry: Entry, by offset: Int) {
        let entries = visibleItems.map(\.entry)
        guard let origin = entries.firstIndex(of: entry), entries.indices.contains(origin + offset) else { return }
        place(entry, onto: entries[origin+offset], placement: offset < 0 ? .before : .after)
    }
    func removeFromFolder(_ entry: Entry) {
        guard case .app(let id) = entry, let folderID else { return }
        var updated = layout
        updated.moveOut(id, from: folderID, available: available)
        save(updated)
        if visibleItems.isEmpty { clearFolder() }
        else { resetPage(page) }
    }
    func extract(_ entry: Entry, from folder: String, onto target: Entry?, placement: DropPlacement?) {
        guard folderID == nil else { return }
        save(extractionLayout(entry, from: folder, onto: target, placement: placement))
        resetPage(page)
    }
    func previewExtraction(_ entry: Entry, from folder: String, onto target: Entry?,
                           placement: DropPlacement?) -> [GridItemValue] {
        rootItems(in: extractionLayout(entry, from: folder, onto: target, placement: placement))
    }
    private func extractionLayout(_ entry: Entry, from folder: String, onto target: Entry?,
                                  placement: DropPlacement?) -> LaunchLayout {
        var updated = layout
        if case .app(let app) = entry {
            updated.moveOut(app, from: folder, onto: target, placement: placement, available: available)
        }
        return updated
    }
    func rename(_ name: String) {
        guard let folderID else { return }
        var updated = layout
        updated.rename(folderID, to: name)
        save(updated)
        editingName = false
    }
    func edit(_ id: String) { openFolder(id); editingName = true }
    func choose(_ item: GridItemValue) {
        switch item {
        case .folder(let id, _, _): openFolder(id)
        case .app(let app): openApp(app.url)
        }
    }
}
