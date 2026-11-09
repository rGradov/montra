import AppKit
import SwiftUI

/// A native horizontal picker that keeps all accounts reachable on the Touch Bar.
struct TouchBarAccountPicker: NSViewRepresentable {
    struct Item: Equatable {
        let id: UUID
        let name: String
        let iconName: String
    }

    let accounts: [Item]
    let selection: UUID?
    let onSelect: (UUID) -> Void

    private static let itemWidth: CGFloat = 118
    private static let itemHeight: CGFloat = 30
    private static let itemSpacing: CGFloat = 6

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> NSScrubber {
        let scrubber = NSScrubber(frame: .zero)
        let layout = NSScrubberFlowLayout()
        layout.itemSize = NSSize(width: Self.itemWidth, height: Self.itemHeight)
        layout.itemSpacing = Self.itemSpacing
        scrubber.scrubberLayout = layout
        scrubber.mode = .free
        scrubber.showsAdditionalContentIndicators = true
        scrubber.register(AccountItemView.self, forItemIdentifier: Coordinator.itemIdentifier)
        scrubber.setAccessibilityLabel(String(localized: "common.accounts"))
        scrubber.dataSource = context.coordinator
        scrubber.delegate = context.coordinator
        return scrubber
    }

    func updateNSView(_ scrubber: NSScrubber, context: Context) {
        context.coordinator.update(scrubber, accounts: accounts, selection: selection, onSelect: onSelect)
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: NSScrubber, context: Context) -> CGSize? {
        let visibleCount = CGFloat(min(accounts.count, 3))
        let width = visibleCount * Self.itemWidth + max(0, visibleCount - 1) * Self.itemSpacing
        return CGSize(width: min(proposal.width ?? width, width), height: Self.itemHeight)
    }

    @MainActor
    final class Coordinator: NSObject, NSScrubberDataSource, NSScrubberDelegate {
        static let itemIdentifier = NSUserInterfaceItemIdentifier("montra.touchbar.account")
        private var accounts: [Item] = []
        private var onSelect: ((UUID) -> Void)?

        func update(_ scrubber: NSScrubber, accounts: [Item], selection: UUID?, onSelect: @escaping (UUID) -> Void) {
            self.onSelect = onSelect
            if self.accounts != accounts {
                self.accounts = accounts
                scrubber.reloadData()
            }

            let index = accounts.firstIndex { $0.id == selection } ?? -1
            if scrubber.selectedIndex != index {
                scrubber.selectedIndex = index
                if index >= 0 { scrubber.scrollItem(at: index, to: .none) }
            }
        }

        func numberOfItems(for scrubber: NSScrubber) -> Int { accounts.count }

        func scrubber(_ scrubber: NSScrubber, viewForItemAt index: Int) -> NSScrubberItemView {
            let item = scrubber.makeItem(withIdentifier: Self.itemIdentifier, owner: nil) as? AccountItemView
                ?? AccountItemView(frame: .zero)
            item.configure(with: accounts[index])
            return item
        }

        func scrubber(_ scrubber: NSScrubber, didSelectItemAt index: Int) {
            guard accounts.indices.contains(index) else { return }
            onSelect?(accounts[index].id)
        }
    }
}

/// The scrubber owns taps and swipes. The item draws its button shape in every state.
private final class AccountItemView: NSScrubberItemView {
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

    func configure(with account: TouchBarAccountPicker.Item) {
        name.stringValue = account.name
        icon.image = NSImage(systemSymbolName: account.iconName, accessibilityDescription: nil)
            ?? NSImage(systemSymbolName: "creditcard.fill", accessibilityDescription: nil)
        setAccessibilityLabel(account.name)
    }

    private func updateAppearance() {
        let fill: CGFloat = isHighlighted ? 0.39 : isSelected ? 0.30 : 0.18
        layer?.backgroundColor = NSColor(white: fill, alpha: 1).cgColor
        layer?.borderColor = NSColor(white: isSelected || isHighlighted ? 0.72 : 0.36, alpha: 1).cgColor
    }
}
