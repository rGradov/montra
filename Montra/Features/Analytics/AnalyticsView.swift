import SwiftData
#if os(macOS)
import AppKit
#endif
import SwiftUI

/// The Analytics screen: how much left, where it went, whether the pace is
/// faster than the last period, and which days carried the spending.
struct AnalyticsView: View {
    @EnvironmentObject private var settings: SettingsStore
    @EnvironmentObject private var headerHost: DetailHeaderHost
    @EnvironmentObject private var rates: RateStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @Query(sort: [SortDescriptor(\Operation.date, order: .reverse)]) private var operations: [Operation]
    @Query(sort: [SortDescriptor(\Period.start, order: .forward)]) private var periods: [Period]
    @Query(sort: [SortDescriptor(\Category.name, order: .forward)]) private var allCategories: [Category]
    @AppStorage("analytics.hiddenCategoryIDs") private var hiddenCategoryIDsRaw = ""

    var onNewOperation: () -> Void = {}

    @State private var scope: AnalyticsScope = .period
    @State private var selectedPeriodID: UUID?
    @State private var selectedMonthStart: Date?
    @State private var selectedYearStart: Date?
    /// The day's popup lives at page level so it floats above every card and is
    /// never clipped by the heat card or by the scroll view.
    @State private var popupDay: AnalyticsDay?
    @State private var popupSize: CGSize = .zero
    @State private var popupFrameGlobal = CGRect.null
    @State private var popupAnchorFrameGlobal = CGRect.null
    @State private var shotReported = false
    @State private var shotBox = AnalyticsShotBox()

    private var calendar: Calendar { .current }
    private var now: Date { .now }

    private var currentPeriod: Period? {
        PeriodService.currentPeriod(in: periods)
    }

    private var availablePeriods: [Period] {
        if let currentPeriod {
            return periods.filter { $0.start <= currentPeriod.start }
        }
        return periods.filter { $0.start <= now }
    }

    private var selectedPeriod: Period? {
        availablePeriods.first { $0.id == selectedPeriodID }
            ?? currentPeriod
            ?? availablePeriods.last
    }

    private var monthStarts: [Date] {
        let first = availablePeriods.first?.start ?? now
        let start = calendar.dateInterval(of: .month, for: first)?.start ?? first
        let current = calendar.dateInterval(of: .month, for: now)?.start ?? now
        var months: [Date] = []
        var cursor = start
        while cursor <= current {
            months.append(cursor)
            guard let next = calendar.date(byAdding: .month, value: 1, to: cursor) else { break }
            cursor = next
        }
        if months.isEmpty { months = [current] }
        return months
    }

    private var selectedMonth: Date? {
        if let selectedMonthStart,
           monthStarts.contains(where: { calendar.isDate($0, equalTo: selectedMonthStart, toGranularity: .month) }) {
            return selectedMonthStart
        }
        return monthStarts.last
    }

    private var yearStarts: [Date] {
        let first = availablePeriods.first?.start ?? now
        let startYear = calendar.dateInterval(of: .year, for: first)?.start ?? first
        let currentYear = calendar.dateInterval(of: .year, for: now)?.start ?? now
        var years: [Date] = []
        var cursor = startYear
        while cursor <= currentYear {
            years.append(cursor)
            guard let next = calendar.date(byAdding: .year, value: 1, to: cursor) else { break }
            cursor = next
        }
        if years.isEmpty { years = [currentYear] }
        return years
    }

    private var selectedYear: Date? {
        if let selectedYearStart,
           yearStarts.contains(where: { calendar.isDate($0, equalTo: selectedYearStart, toGranularity: .year) }) {
            return selectedYearStart
        }
        return yearStarts.last
    }

    private var range: AnalyticsRange? {
        switch scope {
        case .period:
            guard let selectedPeriod else { return nil }
            let index = availablePeriods.firstIndex { $0.id == selectedPeriod.id }
            let previous = index.flatMap { $0 > 0 ? availablePeriods[$0 - 1] : nil }
            return AnalyticsEngine.periodRange(period: selectedPeriod, previous: previous)
        case .month:
            guard let selectedMonth else { return nil }
            return AnalyticsEngine.monthRange(containing: selectedMonth)
        case .year:
            guard let selectedYear else { return nil }
            return AnalyticsEngine.yearRange(containing: selectedYear)
        }
    }

    private var snapshot: AnalyticsSnapshot? {
        guard let range else { return nil }
        return AnalyticsEngine.snapshot(
            range: range,
            operations: operations,
            displayCurrency: settings.primaryCurrency,
            rates: rates.rates,
            hiddenCategoryIDs: hiddenCategoryIDs
        )
    }

    private var displayCurrency: Currency { settings.primaryCurrency }
    private var masked: Bool { settings.hideBalances }

    private var hiddenCategoryIDs: Set<UUID> {
        Set(hiddenCategoryIDsRaw.split(separator: ",").compactMap { UUID(uuidString: String($0)) })
    }

    private func toggleCategory(_ id: UUID) {
        var set = hiddenCategoryIDs
        if set.contains(id) { set.remove(id) } else { set.insert(id) }
        hiddenCategoryIDsRaw = set.map(\.uuidString).joined(separator: ",")
    }

    private func showAllCategories() {
        hiddenCategoryIDsRaw = ""
    }

    private var debugPopupDay: Int? {
        guard let raw = ProcessInfo.processInfo.environment["MONTRA_ANALYTICS_POPUP"] else { return nil }
        return Int(raw)
    }

    private var subtitle: String {
        guard let snapshot else { return String(localized: "analytics.no_data") }
        var parts = [
            snapshot.range.spanTitle,
            Finance.operationsCountText(snapshot.operationsCount)
        ]
        if snapshot.range.isCurrent, snapshot.range.daysLeft > 0 {
            parts.append(Finance.daysText(snapshot.range.daysLeft) + String(localized: "period.time_left_suffix"))
        }
        return parts.joined(separator: " · ")
    }

    private var canGoBack: Bool {
        switch scope {
        case .period:
            guard let selectedPeriod,
                  let index = availablePeriods.firstIndex(where: { $0.id == selectedPeriod.id }) else { return false }
            return index > 0
        case .month:
            guard let selectedMonth,
                  let index = monthStarts.firstIndex(where: { calendar.isDate($0, equalTo: selectedMonth, toGranularity: .month) }) else { return false }
            return index > 0
        case .year:
            guard let selectedYear,
                  let index = yearStarts.firstIndex(where: { calendar.isDate($0, equalTo: selectedYear, toGranularity: .year) }) else { return false }
            return index > 0
        }
    }

    private var canGoForward: Bool {
        switch scope {
        case .period:
            guard let selectedPeriod,
                  let index = availablePeriods.firstIndex(where: { $0.id == selectedPeriod.id }) else { return false }
            return index < availablePeriods.count - 1
        case .month:
            guard let selectedMonth,
                  let index = monthStarts.firstIndex(where: { calendar.isDate($0, equalTo: selectedMonth, toGranularity: .month) }) else { return false }
            return index < monthStarts.count - 1
        case .year:
            guard let selectedYear,
                  let index = yearStarts.firstIndex(where: { calendar.isDate($0, equalTo: selectedYear, toGranularity: .year) }) else { return false }
            return index < yearStarts.count - 1
        }
    }

    private var headerKey: String {
        "\(scope.rawValue)|\(range?.title ?? "")|\(subtitle)|\(canGoBack)|\(canGoForward)"
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: AppStyle.Spacing.large) {
                        if let snapshot, snapshot.hasExpenses {
                            AnalyticsSummaryCard(
                                snapshot: snapshot,
                                currency: displayCurrency,
                                masked: masked
                            )

                            AnalyticsBreakdownCard(
                                snapshot: snapshot,
                                currency: displayCurrency,
                                masked: masked,
                                allCategories: allCategories,
                                hiddenCategoryIDs: hiddenCategoryIDs,
                                onToggleCategory: toggleCategory,
                                onShowAllCategories: showAllCategories
                            )

                            AnalyticsPaceCard(
                                snapshot: snapshot,
                                currency: displayCurrency,
                                masked: masked,
                                metric: $settings.spendMetric
                            )

                            if scope == .year {
                                AnalyticsYearMonthsCard(
                                    snapshot: snapshot,
                                    currency: displayCurrency,
                                    masked: masked
                                )
                            } else {
                                AnalyticsHeatCard(
                                    snapshot: snapshot,
                                    currency: displayCurrency,
                                    masked: masked,
                                    popupDay: $popupDay,
                                    initialActiveDay: debugPopupDay
                                )
                                .id(heatCardID)
                            }
                        } else {
                            OverviewCard {
                                if hiddenCategoryIDs.isEmpty {
                                    EmptyState(
                                        symbol: "chart.bar",
                                        title: scope == .year
                                            ? String(localized: "analytics.empty_year")
                                            : (scope == .month
                                                ? String(localized: "analytics.empty_month")
                                                : String(localized: "analytics.empty_period")),
                                        message: String(localized: "analytics.empty_message"),
                                        actionTitle: String(localized: "transaction.new"),
                                        action: onNewOperation
                                    )
                                } else {
                                    EmptyState(
                                        symbol: "eye.slash",
                                        title: String(localized: "analytics.hidden_categories_empty"),
                                        message: String(localized: "analytics.hidden_categories_empty_message"),
                                        actionTitle: String(localized: "analytics.show_all_categories"),
                                        action: showAllCategories
                                    )
                                }
                            }
                        }
                    }
                    .padding(.horizontal, AppDetailPageLayout.horizontalInset)
                    .padding(.bottom, AppStyle.Spacing.large + shotBottomRoom)
                }
                .shellBottomRoom()
                .background(AppColors.surfaceBase)
                .onScrollGeometryChange(for: CGFloat.self) { geometry in
                    geometry.contentOffset.y
                } action: { previous, current in
                    // A page scroll moves the anchor out from under the popup, so
                    // close it instead of letting it point at the wrong cell.
                    guard popupDay != nil, abs(current - previous) > 8 else { return }
                    closePopup()
                }
                .task { await prepareDebugLaunch(proxy) }
            }
            #if os(macOS)
            .overlayPreferenceValue(AnalyticsHeatAnchorKey.self) { anchors in
                popupOverlay(anchors)
            }
            #endif
        }
        .background(AppColors.surfaceBase)
        .onAppear {
            if selectedPeriodID == nil {
                selectedPeriodID = currentPeriod?.id ?? availablePeriods.last?.id
            }
            if selectedMonthStart == nil {
                selectedMonthStart = calendar.dateInterval(of: .month, for: now)?.start
            }
            switch ProcessInfo.processInfo.environment["MONTRA_ANALYTICS_SCOPE"] {
            case "month": scope = .month
            case "year": scope = .year
            default: break
            }
            // QA screenshots can ask for a past month, so a day with many
            // categories can be captured from real data.
            if let raw = ProcessInfo.processInfo.environment["MONTRA_ANALYTICS_MONTH"],
               let requested = launchMonth(from: raw),
               monthStarts.contains(where: { calendar.isDate($0, equalTo: requested, toGranularity: .month) }) {
                selectedMonthStart = requested
            }
            syncHeader()
        }
        .onChange(of: headerKey) { _, _ in syncHeader() }
        .onChange(of: snapshot?.range) { _, _ in closePopup() }
        .onKeyPress(.escape) {
            guard popupDay != nil else { return .ignored }
            closePopup()
            return .handled
        }
        #if os(macOS)
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didResignActiveNotification)) { _ in
            // QA captures drive the app while the harness owns the screen, so an
            // activation change must not remove the popup mid-capture.
            guard !isShotMode else { return }
            closePopup()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didResignKeyNotification)) { _ in
            guard !isShotMode else { return }
            closePopup()
        }
        #endif
        #if os(macOS)
        .modifier(
            AnalyticsPopupDismissModifier(
                isActive: popupDay != nil,
                popupFrame: popupFrameGlobal,
                anchorCellFrame: popupAnchorFrameGlobal,
                onDismiss: closePopup
            )
        )
        #else
        .sheet(item: $popupDay) { day in
            AnalyticsDaySheet(day: day, currency: displayCurrency, masked: masked)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
                .presentationContentInteraction(.scrolls)
        }
        #endif
    }

    private var heatCardID: String { "analytics.heat" }

    private var isShotMode: Bool {
        ProcessInfo.processInfo.environment["MONTRA_ANALYTICS_SHOT"] == "1"
    }

    private var shotTopAnchor: Bool {
        isShotMode && ProcessInfo.processInfo.environment["MONTRA_ANALYTICS_SHOT_ANCHOR"] == "top"
    }

    /// The heat card is the last block, so aligning it to the page top needs room
    /// below it. Only the QA screenshots that capture the "no room above" branch
    /// add that room; normal launches keep the tight page.
    private var shotBottomRoom: CGFloat {
        shotTopAnchor ? 360 : 0
    }

    /// The snapshot is rebuilt on every body pass, so resolve the popup by id and
    /// fall back to the stored day only when the day disappeared.
    private var popupDayResolved: AnalyticsDay? {
        guard let popupDay else { return nil }
        return snapshot?.days.first(where: { $0.id == popupDay.id }) ?? popupDay
    }

    // MARK: - Day popup

    private func closePopup() {
        guard popupDay != nil else { return }
        popupDay = nil
        popupFrameGlobal = .null
        popupAnchorFrameGlobal = .null
    }

    @ViewBuilder
    private func popupOverlay(_ anchors: [Int: Anchor<CGRect>]) -> some View {
        GeometryReader { geometry in
            if let day = popupDayResolved,
               let anchor = anchors[day.id],
               !day.groups.isEmpty {
                let cell = geometry[anchor]
                let globalOrigin = geometry.frame(in: .global).origin
                let layout = AnalyticsPopupLayout.make(
                    cell: cell,
                    popupHeight: popupSize.height,
                    pageSize: geometry.size,
                    pageOriginY: globalOrigin.y
                )
                let cellGlobal = cell.offsetBy(dx: globalOrigin.x, dy: globalOrigin.y)

                AnalyticsDayPopup(
                    day: day,
                    currency: displayCurrency,
                    masked: masked,
                    width: layout.width,
                    caretX: layout.caretX,
                    caretSide: layout.side
                )
                .frame(width: layout.width)
                .fixedSize(horizontal: false, vertical: true)
                .onGeometryChange(for: CGSize.self) { proxy in
                    proxy.size
                } action: { size in
                    if popupSize != size { popupSize = size }
                }
                .offset(x: layout.x, y: layout.y)
                .opacity(popupSize.height > 0 ? 1 : 0)
                // `.offset` is a visual shift: `proxy.frame(in: .global)` keeps
                // reporting the popup at the overlay's origin, which made every
                // click on the page look like a click on the card. Publish the
                // drawn rect instead, from the same origin + layout the harness
                // checks against the pixels.
                .onChange(of: popupGlobalRect(layout: layout, origin: globalOrigin)) { _, rect in
                    popupFrameGlobal = rect
                }
                .transition(isShotMode ? .opacity : popupTransition(layout))
                .onAppear {
                    popupFrameGlobal = popupGlobalRect(layout: layout, origin: globalOrigin)
                    popupAnchorFrameGlobal = cellGlobal
                    updateShotBox(day: day, cell: cell, pageOrigin: globalOrigin, pageSize: geometry.size)
                }
                .onChange(of: cellGlobal) { _, _ in
                    popupAnchorFrameGlobal = cellGlobal
                    updateShotBox(day: day, cell: cell, pageOrigin: globalOrigin, pageSize: geometry.size)
                }
                .task(id: "shot-\(day.id)") {
                    // Report only after the popup has settled: the first measuring
                    // pass and the entry transition both move the card for a moment.
                    guard isShotMode else { return }
                    try? await Task.sleep(nanoseconds: 900_000_000)
                    reportShot()
                }
            }
        }
        .animation(
            isShotMode || reduceMotion ? nil : .easeOut(duration: 0.12),
            value: popupDay == nil
        )
    }

    private func popupTransition(_ layout: AnalyticsPopupLayout) -> AnyTransition {
        guard !reduceMotion else { return .opacity }
        return .opacity.combined(
            with: .scale(scale: 0.98, anchor: layout.side == .above ? .bottom : .top)
        )
    }

    /// The popup's drawn rect in the same corner-based space the click monitor
    /// uses. The height is the measured card, so the rect follows the card instead
    /// of the layout input that moved it.
    private func popupGlobalRect(layout: AnalyticsPopupLayout, origin: CGPoint) -> CGRect {
        CGRect(
            x: origin.x + layout.x,
            y: origin.y + layout.y,
            width: layout.width,
            height: popupSize.height
        )
    }

    /// Keeps the harness' inputs live without touching view state.
    private func updateShotBox(day: AnalyticsDay, cell: CGRect, pageOrigin: CGPoint, pageSize: CGSize) {
        guard isShotMode else { return }
        shotBox.day = day
        shotBox.cell = cell
        shotBox.pageOrigin = pageOrigin
        shotBox.pageSize = pageSize
    }

    /// Scrolls the heat card into view and opens the requested day, then reports
    /// the layout to the screenshot harness.
    private func prepareDebugLaunch(_ proxy: ScrollViewProxy) async {
        let popupRequest = ProcessInfo.processInfo.environment["MONTRA_ANALYTICS_POPUP"]
        guard isShotMode || popupRequest != nil || ProcessInfo.processInfo.environment["MONTRA_ANALYTICS_SCOPE"] != nil else {
            return
        }
        // The first pass still reads `@Query` and applies the debug scope.
        try? await Task.sleep(nanoseconds: 200_000_000)
        if isShotMode, debugPopupDay != nil, scope != .year {
            // The default keeps the whole grid on screen; `top` puts the first row
            // near the page top so the "no room above" placement can be captured.
            let anchor: UnitPoint = ProcessInfo.processInfo.environment["MONTRA_ANALYTICS_SHOT_ANCHOR"] == "top"
                ? .top
                : .bottom
            proxy.scrollTo(heatCardID, anchor: anchor)
            try? await Task.sleep(nanoseconds: 450_000_000)
        }
        if ProcessInfo.processInfo.environment["MONTRA_ANALYTICS_POPUP"] == "first" {
            popupDay = snapshot?.days.first(where: { !$0.groups.isEmpty })
        } else if let id = debugPopupDay, let day = snapshot?.days.first(where: { $0.id == id }) {
            popupDay = day.groups.isEmpty ? nil : day
        }
        guard isShotMode else { return }
        // The popup itself reports after it settles; this only covers the days
        // that legitimately have no popup, so it waits longer than that report.
        try? await Task.sleep(nanoseconds: 2_400_000_000)
        reportMissingPopupIfNeeded()
    }

    private func reportShot() {
        guard isShotMode, !shotReported,
              popupSize.height > 0,
              let day = shotBox.day else { return }
        shotReported = true
        // Recompute from the settled inputs: `popupSize` is read live, so the
        // offsets below are the ones SwiftUI actually applies now.
        let layout = AnalyticsPopupLayout.make(
            cell: shotBox.cell,
            popupHeight: popupSize.height,
            pageSize: shotBox.pageSize,
            pageOriginY: shotBox.pageOrigin.y
        )
        let popup = CGRect(
            x: shotBox.pageOrigin.x + layout.x,
            y: shotBox.pageOrigin.y + layout.y,
            width: layout.width,
            height: popupSize.height
        )
        let cell = shotBox.cell.offsetBy(dx: shotBox.pageOrigin.x, dy: shotBox.pageOrigin.y)
        let payload: [String: Any] = [
            "day": day.id,
            "window": windowJSON(),
            "scale": Double(windowScale),
            "cell": rectJSON(cell),
            "popup": rectJSON(popup),
            "side": layout.side.rawValue,
            "clamped": layout.isClamped,
            "caretX": Double(popup.minX + layout.caretX),
            "caretOffsetX": Double(layout.caretX),
            "coversCell": popup.intersects(cell),
            "groupCount": day.groups.count,
            // Rows that are laid out without inner scrolling. This is the only
            // row count in the payload: a second field equal to `groupCount`
            // would make the height check circular.
            "visibleRowCount": min(day.groups.count, AnalyticsDayPopup.maxRows),
            "pageTop": Double(shotBox.pageOrigin.y),
            "popupHeight": Double(popupSize.height),
        ]
        print("ANALYTICS_SHOT_JSON \(json(payload))")
        // A redirected stdout is block-buffered; the harness kills the app, so flush.
        fflush(stdout)
    }

    private func reportMissingPopupIfNeeded() {
        guard isShotMode, !shotReported, let id = debugPopupDay else { return }
        shotReported = true
        let reason: String
        if let day = snapshot?.days.first(where: { $0.id == id }) {
            reason = day.isFuture ? "future" : (day.groups.isEmpty ? "empty" : "notPlaced")
        } else {
            reason = "missing"
        }
        let payload: [String: Any] = [
            "day": id,
            "popup": NSNull(),
            "reason": reason,
            "window": windowJSON(),
            "scale": Double(windowScale),
        ]
        print("ANALYTICS_SHOT_JSON \(json(payload))")
        fflush(stdout)
    }

    /// Window telemetry feeds the macOS screenshot harness only; on iOS the
    /// shot mode is driven by `simctl` and needs no window coordinates.
    private var windowScale: CGFloat {
        #if os(macOS)
        shotWindow?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 1
        #else
        1
        #endif
    }

    #if os(macOS)
    private var shotWindow: NSWindow? {
        NSApp.windows.first { $0.isVisible && $0.contentView != nil }
    }
    #endif

    /// The window's frame in the same corner-based space `screencapture -R` uses,
    /// so the harness can capture exactly the window.
    private func windowJSON() -> [String: Double] {
        #if os(macOS)
        guard let window = shotWindow else {
            return ["x": 0, "y": 0, "w": Double(AppWindowLayout.width),
                    "h": Double(AppWindowLayout.defaultHeight)]
        }
        let screen = window.screen ?? NSScreen.main
        let originY = (screen?.frame.maxY ?? 0) - window.frame.maxY
        return [
            "x": Double(window.frame.minX),
            "y": Double(originY),
            "w": Double(window.frame.width),
            "h": Double(window.frame.height),
        ]
        #else
        return ["x": 0, "y": 0, "w": 0, "h": 0]
        #endif
    }

    private func rectJSON(_ rect: CGRect) -> [String: Double] {
        [
            "x": Double(rect.minX),
            "y": Double(rect.minY),
            "w": Double(rect.width),
            "h": Double(rect.height),
        ]
    }

    private func json(_ payload: [String: Any]) -> String {
        let data = (try? JSONSerialization.data(
            withJSONObject: payload,
            options: [.sortedKeys]
        )) ?? Data("{}".utf8)
        return String(decoding: data, as: UTF8.self)
    }

    private func launchMonth(from raw: String) -> Date? {
        let parts = raw.split(separator: "-")
        guard parts.count == 2,
              let year = Int(parts[0]),
              let month = Int(parts[1]),
              (1...12).contains(month) else { return nil }
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = 1
        return calendar.date(from: components)
    }

    private func syncHeader() {
        headerHost.config = DetailHeaderConfig(
            title: String(localized: "navigation.analytics"),
            subtitle: subtitle,
            backTitle: nil,
            onBack: nil,
            trailing: AnyView(
                AnalyticsHeaderControls(
                    scope: scope,
                    title: range?.title ?? "",
                    canGoBack: canGoBack,
                    canGoForward: canGoForward,
                    onBack: { step(-1) },
                    onForward: { step(1) },
                    onScope: changeScope
                )
            )
        )
    }

    private func step(_ delta: Int) {
        switch scope {
        case .period:
            guard let selectedPeriod,
                  let index = availablePeriods.firstIndex(where: { $0.id == selectedPeriod.id }) else { return }
            let next = index + delta
            guard availablePeriods.indices.contains(next) else { return }
            selectedPeriodID = availablePeriods[next].id
        case .month:
            guard let selectedMonth,
                  let index = monthStarts.firstIndex(where: { calendar.isDate($0, equalTo: selectedMonth, toGranularity: .month) }) else { return }
            let next = index + delta
            guard monthStarts.indices.contains(next) else { return }
            selectedMonthStart = monthStarts[next]
        case .year:
            guard let selectedYear,
                  let index = yearStarts.firstIndex(where: { calendar.isDate($0, equalTo: selectedYear, toGranularity: .year) }) else { return }
            let next = index + delta
            guard yearStarts.indices.contains(next) else { return }
            selectedYearStart = yearStarts[next]
        }
    }

    private func changeScope(_ newScope: AnalyticsScope) {
        guard newScope != scope else { return }
        switch newScope {
        case .month:
            let reference: Date
            if scope == .year, let selectedYear {
                reference = calendar.isDate(selectedYear, equalTo: now, toGranularity: .year)
                    ? now
                    : (calendar.date(byAdding: .year, value: 1, to: selectedYear)?
                        .addingTimeInterval(-1) ?? selectedYear)
            } else if let selectedPeriod, selectedPeriod.contains(now) {
                reference = now
            } else {
                reference = selectedPeriod?.end ?? now
            }
            selectedMonthStart = calendar.dateInterval(of: .month, for: reference)?.start
        case .period:
            let month = selectedMonth ?? calendar.dateInterval(of: .month, for: now)?.start ?? now
            let monthEnd = calendar.date(byAdding: .month, value: 1, to: month)?
                .addingTimeInterval(-1) ?? month
            let reference = min(now, monthEnd)
            selectedPeriodID = availablePeriods.first { $0.contains(reference) }?.id
                ?? currentPeriod?.id
                ?? availablePeriods.last?.id
        case .year:
            selectedYearStart = calendar.dateInterval(
                of: .year,
                for: selectedMonth ?? selectedPeriod?.end ?? now
            )?.start
        }
        withAnimation(reduceMotion ? nil : AppMotion.page) {
            scope = newScope
        }
    }
}

// MARK: - Header controls

private struct AnalyticsHeaderControls: View {
    let scope: AnalyticsScope
    let title: String
    let canGoBack: Bool
    let canGoForward: Bool
    let onBack: () -> Void
    let onForward: () -> Void
    let onScope: (AnalyticsScope) -> Void

    var body: some View {
        HStack(spacing: AppStyle.Spacing.xSmall) {
            HStack(spacing: 0) {
                ForEach(AnalyticsScope.allCases) { option in
                    Button {
                        onScope(option)
                    } label: {
                        Text(option.title)
                            .font(AppStyle.Typography.metadataEmphasis)
                            .foregroundStyle(option == scope ? AppColors.textPrimary : AppColors.textSecondary)
                            .padding(.horizontal, AppStyle.Spacing.xSmall)
                            .frame(height: 20)
                            .background {
                                Capsule(style: .continuous)
                                    .fill(option == scope ? AppColors.surfaceRaised : .clear)
                            }
                            .contentShape(Capsule(style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(option.title)
                    .accessibilityAddTraits(option == scope ? .isSelected : [])
                }
            }
            .padding(2)
            .background {
                Capsule(style: .continuous).fill(AppColors.fillSecondary)
            }
            .overlay {
                Capsule(style: .continuous).strokeBorder(AppColors.borderSubtle, lineWidth: 0.5)
            }

            HStack(spacing: 0) {
                Button(action: onBack) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 9, weight: .semibold))
                        .frame(width: 22, height: 22)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(!canGoBack)
                .opacity(canGoBack ? 1 : 0.35)
                .accessibilityLabel(String(localized: "analytics.previous"))

                HStack(spacing: AppStyle.Spacing.xxSmall) {
                    Image(systemName: "calendar")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(AppColors.textSecondary)
                        .accessibilityHidden(true)
                    Text(figures: title, style: AppStyle.Typography.metadata)
                        .monospacedDigit()
                        .lineLimit(1)
                }
                .padding(.horizontal, AppStyle.Spacing.xxSmall)
                .frame(height: 22)

                Button(action: onForward) {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 9, weight: .semibold))
                        .frame(width: 22, height: 22)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(!canGoForward)
                .opacity(canGoForward ? 1 : 0.35)
                .accessibilityLabel(String(localized: "analytics.next"))
            }
            .foregroundStyle(AppColors.textSecondary)
            .padding(.horizontal, 2)
            .background {
                Capsule(style: .continuous).fill(AppColors.fillSecondary)
            }
            .overlay {
                Capsule(style: .continuous).strokeBorder(AppColors.borderSubtle, lineWidth: 0.5)
            }
        }
    }
}

// MARK: - Summary

private struct AnalyticsSummaryCard: View {
    let snapshot: AnalyticsSnapshot
    let currency: Currency
    let masked: Bool

    @State private var revealed = false

    var body: some View {
        OverviewCard {
            HStack(alignment: .top, spacing: 0) {
                SummaryCell(
                    label: String(localized: "common.expenses"),
                    value: money(revealed ? snapshot.expenses : 0),
                    sub: AnyView(expenseSub)
                )

                divider

                SummaryCell(
                    label: String(localized: "common.income"),
                    value: money(revealed ? snapshot.income : 0),
                    sub: AnyView(incomeSub)
                )

                divider

                SummaryCell(
                    label: String(localized: "analytics.remaining"),
                    value: money(revealed ? snapshot.remaining : 0),
                    sub: AnyView(remainingSub)
                )
            }
            .padding(.vertical, AppStyle.Spacing.small)

            if snapshot.hasSavings {
                InsetCardDivider(horizontalInset: AppStyle.Row.cardHorizontalPadding)
                VStack(spacing: 0) {
                    if snapshot.savingsIn > 0 {
                        savingsRow(
                            title: String(localized: "analytics.savings_in"),
                            detail: String(localized: "analytics.savings_in_detail"),
                            value: money(snapshot.savingsIn),
                            positive: true
                        )
                    }
                    if snapshot.savingsOut > 0 {
                        savingsRow(
                            title: String(localized: "analytics.savings_out"),
                            detail: String(localized: "analytics.savings_out_detail"),
                            value: money(-snapshot.savingsOut),
                            positive: false
                        )
                    }
                }
            }
        }
        .onAppear { revealed = true }
    }

    private func savingsRow(title: String, detail: String, value: String, positive: Bool) -> some View {
        HStack(spacing: AppStyle.Spacing.small) {
            Image(systemName: "lock.fill")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(AppColors.Chart.teal)
                .frame(width: AppStyle.Row.listIconFrameSize)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: AppStyle.Spacing.xxxSmall) {
                Text(title)
                    .font(AppStyle.Typography.headline)
                Text(detail)
                    .font(AppStyle.Typography.metadata)
                    .foregroundStyle(AppColors.textSecondary)
            }

            Spacer(minLength: AppStyle.Spacing.small)

            Text(value)
                .font(AnalyticsStyle.amount)
                .monospacedDigit()
                .foregroundStyle(positive ? AppColors.statusSafeText : AppColors.textSecondary)
        }
        .padding(.horizontal, AppStyle.Row.cardHorizontalPadding)
        .padding(.vertical, AppStyle.Spacing.xSmall)
    }

    private var divider: some View {
        Rectangle()
            .fill(AppColors.borderSubtle)
            .frame(width: 0.5)
            .padding(.vertical, AppStyle.Spacing.xxSmall)
    }

    @ViewBuilder
    private var expenseSub: some View {
        if snapshot.hasComparison, snapshot.comparisonTotal > 0 {
            let delta = delta
            HStack(spacing: 3) {
                Image(systemName: delta >= 0 ? "arrow.up.right" : "arrow.down.right")
                    .font(.system(size: 9, weight: .semibold))
                Text(figures: String(localized: "analytics.vs_previous \(AnalyticsFormat.percent(delta))"),
                     style: AppStyle.Typography.metadata)
            }
            .foregroundStyle(delta >= 0 ? AppColors.statusCheckText : AppColors.statusSafeText)
        } else {
            Text(String(localized: "analytics.no_previous_period"))
                .font(AppStyle.Typography.metadata)
                .foregroundStyle(AppColors.textTertiary)
        }
    }

    private var incomeSub: some View {
        Text(figures: String(localized: "analytics.income_count \(snapshot.incomeCount)"),
             style: AppStyle.Typography.metadata)
            .foregroundStyle(AppColors.textSecondary)
    }

    @ViewBuilder
    private var remainingSub: some View {
        if snapshot.income > 0 {
            Text(figures: String(localized: "analytics.of_income \(AnalyticsFormat.percent(shareOfIncome, signed: false))"),
                 style: AppStyle.Typography.metadata)
                .foregroundStyle(AppColors.textSecondary)
        } else {
            Text(String(localized: "analytics.no_income"))
                .font(AppStyle.Typography.metadata)
                .foregroundStyle(AppColors.textTertiary)
        }
    }

    private var delta: Double {
        let previous = NSDecimalNumber(decimal: snapshot.comparisonTotal).doubleValue
        guard previous > 0 else { return 0 }
        let current = NSDecimalNumber(decimal: snapshot.expenses).doubleValue
        return (current - previous) / previous * 100
    }

    private var shareOfIncome: Double {
        let income = NSDecimalNumber(decimal: snapshot.income).doubleValue
        guard income > 0 else { return 0 }
        return NSDecimalNumber(decimal: snapshot.remaining).doubleValue / income * 100
    }

    private func money(_ value: Decimal) -> String {
        MoneyFormat.string(value, currency: currency, masked: masked)
    }
}

private struct SummaryCell: View {
    let label: String
    let value: String
    let sub: AnyView

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(label)
                .font(AppStyle.Typography.metadata)
                .foregroundStyle(AppColors.textSecondary)
            Text(value)
                .font(AnalyticsStyle.figure)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.55)
                .contentTransition(reduceMotion ? .identity : .numericText())
                .animation(reduceMotion ? nil : AppMotion.number, value: value)
            sub
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, AppStyle.Spacing.small)
    }
}

// MARK: - Breakdown

private struct AnalyticsBreakdownCard: View {
    let snapshot: AnalyticsSnapshot
    let currency: Currency
    let masked: Bool
    let allCategories: [Category]
    let hiddenCategoryIDs: Set<UUID>
    let onToggleCategory: (UUID) -> Void
    let onShowAllCategories: () -> Void

    @State private var dimension: AnalyticsDimension = .category
    @State private var filter: AnalyticsFilter = .all
    @State private var hoveredSliceID: UUID?
    @State private var otherExpanded = false

    private struct BreakdownGroup: Identifiable {
        let slice: AnalyticsSlice
        let children: [AnalyticsSlice]
        var id: UUID { slice.id }
    }

    private var visible: [AnalyticsSlice] {
        let list = dimension == .category ? snapshot.categories : snapshot.accounts
        guard dimension == .category else { return list }
        switch filter {
        case .all: return list
        case .mandatory: return list.filter(\.isMandatory)
        case .free: return list.filter { !$0.isMandatory }
        }
    }

    private var groups: [BreakdownGroup] {
        let list = visible
        guard dimension == .category, list.count > 1 else {
            return list.map { BreakdownGroup(slice: $0, children: []) }
        }
        let threshold = snapshot.expenses / 100
        let minor = list.filter { $0.amount < threshold }
        guard !minor.isEmpty else {
            return list.map { BreakdownGroup(slice: $0, children: []) }
        }
        let major = list.filter { $0.amount >= threshold }
        let amount = minor.reduce(Decimal(0)) { $0 + $1.amount }
        let count = minor.reduce(0) { $0 + $1.operationCount }
        let previous = minor.reduce(Decimal(0)) { $0 + ($1.previousAmount ?? 0) }
        let grouped = AnalyticsSlice(
            id: UUID(),
            name: String(localized: "analytics.other"),
            symbol: "ellipsis",
            color: AppColors.textTertiary,
            amount: amount,
            operationCount: count,
            operations: [],
            isMandatory: minor.allSatisfy(\.isMandatory),
            previousAmount: previous,
            delta: nil
        )
        let group = BreakdownGroup(
            slice: grouped,
            children: minor.sorted { $0.amount > $1.amount }
        )
        let majorGroups = major
            .map { BreakdownGroup(slice: $0, children: []) }
            .sorted { $0.slice.amount > $1.slice.amount }
        return majorGroups + [group]
    }

    private var total: Decimal {
        groups.reduce(Decimal(0)) { $0 + $1.slice.amount }
    }

    private var filterCounts: (all: Int, mandatory: Int, free: Int) {
        snapshot.filterCounts
    }

    var body: some View {
        OverviewCard {
            HStack {
                Text(String(localized: "analytics.where_money_went"))
                    .font(AppStyle.Typography.headline)
                Spacer(minLength: AppStyle.Spacing.small)
                hiddenMenu
                HStack(spacing: AppStyle.Spacing.xxSmall) {
                    ForEach(AnalyticsDimension.allCases) { option in
                        Button {
                            dimension = option
                            hoveredSliceID = nil
                        } label: {
                            Text(option.title)
                                .font(AppStyle.Typography.metadataEmphasis)
                                .foregroundStyle(option == dimension ? AppColors.textPrimary : AppColors.textSecondary)
                                .padding(.horizontal, AppStyle.Spacing.xSmall)
                                .frame(height: 24)
                                .background {
                                    RoundedRectangle(cornerRadius: AppStyle.Radius.md, style: .continuous)
                                        .fill(option == dimension ? AppColors.surfaceRaised : .clear)
                                }
                                .overlay {
                                    RoundedRectangle(cornerRadius: AppStyle.Radius.md, style: .continuous)
                                        .strokeBorder(option == dimension ? AppColors.borderSubtle : .clear, lineWidth: 0.5)
                                }
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(option == dimension ? .isSelected : [])
                    }
                }
            }
            .padding(.horizontal, AppStyle.Row.cardHorizontalPadding)
            .padding(.top, AppStyle.Row.cardHorizontalPadding)
            .padding(.bottom, AppStyle.Spacing.xxSmall)

            if dimension == .category {
                HStack(spacing: AppStyle.Spacing.xxSmallPlus) {
                    filterButton(.all, count: filterCounts.all)
                    filterButton(.mandatory, count: filterCounts.mandatory)
                    filterButton(.free, count: filterCounts.free)
                }
                .padding(.horizontal, AppStyle.Row.cardHorizontalPadding)
                .padding(.bottom, AppStyle.Spacing.xxSmall)
            }

            BalanceBar(
                segments: groups.map {
                    BalanceBar.Segment(
                        id: $0.slice.id,
                        label: $0.slice.name,
                        value: NSDecimalNumber(decimal: $0.slice.amount).doubleValue,
                        color: $0.slice.color
                    )
                },
                highlightedID: hoveredSliceID,
                onHover: { hoveredSliceID = $0 }
            )
            .padding(.horizontal, AppStyle.Row.cardHorizontalPadding)
            .padding(.top, AppStyle.Spacing.xSmall)

            if visible.isEmpty {
                Text(String(localized: "analytics.no_filter_expenses"))
                    .font(AppStyle.Typography.callout)
                    .foregroundStyle(AppColors.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, AppStyle.Row.cardHorizontalPadding)
                    .padding(.vertical, AppStyle.Spacing.medium)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(groups.enumerated()), id: \.element.id) { index, group in
                        if index > 0 {
                            InsetCardDivider(horizontalInset: AppStyle.Row.cardHorizontalPadding)
                        }
                        row(group)
                    }
                }
            }
        }
        .onChange(of: snapshot.range) { _, _ in
            hoveredSliceID = nil
            otherExpanded = false
        }
        .onChange(of: dimension) { _, _ in
            hoveredSliceID = nil
            otherExpanded = false
        }
        .onChange(of: filter) { _, _ in
            hoveredSliceID = nil
            otherExpanded = false
        }
    }

    private var hiddenMenu: some View {
        Menu {
            ForEach(allCategories) { category in
                Button {
                    onToggleCategory(category.id)
                } label: {
                    if hiddenCategoryIDs.contains(category.id) {
                        Label(category.name, systemImage: "checkmark")
                    } else {
                        Text(category.name)
                    }
                }
            }
            if !hiddenCategoryIDs.isEmpty {
                Divider()
                Button(String(localized: "analytics.show_all_categories")) {
                    onShowAllCategories()
                }
            }
        } label: {
            HStack(spacing: 3) {
                Image(systemName: "eye.slash")
                if !hiddenCategoryIDs.isEmpty {
                    Text("\(hiddenCategoryIDs.count)")
                        .font(AppStyle.Typography.metadataEmphasis.numbers)
                }
            }
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(hiddenCategoryIDs.isEmpty ? AppColors.textSecondary : AppColors.textPrimary)
            .padding(.horizontal, 8)
            .frame(height: 24)
            .background {
                Capsule(style: .continuous)
                    .fill(hiddenCategoryIDs.isEmpty ? AppColors.fillSecondary : AppColors.surfaceRaised)
            }
            .overlay {
                Capsule(style: .continuous)
                    .strokeBorder(AppColors.borderSubtle, lineWidth: 0.5)
            }
            .contentShape(Capsule(style: .continuous))
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .accessibilityLabel(String(localized: "analytics.hide_categories"))
    }

    private func filterButton(_ option: AnalyticsFilter, count: Int) -> some View {
        Button {
            filter = option
            hoveredSliceID = nil
        } label: {
            HStack(spacing: AppStyle.Spacing.xxSmall) {
                Text(option.title)
                    .font(AppStyle.Typography.metadataEmphasis)
                Text("\(count)")
                    .font(AppStyle.Typography.metadataEmphasis.numbers)
                    .foregroundStyle(option == filter ? AppColors.textSecondary : AppColors.textTertiary)
            }
            .foregroundStyle(option == filter ? AppColors.textPrimary : AppColors.textSecondary)
            .padding(.horizontal, AppStyle.Spacing.xSmall)
            .frame(height: 24)
            .background {
                Capsule(style: .continuous)
                    .fill(option == filter ? AppColors.surfaceRaised : AppColors.fillSecondary)
            }
            .overlay {
                Capsule(style: .continuous)
                    .strokeBorder(AppColors.borderStrong, lineWidth: 1)
            }
            .contentShape(Capsule(style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(option == filter ? .isSelected : [])
    }

    @ViewBuilder
    private func row(_ group: BreakdownGroup) -> some View {
        if group.children.isEmpty {
            plainRow(group.slice)
        } else {
            Button {
                withAnimation(AppMotion.page) {
                    otherExpanded.toggle()
                }
            } label: {
                plainRow(group.slice, showsChevron: true)
            }
            .buttonStyle(.plain)
            .pointingHandOnHover()
            .accessibilityLabel(group.slice.name)
            .accessibilityHint(String(localized: "analytics.other_hint"))

            if otherExpanded {
                VStack(spacing: 0) {
                    ForEach(group.children) { child in
                        plainRow(child, indent: 44, iconFrame: 22)
                    }
                }
                .padding(.bottom, AppStyle.Spacing.xxSmall)
            }
        }
    }

    private func plainRow(
        _ slice: AnalyticsSlice,
        indent: CGFloat = 0,
        iconFrame: CGFloat = AppStyle.Row.listIconFrameSize,
        showsChevron: Bool = false
    ) -> some View {
        HStack(spacing: AppStyle.Spacing.small) {
            ListRowIcon(
                symbol: slice.symbol,
                color: slice.color,
                frameSize: iconFrame
            )

            VStack(alignment: .leading, spacing: AppStyle.Spacing.xxxSmall) {
                HStack(spacing: 4) {
                    Text(slice.name)
                        .font(AppStyle.Typography.headline)
                        .lineLimit(1)
                    if showsChevron {
                        Image(systemName: otherExpanded ? "chevron.down" : "chevron.right")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(AppColors.textTertiary)
                            .frame(width: 10)
                    }
                }
                Text(figures: Finance.operationsCountText(slice.operationCount),
                     style: AppStyle.Typography.metadata)
                    .foregroundStyle(AppColors.textSecondary)
                    .lineLimit(1)
            }

            Spacer(minLength: AppStyle.Spacing.small)

            VStack(alignment: .trailing, spacing: AppStyle.Spacing.xxxSmall) {
                Text(money(slice.amount))
                    .font(AnalyticsStyle.amount)
                    .monospacedDigit()
                    .lineLimit(1)

                HStack(spacing: AppStyle.Spacing.xxxSmall) {
                    Text(figures: AnalyticsFormat.percent(share(slice), signed: false),
                         style: AppStyle.Typography.metadata)
                        .foregroundStyle(AppColors.textTertiary)
                    if let delta = slice.delta {
                        Text("·")
                            .font(AppStyle.Typography.metadata)
                            .foregroundStyle(AppColors.textTertiary)
                        Text(figures: AnalyticsFormat.percent(delta),
                             style: AppStyle.Typography.metadata)
                            .foregroundStyle(delta >= 0 ? AppColors.statusCheckText : AppColors.statusSafeText)
                    }
                }
            }

        }
        .padding(.leading, AppStyle.Row.cardHorizontalPadding + indent)
        .padding(.trailing, AppStyle.Row.cardHorizontalPadding)
        .padding(.vertical, AppStyle.Spacing.xSmall)
        .background {
            hoveredSliceID == slice.id
                ? AppColors.fillSecondary.opacity(0.5)
                : .clear
        }
        .accessibilityElement(children: .combine)
    }

    private func share(_ slice: AnalyticsSlice) -> Double {
        guard total > 0 else { return 0 }
        return NSDecimalNumber(decimal: slice.amount).doubleValue
            / NSDecimalNumber(decimal: total).doubleValue * 100
    }

    private func money(_ value: Decimal) -> String {
        MoneyFormat.string(value, currency: currency, masked: masked)
    }
}

// MARK: - Pace

/// The pace card's mean/median switch. Built like the breakdown card's dimension
/// picker (a quiet pair of pills, the active one on `surfaceRaised`) so the two
/// view switches in Analytics read as one family.
private struct AnalyticsSpendMetricPicker: View {
    @Binding var metric: SettingsStore.SpendMetric

    var body: some View {
        HStack(spacing: AppStyle.Spacing.xxSmall) {
            ForEach(SettingsStore.SpendMetric.allCases) { option in
                Button {
                    metric = option
                } label: {
                    Text(option.title)
                        .font(AppStyle.Typography.metadataEmphasis)
                        .foregroundStyle(option == metric ? AppColors.textPrimary : AppColors.textSecondary)
                        .padding(.horizontal, AppStyle.Spacing.xSmall)
                        .frame(height: 24)
                        .background {
                            RoundedRectangle(cornerRadius: AppStyle.Radius.md, style: .continuous)
                                .fill(option == metric ? AppColors.surfaceRaised : .clear)
                        }
                        .overlay {
                            RoundedRectangle(cornerRadius: AppStyle.Radius.md, style: .continuous)
                                .strokeBorder(option == metric ? AppColors.borderSubtle : .clear, lineWidth: 0.5)
                        }
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(option == metric ? .isSelected : [])
            }
        }
    }
}

private struct AnalyticsPaceCard: View {
    let snapshot: AnalyticsSnapshot
    let currency: Currency
    let masked: Bool
    @Binding var metric: SettingsStore.SpendMetric

    var body: some View {
        OverviewCard {
            HStack(spacing: AppStyle.Spacing.small) {
                Text(String(localized: "analytics.pace"))
                    .font(AppStyle.Typography.headline)
                Spacer(minLength: AppStyle.Spacing.small)
                AnalyticsSpendMetricPicker(metric: $metric)
                if snapshot.previousFullTotal > 0 {
                    AppBadge(
                        text: isFaster
                            ? String(localized: "analytics.faster")
                            : String(localized: "analytics.slower"),
                        tone: isFaster ? .warning : .safe
                    )
                }
            }
            .padding(.horizontal, AppStyle.Row.cardHorizontalPadding)
            .padding(.top, AppStyle.Row.cardHorizontalPadding)
            .padding(.bottom, AppStyle.Spacing.xxSmall)

            HStack(spacing: AppStyle.Spacing.small) {
                HStack(alignment: .firstTextBaseline, spacing: 5) {
                    Text(money(metricValue))
                        .font(AnalyticsStyle.figure)
                        .monospacedDigit()
                    Text(metric.unitTitle)
                        .font(AppStyle.Typography.callout)
                        .foregroundStyle(AppColors.textSecondary)
                }
                Spacer(minLength: AppStyle.Spacing.small)
                Text(figures: population, style: AppStyle.Typography.metadata)
                    .foregroundStyle(AppColors.textTertiary)
                    .monospacedDigit()
            }
            .padding(.horizontal, AppStyle.Row.cardHorizontalPadding)
            .padding(.bottom, AppStyle.Spacing.xSmall)

            AnalyticsPaceChart(
                snapshot: snapshot,
                currency: currency,
                masked: masked
            )
            .padding(.horizontal, AppStyle.Spacing.small)

            if let verdict {
                HStack(alignment: .top, spacing: AppStyle.Spacing.xxSmallPlus) {
                    if let symbol = verdictSymbol {
                        Image(systemName: symbol)
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(AppColors.textSecondary)
                            .padding(.top, 3)
                            .accessibilityHidden(true)
                    }
                    Text(figures: verdict, style: AppStyle.Typography.callout)
                        .foregroundStyle(AppColors.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, AppStyle.Row.cardHorizontalPadding)
                .padding(.top, AppStyle.Spacing.xSmall)
                .padding(.bottom, AppStyle.Row.cardHorizontalPadding)
            }
        }
    }

    /// The figure the card leads with, and therefore the one its verdict repeats.
    private var metricValue: Decimal {
        metric == .average ? snapshot.average : snapshot.medianSpendingDay
    }

    /// The median describes spending days, not every elapsed day, so the caption
    /// names its own population instead of borrowing the range progress.
    private var population: String {
        switch metric {
        case .average:
            return AnalyticsFormat.dayProgress(
                elapsed: snapshot.range.elapsedDays,
                total: snapshot.range.totalDays
            )
        case .median:
            return "\(Finance.daysText(snapshot.spendingDayCount)) \(String(localized: "analytics.with_spending"))"
        }
    }

    private var isFaster: Bool {
        guard snapshot.previousFullTotal > 0 else { return false }
        let pace = snapshot.previousFullTotal
            * Decimal(snapshot.range.elapsedDays)
            / Decimal(max(1, snapshot.range.totalDays))
        return snapshot.expenses > pace
    }

    private var isMore: Bool {
        snapshot.expenses >= snapshot.comparisonTotal
    }

    private var verdictSymbol: String? {
        snapshot.hasComparison ? (isMore ? "arrow.up.right" : "arrow.down.right") : nil
    }

    private var verdict: String? {
        guard snapshot.hasComparison else {
            let spent = Finance.daysText(snapshot.range.elapsedDays)
            let total = money(snapshot.expenses)
            // The closing clause must repeat the figure the card shows, and for a
            // median that figure is measured over spending days.
            return metric == .average
                ? String(localized: "analytics.verdict_no_comparison \(spent) \(total) \(money(snapshot.average))")
                : String(localized: "analytics.verdict_no_comparison_median \(spent) \(total) \(money(snapshot.medianSpendingDay))")
        }
        let difference = abs(snapshot.expenses - snapshot.comparisonTotal)
        let daysLeft = snapshot.range.daysLeft

        if snapshot.range.scope == .month {
            if snapshot.range.isCurrent, daysLeft > 0 {
                if isMore {
                    return String(localized: "analytics.verdict_month_current_more \(Finance.daysText(snapshot.range.elapsedDays)) \(money(snapshot.comparisonTotal)) \(money(snapshot.expenses)) \(money(difference)) \(Finance.daysText(daysLeft))")
                }
                return String(localized: "analytics.verdict_month_current_less \(Finance.daysText(snapshot.range.elapsedDays)) \(money(snapshot.comparisonTotal)) \(money(snapshot.expenses)) \(money(difference)) \(Finance.daysText(daysLeft))")
            }
            if isMore {
                return String(localized: "analytics.verdict_month_past_more \(money(snapshot.comparisonTotal)) \(money(difference))")
            }
            return String(localized: "analytics.verdict_month_past_less \(money(snapshot.comparisonTotal)) \(money(difference))")
        }

        if snapshot.range.isCurrent, daysLeft > 0 {
            if isMore {
                return String(localized: "analytics.verdict_current_more \(money(snapshot.comparisonTotal)) \(money(difference)) \(Finance.daysText(daysLeft))")
            }
            return String(localized: "analytics.verdict_current_less \(money(snapshot.comparisonTotal)) \(money(difference)) \(Finance.daysText(daysLeft))")
        }
        if isMore {
            return String(localized: "analytics.verdict_past_more \(money(snapshot.comparisonTotal)) \(money(difference))")
        }
        return String(localized: "analytics.verdict_past_less \(money(snapshot.comparisonTotal)) \(money(difference))")
    }

    private func money(_ value: Decimal) -> String {
        MoneyFormat.string(value, currency: currency, masked: masked)
    }
}

// MARK: - Heat map

private struct AnalyticsHeatCard: View {
    let snapshot: AnalyticsSnapshot
    let currency: Currency
    let masked: Bool
    @Binding var popupDay: AnalyticsDay?
    /// Set by the QA launch env, so the readout shows the day whose popup the
    /// screenshot harness asks for.
    let initialActiveDay: Int?
    @State private var activeDay: AnalyticsDay?

    @FocusState private var gridFocused: Bool

    init(
        snapshot: AnalyticsSnapshot,
        currency: Currency,
        masked: Bool,
        popupDay: Binding<AnalyticsDay?>,
        initialActiveDay: Int? = nil
    ) {
        self.snapshot = snapshot
        self.currency = currency
        self.masked = masked
        self.initialActiveDay = initialActiveDay
        _popupDay = popupDay
        let initial = initialActiveDay.flatMap { id in
            snapshot.days.first(where: { $0.id == id })
        }
        _activeDay = State(initialValue: initial)
    }

    private var title: String {
        snapshot.range.scope == .month
            ? String(localized: "analytics.heat_month")
            : String(localized: "analytics.heat_period")
    }

    private var weekdays: [String] {
        var calendar = Calendar.current
        calendar.firstWeekday = 2
        let symbols = calendar.shortWeekdaySymbols
        return (0..<7).map { offset in
            symbols[(calendar.firstWeekday - 1 + offset) % 7].capitalized
        }
    }

    private var leadingBlanks: Int {
        var calendar = Calendar.current
        calendar.firstWeekday = 2
        let weekday = calendar.component(.weekday, from: snapshot.range.start)
        return (weekday - 2 + 7) % 7
    }

    private var rowCount: Int {
        (leadingBlanks + snapshot.days.count + 6) / 7
    }

    private func dayAt(row: Int, column: Int) -> AnalyticsDay? {
        let index = row * 7 + column - leadingBlanks
        guard snapshot.days.indices.contains(index) else { return nil }
        return snapshot.days[index]
    }

    var body: some View {
        OverviewCard {
            #if os(iOS)
            // A phone cannot hold the title and the whole legend on one line
            // without the words overlapping the title, so the legend sits under
            // it.
            VStack(alignment: .leading, spacing: AppStyle.Spacing.xxSmallPlus) {
                Text(figures: title, style: AppStyle.Typography.headline)
                legend
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, AppStyle.Row.cardHorizontalPadding)
            .padding(.top, AppStyle.Row.cardHorizontalPadding)
            .padding(.bottom, AppStyle.Spacing.xSmall)
            #else
            HStack {
                Text(figures: title, style: AppStyle.Typography.headline)
                Spacer(minLength: AppStyle.Spacing.small)
                legend
            }
            .padding(.horizontal, AppStyle.Row.cardHorizontalPadding)
            .padding(.top, AppStyle.Row.cardHorizontalPadding)
            .padding(.bottom, AppStyle.Spacing.xSmall)
            #endif

            HStack(spacing: AppStyle.Spacing.xxSmallPlus) {
                ForEach(weekdays, id: \.self) { weekday in
                    Text(weekday)
                        .font(AppStyle.Typography.micro)
                        .foregroundStyle(AppColors.textTertiary)
                        .frame(maxWidth: .infinity)
                }
            }
            .padding(.horizontal, AppStyle.Row.cardHorizontalPadding)

            VStack(spacing: AppStyle.Spacing.xxSmallPlus) {
                ForEach(0..<rowCount, id: \.self) { row in
                    HStack(spacing: AppStyle.Spacing.xxSmallPlus) {
                        ForEach(0..<7, id: \.self) { column in
                            if let day = dayAt(row: row, column: column) {
                                cell(day)
                            } else {
                                Color.clear
                                    .frame(height: 44)
                                    .frame(maxWidth: .infinity)
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, AppStyle.Row.cardHorizontalPadding)
            .padding(.top, AppStyle.Spacing.xxSmallPlus)
            .focusable()
            .focusEffectDisabled()
            .focused($gridFocused)
            .onKeyPress(.leftArrow) {
                moveHeat(by: -1)
                return .handled
            }
            .onKeyPress(.rightArrow) {
                moveHeat(by: 1)
                return .handled
            }
            .onKeyPress(.upArrow) {
                moveHeat(by: -7)
                return .handled
            }
            .onKeyPress(.downArrow) {
                moveHeat(by: 7)
                return .handled
            }
            .onChange(of: gridFocused) { _, focused in
                if focused, activeDay == nil {
                    activeDay = snapshot.days.first(where: { $0.id == snapshot.todayDay })
                        ?? snapshot.days.last(where: { !$0.isFuture })
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel(String(localized: "analytics.heat_accessibility"))
            .onChange(of: snapshot.range) { _, _ in
                // The launch scope switch lands here after the first render, so the
                // debug day is restored instead of being cleared with the old range.
                activeDay = initialActiveDay.flatMap { id in
                    snapshot.days.first(where: { $0.id == id })
                }
                popupDay = nil
            }
            .onKeyPress(.return) {
                togglePopupForActiveDay()
                return .handled
            }
            .onKeyPress(.space) {
                togglePopupForActiveDay()
                return .handled
            }
            .onKeyPress(.escape) {
                guard popupDay != nil else { return .ignored }
                popupDay = nil
                return .handled
            }

            readout
                .padding(.horizontal, AppStyle.Row.cardHorizontalPadding)
                .padding(.top, AppStyle.Spacing.xSmall)
                .padding(.bottom, AppStyle.Row.cardHorizontalPadding)
        }
    }

    /// Click, Return or Space: the same cell closes its popup, another day
    /// replaces it in one state update, an empty day only moves the readout.
    private func handleSelection(of day: AnalyticsDay) {
        guard !day.isFuture else { return }
        activeDay = day
        guard day.amount > 0, !day.groups.isEmpty else {
            popupDay = nil
            return
        }
        popupDay = popupDay?.id == day.id ? nil : day
    }

    private func togglePopupForActiveDay() {
        guard let day = activeDay else { return }
        handleSelection(of: day)
    }


    private var legend: some View {
        HStack(spacing: AppStyle.Spacing.xxxSmall) {
            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .fill(AppColors.Chart.sky.opacity(0.42))
                .frame(width: 8, height: 8)
            Text(String(localized: "analytics.above_average"))
                .font(AppStyle.Typography.metadata)
                .foregroundStyle(AppColors.textTertiary)
            Text(String(localized: "analytics.less"))
                .font(AppStyle.Typography.metadata)
                .foregroundStyle(AppColors.textTertiary)
            ForEach(1...4, id: \.self) { index in
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(AppColors.textPrimary.opacity(AnalyticsEngine.heatOpacities[index]))
                    .frame(width: 8, height: 8)
            }
            Text(String(localized: "analytics.more"))
                .font(AppStyle.Typography.metadata)
                .foregroundStyle(AppColors.textTertiary)
        }
        .accessibilityHidden(true)
    }

    private func cell(_ day: AnalyticsDay) -> some View {
        let isActive = activeDay?.id == day.id
        let level = min(max(day.level, 0), AnalyticsEngine.heatOpacities.count - 1)
        let aboveAverage = day.amount > 0 && day.amount > snapshot.average
        let fill: Color
        if day.isFuture || day.amount <= 0 {
            fill = AppColors.fillSecondary
        } else if aboveAverage {
            fill = AppColors.Chart.sky.opacity(0.20 + Double(level) * 0.06)
        } else {
            fill = AppColors.textPrimary.opacity(AnalyticsEngine.heatOpacities[level])
        }
        let textColor = (day.isToday || day.level >= 3 || aboveAverage)
            ? AppColors.textPrimary
            : AppColors.textTertiary

        return ZStack {
            RoundedRectangle(cornerRadius: AppStyle.Radius.md, style: .continuous)
                .fill(fill)

            if !day.isFuture {
                VStack(alignment: .leading, spacing: 0) {
                    Text("\(Calendar.current.component(.day, from: day.date))")
                        .font(AnalyticsStyle.heatDay)
                        .foregroundStyle(textColor)
                    Spacer(minLength: 0)
                    HStack {
                        Spacer(minLength: 0)
                        if day.amount > 0 {
                            Text(masked ? "••••" : heatAmountText(day))
                                .font(AnalyticsStyle.heatAmount)
                                .foregroundStyle(textColor)
                                .lineLimit(1)
                                .minimumScaleFactor(0.7)
                        }
                    }
                }
                .padding(AppStyle.Spacing.xxSmallPlus)
            }
        }
        .frame(height: 44)
        .frame(maxWidth: .infinity)
        .overlay {
            if day.isFuture {
                RoundedRectangle(cornerRadius: AppStyle.Radius.md, style: .continuous)
                    .strokeBorder(
                        AppColors.borderStrong,
                        style: StrokeStyle(lineWidth: 1, dash: [3, 3])
                    )
            }
            RoundedRectangle(cornerRadius: AppStyle.Radius.md, style: .continuous)
                .strokeBorder(
                    isActive && !day.isToday
                        ? AppColors.selectionRing
                        : (day.isToday ? AppColors.textPrimary : .clear),
                    // A 2 pt ring on the selected cell keeps the state legible on
                    // the low-contrast blue heat fill; today keeps its 1 pt ring.
                    lineWidth: isActive && !day.isToday ? 2 : 1
                )
        }
        .opacity(day.isFuture ? 0.5 : 1)
        .contentShape(Rectangle())
        .anchorPreference(key: AnalyticsHeatAnchorKey.self, value: .bounds) { [day.id: $0] }
        .onTapGesture {
            handleSelection(of: day)
        }
        .pointingHandOnHover(day.amount > 0 && !day.isFuture)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText(day))
    }

    @ViewBuilder
    private var readout: some View {
        if let day = activeDay {
            let date = AppDate.short(day.date)
            if day.amount > 0 {
                let above = day.amount > snapshot.average
                let suffix = above ? " · " + String(localized: "analytics.above_average") : ""
                Text(figures: "\(date) · \(money(day.amount)) · \(Finance.operationsCountText(day.operationCount))\(suffix)",
                     style: AppStyle.Typography.metadata)
                    .foregroundStyle(AppColors.textSecondary)
                    .monospacedDigit()
            } else {
                Text(figures: "\(date) · \(String(localized: "analytics.no_day_expenses"))",
                     style: AppStyle.Typography.metadata)
                    .foregroundStyle(AppColors.textTertiary)
            }
        } else {
            Text(String(localized: "analytics.click_day"))
                .font(AppStyle.Typography.metadata)
                .foregroundStyle(AppColors.textTertiary)
        }
    }

    private func moveHeat(by delta: Int) {
        let current = activeDay?.id
            ?? snapshot.todayDay
            ?? snapshot.days.last(where: { !$0.isFuture })?.id
            ?? 1
        let next = min(max(current + delta, 1), max(1, snapshot.range.totalDays))
        activeDay = snapshot.days.first(where: { $0.id == next })
        // Arrows move the highlighted day; the popup stays anchored to the cell
        // it was opened from, so a move closes it. Return opens the new day.
        popupDay = nil
    }

    /// The figure inside a heat cell. The Mac's cells are wide enough for two
    /// decimals; a phone's ~44 pt cell only has room for whole units, and the
    /// exact amount is in the readout below the grid and in the day's popup.
    private func heatAmountText(_ day: AnalyticsDay) -> String {
        #if os(iOS)
        MoneyFormat.number(day.amount, fractionDigits: 0, grouping: false)
        #else
        MoneyFormat.number(day.amount, fractionDigits: 2)
        #endif
    }

    private func accessibilityText(_ day: AnalyticsDay) -> String {
        let date = AppDate.short(day.date)
        if day.amount > 0 {
            let above = day.amount > snapshot.average
            let suffix = above ? ", \(String(localized: "analytics.above_average"))" : ""
            return "\(date), \(money(day.amount)), \(Finance.operationsCountText(day.operationCount))\(suffix)"
        }
        return "\(date), \(String(localized: "analytics.no_day_expenses"))"
    }

    private func money(_ value: Decimal) -> String {
        MoneyFormat.string(value, currency: currency, masked: masked)
    }
}

// MARK: - Shared styles and formatting

private enum AnalyticsStyle {
    /// Three summary figures share a phone's width, so the iOS size is a step
    /// smaller than the desktop one; the Mac's card is unchanged.
    static var figure: AppStyle.TextStyle {
        #if os(iOS)
        AppStyle.TextStyle(family: .rounded, size: 18, weight: .bold, tracking: 0)
        #else
        AppStyle.TextStyle(family: .rounded, size: 22, weight: .bold, tracking: 0)
        #endif
    }
    static let amount = AppStyle.TextStyle(family: .rounded, size: 15, weight: .semibold, tracking: 0)
    static let heatDay = AppStyle.TextStyle(family: .rounded, size: 10, weight: .semibold, tracking: 0)
    static let heatAmount = AppStyle.TextStyle(family: .rounded, size: 11, weight: .semibold, tracking: 0)
}

private struct AnalyticsYearMonthsCard: View {
    let snapshot: AnalyticsSnapshot
    let currency: Currency
    let masked: Bool

    private struct YearMonth: Identifiable {
        let id: Int
        let date: Date
        let name: String
        var amount: Decimal
        var count: Int
        let isCurrent: Bool
        let isFuture: Bool
    }

    private static let nameFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.setLocalizedDateFormatFromTemplate("LLL")
        return formatter
    }()

    private var months: [YearMonth] {
        let calendar = Calendar.current
        let start = snapshot.range.start
        let now = Date.now
        var result = (0..<12).map { offset -> YearMonth in
            let date = calendar.date(byAdding: .month, value: offset, to: start) ?? start
            let current = calendar.isDate(date, equalTo: now, toGranularity: .month)
            return YearMonth(
                id: offset,
                date: date,
                name: Self.nameFormatter.string(from: date).capitalized,
                amount: 0,
                count: 0,
                isCurrent: current,
                isFuture: date > now && !current
            )
        }
        for day in snapshot.days {
            let index = calendar.component(.month, from: day.date) - 1
            guard result.indices.contains(index) else { continue }
            result[index].amount += day.amount
            result[index].count += day.operationCount
        }
        return result
    }

    var body: some View {
        OverviewCard {
            Text(String(localized: "analytics.by_months"))
                .font(AppStyle.Typography.headline)
                .padding(.horizontal, AppStyle.Row.cardHorizontalPadding)
                .padding(.top, AppStyle.Row.cardHorizontalPadding)
                .padding(.bottom, AppStyle.Spacing.xSmall)

            LazyVGrid(
                columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 4),
                spacing: 6
            ) {
                ForEach(months) { month in
                    VStack(alignment: .leading, spacing: 3) {
                        Text(month.name)
                            .font(AppStyle.Typography.metadataEmphasis)
                            .foregroundStyle(month.isFuture ? AppColors.textTertiary : AppColors.textSecondary)

                        Spacer(minLength: 0)

                        Text(month.amount > 0 ? money(month.amount) : "—")
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                            .foregroundStyle(month.isFuture ? AppColors.textTertiary : AppColors.textPrimary)
                            .monospacedDigit()
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)

                        Text(month.count > 0
                             ? Finance.operationsCountText(month.count)
                             : " ")
                            .font(AppStyle.Typography.micro)
                            .foregroundStyle(AppColors.textTertiary)
                            .lineLimit(1)
                    }
                    .padding(8)
                    .frame(maxWidth: .infinity, minHeight: 58, alignment: .leading)
                    .background {
                        RoundedRectangle(cornerRadius: AppStyle.Radius.md, style: .continuous)
                            .fill(month.isCurrent ? AppColors.surfaceRaised : AppColors.fillSecondary)
                    }
                    .overlay {
                        RoundedRectangle(cornerRadius: AppStyle.Radius.md, style: .continuous)
                            .strokeBorder(
                                month.isCurrent ? AppColors.borderStrong : AppColors.borderSubtle,
                                lineWidth: month.isCurrent ? 1 : 0.5
                            )
                    }
                    .opacity(month.isFuture ? 0.5 : 1)
                }
            }
            .padding(.horizontal, AppStyle.Row.cardHorizontalPadding)
            .padding(.bottom, AppStyle.Row.cardHorizontalPadding)
        }
    }

    private func money(_ value: Decimal) -> String {
        MoneyFormat.string(value, currency: currency, masked: masked)
    }
}

// MARK: - Day popup

/// Placement for the day popup in the page's coordinate space. The popup is
/// measured first, then put on the side of the cell that has room for it, so it
/// never covers the cell while either side fits.
struct AnalyticsPopupLayout {
    enum Side: String {
        case above
        case below
    }

    /// The popup keeps one width so the rows and the caret stay predictable.
    /// 340 keeps the longest category in the store ("Покупки: одежда, техника",
    /// 156.3 pt in Onest 12) inside the title's budget next to a chip and the
    /// widest amount of the month.
    static let width: CGFloat = 340
    /// Space between the popup and the cell, and the page edge.
    static let gap: CGFloat = 8
    static let pageInset: CGFloat = 8
    /// Keeps the caret away from the rounded corners.
    static let caretInset: CGFloat = 20

    // Row geometry. The chip and the amount share a fixed trailing block, so the
    // title's width never depends on whether a row carries a `×N` chip.
    static let rowHorizontalInset: CGFloat = 12
    static let rowIconSize: CGFloat = 22
    static let rowSpacing: CGFloat = 8
    static let trailingWidth: CGFloat = 112
    /// What is left for the title once the icon, the gaps and the block are paid
    /// for: 340 − 24 − 22 − 16 − 112 = 166 pt.
    static var titleWidth: CGFloat {
        width - rowHorizontalInset * 2 - rowIconSize - trailingWidth - rowSpacing * 2
    }

    let x: CGFloat
    let y: CGFloat
    /// The popup's width on this page: the designed 340 pt, or less on a narrow
    /// phone so the card and its caret never run off the edge.
    let width: CGFloat
    /// Caret apex in the popup's own horizontal space.
    let caretX: CGFloat
    let side: Side
    /// True when the chosen side did not fit and the popup was pinned to the page.
    let isClamped: Bool
    /// The page's top in window coordinates, for the screenshot harness.
    let pageOriginY: CGFloat

    static func make(
        cell: CGRect,
        popupHeight: CGFloat,
        pageSize: CGSize,
        pageOriginY: CGFloat = 0
    ) -> AnalyticsPopupLayout {
        let height = max(popupHeight, 1)
        let popupWidth = min(Self.width, max(200, pageSize.width - pageInset * 2))
        let topLimit = pageInset
        let bottomLimit = pageSize.height - pageInset
        let aboveRoom = cell.minY - topLimit
        let belowRoom = bottomLimit - cell.maxY
        let fitsAbove = aboveRoom >= height + gap
        let fitsBelow = belowRoom >= height + gap

        let side: Side
        if fitsAbove {
            side = .above
        } else if fitsBelow {
            side = .below
        } else {
            side = aboveRoom >= belowRoom ? .above : .below
        }

        let preferredY = side == .above ? cell.minY - height - gap : cell.maxY + gap
        let minY = topLimit
        let maxY = max(minY, pageSize.height - height - pageInset)
        let isClamped = preferredY < minY || preferredY > maxY
        let y = min(max(preferredY, minY), maxY)

        let x = min(
            max(cell.midX - popupWidth / 2, pageInset),
            max(pageInset, pageSize.width - popupWidth - pageInset)
        )
        let caretX = min(max(cell.midX - x, caretInset), popupWidth - caretInset)

        return AnalyticsPopupLayout(
            x: x,
            y: y,
            width: popupWidth,
            caretX: caretX,
            side: side,
            isClamped: isClamped,
            pageOriginY: pageOriginY
        )
    }
}

/// The floating card for one day: the date and total, then one row per category.
private struct AnalyticsDayPopup: View {
    let day: AnalyticsDay
    let currency: Currency
    let masked: Bool
    /// The width the layout resolved for this page.
    let width: CGFloat
    let caretX: CGFloat
    let caretSide: AnalyticsPopupLayout.Side

    static let maxRows = 8
    static let rowHeight: CGFloat = 32
    private static let caretWidth: CGFloat = 14
    /// One point of the caret overlaps the border so the seam disappears.
    private static let caretHeight: CGFloat = 9
    private static let caretOffset: CGFloat = 8

    private var pointsUp: Bool { caretSide == .below }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            InsetCardDivider(horizontalInset: 12)
            rows
        }
        .frame(width: width, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: AppStyle.Radius.lg, style: .continuous)
                .fill(AppColors.surfaceRaised)
        }
        .overlay {
            RoundedRectangle(cornerRadius: AppStyle.Radius.lg, style: .continuous)
                .strokeBorder(AppColors.borderStrong, lineWidth: 1)
        }
        .overlay(alignment: pointsUp ? .top : .bottom) { caret }
        .compositingGroup()
        .shadow(
            color: AppStyle.Elevation.floatingColor,
            radius: AppStyle.Elevation.floatingRadius,
            y: AppStyle.Elevation.floatingY
        )
        .accessibilityElement(children: .contain)
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(figures: AppDate.short(day.date), style: AppStyle.Typography.headline)
            Spacer(minLength: 4)
            Text(figures: money(day.amount), style: AnalyticsStyle.amount)
                .monospacedDigit()
                .lineLimit(1)
        }
        .padding(.horizontal, 12)
        .padding(.top, 10)
        .padding(.bottom, 8)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var rows: some View {
        if day.groups.count > Self.maxRows {
            ScrollView(.vertical, showsIndicators: true) {
                rowStack
            }
            .frame(height: CGFloat(Self.maxRows) * Self.rowHeight + 8)
        } else {
            rowStack
        }
    }

    private var rowStack: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(day.groups) { group in
                row(group)
            }
        }
        .padding(.vertical, 4)
    }

    private func row(_ group: AnalyticsDayGroup) -> some View {
        HStack(spacing: AnalyticsPopupLayout.rowSpacing) {
            ListRowIcon(
                symbol: group.sample.displayIcon,
                color: group.sample.displayColor,
                frameSize: AnalyticsPopupLayout.rowIconSize
            )
            Text(figures: group.title, style: AppStyle.Typography.callout)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
            // The chip and the amount share one fixed-width trailing block, so the
            // title keeps the same budget whether or not a chip is present.
            HStack(spacing: 0) {
                if group.count > 1 {
                    Text(verbatim: "×\(group.count)")
                        .font(AppStyle.Typography.metadata)
                        .foregroundStyle(AppColors.textTertiary)
                        .monospacedDigit()
                        .padding(.trailing, 6)
                }
                // The day total is an expense, so every row carries its minus.
                Text(figures: expenseText(group.amount), style: AppStyle.Typography.metadataEmphasis)
                    .monospacedDigit()
                    .lineLimit(1)
            }
            .frame(width: AnalyticsPopupLayout.trailingWidth, alignment: .trailing)
        }
        .padding(.horizontal, AnalyticsPopupLayout.rowHorizontalInset)
        .frame(height: Self.rowHeight)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(groupAccessibility(group))
    }

    /// The caret sits outside the card and covers the border at its base, so the
    /// bubble and the pointer read as one shape.
    private var caret: some View {
        ZStack {
            AnalyticsCaret(pointsUp: pointsUp)
                .fill(AppColors.surfaceRaised)
            AnalyticsCaretEdges(pointsUp: pointsUp)
                .stroke(AppColors.borderStrong, lineWidth: 1)
        }
        .frame(width: Self.caretWidth, height: Self.caretHeight)
        .offset(
            x: caretX - width / 2,
            y: caretSide == .above ? Self.caretOffset : -Self.caretOffset
        )
    }

    private func money(_ value: Decimal) -> String {
        MoneyFormat.string(value, currency: currency, masked: masked)
    }

    private func expenseText(_ value: Decimal) -> String {
        MoneyFormat.string(-value, currency: currency, sign: .always, masked: masked)
    }

    private func groupAccessibility(_ group: AnalyticsDayGroup) -> String {
        "\(group.title), \(expenseText(group.amount)), \(Finance.operationsCountText(group.count))"
    }
}

/// The iOS day detail. It mirrors the Mac popup's groups, but as a bottom
/// sheet: the sheet's material, detents and drag indicator are native, and the
/// rows are full-width touch targets.
private struct AnalyticsDaySheet: View {
    let day: AnalyticsDay
    let currency: Currency
    let masked: Bool

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            SheetHeader(
                title: AppDate.short(day.date),
                subtitle: MoneyFormat.string(day.amount, currency: currency, masked: masked),
                onClose: { dismiss() }
            )

            ScrollView {
                VStack(spacing: 0) {
                    InsetCard {
                        ForEach(Array(day.groups.enumerated()), id: \.element.id) { index, group in
                            if index > 0 { InsetCardDivider() }
                            row(group)
                        }
                    }
                }
                .padding(.horizontal, AppStyle.Spacing.large)
                .padding(.bottom, AppStyle.Spacing.large)
            }
        }
        .background(AppColors.surfaceBase)
    }

    private func row(_ group: AnalyticsDayGroup) -> some View {
        HStack(spacing: AppStyle.Spacing.small) {
            ListRowIcon(
                symbol: group.sample.displayIcon,
                color: group.sample.displayColor,
                frameSize: 26
            )

            VStack(alignment: .leading, spacing: 2) {
                Text(figures: group.title, style: AppStyle.Typography.body)
                    .lineLimit(1)
                Text(figures: Finance.operationsCountText(group.count), style: AppStyle.Typography.metadata)
                    .foregroundStyle(AppColors.textTertiary)
            }

            Spacer(minLength: AppStyle.Spacing.small)

            Text(
                figures: MoneyFormat.string(
                    -group.amount,
                    currency: currency,
                    sign: .always,
                    masked: masked
                ),
                style: AppStyle.Typography.body.weight(.semibold)
            )
            .monospacedDigit()
            .lineLimit(1)
        }
        .frame(minHeight: 44)
        .padding(.horizontal, AppStyle.Spacing.medium)
        .padding(.vertical, AppStyle.Spacing.xxSmall)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "\(group.title), \(MoneyFormat.string(-group.amount, currency: currency, sign: .always, masked: masked)), \(Finance.operationsCountText(group.count))"
        )
    }
}

/// Two slanted edges of the caret, without its base: the base is covered by the
/// popup's fill so the stroke does not cut the bubble off.
private struct AnalyticsCaretEdges: Shape {
    let pointsUp: Bool

    func path(in rect: CGRect) -> Path {
        var path = Path()
        if pointsUp {
            path.move(to: CGPoint(x: rect.minX, y: rect.maxY))
            path.addLine(to: CGPoint(x: rect.midX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        } else {
            path.move(to: CGPoint(x: rect.minX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        }
        return path
    }
}

/// Closes the popup on a click outside it while it is open. The click is passed
/// on untouched, so it still does whatever it normally would. Clicks on the
/// anchor cell are left to the cell's own tap, which toggles the popup.
private struct AnalyticsPopupDismissModifier: ViewModifier {
    let isActive: Bool
    let popupFrame: CGRect
    let anchorCellFrame: CGRect
    let onDismiss: () -> Void

    @State private var state = AnalyticsPopupDismissState()
    @State private var monitor: Any?

    func body(content: Content) -> some View {
        content
            .onAppear {
                sync()
                install()
            }
            .onChange(of: isActive) { _, active in
                sync()
                if active {
                    install()
                } else {
                    remove()
                }
            }
            .onChange(of: popupFrame) { _, _ in sync() }
            .onChange(of: anchorCellFrame) { _, _ in sync() }
            .onDisappear { remove() }
    }

    private func sync() {
        state.popupFrame = popupFrame
        state.anchorCellFrame = anchorCellFrame
        state.onDismiss = onDismiss
    }

    private func install() {
        #if os(macOS)
        guard isActive, monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .keyDown]) { event in
            if event.type == .keyDown {
                // Escape closes the popup even when the grid does not have focus.
                if event.keyCode == 53 { state.onDismiss?() }
                return event
            }
            guard let window = event.window else { return event }
            state.dismissIfOutside(window: window, event: event)
            return event
        }
        #endif
    }

    private func remove() {
        #if os(macOS)
        guard let monitor else { return }
        NSEvent.removeMonitor(monitor)
        self.monitor = nil
        #endif
    }
}

/// Live inputs for the screenshot harness: the overlay updates it on every
/// layout pass, and the report reads it once everything has settled.
private final class AnalyticsShotBox {
    var day: AnalyticsDay?
    var cell: CGRect = .null
    var pageOrigin: CGPoint = .zero
    var pageSize: CGSize = .zero
}

private final class AnalyticsPopupDismissState {
    var popupFrame: CGRect = .null
    var anchorCellFrame: CGRect = .null
    var onDismiss: (() -> Void)?

    #if os(macOS)
    func dismissIfOutside(window: NSWindow, event: NSEvent) {
        let point = Self.point(for: event, in: window)
        // The anchor cell keeps its own tap, which toggles the popup: the monitor
        // must not pre-close it. Every other click dismisses, even while the
        // popup rect is still unknown — a click that misses the card is never
        // swallowed, and an extra dismissal is better than a stuck popup.
        if anchorCellFrame.contains(point) { return }
        if !popupFrame.isEmpty, popupFrame.contains(point) { return }
        onDismiss?()
    }

    /// SwiftUI's `.global` space starts at the hosting view's top-left corner.
    private static func point(for event: NSEvent, in window: NSWindow) -> CGPoint {
        guard let view = window.contentView else { return .zero }
        let local = view.convert(event.locationInWindow, from: nil)
        let y = view.isFlipped ? local.y : view.bounds.height - local.y
        return CGPoint(x: local.x - view.bounds.minX, y: y - view.bounds.minY)
    }
    #endif
}

#if os(iOS)
/// Closes the day popup on a tap anywhere outside it. The Mac uses an `NSEvent`
/// monitor, which does not exist on iOS, so this installs the UIKit equivalent
/// on the window. It observes taps without cancelling them, so the page still
/// scrolls and its own controls still work while the popup is up — the same
/// behaviour the Mac has.
private struct AnalyticsTapOutsideCatcher: UIViewRepresentable {
    let isActive: Bool
    let popupFrame: CGRect
    let anchorFrame: CGRect
    let onDismiss: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.isUserInteractionEnabled = false
        view.isHidden = true
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        let coordinator = context.coordinator
        coordinator.popupFrame = popupFrame
        coordinator.anchorFrame = anchorFrame
        coordinator.onDismiss = onDismiss
        // The window only exists once the view is mounted and attached.
        DispatchQueue.main.async {
            coordinator.sync(isActive: isActive, window: uiView.window)
        }
    }

    static func dismantleUIView(_ uiView: UIView, coordinator: Coordinator) {
        coordinator.remove()
    }

    final class Coordinator: NSObject {
        var popupFrame: CGRect = .null
        var anchorFrame: CGRect = .null
        var onDismiss: (() -> Void)?
        private var recognizer: UITapGestureRecognizer?
        private weak var installedWindow: UIWindow?

        func sync(isActive: Bool, window: UIWindow?) {
            if isActive, let window {
                install(on: window)
            } else if !isActive {
                remove()
            }
        }

        private func install(on window: UIWindow) {
            if let recognizer, installedWindow === window {
                window.addGestureRecognizer(recognizer)
                return
            }
            remove()
            let tap = UITapGestureRecognizer(target: self, action: #selector(handle(_:)))
            tap.cancelsTouchesInView = false
            tap.delegate = self
            window.addGestureRecognizer(tap)
            recognizer = tap
            installedWindow = window
        }

        func remove() {
            if let recognizer {
                recognizer.view?.removeGestureRecognizer(recognizer)
            }
            recognizer = nil
            installedWindow = nil
        }

        /// The anchor cell keeps its own tap, which toggles the popup. Every
        /// other tap outside the card dismisses it.
        @objc private func handle(_ recognizer: UITapGestureRecognizer) {
            guard let window = recognizer.view else { return }
            let point = recognizer.location(in: window)
            if anchorFrame.contains(point) { return }
            if !popupFrame.isEmpty, popupFrame.contains(point) { return }
            onDismiss?()
        }
    }
}

extension AnalyticsTapOutsideCatcher.Coordinator: UIGestureRecognizerDelegate {
    func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
    ) -> Bool {
        true
    }
}
#endif

private struct AnalyticsCaret: Shape {
    let pointsUp: Bool

    func path(in rect: CGRect) -> Path {
        var path = Path()
        if pointsUp {
            path.move(to: CGPoint(x: rect.midX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        } else {
            path.move(to: CGPoint(x: rect.midX, y: rect.maxY))
            path.addLine(to: CGPoint(x: rect.minX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        }
        path.closeSubpath()
        return path
    }
}

private struct AnalyticsHeatAnchorKey: PreferenceKey {
    static var defaultValue: [Int: Anchor<CGRect>] = [:]

    static func reduce(
        value: inout [Int: Anchor<CGRect>],
        nextValue: () -> [Int: Anchor<CGRect>]
    ) {
        value.merge(nextValue(), uniquingKeysWith: { $1 })
    }
}

enum AnalyticsFormat {
    static func percent(_ value: Double, signed: Bool = true) -> String {
        let body = MoneyFormat.number(Decimal(abs(value)), fractionDigits: 1) + "%"
        guard signed else { return body }
        if value > 0 { return "+" + body }
        if value < 0 { return "−" + body }
        return body
    }

    static func dayProgress(elapsed: Int, total: Int) -> String {
        let word = (total % 10 == 1 && total % 100 != 11)
            ? String(localized: "analytics.day_genitive_one")
            : String(localized: "analytics.day_genitive_many")
        return "\(elapsed) \(String(localized: "analytics.of")) \(total) \(word)"
    }
}
