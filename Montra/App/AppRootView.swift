import SwiftData
import SwiftUI

struct AppRootView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @EnvironmentObject private var settings: SettingsStore
    @EnvironmentObject private var rates: RateStore

    @Query(sort: [SortDescriptor(\Account.sortIndex, order: .forward)]) private var accounts: [Account]
    @Query(sort: [SortDescriptor(\Category.sortIndex, order: .forward)]) private var categories: [Category]
    @Query private var operations: [Operation]
    @Query(sort: [SortDescriptor(\Period.start, order: .forward)]) private var periods: [Period]

    @StateObject private var app: AppModel
    @StateObject private var headerHost = DetailHeaderHost()
    @State private var didBootstrap = false
    @State private var showsOnboarding: Bool
    @State private var showsOnboardingIntro: Bool
    @State private var isOnboardingExiting = false
    @State private var periodRevision = 0
    @State private var lastSheetID: String?
    @State private var onboardingReplay: OnboardingReplay?
    @State private var isReplayExiting = false
    @State private var onboardingHeroSource: OnboardingHeroFrame?
    @State private var welcomeArtworkFrame: CGRect = .zero
    @State private var sidebarAccountFrames: [UUID: CGRect] = [:]
    @State private var heroAccount: Account?
    @State private var heroPosition: CGPoint = .zero
    @State private var heroSize: CGSize = .zero
    @State private var heroScale: CGFloat = 1
    @State private var heroShowsChrome = true
    @State private var hiddenSidebarAccountID: UUID?

    init(initialRoute: Route = .overview, needsOnboarding: Bool = false) {
        _app = StateObject(wrappedValue: AppModel(route: initialRoute))
        _showsOnboarding = State(initialValue: needsOnboarding)
        _showsOnboardingIntro = State(initialValue: needsOnboarding)
    }

    var body: some View {
        ZStack {
            appShell
                .opacity(showsOnboarding && !isOnboardingExiting ? 0 : 1)
                .blur(radius: showsOnboarding && !isOnboardingExiting ? 10 : 0)
                .allowsHitTesting(!showsOnboarding)

            if showsOnboarding {
                OnboardingFlowView(
                    resumeAccount: didBootstrap ? nil : accounts.first,
                    onFinish: completeOnboarding
                )
                    .background(AppColors.surfaceBase)
                    .opacity(isOnboardingExiting ? 0 : 1)
                    .blur(radius: isOnboardingExiting ? 12 : 0)
                    // The icon holds its focus until the mascot has landed on it
                    // and faded into it. The swap from the flying mascot to the
                    // painted one then happens out of focus, where the two cannot
                    // be told apart, and the icon focuses up around the mascot
                    // that is already in place.
                    .environment(\.welcomeArtworkWaitsForMori, isIntroVisible)
                    // The first run opens with Mori on the soundtrack's peak;
                    // the flow underneath waits, so a stray Return cannot skip it.
                    .disabled(isIntroVisible)
                    // The intro belongs on top of the flow, not beside it in the
                    // stack: its glow is bigger than the window, and as a sibling
                    // it would stretch the stack and push the welcome column down
                    // until the intro goes away.
                    .overlay {
                        if isIntroVisible {
                            OnboardingIntroView(
                                landing: OnboardingHero.flight(toArtwork: welcomeArtworkFrame),
                                onFinished: { showsOnboardingIntro = false }
                            )
                        }
                    }
                    .zIndex(10)
            }

            if let replay = onboardingReplay {
                onboardingReplayOverlay(replay)
            }

            if let account = heroAccount {
                OnboardingAccountHeroChip(
                    account: account,
                    masked: settings.hideBalances,
                    showsChrome: heroShowsChrome
                )
                .frame(width: heroSize.width, height: heroSize.height)
                .scaleEffect(heroScale)
                .position(heroPosition)
                .zIndex(30)
            }
        }
        .coordinateSpace(name: OnboardingHero.coordinateSpace)
        .onPreferenceChange(OnboardingHeroSourceKey.self) { onboardingHeroSource = $0 }
        .onPreferenceChange(SidebarAccountFramesKey.self) { sidebarAccountFrames = $0 }
        .onPreferenceChange(OnboardingWelcomeArtworkKey.self) { welcomeArtworkFrame = $0 ?? .zero }
        .animation(.easeInOut(duration: 0.45), value: isOnboardingExiting)
        .background {
            TouchBarHost(
                accounts: accounts.map {
                    .init(id: $0.id, name: $0.name, iconName: $0.iconName, isSavings: $0.isSavings)
                },
                route: app.route,
                isEnabled: canUseTouchBar,
                actions: .init(
                    openOverview: { app.open(.overview) },
                    openAnalytics: { app.open(.analytics) },
                    newOperation: {
                        app.present(.newOperation(OperationSource(account: selectedAccount, kind: nil)))
                    },
                    openAccount: { id in
                        guard accounts.contains(where: { $0.id == id }) else { return }
                        app.open(.account(id))
                    }
                )
            )
        }
        .sheet(item: $app.sheet) { sheet in
            sheetContent(sheet)
                .environmentObject(settings)
        }
        .task {
            // The welcome flow creates the categories and the first account; a
            // launch that opens onboarding must not seed the full default set
            // behind it.
            if !showsOnboarding { bootstrap() }
            // With Reduce Motion on the intro is skipped; mark it consumed so
            // toggling the setting later cannot make it appear retroactively.
            if reduceMotion { showsOnboardingIntro = false }
            await rates.refreshIfNeeded()
        }
        .onChange(of: settings.rule) { _, _ in
            PeriodService.regenerate(context: context, settings: settings)
        }
        .onChange(of: app.sheet?.id) { _, newID in
            // The header sits behind the sheet, so its animation would play
            // unseen. Replay it once the sheet is gone.
            if newID == nil, lastSheetID == AppSheet.periods.id {
                Task { @MainActor in
                    try? await Task.sleep(nanoseconds: 200_000_000)
                    withAnimation(.easeInOut(duration: 0.4)) { periodRevision += 1 }
                }
            }
            lastSheetID = newID
        }
        .onReceive(NotificationCenter.default.publisher(for: .montraNewOperation)) { _ in
            guard !isCovered else { return }
            app.present(.newOperation(OperationSource(account: nil, kind: nil)))
        }
        .onReceive(NotificationCenter.default.publisher(for: .montraNewAccount)) { _ in
            guard !isCovered else { return }
            app.present(.newAccount(isSavings: false))
        }
        .onReceive(NotificationCenter.default.publisher(for: .montraGoOverview)) { _ in
            guard !isCovered else { return }
            app.open(.overview)
        }
        .onReceive(NotificationCenter.default.publisher(for: .montraGoOperations)) { _ in
            guard !isCovered else { return }
            app.open(.operations)
        }
        .onReceive(NotificationCenter.default.publisher(for: .montraGoCategories)) { _ in
            guard !isCovered else { return }
            app.open(.categories)
        }
        .onReceive(NotificationCenter.default.publisher(for: .montraGoAnalytics)) { _ in
            guard !isCovered else { return }
            app.open(.analytics)
        }
        .onReceive(NotificationCenter.default.publisher(for: .montraGoSettings)) { _ in
            guard !isCovered else { return }
            app.open(.settings)
        }
    }

    private var appShell: some View {
        HStack(spacing: 0) {
            SidebarView(
                route: $app.route,
                accounts: accounts,
                categoryCount: categories.count,
                iCloudConnected: false,
                hiddenAccountID: hiddenSidebarAccountID,
                onNewAccount: { app.present(.newAccount(isSavings: false)) },
                onNewSavingsAccount: { app.present(.newAccount(isSavings: true)) },
                onOpenAccount: { account in app.open(.account(account.id)) },
                onOpenSettings: { app.open(.settings) },
                onOpenAbout: { app.open(.about) },
                onOpenICloud: { app.present(.iCloud) }
            )

            Rectangle()
                .fill(AppColors.borderSubtle)
                .frame(width: 1)
                .frame(maxHeight: .infinity)
                .ignoresSafeArea(.container, edges: .top)

            detail
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AppColors.surfaceBase)
    }

    private var isCovered: Bool {
        showsOnboarding || onboardingReplay != nil
    }

    /// The mascot intro is decorative: with Reduce Motion on, the welcome step
    /// opens directly and no music plays.
    private var isIntroVisible: Bool {
        showsOnboardingIntro && !reduceMotion
    }

    private var canUseTouchBar: Bool {
        !isCovered && app.sheet == nil
    }

    private var selectedAccount: Account? {
        guard case .account(let id) = app.route else { return nil }
        return accounts.first(where: { $0.id == id })
    }

    private var onboardingReplayOverlay: (OnboardingReplay) -> AnyView {
        { replay in
            AnyView(
                ZStack(alignment: .topTrailing) {
                    OnboardingFlowView(onFinish: finishOnboardingReplay)
                        .modelContainer(replay.container)
                        .environmentObject(replay.settings)
                        .background(AppColors.surfaceBase)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)

                    Text(String(localized: "onboarding.preview"))
                        .font(AppStyle.Typography.metadata)
                        .foregroundStyle(AppColors.textTertiary)
                        .padding(.horizontal, AppStyle.Spacing.small)
                        .padding(.vertical, AppStyle.Spacing.xxSmall)
                        .background(AppColors.surfaceRaised.opacity(0.8), in: Capsule(style: .continuous))
                        .padding(.top, AppStyle.Spacing.medium)
                        .padding(.leading, AppStyle.Spacing.large)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

                    Button {
                        finishOnboardingReplay()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 10, weight: .semibold))
                    }
                    .buttonStyle(.montra(.secondary, size: .small, width: .square))
                    .keyboardShortcut(.cancelAction)
                    .padding(.top, AppStyle.Spacing.medium)
                    .padding(.trailing, AppStyle.Spacing.large)
                    .accessibilityLabel(String(localized: "common.close_onboarding"))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(AppColors.surfaceBase)
                .opacity(isReplayExiting ? 0 : 1)
                .blur(radius: isReplayExiting ? 12 : 0)
                .zIndex(20)
                .transition(.opacity)
            )
        }
    }

    private func startOnboardingReplay() {
        guard onboardingReplay == nil, !showsOnboarding else { return }

        let container = ModelContainerFactory.make(inMemory: true)

        let defaults = UserDefaults(suiteName: "montra.onboarding.replay") ?? .standard
        defaults.removePersistentDomain(forName: "montra.onboarding.replay")
        let previewSettings = SettingsStore(defaults: defaults)
        // Keep the window's appearance as the person set it; the preview store
        // otherwise resets it to Auto.
        previewSettings.appearance = settings.appearance

        withAnimation(.easeInOut(duration: 0.35)) {
            onboardingReplay = OnboardingReplay(container: container, settings: previewSettings)
        }
    }

    private func finishOnboardingReplay() {
        guard onboardingReplay != nil, !isReplayExiting else { return }
        app.open(.overview)
        withAnimation(.easeInOut(duration: 0.45)) {
            isReplayExiting = true
        }

        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 450_000_000)
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                onboardingReplay = nil
                isReplayExiting = false
            }
        }
    }

    private func openOperation(_ operation: Operation) {
        if operation.isTransfer, let transferID = operation.transferID {
            app.present(.transferDetails(transferID))
        } else {
            app.present(.editOperation(operation))
        }
    }

    /// Sends the new account from the onboarding card into its sidebar row.
    /// Falls back to the plain fade when either end of the flight was not
    /// measured (for example with Reduce Motion on).
    private func beginAccountHeroIfPossible() {
        guard !reduceMotion,
              let account = accounts.first,
              let source = onboardingHeroSource,
              source.accountID == account.id,
              let target = sidebarAccountFrames[account.id]
        else { return }

        heroAccount = account
        heroSize = target.size
        heroPosition = CGPoint(x: source.rect.midX, y: source.rect.midY)
        heroScale = 1.35
        heroShowsChrome = true
        hiddenSidebarAccountID = account.id

        Task { @MainActor in
            // Mount the chip on its source frame, then let the spring take it.
            try? await Task.sleep(nanoseconds: 20_000_000)
            withAnimation(.spring(response: 0.58, dampingFraction: 0.84)) {
                heroPosition = CGPoint(x: target.midX, y: target.midY)
                heroScale = 1
            }

            try? await Task.sleep(nanoseconds: 600_000_000)
            // Reveal the real row under the chip, then fade the chip's card.
            withAnimation(.easeOut(duration: 0.14)) {
                heroShowsChrome = false
                hiddenSidebarAccountID = nil
            }

            try? await Task.sleep(nanoseconds: 160_000_000)
            heroAccount = nil
            heroScale = 1.35
            heroShowsChrome = true
        }
    }

    private func showOnboardingAfterClear() {
        // Deleting everything is a fresh start, not a state the person should
        // have to restart the app to leave: show the real first-run flow now,
        // opening with the mascot scene as on a real first launch.
        app.open(.overview)
        isOnboardingExiting = false
        withAnimation(.easeInOut(duration: 0.35)) {
            showsOnboardingIntro = !reduceMotion
            showsOnboarding = true
        }
    }

    /// A restored backup has just replaced the store under every screen, so the
    /// route goes back to the Overview: account pages may point at ids that no
    /// longer exist. An empty backup made before the welcome flow returns the
    /// app to that first run, mirroring the launch rules.
    private func showAfterRestore() {
        didBootstrap = true
        if settings.hasCompletedOnboarding {
            periodRevision += 1
            app.open(.overview)
        } else {
            showOnboardingAfterClear()
        }
    }

    private func completeOnboarding() {
        guard !isOnboardingExiting else { return }
        settings.hasCompletedOnboarding = true
        app.open(.overview)
        // Periods (and categories, if a preview skipped the step) are ensured
        // once the real data is in place.
        SeedData.bootstrap(context: context, settings: settings)
        didBootstrap = true
        beginAccountHeroIfPossible()
        withAnimation(.easeInOut(duration: 0.45)) {
            isOnboardingExiting = true
        }

        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 450_000_000)
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                showsOnboarding = false
                isOnboardingExiting = false
            }
        }
    }

    private var routeKey: String {
        switch app.route {
        case .account(let id): "account-\(id)"
        default: "\(app.route)"
        }
    }

    private var detail: some View {
        VStack(spacing: 0) {
            SharedDetailHeader(host: headerHost)

            ZStack {
                AppColors.surfaceBase.ignoresSafeArea()

                Group {
                    switch app.route {
                case .overview:
                    OverviewView(
                        periodRevision: periodRevision,
                        onNewOperation: { account in
                            app.present(.newOperation(OperationSource(account: account, kind: nil)))
                        },
                        onNewAccount: { app.present(.newAccount(isSavings: false)) },
                        onOpenAccount: { account in app.open(.account(account.id)) },
                        onOpenPeriods: { app.present(.periods) },
                        onOpenOperations: { app.open(.operations) },
                        onEditOperation: openOperation
                    )

                case .operations:
                    OperationsView(
                        onBack: { app.open(.overview) },
                        onNewOperation: { kind in
                            app.present(.newOperation(OperationSource(account: nil, kind: kind)))
                        },
                        onEditOperation: openOperation,
                        onOpenPlan: { plan in app.present(.planActions(plan.id)) }
                    )

                case .categories:
                    CategoriesView(
                        onNewCategory: { kind in app.present(.newCategory(kind)) },
                        onEditCategory: { category in app.present(.editCategory(category)) }
                    )

                case .analytics:
                    AnalyticsView(
                        onNewOperation: {
                            app.present(.newOperation(OperationSource(account: nil, kind: nil)))
                        }
                    )

                case .settings:
                    SettingsView(
                        onOpenPeriods: { app.present(.periods) },
                        onOpenICloud: { app.present(.iCloud) },
                        onDataCleared: showOnboardingAfterClear,
                        onDataRestored: showAfterRestore
                    )

                case .about:
                    AboutView(onReplayOnboarding: startOnboardingReplay)

                case .account(let id):
                    if let account = accounts.first(where: { $0.id == id }) {
                        AccountDetailView(
                            account: account,
                            onBack: { app.open(.overview) },
                            onEdit: { app.present(.editAccount(account)) },
                            onNewOperation: { kind in
                                app.present(.newOperation(OperationSource(account: account, kind: kind)))
                            },
                            onEditOperation: openOperation,
                            onOpenPlan: { plan in app.present(.planActions(plan.id)) }
                        )
                        .id(account.id)
                    } else {
                        EmptyState(
                            symbol: "questionmark.circle",
                            title: String(localized: "app.account_not_found"),
                            message: String(localized: "app.it_may_have_been_deleted"),
                            actionTitle: String(localized: "app.back_to_overview"),
                            action: { app.open(.overview) }
                        )
                    }
                    }
                }
                .id(routeKey)
                .transition(.opacity)
                .environmentObject(headerHost)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .animation(AppMotion.route, value: routeKey)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private func sheetContent(_ sheet: AppSheet) -> some View {
        switch sheet {
        case .newOperation(let source):
            OperationSheet(mode: .create(source))
        case .editOperation(let operation):
            OperationSheet(mode: .edit(operation))
        case .transferDetails(let transferID):
            TransferDetailSheet(transferID: transferID)
        case .planActions(let planID):
            PlanActionSheet(planID: planID) { plan in
                app.sheet = .newOperation(OperationSource(
                    account: plan.account,
                    kind: plan.kind,
                    planned: plan
                ))
            }
        case .newAccount(let isSavings):
            AccountSheet(mode: .create, startsAsSavings: isSavings)
        case .editAccount(let account):
            AccountSheet(mode: .edit(account))
        case .newCategory(let kind):
            CategorySheet(mode: .create(kind))
        case .editCategory(let category):
            CategorySheet(mode: .edit(category))
        case .periods:
            PeriodsSheet()
        case .iCloud:
            ICloudSheet()
        }
    }

    private func bootstrap() {
        guard !didBootstrap else { return }
        didBootstrap = true
        SeedData.bootstrap(context: context, settings: settings)
    }
}

/// A throwaway store and settings for replaying the welcome flow from About,
/// so a replay never creates a duplicate account in the real data.
private struct OnboardingReplay: Identifiable {
    let id = UUID()
    let container: ModelContainer
    let settings: SettingsStore
}
