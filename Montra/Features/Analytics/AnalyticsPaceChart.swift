import Charts
import SwiftUI

/// The cumulative spending chart: the current period solid, the previous period
/// dashed, and the previous period's even pace dotted. The hover/focus overlay
/// is custom so the tooltip stays a quiet card and the keyboard can read every
/// day.
struct AnalyticsPaceChart: View {
    let snapshot: AnalyticsSnapshot
    let currency: Currency
    let masked: Bool

    @State private var hoveredDay: Int?
    @FocusState private var isFocused: Bool

    private var totalDays: Int { snapshot.range.totalDays }

    private var currentPoints: [ChartPoint] {
        snapshot.currentCumulative.enumerated().compactMap { index, value in
            guard let value else { return nil }
            return ChartPoint(day: index + 1, value: decimal(value))
        }
    }

    private var previousPoints: [ChartPoint] {
        guard snapshot.previousFullTotal > 0 else { return [] }
        return snapshot.previousCumulative.enumerated().compactMap { index, value in
            guard index + 1 <= totalDays else { return nil }
            return ChartPoint(day: index + 1, value: decimal(value))
        }
    }

    private var pacePoints: [ChartPoint] {
        snapshot.pace.enumerated().map { index, value in
            ChartPoint(day: index + 1, value: decimal(value))
        }
    }

    private var xValues: [Int] {
        var values = Set([1])
        values.formUnion(stride(from: 5, through: totalDays, by: 5))
        if let today = snapshot.todayDay {
            values = Set(values.filter { abs($0 - today) > 2 || $0 == 1 })
            values.insert(today)
        }
        return values.sorted()
    }

    private var yValues: [Double] {
        stride(from: 0, through: snapshot.chartMax, by: 400).map { $0 }
    }

    var body: some View {
        Chart {
            ForEach(currentPoints) { point in
                AreaMark(
                    x: .value("Day", point.day),
                    yStart: .value("Zero", 0),
                    yEnd: .value("Total", point.value)
                )
                .foregroundStyle(
                    LinearGradient(
                        colors: [AppColors.textPrimary.opacity(0.10), AppColors.textPrimary.opacity(0)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .interpolationMethod(.monotone)
            }

            ForEach(currentPoints) { point in
                LineMark(
                    x: .value("Day", point.day),
                    y: .value("Total", point.value),
                    series: .value("Series", "current")
                )
                .foregroundStyle(AppColors.textPrimary)
                .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                .interpolationMethod(.monotone)
            }

            if !previousPoints.isEmpty {
                ForEach(previousPoints) { point in
                    LineMark(
                        x: .value("Day", point.day),
                        y: .value("Total", point.value),
                        series: .value("Series", "previous")
                    )
                    .foregroundStyle(AppColors.textTertiary.opacity(0.55))
                    .lineStyle(StrokeStyle(lineWidth: 1.2, dash: [4, 4]))
                    .interpolationMethod(.monotone)
                }
            }

            if !pacePoints.isEmpty {
                ForEach(pacePoints) { point in
                    LineMark(
                        x: .value("Day", point.day),
                        y: .value("Total", point.value),
                        series: .value("Series", "pace")
                    )
                    .foregroundStyle(AppColors.borderStrong)
                    .lineStyle(StrokeStyle(lineWidth: 1.2, dash: [2, 4]))
                    .interpolationMethod(.monotone)
                }
            }

            if let today = snapshot.todayDay {
                RuleMark(x: .value("Today", today))
                    .foregroundStyle(AppColors.borderStrong)
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))

                if let value = value(on: today) {
                    PointMark(
                        x: .value("Today", today),
                        y: .value("Total", value)
                    )
                    .symbolSize(80)
                    .foregroundStyle(AppColors.surfaceCard)

                    PointMark(
                        x: .value("Today", today),
                        y: .value("Total", value)
                    )
                    .symbolSize(26)
                    .foregroundStyle(AppColors.textPrimary)
                }
            }

            if let hoveredDay, hoveredDay != snapshot.todayDay {
                RuleMark(x: .value("Hovered", hoveredDay))
                    .foregroundStyle(AppColors.textTertiary.opacity(0.55))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
            }
        }
        .chartXScale(domain: 1...max(2, totalDays))
        .chartYScale(domain: 0...snapshot.chartMax)
        .chartLegend(.hidden)
        .chartXAxis {
            AxisMarks(values: xValues) { value in
                AxisTick().foregroundStyle(.clear)
                AxisGridLine().foregroundStyle(.clear)
                AxisValueLabel(anchor: .top) {
                    if let day = value.as(Int.self) {
                        if snapshot.todayDay == day {
                            Text(String(localized: "analytics.today_short"))
                                .font(AppStyle.Typography.micro.weight(.regular))
                                .foregroundStyle(AppColors.textTertiary)
                                .fixedSize()
                        } else {
                            Text("\(day)")
                                .font(.system(size: 10, weight: .regular, design: .rounded))
                                .foregroundStyle(AppColors.textTertiary)
                        }
                    }
                }
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading, values: yValues) { value in
                AxisGridLine().foregroundStyle(AppColors.borderSubtle.opacity(0.55))
                AxisTick().foregroundStyle(.clear)
                AxisValueLabel(anchor: .trailing) {
                    if let number = value.as(Double.self) {
                        Text(masked ? "••••" : MoneyFormat.number(Decimal(number), fractionDigits: 0))
                            .font(.system(size: 10, weight: .regular, design: .rounded))
                            .foregroundStyle(AppColors.textTertiary)
                    }
                }
            }
        }
        .frame(height: 168)
        .chartOverlay { proxy in
            GeometryReader { geometry in
                ZStack(alignment: .topLeading) {
                    Rectangle()
                        .fill(.clear)
                        .contentShape(Rectangle())
                        .onContinuousHover { phase in
                            switch phase {
                            case .active(let location):
                                hoveredDay = day(at: location, proxy: proxy, geometry: geometry)
                            case .ended:
                                if !isFocused { hoveredDay = nil }
                            }
                        }
                        .focusable()
                        .focused($isFocused)
                        .onKeyPress(.leftArrow) {
                            step(-1)
                            return .handled
                        }
                        .onKeyPress(.rightArrow) {
                            step(1)
                            return .handled
                        }
                        .onChange(of: isFocused) { _, focused in
                            if focused, hoveredDay == nil {
                                hoveredDay = snapshot.todayDay ?? 1
                            }
                        }

                    if let hoveredDay,
                       let day = snapshot.days.first(where: { $0.id == hoveredDay }),
                       let plot = plotRect(proxy: proxy, geometry: geometry) {
                        tooltip(day)
                            .frame(width: 166, alignment: .leading)
                            .offset(
                                x: tooltipX(day: hoveredDay, proxy: proxy, geometry: geometry, plot: plot),
                                y: tooltipY(day: hoveredDay, proxy: proxy, geometry: geometry, plot: plot)
                            )
                            .allowsHitTesting(false)
                    }
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
    }

    // MARK: - Geometry

    private func decimal(_ value: Decimal) -> Double {
        NSDecimalNumber(decimal: value).doubleValue
    }

    private func value(on day: Int) -> Double? {
        guard day >= 1, day <= snapshot.currentCumulative.count,
              let value = snapshot.currentCumulative[day - 1] else { return nil }
        return decimal(value)
    }

    private func previousValue(on day: Int) -> Double? {
        guard snapshot.previousFullTotal > 0 else { return nil }
        if day >= 1, day <= snapshot.previousCumulative.count {
            return decimal(snapshot.previousCumulative[day - 1])
        }
        return decimal(snapshot.previousFullTotal)
    }

    private func plotRect(proxy: ChartProxy, geometry: GeometryProxy) -> CGRect? {
        guard let anchor = proxy.plotFrame else { return nil }
        return geometry[anchor]
    }

    private func day(at location: CGPoint, proxy: ChartProxy, geometry: GeometryProxy) -> Int? {
        guard let plot = plotRect(proxy: proxy, geometry: geometry), plot.width > 0 else { return nil }
        let x = location.x - plot.minX
        let fraction = min(max(x / plot.width, 0), 1)
        return 1 + Int((fraction * Double(max(1, totalDays - 1))).rounded())
    }

    private func tooltipX(day: Int, proxy: ChartProxy, geometry: GeometryProxy, plot: CGRect) -> CGFloat {
        let position = proxy.position(forX: Double(day)) ?? (plot.width / 2)
        let x = plot.minX + position
        return min(max(x - 83, 0), max(0, geometry.size.width - 166))
    }

    private func tooltipY(day: Int, proxy: ChartProxy, geometry: GeometryProxy, plot: CGRect) -> CGFloat {
        let y: CGFloat
        if let value = value(on: day), let position = proxy.position(forY: value) {
            y = plot.minY + position
        } else if let previous = previousValue(on: day), let position = proxy.position(forY: previous) {
            y = plot.minY + position
        } else {
            y = plot.midY
        }
        return max(0, min(y - 66, max(0, geometry.size.height - 62)))
    }

    private func step(_ delta: Int) {
        let current = hoveredDay ?? snapshot.todayDay ?? 1
        hoveredDay = min(max(current + delta, 1), max(1, totalDays))
    }

    // MARK: - Tooltip

    private func tooltip(_ day: AnalyticsDay) -> some View {
        let current = snapshot.currentCumulative.indices.contains(day.id - 1)
            ? snapshot.currentCumulative[day.id - 1]
            : nil
        let previous = previousValue(on: day.id).map { Decimal($0) }

        return VStack(alignment: .leading, spacing: 4) {
            Text(AppDate.short(day.date))
                .font(AppStyle.Typography.metadata)
                .foregroundStyle(AppColors.textSecondary)

            Text(current.map { money($0) } ?? "—")
                .font(AppStyle.Typography.sectionTitle.numbers)
                .monospacedDigit()
                .foregroundStyle(AppColors.textPrimary)

            if let previous, snapshot.previousFullTotal > 0 {
                Text(String(localized: "analytics.previous_value \(money(previous))"))
                    .font(AppStyle.Typography.metadata)
                    .foregroundStyle(AppColors.textSecondary)
            }
        }
        .padding(AppStyle.Spacing.xSmall)
        .background(
            RoundedRectangle(cornerRadius: AppStyle.Radius.md, style: .continuous)
                .fill(AppColors.surfaceRaised)
        )
        .overlay {
            RoundedRectangle(cornerRadius: AppStyle.Radius.md, style: .continuous)
                .strokeBorder(AppColors.borderSubtle, lineWidth: 0.5)
        }
    }

    private func money(_ value: Decimal) -> String {
        MoneyFormat.string(value, currency: currency, masked: masked)
    }

    private var accessibilityText: String {
        var text = String(localized: "analytics.chart_accessibility \(money(snapshot.expenses))")
        if snapshot.previousFullTotal > 0 {
            text += " " + String(localized: "analytics.chart_previous_accessibility \(money(snapshot.previousFullTotal))")
        }
        return text
    }
}

private struct ChartPoint: Identifiable {
    let day: Int
    let value: Double
    var id: Int { day }
}
