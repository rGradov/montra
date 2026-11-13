#if os(macOS)
import AppKit
import SwiftData
import SwiftUI

/// Renders every screen to a PNG so the design can be compared with the
/// reference pixel by pixel. Launch with `-snapshot <folder>`; the app writes the
/// images and exits before a window ever opens. Uses an in-memory store and its
/// own defaults, so a run never touches real data.
@MainActor
enum SnapshotRunner {
    static func runIfRequested(container: ModelContainer, settings: SettingsStore) {
        let arguments = CommandLine.arguments
        if let animateIndex = arguments.firstIndex(of: "-animate-header"),
           arguments.indices.contains(animateIndex + 1) {
            let directory = URL(fileURLWithPath: arguments[animateIndex + 1], isDirectory: true)
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            renderHeaderAnimation(into: directory)
            exit(0)
        }
        guard let flagIndex = arguments.firstIndex(of: "-snapshot"),
              arguments.indices.contains(flagIndex + 1) else { return }
        let directory = URL(fileURLWithPath: arguments[flagIndex + 1], isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        renderAll(into: directory)
        exit(0)
    }

    private static func renderAll(into directory: URL) {
        let defaults = UserDefaults(suiteName: "montra.snapshot") ?? .standard
        defaults.removePersistentDomain(forName: "montra.snapshot")
        let settings = SettingsStore(defaults: defaults)
        settings.appearance = .dark
        settings.primaryCurrency = .byn

        let previewRates = RateStore(preview: ExchangeRates(
            bynPerUnit: [
                .byn: 1,
                .usd: 3.0010,
                .eur: 3.3460,
                .usdc: 3.0034,
                .usdt: 2.9963,
                .btc: 227_358,
                .eth: 6_705,
            ],
            date: Calendar.current.date(byAdding: .day, value: -1, to: .now),
            fetchedAt: .now,
            source: .nbrb
        ))

        let container = ModelContainerFactory.make(inMemory: true)
        let context = ModelContext(container)
        SeedData.bootstrap(context: context, settings: settings)
        // The app's own first launch is the welcome flow; the visual fixtures
        // still want a lived-in month to render.
        SeedData.seedDemo(context: context, settings: settings)

        let snapshotCategories = (try? context.fetch(FetchDescriptor<Category>())) ?? []
        let coffeeName = String(localized: "demo.coffee")
        if let food = snapshotCategories.first(where: { $0.starterCategory == .food && $0.kind == .expense }) {
            _ = CategoryRepository(context: context).create(
                name: coffeeName,
                kind: .expense,
                color: .orange,
                iconName: "cup.and.saucer.fill",
                isMandatory: false,
                parent: food
            )
        }

        let snapshotAccounts = (try? context.fetch(FetchDescriptor<Account>(sortBy: [SortDescriptor(\.sortIndex)]))) ?? []
        let account = snapshotAccounts.first

        // The demo seed marks "Savings" as a savings account, so the
        // "Savings" group and the savings labels render.

        // Two recurring plans: one overdue and one upcoming, so the plan rows,
        // the missed/upcoming filters and their actions are all visible.
        if let cash = snapshotAccounts.first(where: { $0.currency == .byn }),
           let housing = snapshotCategories.first(where: { $0.starterCategory == .housing && $0.kind == .expense }) {
            let today = Calendar.current.startOfDay(for: .now)
            let end = Calendar.current.date(byAdding: .year, value: 1, to: today) ?? today
            if let missedStart = Calendar.current.date(byAdding: .day, value: -1, to: today) {
                _ = PlanRepository(context: context).create(
                    kind: .expense,
                    amount: 700,
                    account: cash,
                    category: housing,
                    date: missedStart.addingTimeInterval(10 * 3600),
                    place: String(localized: "demo.landlord"),
                    note: String(localized: "demo.rent"),
                    frequency: .month,
                    weekdays: [],
                    end: end
                )
            }
            if let upcomingStart = Calendar.current.date(byAdding: .day, value: 1, to: today) {
                _ = PlanRepository(context: context).create(
                    kind: .expense,
                    amount: 700,
                    account: cash,
                    category: housing,
                    date: upcomingStart.addingTimeInterval(10 * 3600),
                    place: String(localized: "demo.landlord"),
                    note: String(localized: "demo.rent"),
                    frequency: .month,
                    weekdays: [],
                    end: end
                )
            }
        }

        // One transfer so the lists and the read-only detail are visible.
        var transferID: UUID?
        if let source = snapshotAccounts.first(where: { $0.currency == .byn }),
           let destination = snapshotAccounts.first(where: { $0.currency == .eur }) {
            transferID = TransferRepository(context: context).create(
                from: source,
                to: destination,
                sent: 100,
                received: 30
            )
        }

        // A transfer into the savings account, so Analytics can show it as
        // savings rather than spending.
        if let cash = snapshotAccounts.first(where: { $0.currency == .byn && !$0.isSavings }),
           let savings = snapshotAccounts.first(where: { $0.isSavings }) {
            _ = TransferRepository(context: context).create(
                from: cash,
                to: savings,
                sent: 100,
                received: Decimal(100) / Decimal(227_358)
            )
        }

        render(
            AppRootView(initialRoute: .overview).environmentObject(settings).environmentObject(previewRates).modelContainer(container),
            size: CGSize(width: AppWindowLayout.width, height: AppWindowLayout.defaultHeight),
            colorScheme: .dark,
            name: "01-overview-dark",
            chrome: true,
            in: directory
        )

        render(
            AppRootView(initialRoute: .overview).environmentObject(settings).environmentObject(previewRates).modelContainer(container),
            size: CGSize(width: AppWindowLayout.width, height: 1320),
            colorScheme: .dark,
            name: "01b-overview-tall",
            chrome: true,
            in: directory
        )

        // The savings account is hidden: the total, the bar and the list drop it,
        // and the quiet line under the accounts says where it went. Then the flag
        // goes back so every other screen renders the full picture. The fixture
        // seeded through its own ModelContext, while the views read
        // `mainContext`, so the flag is set in the context the screens observe.
        let overviewAccounts = (try? container.mainContext.fetch(
            FetchDescriptor<Account>(sortBy: [SortDescriptor(\.sortIndex)])
        )) ?? []
        if let savingsAccount = overviewAccounts.first(where: { $0.isSavings }) {
            savingsAccount.isHiddenFromOverview = true

            render(
                AppRootView(initialRoute: .overview).environmentObject(settings).environmentObject(previewRates).modelContainer(container),
                size: CGSize(width: AppWindowLayout.width, height: AppWindowLayout.defaultHeight),
                colorScheme: .dark,
                name: "01c-overview-hidden",
                chrome: true,
                in: directory
            )

            savingsAccount.isHiddenFromOverview = false
        }

        render(
            AppRootView(initialRoute: .operations).environmentObject(settings).environmentObject(previewRates).modelContainer(container),
            size: CGSize(width: AppWindowLayout.width, height: AppWindowLayout.defaultHeight),
            colorScheme: .dark,
            name: "02-operations-dark",
            chrome: true,
            in: directory
        )

        if let account {
            render(
                AppRootView(initialRoute: .account(account.id)).environmentObject(settings).environmentObject(previewRates).modelContainer(container),
                size: CGSize(width: AppWindowLayout.width, height: AppWindowLayout.defaultHeight),
                colorScheme: .dark,
                name: "03-account-dark",
                in: directory
            )
        }

        if let eurAccount = (try? context.fetch(FetchDescriptor<Account>(sortBy: [SortDescriptor(\.sortIndex)])))?
            .first(where: { $0.currency == .eur }) {
            render(
                AppRootView(initialRoute: .account(eurAccount.id)).environmentObject(settings).environmentObject(previewRates).modelContainer(container),
                size: CGSize(width: AppWindowLayout.width, height: AppWindowLayout.defaultHeight),
                colorScheme: .dark,
                name: "03b-account-eur-dark",
                chrome: true,
                in: directory
            )
        }

        if let savingsAccount = snapshotAccounts.first(where: { $0.isSavings }) {
            render(
                AppRootView(initialRoute: .account(savingsAccount.id)).environmentObject(settings).environmentObject(previewRates).modelContainer(container),
                size: CGSize(width: AppWindowLayout.width, height: AppWindowLayout.defaultHeight),
                colorScheme: .dark,
                name: "03c-account-savings-dark",
                chrome: true,
                in: directory
            )
        }

        render(
            AppRootView(initialRoute: .categories).environmentObject(settings).environmentObject(previewRates).modelContainer(container),
            size: CGSize(width: AppWindowLayout.width, height: AppWindowLayout.defaultHeight),
            colorScheme: .dark,
            name: "04-categories-dark",
            chrome: true,
            in: directory
        )

        let integration = LocalIntegration(container: container, available: false)

        render(
            AppRootView(initialRoute: .settings)
                .environmentObject(settings)
                .environmentObject(previewRates)
                .environmentObject(integration)
                .modelContainer(container),
            size: CGSize(width: AppWindowLayout.width, height: AppWindowLayout.defaultHeight),
            colorScheme: .dark,
            name: "05-settings-dark",
            chrome: true,
            in: directory
        )

        render(
            AppRootView(initialRoute: .settings)
                .environmentObject(settings)
                .environmentObject(previewRates)
                .environmentObject(integration)
                .modelContainer(container),
            size: CGSize(width: AppWindowLayout.width, height: 1500),
            colorScheme: .dark,
            name: "05b-settings-tall",
            chrome: true,
            in: directory
        )

        if let backup = try? BackupService.capture(
            context: context,
            settings: settings,
            environment: BackupService.Environment(
                rates: previewRates.rates,
                integrationEnabled: integration.enabled,
                integrationAllowsDelete: integration.allowDelete
            )
        ) {
            render(
                BackupRestoreSheet(
                    candidate: BackupRestoreCandidate(archive: backup, fileName: BackupFile.suggestedName()),
                    onRestored: {}
                )
                .environmentObject(settings)
                .environmentObject(previewRates)
                .environmentObject(integration),
                size: CGSize(width: 520, height: 640),
                colorScheme: .dark,
                name: "26-backup-restore",
                in: directory
            )
        }

        render(
            AppRootView(initialRoute: .about).environmentObject(settings).environmentObject(previewRates).modelContainer(container),
            size: CGSize(width: AppWindowLayout.width, height: 1180),
            colorScheme: .dark,
            name: "07b-about-tall",
            chrome: true,
            in: directory
        )

        render(
            AppRootView(initialRoute: .analytics).environmentObject(settings).environmentObject(previewRates).modelContainer(container),
            size: CGSize(width: AppWindowLayout.width, height: AppWindowLayout.defaultHeight),
            colorScheme: .dark,
            name: "06-analytics-dark",
            chrome: true,
            in: directory
        )

        render(
            AppRootView(initialRoute: .analytics).environmentObject(settings).environmentObject(previewRates).modelContainer(container),
            size: CGSize(width: AppWindowLayout.width, height: 1600),
            colorScheme: .dark,
            name: "06b-analytics-tall",
            chrome: true,
            in: directory
        )

        render(
            AppRootView(initialRoute: .about).environmentObject(settings).environmentObject(previewRates).modelContainer(container),
            size: CGSize(width: AppWindowLayout.width, height: AppWindowLayout.defaultHeight),
            colorScheme: .dark,
            name: "07-about-dark",
            chrome: true,
            in: directory
        )

        settings.appearance = .light
        render(
            AppRootView(initialRoute: .overview).environmentObject(settings).environmentObject(previewRates).modelContainer(container),
            size: CGSize(width: AppWindowLayout.width, height: AppWindowLayout.defaultHeight),
            colorScheme: .light,
            name: "08-overview-light",
            chrome: true,
            in: directory
        )

        render(
            AppRootView(initialRoute: .analytics).environmentObject(settings).environmentObject(previewRates).modelContainer(container),
            size: CGSize(width: AppWindowLayout.width, height: 1600),
            colorScheme: .light,
            name: "08b-analytics-light",
            chrome: true,
            in: directory
        )
        settings.appearance = .dark

        // Onboarding, on its own store so the finished screen shows one account
        // and one expense, not the demo month.
        let onboardingContainer = ModelContainerFactory.make(inMemory: true)
        let onboardingContext = ModelContext(onboardingContainer)
        SeedData.createStarterCategories(
            context: onboardingContext,
            selected: SeedData.onboardingDefaults
        )
        let onboardingCategories = (try? onboardingContext.fetch(FetchDescriptor<Category>())) ?? []
        let firstAccount = AccountRepository(context: onboardingContext).create(
            name: String(localized: "demo.cash"),
            currency: .byn,
            initialAmount: 1000,
            iconName: "banknote.fill",
            color: .green
        )
        render(
            OnboardingFlowView(initialStep: .welcome, onFinish: {})
                .environmentObject(settings).environmentObject(previewRates).modelContainer(onboardingContainer),
            size: CGSize(width: AppWindowLayout.width, height: AppWindowLayout.defaultHeight),
            colorScheme: .dark,
            name: "13-onboarding-welcome",
            chrome: true,
            in: directory
        )

        render(
            OnboardingFlowView(initialStep: .categories, onFinish: {})
                .environmentObject(settings).environmentObject(previewRates).modelContainer(onboardingContainer),
            size: CGSize(width: AppWindowLayout.width, height: AppWindowLayout.defaultHeight),
            colorScheme: .dark,
            name: "13b-onboarding-categories",
            chrome: true,
            in: directory
        )

        render(
            OnboardingFlowView(initialStep: .account, onFinish: {})
                .environmentObject(settings).environmentObject(previewRates).modelContainer(onboardingContainer),
            size: CGSize(width: AppWindowLayout.width, height: AppWindowLayout.defaultHeight),
            colorScheme: .dark,
            name: "14-onboarding-account",
            chrome: true,
            in: directory
        )

        render(
            OnboardingFlowView(initialStep: .expense, previewAccount: firstAccount, onFinish: {})
                .environmentObject(settings).environmentObject(previewRates).modelContainer(onboardingContainer),
            size: CGSize(width: AppWindowLayout.width, height: AppWindowLayout.defaultHeight),
            colorScheme: .dark,
            name: "15-onboarding-expense",
            chrome: true,
            in: directory
        )

        let firstExpense = OperationRepository(context: onboardingContext).create(
            kind: .expense,
            amount: 12.50,
            account: firstAccount,
            category: onboardingCategories.first { $0.starterCategory == .food && $0.kind == .expense },
            date: .now,
            place: String(localized: "demo.coffee_shop"),
            latitude: nil,
            longitude: nil,
            note: ""
        )

        render(
            OnboardingFlowView(
                initialStep: .done,
                previewAccount: firstAccount,
                previewExpense: firstExpense,
                isPreview: true,
                onFinish: {}
            )
            .environmentObject(settings).environmentObject(previewRates).modelContainer(onboardingContainer),
            size: CGSize(width: AppWindowLayout.width, height: AppWindowLayout.defaultHeight),
            colorScheme: .dark,
            name: "16-onboarding-done",
            chrome: true,
            in: directory
        )

        render(
            AccountSheet(mode: .create).environmentObject(settings).environmentObject(previewRates).modelContainer(container),
            size: CGSize(width: 470, height: 650),
            colorScheme: .dark,
            name: "09-new-account",
            in: directory
        )

        render(
            AccountSheet(mode: .create, startsAsSavings: true)
                .environmentObject(settings).environmentObject(previewRates).modelContainer(container),
            size: CGSize(width: 470, height: 650),
            colorScheme: .dark,
            name: "09c-new-savings-account",
            in: directory
        )

        if let savingsAccount = (try? container.mainContext.fetch(FetchDescriptor<Account>()))?
            .first(where: { $0.isSavings }) {
            let wasHidden = savingsAccount.isHiddenFromOverview
            savingsAccount.isHiddenFromOverview = true

            render(
                AccountSheet(mode: .edit(savingsAccount)).environmentObject(settings).environmentObject(previewRates).modelContainer(container),
                size: CGSize(width: 470, height: 650),
                colorScheme: .dark,
                name: "09b-account-hidden",
                in: directory
            )

            savingsAccount.isHiddenFromOverview = wasHidden
        }

        // An emoji is stored in the same field as a symbol, so the sheet opens
        // in Emoji mode with the matching favourite already selected.
        render(
            AccountSheet(mode: .edit(
                Account(name: "Копилка", currency: .byn, initialAmount: 0, iconName: "💰", color: .amber)
            ))
            .environmentObject(settings).environmentObject(previewRates).modelContainer(container),
            size: CGSize(width: 470, height: 650),
            colorScheme: .dark,
            name: "09d-account-emoji",
            in: directory
        )

        // The full lists the sheet shows in a popover: the same grid view, so a
        // missing symbol or an empty emoji tile is visible in a snapshot.
        render(
            GlyphPickerPanel(
                mode: .icon,
                catalog: AccountIconCatalog.catalog,
                selection: "creditcard.fill",
                onSelect: { _ in },
                onClose: {}
            ),
            size: CGSize(width: 310, height: 300),
            colorScheme: .dark,
            name: "09e-account-icon-grid",
            in: directory
        )

        render(
            GlyphPickerPanel(
                mode: .emoji,
                catalog: AccountIconCatalog.catalog,
                selection: "💰",
                onSelect: { _ in },
                onClose: {}
            ),
            size: CGSize(width: 310, height: 300),
            colorScheme: .dark,
            name: "09f-account-emoji-grid",
            in: directory
        )

        render(
            OperationSheet(mode: .create(OperationSource(account: account, kind: .expense)))
                .environmentObject(settings).environmentObject(previewRates)
                .modelContainer(container),
            size: CGSize(width: 470, height: 700),
            colorScheme: .dark,
            name: "10-new-operation",
            in: directory
        )

        render(
            OperationSheet(
                mode: .create(OperationSource(account: account, kind: .expense)),
                initialAmount: "42,80"
            )
            .environmentObject(settings).environmentObject(previewRates)
            .modelContainer(container),
            size: CGSize(width: 470, height: 700),
            colorScheme: .dark,
            name: "10a-new-operation-filled",
            in: directory
        )

        render(
            OperationSheet(
                mode: .create(OperationSource(account: account, kind: .expense)),
                initialRepeats: true
            )
            .environmentObject(settings).environmentObject(previewRates)
            .modelContainer(container),
            size: CGSize(width: 470, height: 700),
            colorScheme: .dark,
            name: "10b-new-operation-repeat",
            in: directory
        )

        render(
            OperationSheet(
                mode: .create(OperationSource(account: account, kind: .expense)),
                initialTab: .transfer,
                previewSent: "100"
            )
            .environmentObject(settings).environmentObject(previewRates)
            .modelContainer(container),
            size: CGSize(width: 470, height: 700),
            colorScheme: .dark,
            name: "10c-new-operation-transfer",
            in: directory
        )

        settings.appearance = .light
        render(
            OperationSheet(
                mode: .create(OperationSource(account: account, kind: .expense)),
                initialAmount: "42,80"
            )
            .environmentObject(settings).environmentObject(previewRates)
            .modelContainer(container),
            size: CGSize(width: 470, height: 700),
            colorScheme: .light,
            name: "10d-new-operation-light",
            in: directory
        )
        settings.appearance = .dark

        render(
            PeriodsSheet().environmentObject(settings).environmentObject(previewRates).modelContainer(container),
            size: CGSize(width: 520, height: 660),
            colorScheme: .dark,
            name: "11-periods",
            in: directory
        )

        render(
            ICloudSheet().environmentObject(settings).environmentObject(previewRates).modelContainer(container),
            size: CGSize(width: 470, height: 560),
            colorScheme: .dark,
            name: "12-icloud",
            in: directory
        )

        render(
            MontraDateTimePicker(date: .constant(Date()))
                .padding(AppStyle.Spacing.small)
                .background(AppColors.surfaceBase),
            size: CGSize(width: 332, height: 380),
            colorScheme: .dark,
            name: "17-datetime-picker",
            in: directory
        )

        let pickerCategories = ((try? context.fetch(FetchDescriptor<Category>())) ?? [])
            .filter { $0.kind == .expense }
            .sorted { $0.sortIndex < $1.sortIndex }
        if let food = pickerCategories.first(where: { $0.starterCategory == .food }) {
            render(
                CategoryPickerPopover(categories: pickerCategories, selection: .constant(food.id))
                    .environmentObject(settings)
                    .modelContainer(container),
                size: CGSize(width: 300, height: 390),
                colorScheme: .dark,
                name: "22-category-picker",
                in: directory
            )
        }

        // A category may store an emoji, so a picker row has to draw it as text
        // instead of looking it up as an SF Symbol.
        let emojiPickerCategory = Category(
            name: "Питомцы", kind: .expense, color: .pink, iconName: "🐱"
        )
        render(
            CategoryPickerPopover(
                categories: pickerCategories + [emojiPickerCategory],
                selection: .constant(emojiPickerCategory.id)
            )
            .environmentObject(settings)
            .modelContainer(container),
            size: CGSize(width: 300, height: 390),
            colorScheme: .dark,
            name: "22b-category-picker-emoji",
            in: directory
        )

        if let coffee = pickerCategories.first(where: { $0.name == coffeeName }) {
            render(
                CategorySheet(mode: .edit(coffee))
                    .environmentObject(settings)
                    .modelContainer(container),
                size: CGSize(width: 470, height: 660),
                colorScheme: .dark,
                name: "23-category-sub",
                in: directory
            )
        }

        // The unified appearance section: the same picker as the account sheet,
        // now with the category catalog and the five one-tap glyphs per kind.
        render(
            CategorySheet(mode: .create(.expense))
                .environmentObject(settings)
                .modelContainer(container),
            size: CGSize(width: 470, height: 660),
            colorScheme: .dark,
            name: "23b-category-create",
            in: directory
        )

        render(
            GlyphPickerPanel(
                mode: .icon,
                catalog: CategoryIcons.catalog(for: .expense),
                selection: "cat.fill",
                onSelect: { _ in },
                onClose: {}
            ),
            size: CGSize(width: 310, height: 470),
            colorScheme: .dark,
            name: "23c-category-icon-grid",
            in: directory
        )

        render(
            GlyphPickerPanel(
                mode: .emoji,
                catalog: CategoryIcons.catalog(for: .expense),
                selection: "🐱",
                onSelect: { _ in },
                onClose: {}
            ),
            size: CGSize(width: 310, height: 470),
            colorScheme: .dark,
            name: "23d-category-emoji-grid",
            in: directory
        )

        // A category can store an emoji in the same field as a symbol, so the
        // sheet opens in Emoji mode with the matching favourite selected.
        render(
            CategorySheet(mode: .edit(
                Category(name: "Питомцы", kind: .expense, color: .pink, iconName: "🐱")
            ))
            .environmentObject(settings)
            .modelContainer(container),
            size: CGSize(width: 470, height: 660),
            colorScheme: .dark,
            name: "23e-category-emoji",
            in: directory
        )

        if let source = snapshotAccounts.first(where: { $0.currency == .byn }) {
            render(
                OperationSheet(
                    mode: .create(OperationSource(account: source, kind: nil)),
                    initialTab: .transfer,
                    previewSent: "100"
                )
                .environmentObject(settings)
                .environmentObject(previewRates)
                .modelContainer(container),
                size: CGSize(width: 470, height: 700),
                colorScheme: .dark,
                name: "20-transfer",
                in: directory
            )
        }

        if let source = snapshotAccounts.first {
            render(
                OperationSheet(
                    mode: .create(OperationSource(account: source, kind: .expense)),
                    initialRepeats: true
                )
                .environmentObject(settings)
                .environmentObject(previewRates)
                .modelContainer(container),
                size: CGSize(width: 470, height: 720),
                colorScheme: .dark,
                name: "24-new-plan",
                in: directory
            )
        }

        if let demoPlan = (try? context.fetch(FetchDescriptor<PlannedOperation>()))?.first(where: { $0.isMissed }) {
            render(
                PlanActionSheet(planID: demoPlan.id) { _ in }
                    .environmentObject(settings)
                    .environmentObject(previewRates)
                    .modelContainer(container),
                size: CGSize(width: 470, height: 660),
                colorScheme: .dark,
                name: "25-plan-actions",
                in: directory
            )
        }

        if let transferID {
            render(
                TransferDetailSheet(transferID: transferID)
                    .environmentObject(settings)
                    .environmentObject(previewRates)
                    .modelContainer(container),
                size: CGSize(width: 470, height: 380),
                colorScheme: .dark,
                name: "21-transfer-detail",
                in: directory
            )
        }

        let operations = (try? context.fetch(FetchDescriptor<Operation>())) ?? []
        let deleteOperations = ["Gastrobar", String(localized: "demo.city_center"), String(localized: "demo.landing_page")]
            .compactMap { value in operations.first { $0.place == value || $0.note == value } }
        guard let deleteRequest = DeleteRequest.make(
            operations: deleteOperations, settings: settings, rates: previewRates, context: context
        ) else { return }

        render(
            DeleteOperationsSheet(items: deleteRequest.items, totalText: deleteRequest.totalText, onDelete: {}),
            size: CGSize(width: 540, height: 600),
            colorScheme: .dark,
            name: "18-delete-confirm",
            in: directory
        )

        render(
            DeleteSuccessView(totalText: deleteRequest.totalText, count: deleteRequest.items.count, elapsed: 0.2, onDone: {}),
            size: CGSize(width: 540, height: 600),
            colorScheme: .dark,
            name: "19-delete-success",
            in: directory
        )
    }

    /// Debug-only: records the real account -> overview route transition frame
    /// by frame, so the header animation can be inspected without screen capture.
    private static func renderHeaderAnimation(into directory: URL) {
        let defaults = UserDefaults(suiteName: "montra.animation") ?? .standard
        defaults.removePersistentDomain(forName: "montra.animation")
        let settings = SettingsStore(defaults: defaults)
        settings.appearance = .dark
        settings.primaryCurrency = .byn
        let previewRates = RateStore(preview: ExchangeRates(
            bynPerUnit: [.byn: 1, .usd: 3.0010, .eur: 3.3460, .usdc: 3.0034, .usdt: 2.9963, .btc: 227_358, .eth: 6_705],
            date: Calendar.current.date(byAdding: .day, value: -1, to: .now),
            fetchedAt: .now,
            source: .nbrb
        ))
        let container = ModelContainerFactory.make(inMemory: true)
        let context = ModelContext(container)
        SeedData.bootstrap(context: context, settings: settings)
        SeedData.seedDemo(context: context, settings: settings)
        let accounts = (try? context.fetch(FetchDescriptor<Account>(sortBy: [SortDescriptor(\.sortIndex)]))) ?? []
        guard let account = accounts.first else { return }

        NSApp.appearance = NSAppearance(named: .darkAqua)
        let size = CGSize(width: AppWindowLayout.width, height: AppWindowLayout.defaultHeight)
        let content = AppRootView(initialRoute: .account(account.id))
            .frame(width: size.width, height: size.height, alignment: .topLeading)
            .environment(\.colorScheme, .dark)
            .environmentObject(settings)
            .environmentObject(previewRates)
            .modelContainer(container)
        let hosting = NSHostingView(rootView: content)
        hosting.frame = CGRect(origin: .zero, size: size)
        let window = NSWindow(
            contentRect: CGRect(origin: .zero, size: size),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.appearance = NSAppearance(named: .darkAqua)
        window.backgroundColor = .clear
        window.contentView = hosting
        window.setFrameOrigin(NSPoint(x: 20, y: 20))
        window.orderFrontRegardless()

        hosting.layoutSubtreeIfNeeded()
        RunLoop.current.run(until: Date().addingTimeInterval(0.9))
        NotificationCenter.default.post(name: .montraGoOverview, object: nil)

        for index in 0..<60 {
            RunLoop.current.run(until: Date().addingTimeInterval(1.0 / 60.0))
            hosting.layoutSubtreeIfNeeded()
            guard let rep = hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds) else { continue }
            hosting.cacheDisplay(in: hosting.bounds, to: rep)
            let data = rep.representation(using: .png, properties: [:])
            let url = directory.appendingPathComponent(String(format: "frame_%03d.png", index))
            try? data?.write(to: url)
        }
    }

    private static func render<V: View>(
        _ view: V,
        size: CGSize,
        colorScheme: ColorScheme,
        name: String,
        chrome: Bool = false,
        in directory: URL
    ) {
        let appearance = colorScheme == .dark ? NSAppearance(named: .darkAqua) : NSAppearance(named: .aqua)
        let previous = NSApp.appearance
        NSApp.appearance = appearance

        let base = view
            .frame(width: size.width, height: size.height, alignment: .topLeading)
            .environment(\.colorScheme, colorScheme)
            .background(AppColors.surfaceBase)

        let content = base.overlay(alignment: .topLeading) {
            if chrome {
                SnapshotTrafficLights()
                    .padding(.leading, 18)
                    .padding(.top, 16)
            }
        }

        let hosting = NSHostingView(rootView: content)
        hosting.frame = CGRect(origin: .zero, size: size)

        let window = NSWindow(
            contentRect: CGRect(origin: .zero, size: size),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.appearance = appearance
        window.backgroundColor = .clear
        window.contentView = hosting
        window.setFrameOrigin(NSPoint(x: -30_000, y: -30_000))
        window.orderBack(nil)

        hosting.layoutSubtreeIfNeeded()
        // Long enough for entry fades and staggered reveals to finish, so a
        // screenshot never catches a half-faded title.
        RunLoop.current.run(until: Date().addingTimeInterval(1.0))
        hosting.layoutSubtreeIfNeeded()

        guard let rep = hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds) else {
            NSApp.appearance = previous
            return
        }
        hosting.cacheDisplay(in: hosting.bounds, to: rep)
        if let png = rep.representation(using: .png, properties: [:]) {
            try? png.write(to: directory.appendingPathComponent("\(name).png"))
        }

        window.contentView = nil
        NSApp.appearance = previous
    }
}

private struct SnapshotTrafficLights: View {
    var body: some View {
        HStack(spacing: 8) {
            Circle().fill(Color(hex: 0xFF5F57)).frame(width: 12, height: 12)
            Circle().fill(Color(hex: 0xFEBC2E)).frame(width: 12, height: 12)
            Circle().fill(Color(hex: 0x28C840)).frame(width: 12, height: 12)
        }
        .accessibilityHidden(true)
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
#endif
