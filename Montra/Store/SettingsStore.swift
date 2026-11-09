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
        static let lastBackup = "montra.backup.lastSavedAt"
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
        didSet { defaults.set(hasCompletedOnboarding, forKey: Key.onboardingCompleted) }
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
        lastBackupAt = defaults.object(forKey: Key.lastBackup) as? Date
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
