import AppKit
import Darwin

/// Captures the identity of the selected app before the confirmation sheet opens.
struct AppUninstall: Equatable {
    let url: URL
    let bundleID: String
    private let device: dev_t
    private let inode: ino_t

    static let roots = [URL(fileURLWithPath: "/Applications", isDirectory: true),
                        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Applications")]

    static func offered(for url: URL, roots: [URL] = roots) -> Bool {
        guard url.isFileURL, url.pathExtension.lowercased() == "app" else { return false }
        let path = url.standardizedFileURL.path
        return roots.contains { root in
            let prefix = root.standardizedFileURL.path + "/"
            guard path.hasPrefix(prefix) else { return false }
            return !path.dropFirst(prefix.count).split(separator: "/").dropLast().contains {
                $0.lowercased().hasSuffix(".app")
            }
        }
    }

    init?(_ selected: URL, bundleID: String, roots: [URL] = roots) {
        let url = selected.standardizedFileURL
        var info = stat()
        guard Self.offered(for: url, roots: roots), url.resolvingSymlinksInPath().path == url.path,
              lstat(url.path, &info) == 0, (info.st_mode & S_IFMT) == S_IFDIR,
              url.path != Bundle.main.bundleURL.standardizedFileURL.path,
              let values = try? url.resourceValues(forKeys: [.isApplicationKey, .isAliasFileKey]),
              values.isApplication == true, values.isAliasFile == false,
              let plist = try? Data(contentsOf: url.appendingPathComponent("Contents/Info.plist")),
              let meta = (try? PropertyListSerialization.propertyList(from: plist, format: nil)) as? [String: Any],
              (meta["CFBundleIdentifier"] as? String)?.lowercased() == bundleID.lowercased() else { return nil }
        self.url = url
        self.bundleID = bundleID
        device = info.st_dev
        inode = info.st_ino
    }

    enum Failure: Error { case changed, running }

    @discardableResult
    func moveToTrash(roots: [URL] = roots) throws -> NSURL? {
        guard AppUninstall(url, bundleID: bundleID, roots: roots) == self else { throw Failure.changed }
        guard !NSWorkspace.shared.runningApplications.contains(where: {
            $0.bundleURL?.resolvingSymlinksInPath().path == url.path
        }) else { throw Failure.running }
        var destination: NSURL?
        try FileManager.default.trashItem(at: url, resultingItemURL: &destination)
        return destination
    }
}
