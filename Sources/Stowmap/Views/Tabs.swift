import SwiftUI

// MARK: - Donut chart

struct DonutSlice: Identifiable {
    let id: Int
    var node: FileNode?
    var label: String
    var size: Int64
    var color: Color
    var start: Double      // 0…1 around the ring, clockwise from 12 o'clock
    var end: Double
}

struct RingSegment: Shape {
    var start: Double
    var end: Double
    var thickness: CGFloat
    var gap: Double = 0.004

    func path(in rect: CGRect) -> Path {
        let c = CGPoint(x: rect.midX, y: rect.midY)
        let outer = min(rect.width, rect.height) / 2
        let inner = max(0, outer - thickness)
        var s = start, e = end
        if e - s > gap * 2.5 && e - s < 0.999 { s += gap / 2; e -= gap / 2 }
        let a0 = Angle.degrees(-90 + 360 * s), a1 = Angle.degrees(-90 + 360 * e)
        var p = Path()
        p.addArc(center: c, radius: outer, startAngle: a0, endAngle: a1, clockwise: false)
        p.addArc(center: c, radius: inner, startAngle: a1, endAngle: a0, clockwise: true)
        p.closeSubpath()
        return p
    }
}

struct DonutChart<Center: View>: View {
    var slices: [DonutSlice]
    @Binding var hovered: Int?
    var onTap: (DonutSlice) -> Void
    @ViewBuilder var center: () -> Center

    private let inset: CGFloat = 8

    var body: some View {
        GeometryReader { geo in
            let side = max(120, min(geo.size.width, geo.size.height))
            let thickness = max(24, side * 0.17)
            ZStack {
                Circle().strokeBorder(Color.white.opacity(0.05), lineWidth: thickness).padding(inset)
                ForEach(slices) { s in
                    let hot = hovered == s.id
                    RingSegment(start: s.start, end: s.end, thickness: thickness + (hot ? inset : 0))
                        .fill(s.color)
                        .opacity(hovered == nil || hot ? 1 : 0.55)
                        .padding(hot ? 0 : inset)
                        .shadow(color: hot ? s.color.opacity(0.55) : Color.clear, radius: 10)
                }
                center()
                    .frame(width: max(60, side - (thickness + inset) * 2 - 24))
                    .allowsHitTesting(false)
            }
            .frame(width: side, height: side)
            .contentShape(Circle())
            .onContinuousHover(coordinateSpace: .local) { phase in
                switch phase {
                case .active(let pt): hovered = hit(pt, side: side, thickness: thickness)
                case .ended: hovered = nil
                }
            }
            .onTapGesture {
                if let h = hovered, let s = slices.first(where: { $0.id == h }) { onTap(s) }
            }
            .animation(.easeOut(duration: 0.16), value: hovered)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func hit(_ pt: CGPoint, side: CGFloat, thickness: CGFloat) -> Int? {
        let dx = Double(pt.x - side / 2), dy = Double(pt.y - side / 2)
        let r = (dx * dx + dy * dy).squareRoot()
        let outer = Double(side / 2)
        let inner = outer - Double(inset) - Double(thickness)
        guard r >= inner, r <= outer else { return nil }
        var f = (atan2(dy, dx) + .pi / 2) / (2 * .pi)
        if f < 0 { f += 1 }
        return slices.first(where: { f >= $0.start && f < $0.end })?.id
    }
}

// MARK: - Map tab (donut + ranked list of the current folder)

struct MapTab: View {
    @ObservedObject var session: ScanSession
    var focus: FileNode
    var showHidden: Bool
    @State private var hovered: Int?

    private let maxSlices = 9

    /// Children to list, plus the size of anything folded away by the hidden toggle.
    private var listing: (items: [FileNode], foldedBytes: Int64, foldedCount: Int) {
        if showHidden { return (focus.children, 0, 0) }
        var items: [FileNode] = []
        var bytes: Int64 = 0
        var count = 0
        for c in focus.children {
            if c.isHidden { bytes += c.size; count += 1 } else { items.append(c) }
        }
        return (items, bytes, count)
    }

    private func slices(_ l: (items: [FileNode], foldedBytes: Int64, foldedCount: Int)) -> [DonutSlice] {
        let total = Double(max(1, focus.size))
        var out: [DonutSlice] = []
        var cursor = 0.0
        func push(_ node: FileNode?, _ label: String, _ size: Int64, _ color: Color) {
            guard size > 0 else { return }
            let span = Double(size) / total
            out.append(DonutSlice(id: out.count, node: node, label: label, size: size, color: color,
                                  start: cursor, end: min(1, cursor + span)))
            cursor += span
        }
        var colorIndex = 0
        for c in l.items.prefix(maxSlices) {
            if c.kind == .hiddenSpace {
                push(c, c.name, c.size, Theme.hiddenSpace)
            } else {
                push(c, c.name, c.size, Theme.slice(colorIndex))
                colorIndex += 1
            }
        }
        let restItems = l.items.dropFirst(maxSlices)
        let rest = restItems.reduce(Int64(0)) { $0 + $1.size }
        push(nil, "\(Fmt.count(restItems.count)) smaller items", rest, Theme.rest)
        push(nil, "\(l.foldedCount) hidden item\(l.foldedCount == 1 ? "" : "s")", l.foldedBytes, Theme.hiddenSpace)
        return out
    }

    var body: some View {
        let l = listing
        let s = slices(l)
        VStack(alignment: .leading, spacing: 12) {
            Breadcrumbs(session: session, focus: focus)
            GeometryReader { geo in
                let wide = geo.size.width > 760
                let layout = wide ? AnyLayout(HStackLayout(spacing: 14)) : AnyLayout(VStackLayout(spacing: 14))
                layout {
                    Card {
                        DonutChart(slices: s, hovered: $hovered, onTap: { slice in
                            if let n = slice.node { session.drill(n) }
                        }) {
                            centerLabel(s)
                        }
                        .id(focus.id)
                        .transition(.scale(scale: 0.92).combined(with: .opacity))
                    }
                    .frame(width: wide ? min(460, geo.size.width * 0.44) : nil,
                           height: wide ? nil : min(320, geo.size.height * 0.5))

                    Card(padding: 8) {
                        ScrollView {
                            LazyVStack(spacing: 2) {
                                ForEach(Array(l.items.prefix(600).enumerated()), id: \.element.id) { i, node in
                                    let sliceID = sliceIndex(for: node, at: i, in: s)
                                    let rowColor: Color = s.first(where: { $0.id == sliceID })?.color ?? Theme.rest
                                    let rowHot: Bool = hovered != nil && hovered == sliceID
                                    MapRow(session: session, node: node,
                                           fraction: Double(node.size) / Double(max(1, focus.size)),
                                           color: rowColor, hot: rowHot)
                                        .onHover { inside in
                                            if inside { hovered = sliceID } else if hovered == sliceID { hovered = nil }
                                        }
                                }
                                if l.items.count > 600 {
                                    Text("…and \(Fmt.count(l.items.count - 600)) smaller items")
                                        .font(.system(size: 11)).foregroundStyle(Theme.textTertiary).padding(8)
                                }
                                if l.foldedBytes > 0 {
                                    HStack {
                                        Image(systemName: "eye.slash").foregroundStyle(Theme.textSecondary)
                                        Text("\(l.foldedCount) hidden item\(l.foldedCount == 1 ? "" : "s") folded away")
                                        Spacer()
                                        Text(Fmt.bytes(l.foldedBytes)).monospacedDigit()
                                    }
                                    .font(.system(size: 11.5)).foregroundStyle(Theme.textSecondary).padding(8)
                                }
                                if l.items.isEmpty && l.foldedBytes == 0 {
                                    Text("This folder is empty.").font(.system(size: 12))
                                        .foregroundStyle(Theme.textSecondary).padding(20)
                                }
                            }
                        }
                    }
                }
            }
        }
        // Slice numbers mean something else in the next folder; don't leave one highlighted.
        .onChange(of: focus.id) { _ in hovered = nil }
    }

    private func sliceIndex(for node: FileNode, at i: Int, in s: [DonutSlice]) -> Int? {
        if let direct = s.first(where: { $0.node === node }) { return direct.id }
        return s.first(where: { $0.node == nil })?.id
    }

    @ViewBuilder
    private func centerLabel(_ s: [DonutSlice]) -> some View {
        if let h = hovered, let slice = s.first(where: { $0.id == h }) {
            VStack(spacing: 3) {
                Text(slice.label).font(.system(size: 12, weight: .semibold)).foregroundStyle(slice.color == Theme.rest || slice.color == Theme.hiddenSpace ? Color.white : slice.color)
                    .lineLimit(2).multilineTextAlignment(.center)
                Text(Fmt.bytes(slice.size))
                    .font(.system(size: 26, weight: .bold, design: .rounded)).monospacedDigit()
                    .minimumScaleFactor(0.6).lineLimit(1)
                Text(Fmt.pct(Double(slice.size) / Double(max(1, focus.size))) + " of this folder")
                    .font(.system(size: 11)).foregroundStyle(Theme.textSecondary)
            }
        } else {
            VStack(spacing: 3) {
                Text(focus.name).font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.textSecondary)
                    .lineLimit(2).multilineTextAlignment(.center)
                Text(Fmt.bytes(focus.size))
                    .font(.system(size: 30, weight: .bold, design: .rounded)).monospacedDigit()
                    .minimumScaleFactor(0.6).lineLimit(1)
                Text("\(Fmt.count(focus.fileCount)) files")
                    .font(.system(size: 11)).foregroundStyle(Theme.textSecondary)
            }
        }
    }
}

struct MapRow: View {
    @ObservedObject var session: ScanSession
    var node: FileNode
    var fraction: Double
    var color: Color
    var hot: Bool
    @State private var hover = false

    var body: some View {
        HStack(spacing: 9) {
            Circle().fill(color).frame(width: 8, height: 8)
            NodeIcon(node: node)
            HStack(spacing: 6) {
                Text(node.name).font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(node.isHidden ? Color.white.opacity(0.7) : Color.white)
                    .lineLimit(1).truncationMode(.middle)
                if node.isHidden {
                    Image(systemName: "eye.slash.fill").font(.system(size: 9))
                        .foregroundStyle(Theme.textTertiary)
                        .help("Hidden in Finder")
                }
                if node.unreadable {
                    Image(systemName: "lock.fill").font(.system(size: 9)).foregroundStyle(Theme.warn)
                        .help("Stowmap wasn't allowed to read this folder")
                }
            }
            Spacer(minLength: 6)
            MeterBar(fraction: fraction, color: color, height: 4).frame(width: 80)
            Text(Fmt.bytes(node.size)).font(.system(size: 12.5, weight: .semibold, design: .rounded))
                .monospacedDigit().lineLimit(1).frame(width: 74, alignment: .trailing)
            Text(Fmt.pct(fraction)).font(.system(size: 11, design: .rounded)).monospacedDigit()
                .foregroundStyle(Theme.textSecondary).frame(width: 40, alignment: .trailing)
            rowActions.frame(width: 53, alignment: .trailing)
            Image(systemName: "chevron.right").font(.system(size: 10, weight: .bold))
                .foregroundStyle(Theme.textTertiary).opacity(node.canDrill ? 1 : 0)
        }
        .padding(.horizontal, 10).padding(.vertical, 8)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous)
            .fill(Color.white.opacity(hot || hover ? 0.08 : 0.0001)))
        .contentShape(Rectangle())
        .onHover { hover = $0 }
        .onTapGesture { session.drill(node) }
        .nodeMenu(session, node)
    }

    @ViewBuilder
    private var rowActions: some View {
        if node.kind == .hiddenSpace {
            let network = session.volume.kind == .network
            IconButton(symbol: "questionmark", help: network
                ? "Space the server counts as used that isn't in this share: other shared folders on the same storage, snapshots, recycle bins and system data. Scan the other shares to see them."
                : "Snapshots, purgeable data and protected system files that macOS counts as used but doesn't show to apps. Full Disk Access can shrink this.") {
                if !network { Finder.openFullDiskAccessSettings() }
            }
        } else {
            NodeActions(session: session, node: node, showCollect: hot || hover)
        }
    }
}

struct Breadcrumbs: View {
    @ObservedObject var session: ScanSession
    var focus: FileNode

    var body: some View {
        let chain = focus.ancestry
        HStack(spacing: 8) {
            IconButton(symbol: "chevron.up", help: "Enclosing folder (⌘↑)") { session.goUp() }
                .disabled(focus.parent == nil).opacity(focus.parent == nil ? 0.4 : 1)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 4) {
                    ForEach(Array(chain.enumerated()), id: \.element.id) { i, node in
                        if i > 0 {
                            Image(systemName: "chevron.right").font(.system(size: 8, weight: .bold))
                                .foregroundStyle(Theme.textTertiary)
                        }
                        Button { session.drill(node) } label: {
                            Text(node.name)
                                .font(.system(size: 12, weight: node === focus ? .bold : .medium))
                                .foregroundStyle(node === focus ? Color.white : Theme.textSecondary)
                                .lineLimit(1)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            IconButton(symbol: "folder", help: "Open this folder in Finder") { Finder.open(focus.path) }
        }
    }
}

// MARK: - Tree tab (whole hierarchy, expandable, searchable)

private struct TreeRow: Identifiable {
    let node: FileNode
    let depth: Int
    let parentSize: Int64
    var id: ObjectIdentifier { node.id }
}

struct TreeTab: View {
    @ObservedObject var session: ScanSession
    var root: FileNode
    var showHidden: Bool
    var showOnMap: () -> Void
    @State private var expanded = Set<ObjectIdentifier>()
    @State private var query = ""
    @State private var matches: [FileNode]?

    private func rows() -> [TreeRow] {
        var out: [TreeRow] = []
        func walk(_ n: FileNode, _ depth: Int) {
            var shown = 0
            for c in n.children {
                if !showHidden && c.isHidden { continue }
                if shown >= 400 { break }
                shown += 1
                out.append(TreeRow(node: c, depth: depth, parentSize: n.size))
                if expanded.contains(c.id) { walk(c, depth + 1) }
            }
        }
        walk(root, 0)
        return out
    }

    private func search() {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { matches = nil; return }
        var found: [FileNode] = []
        var stack: [FileNode] = [root]
        while let n = stack.popLast() {
            for c in n.children where c.isReal {
                if !showHidden && c.isHidden { continue }
                if c.name.range(of: q, options: [.caseInsensitive, .diacriticInsensitive]) != nil { found.append(c) }
                if c.kind == .folder { stack.append(c) }
            }
        }
        found.sort { $0.size > $1.size }
        matches = Array(found.prefix(300))
    }

    var body: some View {
        Card(padding: 8) {
            VStack(spacing: 6) {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass").font(.system(size: 11)).foregroundStyle(Theme.textSecondary)
                    TextField("Find a file or folder by name, then press Return", text: $query)
                        .textFieldStyle(.plain).font(.system(size: 12.5))
                        .onSubmit { search() }
                    if matches != nil {
                        Button("Clear") { query = ""; matches = nil }.buttonStyle(QuietButtonStyle())
                    } else {
                        Button("Collapse All") { withAnimation { expanded.removeAll() } }
                            .buttonStyle(QuietButtonStyle())
                            .disabled(expanded.isEmpty).opacity(expanded.isEmpty ? 0.4 : 1)
                    }
                }
                .padding(.horizontal, 10).padding(.vertical, 6)
                .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.white.opacity(0.05)))

                ScrollView {
                    LazyVStack(spacing: 1) {
                        if let matches {
                            if matches.isEmpty {
                                Text("Nothing in this map matches “\(query)”. Small files are grouped, so try a folder name.")
                                    .font(.system(size: 12)).foregroundStyle(Theme.textSecondary).padding(20)
                            }
                            ForEach(matches) { node in
                                TreeRowView(session: session, node: node, depth: 0,
                                            fraction: Double(node.size) / Double(max(1, root.size)),
                                            expanded: nil, subtitle: node.parent?.path) {
                                    if let p = node.parent {
                                        session.drill(p.canDrill ? p : root)
                                        showOnMap()
                                    }
                                }
                            }
                        } else {
                            ForEach(rows()) { row in
                                TreeRowView(session: session, node: row.node, depth: row.depth,
                                            fraction: Double(row.node.size) / Double(max(1, row.parentSize)),
                                            expanded: row.node.canDrill ? expanded.contains(row.id) : nil,
                                            subtitle: nil) {
                                    guard row.node.canDrill else { return }
                                    withAnimation(.easeOut(duration: 0.15)) {
                                        if expanded.contains(row.id) { expanded.remove(row.id) } else { expanded.insert(row.id) }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}

private struct TreeRowView: View {
    @ObservedObject var session: ScanSession
    var node: FileNode
    var depth: Int
    var fraction: Double
    var expanded: Bool?          // nil = not expandable
    var subtitle: String?
    var onTap: () -> Void
    @State private var hover = false

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "chevron.right").font(.system(size: 9, weight: .bold))
                .foregroundStyle(Theme.textSecondary)
                .rotationEffect(.degrees(expanded == true ? 90 : 0))
                .opacity(expanded == nil ? 0 : 1)
                .frame(width: 12)
            NodeIcon(node: node)
            VStack(alignment: .leading, spacing: 1) {
                Text(node.name).font(.system(size: 12.5, weight: node.isFolder ? .semibold : .regular))
                    .foregroundStyle(node.isHidden ? Color.white.opacity(0.65) : Color.white)
                    .lineLimit(1).truncationMode(.middle)
                if let subtitle {
                    Text(subtitle).font(.system(size: 10)).foregroundStyle(Theme.textTertiary)
                        .lineLimit(1).truncationMode(.head)
                }
            }
            Spacer(minLength: 8)
            MeterBar(fraction: fraction, color: node.isFolder ? Theme.cyan : Theme.lilac, height: 4)
                .frame(width: 90)
            Text(Fmt.pct(fraction)).font(.system(size: 11, design: .rounded)).monospacedDigit()
                .foregroundStyle(Theme.textSecondary).frame(width: 42, alignment: .trailing)
            Text(Fmt.bytes(node.size)).font(.system(size: 12.5, weight: .semibold, design: .rounded))
                .monospacedDigit().frame(width: 78, alignment: .trailing)
            if node.kind == .hiddenSpace {
                Color.clear.frame(width: 53, height: 24)
            } else {
                NodeActions(session: session, node: node, showCollect: hover).frame(width: 53, alignment: .trailing)
            }
        }
        .padding(.leading, 8 + CGFloat(depth) * 18).padding(.trailing, 10).padding(.vertical, 5)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous)
            .fill(Color.white.opacity(hover ? 0.07 : 0.0001)))
        .contentShape(Rectangle())
        .onHover { hover = $0 }
        .onTapGesture(perform: onTap)
        .nodeMenu(session, node)
    }
}

// MARK: - File types tab

struct TypesTab: View {
    var result: ScanResult
    @State private var hovered: Int?

    private func makeSlices(_ cats: [(category: FileCategory, bytes: Int64, count: Int)],
                            total: Int64) -> [DonutSlice] {
        var out: [DonutSlice] = []
        var cursor = 0.0
        for c in cats where c.bytes > 0 {
            let span = Double(c.bytes) / Double(total)
            out.append(DonutSlice(id: out.count, node: nil, label: c.category.title, size: c.bytes,
                                  color: Theme.category(c.category), start: cursor, end: min(1, cursor + span)))
            cursor += span
        }
        return out
    }

    var body: some View {
        let cats = result.categories
        let catBytes: Int64 = cats.reduce(Int64(0)) { $0 + $1.bytes }
        let total: Int64 = max(1, catBytes)
        let slices: [DonutSlice] = makeSlices(cats, total: total)
        let hotTitle: String? = slices.first(where: { $0.id == hovered })?.label
        let topBytes: Int64 = max(1, result.types.first?.bytes ?? 1)

        GeometryReader { geo in
            let wide = geo.size.width > 760
            let layout = wide ? AnyLayout(HStackLayout(spacing: 14)) : AnyLayout(VStackLayout(spacing: 14))
            layout {
                Card {
                    VStack(spacing: 12) {
                        DonutChart(slices: slices, hovered: $hovered, onTap: { _ in }) {
                            if let h = hovered, let s = slices.first(where: { $0.id == h }) {
                                VStack(spacing: 3) {
                                    Text(s.label).font(.system(size: 12, weight: .semibold))
                                        .multilineTextAlignment(.center).lineLimit(2)
                                    Text(Fmt.bytes(s.size)).font(.system(size: 26, weight: .bold, design: .rounded))
                                        .monospacedDigit().minimumScaleFactor(0.6).lineLimit(1)
                                    Text(Fmt.pct(Double(s.size) / Double(total)))
                                        .font(.system(size: 11)).foregroundStyle(Theme.textSecondary)
                                }
                            } else {
                                VStack(spacing: 3) {
                                    Text("All files").font(.system(size: 12, weight: .semibold))
                                        .foregroundStyle(Theme.textSecondary)
                                    Text(Fmt.bytes(total)).font(.system(size: 28, weight: .bold, design: .rounded))
                                        .monospacedDigit().minimumScaleFactor(0.6).lineLimit(1)
                                    Text("\(result.types.count) file types")
                                        .font(.system(size: 11)).foregroundStyle(Theme.textSecondary)
                                }
                            }
                        }
                        VStack(spacing: 5) {
                            ForEach(Array(cats.enumerated()), id: \.element.category) { i, c in
                                HStack(spacing: 7) {
                                    Circle().fill(Theme.category(c.category)).frame(width: 7, height: 7)
                                    Image(systemName: c.category.symbol).font(.system(size: 10))
                                        .foregroundStyle(Theme.textSecondary).frame(width: 14)
                                    Text(c.category.title).font(.system(size: 11.5))
                                    Spacer(minLength: 4)
                                    Text("\(Fmt.count(c.count)) files").font(.system(size: 10.5))
                                        .foregroundStyle(Theme.textTertiary).monospacedDigit()
                                    Text(Fmt.bytes(c.bytes)).font(.system(size: 11.5, weight: .semibold, design: .rounded))
                                        .monospacedDigit().frame(width: 72, alignment: .trailing)
                                }
                                .opacity(hotTitle == nil || hotTitle == c.category.title ? 1 : 0.45)
                            }
                        }
                    }
                }
                .frame(width: wide ? min(440, geo.size.width * 0.42) : nil)

                Card(padding: 8) {
                    VStack(alignment: .leading, spacing: 4) {
                        CardTitle(text: "By extension", symbol: "number").padding(.horizontal, 8).padding(.top, 6)
                        ScrollView {
                            LazyVStack(spacing: 1) {
                                ForEach(result.types.prefix(150)) { t in
                                    HStack(spacing: 10) {
                                        Circle().fill(Theme.category(t.category)).frame(width: 7, height: 7)
                                        Text(t.label).font(.system(size: 12.5, weight: .semibold, design: .monospaced))
                                            .frame(width: 110, alignment: .leading).lineLimit(1)
                                        Text(t.category.title).font(.system(size: 11)).foregroundStyle(Theme.textSecondary)
                                            .frame(width: 130, alignment: .leading).lineLimit(1)
                                        MeterBar(fraction: Double(t.bytes) / Double(topBytes),
                                                 color: Theme.category(t.category), height: 4)
                                        Text(Fmt.count(t.count)).font(.system(size: 11, design: .rounded)).monospacedDigit()
                                            .foregroundStyle(Theme.textSecondary).frame(width: 56, alignment: .trailing)
                                        Text(Fmt.bytes(t.bytes)).font(.system(size: 12.5, weight: .semibold, design: .rounded))
                                            .monospacedDigit().frame(width: 78, alignment: .trailing)
                                    }
                                    .padding(.horizontal, 10).padding(.vertical, 6)
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Largest files tab

struct LargestTab: View {
    @ObservedObject var session: ScanSession
    var files: [LargeFile]
    var showOnMap: () -> Void
    @State private var query = ""

    private var filtered: [LargeFile] {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return files }
        return files.filter { $0.path.range(of: q, options: [.caseInsensitive, .diacriticInsensitive]) != nil }
    }

    var body: some View {
        let list = filtered
        let listBytes: Int64 = list.reduce(Int64(0)) { $0 + $1.size }
        let top: Int64 = max(1, files.first?.size ?? 1)
        Card(padding: 8) {
            VStack(spacing: 6) {
                HStack(spacing: 8) {
                    Image(systemName: "line.3.horizontal.decrease").font(.system(size: 11))
                        .foregroundStyle(Theme.textSecondary)
                    TextField("Filter by name, folder or extension", text: $query)
                        .textFieldStyle(.plain).font(.system(size: 12.5))
                    Text("\(list.count) files  ·  \(Fmt.bytes(listBytes))")
                        .font(.system(size: 11, design: .rounded)).monospacedDigit().foregroundStyle(Theme.textSecondary)
                }
                .padding(.horizontal, 10).padding(.vertical, 8)
                .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.white.opacity(0.05)))

                ScrollView {
                    LazyVStack(spacing: 1) {
                        ForEach(Array(list.enumerated()), id: \.element.id) { i, f in
                            LargeFileRow(file: f, rank: i + 1, fraction: Double(f.size) / Double(top)) {
                                session.show(path: f.folder)
                                showOnMap()
                            }
                        }
                        if list.isEmpty {
                            Text("No large files match.").font(.system(size: 12))
                                .foregroundStyle(Theme.textSecondary).padding(20)
                        }
                    }
                }
            }
        }
    }
}

private struct LargeFileRow: View {
    var file: LargeFile
    var rank: Int
    var fraction: Double
    var showOnMap: () -> Void
    @State private var hover = false

    var body: some View {
        let cat = FileTypes.category(for: FileTypes.ext(of: file.name))
        HStack(spacing: 10) {
            Text("\(rank)").font(.system(size: 10.5, weight: .semibold, design: .rounded)).monospacedDigit()
                .foregroundStyle(Theme.textTertiary).frame(width: 26, alignment: .trailing)
            Image(systemName: cat.symbol).font(.system(size: 12)).foregroundStyle(Theme.category(cat)).frame(width: 18)
            VStack(alignment: .leading, spacing: 1) {
                Text(file.name).font(.system(size: 12.5, weight: .semibold)).lineLimit(1).truncationMode(.middle)
                Text(file.folder).font(.system(size: 10)).foregroundStyle(Theme.textTertiary)
                    .lineLimit(1).truncationMode(.head)
            }
            Spacer(minLength: 8)
            MeterBar(fraction: fraction, color: Theme.category(cat), height: 4).frame(width: 90)
            Text(Fmt.bytes(file.size)).font(.system(size: 12.5, weight: .semibold, design: .rounded))
                .monospacedDigit().frame(width: 78, alignment: .trailing)
            IconButton(symbol: "chart.pie", help: "Show its folder on the map", action: showOnMap)
            IconButton(symbol: "eye", help: "Quick Look") { Finder.quickLook(file.path) }
            IconButton(symbol: "magnifyingglass", help: "Reveal in Finder") { Finder.reveal(file.path) }
        }
        .padding(.horizontal, 8).padding(.vertical, 5)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous)
            .fill(Color.white.opacity(hover ? 0.07 : 0.0001)))
        .onHover { hover = $0 }
        .contextMenu {
            Button("Reveal in Finder") { Finder.reveal(file.path) }
            Button("Quick Look") { Finder.quickLook(file.path) }
            Button("Copy Path") { Finder.copyPath(file.path) }
        }
    }
}
