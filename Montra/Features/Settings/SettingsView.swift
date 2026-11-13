import SwiftData
import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var settings: SettingsStore
    @EnvironmentObject private var sync: SyncService
    @EnvironmentObject private var headerHost: DetailHeaderHost
    @EnvironmentObject private var rates: RateStore
    @EnvironmentObject private var integration: LocalIntegration
    @Environment(\.modelContext) private var context

    @Query(sort: [SortDescriptor(\Period.start, order: .forward)]) private var periods: [Period]
    @Query private var operations: [Operation]

    let onOpenPeriods: () -> Void
    let onOpenICloud: () -> Void
    let onDataCleared: () -> Void
    let onDataRestored: () -> Void

    @State private var pendingAction: PendingAction?
    @State private var pendingRestore: BackupRestoreCandidate?

    private enum PendingAction: String, Identifiable {
        case clearAll

        var id: String { rawValue }
    }

    private var currentPeriod: Period? {
        PeriodService.currentPeriod(in: periods)
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: AppStyle.Spacing.medium) {
                    generalGroup
                    integrationGroup
                    periodGroup
                    ratesGroup
                    backupGroup
                    dataGroup
                    aboutGroup
                }
                .padding(.horizontal, AppDetailPageLayout.horizontalInset)
                .padding(.bottom, AppStyle.Spacing.large)
            }
        }
        .background(AppColors.surfaceBase)
        .onAppear { syncHeader() }
        .sheet(item: $pendingRestore) { candidate in
            BackupRestoreSheet(candidate: candidate, onRestored: onDataRestored)
                .environmentObject(settings)
                .environmentObject(rates)
                .environmentObject(integration)
        }
        .alert(String(localized: "settings.delete_all_data"), isPresented: isPresented(.clearAll)) {
            Button(String(localized: "common.delete_all"), role: .destructive) {
                SeedData.clearEverything(context: context, settings: settings)
                onDataCleared()
            }
            Button(String(localized: "common.cancel"), role: .cancel) {}
        } message: {
            Text(String(localized: "settings.accounts_transactions_scheduled_payments_and"))
        }
    }

    private func isPresented(_ action: PendingAction) -> Binding<Bool> {
        Binding(
            get: { pendingAction == action },
            set: { if !$0 { pendingAction = nil } }
        )
    }

    // MARK: - Groups

    private func syncHeader() {
        headerHost.config = DetailHeaderConfig(
            title: String(localized: "navigation.settings"),
            subtitle: String(localized: "settings.appearance_financial_period_and_data"),
            backTitle: nil,
            onBack: nil,
            trailing: AnyView(EmptyView())
        )
    }

    private var generalGroup: some View {
        group(String(localized: "common.general")) {
            toggleRow(
                title: String(localized: "common.hide_amounts"),
                caption: String(localized: "settings.replaces_balances_and_transaction_amounts"),
                isOn: $settings.hideBalances
            )

            divider

            controlRow(title: String(localized: "common.appearance")) {
                HStack(alignment: .top, spacing: AppStyle.Spacing.medium) {
                    ForEach(SettingsStore.Appearance.allCases) { appearance in
                        AppearanceOptionButton(
                            appearance: appearance,
                            isSelected: settings.appearance == appearance
                        ) {
                            settings.appearance = appearance
                        }
                    }
                }
            }
        }
    }

    private var integrationGroup: some View {
        group(String(localized: "common.integration")) {
            toggleRow(
                title: String(localized: "common.local_api"),
                caption: integrationStatus,
                isOn: Binding(
                    get: { integration.enabled },
                    set: { integration.setEnabled($0, onboardingComplete: settings.hasCompletedOnboarding) }
                )
            )
            .disabled(!integration.available || !settings.hasCompletedOnboarding)

            divider

            controlRow(title: String(localized: "common.api_token"), caption: String(localized: "settings.use_it_to_connect_another")) {
                Button(String(localized: "common.copy_token")) { integration.copyToken() }
                    .buttonStyle(.montra(.secondary, size: .small))
                    .disabled(!integration.active)
            }

            divider

            toggleRow(
                title: String(localized: "app.allow_deletion_via_api"),
                caption: String(localized: "settings.accounts_transactions_and_scheduled_payments"),
                isOn: $integration.allowDelete
            )
            .disabled(!integration.active)
        }
    }

    private var integrationStatus: String {
        if !integration.available { return String(localized: "settings.unavailable_in_this_mode") }
        if !settings.hasCompletedOnboarding { return String(localized: "settings.finish_setting_up_the_app") }
        if let failure = integration.failure { return failure }
        if integration.active { return String(localized: "integration.api_address \(String(LocalHTTPServer.port))") }
        return integration.enabled ? String(localized: "common.starting") : String(localized: "settings.access_for_other_apps_on")
    }

    private var periodGroup: some View {
        group(String(localized: "common.financial_period")) {
            controlRow(
                title: String(localized: "period.how_to_calculate_the_period"),
                caption: settings.periodMode == .payday
                    ? String(localized: "settings.payday_to_payday_you_can")
                    : String(localized: "settings.each_period_lasts_a_fixed")
            ) {
                DropdownMenu(
                    options: SettingsStore.PeriodMode.allCases,
                    selection: settings.periodMode,
                    selectionLabel: settings.periodMode.title,
                    optionLabel: { $0.title },
                    onSelect: { settings.periodMode = $0 }
                )
            }

            divider

            if settings.periodMode == .payday {
                controlRow(
                    title: String(localized: "common.payday"),
                    caption: String(localized: "settings.if_the_month_is_shorter")
                ) {
                    NumberStepper(
                        value: $settings.paydayDay,
                        range: 1...31,
                        label: dayLabel,
                        suffix: { _ in String(localized: "period.payday_suffix") },
                        accessibilityTitle: String(localized: "common.payday")
                    )
                }
            } else {
                controlRow(
                    title: String(localized: "common.period_length"),
                    caption: String(localized: "settings.counting_starts_from_the_date")
                ) {
                    NumberStepper(
                        value: $settings.fixedLengthDays,
                        range: 1...90,
                        label: { Finance.daysText($0) },
                        suffix: { Finance.daysSuffix($0) },
                        accessibilityTitle: String(localized: "common.period_length")
                    )
                }
            }

            divider

            linkRow(
                title: String(localized: "common.periods"),
                caption: String(localized: "settings.adjust_periods_by_month"),
                value: currentPeriod?.title ?? String(localized: "common.not_set_2")
            ) {
                onOpenPeriods()
            }
        }
    }

    private var ratesGroup: some View {
        group(String(localized: "common.exchange_rates")) {
            controlRow(
                title: String(localized: "common.source"),
                caption: String(localized: "settings.usd_and_eur_rates_come")
            ) {
                AppBadge(
                    text: rates.rates.source.title,
                    tone: rates.rates.source == .nbrb
                        ? .safe
                        : (rates.rates.source.isApproximate ? .warning : .accent)
                )
            }

            divider

            ForEach([Currency.usd, .eur, .usdt, .btc, .eth]) { currency in
                if let rate = rates.rateText(for: currency) {
                    plainRow(title: currency.code, value: rate)
                    divider
                }
            }

            HStack(alignment: .center, spacing: AppStyle.Spacing.medium) {
                VStack(alignment: .leading, spacing: AppStyle.Spacing.xxxSmall) {
                    Text(String(localized: "common.updated"))
                        .font(AppStyle.Typography.body)
                    Text(rates.lastError ?? rateStatusCaption)
                        .font(AppStyle.Typography.callout)
                        .foregroundStyle(rates.lastError == nil ? AppColors.textSecondary : AppColors.statusCheckText)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Button {
                    Task { await rates.refresh() }
                } label: {
                    if rates.isRefreshing {
                        ProgressView()
                            .controlSize(.small)
                            .scaleEffect(0.7)
                    } else {
                        Label(String(localized: "common.refresh"), systemImage: "arrow.clockwise")
                    }
                }
                .buttonStyle(.montra(.secondary, size: .small))
                .disabled(rates.isRefreshing)
            }
            .padding(.horizontal, AppStyle.Spacing.medium)
            .padding(.vertical, AppStyle.Spacing.small)
        }
    }

    private var rateStatusCaption: String {
        if rates.rates.source == .currencyAPI {
            return String(localized: "settings.the_national_bank_of_belarus \(rates.updatedText)")
        }
        return rates.updatedText
    }

    private var backupGroup: some View {
        group(String(localized: "backup.title")) {
            linkRow(
                title: String(localized: "backup.save"),
                caption: String(localized: "backup.save_caption"),
                value: lastBackupText
            ) {
                saveBackup()
            }

            divider

            linkRow(
                title: String(localized: "backup.restore"),
                caption: String(localized: "backup.restore_caption"),
                value: String(localized: "backup.choose_file")
            ) {
                chooseBackup()
            }
        }
    }

    private var lastBackupText: String {
        guard let date = settings.lastBackupAt else { return String(localized: "backup.never_saved") }
        return AppDate.dayMonthTime.string(from: date)
    }

    private var backupEnvironment: BackupService.Environment {
        BackupService.Environment(
            rates: rates.rates,
            integrationEnabled: integration.enabled,
            integrationAllowsDelete: integration.allowDelete
        )
    }

    private func saveBackup() {
        do {
            let backup = try BackupService.capture(
                context: context,
                settings: settings,
                environment: backupEnvironment
            )
            guard let url = try BackupFile.export(backup) else { return }
            settings.lastBackupAt = .now
            BackupFile.confirmSave(url)
        } catch {
            BackupFile.presentError(error, title: String(localized: "backup.error.save_title"))
        }
    }

    private func chooseBackup() {
        do {
            guard let picked = try BackupFile.chooseArchive() else { return }
            pendingRestore = BackupRestoreCandidate(
                archive: picked.backup,
                fileName: picked.url.lastPathComponent
            )
        } catch {
            BackupFile.presentError(error, title: String(localized: "backup.error.open_title"))
        }
    }

    private var dataGroup: some View {
        group(String(localized: "common.data")) {
            controlRow(
                title: String(localized: "common.primary_currency"),
                caption: String(localized: "settings.used_to_calculate_the_total")
            ) {
                DropdownMenu(
                    options: Currency.allCases,
                    selection: settings.primaryCurrency,
                    selectionLabel: settings.primaryCurrency.code,
                    optionLabel: { $0.code },
                    onSelect: { settings.primaryCurrency = $0 }
                )
            }

            divider

            linkRow(
                title: String(localized: "common.icloud_sync"),
                caption: String(localized: "sync.settings_caption"),
                value: sync.appearance.compact
            ) {
                onOpenICloud()
            }

            divider

            linkRow(
                title: String(localized: "common.export_transactions"),
                caption: String(localized: "settings.export_all_transactions_as_a"),
                value: "\(operations.count)"
            ) {
                CSVExporter.export(operations)
            }

            divider

            actionRow(
                title: String(localized: "settings.delete_all_data_2"),
                caption: String(localized: "settings.keep_only_the_built_in"),
                value: String(localized: "common.delete"),
                isDestructive: true
            ) {
                pendingAction = .clearAll
            }
        }
    }

    private var aboutGroup: some View {
        group(String(localized: "common.about_2")) {
            plainRow(title: String(localized: "common.version"), value: "1.0")
            divider
            plainRow(title: String(localized: "common.storage"), value: String(localized: "settings.swiftdata_on_this_mac"))
        }
    }

    // MARK: - Building blocks

    private func group<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: AppStyle.Spacing.xxSmallPlus) {
            Text(title)
                .font(AppStyle.Typography.metadataEmphasis)
                .foregroundStyle(AppColors.textSecondary)
                .padding(.horizontal, AppStyle.Spacing.xxSmall)
                .accessibilityAddTraits(.isHeader)
            InsetCard(content: content)
        }
    }

    private var divider: some View {
        InsetCardDivider()
    }

    private func rowLabel(title: String, caption: String?, info: String? = nil) -> some View {
        VStack(alignment: .leading, spacing: AppStyle.Spacing.xxxSmall) {
            HStack(spacing: AppStyle.Spacing.xxSmallPlus) {
                Text(title)
                    .font(AppStyle.Typography.body)
                if let info {
                    InfoButton(title: title, text: info)
                }
            }
            if let caption {
                Text(caption)
                    .font(AppStyle.Typography.callout)
                    .foregroundStyle(AppColors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func toggleRow(title: String, caption: String?, info: String? = nil, isOn: Binding<Bool>) -> some View {
        HStack(alignment: .center, spacing: AppStyle.Spacing.medium) {
            rowLabel(title: title, caption: caption, info: info)
            Toggle("", isOn: isOn)
                .labelsHidden()
                .toggleStyle(.montraSwitch)
                .accessibilityLabel(title)
        }
        .padding(.horizontal, AppStyle.Spacing.medium)
        .padding(.vertical, AppStyle.Spacing.small)
    }

    private func controlRow<Control: View>(
        title: String,
        caption: String? = nil,
        info: String? = nil,
        @ViewBuilder control: () -> Control
    ) -> some View {
        HStack(alignment: .center, spacing: AppStyle.Spacing.medium) {
            rowLabel(title: title, caption: caption, info: info)
            control()
        }
        .padding(.horizontal, AppStyle.Spacing.medium)
        .padding(.vertical, AppStyle.Spacing.small)
    }

    private func linkRow(
        title: String,
        caption: String? = nil,
        value: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(alignment: .center, spacing: AppStyle.Spacing.small) {
                VStack(alignment: .leading, spacing: AppStyle.Spacing.xxxSmall) {
                    Text(title)
                        .font(AppStyle.Typography.body)
                    if let caption {
                        Text(caption)
                            .font(AppStyle.Typography.callout)
                            .foregroundStyle(AppColors.textSecondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Text(figures: value, style: AppStyle.Typography.callout)
                    .foregroundStyle(AppColors.textSecondary)
                    .lineLimit(1)

                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(AppColors.textTertiary)
            }
            .padding(.horizontal, AppStyle.Spacing.medium)
            .padding(.vertical, AppStyle.Spacing.small)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .pointingHandOnHover()
        .accessibilityLabel("\(title), \(value)")
    }

    private func actionRow(
        title: String,
        caption: String? = nil,
        value: String,
        isDestructive: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(alignment: .center, spacing: AppStyle.Spacing.small) {
                VStack(alignment: .leading, spacing: AppStyle.Spacing.xxxSmall) {
                    Text(title)
                        .font(AppStyle.Typography.body)
                        .foregroundStyle(isDestructive ? AppColors.statusDangerText : AppColors.textPrimary)
                    if let caption {
                        Text(caption)
                            .font(AppStyle.Typography.callout)
                            .foregroundStyle(AppColors.textSecondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Text(value)
                    .font(AppStyle.Typography.callout.weight(.semibold))
                    .foregroundStyle(isDestructive ? AppColors.statusDangerText : AppColors.textPrimary)
                    .padding(.horizontal, AppStyle.Spacing.small)
                    .frame(height: 24)
                    .background(AppColors.fillSecondary, in: Capsule(style: .continuous))
                    .overlay {
                        Capsule(style: .continuous)
                            .strokeBorder(AppColors.borderStrong, lineWidth: 1)
                    }
            }
            .padding(.horizontal, AppStyle.Spacing.medium)
            .padding(.vertical, AppStyle.Spacing.small)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .pointingHandOnHover()
    }

    private func plainRow(title: String, value: String) -> some View {
        HStack(spacing: AppStyle.Spacing.small) {
            Text(title)
                .font(AppStyle.Typography.body)
            Spacer(minLength: AppStyle.Spacing.small)
            Text(value)
                .font(AppStyle.Typography.callout)
                .foregroundStyle(AppColors.textSecondary)
        }
        .padding(.horizontal, AppStyle.Spacing.medium)
        .padding(.vertical, AppStyle.Spacing.small)
    }

    private func dayLabel(_ day: Int) -> String {
        String(localized: "period.payday_ordinal \(day)")
    }
}

// MARK: - Appearance thumbnails

private struct AppearanceOptionButton: View {
    let appearance: SettingsStore.Appearance
    let isSelected: Bool
    let action: () -> Void

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: AppStyle.Radius.sm, style: .continuous)
    }

    var body: some View {
        Button(action: action) {
            VStack(spacing: AppStyle.Spacing.xSmall) {
                thumbnail
                    .overlay { shape.strokeBorder(AppColors.borderStrong, lineWidth: 0.5) }
                    .overlay {
                        if isSelected {
                            shape.inset(by: -3)
                                .strokeBorder(AppColors.textPrimary, lineWidth: 2)
                        }
                    }

                Text(appearance.title)
                    .font(AppStyle.Typography.metadata.weight(isSelected ? .semibold : .regular))
                    .foregroundStyle(isSelected ? AppColors.textPrimary : AppColors.textSecondary)
            }
        }
        .buttonStyle(.plain)
        .animation(.easeOut(duration: 0.15), value: isSelected)
        .accessibilityLabel(String(localized: "settings.appearance \(appearance.title)"))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var thumbnail: some View {
        Group {
            switch appearance {
            case .dark:
                MiniWindow(isDark: true)
            case .light:
                MiniWindow(isDark: false)
            case .auto:
                ZStack {
                    MiniWindow(isDark: true)
                    MiniWindow(isDark: false)
                        .mask {
                            GeometryReader { geometry in
                                HStack(spacing: 0) {
                                    Rectangle().frame(width: geometry.size.width * 0.5)
                                    Color.clear
                                }
                            }
                        }
                }
            }
        }
        .frame(width: 64, height: 44)
        .clipShape(shape)
    }
}

/// A 64×44 sketch of the app window: sidebar, traffic lights, a title and two
/// cards with a tile. Enough detail to tell light from dark at a glance.
private struct MiniWindow: View {
    let isDark: Bool

    private var background: Color { isDark ? Color(hex: 0x171615) : Color(hex: 0xF6F5F3) }
    private var sidebar: Color { isDark ? Color(hex: 0x1E1D1C) : Color(hex: 0xFFFFFF) }
    private var card: Color { isDark ? Color(hex: 0x2B2A28) : Color(hex: 0xEFEDEA) }
    private var cardBorder: Color { isDark ? Color(hex: 0x353330) : Color(hex: 0xE2DFDA) }
    private var ink: Color { isDark ? Color(hex: 0xECEAE6) : Color(hex: 0x2E2D2B) }
    private var tile: Color { Color(hex: 0x3A94D0) }

    var body: some View {
        HStack(spacing: 0) {
            sidebar
                .frame(width: 18)
                .overlay(alignment: .topLeading) {
                    HStack(spacing: 1.5) {
                        Circle().fill(Color(hex: 0xFF5F57))
                        Circle().fill(Color(hex: 0xFEBC2E))
                        Circle().fill(Color(hex: 0x28C840))
                    }
                    .frame(width: 12)
                    .padding(.top, 3)
                    .padding(.leading, 3)
                }
                .overlay(alignment: .topLeading) {
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(0..<4, id: \.self) { index in
                            Capsule()
                                .fill(ink.opacity(index == 0 ? 0.75 : 0.35))
                                .frame(width: index == 0 ? 10 : 8, height: 1.5)
                                .padding(.leading, 3)
                        }
                    }
                    .padding(.top, 12)
                }

            VStack(alignment: .leading, spacing: 5) {
                capsBar(width: 20, height: 3, color: ink.opacity(0.85))
                cardRow(filled: true)
                cardRow(filled: false)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 5)
            .padding(.top, 5)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(background)
    }

    private func cardRow(filled: Bool) -> some View {
        HStack(spacing: 3) {
            RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                .fill(filled ? tile : tile.opacity(0.5))
                .frame(width: 7, height: 7)
            VStack(alignment: .leading, spacing: 1.5) {
                capsBar(width: 14, height: 1.6, color: ink.opacity(0.55))
                capsBar(width: 22, height: 1.2, color: ink.opacity(0.25))
            }
        }
        .padding(3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 3, style: .continuous)
                .fill(card)
                .overlay {
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .strokeBorder(cardBorder, lineWidth: 0.5)
                }
        )
    }

    private func capsBar(width: CGFloat, height: CGFloat, color: Color) -> some View {
        Capsule().fill(color).frame(width: width, height: height)
    }
}

private extension Color {
    init(hex: UInt32) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: 1
        )
    }
}
