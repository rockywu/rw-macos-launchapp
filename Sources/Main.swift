import AppKit
import SwiftUI
import ServiceManagement

let toolName = "RWLaunch"

func gesturePermissionName(in language: AppLanguage) -> String {
    if #available(macOS 27.0, *) { return language.text("Device Control & Data Access") }
    return language.text("Accessibility")
}

struct InstalledApp: Identifiable {
    let url: URL
    let bundleID: String
    let name: String
    let originalName: String
    var categoryIdentifier: String? = nil
    var id: String { url.path }

    func suggestedFolderName(in language: AppLanguage) -> String {
        let prefix = "public.app-category."
        guard let identifier = categoryIdentifier?.lowercased(), identifier.hasPrefix(prefix) else { return name }
        let category = identifier.dropFirst(prefix.count)
        if category == "games" || category.hasSuffix("-games") { return language.text("Games") }
        switch category {
        case "music": return language.text("Music")
        case "photography": return language.text("Photography")
        case "video": return language.text("Video")
        case "graphics-design": return language.text("Design")
        case "developer-tools": return language.text("Developer Tools")
        case "utilities": return language.text("Utilities")
        case "productivity", "business": return language.text("Productivity")
        case "social-networking": return language.text("Social")
        case "education": return language.text("Education")
        case "news": return language.text("News")
        case "finance": return language.text("Finance")
        case "reference": return language.text("Reference")
        case "entertainment": return language.text("Entertainment")
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
    func load(language: AppLanguage) -> (apps: [InstalledApp], items: [GridItemValue]) {
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
        if !utilities.isEmpty { items.append(.folder("utilities", language.text("Utilities"), utilities)) }
        if !systemOther.isEmpty { items.append(.folder("system-other", language.text("Other"), systemOther)) }
        if !games.isEmpty { items.append(.folder("games", language.text("Games"), games)) }
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
    private lazy var optionsItems: [(NSMenuItem, String)] = [
        (option(#selector(show)), "Open Launcher"),
        (.separator(), ""),
        (option(#selector(toggleGesture)), "4- or 5-Finger Pinch"),
        (option(#selector(toggleLogin)), "Open at Login"),
        (option(#selector(reconnect)), "Reconnect Trackpad"),
        (option(#selector(openAccessibility)), "System Pinch Settings…"),
        (option(#selector(toggleMenuBarIcon)), "Show Menu Bar Icon"),
        (NSMenuItem(), "Language"),
        (.separator(), ""),
        (option(#selector(quit), key: "q"), "Quit")
    ]
    private lazy var languageMenu: NSMenu = {
        let submenu = NSMenu()
        for selection in LanguagePreference.allCases {
            let item = option(#selector(selectLanguage(_:)))
            item.representedObject = selection.rawValue
            submenu.addItem(item)
        }
        return submenu
    }()
    private lazy var menu: NSMenu = {
        let m = NSMenu()
        m.delegate = self
        for (item, key) in optionsItems {
            if key == "Language" { item.submenu = languageMenu }
            m.addItem(item)
        }
        return m
    }()

    private func option(_ action: Selector, key: String = "") -> NSMenuItem {
        let item = NSMenuItem(title: "", action: action, keyEquivalent: key)
        item.target = self
        return item
    }

    @objc private func selectLanguage(_ sender: NSMenuItem) {
        guard let value = sender.representedObject as? String,
              let selection = LanguagePreference(rawValue: value) else { return }
        model.setLanguage(selection)
        menuNeedsUpdate(menu)
    }

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
        if !gestureEnabled && !menuBarIconVisible {
            setMenuBarIconVisible(true)
        } else {
            bar.isVisible = menuBarIconVisible
        }
        menuNeedsUpdate(menu)
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
        guard canToggleEntryPoint(#selector(toggleGesture)) else { return }
        UserDefaults.standard.set(gestureEnabled, forKey: "gestureDisabled")
        updateGesture()
        menuNeedsUpdate(menu)
    }
    @objc private func toggleMenuBarIcon() {
        guard canToggleEntryPoint(#selector(toggleMenuBarIcon)) else { return }
        setMenuBarIconVisible(!menuBarIconVisible)
        menuNeedsUpdate(menu)
    }
    private func canToggleEntryPoint(_ action: Selector?) -> Bool {
        switch action {
        case #selector(toggleGesture):
            return !gestureEnabled || menuBarIconVisible
        case #selector(toggleMenuBarIcon):
            return !menuBarIconVisible || gestureEnabled
        default:
            return true
        }
    }
    private func setMenuBarIconVisible(_ visible: Bool) {
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
            alert.messageText = model.language.text("Couldn’t Change Login Setting")
            alert.addButton(withTitle: model.language.text("OK"))
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
        let catalog = Catalog.shared.load(language: model.language)
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
            menu: { [weak self] in self?.openOptions() },
            requestUninstall: { [weak self] app in self?.requestUninstall(app) }
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
        NSWorkspace.shared.openApplication(at: url, configuration: .init()) { [weak self] _, error in
            guard let error else { return }
            DispatchQueue.main.async {
                let alert = NSAlert()
                let language = self?.model.language ?? .system()
                alert.messageText = language.text("Couldn’t Open App")
                alert.addButton(withTitle: language.text("OK"))
                alert.informativeText = error.localizedDescription
                alert.runModal()
            }
        }
    }
    private func requestUninstall(_ app: InstalledApp) {
        guard let window, window.attachedSheet == nil else { return }
        let language = model.language
        func showError(_ message: String) {
            let alert = NSAlert()
            alert.messageText = language.text("Couldn’t Uninstall App")
            alert.informativeText = message
            alert.addButton(withTitle: language.text("OK"))
            alert.beginSheetModal(for: window, completionHandler: nil)
        }
        let changed = language.text("The selected app has changed or cannot be uninstalled here.")
        guard let target = AppUninstall(app.url, bundleID: app.bundleID) else { showError(changed); return }
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = String(format: language.text("Uninstall “%@”?"), app.name)
        alert.informativeText = target.url.path + "\n\n" + language.text("The app will move to Trash. Its documents and settings will be kept.")
        let cancel = alert.addButton(withTitle: language.text("Cancel"))
        cancel.keyEquivalent = "\r"
        let remove = alert.addButton(withTitle: language.text("Move to Trash"))
        remove.hasDestructiveAction = true
        remove.keyEquivalent = ""
        alert.beginSheetModal(for: window) { [weak self] response in
            guard response == .alertSecondButtonReturn else { return }
            do {
                try target.moveToTrash()
                self?.model.didUninstall(app)
            } catch AppUninstall.Failure.changed { showError(changed) }
            catch AppUninstall.Failure.running { showError(language.text("Quit the app before uninstalling it.")) }
            catch { showError(error.localizedDescription) }
        }
    }
    private func handleKey(_ e: NSEvent) -> Bool {
        if window?.attachedSheet != nil { return false }
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

extension Launcher: NSMenuDelegate, NSMenuItemValidation, NSWindowDelegate {
    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        canToggleEntryPoint(menuItem.action)
    }

    func menuNeedsUpdate(_ m: NSMenu) {
        let language = model.language
        for (item, key) in optionsItems where !item.isSeparatorItem {
            item.title = language.text(key)
            switch item.action {
            case #selector(toggleGesture):
                item.state = gestureEnabled ? .on : .off
                if gestureEnabled && !gestureOK { item.title = language.text("Pinch (Disconnected)") }
            case #selector(openAccessibility):
                if model.needsGesturePermission {
                    item.title = language.text("System Pinch: Not Allowed…")
                } else if systemGestureOK {
                    item.title = language.text(SystemPinchSuppressionCount() > 0 ? "System Pinch: Active" : "System Pinch: Waiting")
                }
            case #selector(toggleLogin):
                let status = SMAppService.mainApp.status
                item.state = status == .enabled || status == .requiresApproval ? .on : .off
            case #selector(toggleMenuBarIcon):
                item.state = menuBarIconVisible ? .on : .off
            default: break
            }
        }
        for item in languageMenu.items {
            guard let value = item.representedObject as? String,
                  let selection = LanguagePreference(rawValue: value) else { continue }
            item.title = selection.label(in: language)
            item.state = selection == model.languagePreference ? .on : .off
        }
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
