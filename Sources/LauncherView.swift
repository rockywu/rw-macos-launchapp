import AppKit
import SwiftUI

private enum FolderOutline {
    static func icon(side: CGFloat) -> RoundedRectangle {
        RoundedRectangle(cornerRadius: side * 0.16, style: .continuous)
    }

    static func panel(side: CGFloat) -> RoundedRectangle {
        RoundedRectangle(cornerRadius: side * 0.075, style: .continuous)
    }
}

private struct TileTarget: Shape {
    let artworkSide: CGFloat
    let hitSide: CGFloat
    let isFolder: Bool
    let gap: CGFloat
    let labelWidth: CGFloat
    let labelHeight: CGFloat

    func path(in bounds: CGRect) -> Path {
        let top = bounds.midY - (artworkSide + gap + labelHeight) / 2
        var path = Path()
        let artwork = CGRect(x: bounds.midX - hitSide / 2, y: top + (artworkSide - hitSide) / 2,
                             width: hitSide, height: hitSide)
        if isFolder {
            path.addPath(FolderOutline.icon(side: hitSide).path(in: artwork))
        } else {
            path.addRoundedRect(in: artwork, cornerSize: CGSize(width: hitSide * 0.19, height: hitSide * 0.19))
        }
        path.addRect(CGRect(x: bounds.midX - labelWidth / 2, y: top + artworkSide + gap,
                            width: labelWidth, height: labelHeight))
        return path
    }
}

struct LauncherView: View {
    @ObservedObject var model: LaunchModel
    let wallpaper: NSImage?
    let topInset: CGFloat
    let openPermissionSettings: () -> Void
    let menu: () -> Void
    let requestUninstall: (InstalledApp) -> Void
    private var language: AppLanguage { model.language }
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @FocusState private var focus: Field?
    @State private var nameDraft = ""
    @State private var hovered: Entry?
    @State private var activating: Entry?
    @State private var activationTask: Task<Void, Never>?
    @State private var dragged: GridItemValue?
    @State private var dragFolder: String?
    @State private var dragIconSize: CGFloat = 0
    @State private var pointer = CGPoint.zero
    @State private var insertion: Insertion?
    @State private var mergeTarget: Entry?
    @State private var landing: Landing?
    @State private var edge = 0
    @State private var edgeTimer: Task<Void, Never>?
    private enum Field { case search, folderName }
    private struct Insertion: Equatable {
        let target: Entry?
        let placement: DropPlacement
    }
    private struct Landing {
        let id: UUID
        let page: Int
        let scale: CGFloat
        let opacity: Double
    }

    private struct FolderGrid {
        let size: CGFloat
        var normal: CGFloat { size * 0.85 }
        var small: CGFloat { size * 0.20 }
        var gridSide: CGFloat { normal * 0.79 }
        var gap: CGFloat { (gridSide - 3 * small) / 2 }

        func iconOffset(at index: Int) -> CGPoint {
            let first = (small - gridSide) / 2
            return CGPoint(x: first + CGFloat(index % 3) * (small + gap),
                           y: first + CGFloat(index / 3) * (small + gap))
        }
    }

    private struct Metrics {
        let width: CGFloat, height: CGFloat, topInset: CGFloat
        let showsPermissionHint: Bool
        var panel: CGRect? = nil
        var folderColumns = LaunchModel.folderColumns
        static let folderTitleGap: CGFloat = 8
        static let folderTitlePadding: CGFloat = 8
        var folderInset: CGFloat { (panel?.width ?? 0) * 0.028 }
        var rows: Int { panel == nil ? 5 : folderColumns }
        var columns: Int { panel == nil ? 7 : folderColumns }
        var viewportWidth: CGFloat { panel?.width ?? width }
        var viewportLeft: CGFloat { panel?.minX ?? 0 }
        var top: CGFloat { max(16, topInset + 9) }
        var bottom: CGFloat { max(29, height * 0.038) }
        var gridTop: CGFloat {
            if let panel { return panel.minY + folderInset }
            return max(top + (showsPermissionHint ? 122 : 72), height * 0.105)
        }
        var gridWidth: CGFloat { panel.map { $0.width - 2 * folderInset } ?? width * 0.886 }
        var left: CGFloat { (width - gridWidth) / 2 }
        var cellW: CGFloat { gridWidth / CGFloat(columns) }
        var cellH: CGFloat {
            if panel != nil { return cellW }
            return max(20, (height - gridTop - bottom - 12) / CGFloat(rows))
        }
        var gridHeight: CGFloat { cellH * CGFloat(rows) }
        var iconSize: CGFloat {
            panel == nil ? min(cellW * 0.55, cellH * 0.69, 144) : min(cellW * 0.65, 80)
        }

        var labelFontSize: CGFloat { max(10, min(16, panel == nil ? iconSize * 0.126 : iconSize * 0.17)) }
        let searchWidth: CGFloat = 245
        var permissionWidth: CGFloat { max(1, min(width - 32, 572)) }
        var titleFontSize: CGFloat { max(16, min(26, (panel?.width ?? 0) * 0.062)) }
        var titleFont: NSFont { .systemFont(ofSize: titleFontSize, weight: .semibold) }
        var folderHeaderTop: CGFloat { (panel?.minY ?? top) - Self.folderTitleGap - folderHeaderHeight }
        var folderHeaderHeight: CGFloat {
            ceil(titleFont.ascender - titleFont.descender + titleFont.leading) + 8
        }
        func folderTitleWidth(_ name: String, editing: Bool) -> CGFloat {
            let textWidth = (name as NSString).size(withAttributes: [.font: titleFont]).width
            let paddedWidth = ceil(textWidth) + 2 * Self.folderTitlePadding
            return min(max(1, viewportWidth - 2 * Self.folderTitlePadding), editing ? max(160, paddedWidth) : paddedWidth)
        }
        func centeredRect(width boxWidth: CGFloat, y: CGFloat, height: CGFloat) -> CGRect {
            CGRect(x: (width - boxWidth) / 2, y: y, width: boxWidth, height: height)
        }
        func containsControls(_ point: CGPoint, folderName: String?, editingName: Bool, pageCount: Int) -> Bool {
            let headerWidth = folderName.map { folderTitleWidth($0, editing: editingName) } ?? searchWidth
            let headerY = panel == nil ? top : folderHeaderTop
            if centeredRect(width: headerWidth, y: headerY, height: panel == nil ? 40 : folderHeaderHeight)
                .contains(point) { return true }
            if showsPermissionHint, centeredRect(width: permissionWidth, y: top + 50, height: 70).contains(point) { return true }
            return pageCount > 1 && centeredRect(width: CGFloat(22 * pageCount - 4),
                                                  y: dotsTop, height: 24).contains(point)
        }
        var dotsTop: CGFloat { panel.map { $0.maxY + 6 } ?? (height - bottom) }

        func tileTarget(for item: GridItemValue) -> TileTarget {
            let font = NSFont.systemFont(ofSize: labelFontSize, weight: .medium)
            let textWidth = (item.name as NSString).size(withAttributes: [.font: font]).width
            let hitSide: CGFloat
            let isFolder: Bool
            switch item {
            case .app: (hitSide, isFolder) = (iconSize * 0.92, false)
            case .folder: (hitSide, isFolder) = (iconSize * 0.85, true)
            }
            return TileTarget(artworkSide: iconSize, hitSide: hitSide, isFolder: isFolder, gap: max(3, iconSize * 0.10),
                              labelWidth: max(1, min(cellW - 12, ceil(textWidth) + 4)),
                              labelHeight: ceil(font.ascender - font.descender + font.leading) + 2)
        }

        func hitsTile(_ point: CGPoint, slot: Int, item: GridItemValue) -> Bool {
            let translation = CGPoint(x: left + CGFloat(slot % columns) * cellW,
                                      y: gridTop + CGFloat(slot / columns) * cellH)
            let local = CGPoint(x: point.x - translation.x, y: point.y - translation.y)
            return tileTarget(for: item).path(in: CGRect(x: 0, y: 0, width: cellW, height: cellH)).contains(local)
        }

        func slot(at point: CGPoint) -> Int? {
            let x = point.x - left, y = point.y - gridTop
            guard x >= 0, x < gridWidth, y >= 0, y < gridHeight else { return nil }
            return Int(y / cellH) * columns + Int(x / cellW)
        }
    }

    private func activeMetrics(_ root: Metrics) -> Metrics {
        guard model.folderID != nil else { return root }
        let itemCount = model.visibleItems.count
        let columns = itemCount <= 4 ? 2 : (itemCount <= 9 ? 3 : LaunchModel.folderColumns)
        let topReserve = root.top + 46 + Metrics.folderTitleGap
        let availableHeight = root.height - topReserve - 42 // Space below the panel for paging controls.
        let side = max(1, min(CGFloat(116 * columns + 40), root.width - 48, availableHeight))
        let panel = CGRect(x: (root.width - side) / 2, y: topReserve + (availableHeight - side) / 2,
                           width: side, height: side)
        return Metrics(width: root.width, height: root.height, topInset: root.topInset,
                       showsPermissionHint: false, panel: panel, folderColumns: columns)
    }

    var body: some View {
        GeometryReader { g in
            let m = Metrics(width: g.size.width, height: g.size.height, topInset: topInset,
                            showsPermissionHint: model.needsGesturePermission)
            let active = activeMetrics(m)
            let folderAtLayout = model.folderID
            let pageAtLayout = model.page
            ZStack(alignment: .top) {
                background(m).opacity(model.isExpanded || reduceMotion ? 1 : 0)
                    .allowsHitTesting(false)
                Color.clear.contentShape(Rectangle()).accessibilityHidden(true)
                ZStack(alignment: .top) {
                    rootLayer(m)
                        .allowsHitTesting(folderAtLayout == nil)
                        .disabled(folderAtLayout != nil)
                        .accessibilityHidden(folderAtLayout != nil)
                    ZStack(alignment: .top) {
                        if let panel = active.panel {
                            Color.black.opacity(0.25).allowsHitTesting(false).accessibilityHidden(true)
                                .transition(.opacity)
                            folderLayer(active, panel: panel)
                                .transition(.scale(scale: 0.94).combined(with: .opacity))
                        }
                    }
                    .animation(reduceMotion ? nil : .easeOut(duration: 0.19), value: folderAtLayout)
                    if let dragged {
                        artwork(dragged, size: dragIconSize)
                            .opacity(landing?.opacity ?? 0.83).scaleEffect(landing?.scale ?? 0.9)
                            .position(x: pointer.x, y: pointer.y).allowsHitTesting(false).accessibilityHidden(true)
                    }
                }
                .frame(width: m.width, height: m.height, alignment: .top)
                .scaleEffect(model.isExpanded || reduceMotion ? 1 : 0.88)
                .opacity(model.isExpanded || reduceMotion ? 1 : 0)
                .allowsHitTesting(model.isExpanded || reduceMotion)
            }.frame(width: m.width, height: m.height).clipped().foregroundStyle(.white)
                .preferredColorScheme(.dark)
                .coordinateSpace(name: "launcher")
                .onContinuousHover(coordinateSpace: .named("launcher")) { phase in
                    switch phase {
                    case .active(let point):
                        setHover(tile(at: point, metrics: active)?.entry)
                    case .ended:
                        setHover(nil)
                    }
                }
                .simultaneousGesture(
                    dragGesture(m).exclusively(before: SpatialTapGesture(count: 1, coordinateSpace: .named("launcher"))
                        .onEnded {
                            guard folderAtLayout == model.folderID, pageAtLayout == model.page else { return }
                            handleClick($0.location, metrics: active)
                        })
                )
                .transaction { if reduceMotion { $0.animation = nil; $0.disablesAnimations = true } }
        }
        .onAppear { focus = .search }
        .onChange(of: model.editingName) { _, editing in
            if editing {
                nameDraft = model.folderName
                focus = .folderName
            } else if focus == .folderName { focus = nil }
        }
        .onChange(of: model.folderID) { _, folder in
            if !(folder == nil && dragFolder != nil && dragged != nil) { finishDrag() }
            resetFeedback()
            if folder == nil { focus = .search }
            else if !model.editingName { focus = nil }
        }
        .onChange(of: model.page) { _, page in
            if let landing, landing.page != page { finishDrag() }
            resetFeedback()
        }
        .onChange(of: model.query) { _, _ in resetFeedback() }
        .onChange(of: model.isExpanded) { _, expanded in
            if !expanded {
                finishDrag()
                resetFeedback()
            }
        }
        .onDisappear {
            finishDrag()
            resetFeedback()
        }
    }

    private func rootLayer(_ m: Metrics) -> some View {
        let items = model.rootItems
        let interactive = model.folderID == nil
        return ZStack(alignment: .top) {
            if interactive {
                header(m).frame(height: 40).offset(y: m.top)
            }
            if interactive && m.showsPermissionHint {
                permissionHint(width: m.permissionWidth).offset(y: m.top + 50)
            }
            if items.isEmpty {
                Text(language.text("No apps found")).foregroundStyle(.white.opacity(0.8)).offset(y: m.gridTop + m.cellH)
            } else {
                pages(m, items: items, page: model.rootPage, capacity: LaunchModel.rootCapacity,
                      interactive: interactive).offset(y: m.gridTop)
            }
            if interactive {
                pageDots(count: max(1, (items.count + LaunchModel.rootCapacity - 1) / LaunchModel.rootCapacity),
                         page: model.rootPage).offset(y: m.dotsTop)
            }
        }
        .frame(width: m.width, height: m.height, alignment: .top)
    }

    private func folderLayer(_ m: Metrics, panel: CGRect) -> some View {
        ZStack(alignment: .top) {
            let shape = FolderOutline.panel(side: panel.width)
            shape.fill(Color(red: 0.10, green: 0.17, blue: 0.22).opacity(0.49))
                .background(.ultraThinMaterial.opacity(0.40), in: shape)
                .overlay(shape.strokeBorder(.white.opacity(0.24)))
                .shadow(color: .black.opacity(0.32), radius: 21, y: 8)
                .frame(width: panel.width, height: panel.height)
                .offset(y: panel.minY)
                .accessibilityHidden(true)
            header(m).frame(height: m.folderHeaderHeight).offset(y: m.folderHeaderTop)
            pages(m, items: model.visibleItems, page: model.page, capacity: LaunchModel.folderCapacity,
                  interactive: true).offset(y: m.gridTop)
            pageDots(count: model.pageCount, page: model.page).offset(y: m.dotsTop)
        }
        .frame(width: m.width, height: m.height, alignment: .top)
    }

    @ViewBuilder private func pageDots(count: Int, page: Int) -> some View {
        if count > 1 {
            HStack(spacing: 4) {
                ForEach(0..<count, id: \.self) { n in
                    Button { model.go(n) } label: {
                        Circle().fill(.white.opacity(n == page ? 1 : 0.37))
                            .frame(width: 7, height: 7).frame(width: 18, height: 24)
                            .contentShape(Rectangle())
                    }.buttonStyle(.plain).accessibilityLabel(String(format: language.text("Page %lld"), n + 1))
                        .accessibilityAddTraits(n == page ? .isSelected : [])
                }
            }
        }
    }

    private func permissionHint(width: CGFloat) -> some View {
        HStack(spacing: 11) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Color(red: 1, green: 0.8, blue: 0.45))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(language.text("System Pinch Is Not Active")).font(.system(size: 13, weight: .semibold))
                Text(String(format: language.text("Allow RWLaunch under %@ to prevent the system Apps view from opening."),
                            gesturePermissionName(in: language)))
                    .font(.system(size: 12)).foregroundStyle(.white.opacity(0.86))
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 4)
            Button(language.text("Open Settings"), action: openPermissionSettings)
                .buttonStyle(.bordered)
                .fixedSize()
        }
        .padding(.horizontal, 13).padding(.vertical, 8)
        .frame(width: max(1, width))
        .background(Color(red: 0.11, green: 0.14, blue: 0.18), in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(.white.opacity(0.18)).allowsHitTesting(false))
    }

    private func background(_ m: Metrics) -> some View {
        ZStack {
            BlurFallback()
            if let wallpaper {
                Image(nsImage: wallpaper).resizable().scaledToFill()
                    .frame(width: m.width + 160, height: m.height + 160).blur(radius: 48)
                Color(red: 0.015, green: 0.095, blue: 0.135).opacity(0.46)
            }
        }.frame(width: m.width, height: m.height).clipped()
            .accessibilityHidden(true)
    }

    // Mouse clicks and drags share one recognizer so a drop cannot also activate a tile.
    private func handleClick(_ point: CGPoint, metrics m: Metrics) {
        guard dragged == nil, activating == nil, model.isExpanded,
              !m.containsControls(point, folderName: model.folderID == nil ? nil : model.folderName,
                                  editingName: model.editingName,
                                  pageCount: model.pageCount) else { return }
        if let item = tile(at: point, metrics: m) { activate(item) }
        else if model.editingName { model.rename(nameDraft) }
        else if m.panel?.contains(point) != true { model.dismissCurrentLevel() }
    }

    private func tile(at point: CGPoint, metrics m: Metrics) -> GridItemValue? {
        let gridPoint = CGPoint(x: point.x - swipeOffset(m), y: point.y)
        let items = model.currentItems
        guard let slot = m.slot(at: gridPoint), items.indices.contains(slot),
              m.hitsTile(gridPoint, slot: slot, item: items[slot]) else { return nil }
        return items[slot]
    }

    private func swipeOffset(_ m: Metrics) -> CGFloat {
        let limit = m.viewportWidth * 0.95
        return reduceMotion ? 0 : min(limit, max(-limit, model.swipeOffset))
    }

    private func setHover(_ entry: Entry?) {
        let next = dragged == nil && model.isExpanded ? entry : nil
        if hovered != next { hovered = next }
    }

    private func resetFeedback() {
        activationTask?.cancel()
        activationTask = nil
        activating = nil
        hovered = nil
    }

    private func activate(_ item: GridItemValue) {
        guard dragged == nil, activating == nil, model.isExpanded, !model.editingName else { return }
        let folder = model.folderID, page = model.page, query = model.query
        activating = item.entry
        activationTask = Task { @MainActor in
            do { try await Task.sleep(for: .milliseconds(110)) }
            catch { return }
            guard !Task.isCancelled else { return }
            activationTask = nil
            if model.isExpanded, !model.editingName, model.folderID == folder,
               model.page == page, model.query == query { model.choose(item) }
            activating = nil
        }
    }

    @ViewBuilder private func header(_ m: Metrics) -> some View {
        if m.panel != nil {
            let badge = RoundedRectangle(cornerRadius: 8, style: .continuous)
            Group {
                if model.editingName {
                    TextField(language.text("Folder Name"), text: $nameDraft)
                        .textFieldStyle(.plain)
                        .multilineTextAlignment(.center)
                        .focused($focus, equals: .folderName)
                        .accessibilityLabel(language.text("Folder Name"))
                        .onSubmit { model.rename(nameDraft) }
                } else {
                    Text(model.folderName).lineLimit(1)
                        .padding(.horizontal, Metrics.folderTitlePadding)
                        .frame(width: m.folderTitleWidth(model.folderName, editing: false), height: m.folderHeaderHeight)
                        .contentShape(Rectangle())
                        .onLongPressGesture(minimumDuration: 0.45, maximumDistance: 7) {
                            if dragged == nil { model.editingName = true }
                        }
                        .help(language.text("Press and hold the folder name to rename it"))
                        .accessibilityAction(named: Text(language.text("Rename Folder"))) { model.editingName = true }
                        .accessibilityAction(named: Text(language.text("Close Folder"))) { model.clearFolder() }
                }
            }.font(.system(size: m.titleFontSize, weight: .semibold))
                .padding(.horizontal, model.editingName ? Metrics.folderTitlePadding : 0)
                .frame(width: m.folderTitleWidth(model.folderName, editing: model.editingName), height: m.folderHeaderHeight)
                .background(Color(red: 0.08, green: 0.13, blue: 0.18).opacity(model.editingName ? 0.88 : 0.68), in: badge)
                .overlay(badge.strokeBorder(.white.opacity(model.editingName ? 0.28 : 0.10)).allowsHitTesting(false))
        } else {
            HStack(spacing: 9) {
                Image(systemName: "magnifyingglass").font(.system(size: 16, weight: .medium)).accessibilityHidden(true)
                TextField("", text: $model.query, prompt: Text(language.text("Search Apps")).foregroundStyle(.white.opacity(0.64)))
                    .textFieldStyle(.plain).font(.system(size: 15, weight: .medium))
                    .accessibilityLabel(language.text("Search Apps")).focused($focus, equals: .search)
                    .onSubmit { if model.searching, let first = model.visibleItems.first { activate(first) } }
                Button(action: menu) {
                    Image(systemName: "ellipsis.circle").font(.system(size: 18)).foregroundStyle(.white.opacity(0.72))
                }.buttonStyle(.plain).accessibilityLabel(language.text("Options"))
            }.padding(.horizontal, 15).frame(width: m.searchWidth, height: 40)
                .background(.white.opacity(0.10), in: Capsule())
                .overlay(Capsule().strokeBorder(.white.opacity(0.18)))
        }
    }

    private func pages(_ m: Metrics, items: [GridItemValue], page: Int, capacity: Int,
                       interactive: Bool) -> some View {
        let displayed = interactive ? projectedItems(items) : items
        let entries = displayed.map(\.entry)
        let slots = Dictionary(entries.enumerated().map { ($0.element, $0.offset) },
                               uniquingKeysWith: { first, _ in first })
        let pageCount = max(1, (entries.count + capacity - 1) / capacity)
        // Clip neighboring pages at the sides while leaving room for the expanded frame.
        let verticalClearance = m.labelFontSize + m.iconSize * 0.08
        return ZStack(alignment: .topLeading) {
            ZStack(alignment: .topLeading) {
                ForEach(displayed) { item in
                    if let index = slots[item.entry] {
                        let itemPage = index / capacity
                        let slot = index % capacity
                        let lifted = dragged?.entry == item.entry
                        cell(item, m)
                            .opacity(lifted ? 0 : 1)
                            .allowsHitTesting(interactive && itemPage == page && !lifted)
                            .accessibilityHidden(!interactive || itemPage != page || lifted)
                            .position(x: CGFloat(itemPage) * m.viewportWidth + m.left - m.viewportLeft +
                                        (CGFloat(slot % m.columns) + 0.5) * m.cellW,
                                      y: (CGFloat(slot / m.columns) + 0.5) * m.cellH)
                    }
                }
            }.frame(width: CGFloat(pageCount) * m.viewportWidth, height: m.gridHeight)
                .offset(x: -CGFloat(page) * m.viewportWidth + (interactive ? swipeOffset(m) : 0))
        }.frame(width: m.viewportWidth, height: m.gridHeight, alignment: .topLeading)
            .padding(.vertical, verticalClearance).clipped()
            .padding(.vertical, -verticalClearance)
    }

    private func projectedItems(_ items: [GridItemValue]) -> [GridItemValue] {
        guard let dragged else { return items }
        if let dragFolder, model.folderID == nil {
            guard let insertion else { return items }
            return model.previewExtraction(dragged.entry, from: dragFolder, onto: insertion.target,
                                           placement: insertion.placement)
        }
        guard let insertion else { return items }
        let indexed = Dictionary(items.map { ($0.entry, $0) }, uniquingKeysWith: { first, _ in first })
        return insertion.placement.reordering(items.map(\.entry), moving: dragged.entry, onto: insertion.target)
            .compactMap { indexed[$0] }
    }

    private func cell(_ item: GridItemValue, _ m: Metrics) -> some View {
        let target = m.tileTarget(for: item)
        let pressed = activating == item.entry
        let highlighted = activating == nil && dragged == nil && model.isExpanded && !model.editingName &&
            model.swipeOffset == 0 && hovered == item.entry
        return VStack(spacing: target.gap) {
            artwork(item, size: m.iconSize, merging: mergeTarget == item.entry)
                .scaleEffect(reduceMotion ? 1 : (pressed ? 1.09 : highlighted ? 1.04 : 1))
                .brightness(pressed ? 0.12 : highlighted ? 0.06 : 0)
                .animation(.easeOut(duration: 0.09), value: pressed)
                .animation(.easeOut(duration: 0.13), value: highlighted)
            Text(item.name).font(.system(size: m.labelFontSize, weight: .medium))
                .lineLimit(1).truncationMode(.tail)
                .frame(width: target.labelWidth, height: target.labelHeight)
                .shadow(color: .black.opacity(0.55), radius: 3, y: 1)
        }.frame(width: m.cellW, height: m.cellH).contentShape(.interaction, target)
            .focusable(interactions: .activate)
            .onKeyPress(keys: [.space, .return]) { _ in
                activate(item)
                return .handled
            }
            .accessibilityRepresentation { Button(item.name) { activate(item) } }
            .accessibilityActions { uninstallAction(item) }
            .help(item.name)
            .contextMenu {
                if !model.searching {
                    Button(language.text("Move Earlier")) { model.shift(item.entry, by: -1) }
                    Button(language.text("Move Later")) { model.shift(item.entry, by: 1) }
                    if case .folder(let id, _, _) = item {
                        Button(language.text("Rename Folder")) { model.edit(id) }
                    } else if model.folderID != nil {
                        Button(language.text("Remove from Folder")) { model.removeFromFolder(item.entry) }
                    } else if case .app = item {
                        Menu(language.text("Merge into Folder")) {
                            ForEach(model.currentItems.filter { $0.entry != item.entry }) { target in
                                Button(target.name) { model.place(item.entry, onto: target.entry, placement: .center) }
                            }
                        }
                    }
                }
                if case .app(let app) = item, AppUninstall.offered(for: app.url) {
                    if !model.searching { Divider() }
                    uninstallAction(item)
                }
            }
    }

    @ViewBuilder private func uninstallAction(_ item: GridItemValue) -> some View {
        if case .app(let app) = item, AppUninstall.offered(for: app.url) {
            Button(language.text("Uninstall…"), role: .destructive) { requestUninstall(app) }
        }
    }

    private func dragGesture(_ m: Metrics) -> some Gesture {
        DragGesture(minimumDistance: 7, coordinateSpace: .named("launcher"))
            .onChanged { value in
                guard landing == nil else { return }
                if dragged == nil {
                    let active = activeMetrics(m)
                    guard model.isExpanded, activating == nil, !model.searching, !model.editingName,
                          let item = tile(at: value.startLocation, metrics: active) else { return }
                    dragged = item
                    dragFolder = model.folderID
                    dragIconSize = active.iconSize
                }
                pointer = value.location
                let active = trackDrag(m)
                scheduleEdge(active)
            }.onEnded { value in
                guard let dragged, landing == nil else { return }
                pointer = value.location
                _ = trackDrag(m)
                if let dragFolder, model.folderID == nil {
                    if m.slot(at: pointer) != nil {
                        model.extract(dragged.entry, from: dragFolder, onto: insertion?.target,
                                      placement: insertion?.placement)
                    }
                } else if let mergeTarget {
                    completeMerge(dragged.entry, into: mergeTarget, metrics: m)
                    return
                } else if let insertion {
                    model.place(dragged.entry, onto: insertion.target, placement: insertion.placement)
                }
                finishDrag()
            }
    }

    private func trackDrag(_ root: Metrics) -> Metrics {
        var active = activeMetrics(root)
        if let panel = active.panel, !panel.contains(pointer) {
            // The gesture stays on the launcher when the panel disappears.
            edgeTimer?.cancel()
            edge = 0
            insertion = nil
            model.clearFolder()
            active = root
        }
        updateTarget(active)
        return active
    }

    private func completeMerge(_ source: Entry, into target: Entry, metrics m: Metrics) {
        edgeTimer?.cancel()
        let id = UUID()
        let all = model.visibleItems
        let previewCenter = m.slot(at: pointer).flatMap { slot in
            all.first { $0.entry == target }.map { artworkCenter(of: $0, at: slot, metrics: m) }
        }
        withAnimation(.easeInOut(duration: 0.24), completionCriteria: .logicallyComplete) {
            insertion = nil
            mergeTarget = nil
            // Save the drop immediately. Only the icon's visual arrival is delayed.
            guard let destination = model.place(source, onto: target, placement: .center),
                  !reduceMotion else { return }
            let items = model.currentItems
            guard let slot = items.firstIndex(where: { $0.entry == destination }),
                  case .folder(_, _, let apps) = items[slot] else {
                // Removing the source can move the first folder on this page to the preceding page.
                if let previewCenter {
                    pointer = previewCenter
                    landing = Landing(id: id, page: model.page, scale: 0.12, opacity: 0)
                }
                return
            }
            let center = artworkCenter(of: items[slot], at: slot, metrics: m)
            let grid = FolderGrid(size: m.iconSize)
            if let index = apps.prefix(9).firstIndex(where: { Entry.app($0.bundleID) == source }) {
                let offset = grid.iconOffset(at: index)
                pointer = CGPoint(x: center.x + offset.x, y: center.y + offset.y)
                landing = Landing(id: id, page: model.page, scale: grid.small / m.iconSize, opacity: 1)
            } else {
                // Full previews have no free thumbnail; the icon disappears into the center.
                pointer = center
                landing = Landing(id: id, page: model.page, scale: 0.12, opacity: 0)
            }
        } completion: {
            if landing?.id == id { finishDrag() }
        }
        if landing == nil { finishDrag() }
    }

    private func artworkCenter(of item: GridItemValue, at slot: Int, metrics m: Metrics) -> CGPoint {
        let tile = m.tileTarget(for: item)
        return CGPoint(x: m.left + (CGFloat(slot % m.columns) + 0.5) * m.cellW,
                       y: m.gridTop + (CGFloat(slot / m.columns) + 0.5) * m.cellH - (tile.gap + tile.labelHeight) / 2)
    }

    private func updateTarget(_ m: Metrics) {
        guard let dragged, let slot = m.slot(at: pointer) else {
            previewMerge(nil)
            preview(nil)
            return
        }
        let entries = projectedItems(model.visibleItems).map(\.entry)
        let index = model.page * model.capacity + slot
        guard entries.indices.contains(index) else {
            previewMerge(nil)
            preview(Insertion(target: nil, placement: .after))
            return
        }
        let target = entries[index]
        // The lifted item's slot is the gap. Keep it open while the pointer is inside it.
        guard target != dragged.entry else {
            previewMerge(nil)
            return
        }
        let localX = (pointer.x - m.left).truncatingRemainder(dividingBy: m.cellW) / m.cellW
        let localY = (pointer.y - m.gridTop).truncatingRemainder(dividingBy: m.cellH) / m.cellH
        if model.folderID == nil, dragFolder == nil, case .app = dragged, (0.31...0.69).contains(localX),
           (0.11...0.78).contains(localY) {
            previewMerge(target)
        } else {
            previewMerge(nil)
            preview(Insertion(target: target, placement: localX < 0.5 ? .before : .after))
        }
    }

    private func preview(_ next: Insertion?) {
        guard insertion != next else { return }
        withAnimation(.easeInOut(duration: 0.18)) { insertion = next }
    }

    private func previewMerge(_ target: Entry?) {
        guard mergeTarget != target else { return }
        withAnimation(.easeInOut(duration: 0.16)) { mergeTarget = target }
    }

    private func scheduleEdge(_ m: Metrics) {
        let right = m.left + m.gridWidth
        let intent = pointer.x < m.left && model.page > 0 ? -1 :
            (pointer.x > right && model.page + 1 < model.pageCount ? 1 : 0)
        guard intent != edge else { return }
        edgeTimer?.cancel()
        edge = intent
        if intent != 0 {
            edgeTimer = Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(500))
                guard !Task.isCancelled, dragged != nil, edge == intent else { return }
                model.move(intent)
                updateTarget(m)
                edge = 0
                scheduleEdge(m)
            }
        }
    }

    private func finishDrag() {
        edgeTimer?.cancel()
        edgeTimer = nil
        edge = 0
        dragged = nil
        dragFolder = nil
        insertion = nil
        landing = nil
        previewMerge(nil)
    }

    @ViewBuilder private func artwork(_ item: GridItemValue, size: CGFloat, merging: Bool = false) -> some View {
        switch item {
        case .app(let app):
            if merging {
                folderArtwork([app], size: size, merging: true)
            } else {
                Image(nsImage: Catalog.shared.icon(app)).resizable().interpolation(.high).scaledToFit()
                    .frame(width: size, height: size).shadow(color: .black.opacity(0.32), radius: 5, y: 4)
                    .accessibilityHidden(true)
            }
        case .folder(_, _, let apps):
            folderArtwork(apps, size: size, merging: merging)
        }
    }

    private func folderArtwork(_ apps: [InstalledApp], size: CGFloat, merging: Bool) -> some View {
        let grid = FolderGrid(size: size)
        let panelSide = merging ? grid.normal * 1.15 : grid.normal
        let panel = FolderOutline.icon(side: panelSide)
        return ZStack {
            panel.fill(.white.opacity(merging ? 0.12 : 0.09))
                .overlay(panel.strokeBorder(.white.opacity(merging ? 0.24 : 0.15)))
                .frame(width: panelSide, height: panelSide)
            LazyVGrid(columns: Array(repeating: SwiftUI.GridItem(.fixed(grid.small), spacing: grid.gap), count: 3),
                      spacing: grid.gap) {
                ForEach(Array(apps.prefix(9))) { app in
                    Image(nsImage: Catalog.shared.icon(app)).resizable().scaledToFit()
                        .frame(width: grid.small, height: grid.small)
                        .opacity(landing != nil && dragged?.entry == .app(app.bundleID) ? 0 : 1)
                }
            }.frame(width: grid.gridSide, height: grid.gridSide, alignment: .top)
        }
        .frame(width: size, height: size).accessibilityHidden(true)
    }
}
