import SwiftData
import SwiftUI

/// The About page in the reference's shape: a centred mark and version, one big
/// figure, a list of what the app does, and a single action — replaying the
/// welcome flow.
struct AboutView: View {
    private static let contentMaxWidth: CGFloat = 560

    @EnvironmentObject private var settings: SettingsStore
    @EnvironmentObject private var headerHost: DetailHeaderHost
    @EnvironmentObject private var rates: RateStore

    @Query(sort: [SortDescriptor(\Account.sortIndex, order: .forward)]) private var accounts: [Account]
    @Query private var operations: [Operation]

    let onReplayOnboarding: () -> Void

    private var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
    }

    private var total: Decimal {
        Finance.totalConverted(accounts, to: settings.primaryCurrency, rates: rates.rates)
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: AppStyle.Spacing.large) {
                    identity
                    replayCard
                    summaryCard
                    capabilitiesCard
                    footer
                }
                .frame(maxWidth: Self.contentMaxWidth)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, AppDetailPageLayout.horizontalInset)
                .padding(.bottom, AppStyle.Spacing.large)
            }
        }
        .background(AppColors.surfaceBase)
        .onAppear { syncHeader() }
    }

    private func syncHeader() {
        headerHost.config = DetailHeaderConfig(
            title: String(localized: "common.about"),
            subtitle: String(localized: "about.version_data_and_onboarding"),
            backTitle: nil,
            onBack: nil,
            trailing: AnyView(EmptyView())
        )
    }

    private var identity: some View {
        VStack(spacing: AppStyle.Spacing.small) {
            MontraArtwork(size: 52)

            Text(String(localized: "common.montra"))
                .font(AppStyle.Typography.title)
                .padding(.top, AppStyle.Spacing.xxSmall)

            Text(String(localized: "about.version \(version)"))
                .font(AppStyle.Typography.metadata)
                .foregroundStyle(AppColors.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, AppStyle.Spacing.xxSmall)
    }

    private var replayCard: some View {
        InsetCard {
            ReplayOnboardingRow(action: onReplayOnboarding)
        }
    }

    private var summaryCard: some View {
        InsetCard {
            VStack(spacing: AppStyle.Spacing.small) {
                Text(String(localized: "about.total_across_accounts"))
                    .font(AppStyle.Typography.metadataEmphasis)
                    .tracking(0.6)
                    .foregroundStyle(AppColors.textSecondary)

                Text(settings.money(total, currency: settings.primaryCurrency))
                    .font(AppStyle.Typography.display.numbers)
                    .monospacedDigit()
                    .contentTransition(.numericText())

                HStack(spacing: AppStyle.Spacing.xxSmallPlus) {
                    Image(systemName: "arrow.up.right")
                        .font(.system(size: 11, weight: .semibold))
                    Text("\(Finance.accountsCountText(accounts.count)) · \(Finance.operationsCountText(operations.count))")
                }
                .font(AppStyle.Typography.callout)
                .foregroundStyle(AppColors.textSecondary)
                .padding(.horizontal, AppStyle.Spacing.small)
                .padding(.vertical, AppStyle.Spacing.xxSmallPlus)
                .background(AppColors.surfaceRaised, in: Capsule(style: .continuous))
                .overlay {
                    Capsule(style: .continuous)
                        .strokeBorder(AppColors.borderStrong, lineWidth: 1)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, AppStyle.Spacing.medium)
        }
    }

    private var capabilitiesCard: some View {
        InsetCard {
            VStack(alignment: .leading, spacing: AppStyle.Spacing.medium) {
                Text(String(localized: "about.what_montra_can_do"))
                    .font(AppStyle.Typography.metadataEmphasis)
                    .tracking(0.6)
                    .foregroundStyle(AppColors.textSecondary)

                capability(
                    symbol: "creditcard",
                    title: String(localized: "about.accounts_in_multiple_currencies"),
                    detail: String(localized: "about.track_byn_eur_usd_usdc")
                )
                capability(
                    symbol: "calendar",
                    title: String(localized: "common.financial_month"),
                    detail: String(localized: "about.track_money_from_payday_to")
                )
                capability(
                    symbol: "magnifyingglass",
                    title: String(localized: "about.transactions_and_search"),
                    detail: String(localized: "about.use_categories_places_and_notes")
                )

                Text(String(localized: "about.your_data_stays_on_this"))
                    .font(AppStyle.Typography.callout)
                    .foregroundStyle(AppColors.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, AppStyle.Spacing.xxxSmall)
            }
            .padding(.horizontal, AppStyle.Spacing.medium)
            .padding(.vertical, AppStyle.Spacing.medium)
        }
    }

    private func capability(symbol: String, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: AppStyle.Spacing.small) {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(AppColors.textSecondary)
                .frame(width: 18, alignment: .leading)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: AppStyle.Spacing.xxxSmall) {
                Text(title)
                    .font(AppStyle.Typography.headline)
                Text(detail)
                    .font(AppStyle.Typography.callout)
                    .foregroundStyle(AppColors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var footer: some View {
        VStack(spacing: AppStyle.Spacing.xxxSmall) {
            Text(String(localized: "about.built_with_swiftui_and_swiftdata"))
            Text(String(localized: "about.version \(version)"))
        }
        .font(AppStyle.Typography.metadata)
        .foregroundStyle(AppColors.textTertiary)
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity)
        .padding(.top, AppStyle.Spacing.xxSmall)
    }
}

private struct ReplayOnboardingRow: View {
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: AppStyle.Spacing.small) {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(AppColors.textSecondary)
                    .frame(width: 18, alignment: .leading)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: AppStyle.Spacing.xxxSmall) {
                    Text(String(localized: "common.replay_onboarding"))
                        .font(AppStyle.Typography.headline)
                    Text(String(localized: "about.start_from_the_beginning_without"))
                        .font(AppStyle.Typography.callout)
                        .foregroundStyle(AppColors.textSecondary)
                }

                Spacer(minLength: AppStyle.Spacing.small)

                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(AppColors.textTertiary)
            }
            .padding(.horizontal, AppStyle.Spacing.medium)
            .padding(.vertical, AppStyle.Spacing.xSmall)
            .background(isHovering ? AppColors.fillSecondary.opacity(0.5) : .clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .pointingHandOnHover()
        .accessibilityLabel(String(localized: "common.replay_onboarding"))
    }
}
