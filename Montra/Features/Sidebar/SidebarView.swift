import SwiftUI

enum SidebarLayout {
    static let width: CGFloat = 240
    static let navRowInnerPadding: CGFloat = AppStyle.Spacing.xSmall
    static let selectionCornerRadius: CGFloat = AppStyle.Radius.md
    /// Clears the traffic lights, which float over the sidebar.
    static let topContentInset: CGFloat = 42
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
    let onOpenAccount: (Account) -> Void
    let onOpenSettings: () -> Void
    let onOpenAbout: () -> Void
    let onOpenICloud: () -> Void

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

                    if !standardAccounts.isEmpty {
                        sectionLabel(String(localized: "common.accounts"))
                        ForEach(standardAccounts) { account in
                            accountRow(account)
                        }
                    }

                    if !savingsAccounts.isEmpty {
                        sectionLabel(String(localized: "common.savings_3"))
                        ForEach(savingsAccounts) { account in
                            accountRow(account)
                        }
                    }

                    sectionLabel(String(localized: "common.money"))
                    navRow(
                        title: String(localized: "navigation.categories"),
                        symbol: "tag",
                        selectedSymbol: "tag.fill",
                        destination: .categories,
                        accessory: "\(categoryCount)"
                    )

                    sectionLabel(String(localized: "common.analysis"))
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
    }

    private var bottomBar: some View {
        VStack(alignment: .leading, spacing: AppStyle.Spacing.xSmall) {
            Button(action: onNewAccount) {
                HStack(spacing: AppStyle.Spacing.xSmall) {
                    Image(systemName: "plus")
                        .font(.system(size: 11, weight: .semibold))
                    Text(String(localized: "account.new"))
                    Spacer(minLength: 0)
                }
            }
            .buttonStyle(.montra(.secondary, width: .fill))
            .focusEffectDisabled()
            .accessibilityLabel(String(localized: "account.new"))

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
            accessory: accessory
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
            masked: settings.hideBalances
        ) {
            withAnimation(AppMotion.page) { route = .account(account.id) }
        }
    }

    private func sectionLabel(_ title: String) -> some View {
        Text(title)
            .font(AppStyle.Typography.metadata.weight(.semibold))
            .foregroundStyle(AppColors.textTertiary)
            .padding(.horizontal, SidebarLayout.navRowInnerPadding)
            .padding(.top, AppStyle.Spacing.small)
            .padding(.bottom, AppStyle.Spacing.xxxSmall)
            .accessibilityAddTraits(.isHeader)
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
    let action: () -> Void

    @State private var isHovering = false
    @FocusState private var isFocused: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

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
        .focused($isFocused)
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
    let action: () -> Void

    @State private var isHovering = false
    @FocusState private var isFocused: Bool

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
        .focused($isFocused)
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
            Image(systemName: account.iconName)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(account.color.color)
                .frame(width: 16)
                .accessibilityHidden(true)

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
