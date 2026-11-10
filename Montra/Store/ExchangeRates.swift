import Foundation

/// Where the exchange rates came from. Shown in Settings and on the rate line, so
/// a fallback rate is never mistaken for an official one.
enum RateSource: String, Codable, Equatable {
    case nbrb
    case currencyAPI
    case cache
    case fallback

    var title: String {
        switch self {
        case .nbrb: String(localized: "rates.national_bank_of_belarus")
        case .currencyAPI: "currency-api"
        case .cache: String(localized: "common.cached_rate")
        case .fallback: String(localized: "common.approximate_rate")
        }
    }

    var isApproximate: Bool { self == .fallback }
}

/// The rate table: how many Belarusian rubles one unit of each currency costs.
/// BYN is the pivot, so converting between any two currencies is one division.
struct ExchangeRates: Equatable {
    var bynPerUnit: [Currency: Decimal]
    var date: Date?
    var fetchedAt: Date?
    var source: RateSource

    func rate(for currency: Currency) -> Decimal? {
        bynPerUnit[currency]
    }

    /// Converts a money value between currencies. Returns nil when a rate is
    /// missing, so a caller can leave the figure out instead of inventing one.
    func convert(_ value: Decimal, from: Currency, to: Currency) -> Decimal? {
        if from == to { return value }
        guard let fromRate = bynPerUnit[from], let toRate = bynPerUnit[to], toRate > 0 else { return nil }
        return value * fromRate / toRate
    }

    /// A fixed table used only when there is no network and no cache. It is
    /// labelled "approximate rate" everywhere it shows.
    static let fallback = ExchangeRates(
        bynPerUnit: [
            .byn: 1,
            .usd: 3.00,
            .eur: 3.35,
            .usdc: 3.00,
            .usdt: 3.00,
            .btc: 227_000,
            .eth: 6_700,
        ],
        date: nil,
        fetchedAt: nil,
        source: .fallback
    )
}

/// Loads official NBRB rates for the fiat currencies and an open feed for crypto
/// (NBRB has no crypto), caches the last good table, and refreshes it quietly.
/// The UI never waits on the network: it draws the cached table immediately.
@MainActor
final class RateStore: ObservableObject {
    @Published private(set) var rates: ExchangeRates
    @Published private(set) var isRefreshing = false
    @Published private(set) var lastError: String?

    private let defaults: UserDefaults
    private var lastAttempt: Date?
    private let cacheKey = "montra.rates.v1"
    private let refreshInterval: TimeInterval = 6 * 60 * 60

    private static let nbrbURL = URL(string: "https://api.nbrb.by/exrates/rates?periodicity=0")!
    /// A CDN-hosted open table. It covers BYN, fiat and crypto in one request and
    /// answers when NBRB does not; NBRB stays authoritative for USD and EUR.
    private static let openRatesURL = URL(string: "https://cdn.jsdelivr.net/npm/@fawazahmed0/currency-api@latest/v1/currencies/byn.json")!

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: cacheKey),
           let cached = try? JSONDecoder().decode(CachedRates.self, from: data),
           let table = cached.exchangeRates {
            rates = table
        } else {
            rates = .fallback
        }
        lastAttempt = rates.fetchedAt
    }

    /// A store with fixed rates, for snapshots and previews.
    init(preview rates: ExchangeRates) {
        self.defaults = UserDefaults(suiteName: "montra.preview") ?? .standard
        self.rates = rates
        self.lastAttempt = rates.fetchedAt
    }

    // MARK: - Conversion

    func convert(_ value: Decimal, from: Currency, to: Currency) -> Decimal? {
        rates.convert(value, from: from, to: to)
    }

    /// The signed net of a set of operations in one currency.
    func total(of operations: [Operation], to currency: Currency) -> Decimal {
        operations.reduce(Decimal(0)) { sum, operation in
            sum + (convert(operation.signedAmount, from: operation.currency, to: currency) ?? 0)
        }
    }

    /// The rate as a short line: "3,0010 Br" — four digits, as NBRB publishes.
    func rateText(for currency: Currency) -> String? {
        guard currency != .byn, let rate = rates.rate(for: currency) else { return nil }
        let digits = currency == .btc || currency == .eth ? 2 : 4
        return MoneyFormat.number(rate, fractionDigits: digits) + " Br"
    }

    var updatedText: String {
        guard let fetchedAt = rates.fetchedAt else { return String(localized: "common.never_updated") }
        return AppDate.dayMonthTime.string(from: fetchedAt)
    }

    // MARK: - Restore

    /// Installs the table that came with a backup, so the totals and the rate
    /// cards match the money at that moment even before the next refresh. The
    /// quiet refresh below still replaces it when it is older than six hours.
    func applyBackup(_ table: ExchangeRates) {
        rates = table
        lastAttempt = table.fetchedAt
        if table.source != .fallback {
            save(table)
        }
    }

    // MARK: - Refresh

    /// Called on launch: refreshes only when the table is older than six hours.
    /// A currency added in an update has no cached rate yet, so it also forces a
    /// refresh even when the saved table is still fresh.
    func refreshIfNeeded() async {
        let isComplete = Currency.allCases.allSatisfy { rates.rate(for: $0) != nil }
        if isComplete, let fetchedAt = rates.fetchedAt, Date().timeIntervalSince(fetchedAt) < refreshInterval { return }
        if let lastAttempt, Date().timeIntervalSince(lastAttempt) < 60 { return }
        await refresh()
    }

    func refresh() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        lastAttempt = .now
        lastError = nil
        defer { isRefreshing = false }

        async let official = fetchNBRB()
        async let open = fetchOpenRates()
        let (nbrb, openTable) = await (official, open)

        guard nbrb != nil || openTable != nil else {
            lastError = String(localized: "rates.couldnt_get_exchange_rates_showing")
            return
        }

        var table: [Currency: Decimal] = [.byn: 1]

        if let openTable {
            if let usd = openTable.usd { table[.usd] = usd }
            if let eur = openTable.eur { table[.eur] = eur }
            if let usdt = openTable.usdt { table[.usdt] = usdt }
            if let usdc = openTable.usdc { table[.usdc] = usdc }
            if let btc = openTable.btc { table[.btc] = btc }
            if let eth = openTable.eth { table[.eth] = eth }
        }

        if let nbrb {
            if let usd = nbrb.usd { table[.usd] = usd }
            if let eur = nbrb.eur { table[.eur] = eur }
        }

        // Never drop a currency the table had before: a partial answer still
        // leaves the other cards working.
        for currency in Currency.allCases where table[currency] == nil {
            table[currency] = rates.rate(for: currency)
        }
        if table[.usdc] == nil { table[.usdc] = table[.usd] }
        if table[.usdt] == nil { table[.usdt] = table[.usd] }

        let date = nbrb?.date ?? openTable?.date
        let updated = ExchangeRates(
            bynPerUnit: table,
            date: date,
            fetchedAt: .now,
            source: nbrb == nil ? .currencyAPI : .nbrb
        )
        rates = updated
        save(updated)
    }

    // MARK: - Sources

    private struct NBRBTable {
        var usd: Decimal?
        var eur: Decimal?
        var date: Date?
    }

    private struct OpenTable {
        var usd: Decimal?
        var eur: Decimal?
        var usdt: Decimal?
        var usdc: Decimal?
        var btc: Decimal?
        var eth: Decimal?
        var date: Date?
    }

    private func fetchNBRB() async -> NBRBTable? {
        // NBRB is the authority for BYN fiat, but it can be slow from outside
        // Belarus, so the request gets a short leash and the open table is the net.
        guard let data = try? await request(Self.nbrbURL, timeout: 8) else { return nil }
        guard let rows = try? JSONDecoder().decode([NBRBRow].self, from: data) else { return nil }

        var table = NBRBTable()
        for row in rows {
            guard row.Cur_Scale > 0 else { continue }
            let perUnit = row.Cur_OfficialRate / row.Cur_Scale
            switch row.Cur_Abbreviation.uppercased() {
            case "USD": table.usd = perUnit
            case "EUR": table.eur = perUnit
            default: break
            }
            if table.date == nil {
                table.date = Self.parseNBRBDate(row.Date)
            }
        }
        guard table.usd != nil || table.eur != nil else { return nil }
        return table
    }

    /// NBRB sends "2026-11-09T00:00:00" without a time zone, which ISO8601's
    /// default options reject, so both shapes are accepted.
    private static func parseNBRBDate(_ raw: String) -> Date? {
        if let date = ISO8601DateFormatter().date(from: raw) { return date }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
        return formatter.date(from: raw)
    }

    private struct NBRBRow: Decodable {
        let Cur_Abbreviation: String
        let Cur_Scale: Decimal
        let Cur_OfficialRate: Decimal
        let Date: String
    }

    private func fetchOpenRates() async -> OpenTable? {
        guard let data = try? await request(Self.openRatesURL, timeout: 12) else { return nil }
        guard let document = try? JSONDecoder().decode(OpenRatesDocument.self, from: data) else { return nil }
        let byn = document.byn

        func perUnit(_ key: String) -> Decimal? {
            guard let value = byn[key], value > 0 else { return nil }
            return Decimal(1 / value)
        }

        var table = OpenTable()
        table.usd = perUnit("usd")
        table.eur = perUnit("eur")
        table.usdt = perUnit("usdt")
        table.usdc = perUnit("usdc")
        table.btc = perUnit("btc")
        table.eth = perUnit("eth")

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        if let raw = document.date { table.date = formatter.date(from: raw) }

        guard table.usd != nil || table.eur != nil else { return nil }
        return table
    }

    private struct OpenRatesDocument: Decodable {
        let date: String?
        let byn: [String: Double]
    }

    private func request(_ url: URL, timeout: TimeInterval) async throws -> Data {
        var request = URLRequest(url: url)
        request.timeoutInterval = timeout
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Montra/1.0 (macOS)", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
        return data
    }

    // MARK: - Cache

    private struct CachedRates: Codable {
        var table: [String: Double]
        var date: Date?
        var fetchedAt: Date?
        var source: String

        var exchangeRates: ExchangeRates? {
            var perUnit: [Currency: Decimal] = [:]
            for (key, value) in table {
                guard let currency = Currency(rawValue: key), value > 0 else { continue }
                perUnit[currency] = Decimal(value)
            }
            guard perUnit[.byn] != nil else { return nil }
            return ExchangeRates(
                bynPerUnit: perUnit,
                date: date,
                fetchedAt: fetchedAt,
                source: RateSource(rawValue: source) ?? .cache
            )
        }
    }

    private func save(_ table: ExchangeRates) {
        var raw: [String: Double] = [:]
        for (currency, value) in table.bynPerUnit {
            raw[currency.rawValue] = NSDecimalNumber(decimal: value).doubleValue
        }
        let cached = CachedRates(
            table: raw,
            date: table.date,
            fetchedAt: table.fetchedAt,
            source: table.source.rawValue
        )
        if let data = try? JSONEncoder().encode(cached) {
            defaults.set(data, forKey: cacheKey)
        }
    }
}
