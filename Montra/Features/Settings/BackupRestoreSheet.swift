import SwiftData
import SwiftUI

/// A decoded backup waiting for a yes. The sheet is the whole restore flow:
/// check what is inside, optionally save the current state, then replace it.
struct BackupRestoreCandidate: Identifiable {
    let id = UUID()
    let archive: MontraBackup
    let fileName: String

    var summary: BackupSummary { archive.summary }
}

struct BackupRestoreSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @EnvironmentObject private var settings: SettingsStore
    @EnvironmentObject private var rates: RateStore
    @EnvironmentObject private var integration: LocalIntegration

    let candidate: BackupRestoreCandidate
    let onRestored: () -> Void

    @State private var restored: BackupSummary?
    @State private var isRestoring = false

    private var summary: BackupSummary { candidate.summary }

    var body: some View {
        VStack(spacing: 0) {
            if let restored {
                restoredState(restored)
                    .transition(.opacity)
            } else {
                confirmState
                    .transition(.opacity)
            }
        }
        .frame(width: 520, height: 640)
        .background(AppColors.surfaceBase)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.28), value: restored != nil)
    }

    // MARK: - Confirmation

    private var confirmState: some View {
        VStack(spacing: 0) {
            SheetHeader(
                title: String(localized: "backup.title"),
                subtitle: String(localized: "backup.check_the_contents_before_restoring"),
                onClose: { dismiss() }
            )

            ScrollView {
                VStack(alignment: .leading, spacing: AppStyle.Spacing.medium) {
                    InsetCard {
                        statusRow
                    }

                    VStack(alignment: .leading, spacing: AppStyle.Spacing.xSmall) {
                        Text(String(localized: "backup.contents"))
                            .font(AppStyle.Typography.metadataEmphasis)
                            .foregroundStyle(AppColors.textSecondary)
                            .padding(.horizontal, AppStyle.Spacing.xxSmall)

                        InsetCard {
                            countRow(String(localized: "backup.accounts"), summary.accounts)
                            InsetCardDivider()
                            countRow(String(localized: "backup.categories"), summary.categories)
                            InsetCardDivider()
                            countRow(String(localized: "backup.operations"), summary.operations)
                            InsetCardDivider()
                            countRow(String(localized: "backup.plans"), summary.plans)
                            InsetCardDivider()
                            countRow(String(localized: "backup.periods"), summary.periods)
                        }
                    }

                    warning

                    Button {
                        saveCurrentState()
                    } label: {
                        Label(String(localized: "backup.save_current_first"), systemImage: "arrow.down.doc")
                    }
                    .buttonStyle(.montra(.secondary, size: .small))
                    .disabled(isRestoring)
                }
                .padding(.horizontal, AppStyle.Spacing.large)
                .padding(.bottom, AppStyle.Spacing.medium)
            }

            SheetFooter {
                Spacer(minLength: AppStyle.Spacing.small)

                Button(String(localized: "common.cancel")) { dismiss() }
                    .buttonStyle(.montra(.secondary))
                    .keyboardShortcut(.cancelAction)
                    .disabled(isRestoring)

                Button(String(localized: "backup.restore_action")) { performRestore() }
                    .buttonStyle(.montra(.destructive))
                    .keyboardShortcut(.defaultAction)
                    .disabled(isRestoring)
            }
        }
    }

    private var statusRow: some View {
        HStack(spacing: AppStyle.Spacing.small) {
            IconTile(symbol: "archivebox.fill", color: AppColors.Chart.neutralTile)

            VStack(alignment: .leading, spacing: 1) {
                Text(candidate.fileName)
                    .font(AppStyle.Typography.headline)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text("\(AppDate.dayMonthTime.string(from: candidate.archive.createdAt)) · Montra \(candidate.archive.appVersion) (\(candidate.archive.appBuild))")
                    .font(AppStyle.Typography.metadata)
                    .foregroundStyle(AppColors.textSecondary)
            }

            Spacer(minLength: AppStyle.Spacing.small)

            AppBadge(text: String(localized: "backup.verified"), tone: .safe)
        }
        .padding(.horizontal, AppStyle.Spacing.medium)
        .padding(.vertical, AppStyle.Spacing.small)
    }

    private var warning: some View {
        HStack(alignment: .top, spacing: AppStyle.Spacing.small) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(AppColors.statusCheckText)
                .padding(.top, 1)

            VStack(alignment: .leading, spacing: AppStyle.Spacing.xxxSmall) {
                Text(String(localized: "backup.replace_warning_title"))
                    .font(AppStyle.Typography.callout.weight(.semibold))
                Text(String(localized: "backup.replace_warning_text"))
                    .font(AppStyle.Typography.callout)
                    .foregroundStyle(AppColors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(AppStyle.Spacing.medium)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            AppColors.fillSecondary,
            in: RoundedRectangle(cornerRadius: AppStyle.Radius.lg, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: AppStyle.Radius.lg, style: .continuous)
                .strokeBorder(AppColors.borderSubtle, lineWidth: 1)
        }
    }

    // MARK: - Done

    private func restoredState(_ summary: BackupSummary) -> some View {
        VStack(spacing: 0) {
            SheetHeader(
                title: String(localized: "backup.title"),
                subtitle: nil,
                onClose: { finish() }
            )

            Spacer(minLength: AppStyle.Spacing.large)

            ZStack {
                Circle()
                    .fill(AppColors.statusSafeText.opacity(0.12))
                Image(systemName: "checkmark")
                    .font(.system(size: 30, weight: .semibold))
                    .foregroundStyle(AppColors.statusSafeText)
            }
            .frame(width: 84, height: 84)

            Text(String(localized: "backup.restored_title"))
                .font(AppStyle.Typography.sectionTitle)
                .padding(.top, AppStyle.Spacing.large)

            Text(String(localized: "backup.restored_text"))
                .font(AppStyle.Typography.callout)
                .foregroundStyle(AppColors.textSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, AppStyle.Spacing.xLarge)
                .padding(.top, AppStyle.Spacing.xxSmall)

            HStack(spacing: AppStyle.Spacing.small) {
                restoredChip(symbol: "creditcard", text: Finance.accountsCountText(summary.accounts))
                restoredChip(symbol: "list.bullet", text: Finance.operationsCountText(summary.operations))
            }
            .padding(.top, AppStyle.Spacing.medium)

            Spacer(minLength: AppStyle.Spacing.large)

            Button(String(localized: "common.done")) { finish() }
                .buttonStyle(.montra(.primary, size: .large, width: .fixed(280)))
                .keyboardShortcut(.defaultAction)
                .padding(.bottom, AppStyle.Spacing.large)
        }
        .padding(.horizontal, AppStyle.Spacing.large)
    }

    private func restoredChip(symbol: String, text: String) -> some View {
        HStack(spacing: AppStyle.Spacing.xxSmallPlus) {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .semibold))
            Text(text)
                .lineLimit(1)
        }
        .font(AppStyle.Typography.callout)
        .foregroundStyle(AppColors.textSecondary)
        .padding(.horizontal, AppStyle.Spacing.small)
        .padding(.vertical, AppStyle.Spacing.xxSmallPlus)
        .background(AppColors.surfaceRaised, in: Capsule(style: .continuous))
        .overlay {
            Capsule(style: .continuous)
                .strokeBorder(AppColors.borderSubtle, lineWidth: 1)
        }
    }

    // MARK: - Actions

    private func saveCurrentState() {
        do {
            let backup = try BackupService.capture(
                context: context,
                settings: settings,
                environment: environment
            )
            if let url = try BackupFile.export(backup, suggestedName: "Montra-\(currentStamp())-before-restore.\(BackupFile.fileExtension)") {
                settings.lastBackupAt = .now
                BackupFile.confirmSave(url)
            }
        } catch {
            BackupFile.presentError(error, title: String(localized: "backup.error.save_title"))
        }
    }

    private func performRestore() {
        guard !isRestoring else { return }
        isRestoring = true
        defer { isRestoring = false }

        do {
            let report = try BackupService.restore(candidate.archive, context: context, settings: settings)
            if let table = report.rates { rates.applyBackup(table) }
            if let switches = report.integration {
                integration.applyBackup(
                    enabled: switches.enabled,
                    allowDelete: switches.allowDelete,
                    onboardingComplete: settings.hasCompletedOnboarding
                )
            }
            restored = report.summary
            // A restored table may already be stale; the usual quiet refresh
            // takes over without blocking the screen.
            Task { await rates.refreshIfNeeded() }
        } catch {
            BackupFile.presentError(error, title: String(localized: "backup.error.restore_title"))
        }
    }

    private func finish() {
        dismiss()
        onRestored()
    }

    private var environment: BackupService.Environment {
        BackupService.Environment(
            rates: rates.rates,
            integrationEnabled: integration.enabled,
            integrationAllowsDelete: integration.allowDelete
        )
    }

    private func currentStamp() -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd-HHmm"
        return formatter.string(from: .now)
    }

    // MARK: - Rows

    private func countRow(_ title: String, _ value: Int) -> some View {
        HStack(spacing: AppStyle.Spacing.small) {
            Text(title)
                .font(AppStyle.Typography.body)
            Spacer(minLength: AppStyle.Spacing.small)
            Text(MoneyFormat.number(Decimal(value), fractionDigits: 0))
                .font(AppStyle.Typography.callout)
                .foregroundStyle(AppColors.textSecondary)
                .monospacedDigit()
        }
        .padding(.horizontal, AppStyle.Spacing.medium)
        .padding(.vertical, AppStyle.Spacing.small)
    }
}
