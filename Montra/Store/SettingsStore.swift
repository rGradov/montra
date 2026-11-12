import AppKit
import Combine
import SwiftUI

/// Everything the app remembers between launches. Kept in UserDefaults (through
/// one type, so a future iCloud key-value sync plugs in here) and published for
/// the views that read it.
@MainActor
final class SettingsStore: ObservableObject {
    enum Appearance: String, CaseIterable, Identifiable {
        case auto
        case light
        case dark

        var id: String { rawValue }

        var title: String {
            switch self {
            case .auto: String(localized: "common.automatic")
            case .light: String(localized: "common.light")
            case .dark: String(localized: "common.dark")
            }
        }

        var nsAppearance: NSAppearance? {
            switch self {
            case .auto: nil
            case .light: NSAppearance(named: .aqua)
            case .dark: NSAppearance(named: .darkAqua)
            }
        }
    }

    enum PeriodMode: String, CaseIterable, Identifiable {
        /// Salary to salary, anchored on a day of the month.
        case payday
        /// Fixed number of days from an anchor date.
        case fixedDays

        var id: String { rawValue }

        var title: String {
            switch self {
            case .payday: String(localized: "common.payday")
            case .fixedDays: String(localized: "common.fixed_length")
            }
        }
    }

    /// How the Analytics pace card summarises a typical day.
    enum SpendMetric: String, CaseIterable, Identifiable {
        /// The period total spread over every elapsed day.
        case average
        /// The median of the elapsed days that had spending.
        case median

        var id: String { rawValue }

        var title: String {
            switch self {
            case .average: String(localized: "analytics.average")
            case .median: String(localized: "analytics.metric_median")
            }
        }

        /// What the figure is measured over, printed after the amount.
        var unitTitle: String {
            switch self {
            case .average: String(localized: "analytics.per_day")
            case .median: String(localized: "analytics.per_spending_day")
            }
        }
    }

    private enum Key {
        static let appearance = "montra.appearance"
        static let hideBalances = "montra.hideBalances"
        static let primaryCurrency = "montra.primaryCurrency"
        static let periodMode = "montra.periodMode"
        static let paydayDay = "montra.paydayDay"
        static let fixedLengthDays = "montra.fixedLengthDays"
        static let periodAnchor = "montra.periodAnchor"
        static let didSeed = "montra.didSeedDemo"
        static let onboardingCompleted = "montra.onboarding.completed"
        static let onboardingStarted = "montra.onboarding.started"
        static let lastBackup = "montra.backup.lastSavedAt"
        static let spendMetric = "montra.analytics.spendMetric"
    }

    private let defaults: UserDefaults

    @Published var appearance: Appearance {
        didSet {
            defaults.set(appearance.rawValue, forKey: Key.appearance)
            applyAppearance()
        }
    }

    @Published var hideBalances: Bool {
        didSet { defaults.set(hideBalances, forKey: Key.hideBalances) }
    }

    @Published var primaryCurrency: Currency {
        didSet { defaults.set(primaryCurrency.rawValue, forKey: Key.primaryCurrency) }
    }

    @Published var periodMode: PeriodMode {
        didSet { defaults.set(periodMode.rawValue, forKey: Key.periodMode) }
    }

    @Published var paydayDay: Int {
        didSet { defaults.set(paydayDay, forKey: Key.paydayDay) }
    }

    @Published var fixedLengthDays: Int {
        didSet { defaults.set(fixedLengthDays, forKey: Key.fixedLengthDays) }
    }

    @Published var periodAnchor: Date {
        didSet { defaults.set(periodAnchor, forKey: Key.periodAnchor) }
    }

    @Published var didSeedDemo: Bool {
        didSet { defaults.set(didSeedDemo, forKey: Key.didSeed) }
    }

    /// False until the welcome flow is finished. Legacy installs that already
    /// have accounts are marked complete at launch, so nobody is shown a first
    /// run on top of their own data.
    @Published var hasCompletedOnboarding: Bool {
        didSet {
            defaults.set(hasCompletedOnboarding, forKey: Key.onboardingCompleted)
            // Unfinished means started: this keeps a reset (delete all data, an
            // empty restore) from looking like a legacy install on the next launch.
            if !hasCompletedOnboarding, !hasStartedOnboarding { hasStartedOnboarding = true }
        }
    }

    /// True from the first launch that opens the welcome flow, including one
    /// interrupted after the first account. It separates "the person quit in the
    /// middle of onboarding" from "this store predates onboarding", which both
    /// end up as `hasCompletedOnboarding == false` with accounts on disk.
    @Published var hasStartedOnboarding: Bool {
        didSet { defaults.set(hasStartedOnboarding, forKey: Key.onboardingStarted) }
    }

    /// Mean or median on the Analytics pace card. Remembered because it is a way
    /// of reading the same numbers, not a per-visit choice.
    @Published var spendMetric: SpendMetric {
        didSet { defaults.set(spendMetric.rawValue, forKey: Key.spendMetric) }
    }

    /// When a backup was last written from this Mac. It describes the machine,
    /// not the money, so a restore leaves it alone.
    @Published var lastBackupAt: Date? {
        didSet { defaults.set(lastBackupAt, forKey: Key.lastBackup) }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        appearance = Appearance(rawValue: defaults.string(forKey: Key.appearance) ?? "") ?? .auto
        hideBalances = defaults.bool(forKey: Key.hideBalances)
        primaryCurrency = Currency(rawValue: defaults.string(forKey: Key.primaryCurrency) ?? "") ?? .byn
        periodMode = PeriodMode(rawValue: defaults.string(forKey: Key.periodMode) ?? "") ?? .payday
        let payday = defaults.integer(forKey: Key.paydayDay)
        paydayDay = payday == 0 ? 15 : min(max(payday, 1), 31)
        let length = defaults.integer(forKey: Key.fixedLengthDays)
        fixedLengthDays = length == 0 ? 30 : min(max(length, 1), 90)
        if let stored = defaults.object(forKey: Key.periodAnchor) as? Date {
            periodAnchor = stored
        } else {
            periodAnchor = Calendar.current.startOfDay(for: .now)
        }
        didSeedDemo = defaults.bool(forKey: Key.didSeed)
        hasCompletedOnboarding = defaults.bool(forKey: Key.onboardingCompleted)
        hasStartedOnboarding = defaults.bool(forKey: Key.onboardingStarted)
        lastBackupAt = defaults.object(forKey: Key.lastBackup) as? Date
        spendMetric = SpendMetric(rawValue: defaults.string(forKey: Key.spendMetric) ?? "") ?? .average
        applyAppearance()
    }

    var rule: PeriodRule {
        PeriodRule(
            mode: periodMode,
            paydayDay: paydayDay,
            fixedLengthDays: fixedLengthDays,
            anchor: periodAnchor
        )
    }

    /// Today's money, hidden on screen while someone is looking over a shoulder.
    func money(_ value: Decimal, currency: Currency, sign: MoneyFormat.Sign = .none) -> String {
        MoneyFormat.string(value, currency: currency, sign: sign, masked: hideBalances)
    }

    private func applyAppearance() {
        NSApplication.shared.appearance = appearance.nsAppearance
    }
}

/// The one place that decides whether a launch opens the welcome flow.
///
/// Accounts on disk mean two different things. A store from a Montra that
/// predates onboarding belongs to someone who has already used the app: it is
/// marked complete once, so a first run is never put on top of real data. A
/// store from a flow that was closed after the first account does not: the
/// account is a step inside onboarding, so the flow comes back until the person
/// actually finishes it.
@MainActor
enum OnboardingLaunch {
    static func needsOnboarding(accountCount: Int, settings: SettingsStore) -> Bool {
        if accountCount > 0, !settings.hasCompletedOnboarding, !settings.hasStartedOnboarding {
            settings.hasCompletedOnboarding = true
        }

        let needsOnboarding = !settings.hasCompletedOnboarding
        if needsOnboarding { settings.hasStartedOnboarding = true }
        return needsOnboarding
    }
}
