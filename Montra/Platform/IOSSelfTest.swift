#if os(iOS)
import Foundation
import SwiftData
import UIKit

/// The iOS half of `-selftest`: the money, period, transfer, settings and
/// `.montra` archive rules on the same code the phone runs. It is deliberately
/// headless — it runs before any scene and exits — because a UIKit app cannot
/// reuse the macOS AppKit checks. UI behaviour is covered by the simulator
/// matrix and screenshots, not here.
@MainActor
enum IOSSelfTest {
    static func runIfRequested() -> Int32? {
        guard CommandLine.arguments.contains("-iostest") else { return nil }

        var failures = 0
        func check(_ condition: Bool, _ label: String) {
            print(condition ? "PASS  \(label)" : "FAIL  \(label)")
            if !condition { failures += 1 }
        }

        let defaults = UserDefaults(suiteName: "montra.iostest") ?? .standard
        defaults.removePersistentDomain(forName: "montra.iostest")
        let settings = SettingsStore(defaults: defaults)

        let container = ModelContainerFactory.make(inMemory: true)
        let context = container.mainContext
        SeedData.bootstrap(context: context, settings: settings)

        let categories = (try? context.fetch(FetchDescriptor<Category>())) ?? []
        let periods = (try? context.fetch(FetchDescriptor<Period>())) ?? []
        check(categories.count >= 14, "стартовые категории создаются")
        check(!periods.isEmpty, "финансовый период создаётся")

        let cash = AccountRepository(context: context).create(
            name: "Наличные", currency: .byn, initialAmount: 100,
            iconName: "banknote.fill", color: .green
        )
        let card = AccountRepository(context: context).create(
            name: "Карта", currency: .byn, initialAmount: 0,
            iconName: "creditcard.fill", color: .blue
        )
        let food = categories.first { $0.kind == .expense }
        let expense = OperationRepository(context: context).create(
            kind: .expense, amount: 30, account: cash, category: food,
            date: .now, place: "Минск", latitude: nil, longitude: nil, note: "обед"
        )
        let income = OperationRepository(context: context).create(
            kind: .income, amount: 10, account: cash, category: nil,
            date: .now, place: "", latitude: nil, longitude: nil, note: ""
        )
        check(cash.balance == 80, "расход и доход меняют баланс (100 − 30 + 10)")
        check(expense.signedAmount == -30 && income.signedAmount == 10, "знаки операций верные")

        let transferID = TransferRepository(context: context).create(
            from: cash, to: card, sent: 20, received: 20
        )
        let transfers = ((try? context.fetch(FetchDescriptor<Operation>())) ?? [])
            .filter { $0.transferID == transferID }
        check(transfers.count == 2, "перевод создаёт две связанные операции")
        check(cash.balance == 60 && card.balance == 20, "перевод двигает оба счёта")

        check(MoneyFormat.string(100, currency: .byn, masked: true) == "••••",
              "скрытие сумм работает")
        check(!MoneyFormat.string(100, currency: .byn).isEmpty,
              "сумма форматируется")

        let rates = ExchangeRates(
            bynPerUnit: [.byn: 1, .usd: 3, .eur: 3.5],
            date: .now, fetchedAt: .now, source: .nbrb
        )
        check(Finance.converted(10, from: .usd, to: .byn, rates: rates) == 30,
              "конвертация валюты верна")

        let environment = BackupService.Environment(
            rates: rates, integrationEnabled: false, integrationAllowsDelete: false
        )
        do {
            let backup = try BackupService.capture(context: context, settings: settings, environment: environment)
            let data = try BackupCoding.encode(backup)
            let decoded = try BackupCoding.decode(data)
            check(decoded.payload.accounts.count == 2, "архив сохраняет счета")
            check(decoded.payload.operations.count == 4, "архив сохраняет операции")
            check(decoded.checksum == backup.checksum, "контрольная сумма архива совпадает")
        } catch {
            check(false, "бэкап кодируется и читается: \(error)")
        }

        check(CSVExporter.csv(for: (try? context.fetch(FetchDescriptor<Operation>())) ?? [])
            .hasPrefix("\u{FEFF}"), "CSV начинается с BOM и экспортируется")

        let pending = SettingsStore(defaults: UserDefaults(suiteName: "montra.iostest.pending") ?? .standard)
        let freshDefaults = UserDefaults(suiteName: "montra.iostest.fresh") ?? .standard
        freshDefaults.removePersistentDomain(forName: "montra.iostest.fresh")
        let fresh = SettingsStore(defaults: freshDefaults)
        check(OnboardingLaunch.needsOnboarding(accountCount: 0, settings: fresh),
              "первый запуск открывает онбординг")
        fresh.hasCompletedOnboarding = true
        check(!OnboardingLaunch.needsOnboarding(accountCount: 0, settings: fresh),
              "завершённый онбординг больше не открывается")
        check(!OnboardingLaunch.needsOnboarding(accountCount: 1, settings: pending),
              "данные без флага онбординга считаются старым пользователем")

        check(AppLocalization.language == "ru" || AppLocalization.language == "en",
              "язык приложения распознан")
        check(UIImage(systemName: AppIconSymbol.resolved("banknote")) != nil,
              "иконка SF Symbol доступна на iOS")

        print(failures == 0 ? "ALL IOS CHECKS PASSED" : "IOS FAILURES: \(failures)")
        let log = "\(failures == 0 ? "ALL IOS CHECKS PASSED" : "IOS FAILURES: \(failures)")\n"
        if let folder = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
            try? log.write(to: folder.appendingPathComponent("iostest.log"), atomically: true, encoding: .utf8)
        }
        return failures == 0 ? 0 : 1
    }
}
#endif
