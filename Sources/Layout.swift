import Foundation

enum Entry: Codable, Equatable, Hashable {
    case app(String)
    case folder(String)
}

struct LaunchFolder: Codable, Equatable {
    var name: String
    var apps: [String]
}

enum DropPlacement {
    case before, after, center

    func reordering<T: Equatable>(_ items: [T], moving source: T, onto target: T?) -> [T] {
        guard target != source, let origin = items.firstIndex(of: source),
              target.map(items.contains) ?? true else { return items }
        var reordered = items
        reordered.remove(at: origin)
        if let target, let index = reordered.firstIndex(of: target) {
            reordered.insert(source, at: index + (self == .before ? 0 : 1))
        } else {
            reordered.append(source)
        }
        return reordered
    }
}

struct LaunchLayout: Codable, Equatable {
    var root: [Entry] = []
    var folders: [String: LaunchFolder] = [:]

    mutating func include(_ defaults: LaunchLayout) {
        var assigned = Set(root.compactMap { if case .app(let id) = $0 { return id }; return nil })
        for group in folders.values { assigned.formUnion(group.apps) }
        for entry in defaults.root {
            switch entry {
            case .app(let id):
                if assigned.insert(id).inserted { root.append(entry) }
            case .folder(let id):
                guard let group = defaults.folders[id] else { continue }
                let fresh = group.apps.filter { assigned.insert($0).inserted }
                guard !fresh.isEmpty else { continue }
                if folders[id] == nil {
                    folders[id] = LaunchFolder(name: group.name, apps: [])
                    root.append(entry)
                }
                folders[id]?.apps.append(contentsOf: fresh)
            }
        }
    }

    mutating func rename(_ id: String, to text: String) {
        guard let name = Self.validFolderName(text) else { return }
        folders[id]?.name = name
    }

    private static func validFolderName(_ text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : String(trimmed.prefix(64))
    }

    @discardableResult
    mutating func drop(_ source: Entry, onto target: Entry?, placement: DropPlacement, in folder: String?,
                       newFolderName: String? = nil) -> String? {
        guard target != source else { return nil }
        if let folder {
            guard case .app(let id) = source, var group = folders[folder] else { return nil }
            var destination: String?
            if let target {
                guard case .app(let dest) = target else { return nil }
                destination = dest
            }
            group.apps = placement.reordering(group.apps, moving: id, onto: destination)
            folders[folder] = group
            return nil
        }
        guard let origin = root.firstIndex(of: source), target.map(root.contains) ?? true else { return nil }
        if placement == .center, case .app(let id) = source, let target {
            switch target {
            case .app(let dest):
                let key = UUID().uuidString
                root.remove(at: origin)
                if let i = root.firstIndex(of: target) { root[i] = .folder(key) }
                let name = newFolderName.flatMap(Self.validFolderName) ?? "New Folder"
                folders[key] = LaunchFolder(name: name, apps: [dest, id])
                return key
            case .folder(let key):
                guard folders[key] != nil else { return nil }
                root.remove(at: origin)
                folders[key]?.apps.append(id)
                return nil
            }
        }
        root = placement.reordering(root, moving: source, onto: target)
        return nil
    }

    private func shouldDissolve(_ group: LaunchFolder, available: Set<String>?) -> Bool {
        group.apps.count <= 1 || available.map { ids in group.apps.filter(ids.contains).count == 1 } == true
    }

    mutating func dissolveSmallFolders(available: Set<String>) -> Bool {
        var dissolved = false
        root = root.flatMap { entry -> [Entry] in
            guard case .folder(let id) = entry, let group = folders[id],
                  shouldDissolve(group, available: available) else { return [entry] }
            folders.removeValue(forKey: id)
            dissolved = true
            // Keep unavailable apps in the layout so they can reappear when reinstalled.
            return group.apps.map(Entry.app)
        }
        return dissolved
    }

    mutating func moveOut(_ app: String, from folder: String, onto target: Entry? = nil,
                          placement: DropPlacement? = nil, available: Set<String>? = nil) {
        let source = Entry.app(app)
        guard !root.contains(source), target != source else { return }
        guard var group = folders[folder], let pos = group.apps.firstIndex(of: app),
              let slot = root.firstIndex(of: .folder(folder)) else { return }
        group.apps.remove(at: pos)
        var updatedRoot = root
        let dissolve = shouldDissolve(group, available: available)
        let promoted = dissolve ? group.apps.map(Entry.app) : []
        if dissolve {
            updatedRoot.replaceSubrange(slot...slot, with: promoted + [source])
        } else {
            updatedRoot.insert(source, at: slot + 1)
        }
        let anchor = dissolve && target == .folder(folder) ?
            (promoted.first(where: { entry in
                if case .app(let id) = entry { return available?.contains(id) ?? true }
                return false
            }) ?? source) : target
        guard anchor.map(updatedRoot.contains) ?? true else { return }
        if let placement {
            updatedRoot = placement.reordering(updatedRoot, moving: source, onto: anchor)
        }
        root = updatedRoot
        folders[folder] = dissolve ? nil : group
    }
}
