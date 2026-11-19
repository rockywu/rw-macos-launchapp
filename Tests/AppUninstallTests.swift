import Foundation

@main struct AppUninstallTests {
    static func main() throws {
        let fm = FileManager.default
        let scratch = fm.temporaryDirectory.resolvingSymlinksInPath().appendingPathComponent(UUID().uuidString)
        let root = scratch.appendingPathComponent("Applications")
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: scratch) }
        let name = "RWLaunch-Fixture-" + UUID().uuidString
        let bundleID = "local.rwlaunch.fixture." + UUID().uuidString.lowercased()
        let app = root.appendingPathComponent(name + ".app")
        func makeApp(_ url: URL) throws {
            let contents = url.appendingPathComponent("Contents")
            try fm.createDirectory(at: contents, withIntermediateDirectories: true)
            let plist = try PropertyListSerialization.data(fromPropertyList: [
                "CFBundleIdentifier": bundleID, "CFBundlePackageType": "APPL", "CFBundleName": name
            ], format: .xml, options: 0)
            try plist.write(to: contents.appendingPathComponent("Info.plist"))
        }
        try makeApp(app)
        func target(_ url: URL) -> AppUninstall? { AppUninstall(url, bundleID: bundleID, roots: [root]) }
        precondition(!AppUninstall.offered(for: URL(fileURLWithPath: "/System/Applications/News.app")))
        precondition(target(root.appendingPathComponent("Other.app/Contents/Helper.app")) == nil)
        precondition(AppUninstall(app, bundleID: "wrong.id", roots: [root]) == nil)
        let link = root.appendingPathComponent("Alias.app")
        try fm.createSymbolicLink(at: link, withDestinationURL: app)
        precondition(target(link) == nil)
        let original = try require(target(app))
        try fm.moveItem(at: app, to: scratch.appendingPathComponent("Original.app"))
        try makeApp(app)
        do {
            try original.moveToTrash(roots: [root])
            fatalError("Replaced application was removed")
        } catch AppUninstall.Failure.changed {}
        precondition(fm.fileExists(atPath: app.path))
        let prepared = try require(target(app))
        let destination = try require(try prepared.moveToTrash(roots: [root]) as URL?)
        precondition(!fm.fileExists(atPath: app.path) && fm.fileExists(atPath: destination.path))
        // Only move our unique fixture back, proving recoverability without emptying Trash.
        try fm.moveItem(at: destination, to: app)
        precondition(target(app) == prepared)
        print("System path, alias, bundle identity, replacement, move to Trash and recovery passed.")
    }

    static func require<T>(_ value: T?) throws -> T {
        guard let value else { throw CocoaError(.fileReadUnknown) }
        return value
    }
}
