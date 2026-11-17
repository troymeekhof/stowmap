import SwiftUI

enum Theme {
    static let violet = Color(red: 0.55, green: 0.36, blue: 1.00)
    static let cyan = Color(red: 0.25, green: 0.85, blue: 1.00)
    static let coral = Color(red: 1.00, green: 0.45, blue: 0.40)
    static let amber = Color(red: 1.00, green: 0.78, blue: 0.30)
    static let green = Color(red: 0.35, green: 0.92, blue: 0.65)
    static let pink = Color(red: 1.00, green: 0.55, blue: 0.70)
    static let blue = Color(red: 0.30, green: 0.75, blue: 1.00)
    static let lilac = Color(red: 0.70, green: 0.50, blue: 1.00)
    static let yellow = Color(red: 1.00, green: 0.85, blue: 0.30)
    static let mint = Color(red: 0.45, green: 0.95, blue: 0.70)

    /// Slice colours, largest item first.
    static let slices: [Color] = [violet, cyan, coral, amber, green, pink, blue, lilac, yellow, mint]
    static let rest = Color.white.opacity(0.22)
    static let hiddenSpace = Color.white.opacity(0.12)

    static let good = Color(red: 0.35, green: 0.90, blue: 0.60)
    static let warn = Color(red: 1.00, green: 0.75, blue: 0.25)
    static let bad = Color(red: 1.00, green: 0.40, blue: 0.40)

    static let brand = LinearGradient(colors: [violet, cyan], startPoint: .topLeading, endPoint: .bottomTrailing)

    static let windowBackground = LinearGradient(
        colors: [Color(red: 0.07, green: 0.07, blue: 0.10), Color(red: 0.03, green: 0.03, blue: 0.05)],
        startPoint: .top, endPoint: .bottom)

    static let card = Color.white.opacity(0.06)
    static let cardStroke = Color.white.opacity(0.10)
    static let textSecondary = Color.white.opacity(0.55)
    static let textTertiary = Color.white.opacity(0.35)

    static func slice(_ i: Int) -> Color { i < slices.count ? slices[i] : rest }

    static func usage(_ fraction: Double) -> Color {
        fraction > 0.92 ? bad : (fraction > 0.82 ? warn : cyan)
    }

    static func category(_ c: FileCategory) -> Color {
        switch c {
        case .video: return violet
        case .images: return cyan
        case .audio: return pink
        case .documents: return amber
        case .code: return green
        case .archives: return coral
        case .apps: return blue
        case .system: return lilac
        case .other: return rest
        }
    }
}

// MARK: - Card container

struct Card<Content: View>: View {
    var padding: CGFloat = 16
    @ViewBuilder var content: () -> Content
    var body: some View {
        content()
            .padding(padding)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Theme.card)
                    .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(Theme.cardStroke, lineWidth: 1))
            )
    }
}

struct CardTitle: View {
    var text: String
    var symbol: String
    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: symbol).font(.system(size: 11, weight: .semibold)).foregroundStyle(Theme.textSecondary)
            Text(text).font(.system(size: 11, weight: .semibold)).foregroundStyle(Theme.textSecondary)
                .textCase(.uppercase)
        }
    }
}

struct Pill: View {
    var text: String
    var color: Color
    var body: some View {
        HStack(spacing: 5) {
            Circle().fill(color).frame(width: 6, height: 6).shadow(color: color, radius: 4)
            Text(text).font(.system(size: 10.5, weight: .semibold)).lineLimit(1)
        }
        .padding(.horizontal, 9).padding(.vertical, 5)
        .background(Capsule().fill(color.opacity(0.15)))
        .foregroundStyle(color)
    }
}

/// One label/value line in a facts list.
struct FactRow: View {
    var label: String
    var value: String
    var body: some View {
        HStack(spacing: 12) {
            Text(label).foregroundStyle(Theme.textSecondary)
            Spacer(minLength: 0)
            Text(value).fontWeight(.semibold).monospacedDigit().lineLimit(1).truncationMode(.middle)
        }
        .font(.system(size: 12.5))
        .padding(.horizontal, 10).padding(.vertical, 8)
    }
}

/// Two cards side by side (stacked when the window is narrow): a hero on the left, detail on the right.
struct SplitPanel<Left: View, Right: View>: View {
    @ViewBuilder var left: () -> Left
    @ViewBuilder var right: () -> Right

    var body: some View {
        GeometryReader { geo in
            let wide = geo.size.width > 760
            let layout = wide ? AnyLayout(HStackLayout(spacing: 14)) : AnyLayout(VStackLayout(spacing: 14))
            layout {
                Card(padding: 24) {
                    left().frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .frame(width: wide ? min(460, geo.size.width * 0.44) : nil)
                Card(padding: 8) {
                    right().frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                }
            }
        }
    }
}

struct Stat: View {
    var label: String
    var value: String
    var color: Color? = nil
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.system(size: 10, weight: .medium)).foregroundStyle(Theme.textSecondary)
                .textCase(.uppercase)
            Text(value).font(.system(size: 14, weight: .semibold, design: .rounded)).monospacedDigit()
                .foregroundStyle(color ?? .white)
        }
    }
}

/// Thin capsule progress bar.
struct MeterBar: View {
    var fraction: Double
    var color: Color
    var height: CGFloat = 4
    var body: some View {
        GeometryReader { g in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.08))
                Capsule().fill(color)
                    .frame(width: max(height, g.size.width * CGFloat(min(1, max(0, fraction)))))
            }
        }
        .frame(height: height)
    }
}

// MARK: - Buttons

struct GlowButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 18).padding(.vertical, 9)
            .background(Capsule().fill(Theme.brand))
            .shadow(color: Theme.violet.opacity(0.45), radius: configuration.isPressed ? 4 : 12, y: 3)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}

struct QuietButtonStyle: ButtonStyle {
    var tint: Color = .white
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(tint)
            .padding(.horizontal, 12).padding(.vertical, 6)
            .background(Capsule().fill(tint.opacity(configuration.isPressed ? 0.22 : 0.10)))
            .overlay(Capsule().strokeBorder(tint.opacity(0.14), lineWidth: 1))
    }
}

/// Small round icon button used on rows.
struct IconButton: View {
    var symbol: String
    var help: String
    var tint: Color = Theme.textSecondary
    var action: () -> Void
    @State private var hover = false
    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(hover ? Color.white : tint)
                .frame(width: 24, height: 24)
                .background(Circle().fill(Color.white.opacity(hover ? 0.16 : 0.06)))
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
        .help(help)
    }
}

// MARK: - Tab switcher (Liquid Glass capsule on macOS 26+, frosted material before that)

struct GlassTabs: View {
    @Binding var selection: Int
    let tabs: [(title: String, icon: String)]
    @Namespace private var ns

    var body: some View {
        HStack(spacing: 0) {
            ForEach(tabs.indices, id: \.self) { i in segment(i) }
        }
        .padding(4)
        .modifier(GlassCapsule(tint: nil, interactive: false))
    }

    private func segment(_ i: Int) -> some View {
        let selected = selection == i
        return Button {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) { selection = i }
        } label: {
            Label(tabs[i].title, systemImage: tabs[i].icon)
                .font(.system(size: 12.5, weight: .semibold))
                .foregroundStyle(selected ? Color.white : Theme.textSecondary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 7)
                .background {
                    if selected {
                        Capsule().fill(Color.white.opacity(0.08))
                            .modifier(GlassCapsule(tint: Theme.cyan.opacity(0.35), interactive: true))
                            .matchedGeometryEffect(id: "thumb", in: ns)
                    }
                }
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

private struct GlassCapsule: ViewModifier {
    var tint: Color?
    var interactive: Bool

    func body(content: Content) -> some View {
        #if compiler(>=6.2)
        if #available(macOS 26, *) {
            content.glassEffect(glass, in: .capsule)
        } else {
            fallback(content)
        }
        #else
        fallback(content)
        #endif
    }

    private func fallback(_ content: Content) -> some View {
        content.background {
            Capsule().fill(tint ?? Color.white.opacity(0.06))
                .background(.ultraThinMaterial, in: Capsule())
                .overlay(Capsule().stroke(Theme.cardStroke, lineWidth: 0.5))
        }
    }

    #if compiler(>=6.2)
    @available(macOS 26, *)
    private var glass: Glass {
        var g = Glass.regular
        if let tint { g = g.tint(tint) }
        return interactive ? g.interactive() : g
    }
    #endif
}

// MARK: - Node visuals shared by every tab

struct NodeIcon: View {
    var node: FileNode
    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(tint)
            .frame(width: 18)
    }

    private var symbol: String {
        switch node.kind {
        case .folder: return node.unreadable ? "lock.fill" : (node.isHidden ? "folder.badge.gearshape" : "folder.fill")
        case .file: return FileTypes.category(for: node.ext).symbol
        case .smallFiles: return "doc.on.doc"
        case .hiddenSpace: return node.linkedVolumeID != nil ? "externaldrive.connected.to.line.below.fill" : "eye.slash"
        }
    }

    private var tint: Color {
        switch node.kind {
        case .folder: return node.isHidden ? Theme.textSecondary : Theme.blue
        case .file: return Theme.category(FileTypes.category(for: node.ext))
        default: return Theme.textSecondary
        }
    }
}

/// Finder / Quick Look / collector actions for a row, as buttons.
struct NodeActions: View {
    @ObservedObject var session: ScanSession
    var node: FileNode
    var showCollect: Bool = true     // the collector button rests hidden until the row is hovered

    var body: some View {
        HStack(spacing: 5) {
            if node.isReal && node.parent != nil {
                let on = session.isCollected(node)
                IconButton(symbol: on ? "tray.full.fill" : "tray.and.arrow.down",
                           help: on ? "Remove from Collector" : "Add to Collector",
                           tint: on ? Theme.amber : Theme.textSecondary) {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { session.toggleCollect(node) }
                }
                .opacity(showCollect || on ? 1 : 0)
            }
            IconButton(symbol: node.kind == .file ? "magnifyingglass" : "folder",
                       help: node.kind == .file ? "Reveal in Finder" : "Open in Finder") {
                Finder.show(node)
            }
        }
    }
}

struct NodeMenu: ViewModifier {
    @ObservedObject var session: ScanSession
    var node: FileNode

    func body(content: Content) -> some View {
        content.contextMenu {
            if node.kind == .hiddenSpace {
                if node.linkedVolumeID != nil {
                    Text("Another share on the same server")
                } else if session.volume.kind == .network {
                    Text("Unscanned shares, snapshots and system data on the server")
                } else {
                    Button("Open Full Disk Access Settings…") { Finder.openFullDiskAccessSettings() }
                }
            } else {
                Button(node.kind == .file ? "Reveal in Finder" : "Open in Finder") { Finder.show(node) }
                if node.kind == .folder {
                    Button("Reveal in Enclosing Folder") { Finder.reveal(node.path) }
                    Button("Open in Terminal") { Finder.openTerminal(node.path) }
                }
                if node.isReal { Button("Quick Look") { Finder.quickLook(node.path) } }
                Button("Copy Path") { Finder.copyPath(node.path) }
                if node.isReal && node.parent != nil {
                    Divider()
                    Button(session.isCollected(node) ? "Remove from Collector" : "Add to Collector") {
                        session.toggleCollect(node)
                    }
                }
            }
        }
    }
}

extension View {
    func nodeMenu(_ session: ScanSession, _ node: FileNode) -> some View {
        modifier(NodeMenu(session: session, node: node))
    }
}
