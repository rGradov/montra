import SwiftData
import SwiftUI

/// The page the app opens on: every account's money in one figure, how the period
/// is going, and the last few operations. Mirrors the reference Overview row for
/// row, with cross-currency totals from live exchange rates.
struct OverviewView: View {
    @EnvironmentObject private var settings: SettingsStore
    @EnvironmentObject private var headerHost: DetailHeaderHost
    @EnvironmentObject private var rates: RateStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @Query(sort: [SortDescriptor(\Account.sortIndex, order: .forward)]) private var accounts: [Account]
    @Query(sort: [SortDescriptor(\Operation.date, order: .reverse)]) private var operations: [Operation]
    @Query(sort: [SortDescriptor(\Period.start, order: .forward)]) private var periods: [Period]
    @Query private var categories: [Category]

    /// Incremented when the period was edited in its sheet; the header replays.
    var periodRevision: Int = 0

    let onNewOperation: (Account?) -> Void
    let onNewAccount: () -> Void
    let onOpenAccount: (Account) -> Void
    let onOpenPeriods: () -> Void
    let onOpenOperations: () -> Void
    let onEditOperation: (Operation) -> Void

    @State private var selectedCurrency: Currency?
    @State private var highlightedAccountID: UUID?
    @StateObject private var newRows = NewRowHighlighter()

    private var currentPeriod: Period? {
        PeriodService.currentPeriod(in: periods)
    }

    private var periodOperations: [Operation] {
        Finance.operations(operations, in: currentPeriod)
    }

    /// The accounts this page talks about. Hiding one keeps its money and its
    /// sidebar row; it just stops contributing to the Overview's total, bar and
    /// list, so savings can stay out of the spendable picture.
    private var visibleAccounts: [Account] {
        accounts.filter { !$0.isHiddenFromOverview }
    }

    private var hiddenAccounts: [Account] {
        accounts.filter(\.isHiddenFromOverview)
    }

    private var presentCurrencies: [Currency] {
        Finance.currencies(in: visibleAccounts)
    }

    private var displayCurrency: Currency {
        if let selectedCurrency, presentCurrencies.contains(selectedCurrency) { return selectedCurrency }
        if presentCurrencies.contains(settings.primaryCurrency) { return settings.primaryCurrency }
        return presentCurrencies.first ?? settings.primaryCurrency
    }

    private var totalInDisplay: Decimal {
        Finance.totalConverted(visibleAccounts, to: displayCurrency, rates: rates.rates)
    }

    private var summary: Finance.PeriodSummary {
        Finance.PeriodSummary(
            income: Finance.sumConverted(periodOperations, kind: .income, to: displayCurrency, rates: rates.rates),
            expense: Finance.sumConverted(periodOperations, kind: .expense, to: displayCurrency, rates: rates.rates),
            mandatory: Finance.mandatoryConverted(periodOperations, to: displayCurrency, rates: rates.rates)
        )
    }

    private var hoveredAccount: Account? {
        visibleAccounts.first { $0.id == highlightedAccountID }
    }

    private var subtitle: String {
        var parts = [Finance.accountsCountText(visibleAccounts.count)]
        parts.append(Finance.operationsCountText(periodOperations.count) + String(localized: "transaction.in_period_suffix"))
        if let currentPeriod {
            let left = max(0, AppDate.daysBetween(.now, currentPeriod.end))
            parts.append(Finance.daysText(left) + String(localized: "period.time_left_suffix"))
        }
        return parts.joined(separator: " · ")
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppStyle.Spacing.large) {
                hero
                accountsSection
                periodSection
                recentSection
            }
            .padding(.horizontal, AppDetailPageLayout.horizontalInset)
            .padding(.bottom, AppStyle.Spacing.large)
        }
        .shellBottomRoom()
        .background(AppColors.surfaceBase)
        .onAppear {
            syncHeader()
            newRows.track(operations.map(\.id))
        }
        .onChange(of: headerKey) { _, _ in syncHeader() }
        .onChange(of: operations.map(\.id)) { _, ids in newRows.track(ids) }
    }

    private var headerKey: String {
        "overview|\(subtitle)|\(periodRevision)"
    }

    private var headerTrailing: some View {
        HStack(spacing: AppStyle.Spacing.xSmall) {
            periodButton
            Button {
                onNewOperation(nil)
            } label: {
                Label(String(localized: "transaction.new"), systemImage: "plus")
            }
            .buttonStyle(.montra(.primary))
            .fixedSize(horizontal: true, vertical: false)
        }
    }

    private func syncHeader() {
        headerHost.config = DetailHeaderConfig(
            title: String(localized: "navigation.overview"),
            subtitle: subtitle,
            backTitle: nil,
            onBack: nil,
            trailing: AnyView(headerTrailing)
        )
    }

    private var periodButton: some View {
        Button {
            onOpenPeriods()
        } label: {
            HStack(spacing: AppStyle.Spacing.xxSmallPlus) {
                Image(systemName: "calendar")
                    .font(.system(size: 11, weight: .semibold))
                Text(currentPeriod?.title ?? String(localized: "common.period"))
                    .monospacedDigit()
                    .contentTransition(reduceMotion ? .identity : .numericText())
                    .animation(reduceMotion ? nil : .easeInOut(duration: 0.45), value: currentPeriod?.title)
            }
        }
        .buttonStyle(.montra(.secondary))
        .fixedSize(horizontal: true, vertical: false)
        .accessibilityLabel(String(localized: "transaction.list.period \(currentPeriod?.title ?? String(localized: "common.not_set"))"))
    }

    // MARK: - Hero

    private var hero: some View {
        VStack(alignment: .leading, spacing: AppStyle.Spacing.small) {
            HStack(alignment: .firstTextBaseline, spacing: AppStyle.Spacing.xSmall) {
                if visibleAccounts.isEmpty && !accounts.isEmpty {
                    VStack(alignment: .leading, spacing: AppStyle.Spacing.xxxSmall) {
                        Text(String(localized: "overview.accounts_are_hidden"))
                            .font(AppStyle.Typography.title.weight(.bold))
                        Text(String(localized: "overview.go_to_account_settings_to"))
                            .font(AppStyle.Typography.callout)
                            .foregroundStyle(AppColors.textSecondary)
                    }
                } else {
                    Text(money(totalInDisplay))
                        .font(AppStyle.Typography.title.weight(.bold).numbers)
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                        .contentTransition(reduceMotion ? .identity : .numericText())
                        .animation(reduceMotion ? nil : AppMotion.number, value: totalInDisplay)

                    Text(Finance.onAccountsText(visibleAccounts.count))
                        .font(AppStyle.Typography.rowTitle.numbers)
                        .foregroundStyle(AppColors.textSecondary)
                        .lineLimit(1)
                        #if os(iOS)
                        // English runs longer than Russian here; a phone should
                        // shrink the caption rather than cut it off.
                        .minimumScaleFactor(0.7)
                        #endif
                }

                Spacer(minLength: AppStyle.Spacing.small)

                VStack(alignment: .trailing, spacing: AppStyle.Spacing.xxxSmall) {
                    Text(String(localized: "overview.spending_this_period"))
                        .font(AppStyle.Typography.metadata)
                        .foregroundStyle(AppColors.textSecondary)
                    Text(money(summary.expense))
                        .font(AppStyle.Typography.rowTitle.numbers)
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .contentTransition(reduceMotion ? .identity : .numericText())
                        .animation(reduceMotion ? nil : AppMotion.number, value: summary.expense)
                }
            }
            .accessibilityElement(children: .combine)

            if !visibleAccounts.isEmpty {
                BalanceBar(
                    segments: visibleAccounts.map { account in
                        BalanceBar.Segment(
                            id: account.id,
                            label: account.name,
                            value: max(0, (convertedBalance(account) as NSDecimalNumber).doubleValue),
                            color: account.color.color
                        )
                    },
                    highlightedID: highlightedAccountID,
                    onHover: { id in highlightedAccountID = id }
                )
            }

            hoverLine

            if presentCurrencies.count > 1 {
                currencyChips
            }
        }
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.15), value: highlightedAccountID)
    }

    /// One line under the bar. At rest it says where the rates came from; under
    /// the pointer it explains the account, including what a foreign balance is
    /// worth in the currency on screen. Hovering Revolut now says something.
    private var hoverLine: some View {
        HStack(spacing: AppStyle.Spacing.xxSmall) {
            if let account = hoveredAccount {
                AccountGlyph(icon: account.iconName, color: account.color.color, size: 10)
                    .frame(width: 12)

                Text(account.name)
                    .font(AppStyle.Typography.metadata.weight(.medium))
                    .foregroundStyle(AppColors.textSecondary)

                Text("·")
                    .foregroundStyle(AppColors.textTertiary)

                Text(MoneyFormat.string(account.balance, currency: account.currency,
                                        masked: settings.hideBalances, compact: true))
                    .font(AppStyle.Typography.metadata.numbers)
                    .foregroundStyle(AppColors.textTertiary)

                if account.currency != displayCurrency {
                    Text("≈")
                        .foregroundStyle(AppColors.textTertiary)
                    Text(money(convertedBalance(account)))
                        .font(AppStyle.Typography.metadataEmphasis.numbers)
                        .foregroundStyle(AppColors.textPrimary)
                }
            } else {
                Image(systemName: rates.rates.source.isApproximate ? "exclamationmark.triangle.fill" : "arrow.triangle.2.circlepath")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(rates.rates.source.isApproximate ? AppColors.statusCheckText : AppColors.textTertiary)

                Text(rates.rates.source.isApproximate
                     ? String(localized: "overview.approximate_rate_update_it_in")
                     : String(localized: "overview.rates_updated \(rates.rates.source.title) \(rates.updatedText)"))
                    .font(AppStyle.Typography.metadata)
                    .foregroundStyle(rates.rates.source.isApproximate ? AppColors.statusCheckText : AppColors.textTertiary)
                    .lineLimit(1)
            }

            Spacer(minLength: AppStyle.Spacing.small)

            if rates.isRefreshing {
                ProgressView()
                    .controlSize(.small)
                    .scaleEffect(0.5)
                    .frame(width: 12, height: 12)
            }
        }
        .frame(height: 14, alignment: .leading)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: highlightedAccountID)
        .accessibilityElement(children: .combine)
    }

    private var currencyChips: some View {
        #if os(iOS)
        // Four currency totals do not fit a phone's width. Wrapping keeps every
        // one of them readable instead of squeezing each capsule until its own
        // text runs onto a second line.
        FlowLayout(spacing: AppStyle.Spacing.xSmall, lineSpacing: AppStyle.Spacing.xSmall) {
            currencyChipViews
        }
        .padding(.top, AppStyle.Spacing.xxSmall)
        #else
        HStack(spacing: AppStyle.Spacing.xSmall) {
            currencyChipViews
            Spacer(minLength: 0)
        }
        .padding(.top, AppStyle.Spacing.xxSmall)
        #endif
    }

    @ViewBuilder
    private var currencyChipViews: some View {
        ForEach(presentCurrencies) { currency in
            CurrencyChip(
                currency: currency,
                total: Finance.totalConverted(visibleAccounts, to: currency, rates: rates.rates),
                isSelected: currency == displayCurrency,
                masked: settings.hideBalances
            ) {
                withAnimation(AppMotion.number) { selectedCurrency = currency }
            }
        }
    }

    // MARK: - Accounts

    private var accountsSection: some View {
        VStack(alignment: .leading, spacing: AppStyle.Spacing.xxSmallPlus) {
            SectionLabel(title: String(localized: "common.accounts"), trailing: "\(visibleAccounts.count)")

            if visibleAccounts.isEmpty {
                OverviewCard {
                    if accounts.isEmpty {
                        EmptyState(
                            symbol: "creditcard",
                            title: String(localized: "overview.no_accounts_yet"),
                            message: String(localized: "overview.add_cash_a_card_or"),
                            actionTitle: String(localized: "account.new"),
                            action: onNewAccount
                        )
                    } else {
                        EmptyState(
                            symbol: "eye.slash",
                            title: String(localized: "overview.all_accounts_are_hidden"),
                            message: String(localized: "overview.hidden_accounts_are_excluded_from"),
                            actionTitle: String(localized: "common.open_account"),
                            action: {
                                if let first = hiddenAccounts.first { onOpenAccount(first) }
                            }
                        )
                    }
                }
            } else {
                OverviewCard {
                    ForEach(Array(visibleAccounts.enumerated()), id: \.element.id) { index, account in
                        if index > 0 {
                            InsetCardDivider(horizontalInset: AppStyle.Row.cardHorizontalPadding)
                        }
                        AccountOverviewRow(
                            account: account,
                            share: shareFor(account),
                            converted: account.currency == displayCurrency ? nil : convertedBalance(account),
                            displayCurrency: displayCurrency,
                            masked: settings.hideBalances,
                            isEmphasized: highlightedAccountID == account.id,
                            isDimmed: highlightedAccountID != nil && highlightedAccountID != account.id,
                            onOpen: { onOpenAccount(account) },
                            onNewOperation: { onNewOperation(account) },
                            onHover: { hovering in
                                guard highlightedAccountID == nil || hovering else { return }
                                highlightedAccountID = hovering ? account.id : nil
                            }
                        )
                    }
                }
            }

            if !visibleAccounts.isEmpty, !hiddenAccounts.isEmpty {
                hiddenAccountsRow
            }
        }
    }

    /// A quiet way back to the accounts that left the page. Opens the first one
    /// so the switch can be found where it lives, in the account sheet.
    private var hiddenAccountsRow: some View {
        Button {
            if let first = hiddenAccounts.first { onOpenAccount(first) }
        } label: {
            HStack(spacing: AppStyle.Spacing.xxSmall) {
                Image(systemName: "eye.slash")
                    .font(.system(size: 10, weight: .semibold))
                    .accessibilityHidden(true)

                Text(String(localized: "overview.hidden_from_overview \(Finance.accountsCountText(hiddenAccounts.count))"))
                    .font(AppStyle.Typography.metadata)

                Spacer(minLength: AppStyle.Spacing.small)

                Text(String(localized: "common.manage"))
                    .font(AppStyle.Typography.metadataEmphasis)
            }
            .foregroundStyle(AppColors.textTertiary)
            .padding(.horizontal, AppStyle.Spacing.xxSmall)
            .padding(.vertical, AppStyle.Spacing.xxxSmall)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .pointingHandOnHover()
        .platformHelp(String(localized: "overview.open_an_account_to_show"))
        .accessibilityLabel(String(localized: "overview.hidden_from_overview_manage \(Finance.accountsCountText(hiddenAccounts.count))"))
    }

    private func convertedBalance(_ account: Account) -> Decimal {
        rates.convert(account.balance, from: account.currency, to: displayCurrency) ?? 0
    }

    /// The account's part of everything on screen, in the display currency.
    private func shareFor(_ account: Account) -> Double? {
        guard visibleAccounts.count > 1, totalInDisplay > 0 else { return nil }
        return Finance.share(convertedBalance(account), of: totalInDisplay)
    }

    // MARK: - Period

    private var periodSection: some View {
        VStack(alignment: .leading, spacing: AppStyle.Spacing.xxSmallPlus) {
            SectionLabel(title: String(localized: "common.period"), trailing: periodModeName)

            OverviewCard {
                PeriodSummaryRow(
                    period: currentPeriod,
                    daysLeft: currentPeriod.map { max(0, AppDate.daysBetween(.now, $0.end)) } ?? 0,
                    onOpen: onOpenPeriods
                )

                InsetCardDivider(horizontalInset: AppStyle.Row.cardHorizontalPadding)

                PlainSummaryRow(
                    symbol: "checkmark.shield.fill",
                    color: AppColors.Chart.amber,
                    title: String(localized: "common.essential_expenses"),
                    detail: mandatoryDetail,
                    value: money(summary.mandatory)
                )

                InsetCardDivider(horizontalInset: AppStyle.Row.cardHorizontalPadding)

                PlainSummaryRow(
                    symbol: "banknote",
                    color: AppColors.textTertiary,
                    title: String(localized: "common.available"),
                    detail: String(localized: "overview.income_minus_essential_expenses_in \(displayCurrency.code)"),
                    value: money(summary.free),
                    isEmphasized: true
                )
            }
        }
    }

    private var periodModeName: String {
        switch settings.periodMode {
        case .payday: String(localized: "overview.payday_to_payday")
        case .fixedDays: "\(Finance.daysText(settings.fixedLengthDays))"
        }
    }

    private var mandatoryDetail: String {
        let names = categories
            .filter { $0.kind == .expense && $0.isMandatory }
            .sorted { $0.sortIndex < $1.sortIndex }
            .map(\.displayName)
        return names.isEmpty ? String(localized: "overview.no_essential_categories") : names.joined(separator: ", ")
    }

    // MARK: - Recent operations

    private var recentSection: some View {
        VStack(alignment: .leading, spacing: AppStyle.Spacing.xxSmallPlus) {
            HStack(alignment: .firstTextBaseline) {
                SectionLabel(title: String(localized: "common.recent_transactions"))
                Spacer(minLength: AppStyle.Spacing.small)
                Button(String(localized: "transaction.all")) { onOpenOperations() }
                    .buttonStyle(.montra(.quiet, size: .small))
            }

            OverviewCard {
                let recent = recentOperations
                if recent.isEmpty {
                    EmptyState(
                        symbol: "arrow.left.arrow.right",
                        title: String(localized: "overview.no_transactions_yet"),
                        message: String(localized: "overview.add_your_first_expense_or"),
                        actionTitle: String(localized: "transaction.new"),
                        action: { onNewOperation(nil) }
                    )
                } else {
                    ForEach(Array(recent.enumerated()), id: \.element.id) { index, operation in
                        if index > 0 {
                            InsetCardDivider(horizontalInset: AppStyle.Row.cardHorizontalPadding)
                        }
                        RecentOperationRow(
                            operation: operation,
                            isNew: newRows.isNew(operation.id),
                            masked: settings.hideBalances,
                            onOpen: { onEditOperation(operation) }
                        )
                        .transition(.rowReveal)
                    }
                }
            }
            .animation(AppMotion.insert, value: recentIDs)
        }
    }

    private var recentOperations: [Operation] {
        Array(operations.prefix(5))
    }

    private var recentIDs: [UUID] {
        recentOperations.map(\.id)
    }

    private func money(_ value: Decimal, sign: MoneyFormat.Sign = .none) -> String {
        settings.money(value, currency: displayCurrency, sign: sign)
    }
}

// MARK: - Rows

private struct AccountOverviewRow: View {
    @Environment(\.horizontalSizeClass) private var sizeClass

    let account: Account
    let share: Double?
    let converted: Decimal?
    let displayCurrency: Currency
    let masked: Bool
    let isEmphasized: Bool
    let isDimmed: Bool
    let onOpen: () -> Void
    let onNewOperation: () -> Void
    let onHover: (Bool) -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: onOpen) {
            HStack(spacing: AppStyle.Spacing.small) {
                ListRowIcon(symbol: account.iconName, color: account.color.color)

                VStack(alignment: .leading, spacing: AppStyle.Spacing.xxxSmall) {
                    Text(account.name)
                        .font(AppStyle.Typography.headline)
                        .lineLimit(1)
                    Text(figures: "\(account.currency.code) · \(Finance.operationsCountText(account.operationCount))\(account.isSavings ? String(localized: "common.savings_2") : "")",
                         style: AppStyle.Typography.callout)
                        .foregroundStyle(AppColors.textSecondary)
                        .lineLimit(1)
                }

                Spacer(minLength: AppStyle.Spacing.small)

                HStack(spacing: AppStyle.Spacing.small) {
                    // A phone row cannot hold the share, the balance and the
                    // account's metadata on one line; the share is the one figure
                    // Analytics also shows, so it is the one that makes way.
                    if let share, sizeClass != .compact {
                        Text(Finance.shareText(share))
                            .font(AppStyle.Typography.metadata.numbers)
                            .foregroundStyle(AppColors.textTertiary)
                            .lineLimit(1)
                    }

                    VStack(alignment: .trailing, spacing: 1) {
                        Text(MoneyFormat.string(account.balance, currency: account.currency, masked: masked))
                            .font(AppStyle.Typography.sectionTitle.numbers)
                            .monospacedDigit()
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                            .frame(minWidth: 64, alignment: .trailing)

                        if let converted {
                            Text("≈ \(MoneyFormat.string(converted, currency: displayCurrency, masked: masked))")
                                .font(AppStyle.Typography.metadata.numbers)
                                .monospacedDigit()
                                .lineLimit(1)
                                .minimumScaleFactor(0.7)
                                .foregroundStyle(AppColors.textTertiary)
                                .frame(minWidth: 64, alignment: .trailing)
                        } else {
                            // Keeps every row the same height whether or not it
                            // has an equivalent to show. Zero width, so the share
                            // stays next to the amount.
                            Color.clear.frame(width: 0, height: 13)
                        }
                    }
                }
                // The figures keep their size; a long account name truncates
                // first, which is what a narrow phone needs.
                .layoutPriority(1)
            }
            .padding(.horizontal, AppStyle.Row.cardHorizontalPadding)
            .padding(.vertical, AppStyle.Spacing.small)
            .background(
                isEmphasized || isHovering ? AppColors.fillSecondary.opacity(0.5) : .clear
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .opacity(isDimmed ? 0.4 : 1)
        .saturation(isDimmed ? 0 : 1)
        .animation(AppMotion.row, value: isHovering)
        .animation(AppMotion.row, value: isDimmed)
        .onHover { hovering in
            isHovering = hovering
            onHover(hovering)
        }
        .pointingHandOnHover()
        .modifier(AccountCardFramePublisher(accountID: account.id))
        .contextMenu {
            Button {
                onNewOperation()
            } label: {
                Label(String(localized: "transaction.new"), systemImage: "plus")
            }
            Button(action: onOpen) {
                Label(String(localized: "common.open_account"), systemImage: "arrow.up.forward.square")
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
    }
}

/// Publishes this account card's frame under `SidebarAccountFramesKey`, the
/// preference the onboarding hero flight reads. The sidebar does the same on the
/// Mac; on iOS the card in Overview is the flight's destination, so the landing
/// happens on the card the person can see instead of fading out. The value is
/// live, so a scroll, rotation or different window width cannot send the chip to
/// a stale spot.
private struct AccountCardFramePublisher: ViewModifier {
    let accountID: UUID

    func body(content: Content) -> some View {
        #if os(iOS)
        content.background {
            GeometryReader { proxy in
                Color.clear.preference(
                    key: SidebarAccountFramesKey.self,
                    value: [accountID: proxy.frame(in: .named(OnboardingHero.coordinateSpace))]
                )
            }
        }
        #else
        content
        #endif
    }
}

private struct PeriodSummaryRow: View {
    let period: Period?
    let daysLeft: Int
    let onOpen: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: onOpen) {
            HStack(spacing: AppStyle.Spacing.small) {
                ListRowIcon(symbol: "calendar", color: AppColors.Chart.blueTile)

                VStack(alignment: .leading, spacing: AppStyle.Spacing.xxxSmall) {
                    Text(String(localized: "common.current_period"))
                        .font(AppStyle.Typography.headline)
                    if let period {
                        Text(figures: String(localized: "period.time_left \(period.title) \(Finance.daysText(daysLeft))"),
                             style: AppStyle.Typography.callout)
                            .foregroundStyle(AppColors.textSecondary)
                            .lineLimit(1)
                    } else {
                        Text(String(localized: "overview.set_your_payday_in_settings"))
                            .font(AppStyle.Typography.callout)
                            .foregroundStyle(AppColors.textSecondary)
                    }
                }

                Spacer(minLength: AppStyle.Spacing.small)

                HStack(spacing: AppStyle.Spacing.xxSmall) {
                    Text(String(localized: "common.edit"))
                        .font(AppStyle.Typography.callout)
                        .foregroundStyle(AppColors.textSecondary)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(AppColors.textTertiary)
                }
            }
            .padding(.horizontal, AppStyle.Row.cardHorizontalPadding)
            .padding(.vertical, AppStyle.Spacing.small)
            .background(isHovering ? AppColors.fillSecondary.opacity(0.5) : .clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .pointingHandOnHover()
        .accessibilityLabel(String(localized: "overview.edit_the_current_period"))
    }
}

private struct PlainSummaryRow: View {
    let symbol: String
    let color: Color
    let title: String
    let detail: String
    let value: String
    var isEmphasized = false

    var body: some View {
        HStack(spacing: AppStyle.Spacing.small) {
            ListRowIcon(symbol: symbol, color: color)

            VStack(alignment: .leading, spacing: AppStyle.Spacing.xxxSmall) {
                Text(title)
                    .font(AppStyle.Typography.headline)
                Text(detail)
                    .font(AppStyle.Typography.callout)
                    .foregroundStyle(AppColors.textSecondary)
                    .lineLimit(1)
            }

            Spacer(minLength: AppStyle.Spacing.small)

            Text(value)
                .font(AppStyle.Typography.sectionTitle.numbers)
                .monospacedDigit()
                .foregroundStyle(AppColors.textPrimary)
                .frame(minWidth: 64, alignment: .trailing)
        }
        .padding(.horizontal, AppStyle.Row.cardHorizontalPadding)
        .padding(.vertical, AppStyle.Spacing.small)
        .accessibilityElement(children: .combine)
    }
}

private struct RecentOperationRow: View {
    let operation: Operation
    var isNew: Bool = false
    let masked: Bool
    let onOpen: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: onOpen) {
            HStack(spacing: AppStyle.Spacing.small) {
                ListRowIcon(
                    symbol: operation.displayIcon,
                    color: operation.displayColor
                )

                VStack(alignment: .leading, spacing: AppStyle.Spacing.xxxSmall) {
                    Text(operation.displayTitle)
                        .font(AppStyle.Typography.headline)
                        .lineLimit(1)
                    Text(operation.detailText)
                        .font(AppStyle.Typography.callout)
                        .foregroundStyle(AppColors.textSecondary)
                        .lineLimit(1)
                }

                Spacer(minLength: AppStyle.Spacing.small)

                VStack(alignment: .trailing, spacing: AppStyle.Spacing.xxxSmall) {
                    Text(operation.amountText(masked: masked))
                        .font(AppStyle.Typography.headline.numbers)
                        .monospacedDigit()
                        .foregroundStyle(operation.kind == .income ? AppColors.statusSafeText : AppColors.textPrimary)
                    Text(AppDate.short(operation.date))
                        .font(AppStyle.Typography.metadata)
                        .foregroundStyle(AppColors.textTertiary)
                }
            }
            .padding(.horizontal, AppStyle.Row.cardHorizontalPadding)
            .padding(.vertical, AppStyle.Spacing.small)
            .background {
                RoundedRectangle(cornerRadius: AppStyle.Radius.md, style: .continuous)
                    .fill(isNew
                          ? AppColors.fillSecondaryHover
                          : (isHovering ? AppColors.fillSecondary.opacity(0.5) : .clear))
                    .padding(.horizontal, AppStyle.Spacing.xxSmall)
                    .padding(.vertical, 2)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .animation(AppMotion.highlight, value: isNew)
        .pointingHandOnHover()
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
    }
}

// MARK: - Currency chip

private struct CurrencyChip: View {
    let currency: Currency
    let total: Decimal
    let isSelected: Bool
    let masked: Bool
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: AppStyle.Spacing.xxSmallPlus) {
                Text(currency.code)
                    .font(AppStyle.Typography.body.weight(isSelected ? .semibold : .regular))
                    .lineLimit(1)
                Text(MoneyFormat.string(total, currency: currency, masked: masked))
                    .font(AppStyle.Typography.metadata.numbers.weight(isSelected ? .medium : .regular))
                    .monospacedDigit()
                    .foregroundStyle(isSelected ? AppColors.textPrimary : AppColors.textTertiary)
                    .lineLimit(1)
            }
            .fixedSize(horizontal: true, vertical: false)
            .foregroundStyle(isSelected ? AppColors.textPrimary : AppColors.textSecondary)
            .padding(.horizontal, AppStyle.Spacing.small)
            .padding(.vertical, AppStyle.Spacing.xxSmallPlus)
            .background(background, in: Capsule(style: .continuous))
            .overlay {
                Capsule(style: .continuous)
                    .strokeBorder(isSelected ? AppColors.borderStrong : AppColors.borderSubtle, lineWidth: 1)
            }
            .contentShape(Capsule(style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .pointingHandOnHover()
        .accessibilityLabel("\(currency.code), \(MoneyFormat.string(total, currency: currency, masked: masked))")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var background: Color {
        if isSelected { return AppColors.surfaceRaised }
        return isHovering ? AppColors.fillSecondaryHover : AppColors.fillSecondary
    }
}

// MARK: - Balance bar

/// One bar for the money on screen. Segments are accounts, sized by their value in
/// the display currency; small ones keep a minimum width so a tiny wallet stays
/// visible. Hovering a segment lights its row, and the rest of the bar fades.
struct BalanceBar: View {
    struct Segment: Identifiable {
        let id: UUID
        let label: String
        let value: Double
        let color: Color
    }

    let segments: [Segment]
    var highlightedID: UUID?
    var onHover: (UUID?) -> Void = { _ in }

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let height: CGFloat = 14
    private static let fadedOpacity: Double = 0.3
    private static let gap: CGFloat = AppStyle.Spacing.xxxSmall
    private static let minimumWidth: CGFloat = 4

    var body: some View {
        GeometryReader { geometry in
            let layout = Self.layout(for: segments.map(\.value), in: geometry.size.width)
            ZStack(alignment: .leading) {
                // Only when nothing is positive: a quiet track instead of an
                // invisible bar. Otherwise the colored segments are the bar.
                if segments.allSatisfy({ $0.value <= 0 }) {
                    Capsule(style: .continuous)
                        .fill(AppColors.fillSecondary)
                }

                // Plain rectangles, as in the reference: the capsule clip rounds
                // only the two outer ends, so neighbours meet like one bar rather
                // than a row of pills.
                ForEach(Array(segments.enumerated()), id: \.element.id) { index, segment in
                    Rectangle()
                        .fill(segment.color)
                        .frame(width: layout[index].width, height: Self.height)
                        .opacity(highlightedID == nil || highlightedID == segment.id ? 1 : Self.fadedOpacity)
                        .offset(x: layout[index].x)
                }
            }
            .frame(width: geometry.size.width, height: Self.height, alignment: .leading)
            .clipShape(Capsule(style: .continuous))
            .animation(reduceMotion ? nil : AppMotion.bar, value: layout)
            .contentShape(Rectangle())
            .onContinuousHover { phase in
                switch phase {
                case .active(let location):
                    onHover(Self.segmentID(at: location.x, in: layout).map { segments[$0].id })
                case .ended:
                    onHover(nil)
                }
            }
        }
        .frame(height: Self.height)
        .accessibilityElement()
        .accessibilityLabel(accessibilityText)
    }

    private var accessibilityText: String {
        segments
            .map { "\($0.label) \(MoneyFormat.number(Decimal($0.value)))" }
            .joined(separator: ", ")
    }

    private static func segmentID(at x: CGFloat, in layout: [Placement]) -> Int? {
        let visible = layout.indices.filter { layout[$0].width > 0 }
        if let hit = visible.first(where: { x >= layout[$0].x && x <= layout[$0].x + layout[$0].width }) {
            return hit
        }
        return visible.min { distance(x, to: layout[$0]) < distance(x, to: layout[$1]) }
    }

    private static func distance(_ x: CGFloat, to placement: Placement) -> CGFloat {
        x < placement.x ? placement.x - x : x - (placement.x + placement.width)
    }

    struct Placement: Equatable {
        let x: CGFloat
        let width: CGFloat
    }

    static func layout(for values: [Double], in totalWidth: CGFloat) -> [Placement] {
        let visibleIndices = values.indices.filter { values[$0] > 0 }
        let visibleWidths = widths(for: visibleIndices.map { values[$0] }, in: totalWidth)
        var placements: [Placement] = []
        placements.reserveCapacity(values.count)
        var x: CGFloat = 0
        var visibleIndex = 0
        for index in values.indices {
            guard values[index] > 0 else {
                placements.append(Placement(x: x, width: 0))
                continue
            }
            if visibleIndex > 0 { x += gap }
            let width = visibleWidths[visibleIndex]
            placements.append(Placement(x: x, width: width))
            x += width
            visibleIndex += 1
        }
        return placements
    }

    static func widths(for values: [Double], in totalWidth: CGFloat) -> [CGFloat] {
        guard !values.isEmpty else { return [] }
        let available = max(0, totalWidth - gap * CGFloat(values.count - 1))
        let sum = values.reduce(0, +)
        guard sum > 0 else { return values.map { _ in 0 } }
        var widths = values.map { max(minimumWidth, available * CGFloat($0) / CGFloat(sum)) }
        let overflow = widths.reduce(0, +) - available
        if overflow > 0, let largest = widths.indices.max(by: { widths[$0] < widths[$1] }) {
            widths[largest] = max(minimumWidth, widths[largest] - overflow)
        }
        return widths
    }
}
