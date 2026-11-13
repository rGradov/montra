#if os(macOS)
import AppKit
import SwiftUI

/// Geometry of the account strip. The app area of a MacBook Pro Touch Bar is
/// only about 685 pt wide, so the account strip can never just ask for its
/// natural width: the buttons need theirs first, and an item that does not fit
/// is laid out at a negative x instead of shrinking. Everything here is pure so
/// `-selftest` can pin the arithmetic that keeps the strip on screen.
enum TouchBarLayout {
    /// Width of one account cell: a long name like "Long-term Savings" still fits.
    static let accountWidth: CGFloat = 118
    static let accountSpacing: CGFloat = 6
    static let height: CGFloat = 30
    /// Space the system puts between two Touch Bar items.
    static let itemGap: CGFloat = 8
    /// Past three cells the strip scrolls instead of eating the whole bar.
    static let maxVisibleAccounts = 3
    static let minimumStripWidth = accountWidth
    /// Used before the bar has been laid out. Narrower than a real app area on
    /// purpose: an over-wide item is invisible, an under-wide one only scrolls.
    static let unresolvedAppWidth: CGFloat = 600
    static let minimumAppWidth: CGFloat = 200

    /// Width for `accountCount` cells, clamped to the room the buttons left.
    static func stripWidth(accountCount: Int, available: CGFloat) -> CGFloat {
        let visible = max(1, min(accountCount, maxVisibleAccounts))
        let natural = CGFloat(visible) * accountWidth + CGFloat(max(0, visible - 1)) * accountSpacing
        guard available > 0 else { return natural }
        return max(minimumStripWidth, min(natural, available))
    }
}

/// Owns the window's Touch Bar.
///
/// SwiftUI's `.touchBar` handed every item to the system and let it lay them out
/// blindly: with a 685 pt app area the three buttons took 394 pt and the 366 pt
/// account strip was pushed off the bar, so only the buttons ever appeared. An
/// `NSTouchBar` lets the strip measure the room the buttons left and ask for a
/// width that fits — and it keeps every account, savings included, reachable
/// with a swipe.
@MainActor
final class MontraTouchBarController: NSObject, NSTouchBarDelegate, NSScrubberDataSource, NSScrubberDelegate {
    struct Account: Equatable, Identifiable {
        let id: UUID
        let name: String
        let iconName: String
        /// Savings accounts follow the regular ones, as they do in the sidebar.
        let isSavings: Bool
    }

    struct Actions {
        var openOverview: () -> Void = {}
        var openAnalytics: () -> Void = {}
        var newOperation: () -> Void = {}
        var openAccount: (UUID) -> Void = { _ in }
    }

    static let accountsIdentifier = NSTouchBarItem.Identifier("montra.touchbar.accounts")
    private enum ItemID {
        static let overview = NSTouchBarItem.Identifier("montra.touchbar.overview")
        static let analytics = NSTouchBarItem.Identifier("montra.touchbar.analytics")
        static let newOperation = NSTouchBarItem.Identifier("montra.touchbar.newOperation")
        static let navigation = [overview, analytics, newOperation]
    }

    private(set) var accounts: [Account] = []
    private(set) var route: Route = .overview
    private(set) var isEnabled = false
    private var actions = Actions()
    private weak var window: NSWindow?
    private var stripWidth: NSLayoutConstraint?
    private var visibility: NSKeyValueObservation?
    private var retries = 0

    private(set) lazy var bar: NSTouchBar = {
        let bar = NSTouchBar()
        bar.delegate = self
        bar.defaultItemIdentifiers = itemIdentifiers
        return bar
    }()

    /// The strip is ordered like the sidebar: regular accounts first, then the
    /// savings ones, each group in its stored order.
    static func ordered(_ accounts: [Account]) -> [Account] {
        accounts.enumerated()
            .sorted { lhs, rhs in
                if lhs.element.isSavings != rhs.element.isSavings { return !lhs.element.isSavings }
                return lhs.offset < rhs.offset
            }
            .map(\.element)
    }

    func update(accounts: [Account], route: Route, isEnabled: Bool, actions: Actions) {
        self.route = route
        self.isEnabled = isEnabled
        self.actions = actions

        let ordered = Self.ordered(accounts)
        if ordered != self.accounts {
            self.accounts = ordered
            bar.defaultItemIdentifiers = itemIdentifiers
            accountsScrubber?.reloadData()
        }

        refreshSelection()
        applyStripWidth()
    }

    /// Attaching is idempotent: SwiftUI calls it on every update and on the
    /// first layout, when the hosting view finally has a window.
    func attach(to window: NSWindow?) {
        guard let window else { return }
        self.window = window
        let wanted: NSTouchBar? = isEnabled ? bar : nil
        if window.touchBar !== wanted { window.touchBar = wanted }
        observeVisibility()
        if isEnabled { applyStripWidth() }
    }

    /// The bar is laid out only once the window is key, which can happen long
    /// after the first update — for example when the app starts in the
    /// background. Its item views keep their un-styled sizes until then, so the
    /// width has to be measured again on every appearance.
    private func observeVisibility() {
        guard visibility == nil else { return }
        visibility = bar.observe(\.isVisible, options: [.initial, .new]) { [weak self] bar, _ in
            guard bar.isVisible else { return }
            Task { @MainActor in self?.applyStripWidth() }
        }
    }

    // MARK: - Items

    private var itemIdentifiers: [NSTouchBarItem.Identifier] {
        var identifiers: [NSTouchBarItem.Identifier] = [ItemID.overview, ItemID.analytics]
        if !accounts.isEmpty { identifiers.append(Self.accountsIdentifier) }
        identifiers.append(ItemID.newOperation)
        return identifiers
    }

    func touchBar(_ touchBar: NSTouchBar, makeItemForIdentifier identifier: NSTouchBarItem.Identifier) -> NSTouchBarItem? {
        switch identifier {
        case ItemID.overview:
            return navigationItem(
                identifier,
                title: String(localized: "navigation.overview"),
                symbol: "square.grid.2x2",
                selectedSymbol: "square.grid.2x2.fill",
                selected: route == .overview,
                action: #selector(openOverview)
            )
        case ItemID.analytics:
            return navigationItem(
                identifier,
                title: String(localized: "navigation.analytics"),
                symbol: "chart.bar",
                selectedSymbol: "chart.bar.fill",
                selected: route == .analytics,
                action: #selector(openAnalytics)
            )
        case ItemID.newOperation:
            // The label is dropped on purpose: a bare plus is the Touch Bar way
            // to add, and those ~90 pt are what let all three accounts fit.
            let title = String(localized: "transaction.new")
            let item = NSButtonTouchBarItem(
                identifier: identifier,
                image: symbolImage("plus", description: title),
                target: self,
                action: #selector(startOperation)
            )
            item.customizationLabel = title
            return item
        case Self.accountsIdentifier:
            return accountsItem()
        default:
            return nil
        }
    }

    private func navigationItem(
        _ identifier: NSTouchBarItem.Identifier,
        title: String,
        symbol: String,
        selectedSymbol: String,
        selected: Bool,
        action: Selector
    ) -> NSButtonTouchBarItem {
        let item = NSButtonTouchBarItem(
            identifier: identifier,
            title: title,
            image: symbolImage(selected ? selectedSymbol : symbol, description: title),
            target: self,
            action: action
        )
        item.bezelColor = selected ? NSColor(AppColors.accent).withAlphaComponent(0.55) : nil
        return item
    }

    private func accountsItem() -> NSTouchBarItem {
        let item = NSCustomTouchBarItem(identifier: Self.accountsIdentifier)
        let scrubber = NSScrubber(frame: NSRect(x: 0, y: 0, width: TouchBarLayout.accountWidth, height: TouchBarLayout.height))
        let layout = NSScrubberFlowLayout()
        layout.itemSize = NSSize(width: TouchBarLayout.accountWidth, height: TouchBarLayout.height)
        layout.itemSpacing = TouchBarLayout.accountSpacing
        scrubber.scrubberLayout = layout
        scrubber.mode = .free
        scrubber.showsAdditionalContentIndicators = true
        scrubber.register(AccountItemView.self, forItemIdentifier: AccountItemView.reuseIdentifier)
        scrubber.dataSource = self
        scrubber.delegate = self
        scrubber.setAccessibilityLabel(String(localized: "common.accounts"))
        item.view = scrubber
        // The item is resolved lazily, so the data source has to be read here:
        // a scrubber that is never displayed does not reload on its own.
        scrubber.reloadData()

        // A custom Touch Bar item is sized by its own constraints: without a
        // width the scrubber lays out at zero and is never seen.
        let width = scrubber.widthAnchor.constraint(
            equalToConstant: TouchBarLayout.stripWidth(
                accountCount: accounts.count,
                available: TouchBarLayout.unresolvedAppWidth
            )
        )
        width.isActive = true
        scrubber.heightAnchor.constraint(equalToConstant: TouchBarLayout.height).isActive = true
        stripWidth = width
        return item
    }

    private var accountsScrubber: NSScrubber? {
        bar.item(forIdentifier: Self.accountsIdentifier)?.view as? NSScrubber
    }

    // MARK: - Selection

    private func refreshSelection() {
        if let overview = bar.item(forIdentifier: ItemID.overview) as? NSButtonTouchBarItem {
            update(overview, title: String(localized: "navigation.overview"),
                   symbol: "square.grid.2x2", selectedSymbol: "square.grid.2x2.fill",
                   selected: route == .overview)
        }
        if let analytics = bar.item(forIdentifier: ItemID.analytics) as? NSButtonTouchBarItem {
            update(analytics, title: String(localized: "navigation.analytics"),
                   symbol: "chart.bar", selectedSymbol: "chart.bar.fill",
                   selected: route == .analytics)
        }
        guard let scrubber = accountsScrubber else { return }
        let index = selectedIndex
        if scrubber.selectedIndex != index {
            scrubber.selectedIndex = index
            if index >= 0 { scrubber.scrollItem(at: index, to: .none) }
        }
    }

    private func update(
        _ item: NSButtonTouchBarItem,
        title: String,
        symbol: String,
        selectedSymbol: String,
        selected: Bool
    ) {
        item.image = symbolImage(selected ? selectedSymbol : symbol, description: title)
        item.bezelColor = selected ? NSColor(AppColors.accent).withAlphaComponent(0.55) : nil
    }

    private var selectedIndex: Int {
        guard case .account(let id) = route else { return -1 }
        return accounts.firstIndex { $0.id == id } ?? -1
    }

    // MARK: - Width

    /// Gives the strip whatever the buttons left, and retries until the bar has
    /// been laid out: before that every item still reports its un-styled size.
    private func applyStripWidth() {
        guard isEnabled else { return }
        guard let width = measuredStripWidth() else {
            scheduleWidthRetry()
            return
        }
        retries = 0
        guard let constraint = stripWidth, abs(constraint.constant - width) > 0.5 else { return }
        constraint.constant = width
    }

    private func measuredStripWidth() -> CGFloat? {
        guard let scrubber = accountsScrubber else { return nil }
        let buttonWidths = ItemID.navigation.compactMap { identifier -> CGFloat? in
            guard let view = bar.item(forIdentifier: identifier)?.view,
                  view.fittingSize.height >= TouchBarLayout.height - 1
            else { return nil }
            return view.fittingSize.width
        }
        guard buttonWidths.count == ItemID.navigation.count else { return nil }

        let appWidth = widestSuperview(of: scrubber) ?? TouchBarLayout.unresolvedAppWidth
        // Four items leave three gaps: the strip sits between the navigation
        // buttons and the plus.
        let available = appWidth - buttonWidths.reduce(0, +) - TouchBarLayout.itemGap * CGFloat(buttonWidths.count)
        return TouchBarLayout.stripWidth(accountCount: accounts.count, available: available)
    }

    private func widestSuperview(of view: NSView) -> CGFloat? {
        var width: CGFloat?
        var parent = view.superview
        while let current = parent {
            if current.frame.width > (width ?? 0) { width = current.frame.width }
            parent = current.superview
        }
        guard let width, width >= TouchBarLayout.minimumAppWidth else { return nil }
        return width
    }

    private func scheduleWidthRetry() {
        guard retries < 30 else { return }
        retries += 1
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 60_000_000)
            self?.applyStripWidth()
        }
    }

    // MARK: - Actions

    @objc private func openOverview() {
        guard isEnabled else { return }
        actions.openOverview()
    }

    @objc private func openAnalytics() {
        guard isEnabled else { return }
        actions.openAnalytics()
    }

    @objc private func startOperation() {
        guard isEnabled else { return }
        actions.newOperation()
    }

    // MARK: - Scrubber

    func numberOfItems(for scrubber: NSScrubber) -> Int { accounts.count }

    func scrubber(_ scrubber: NSScrubber, viewForItemAt index: Int) -> NSScrubberItemView {
        guard accounts.indices.contains(index) else { return AccountItemView(frame: .zero) }
        let view = scrubber.makeItem(withIdentifier: AccountItemView.reuseIdentifier, owner: nil) as? AccountItemView
            ?? AccountItemView(frame: .zero)
        view.configure(name: accounts[index].name, iconName: accounts[index].iconName)
        return view
    }

    func scrubber(_ scrubber: NSScrubber, didSelectItemAt index: Int) {
        guard isEnabled, accounts.indices.contains(index) else { return }
        actions.openAccount(accounts[index].id)
    }
}

/// One account in the strip. The scrubber owns taps and swipes; the cell only
/// draws its button shape in every state.
private final class AccountItemView: NSScrubberItemView {
    static let reuseIdentifier = NSUserInterfaceItemIdentifier("montra.touchbar.account")

    private let icon = NSImageView()
    private let name = NSTextField(labelWithString: "")

    override var isSelected: Bool { didSet { updateAppearance() } }
    override var isHighlighted: Bool { didSet { updateAppearance() } }

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.cornerRadius = 7
        layer?.borderWidth = 1
        updateAppearance()

        icon.imageScaling = .scaleProportionallyDown
        icon.symbolConfiguration = .init(pointSize: 13, weight: .medium)
        icon.contentTintColor = .white
        name.font = .systemFont(ofSize: 13, weight: .medium)
        name.textColor = .white
        name.lineBreakMode = .byTruncatingTail
        name.maximumNumberOfLines = 1
        name.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        icon.translatesAutoresizingMaskIntoConstraints = false
        name.translatesAutoresizingMaskIntoConstraints = false
        addSubview(icon)
        addSubview(name)
        NSLayoutConstraint.activate([
            icon.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 9),
            icon.centerYAnchor.constraint(equalTo: centerYAnchor),
            icon.widthAnchor.constraint(equalToConstant: 16),
            icon.heightAnchor.constraint(equalToConstant: 16),
            name.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 6),
            name.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -9),
            name.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }

    required init?(coder: NSCoder) { nil }

    func configure(name: String, iconName: String) {
        self.name.stringValue = name
        icon.image = Self.glyphImage(iconName)
            ?? NSImage(systemSymbolName: "creditcard.fill", accessibilityDescription: nil)
        setAccessibilityLabel(name)
    }

    /// The account's glyph, drawn the way the rest of the app draws it: an emoji
    /// becomes an image of itself, everything else resolves as an SF Symbol.
    private static func glyphImage(_ glyph: String) -> NSImage? {
        guard AppIconGlyph.isEmoji(glyph) else {
            return NSImage(systemSymbolName: glyph, accessibilityDescription: nil)
        }
        return NSImage(size: NSSize(width: 16, height: 16), flipped: false) { rect in
            let attributes: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 12)]
            let text = glyph as NSString
            let textSize = text.size(withAttributes: attributes)
            text.draw(
                at: NSPoint(x: rect.midX - textSize.width / 2, y: rect.midY - textSize.height / 2),
                withAttributes: attributes
            )
            return true
        }
    }

    private func updateAppearance() {
        let fill: CGFloat = isHighlighted ? 0.39 : isSelected ? 0.30 : 0.18
        layer?.backgroundColor = NSColor(white: fill, alpha: 1).cgColor
        layer?.borderColor = NSColor(white: isSelected || isHighlighted ? 0.72 : 0.36, alpha: 1).cgColor
    }
}

/// Puts the controller's bar on the hosting window. The window is only known
/// once the view is in the hierarchy, so the attach also runs on that move.
struct TouchBarHost: NSViewRepresentable {
    let accounts: [MontraTouchBarController.Account]
    let route: Route
    let isEnabled: Bool
    let actions: MontraTouchBarController.Actions

    func makeCoordinator() -> MontraTouchBarController { MontraTouchBarController() }

    func makeNSView(context: Context) -> NSView {
        let view = WindowAttachmentView()
        view.onWindowChange = { [weak coordinator = context.coordinator] window in
            coordinator?.attach(to: window)
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        let coordinator = context.coordinator
        coordinator.update(accounts: accounts, route: route, isEnabled: isEnabled, actions: actions)
        coordinator.attach(to: nsView.window)
    }
}

private final class WindowAttachmentView: NSView {
    var onWindowChange: ((NSWindow) -> Void)?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if let window { onWindowChange?(window) }
    }
}

private func symbolImage(_ name: String, description: String) -> NSImage {
    NSImage(systemSymbolName: name, accessibilityDescription: description)
        ?? NSImage(size: NSSize(width: 1, height: 1))
}
#endif
