import AppKit
import SwiftUI
import ServiceManagement

let toolName = "RWLaunch"

var gesturePermissionName: String {
    if #available(macOS 27.0, *) { return "设备控制和数据访问" }
    return "辅助功能"
}

struct InstalledApp: Identifiable {
    let url: URL
    let bundleID: String
    let name: String
    let originalName: String
    var categoryIdentifier: String? = nil
    var id: String { url.path }

    var suggestedFolderName: String {
        let prefix = "public.app-category."
        guard let identifier = categoryIdentifier?.lowercased(), identifier.hasPrefix(prefix) else { return name }
        let category = identifier.dropFirst(prefix.count)
        if category == "games" || category.hasSuffix("-games") { return "游戏" }
        switch category {
        case "music": return "音乐"
        case "photography": return "摄影"
        case "video": return "视频"
        case "graphics-design": return "设计"
        case "developer-tools": return "开发工具"
        case "utilities": return "实用工具"
        case "productivity", "business": return "办公"
        case "social-networking": return "社交"
        case "education": return "教育"
        case "news": return "新闻"
        case "finance": return "财务"
        case "reference": return "参考资料"
        case "entertainment": return "娱乐"
        default: return name
        }
    }
}

enum GridItemValue: Identifiable {
    case app(InstalledApp)
    case folder(String, String, [InstalledApp])
    var id: String {
        switch self {
        case .app(let app): return app.id
        case .folder(let id, _, _): return "folder:" + id
        }
    }
    var entry: Entry {
        switch self {
        case .app(let app): return .app(app.bundleID)
        case .folder(let id, _, _): return .folder(id)
        }
    }
    var name: String {
        switch self {
        case .app(let app): return app.name
        case .folder(_, let name, _): return name
        }
    }
}

@MainActor final class Catalog {
    static let shared = Catalog()
    private var icons: [String: NSImage] = [:]
    func icon(_ app: InstalledApp) -> NSImage {
        if let cached = icons[app.id] { return cached }
        let img = NSWorkspace.shared.icon(forFile: app.url.path)
        icons[app.id] = img
        return img
    }
    func load() -> (apps: [InstalledApp], items: [GridItemValue]) {
        let fm = FileManager.default
        let roots = ["/System/Applications", "/Applications",
                     fm.homeDirectoryForCurrentUser.appendingPathComponent("Applications").path]
        var known = Set<String>()
        var main: [InstalledApp] = [], others: [InstalledApp] = [], utilities: [InstalledApp] = [], games: [InstalledApp] = []
        let preferred = [
            "com.apple.AppStore", "com.apple.FaceTime", "com.apple.news", "com.apple.PhotoBooth",
            "com.apple.ScreenContinuity", "com.apple.MobileSMS", "com.apple.GenerativePlaygroundApp",
            "com.apple.iBooksX", "com.apple.Maps", "com.apple.Notes", "com.apple.Home",
            "com.apple.Passwords", "com.apple.journal", "com.apple.reminders", "com.apple.freeform",
            "com.apple.iCal", "com.apple.clock", "com.apple.findmy", "com.apple.Photos",
            "com.apple.mobilephone", "com.apple.TV", "com.apple.systempreferences",
            "com.apple.AddressBook", "com.apple.calculator", "com.apple.mail", "com.apple.Music"
        ].map { $0.lowercased() }
        let selfID = Bundle.main.bundleIdentifier?.lowercased()
        for root in roots {
            let rootURL = URL(fileURLWithPath: root, isDirectory: true)
            guard let files = fm.enumerator(at: rootURL, includingPropertiesForKeys: [.isDirectoryKey, .localizedNameKey, .isSymbolicLinkKey],
                                             options: [.skipsHiddenFiles, .skipsPackageDescendants]) else { continue }
            for case let url as URL in files {
                if url.pathExtension.lowercased() != "app" {
                    if url.pathComponents.count > rootURL.pathComponents.count + 2 { files.skipDescendants() }
                    continue
                }
                files.skipDescendants()
                guard let bundle = Bundle(url: url), let bundleID = bundle.bundleIdentifier?.lowercased(),
                      bundleID != selfID, bundleID != "com.apple.apps.launcher",
                      bundleID != "com.apple.launchpad", known.insert(bundleID).inserted else { continue }
                let name = (try? url.resourceValues(forKeys: [.localizedNameKey]).localizedName) ??
                    fm.displayName(atPath: url.path)
                let visible = name.lowercased().hasSuffix(".app") ? String(name.dropLast(4)) : name
                let original = url.deletingPathExtension().lastPathComponent
                let category = bundle.object(forInfoDictionaryKey: "LSApplicationCategoryType") as? String
                let app = InstalledApp(url: url, bundleID: bundleID, name: visible, originalName: original,
                                       categoryIdentifier: category)
                if url.path.contains("/Utilities/") { utilities.append(app) }
                else if category?.hasSuffix("games") == true || bundleID == "com.apple.chess" { games.append(app) }
                else if root == "/System/Applications" && preferred.contains(bundleID) { main.append(app) }
                else { others.append(app) }
            }
        }
        func byName(_ a: InstalledApp, _ b: InstalledApp) -> Bool { a.name.localizedStandardCompare(b.name) == .orderedAscending }
        main.sort { (preferred.firstIndex(of: $0.bundleID) ?? 999) < (preferred.firstIndex(of: $1.bundleID) ?? 999) }
        let systemOther = others.filter { $0.url.path.hasPrefix("/System/") }.sorted(by: byName)
        let thirdParty = others.filter { !$0.url.path.hasPrefix("/System/") }.sorted(by: byName)
        utilities.sort(by: byName)
        games.sort(by: byName)
        var items = main.map(GridItemValue.app)
        if !utilities.isEmpty { items.append(.folder("utilities", "实用工具", utilities)) }
        if !systemOther.isEmpty { items.append(.folder("system-other", "其他", systemOther)) }
        if !games.isEmpty { items.append(.folder("games", "游戏", games)) }
        items.append(contentsOf: thirdParty.map(GridItemValue.app))
        let apps = (main + utilities + systemOther + games + thirdParty).sorted(by: byName)
        icons = icons.filter { knownIcon in apps.contains { $0.id == knownIcon.key } }
        return (apps, items)
    }
}

struct BlurFallback: View {
    var body: some View {
        ZStack {
            Color(red: 0.018, green: 0.11, blue: 0.17)
            GeometryReader { g in
                let w = g.size.width
                let h = g.size.height
                ForEach(0..<9) { i in
                    let horizontal = [0.18, 0.41, 0.71, 0.86, 0.3, 0.56, 0.11, 0.64, 0.98]
                    let vertical = [0.13, 0.25, 0.15, 0.39, 0.51, 0.65, 0.81, 0.93, 0.88]
                    let tint: Color = i.isMultiple(of: 3) ? .cyan.opacity(0.50) :
                        Color(red: 0.27, green: 0.59, blue: 0.69).opacity(0.72)
                    Ellipse().fill(tint).frame(width: w * 0.23, height: h * 0.29)
                        .rotationEffect(.degrees(Double(i) * 19 + 25))
                        .position(x: w * horizontal[i], y: h * vertical[i])
                }
            }.blur(radius: 44)
            LinearGradient(colors: [.black.opacity(0.3), .clear, .black.opacity(0.36)], startPoint: .top, endPoint: .bottom)
        }
    }
}

final class LauncherHostingView: NSHostingView<LauncherView> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

final class LauncherWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
    var handleKey: (NSEvent) -> Bool = { _ in false }
    var handleScroll: (NSEvent) -> Void = { _ in }
    override func sendEvent(_ event: NSEvent) {
        if event.type == .keyDown, handleKey(event) { return }
        if event.type == .scrollWheel { handleScroll(event) }
        super.sendEvent(event)
    }
}

@MainActor final class Launcher: NSObject, NSApplicationDelegate {
    private var bar: NSStatusItem!
    private var window: LauncherWindow?
    private var isClosing = false
    private var model = LaunchModel()
    private var previousApp: NSRunningApplication?
    private var gestureOK = false
    private var systemGestureOK = false
    private var gestureTimer: Timer?
    private let disableSystemTap = CommandLine.arguments.contains("--no-system-gesture")
    private var lastPageAt: TimeInterval = 0
    private var pageSwipe = PageSwipe()
    private var optionsShown = false
    private lazy var menu: NSMenu = {
        let m = NSMenu()
        m.delegate = self
        m.addItem(withTitle: "打开启动台", action: #selector(show), keyEquivalent: "")
        m.addItem(.separator())
        m.addItem(withTitle: "四指或五指捏合", action: #selector(toggleGesture), keyEquivalent: "")
        m.addItem(withTitle: "开机时启动", action: #selector(toggleLogin), keyEquivalent: "")
        m.addItem(withTitle: "重新连接触控板", action: #selector(reconnect), keyEquivalent: "")
        m.addItem(withTitle: "系统捏合接管设置…", action: #selector(openAccessibility), keyEquivalent: "")
        m.addItem(withTitle: "显示菜单栏图标", action: #selector(toggleMenuBarIcon), keyEquivalent: "")
        m.addItem(.separator())
        m.addItem(withTitle: "退出 \(toolName)", action: #selector(quit), keyEquivalent: "q")
        m.items.forEach { $0.target = self }
        return m
    }()
    private var gestureEnabled: Bool { !UserDefaults.standard.bool(forKey: "gestureDisabled") }
    private let menuBarIconHiddenKey = "menuBarIconHidden"
    private var menuBarIconVisible: Bool { !UserDefaults.standard.bool(forKey: menuBarIconHiddenKey) }
    func applicationDidFinishLaunching(_ notification: Notification) {
        bar = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        let image = NSImage(systemSymbolName: "square.grid.3x3.fill", accessibilityDescription: toolName)
        image?.isTemplate = true
        bar.button?.image = image
        bar.button?.toolTip = toolName
        bar.menu = menu
        bar.isVisible = menuBarIconVisible
        menu.items[2].state = gestureEnabled ? .on : .off
        let nc = NSWorkspace.shared.notificationCenter
        nc.addObserver(self, selector: #selector(sleep), name: NSWorkspace.willSleepNotification, object: nil)
        nc.addObserver(self, selector: #selector(reconnect), name: NSWorkspace.didWakeNotification, object: nil)
        updateGesture()
        gestureTimer = Timer.scheduledTimer(timeInterval: 2, target: self, selector: #selector(checkSystemGesture), userInfo: nil, repeats: true)
        if !CommandLine.arguments.contains("--background") { show() }
    }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool { show(); return true }
    func applicationWillTerminate(_ notification: Notification) {
        gestureTimer?.invalidate(); SystemPinchStop(); TouchStop()
    }
    @objc private func sleep() { SystemPinchStop(); TouchStop(); gestureOK = false; systemGestureOK = false }
    @objc private func reconnect() { TouchStop(); updateGesture() }
    @objc private func toggleGesture() {
        UserDefaults.standard.set(gestureEnabled, forKey: "gestureDisabled")
        updateGesture()
    }
    @objc private func toggleMenuBarIcon() {
        let visible = !menuBarIconVisible
        UserDefaults.standard.set(!visible, forKey: menuBarIconHiddenKey)
        bar.isVisible = visible
    }
    @objc private func toggleLogin() {
        do {
            let service = SMAppService.mainApp
            if service.status == .enabled || service.status == .requiresApproval { try service.unregister() }
            else { try service.register() }
        } catch {
            let alert = NSAlert()
            alert.messageText = "无法更改开机启动"
            alert.informativeText = error.localizedDescription
            alert.runModal()
        }
    }
    private func updateGesture() {
        if !gestureEnabled {
            sleep()
            checkSystemGesture()
            return
        }
        gestureOK = TouchStart {
            DispatchQueue.main.async {
                (NSApp.delegate as? Launcher)?.showFromGesture()
            }
        }
        checkSystemGesture()
    }
    @objc private func checkSystemGesture() {
        let requestingTakeover = !disableSystemTap && gestureEnabled
        let trusted = requestingTakeover && SystemPinchTrusted()
        let needsPermission = requestingTakeover && !trusted
        if model.needsGesturePermission != needsPermission {
            model.needsGesturePermission = needsPermission
        }
        guard trusted && gestureOK else {
            SystemPinchStop()
            systemGestureOK = false
            return
        }
        systemGestureOK = SystemPinchStart {
            DispatchQueue.main.async {
                (NSApp.delegate as? Launcher)?.showFromGesture()
            }
        }
    }
    @objc private func openAccessibility() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") else { return }
        hide(restore: false) { NSWorkspace.shared.open(url) }
    }
    private func showFromGesture() {
        if gestureEnabled && window?.isVisible != true { show() }
    }
    @objc private func quit() {
        if isClosing { NSApp.terminate(nil); return }
        hide(restore: false) { NSApp.terminate(nil) }
    }
    @objc func show() {
        guard window?.isVisible != true else { return }
        checkSystemGesture()
        let mouse = NSEvent.mouseLocation
        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(mouse) }) ?? NSScreen.main else { return }
        if let front = NSWorkspace.shared.frontmostApplication, front != NSRunningApplication.current { previousApp = front }
        let catalog = Catalog.shared.load()
        model.load(catalog.apps, defaultItems: catalog.items)
        pageSwipe = PageSwipe()
        model.isExpanded = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        model.close = { [weak self] in self?.hide(restore: true) }
        model.openApp = { [weak self] url in
            self?.hide(restore: false) { self?.launch(url) }
        }
        let w = LauncherWindow(contentRect: screen.frame, styleMask: [.borderless], backing: .buffered, defer: false, screen: screen)
        w.isReleasedWhenClosed = false
        w.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.mainMenuWindow)) + 1)
        w.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary, .ignoresCycle]
        w.isOpaque = false
        w.backgroundColor = .clear
        w.hasShadow = false
        w.title = toolName
        w.delegate = self
        let wall = NSWorkspace.shared.desktopImageURL(for: screen).flatMap { NSImage(contentsOf: $0) }
        w.contentView = LauncherHostingView(rootView: LauncherView(
            model: model, wallpaper: wall, topInset: screen.safeAreaInsets.top,
            openPermissionSettings: { [weak self] in self?.openAccessibility() },
            menu: { [weak self] in self?.openOptions() }
        ))
        w.setFrame(screen.frame, display: true)
        w.handleKey = { [weak self] evt in self?.handleKey(evt) ?? false }
        w.handleScroll = { [weak self] evt in self?.handleScroll(evt) }
        window = w
        NSApp.activate()
        w.makeKeyAndOrderFront(nil)
        if !model.isExpanded {
            // Commit the collapsed view before animating to its resting size.
            w.displayIfNeeded()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.02) { [weak self, weak w] in
                guard let self, let w, self.window === w, !self.isClosing else { return }
                withAnimation(.easeOut(duration: 0.28)) { self.model.isExpanded = true }
            }
        }
    }

    private func hide(restore: Bool, animated: Bool = true, completion: @escaping () -> Void = {}) {
        guard let w = window else { completion(); return }
        guard !isClosing else { return }
        isClosing = true
        w.ignoresMouseEvents = true
        let finish = { [weak self, weak w] in
            guard let self, let w, self.window === w else { return }
            self.window = nil
            w.orderOut(nil)
            self.isClosing = false
            if restore { self.previousApp?.activate() }
            completion()
        }
        if animated && model.isExpanded && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            withAnimation(.easeIn(duration: 0.22), completionCriteria: .logicallyComplete) {
                model.isExpanded = false
            } completion: { finish() }
        } else {
            finish()
        }
    }

    private func launch(_ url: URL) {
        NSWorkspace.shared.openApplication(at: url, configuration: .init()) { _, error in
            guard let error else { return }
            DispatchQueue.main.async {
                let alert = NSAlert()
                alert.messageText = "无法打开应用"
                alert.informativeText = error.localizedDescription
                alert.runModal()
            }
        }
    }
    private func handleKey(_ e: NSEvent) -> Bool {
        if isClosing { return true }
        if e.keyCode == 53 {
            if model.editingName { model.editingName = false }
            else if model.folderID != nil { model.clearFolder() }
            else { hide(restore: true) }
            return true
        }
        if e.modifierFlags.intersection([.shift, .control, .option, .command]).isEmpty {
            if e.keyCode == 123 || e.keyCode == 124 {
                if !model.searching && !model.editingName { model.move(e.keyCode == 123 ? -1 : 1); return true }
            }
        }
        return false
    }
    private func handleScroll(_ e: NSEvent) {
        guard !isClosing, e.momentumPhase.isEmpty, !model.editingName else { return }
        let dx = e.scrollingDeltaX, dy = e.scrollingDeltaY
        if e.hasPreciseScrollingDeltas && !e.phase.isEmpty {
            let phase = e.phase
            if phase.contains(.began) { pageSwipe = PageSwipe() }
            if phase.contains(.cancelled) {
                model.finishSwipe(by: pageSwipe.finish(at: e.timestamp, cancelled: true))
            } else if phase.contains(.ended) {
                _ = pageSwipe.track(dx: dx, dy: dy, at: e.timestamp)
                model.finishSwipe(by: pageSwipe.finish(at: e.timestamp))
            } else if phase.contains(.began) || phase.contains(.changed),
                      let distance = pageSwipe.track(dx: dx, dy: dy, at: e.timestamp) {
                let limit = (window?.frame.width ?? 1000) * 0.95
                model.trackSwipe(min(limit, max(-limit, distance)))
            }
        } else if e.timestamp - lastPageAt >= 0.25 {
            if e.hasPreciseScrollingDeltas && abs(dx) <= abs(dy) { return }
            let delta = abs(dx) > abs(dy) ? dx : dy
            if abs(delta) >= (e.hasPreciseScrollingDeltas ? 5 : 1) {
                model.move(delta < 0 ? 1 : -1)
                lastPageAt = e.timestamp
            }
        }
    }
    private func openOptions() {
        guard let view = window?.contentView else { return }
        optionsShown = true
        defer { optionsShown = false }
        let pointer = view.convert(window?.mouseLocationOutsideOfEventStream ?? .zero, from: nil)
        menu.popUp(positioning: nil, at: pointer, in: view)
    }
}

extension Launcher: NSMenuDelegate, NSWindowDelegate {
    func menuNeedsUpdate(_ m: NSMenu) {
        m.items[2].state = gestureEnabled ? .on : .off
        m.items[2].title = gestureEnabled && !gestureOK ? "四指或五指捏合（未连接）" : "四指或五指捏合"
        if model.needsGesturePermission {
            m.items[5].title = "系统捏合：未授权…"
        } else if SystemPinchSuppressionCount() > 0 && systemGestureOK {
            m.items[5].title = "系统捏合：接管中"
        } else if systemGestureOK {
            m.items[5].title = "系统捏合：等待手势"
        } else {
            m.items[5].title = "系统捏合接管设置…"
        }
        let service = SMAppService.mainApp
        m.items[3].state = service.status == .enabled || service.status == .requiresApproval ? .on : .off
        m.items.first { $0.action == #selector(toggleMenuBarIcon) }?.state = menuBarIconVisible ? .on : .off
    }
    func windowDidResignKey(_ notification: Notification) {
        if !optionsShown && !NSApp.isActive && window?.isVisible == true { hide(restore: false, animated: false) }
    }
}

@main struct Main {
    @MainActor static func main() {
        let app = NSApplication.shared
        let delegate = Launcher()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        app.run()
    }
}
