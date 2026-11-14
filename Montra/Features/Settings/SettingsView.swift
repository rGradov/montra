import SwiftData
import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var settings: SettingsStore
    @EnvironmentObject private var headerHost: DetailHeaderHost
    @EnvironmentObject private var rates: RateStore
    @EnvironmentObject private var integration: LocalIntegration
    @Environment(\.modelContext) private var context
    #if os(iOS)
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    #endif

    @Query(sort: [SortDescriptor(\Period.start, order: .forward)]) private var periods: [Period]
    @Query private var operations: [Operation]

    let onOpenPeriods: () -> Void
    let onOpenICloud: () -> Void
    let onOpenAbout: () -> Void
    let onDataCleared: () -> Void
    let onDataRestored: () -> Void

    @State private var pendingAction: PendingAction?
    @State private var pendingRestore: BackupRestoreCandidate?

    #if os(iOS)
    // iOS has no save/open panels: backups go through SwiftUI's file exporter and
    // importer, and the CSV through the system share sheet.
    @State private var exportDocument: BackupDocument?
    @State private var isExportingBackup = false
    @State private var isImportingBackup = false
    @State private var sharedCSV: SharedFile?
    @State private var notice: BackupNotice?
    #endif

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
                    // The Local API and the MCP bridge are macOS features: an iOS
                    // app cannot expose a useful loopback server, so the group is
                    // absent instead of permanently unavailable.
                    if AppPlatform.supportsLocalIntegration {
                        integrationGroup
                    }
                    periodGroup
                    ratesGroup
                    backupGroup
                    dataGroup
                    aboutGroup
                }
                .platformReadableWidth()
                .padding(.horizontal, AppDetailPageLayout.horizontalInset)
                .padding(.bottom, AppStyle.Spacing.large)
            }
            #if os(iOS)
            .sheet(item: $sharedCSV) { file in
                ActivityShareSheet(items: [file.url])
            }
            #endif
        }
        .background(AppColors.surfaceBase)
        .onAppear { syncHeader() }
        .sheet(item: $pendingRestore) { candidate in
            BackupRestoreSheet(candidate: candidate, onRestored: onDataRestored)
                .environmentObject(settings)
                .environmentObject(rates)
                .environmentObject(integration)
                #if os(iOS)
                .restoreSheetPresentation()
                #endif
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
        #if os(iOS)
        .fileExporter(
            isPresented: $isExportingBackup,
            document: exportDocument,
            contentType: BackupFile.contentType,
            defaultFilename: BackupFile.suggestedName(),
            onCompletion: handleBackupExport
        )
        .fileImporter(
            isPresented: $isImportingBackup,
            allowedContentTypes: [BackupFile.contentType],
            allowsMultipleSelection: false,
            onCompletion: handleBackupImport
        )
        .alert(
            notice?.title ?? "",
            isPresented: Binding(get: { notice != nil }, set: { if !$0 { notice = nil } })
        ) {
            Button(String(localized: "common.ok"), role: .cancel) { notice = nil }
        } message: {
            Text(notice?.message ?? "")
        }
        .task { prepareRestorePreviewIfRequested() }
        #endif
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

            appearanceRow
        }
    }

    /// Three 64pt thumbnails and a label do not share one row on a phone: the
    /// label wins the space and the captions wrap one letter per line. At compact
    /// width the choices span a row of their own under the label.
    @ViewBuilder
    private var appearanceRow: some View {
        #if os(iOS)
        if horizontalSizeClass == .compact {
            VStack(alignment: .leading, spacing: AppStyle.Spacing.small) {
                rowLabel(title: String(localized: "common.appearance"), caption: nil)
                appearanceOptions
            }
            .padding(.horizontal, AppStyle.Spacing.medium)
            .padding(.vertical, rowVerticalPadding)
        } else {
            regularAppearanceRow
        }
        #else
        regularAppearanceRow
        #endif
    }

    private var regularAppearanceRow: some View {
        controlRow(title: String(localized: "common.appearance")) {
            appearanceOptions
        }
    }

    private var appearanceOptions: some View {
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
            .padding(.vertical, rowVerticalPadding)
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
        #if os(iOS)
        do {
            let backup = try BackupService.capture(
                context: context,
                settings: settings,
                environment: backupEnvironment
            )
            exportDocument = BackupFile.document(for: backup)
            isExportingBackup = true
        } catch {
            notice = BackupNotice(
                title: String(localized: "backup.error.save_title"),
                message: error.localizedDescription
            )
        }
        #else
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
        #endif
    }

    private func chooseBackup() {
        #if os(iOS)
        isImportingBackup = true
        #else
        do {
            guard let picked = try BackupFile.chooseArchive() else { return }
            pendingRestore = BackupRestoreCandidate(
                archive: picked.backup,
                fileName: picked.url.lastPathComponent
            )
        } catch {
            BackupFile.presentError(error, title: String(localized: "backup.error.open_title"))
        }
        #endif
    }

    #if os(iOS)
    private func handleBackupExport(_ result: Result<URL, Error>) {
        exportDocument = nil
        switch result {
        case .success:
            settings.lastBackupAt = .now
            notice = BackupNotice(
                title: String(localized: "backup.saved_title"),
                message: String(localized: "backup.save_caption")
            )
        case .failure(let error):
            guard !Self.isUserCancelled(error) else { return }
            notice = BackupNotice(
                title: String(localized: "backup.error.save_title"),
                message: error.localizedDescription
            )
        }
    }

    private func handleBackupImport(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }
            // The picker hands back a security-scoped URL; the read happens here,
            // while the scope is open.
            let isScoped = url.startAccessingSecurityScopedResource()
            defer { if isScoped { url.stopAccessingSecurityScopedResource() } }
            do {
                let picked = try BackupFile.readArchive(from: url)
                pendingRestore = BackupRestoreCandidate(
                    archive: picked.backup,
                    fileName: picked.url.lastPathComponent
                )
            } catch {
                notice = BackupNotice(
                    title: String(localized: "backup.error.open_title"),
                    message: error.localizedDescription
                )
            }
        case .failure(let error):
            guard !Self.isUserCancelled(error) else { return }
            notice = BackupNotice(
                title: String(localized: "backup.error.open_title"),
                message: error.localizedDescription
            )
        }
    }

    private func exportTransactions() {
        do {
            sharedCSV = SharedFile(url: try CSVExporter.temporaryFileURL(for: operations))
        } catch {
            notice = BackupNotice(
                title: String(localized: "export.couldnt_save_the_file"),
                message: error.localizedDescription
            )
        }
    }

    private static func isUserCancelled(_ error: Error) -> Bool {
        let nsError = error as NSError
        return nsError.domain == NSCocoaErrorDomain && nsError.code == NSUserCancelledError
    }

    /// `-qa-sheet restore` screenshots the restore sheet: it needs a decoded
    /// backup, which the demo store can produce on demand.
    private func prepareRestorePreviewIfRequested() {
        #if DEBUG
        guard QAFixtures.presentsRestoreSheet, pendingRestore == nil else { return }
        guard let backup = try? BackupService.capture(
            context: context,
            settings: settings,
            environment: backupEnvironment
        ) else { return }
        pendingRestore = BackupRestoreCandidate(archive: backup, fileName: "Montra-demo.montra")
        #endif
    }
    #else
    private func exportTransactions() {
        CSVExporter.export(operations)
    }
    #endif

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
                caption: String(localized: "settings.the_app_is_ready_the"),
                value: String(localized: "common.not_connected_2")
            ) {
                onOpenICloud()
            }

            divider

            linkRow(
                title: String(localized: "common.export_transactions"),
                caption: String(localized: "settings.export_all_transactions_as_a"),
                value: "\(operations.count)"
            ) {
                exportTransactions()
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
            // On iOS the About page is not a destination: this row opens it as a
            // bottom sheet. The macOS About page stays a sidebar destination, so
            // the row would be a duplicate there.
            if !AppPlatform.isMac {
                linkRow(
                    title: String(localized: "common.about"),
                    caption: String(localized: "about.version_data_and_onboarding"),
                    value: AboutMetrics.version
                ) {
                    onOpenAbout()
                }
                divider
            }
            plainRow(title: String(localized: "common.version"), value: AboutMetrics.version)
            divider
            plainRow(title: String(localized: "common.storage"), value: storageText)
        }
    }

    private var storageText: String {
        #if os(macOS)
        String(localized: "settings.swiftdata_on_this_mac")
        #else
        String(localized: "settings.swiftdata_on_this_device")
        #endif
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
        .padding(.vertical, rowVerticalPadding)
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
        .padding(.vertical, rowVerticalPadding)
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
            .padding(.vertical, rowVerticalPadding)
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
            .padding(.vertical, rowVerticalPadding)
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
        .padding(.vertical, rowVerticalPadding)
    }

    /// iOS touch targets want a little more room than the desktop rows; the
    /// macOS row height stays exactly as it was.
    private var rowVerticalPadding: CGFloat {
        #if os(iOS)
        AppStyle.Spacing.small + 2
        #else
        AppStyle.Spacing.small
        #endif
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
                preview(isDark: true)
            case .light:
                preview(isDark: false)
            case .auto:
                ZStack {
                    preview(isDark: true)
                    preview(isDark: false)
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

    @ViewBuilder
    private func preview(isDark: Bool) -> some View {
        #if os(iOS)
        IOSMiniWindow(isDark: isDark)
        #else
        MiniWindow(isDark: isDark)
        #endif
    }
}

/// The iOS equivalent of `MiniWindow`: an app surface with a title and two
/// cards, with no desktop sidebar or traffic lights. The Mac keeps its window
/// sketch so the existing macOS screenshots do not change.
private struct IOSMiniWindow: View {
    let isDark: Bool

    private var background: Color { isDark ? Color(hex: 0x171615) : Color(hex: 0xF6F5F3) }
    private var card: Color { isDark ? Color(hex: 0x2B2A28) : Color(hex: 0xEFEDEA) }
    private var cardBorder: Color { isDark ? Color(hex: 0x353330) : Color(hex: 0xE2DFDA) }
    private var ink: Color { isDark ? Color(hex: 0xECEAE6) : Color(hex: 0x2E2D2B) }
    private let tile = Color(hex: 0x3A94D0)

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Capsule()
                .fill(ink.opacity(0.35))
                .frame(width: 18, height: 2)
            cardRow(filled: true)
            cardRow(filled: false)
        }
        .padding(5)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(background)
    }

    private func cardRow(filled: Bool) -> some View {
        HStack(spacing: 3) {
            RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                .fill(filled ? tile : tile.opacity(0.5))
                .frame(width: 7, height: 7)
            VStack(alignment: .leading, spacing: 1.5) {
                Capsule().fill(ink.opacity(0.55)).frame(width: 14, height: 1.6)
                Capsule().fill(ink.opacity(0.25)).frame(width: 22, height: 1.2)
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

#if os(iOS)
/// A one-line result for the file flows, shown as a SwiftUI alert: the Mac uses
/// `NSAlert`, which does not exist here.
private struct BackupNotice: Identifiable {
    let id = UUID()
    let title: String
    let message: String
}
#endif

#if os(iOS)
private extension View {
    /// The restore sheet is presented by Settings rather than by
    /// `BottomSheetHost`, so it carries the same chrome: a tall sheet, drag
    /// indicator, and a centred form card at iPad regular width.
    @ViewBuilder
    func restoreSheetPresentation() -> some View {
        self
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
            .modifier(RestoreFormSizing())
    }
}

private struct RestoreFormSizing: ViewModifier {
    @Environment(\.horizontalSizeClass) private var sizeClass

    func body(content: Content) -> some View {
        if sizeClass == .regular {
            content.presentationSizing(.form)
        } else {
            content
        }
    }
}
#endif
