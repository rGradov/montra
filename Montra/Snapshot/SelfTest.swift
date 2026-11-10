import AppKit
import Foundation
import SwiftData

/// A launch-time check of the money and period rules, run with `-selftest`.
/// It uses an in-memory store, prints one line per rule and exits non-zero on a
/// failure, so the arithmetic behind the screens is verified without the UI.
@MainActor
enum SelfTest {
    static func runIfRequested() -> Bool {
        guard CommandLine.arguments.contains("-selftest") else { return false }
        var failures = 0
        let english = AppLocalization.language == "en"

        func check(_ condition: Bool, _ label: String) {
            print(condition ? "PASS  \(label)" : "FAIL  \(label)")
            if !condition { failures += 1 }
        }

        let categorySymbols = CategoryIcons.options.map(\.symbol)
        let missingSymbols = categorySymbols.filter {
            NSImage(systemSymbolName: $0, accessibilityDescription: nil) == nil
        }
        check(missingSymbols.isEmpty, "все иконки категорий доступны: \(missingSymbols)")
        check(["hand.heart.fill", "cigarette.fill"].allSatisfy {
            categorySymbols.contains(AppIconSymbol.resolved($0))
        }, "старые имена иконок заменяются доступными")
        check(AppIconGlyph.isEmoji("💳") && !AppIconGlyph.isEmoji("creditcard.fill"),
              "эмодзи-иконка отличается от имени символа")
        let accountSymbols = AccountIconCatalog.options.map(\.symbol)
        check(accountSymbols.allSatisfy {
            NSImage(systemSymbolName: $0, accessibilityDescription: nil) != nil
        }, "все иконки счетов доступны")

        let settings = SettingsStore(defaults: UserDefaults(suiteName: "montra.selftest") ?? .standard)
        settings.periodMode = .payday
        settings.paydayDay = 15

        let container = ModelContainerFactory.make(inMemory: true)
        let context = ModelContext(container)

        let integrationSuite = "montra.selftest.integration"
        if let defaults = UserDefaults(suiteName: integrationSuite) {
            defaults.removePersistentDomain(forName: integrationSuite)
            let accountDeleteKey = "montra.integration.allowAccountDeletion"
            let entryDeleteKey = "montra.integration.allowEntryDeletion"
            defaults.set(true, forKey: accountDeleteKey)
            check(!LocalIntegration(container: container, available: false, defaults: defaults).allowDelete,
                  "разрешение удаления только счетов не расширяется")
            defaults.set(false, forKey: accountDeleteKey)
            defaults.set(true, forKey: entryDeleteKey)
            check(!LocalIntegration(container: container, available: false, defaults: defaults).allowDelete,
                  "разрешение удаления только операций и планов не расширяется")
            defaults.set(true, forKey: accountDeleteKey)
            let integration = LocalIntegration(container: container, available: false, defaults: defaults)
            check(integration.allowDelete, "два старых разрешения включают общее")
            integration.allowDelete = false
            check(!LocalIntegration(container: container, available: false, defaults: defaults).allowDelete,
                  "общее разрешение сохраняется после выключения")
            defaults.removePersistentDomain(forName: integrationSuite)
        } else {
            check(false, "доступны тестовые настройки интеграции")
        }

        // 1. Payday periods are contiguous and span the expected days.
        let periods = PeriodService.generatedPeriods(rule: settings.rule, covering: date(year: 2026, month: 11, day: 9))
        check(periods.count > 5, "периоды сгенерированы")
        var contiguous = true
        for index in 0..<(periods.count - 1) {
            if abs(periods[index].end.addingTimeInterval(1).timeIntervalSince(periods[index + 1].start)) > 0.5 {
                contiguous = false
            }
        }
        check(contiguous, "границы периодов непрерывны")

        let october = periods.first { month(of: $0.start) == 10 && year(of: $0.start) == 2026 }
        check(october?.days == 31, "октябрьский период — 31 день")
        check(day(of: october?.start) == 15, "период начинается 15-го")
        check(day(of: october?.end) == 14, "период заканчивается 14-го")
        check(october?.contains(date(year: 2026, month: 11, day: 9)) == true, "9 ноября входит в период")

        // 2. A 31st payday clamps to the last day of a short month.
        settings.paydayDay = 31
        let clamped = PeriodService.generatedPeriods(rule: settings.rule, covering: date(year: 2027, month: 2, day: 10))
        let february = clamped.first { month(of: $0.start) == 2 && year(of: $0.start) == 2027 }
        check(day(of: february?.start) == 28, "31-е в феврале превращается в 28-е")

        // 3. Fixed-length periods.
        settings.periodMode = .fixedDays
        settings.fixedLengthDays = 10
        let fixed = PeriodService.generatedPeriods(rule: settings.rule, covering: date(year: 2026, month: 11, day: 9))
        check(fixed.allSatisfy { $0.days == 10 }, "фиксированные периоды по 10 дней")
        check(fixed.count > 5, "фиксированные периоды сгенерированы")

        // 4. Moving one boundary drags its neighbours, with no gap.
        settings.periodMode = .payday
        settings.paydayDay = 15
        for period in periods { context.insert(period) }
        try? context.save()
        let target = periods.first { month(of: $0.start) == 10 && year(of: $0.start) == 2026 }!
        PeriodService.update(
            period: target,
            startDay: date(year: 2026, month: 10, day: 13),
            endDay: date(year: 2026, month: 11, day: 12),
            context: context
        )
        let sorted = PeriodService.sorted(PeriodService.allPeriods(context))
        let index = sorted.firstIndex { $0.id == target.id }!
        check(day(of: target.start) == 13, "начало периода сдвинулось")
        check(day(of: target.end) == 12, "конец периода сдвинулся")
        check(sorted[index - 1].end.addingTimeInterval(1).timeIntervalSince(target.start) < 1, "предыдущий период примкнул")
        check(target.end.addingTimeInterval(1).timeIntervalSince(sorted[index + 1].start) < 1, "следующий период примкнул")
        check(target.isManual, "правка помечена ручной")

        // 5. Account balance = initial + income − expense.
        let account = Account(name: "Тест", currency: .byn, initialAmount: 100, iconName: "creditcard.fill", color: .blue)
        context.insert(account)
        let food = Category(name: "Еда", kind: .expense, color: .green, iconName: "cart.fill", isMandatory: true, isSystem: true)
        let salary = Category(name: "Зарплата", kind: .income, color: .green, iconName: "banknote.fill", isSystem: true)
        context.insert(food)
        context.insert(salary)
        let income = Operation(kind: .income, amount: 50, currency: .byn, date: .now, account: account, category: salary)
        let expense = Operation(kind: .expense, amount: 20, currency: .byn, date: .now, account: account, category: food)
        context.insert(income)
        context.insert(expense)
        try? context.save()
        check(account.balance == 130, "баланс счёта учитывает доходы и расходы")
        check(expense.amountText() == (english ? "−20.00 Br" : "−20,00 Br"), "расход печатается со знаком минус")
        check(income.amountText() == (english ? "+50.00 Br" : "+50,00 Br"), "доход печатается со знаком плюс")
        check(Finance.mandatoryExpenses([income, expense], currency: .byn) == 20, "обязательные расходы посчитаны")
        check(Finance.shareText(0.5) == (english ? "50.0%" : "50,0%"), "доля печатается как процент")

        // 6. Deleting a custom category moves its operations to "Other".
        let fallback = Category(name: "Прочее", kind: .expense, color: .graphite, iconName: "ellipsis.circle.fill", isSystem: true)
        context.insert(fallback)
        let custom = Category(name: "Кофе", kind: .expense, color: .orange, iconName: "cup.and.saucer.fill", isSystem: false)
        context.insert(custom)
        expense.category = custom
        try? context.save()
        CategoryRepository(context: context).delete(custom)
        check(expense.category?.name == "Прочее", "операции переходят в «Прочее» при удалении категории")

        // 7. Cross-currency totals.
        let table = ExchangeRates(
            bynPerUnit: [.byn: 1, .usd: 3, .eur: 3.6, .usdt: 3, .btc: 200_000, .eth: 9_000],
            date: nil,
            fetchedAt: nil,
            source: .nbrb
        )
        let usdAccount = Account(name: "USD", currency: .usd, initialAmount: 100, iconName: "creditcard.fill", color: .sky)
        context.insert(usdAccount)
        check(table.convert(100, from: .usd, to: .byn) == 300, "конвертация USD → BYN")
        check(table.convert(360, from: .byn, to: .eur) == 100, "конвертация BYN → EUR")
        check(table.convert(2, from: .eur, to: .usd) == 2.4, "конвертация EUR → USD")
        check(table.convert(50, from: .byn, to: .byn) == 50, "конвертация в ту же валюту")
        check(Finance.totalConverted([usdAccount], to: .byn, rates: table) == 300, "итог по всем счетам в BYN")
        check(Finance.totalConverted([usdAccount], to: .usd, rates: table) == 100, "итог по всем счетам в USD")
        check(MoneyFormat.string(0.0128, currency: .btc, compact: true) == (english ? "0.0128 ₿" : "0,0128 ₿"), "компактный BTC в сайдбаре")
        check(table.convert(1, from: .eth, to: .byn) == 9_000, "конвертация ETH → BYN")
        check(MoneyFormat.string(0.5, currency: .eth) == (english ? "0.50000000 Ξ" : "0,50000000 Ξ"), "ETH с восемью знаками")

        // 7b. A transfer is two linked legs, moves both balances, and is not
        // counted as ordinary income or expense.
        let transferID = TransferRepository(context: context).create(
            from: account,
            to: usdAccount,
            sent: 30,
            received: 10
        )
        let transferLegs = ((try? context.fetch(FetchDescriptor<Operation>())) ?? [])
            .filter { $0.transferID == transferID }
        check(transferLegs.count == 2, "перевод создаёт две связанные части")
        check(transferLegs.allSatisfy { $0.transferID == transferID }, "обе части ссылаются на один перевод")
        check(account.balance == 100 && usdAccount.balance == 110, "перевод меняет балансы обоих счетов")
        check(
            Finance.sumConverted(transferLegs, kind: .expense, to: .byn, rates: table) == 0
                && Finance.sumConverted(transferLegs, kind: .income, to: .byn, rates: table) == 0,
            "перевод не считается расходом или доходом"
        )
        let transferRequest = DeleteRequest.make(
            operations: transferLegs.filter { $0.kind == .expense },
            settings: settings,
            rates: RateStore(preview: table),
            context: context
        )
        check(transferRequest?.items.count == 2, "удаление одной части расширяется до всего перевода")

        // 7c. A subcategory keeps its parent, inherits mandatory status, and
        // survives its parent's deletion as a normal category.
        let parentCategory = Category(
            name: "Дом",
            kind: .expense,
            color: .blue,
            iconName: "house.fill",
            isMandatory: true,
            isSystem: false
        )
        context.insert(parentCategory)
        let childCategory = Category(
            name: "Ремонт",
            kind: .expense,
            color: .blue,
            iconName: "hammer.fill",
            isMandatory: false,
            isSystem: false
        )
        childCategory.parent = parentCategory
        context.insert(childCategory)
        let childOperation = Operation(
            kind: .expense,
            amount: 10,
            currency: .byn,
            date: .now,
            account: account,
            category: childCategory
        )
        context.insert(childOperation)
        try? context.save()
        check(childCategory.parent?.id == parentCategory.id, "подкатегория знает родителя")
        check(Finance.mandatoryExpenses([childOperation], currency: .byn) == 10, "подкатегория наследует обязательность")
        CategoryRepository(context: context).delete(parentCategory)
        check(childCategory.parent == nil, "подкатегория становится обычной при удалении родителя")

        // 7d. Operations group into day sections with friendly titles.
        let today = Calendar.current.startOfDay(for: .now)
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: today)!
        let todayOperation = Operation(
            kind: .expense,
            amount: 1,
            currency: .byn,
            date: today.addingTimeInterval(3600),
            account: account,
            category: food
        )
        let yesterdayOperation = Operation(
            kind: .expense,
            amount: 1,
            currency: .byn,
            date: yesterday.addingTimeInterval(3600),
            account: account,
            category: food
        )
        let daySections = OperationDaySection.sections(from: [yesterdayOperation, todayOperation])
        check(daySections.count == 2, "операции группируются по дням")
        check(daySections.map(\.title) == (english ? ["Today", "Yesterday"] : ["Сегодня", "Вчера"]),
              "сегодня и вчера подписаны")

        // 8. A newly added row is highlighted; a bulk change is not.
        let highlighter = NewRowHighlighter()
        let rowA = UUID()
        let rowB = UUID()
        highlighter.track([rowA])
        check(highlighter.highlighted.isEmpty, "первая отрисовка не подсвечивает старые строки")
        highlighter.track([rowA, rowB])
        check(highlighter.isNew(rowB), "новая строка получает подсветку")
        check(!highlighter.isNew(rowA), "старая строка остаётся спокойной")
        highlighter.track([rowA, rowB, UUID(), UUID(), UUID(), UUID()])
        check(highlighter.highlighted.count == 1, "массовая вставка не мигает")

        // 9. A clean install opens the welcome flow, and has no demo rows under it.
        let freshDefaults = UserDefaults(suiteName: "montra.selftest.fresh") ?? .standard
        freshDefaults.removePersistentDomain(forName: "montra.selftest.fresh")
        let freshSettings = SettingsStore(defaults: freshDefaults)
        check(!freshSettings.hasCompletedOnboarding, "знакомство не пройдено по умолчанию")

        // 9-0. A launch opens the welcome flow until it is actually finished: the
        // first account is a step inside onboarding, not a completion signal.
        // A store that predates onboarding still opens as before, exactly once.
        let launchSuite = "montra.selftest.onboarding.launch"
        UserDefaults(suiteName: launchSuite)?.removePersistentDomain(forName: launchSuite)
        let launchSettings = SettingsStore(defaults: UserDefaults(suiteName: launchSuite) ?? .standard)
        check(OnboardingLaunch.needsOnboarding(accountCount: 0, settings: launchSettings),
              "первый запуск открывает знакомство")
        check(launchSettings.hasStartedOnboarding, "открытое знакомство запоминается")
        check(OnboardingLaunch.needsOnboarding(accountCount: 1, settings: launchSettings),
              "после перезапуска знакомство возвращается даже со счётом")
        check(!launchSettings.hasCompletedOnboarding, "незавершённое знакомство не считается пройденным")
        check(
            OnboardingStep.afterWelcome(hasExistingAccount: true) == .categories
                && OnboardingStep.afterWelcome(hasExistingAccount: false) == .account,
            "прерванное знакомство не просит второй счёт"
        )
        launchSettings.hasCompletedOnboarding = true
        check(!OnboardingLaunch.needsOnboarding(accountCount: 0, settings: launchSettings),
              "пройденное знакомство не повторяется")

        let legacySuite = "montra.selftest.onboarding.legacy"
        UserDefaults(suiteName: legacySuite)?.removePersistentDomain(forName: legacySuite)
        let legacySettings = SettingsStore(defaults: UserDefaults(suiteName: legacySuite) ?? .standard)
        check(!OnboardingLaunch.needsOnboarding(accountCount: 3, settings: legacySettings),
              "хранилище до знакомства не получает первый запуск")
        check(legacySettings.hasCompletedOnboarding, "хранилище до знакомства считается пройденным")

        let freshContainer = ModelContainerFactory.make(inMemory: true)
        let freshContext = ModelContext(freshContainer)
        SeedData.bootstrap(context: freshContext, settings: freshSettings)
        let freshAccounts = (try? freshContext.fetchCount(FetchDescriptor<Account>())) ?? -1
        let freshCategories = (try? freshContext.fetchCount(FetchDescriptor<Category>())) ?? -1
        check(freshAccounts == 0, "на первом запуске нет демо-счетов")
        check(freshCategories >= 14, "bootstrap создаёт стандартные категории")

        let orphanPlan = PlannedOperation(
            seriesID: UUID(),
            kind: .expense,
            amount: 1,
            currency: .byn,
            date: .now,
            frequency: .month,
            weekdays: [],
            seriesStart: .now,
            seriesEnd: .now,
            account: nil,
            category: nil
        )
        freshContext.insert(orphanPlan)
        try? freshContext.save()

        freshSettings.hasCompletedOnboarding = true
        SeedData.clearEverything(context: freshContext, settings: freshSettings)
        check(!freshSettings.hasCompletedOnboarding, "после удаления всех данных знакомство вернётся")
        check(freshSettings.hasStartedOnboarding, "удаление данных помечает знакомство начатым")
        let leftoverPlans = (try? freshContext.fetchCount(FetchDescriptor<PlannedOperation>())) ?? -1
        check(leftoverPlans == 0, "удаление всех данных убирает и планы")
        let leftoverCategories = (try? freshContext.fetchCount(FetchDescriptor<Category>())) ?? -1
        check(leftoverCategories == 0, "удаление всех данных очищает и категории")

        // 9a. The onboarding category step: skips fall back to "Other", picks
        // are created alongside it, and replaying never duplicates rows.
        let skippedContainer = ModelContainerFactory.make(inMemory: true)
        let skippedContext = ModelContext(skippedContainer)
        SeedData.createStarterCategories(context: skippedContext, selected: [])
        let skipped = (try? skippedContext.fetch(FetchDescriptor<Category>())) ?? []
        check(skipped.count == 2, "пропуск категорий создаёт две запасные")
        check(skipped.allSatisfy { $0.name == "Прочее" }, "запасные категории названы «Прочее»")

        let pickedContainer = ModelContainerFactory.make(inMemory: true)
        let pickedContext = ModelContext(pickedContainer)
        let picked = SeedData.expenseCategories.filter { $0.starter == .food || $0.starter == .transport }
        SeedData.createStarterCategories(context: pickedContext, selected: picked)
        SeedData.createStarterCategories(context: pickedContext, selected: picked)
        let pickedAll = (try? pickedContext.fetch(FetchDescriptor<Category>())) ?? []
        check(pickedAll.count == 4, "выбранные категории не дублируются при повторе")
        check(pickedAll.filter { $0.kind == .expense }.count == 3, "два выбора плюс «Прочее»")

        // 9a-2. The category step opens with exactly housing, food and salary
        // ticked — a first budget needs nothing else, and the rest is one tap away.
        check(
            SeedData.onboardingDefaults.map(\.starter) == [.housing, .food, .salary],
            "знакомство по умолчанию отмечает жильё, еду и зарплату"
        )

        // 9b. A savings flag is just a label: deposits and withdrawals behave
        // exactly like on a regular account.
        let savingsContainer = ModelContainerFactory.make(inMemory: true)
        let savingsContext = ModelContext(savingsContainer)
        let savingsRepository = AccountRepository(context: savingsContext)
        let piggy = savingsRepository.create(
            name: "Копилка", currency: .byn, initialAmount: 150,
            iconName: "building.columns.fill", color: .blue, isSavings: true
        )
        check(piggy.isSavings, "счёт создаётся накопительным")
        check(piggy.balance == 150, "флаг не меняет начальный баланс")

        _ = OperationRepository(context: savingsContext).create(
            kind: .expense, amount: 50, account: piggy, category: nil,
            date: .now, place: "", latitude: nil, longitude: nil, note: ""
        )
        check(piggy.balance == 100, "с накопительного можно списывать")

        _ = OperationRepository(context: savingsContext).create(
            kind: .income, amount: 20, account: piggy, category: nil,
            date: .now, place: "", latitude: nil, longitude: nil, note: ""
        )
        check(piggy.balance == 120, "накопительный можно пополнять")

        savingsRepository.update(
            piggy, name: "Копилка", initialAmount: 150,
            iconName: "building.columns.fill", color: .blue, isSavings: false,
            isHiddenFromOverview: false
        )
        check(!piggy.isSavings, "флаг снимается при редактировании")

        // 9b-2. Hiding from the Overview is a view setting, not a money rule: the
        // account keeps its balance and stays available to the sidebar and API.
        let vacation = savingsRepository.create(
            name: "Отпуск", currency: .usd, initialAmount: 300,
            iconName: "airplane", color: .green, isHiddenFromOverview: true
        )
        check(vacation.isHiddenFromOverview, "счёт создаётся скрытым из обзора")
        check(vacation.balance == 300, "скрытие не меняет баланс")

        savingsRepository.update(
            vacation, name: "Отпуск", initialAmount: 300,
            iconName: "airplane", color: .green, isSavings: false,
            isHiddenFromOverview: false
        )
        check(!vacation.isHiddenFromOverview, "скрытие снимается при редактировании")

        // 9b. Recurring plans: date clamping, weekdays, linking and deletion.
        var planCalendar = Calendar(identifier: .gregorian)
        planCalendar.timeZone = TimeZone(identifier: "Europe/Minsk")!
        let jan31 = planCalendar.date(from: DateComponents(year: 2026, month: 1, day: 31, hour: 10))!
        let apr30 = planCalendar.date(from: DateComponents(year: 2026, month: 4, day: 30, hour: 23))!
        let monthlyDates = PlanSchedule.dates(
            start: jan31,
            end: apr30,
            frequency: .month,
            weekdays: [],
            calendar: planCalendar
        )
        check(monthlyDates.count == 4, "месячный план даёт 4 платежа")
        check(planCalendar.component(.day, from: monthlyDates[1]) == 28, "31-е переносится на конец февраля")
        check(planCalendar.component(.day, from: monthlyDates[2]) == 31, "март возвращается к 31-му")

        let monday = planCalendar.date(from: DateComponents(year: 2026, month: 11, day: 2, hour: 9))!
        let weekEnd = planCalendar.date(from: DateComponents(year: 2026, month: 11, day: 30, hour: 23))!
        let weeklyDates = PlanSchedule.dates(
            start: monday,
            end: weekEnd,
            frequency: .week,
            weekdays: [2, 4],
            calendar: planCalendar
        )
        check(weeklyDates.count == 9, "недельный план учитывает выбранные дни")

        let balanceBeforePlans = account.balance
        let planRepository = PlanRepository(context: context)
        let madePlans = planRepository.create(
            kind: .expense,
            amount: 700,
            account: account,
            category: food,
            date: monday,
            place: "Арендодатель",
            note: "Аренда",
            frequency: .week,
            weekdays: [2, 4],
            end: weekEnd,
            saveImmediately: false
        )
        check(madePlans.count == 9 && Set(madePlans.map(\.seriesID)).count == 1, "серия планов создаётся одной цепочкой")
        check(account.balance == balanceBeforePlans, "планы не меняют баланс счёта")

        let planFact = OperationRepository(context: context).create(
            kind: .expense,
            amount: 700,
            account: account,
            category: food,
            date: monday,
            place: "Арендодатель",
            latitude: nil,
            longitude: nil,
            note: "Факт",
            saveImmediately: false
        )
        planRepository.link(madePlans[0], to: planFact)
        check(madePlans[0].isLinked, "план связывается с фактом")

        let yesterdayPlan = PlannedOperation(
            seriesID: UUID(),
            kind: .expense,
            amount: 1,
            currency: .byn,
            date: Calendar.current.date(byAdding: .day, value: -1, to: .now)!,
            frequency: .month,
            weekdays: [],
            seriesStart: .now,
            seriesEnd: .now,
            account: account,
            category: food
        )
        let tomorrowPlan = PlannedOperation(
            seriesID: UUID(),
            kind: .expense,
            amount: 1,
            currency: .byn,
            date: Calendar.current.date(byAdding: .day, value: 1, to: .now)!,
            frequency: .month,
            weekdays: [],
            seriesStart: .now,
            seriesEnd: .now,
            account: account,
            category: food
        )
        check(yesterdayPlan.isMissed && tomorrowPlan.isUpcoming, "пропущенный и будущий планы различаются")

        planRepository.deleteSeries(madePlans[0])
        let remainingPlans = (try? context.fetch(FetchDescriptor<PlannedOperation>()))?
            .filter { $0.seriesID == madePlans[0].seriesID }.count ?? 0
        check(remainingPlans == 0, "вся серия планов удаляется")

        // 10. Backup: every record, the settings around it and the file format.
        let decimal: (String) -> Decimal = { Decimal(string: $0, locale: Locale(identifier: "en_US_POSIX"))! }
        let base = Date(timeIntervalSince1970: 1_760_000_000)

        let backupSuite = "montra.selftest.backup"
        UserDefaults(suiteName: backupSuite)?.removePersistentDomain(forName: backupSuite)
        let backupSettings = SettingsStore(defaults: UserDefaults(suiteName: backupSuite) ?? .standard)
        backupSettings.appearance = .dark
        backupSettings.hideBalances = true
        backupSettings.primaryCurrency = .usd
        backupSettings.periodMode = .fixedDays
        backupSettings.fixedLengthDays = 14
        backupSettings.periodAnchor = base
        backupSettings.didSeedDemo = true
        backupSettings.hasCompletedOnboarding = true
        backupSettings.hasStartedOnboarding = true

        let backupContainer = ModelContainerFactory.make(inMemory: true)
        let backupContext = ModelContext(backupContainer)

        let cash = Account(
            name: "Наличные", currency: .byn, initialAmount: decimal("420.50"),
            iconName: "banknote.fill", color: .green, sortIndex: 0
        )
        cash.createdAt = base
        let crypto = Account(
            name: "Крипто", currency: .btc, initialAmount: decimal("0.0128"),
            iconName: "💰", color: .amber,
            isSavings: true, isHiddenFromOverview: true, sortIndex: 1
        )
        crypto.createdAt = base
        backupContext.insert(cash)
        backupContext.insert(crypto)

        let home = Category(
            name: "Дом", kind: .expense, color: .blue, iconName: "house.fill",
            isMandatory: true, isSystem: false, sortIndex: 0
        )
        home.createdAt = base
        let repair = Category(
            name: "Ремонт", kind: .expense, color: .blue, iconName: "hammer.fill",
            isMandatory: false, isSystem: false, sortIndex: 1
        )
        repair.createdAt = base
        repair.parent = home
        let salaryCategory = Category(
            name: "Зарплата", kind: .income, color: .green, iconName: "banknote.fill",
            isMandatory: false, isSystem: true, sortIndex: 0
        )
        salaryCategory.createdAt = base
        backupContext.insert(home)
        backupContext.insert(repair)
        backupContext.insert(salaryCategory)

        let backupExpense = Operation(
            kind: .expense, amount: decimal("214.30"), currency: .byn,
            date: base.addingTimeInterval(-3600), place: "Green",
            latitude: 53.9, longitude: 27.5, note: "Продукты",
            account: cash, category: repair
        )
        backupExpense.createdAt = base
        let backupIncome = Operation(
            kind: .income, amount: 4200, currency: .byn,
            date: base.addingTimeInterval(-7200), place: "", note: "",
            account: cash, category: salaryCategory
        )
        backupIncome.createdAt = base.addingTimeInterval(1)
        backupContext.insert(backupExpense)
        backupContext.insert(backupIncome)

        let backupTransferID = UUID()
        let sent = Operation(
            kind: .expense, amount: 30, currency: .byn, date: base.addingTimeInterval(-1800),
            place: "", note: "→ Крипто", account: cash, category: nil
        )
        sent.transferID = backupTransferID
        sent.createdAt = base.addingTimeInterval(2)
        let received = Operation(
            kind: .income, amount: decimal("0.0001"), currency: .btc,
            date: base.addingTimeInterval(-1800), place: "", note: "← Наличные",
            account: crypto, category: nil
        )
        received.transferID = backupTransferID
        received.createdAt = base.addingTimeInterval(3)
        backupContext.insert(sent)
        backupContext.insert(received)

        let plan = PlannedOperation(
            seriesID: UUID(), kind: .expense, amount: 700, currency: .byn,
            date: base.addingTimeInterval(86_400), place: "Арендодатель",
            note: "Аренда", frequency: .week, weekdays: [2, 4],
            seriesStart: base, seriesEnd: base.addingTimeInterval(86_400 * 30),
            account: cash, category: home
        )
        plan.id = UUID()
        plan.createdAt = base
        plan.linkedOperationID = backupExpense.id
        // A mask that differs from the initializer's input proves the file's
        // stored mask is what comes back, not a re-derived one.
        plan.weekdayMask = PlanWeekday.mask(for: [1, 3, 5])
        backupContext.insert(plan)

        let manualPeriod = Period(
            start: base.addingTimeInterval(-86_400 * 10),
            end: base.addingTimeInterval(-1),
            isManual: true
        )
        manualPeriod.createdAt = base
        let autoPeriod = Period(
            start: base,
            end: base.addingTimeInterval(86_400 * 20),
            isManual: false
        )
        autoPeriod.createdAt = base
        backupContext.insert(manualPeriod)
        backupContext.insert(autoPeriod)
        try? backupContext.save()

        let backupRates = ExchangeRates(
            bynPerUnit: [.byn: 1, .usd: decimal("3.1234"), .btc: decimal("227000.5")],
            date: base, fetchedAt: base, source: .nbrb
        )
        let archive: MontraBackup
        do {
            archive = try BackupService.capture(
                context: backupContext,
                settings: backupSettings,
                environment: BackupService.Environment(
                    rates: backupRates,
                    integrationEnabled: true,
                    integrationAllowsDelete: false
                ),
                createdAt: base
            )
        } catch {
            check(false, "копия собирается: \(error.localizedDescription)")
            exit(1)
        }
        check(
            archive.format == BackupCoding.formatIdentifier
                && archive.formatVersion == BackupCoding.currentFormatVersion,
            "копия помечена собственным форматом"
        )
        check(
            archive.summary.accounts == 2 && archive.summary.categories == 3
                && archive.summary.operations == 4 && archive.summary.plans == 1
                && archive.summary.periods == 2,
            "в копию попадают все записи"
        )

        var backupData = Data()
        do {
            backupData = try BackupCoding.encode(archive)
            let decoded = try BackupCoding.decode(backupData)
            check(decoded.payload == archive.payload, "все данные переживают запись и чтение")
            check(
                decoded.payload.accounts.first { $0.currency == "btc" }?.initialAmount == "0.0128",
                "дробная сумма сохраняется точно"
            )
            let storedAmount = decoded.payload.operations.first { $0.id == backupExpense.id }?.amount
            check(
                storedAmount.flatMap { try? BackupDecimal.value($0) } == decimal("214.30"),
                "сумма операции хранится без потерь"
            )
            check(decoded.checksum == archive.checksum, "контрольная сумма сходится")

            // A copy written before the flag existed has no such key. It must
            // still decode and match its own checksum, or old files would be read
            // as corrupted.
            var oldPayload = decoded.payload
            oldPayload.settings.hasStartedOnboarding = nil
            var oldArchive = try BackupCoding.seal(oldPayload)
            oldArchive.formatVersion = 2
            let oldDecoded = try BackupCoding.decode(BackupCoding.encode(oldArchive))
            check(oldDecoded.payload.settings.hasStartedOnboarding == nil,
                  "старая копия без флага знакомства читается")

            let url = FileManager.default.temporaryDirectory
                .appendingPathComponent("montra-selftest-\(UUID().uuidString).montra")
            try BackupService.write(archive, to: url)
            defer { try? FileManager.default.removeItem(at: url) }
            let fromDisk = try BackupService.read(from: url)
            check(fromDisk.payload == archive.payload, "файл копии читается с диска")
        } catch {
            check(false, "копия кодируется и читается: \(error.localizedDescription)")
        }

        let restoreSuite = "montra.selftest.restore"
        UserDefaults(suiteName: restoreSuite)?.removePersistentDomain(forName: restoreSuite)
        let restoredSettings = SettingsStore(defaults: UserDefaults(suiteName: restoreSuite) ?? .standard)
        restoredSettings.hasCompletedOnboarding = true
        let restoreContainer = ModelContainerFactory.make(inMemory: true)
        let restoreContext = ModelContext(restoreContainer)
        let stale = Account(
            name: "Старый", currency: .byn, initialAmount: 1,
            iconName: "banknote.fill", color: .green
        )
        restoreContext.insert(stale)
        try? restoreContext.save()

        do {
            let archiveToRestore = try BackupCoding.decode(backupData)
            let report = try BackupService.restore(
                archiveToRestore, context: restoreContext, settings: restoredSettings
            )
            check(report.summary == archive.summary, "отчёт о восстановлении совпадает с копией")

            let accounts = (try? restoreContext.fetch(FetchDescriptor<Account>())) ?? []
            check(
                accounts.count == 2 && !accounts.contains { $0.id == stale.id },
                "восстановление заменяет текущие счета"
            )
            check(
                accounts.first { $0.id == cash.id }?.balance == decimal("4376.20"),
                "баланс счёта восстановлен с переводами"
            )
            check(
                accounts.first { $0.id == crypto.id }?.balance == decimal("0.0129"),
                "дробный баланс восстановлен точно"
            )
            check(
                accounts.first { $0.id == crypto.id }?.isHiddenFromOverview == true,
                "флаг скрытия счёта восстановлен"
            )
            check(
                accounts.first { $0.id == crypto.id }?.iconName == "💰",
                "эмодзи-иконка счёта переживает копию"
            )

            let categories = (try? restoreContext.fetch(FetchDescriptor<Category>())) ?? []
            check(
                categories.first { $0.id == repair.id }?.parent?.id == home.id,
                "подкатегория восстановлена вместе с родителем"
            )
            check(
                categories.first { $0.id == salaryCategory.id }?.isSystem == true,
                "системная категория осталась системной"
            )

            let operations = (try? restoreContext.fetch(FetchDescriptor<Operation>())) ?? []
            let restoredExpense = operations.first { $0.id == backupExpense.id }
            check(operations.count == 4, "все операции восстановлены")
            check(restoredExpense?.amount == decimal("214.30"), "сумма операции восстановлена точно")
            check(
                restoredExpense?.category?.id == repair.id && restoredExpense?.place == "Green",
                "категория, место и детали операции восстановлены"
            )
            check(restoredExpense?.latitude == 53.9, "координаты операции восстановлены")
            check(
                operations.filter { $0.transferID == backupTransferID }.count == 2,
                "обе части перевода восстановлены"
            )

            let plans = (try? restoreContext.fetch(FetchDescriptor<PlannedOperation>())) ?? []
            check(plans.count == 1 && plans[0].weekdayMask == PlanWeekday.mask(for: [1, 3, 5]),
                  "плановый платёж и дни недели восстановлены")
            check(plans.first?.linkedOperationID == backupExpense.id, "связь плана с фактом восстановлена")

            let periods = (try? restoreContext.fetch(FetchDescriptor<Period>())) ?? []
            check(
                periods.contains { $0.id == manualPeriod.id && $0.isManual }
                    && periods.contains { $0.id == autoPeriod.id && !$0.isManual },
                "периоды восстановлены вместе с ручной правкой"
            )

            check(restoredSettings.appearance == .dark && restoredSettings.hideBalances, "оформление и маска восстановлены")
            check(
                restoredSettings.primaryCurrency == .usd && restoredSettings.periodMode == .fixedDays
                    && restoredSettings.fixedLengthDays == 14 && restoredSettings.periodAnchor == base,
                "валюта и правило периодов восстановлены"
            )
            check(restoredSettings.hasCompletedOnboarding, "знакомство отмечено пройденным")
            check(restoredSettings.hasStartedOnboarding, "запущенное знакомство восстановлено")
            check(report.rates?.rate(for: .usd) == decimal("3.1234"), "курсы из копии доступны для установки")
            check(
                report.integration?.enabled == true && report.integration?.allowDelete == false,
                "настройки локального API восстановлены"
            )
        } catch {
            check(false, "копия восстанавливается: \(error.localizedDescription)")
        }

        // A file whose data was edited after it was written no longer matches its
        // checksum, and a file with a broken reference is rejected before any
        // current record is deleted.
        do {
            if var root = try JSONSerialization.jsonObject(with: backupData) as? [String: Any],
               var payload = root["payload"] as? [String: Any],
               var accounts = payload["accounts"] as? [[String: Any]],
               !accounts.isEmpty {
                accounts[0]["initialAmount"] = "999999"
                payload["accounts"] = accounts
                root["payload"] = payload
                let tampered = try JSONSerialization.data(withJSONObject: root)
                do {
                    _ = try BackupCoding.decode(tampered)
                    check(false, "изменённая сумма отклоняется")
                } catch {
                    check(true, "изменённая сумма отклоняется")
                }
            } else {
                check(false, "файл копии разбирается как JSON")
            }
        } catch {
            check(false, "файл копии разбирается как JSON")
        }

        do {
            _ = try BackupCoding.decode(Data("not a backup".utf8))
            check(false, "посторонний файл отклоняется")
        } catch {
            check(true, "посторонний файл отклоняется")
        }

        do {
            var brokenPayload = archive.payload
            brokenPayload.operations[0].accountID = UUID()
            let broken = try BackupCoding.seal(brokenPayload)

            let guardSuite = "montra.selftest.backup.guard"
            UserDefaults(suiteName: guardSuite)?.removePersistentDomain(forName: guardSuite)
            let guardSettings = SettingsStore(defaults: UserDefaults(suiteName: guardSuite) ?? .standard)
            let guardContainer = ModelContainerFactory.make(inMemory: true)
            let guardContext = ModelContext(guardContainer)
            let keeper = Account(
                name: "Цел", currency: .byn, initialAmount: 7,
                iconName: "banknote.fill", color: .green
            )
            guardContext.insert(keeper)
            try? guardContext.save()

            var rejected = false
            do {
                _ = try BackupService.restore(broken, context: guardContext, settings: guardSettings)
            } catch {
                rejected = true
            }
            let kept = (try? guardContext.fetch(FetchDescriptor<Account>())) ?? []
            check(
                rejected && kept.contains { $0.id == keeper.id },
                "битая ссылка в копии не стирает текущие данные"
            )
        } catch {
            check(false, "битая ссылка в копии не стирает текущие данные: \(error.localizedDescription)")
        }

        // 11. Formatting and plurals.
        check(food.displayName == (english ? "Food" : "Еда"), "старая системная категория отображается на языке приложения")
        check(MoneyFormat.number(1234.56, grouping: false) == (english ? "1234.56" : "1234,56"),
              "автозаполнение суммы перевода без разделителя тысяч")
        check(MoneyFormat.string(1234.56, currency: .byn) == (english ? "1,234.56 Br" : "1\u{202F}234,56 Br"), "локальный формат BYN")
        check(Finance.operationsCountText(1) == (english ? "1 transaction" : "1 операция"), "склонение: 1 операция")
        check(Finance.operationsCountText(3) == (english ? "3 transactions" : "3 операции"), "склонение: 3 операции")
        check(Finance.operationsCountText(11) == (english ? "11 transactions" : "11 операций"), "склонение: 11 операций")
        check(Finance.accountsCountText(2) == (english ? "2 accounts" : "2 счёта"), "склонение: 2 счёта")

        // Spotlight uses the same ledger for its actions and its balance cards.
        do {
            freshSettings.hasCompletedOnboarding = true
            freshSettings.primaryCurrency = .byn
            let spotlightRates = RateStore(preview: table)
            let ledger = SpotlightLedger(context: freshContext, settings: freshSettings, rates: spotlightRates)
            try ledger.createAccount(name: " Карта Spotlight ", currency: .byn, initialAmount: 100)
            try ledger.createAccount(name: "Доллары Spotlight", currency: .usd, initialAmount: 10)
            try ledger.createCategory(name: "Транспорт Spotlight", kind: .expense, isMandatory: true)
            try ledger.createCategory(name: "Доход Spotlight", kind: .income, isMandatory: false)
            let accounts = try ledger.accounts()
            let categories = try ledger.categories()
            let card = accounts.first { $0.name == "Карта Spotlight" }!
            let dollars = accounts.first { $0.name == "Доллары Spotlight" }!
            let transport = categories.first { $0.name == "Транспорт Spotlight" }!
            let earnings = categories.first { $0.name == "Доход Spotlight" }!

            try ledger.createSubcategory(name: "Такси Spotlight", parentID: transport.id)
            let taxi = try ledger.categories().first { $0.name == "Такси Spotlight" }!
            check(taxi.parent?.id == transport.id && taxi.kind == .expense, "Spotlight сохраняет подкатегорию")
            try ledger.createOperation(kind: .expense, amount: SpotlightLedger.parseAmount("12,50"),
                                       accountID: card.id, categoryID: taxi.id)
            try ledger.createOperation(kind: .income, amount: 5, accountID: dollars.id, categoryID: earnings.id)

            do {
                try ledger.transfer(from: card.id, to: dollars.id, sent: 30, received: nil)
                check(false, "Spotlight требует сумму зачисления в другой валюте")
            } catch SpotlightLedgerError.receivedRequired {
                check(card.balance == 87.5 && dollars.balance == 15, "неполный перевод не меняет счета")
            }
            try ledger.transfer(from: card.id, to: dollars.id, sent: 30, received: 10)

            let saved = SpotlightLedger(context: ModelContext(freshContainer), settings: freshSettings, rates: spotlightRates)
            check(try saved.balance(id: card.id).amount == (english ? "57.50 Br" : "57,50 Br"), "Spotlight читает сохранённый баланс")
            let overview = try saved.overview(currency: nil)
            check(overview.total == (english ? "132.50 Br" : "132,50 Br") && overview.accounts.count == 2, "Spotlight показывает итог и все счета")
            check(try saved.overview(currency: .usdc).missingCurrencies == ["BYN", "USD"],
                  "Spotlight отмечает неполный итог")
            freshSettings.hideBalances = true
            check(try saved.balance(id: card.id).amount == freshSettings.money(0, currency: .byn),
                  "Spotlight скрывает баланс по настройке Montra")

        } catch {
            check(false, "Spotlight: \(error.localizedDescription)")
        }

        // 12. Touch Bar: the strip fits the app area and lists every account.
        check(TouchBarLayout.stripWidth(accountCount: 3, available: 373) == 366,
              "полоса счетов занимает три ячейки, когда они влезают")
        check(TouchBarLayout.stripWidth(accountCount: 8, available: 373) == 366,
              "полоса счетов не растёт больше трёх ячеек")
        check(TouchBarLayout.stripWidth(accountCount: 3, available: 240) == 240,
              "полоса счетов ужимается до оставшегося места")
        check(TouchBarLayout.stripWidth(accountCount: 1, available: 373) == TouchBarLayout.accountWidth,
              "один счёт не растягивает полосу")

        let card = MontraTouchBarController.Account(
            id: UUID(), name: "Карта", iconName: "creditcard.fill", isSavings: false
        )
        let savingsAccount = MontraTouchBarController.Account(
            id: UUID(), name: "Копилка", iconName: "banknote.fill", isSavings: true
        )
        let exchange = MontraTouchBarController.Account(
            id: UUID(), name: "Биржа", iconName: "bitcoinsign.circle.fill", isSavings: true
        )
        let touchBar = MontraTouchBarController()
        touchBar.update(accounts: [savingsAccount, card, exchange], route: .overview, isEnabled: true, actions: .init())
        let bar = touchBar.bar
        check(bar.defaultItemIdentifiers == [
            NSTouchBarItem.Identifier("montra.touchbar.overview"),
            NSTouchBarItem.Identifier("montra.touchbar.analytics"),
            MontraTouchBarController.accountsIdentifier,
            NSTouchBarItem.Identifier("montra.touchbar.newOperation"),
        ], "тачбар: дорожки, полоса счетов и новая операция")
        let strip = bar.item(forIdentifier: MontraTouchBarController.accountsIdentifier)?.view as? NSScrubber
        check(strip?.numberOfItems == 3, "полоса тачбара показывает обычный и накопительные счета")
        check(touchBar.accounts.map(\.name) == ["Карта", "Копилка", "Биржа"],
              "накопительные счета идут после обычных")
        touchBar.update(accounts: [savingsAccount, card, exchange], route: .account(exchange.id), isEnabled: true, actions: .init())
        check(strip?.selectedIndex == 2, "открытый счёт подсвечен в полосе тачбара")
        touchBar.update(accounts: [], route: .overview, isEnabled: false, actions: .init())
        check(!bar.defaultItemIdentifiers.contains(MontraTouchBarController.accountsIdentifier),
              "без счетов полоса тачбара не занимает место")

        print(failures == 0 ? "ALL CHECKS PASSED" : "\(failures) CHECK(S) FAILED")
        exit(failures == 0 ? 0 : 1)
    }

    // MARK: - Helpers

    private static func date(year: Int, month: Int, day: Int) -> Date {
        Calendar.current.date(from: DateComponents(year: year, month: month, day: day, hour: 12)) ?? .now
    }

    private static func day(of date: Date?) -> Int {
        guard let date else { return -1 }
        return Calendar.current.component(.day, from: date)
    }

    private static func month(of date: Date?) -> Int {
        guard let date else { return -1 }
        return Calendar.current.component(.month, from: date)
    }

    private static func year(of date: Date?) -> Int {
        guard let date else { return -1 }
        return Calendar.current.component(.year, from: date)
    }
}
