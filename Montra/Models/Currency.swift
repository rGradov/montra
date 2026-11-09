import Foundation
import SwiftUI

enum AppLocalization {
    static let language = Bundle.main.preferredLocalizations.first ?? "ru"
    static let locale = Locale(identifier: language)
    static let russianBundle = Bundle.main.url(forResource: "ru", withExtension: "lproj")
        .flatMap(Bundle.init(url:)) ?? .main
}

/// The currencies an account can hold. One place to add another: the picker, the
/// account tile and every figure pick it up from here.
enum Currency: String, Codable, CaseIterable, Identifiable, Hashable, Sendable {
    case byn
    case eur
    case usd
    case usdc
    case usdt
    case btc
    case eth

    var id: String { rawValue }

    var code: String {
        switch self {
        case .byn: "BYN"
        case .eur: "EUR"
        case .usd: "USD"
        case .usdc: "USDC"
        case .usdt: "USDT"
        case .btc: "BTC"
        case .eth: "ETH"
        }
    }

    var symbol: String {
        switch self {
        case .byn: "Br"
        case .eur: "€"
        case .usd: "$"
        case .usdc: "USDC"
        case .usdt: "USDT"
        case .btc: "₿"
        case .eth: "Ξ"
        }
    }

    var name: String {
        switch self {
        case .byn: String(localized: "format.belarusian_ruble")
        case .eur: String(localized: "format.euro")
        case .usd: String(localized: "format.us_dollar")
        case .usdc: String(localized: "format.usd_coin")
        case .usdt: String(localized: "format.tether")
        case .btc: String(localized: "format.bitcoin")
        case .eth: String(localized: "format.ether")
        }
    }

    var fractionDigits: Int {
        switch self {
        case .btc, .eth: 8
        default: 2
        }
    }

    var isCrypto: Bool {
        switch self {
        case .usdc, .usdt, .btc, .eth: true
        default: false
        }
    }

    /// Only used by the account form's icon preview, never as the account icon.
    var systemImage: String {
        switch self {
        case .btc: "bitcoinsign"
        case .eth: "diamond"
        case .usdc, .usdt: "dollarsign.circle"
        default: "banknote"
        }
    }
}

enum MoneyFormat {
    private static let locale = AppLocalization.locale

    private static func formatter(for currency: Currency) -> NumberFormatter {
        let key = "\(currency.rawValue)-\(currency.fractionDigits)"
        if let cached = cache[key] { return cached }
        let formatter = NumberFormatter()
        formatter.locale = locale
        formatter.numberStyle = .decimal
        if AppLocalization.language == "ru" { formatter.groupingSeparator = "\u{202F}" }
        formatter.minimumFractionDigits = currency.fractionDigits
        formatter.maximumFractionDigits = currency.fractionDigits
        formatter.usesSignificantDigits = false
        cache[key] = formatter
        return formatter
    }

    private static var cache: [String: NumberFormatter] = [:]

    private static func compactFormatter(for currency: Currency) -> NumberFormatter {
        let key = "compact-\(currency.rawValue)"
        if let cached = cache[key] { return cached }
        let formatter = NumberFormatter()
        formatter.locale = locale
        formatter.numberStyle = .decimal
        if AppLocalization.language == "ru" { formatter.groupingSeparator = "\u{202F}" }
        formatter.usesSignificantDigits = false
        if currency == .btc || currency == .eth {
            formatter.minimumFractionDigits = 0
            formatter.maximumFractionDigits = 4
        } else {
            formatter.minimumFractionDigits = currency.fractionDigits
            formatter.maximumFractionDigits = currency.fractionDigits
        }
        cache[key] = formatter
        return formatter
    }

    /// "1 240,50 Br". `sign` adds + for income and − for expense. `compact`
    /// shortens a crypto figure for a narrow sidebar row.
    static func string(
        _ value: Decimal,
        currency: Currency,
        sign: Sign = .none,
        masked: Bool = false,
        compact: Bool = false
    ) -> String {
        if masked { return "••••" }
        let number = NSDecimalNumber(decimal: abs(value))
        let formatter = compact ? compactFormatter(for: currency) : formatter(for: currency)
        let body = formatter.string(from: number) ?? number.stringValue
        let prefix: String
        switch sign {
        case .none: prefix = value < 0 ? "−" : ""
        case .always: prefix = value < 0 ? "−" : "+"
        }
        return "\(prefix)\(body) \(currency.symbol)"
    }

    enum Sign {
        case none
        case always
    }

    /// A bare figure without a currency, for percentages and counts.
    static func number(_ value: Decimal, fractionDigits: Int = 2, grouping: Bool = true) -> String {
        let formatter = NumberFormatter()
        formatter.locale = locale
        formatter.numberStyle = .decimal
        formatter.usesGroupingSeparator = grouping
        if AppLocalization.language == "ru" { formatter.groupingSeparator = "\u{202F}" }
        formatter.minimumFractionDigits = fractionDigits
        formatter.maximumFractionDigits = fractionDigits
        return formatter.string(from: NSDecimalNumber(decimal: value)) ?? "\(value)"
    }
}

enum AppDate {
    private static let locale = AppLocalization.locale

    static let dayMonth: DateFormatter = {
        let f = DateFormatter()
        f.locale = locale
        f.setLocalizedDateFormatFromTemplate("d MMM")
        return f
    }()

    static let dayMonthTime: DateFormatter = {
        let f = DateFormatter()
        f.locale = locale
        f.setLocalizedDateFormatFromTemplate("d MMM, HH:mm")
        return f
    }()

    static let fullDay: DateFormatter = {
        let f = DateFormatter()
        f.locale = locale
        f.setLocalizedDateFormatFromTemplate("d MMMM yyyy")
        return f
    }()

    static let monthYear: DateFormatter = {
        let f = DateFormatter()
        f.locale = locale
        f.setLocalizedDateFormatFromTemplate("LLLL yyyy")
        return f
    }()

    /// "9 нояб." — the row's trailing date.
    static func short(_ date: Date) -> String { dayMonth.string(from: date) }

    /// "15 нояб. — 14 дек."
    static func range(_ start: Date, _ end: Date) -> String {
        if Calendar.current.isDate(start, inSameDayAs: end) { return short(start) }
        return "\(short(start)) — \(short(end))"
    }

    static func relative(_ date: Date, now: Date = .now) -> String {
        let calendar = Calendar.current
        let day = calendar.startOfDay(for: date)
        let today = calendar.startOfDay(for: now)
        let days = calendar.dateComponents([.day], from: today, to: day).day ?? 0
        switch days {
        case 0: return String(localized: "date.today")
        case -1: return String(localized: "date.yesterday")
        case 1: return String(localized: "date.tomorrow")
        default: return short(date)
        }
    }

    static func daysBetween(_ start: Date, _ end: Date) -> Int {
        let calendar = Calendar.current
        let from = calendar.startOfDay(for: start)
        let to = calendar.startOfDay(for: end)
        return (calendar.dateComponents([.day], from: from, to: to).day ?? 0) + 1
    }
}

enum OperationKind: String, Codable, CaseIterable, Identifiable, Hashable, Sendable {
    case expense
    case income

    var id: String { rawValue }

    var title: String {
        switch self {
        case .expense: String(localized: "transaction.expense")
        case .income: String(localized: "transaction.income")
        }
    }

    var badgeTitle: String { title }

    var signPrefix: String {
        switch self {
        case .expense: "−"
        case .income: "+"
        }
    }
}

/// An account's (and a category's) colour. Stored as the raw value, so adding a
/// swatch never changes existing rows.
enum PaletteColor: String, CaseIterable, Identifiable, Hashable {
    case blue
    case sky
    case teal
    case green
    case amber
    case orange
    case red
    case pink
    case purple
    case graphite

    var id: String { rawValue }

    var title: String {
        switch self {
        case .blue: String(localized: "format.blue")
        case .sky: String(localized: "format.sky_blue")
        case .teal: String(localized: "format.teal")
        case .green: String(localized: "format.green")
        case .amber: String(localized: "format.amber")
        case .orange: String(localized: "format.orange")
        case .red: String(localized: "format.red")
        case .pink: String(localized: "format.pink")
        case .purple: String(localized: "format.purple")
        case .graphite: String(localized: "format.graphite")
        }
    }

    /// The bar / chart shade.
    var color: Color {
        switch self {
        case .blue: AppColors.Chart.blue
        case .sky: AppColors.Chart.sky
        case .teal: AppColors.Chart.teal
        case .green: AppColors.Chart.green
        case .amber: AppColors.Chart.amber
        case .orange: AppColors.Chart.vermillion
        case .red: Color(light: 0xC0392B, dark: 0xE05A4B)
        case .pink: AppColors.Chart.purple
        case .purple: Color(light: 0x7D5BC6, dark: 0x9B7BE0)
        case .graphite: AppColors.Chart.neutralTile
        }
    }

    /// The tile shade: deep enough for a white glyph in both appearances.
    var tileColor: Color {
        switch self {
        case .blue: AppColors.Chart.blueTile
        case .sky: AppColors.Chart.skyTile
        case .teal: AppColors.Chart.tealTile
        case .green: Color(light: 0x2C8A3E, dark: 0x2E9E4B)
        case .amber: Color(light: 0xC98A00, dark: 0xCC9000)
        case .orange: AppColors.Chart.vermillion
        case .red: Color(light: 0xB4302A, dark: 0xC94036)
        case .pink: AppColors.Chart.purpleTile
        case .purple: Color(light: 0x6B4BB0, dark: 0x7A5AC4)
        case .graphite: AppColors.Chart.neutralTile
        }
    }
}
