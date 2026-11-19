import Foundation

@main struct LayoutTests {
    static func main() throws {
        let a: Entry = .app("a"), b: Entry = .app("b"), c: Entry = .app("c")
        let system: Entry = .folder("system")
        let baseline = LaunchLayout(root: [a,b,c,system],
            folders: ["system": LaunchFolder(name: "实用工具", apps: ["u", "v"])])
        var layout = LaunchLayout()
        layout.include(baseline)
        assert(layout == baseline)
        // The preview clears the destination slot for the lifted app and fills its old slot.
        var paged = LaunchLayout(root: (0..<40).map { .app("app\($0)") })
        let source = paged.root[38], anchor = paged.root[33]
        let preview = DropPlacement.before.reordering(paged.root, moving: source, onto: anchor)
        assert(preview[33] == source && preview[34] == anchor && preview[35] == .app("app34"))
        paged.drop(source, onto: anchor, placement: .before, in: nil)
        assert(paged.root == preview)

        layout.drop(c, onto: a, placement: .before, in: nil)
        assert(layout.root == [c,a,b,system])
        guard let folder = layout.drop(a, onto: b, placement: .center, in: nil,
                                       newFolderName: "  音乐  ") else { fatalError("Folder not made") }
        assert(layout.root == [c,.folder(folder),system])
        assert(layout.folders[folder]?.name == "音乐")
        assert(layout.folders[folder]?.apps == ["b","a"])
        layout.rename(folder, to: "  办公  ")
        layout.rename("system", to: " 内置工具 ")
        layout.rename(folder, to: "  ")
        assert(layout.folders[folder]?.name == "办公")
        assert(layout.folders["system"]?.name == "内置工具")
        layout.drop(a, onto: b, placement: .before, in: folder)
        layout.drop(c, onto: .folder(folder), placement: .center, in: nil, newFolderName: "游戏")
        assert(layout.folders[folder]?.apps == ["a","b","c"])
        assert(layout.folders[folder]?.name == "办公")
        layout.moveOut("b", from: folder)
        assert(layout.root == [.folder(folder),b,system])
        assert(layout.folders[folder]?.apps == ["a","c"])
        layout.moveOut("a", from: folder)
        assert(layout.folders[folder] == nil)
        let restored = try JSONDecoder().decode(LaunchLayout.self, from: JSONEncoder().encode(layout))
        assert(restored == layout)
        var withNew = baseline
        withNew.root.append(.app("d"))
        withNew.folders["system"]?.apps.append("w")
        layout.include(withNew)
        assert(layout.root == [c,a,b,system,.app("d")])
        assert(layout.folders["system"] == LaunchFolder(name: "内置工具", apps: ["u","v","w"]))
        var extracted = baseline
        extracted.moveOut("v", from: "system", onto: b, placement: .before)
        assert(extracted.root == [a, .app("v"), b, c, .app("u")])
        assert(extracted.folders["system"] == nil)
        var anchored = baseline
        anchored.moveOut("v", from: "system", onto: .app("missing"), placement: .before)
        assert(anchored == baseline)
        anchored.moveOut("v", from: "system", onto: system, placement: .before)
        assert(anchored.root == [a,b,c,.app("v"),.app("u")])
        var old = LaunchLayout(root: [a, system, b], folders: [
            "system": LaunchFolder(name: "旧文件夹", apps: ["missing", "u"])
        ])
        assert(old.dissolveSmallFolders(available: ["a", "b", "u"]))
        assert(old.root == [a,.app("missing"),.app("u"),b] && old.folders.isEmpty)
        assert(!old.dissolveSmallFolders(available: ["a", "b", "u"]))
        print("Layout reorder, folder operations, targeted extraction, persistence and new-app merge: passed")
        testPageSwipes()
    }

    static func testPageSwipes() {
        var swipe = PageSwipe()
        // Early diagonal movement counts towards the same swipe once it becomes horizontal.
        assert(swipe.track(dx: -3, dy: 3, at: 1) == nil)
        assert(swipe.track(dx: -8, dy: 1, at: 1.12) == -11)
        assert(swipe.track(dx: -12, dy: 2, at: 1.24) == -23)
        assert(swipe.finish(at: 1.3) == 1)

        // A short, deliberate flick moves one page in the opposite direction.
        _ = swipe.track(dx: 3, dy: 0, at: 2)
        _ = swipe.track(dx: 4, dy: 1, at: 2.01)
        _ = swipe.track(dx: 4, dy: 1, at: 2.02)
        assert(swipe.finish(at: 2.04) == -1)
        assert(swipe.finish(at: 2.05) == 0)

        _ = swipe.track(dx: 3, dy: 0, at: 3)
        _ = swipe.track(dx: 8, dy: 2, at: 3.01)
        assert(swipe.finish(at: 3.2) == 0) // A paused flick snaps back.
        _ = swipe.track(dx: 1, dy: 12, at: 4)
        assert(swipe.track(dx: 27, dy: 1, at: 4.02) == nil)
        assert(swipe.finish(at: 4.03) == 0)
        _ = swipe.track(dx: -3, dy: 1, at: 5)
        assert(swipe.finish(at: 5.01) == 0)
        _ = swipe.track(dx: -28, dy: 1, at: 6)
        assert(swipe.finish(at: 6.01, cancelled: true) == 0)
        print("Short swipes, flicks, jitter, vertical motion, cancellation and reset: passed")
    }
}
