import SwiftUI

enum SidebarLayout {
    static let width: CGFloat = 240
    static let navRowInnerPadding: CGFloat = AppStyle.Spacing.xSmall
    static let selectionCornerRadius: CGFloat = AppStyle.Radius.md
    /// Clears the traffic lights, which float over the sidebar.
    static let topContentInset: CGFloat = 42
}

/// Which sidebar row holds keyboard focus. One shared `@FocusState` lets the
/// window start on the row of the page it opens, instead of letting AppKit pick
/// the first control it finds at the bottom of the sidebar.
private enum SidebarFocusTarget: Hashable {
    case nav(Route)
    case account(UUID)
}

struct SidebarView: View {
    @EnvironmentObject private var settings: SettingsStore

    @Binding var route: Route
    let accounts: [Account]
    let categoryCount: Int
    let iCloudConnected: Bool
    /// Hidden while the onboarding hero account is still flying into place; the
    /// row keeps its space so the flight can land on its exact frame.
    var hiddenAccountID: UUID? = nil
    let onNewAccount: () -> Void
    /// Opens the create sheet with the savings switch already on, straight into
    /// the "Savings" group.
    let onNewSavingsAccount: () -> Void
    let onOpenAccount: (Account) -> Void
    let onOpenSettings: () -> Void
    let onOpenAbout: () -> Void
    let onOpenICloud: () -> Void

    @FocusState private var focusedRow: SidebarFocusTarget?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            AppBrandMark()
                .padding(.top, SidebarLayout.topContentInset)
                .padding(.bottom, AppStyle.Spacing.large)
                .padding(.horizontal, AppStyle.Spacing.small)

            ScrollView {
                VStack(alignment: .leading, spacing: AppStyle.Spacing.xxxSmall) {
                    navRow(
                        title: String(localized: "navigation.overview"),
                        symbol: "square.grid.2x2",
                        selectedSymbol: "square.grid.2x2.fill",
                        destination: .overview
                    )

                    // Both account groups keep their header even when empty: the
                    // «+» in it is the only place to start a new account or a
                    // new savings account from the sidebar. Once a group has
                    // rows, the «+» rests until the pointer reaches the header.
                    SidebarSectionLabel(
                        title: String(localized: "common.accounts"),
                        addLabel: String(localized: "account.new"),
                        addAction: onNewAccount,
                        showsAddAlways: standardAccounts.isEmpty
                    )
                    ForEach(standardAccounts) { account in
                        accountRow(account)
                    }

                    SidebarSectionLabel(
                        title: String(localized: "common.savings_3"),
                        addLabel: String(localized: "account.new_savings"),
                        addAction: onNewSavingsAccount,
                        showsAddAlways: savingsAccounts.isEmpty
                    )
                    ForEach(savingsAccounts) { account in
                        accountRow(account)
                    }

                    SidebarSectionLabel(title: String(localized: "common.money"))
                    navRow(
                        title: String(localized: "navigation.categories"),
                        symbol: "tag",
                        selectedSymbol: "tag.fill",
                        destination: .categories,
                        accessory: "\(categoryCount)"
                    )

                    SidebarSectionLabel(title: String(localized: "common.analysis"))
                    navRow(
                        title: String(localized: "navigation.analytics"),
                        symbol: "chart.bar",
                        selectedSymbol: "chart.bar.fill",
                        destination: .analytics
                    )
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, AppStyle.Spacing.small)
                .padding(.bottom, AppStyle.Spacing.xSmall)
            }
            .scrollIndicators(.never)
            .focusEffectDisabled()

            bottomBar
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .frame(width: SidebarLayout.width)
        .background(AppColors.surfaceCard)
        .ignoresSafeArea(.container, edges: .top)
        .task {
            // Without a hint a fresh window focuses the first control at the
            // bottom of the sidebar, so "Settings" lights up on launch. Start on
            // the row of the page the window already shows instead.
            focusedRow = initialFocusTarget
        }
    }

    /// The row of the page the window opens on, so the initial keyboard focus
    /// sits on the selected row and not on "Settings".
    private var initialFocusTarget: SidebarFocusTarget {
        if case .account(let id) = route { return .account(id) }
        return .nav(route.sidebarSection ?? .overview)
    }

    private var bottomBar: some View {
        VStack(alignment: .leading, spacing: AppStyle.Spacing.xSmall) {
            VStack(alignment: .leading, spacing: AppStyle.Spacing.xxxSmall) {
                navRow(
                    title: String(localized: "navigation.settings"),
                    symbol: "gearshape",
                    selectedSymbol: "gearshape.fill",
                    destination: .settings
                )
                navRow(
                    title: String(localized: "common.about"),
                    symbol: "info.circle",
                    selectedSymbol: "info.circle.fill",
                    destination: .about
                )
            }

            syncStatusCard
                .padding(.top, AppStyle.Spacing.xxSmall)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, AppStyle.Spacing.small)
        .padding(.bottom, AppStyle.Spacing.small)
    }

    private func navRow(
        title: String,
        symbol: String,
        selectedSymbol: String,
        destination: Route,
        accessory: String? = nil
    ) -> some View {
        SidebarNavRow(
            title: title,
            symbol: symbol,
            selectedSymbol: selectedSymbol,
            isSelected: route.sidebarSection == destination,
            accessory: accessory,
            focusedRow: $focusedRow,
            focusTarget: .nav(destination)
        ) {
            withAnimation(AppMotion.page) { route = destination }
        }
    }

    private var standardAccounts: [Account] {
        accounts.filter { !$0.isSavings }
    }

    private var savingsAccounts: [Account] {
        accounts.filter(\.isSavings)
    }

    private func accountRow(_ account: Account) -> some View {
        SidebarAccountRow(
            account: account,
            isSelected: route == .account(account.id),
            isHidden: hiddenAccountID == account.id,
            masked: settings.hideBalances,
            focusedRow: $focusedRow,
            focusTarget: .account(account.id)
        ) {
            withAnimation(AppMotion.page) { route = .account(account.id) }
        }
    }

    private var syncStatusCard: some View {
        Button(action: onOpenICloud) {
            HStack(spacing: AppStyle.Spacing.xSmall) {
                Image(systemName: iCloudConnected ? "checkmark.icloud" : "icloud.slash")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(iCloudConnected ? AppColors.statusSafeText : AppColors.textSecondary)
                    .accessibilityHidden(true)

                Text(iCloudConnected ? String(localized: "common.icloud_connected") : String(localized: "sidebar.icloud_not_connected"))
                    .font(AppStyle.Typography.callout.weight(.medium))
                    .foregroundStyle(AppColors.textSecondary)

                Spacer(minLength: 0)
            }
            .padding(.horizontal, AppStyle.Spacing.small)
            .padding(.vertical, AppStyle.Spacing.small)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: AppStyle.Radius.lg, style: .continuous)
                    .fill(AppColors.fillSecondary)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .focusEffectDisabled()
        .pointingHandOnHover()
        .accessibilityLabel(iCloudConnected ? String(localized: "common.icloud_connected") : String(localized: "sidebar.icloud_not_connected_open_sync"))
    }
}

/// One sidebar row. The icon swaps outline for filled with a short snappy
/// animation, the way the reference marks the selected page.
private struct SidebarNavRow: View {
    let title: String
    let symbol: String
    let selectedSymbol: String
    let isSelected: Bool
    let accessory: String?
    @FocusState.Binding var focusedRow: SidebarFocusTarget?
    let focusTarget: SidebarFocusTarget
    let action: () -> Void

    @State private var isHovering = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var isFocused: Bool { focusedRow == focusTarget }

    var body: some View {
        Button(action: action) {
            HStack(spacing: AppStyle.Spacing.xSmall) {
                icon
                Text(title)
                    .font(AppStyle.Typography.body.weight(isSelected ? .semibold : .medium))
                    .lineLimit(1)
                Spacer(minLength: AppStyle.Spacing.xSmall)
                if let accessory {
                    Text(accessory)
                        .font(AppStyle.Typography.metadataEmphasis.numbers)
                        .monospacedDigit()
                        .foregroundStyle(AppColors.textTertiary)
                        .lineLimit(1)
                        .contentTransition(reduceMotion ? .identity : .numericText())
                }
            }
            .foregroundStyle(isSelected || isFocused ? AppColors.textPrimary : AppColors.textSecondary)
            .padding(.horizontal, SidebarLayout.navRowInnerPadding)
            .padding(.vertical, AppStyle.Spacing.xxSmallPlus)
            .background(
                background,
                in: RoundedRectangle(cornerRadius: SidebarLayout.selectionCornerRadius, style: .continuous)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .focused($focusedRow, equals: focusTarget)
        .focusEffectDisabled()
        .onHover { isHovering = $0 }
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var icon: some View {
        ZStack {
            Image(systemName: symbol)
                .opacity(isSelected ? 0 : 1)
            Image(systemName: selectedSymbol)
                .opacity(isSelected ? 1 : 0)
                .scaleEffect(isSelected ? 1 : 0.86)
        }
        .font(AppStyle.Typography.rowTitle)
        .frame(width: 16)
        .animation(reduceMotion ? nil : .snappy(duration: 0.2), value: isSelected)
    }

    private var background: Color {
        if isSelected { return AppColors.fillSecondary }
        if isFocused { return AppColors.fillSecondary.opacity(0.55) }
        if isHovering { return AppColors.surfaceRaised }
        return .clear
    }
}

/// A single account under Overview: its own colour, its name and the balance in
/// its own currency, so every wallet is one click away from the sidebar.
private struct SidebarAccountRow: View {
    let account: Account
    let isSelected: Bool
    let isHidden: Bool
    let masked: Bool
    @FocusState.Binding var focusedRow: SidebarFocusTarget?
    let focusTarget: SidebarFocusTarget
    let action: () -> Void

    @State private var isHovering = false

    private var isFocused: Bool { focusedRow == focusTarget }

    var body: some View {
        Button(action: action) {
            SidebarAccountRowContent(
                account: account,
                isSelected: isSelected,
                isFocused: isFocused,
                masked: masked
            )
            .background(
                background,
                in: RoundedRectangle(cornerRadius: SidebarLayout.selectionCornerRadius, style: .continuous)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .focused($focusedRow, equals: focusTarget)
        .focusEffectDisabled()
        .onHover { isHovering = $0 }
        .pointingHandOnHover()
        .opacity(isHidden ? 0 : 1)
        .background {
            GeometryReader { proxy in
                Color.clear.preference(
                    key: SidebarAccountFramesKey.self,
                    value: [account.id: proxy.frame(in: .named(OnboardingHero.coordinateSpace))]
                )
            }
        }
        .accessibilityLabel("\(account.name), \(MoneyFormat.string(account.balance, currency: account.currency, masked: masked))")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var background: Color {
        if isSelected { return AppColors.fillSecondary }
        if isFocused { return AppColors.fillSecondary.opacity(0.55) }
        if isHovering { return AppColors.surfaceRaised }
        return .clear
    }
}

/// The inside of an account row. The onboarding hero renders the same content,
/// so the chip that flies in lands on exactly the pixels the row occupies.
struct SidebarAccountRowContent: View {
    let account: Account
    let isSelected: Bool
    let isFocused: Bool
    let masked: Bool

    var body: some View {
        HStack(spacing: AppStyle.Spacing.xSmall) {
            AccountGlyph(icon: account.iconName, color: account.color.color, size: 12)
                .frame(width: 16)

            Text(account.name)
                .font(AppStyle.Typography.body.weight(isSelected ? .semibold : .medium))
                .foregroundStyle(isSelected || isFocused ? AppColors.textPrimary : AppColors.textSecondary)
                .lineLimit(1)

            Spacer(minLength: AppStyle.Spacing.xxSmallPlus)

            Text(MoneyFormat.string(
                account.balance,
                currency: account.currency,
                masked: masked,
                compact: true
            ))
            .font(AppStyle.Typography.metadataEmphasis.numbers)
            .monospacedDigit()
            .foregroundStyle(isSelected ? AppColors.textSecondary : AppColors.textTertiary)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
        }
        .padding(.horizontal, SidebarLayout.navRowInnerPadding)
        .padding(.vertical, AppStyle.Spacing.xxSmallPlus)
    }
}

/// The small circular «+» in a group caption: it opens the create sheet for that
/// group without a full-width button taking a row from the bottom bar.
/// A quiet group caption. Account groups put a circular «+» at its trailing
/// edge: once the group has rows the «+» rests and only fades in while the
/// pointer is on the caption, so the sidebar stays calm; a group that is still
/// empty keeps it on screen, because there is nothing else to hover and it is
/// the only way to create the first row.
private struct SidebarSectionLabel: View {
    let title: String
    var addLabel: String? = nil
    var addAction: (() -> Void)? = nil
    var showsAddAlways: Bool = false

    @State private var isHovering = false

    var body: some View {
        HStack(spacing: AppStyle.Spacing.xxSmall) {
            Text(title)
                .font(AppStyle.Typography.metadata.weight(.semibold))
                .foregroundStyle(AppColors.textTertiary)
                .accessibilityAddTraits(.isHeader)

            Spacer(minLength: 0)

            if let addLabel, let addAction {
                SidebarAddButton(
                    label: addLabel,
                    isVisible: showsAddAlways || isHovering,
                    action: addAction
                )
            }
        }
        .padding(.horizontal, SidebarLayout.navRowInnerPadding)
        .padding(.top, AppStyle.Spacing.small)
        .padding(.bottom, AppStyle.Spacing.xxxSmall)
        .contentShape(Rectangle())
        .onHover { isHovering = $0 }
    }
}

/// The small circular «+» in a group caption: it opens the create sheet for that
/// group without a full-width button taking a row from the bottom bar.
private struct SidebarAddButton: View {
    let label: String
    /// The caption's hover state; keyboard focus shows the button too.
    let isVisible: Bool
    let action: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isHovering = false
    @FocusState private var isFocused: Bool

    private var isShown: Bool { isVisible || isHovering || isFocused }

    var body: some View {
        Button(action: action) {
            Image(systemName: "plus")
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(isFocused || isHovering ? AppColors.textPrimary : AppColors.textSecondary)
                .frame(width: 18, height: 18)
                .background(
                    Circle().fill(isFocused || isHovering ? AppColors.fillSecondaryHover : AppColors.fillSecondary)
                )
                .overlay {
                    if isFocused {
                        Circle().strokeBorder(AppColors.textSecondary, lineWidth: 1)
                    }
                }
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .focused($isFocused)
        .focusEffectDisabled()
        .onHover { isHovering = $0 }
        .pointingHandOnHover()
        .opacity(isShown ? 1 : 0)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: isShown)
        .help(label)
        .accessibilityLabel(label)
    }
}
