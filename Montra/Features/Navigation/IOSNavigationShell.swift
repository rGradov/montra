#if os(iOS)
import SwiftUI
import UIKit

/// One header host per tab. Each tab has its own page header, so switching tabs
/// never shows the previous tab's title, and a pushed account page writes into
/// the same host as the Overview it belongs to.
@MainActor
final class TabHeaderStore: ObservableObject {
    private let hosts: [AppTab: DetailHeaderHost]

    init() {
        hosts = Dictionary(uniqueKeysWithValues: AppTab.allCases.map { ($0, DetailHeaderHost()) })
    }

    func host(for tab: AppTab) -> DetailHeaderHost {
        hosts[tab] ?? DetailHeaderHost()
    }
}

/// Renders one page header from the screen's shared host.
///
/// The screens own the header content and keep the Mac's "back to Overview" row
/// on Operations. At a bottom-menu root that row would be a dead end, so it is
/// dropped there; a pushed page keeps it and it pops the stack, as expected.
private struct DockedHeader: View {
    let source: DetailHeaderHost
    let showsBack: Bool

    /// The header draws from its own host: a pushed page's title must not leak
    /// back into the tab root's header when the page is popped.
    @StateObject private var display = DetailHeaderHost()

    var body: some View {
        SharedDetailHeader(host: display)
            .onAppear { forward(source.config) }
            .onReceive(source.$config) { forward($0) }
    }

    private func forward(_ config: DetailHeaderConfig) {
        var next = config
        if !showsBack {
            next.backTitle = nil
            next.onBack = nil
        }
        display.config = next
    }
}

/// The iOS/iPadOS shell: five roots behind one bottom menu.
///
/// iPhone gets the system `TabView` and its Liquid Glass bar. iPadOS has no
/// system bottom tab bar (the system puts the bar at the top, and
/// `AdaptableTabBarPlacement` has no bottom case), so iPad gets the same five
/// destinations behind a custom bottom bar built from `GlassEffectContainer` and
/// `glassEffect`, mounted with `safeAreaInset` so content scrolls under it.
struct IOSNavigationShell: View {
    @ObservedObject var app: AppModel
    let rootContent: (AppTab) -> AnyView
    let destinationContent: (Route) -> AnyView

    @StateObject private var headers = TabHeaderStore()
    /// iPad keeps every visited tab mounted, like a real tab bar does, so a
    /// screen keeps its scroll position and its own stack.
    @State private var visitedTabs: Set<AppTab>
    @Environment(\.openWindow) private var openWindow

    init(
        app: AppModel,
        rootContent: @escaping (AppTab) -> AnyView,
        destinationContent: @escaping (Route) -> AnyView
    ) {
        _app = ObservedObject(wrappedValue: app)
        self.rootContent = rootContent
        self.destinationContent = destinationContent
        _visitedTabs = State(initialValue: [app.selectedTab])
    }

    var body: some View {
        Group {
            if AppPlatform.isPad {
                padShell
            } else {
                phoneShell
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AppColors.surfaceBase)
        .onAppear { visitedTabs.insert(app.selectedTab) }
        .onChange(of: app.selectedTab) { _, tab in visitedTabs.insert(tab) }
        .task { await openQAExtraWindowIfRequested() }
        .task { applyQAOrientationIfRequested() }
    }

    /// Debug-only: proves the iPad multi-window path (`openWindow` with a tab
    /// value) and reports how many scenes share the one store. Only the first
    /// window runs it, otherwise every new window would open another.
    private func openQAExtraWindowIfRequested() async {
        #if DEBUG
        guard QAFixtures.opensExtraWindow else { return }
        enum Probe { @MainActor static var opened = false }
        guard !Probe.opened else { return }
        Probe.opened = true
        try? await Task.sleep(nanoseconds: 600_000_000)
        openWindow(id: AppSceneID.main, value: AppTab.operations)
        try? await Task.sleep(nanoseconds: 1_500_000_000)
        print("MONTRA-QA scenes=\(UIApplication.shared.connectedScenes.count)")
        #endif
    }

    /// Debug-only: a simulator has no rotation control, so rotated screenshots
    /// use the same geometry-update API an app would for a supported orientation
    /// change.
    private func applyQAOrientationIfRequested() {
        #if DEBUG
        guard let mask = QAFixtures.orientationMask,
              let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first
        else { return }
        scene.requestGeometryUpdate(.iOS(interfaceOrientations: mask)) { error in
            print("MONTRA-QA orientation request failed: \(error)")
        }
        #endif
    }

    // MARK: - iPhone

    private var phoneShell: some View {
        TabView(selection: tabSelection) {
            ForEach(AppTab.allCases) { tab in
                Tab(tab.title, systemImage: tab.symbol, value: tab) {
                    tabStack(tab)
                }
            }
        }
        .tabBarMinimizeBehavior(.onScrollDown)
    }

    private var tabSelection: Binding<AppTab> {
        Binding(
            get: { app.selectedTab },
            set: { app.selectTab($0) }
        )
    }

    // MARK: - iPad

    private var padShell: some View {
        ZStack {
            ForEach(AppTab.allCases) { tab in
                if visitedTabs.contains(tab) {
                    tabStack(tab)
                        .opacity(app.selectedTab == tab ? 1 : 0)
                        .allowsHitTesting(app.selectedTab == tab)
                        .accessibilityHidden(app.selectedTab != tab)
                        .zIndex(app.selectedTab == tab ? 1 : 0)
                }
            }
        }
        // The bar floats over the content: the inset keeps the last row clear of
        // it while lists still scroll underneath, and the hard edge effect draws
        // the boundary where content passes behind the glass.
        .safeAreaInset(edge: .bottom, spacing: 0) {
            GlassTabBar(
                selection: app.selectedTab,
                onSelect: { app.selectTab($0) },
                onOpenInNewWindow: { openWindow(id: AppSceneID.main, value: $0) }
            )
        }
        .scrollEdgeEffectStyle(.hard, for: .bottom)
    }

    // MARK: - One tab

    private func tabStack(_ tab: AppTab) -> some View {
        let header = headers.host(for: tab)
        return NavigationStack(path: pathBinding(tab)) {
            VStack(spacing: 0) {
                DockedHeader(source: header, showsBack: false)
                rootContent(tab)
                    .environmentObject(header)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(AppColors.surfaceBase)
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: Route.self) { route in
                VStack(spacing: 0) {
                    DockedHeader(source: header, showsBack: true)
                    destinationContent(route)
                        .environmentObject(header)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(AppColors.surfaceBase)
                .toolbar(.hidden, for: .navigationBar)
            }
        }
    }

    private func pathBinding(_ tab: AppTab) -> Binding<[Route]> {
        Binding(
            get: { app.path(for: tab) },
            set: { app.setPath($0, for: tab) }
        )
    }
}

// MARK: - iPad bottom bar

/// The iPad bottom menu: real Liquid Glass, one `glassEffect(.regular…)` capsule
/// per item inside a single `GlassEffectContainer`, so neighbouring glass samples
/// the same content. Never `.clear`, never glass on glass.
struct GlassTabBar: View {
    let selection: AppTab
    let onSelect: (AppTab) -> Void
    var onOpenInNewWindow: ((AppTab) -> Void)?

    @Namespace private var glassNamespace
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ScaledMetric(relativeTo: .caption2) private var scaledItemHeight: CGFloat = 44
    @ScaledMetric(relativeTo: .caption2) private var scaledItemMinWidth: CGFloat = 54
    @ScaledMetric(relativeTo: .caption2) private var scaledIconSize: CGFloat = 18
    @ScaledMetric(relativeTo: .caption2) private var scaledCaptionSize: CGFloat = 10

    /// At accessibility sizes five captions cannot share one bar at a legible
    /// size, so the bar drops to icons (as the system does) and the accessibility
    /// labels carry the names. The icon keeps its 44pt target.
    private var showsCaptions: Bool { !dynamicTypeSize.isAccessibilitySize }
    /// The bar grows with Dynamic Type up to the size where it still reads as a
    /// bar; past that the icon is what matters, and a 44pt target must survive
    /// instead of a 150pt pill.
    private var itemHeight: CGFloat { min(max(scaledItemHeight, 44), 56) }
    private var itemMinWidth: CGFloat { min(max(scaledItemMinWidth, 54), 76) }
    private var iconSize: CGFloat { min(scaledIconSize, 26) }
    private var captionSize: CGFloat { min(scaledCaptionSize, 13) }

    private var captionStyle: AppStyle.TextStyle {
        AppStyle.TextStyle(family: .onest, size: captionSize, weight: .medium, tracking: 0.3)
    }

    var body: some View {
        GlassEffectContainer(spacing: AppStyle.Spacing.xxSmall) {
            HStack(spacing: AppStyle.Spacing.xxSmall) {
                ForEach(AppTab.allCases) { tab in
                    item(tab)
                }
            }
            .padding(AppStyle.Spacing.xxSmallPlus)
        }
        .padding(.horizontal, AppStyle.Spacing.large)
        .padding(.bottom, AppStyle.Spacing.xxSmallPlus)
        .frame(maxWidth: .infinity)
    }

    private func item(_ tab: AppTab) -> some View {
        let isSelected = tab == selection

        return Button {
            onSelect(tab)
        } label: {
            VStack(spacing: AppStyle.Spacing.xxxSmall) {
                Image(systemName: isSelected ? tab.selectedSymbol : tab.symbol)
                    .font(.system(size: iconSize, weight: .medium))
                if showsCaptions {
                    Text(tab.title)
                        .font(captionStyle)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
            }
            .foregroundStyle(isSelected ? AppColors.accent : AppColors.textSecondary)
            .frame(minWidth: showsCaptions ? itemMinWidth : 46, minHeight: itemHeight)
            .padding(.horizontal, AppStyle.Spacing.xxSmall)
            .contentShape(.capsule)
        }
        .buttonStyle(.plain)
        .glassEffect(
            isSelected
                ? .regular.tint(AppColors.accent.opacity(0.16)).interactive()
                : .regular.interactive(),
            in: .capsule
        )
        .glassEffectID(tab.rawValue, in: glassNamespace)
        .hoverEffect(.automatic)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(tab.title)
        .accessibilityAddTraits(.isButton)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
        .contextMenu {
            if let onOpenInNewWindow {
                Button {
                    onOpenInNewWindow(tab)
                } label: {
                    Label(String(localized: "common.open_in_new_window"), systemImage: "macwindow.badge.plus")
                }
            }
        }
    }
}
#endif
