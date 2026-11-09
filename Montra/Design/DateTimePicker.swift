import SwiftUI

/// A calendar and time picker in Montra's own palette. The system graphical
/// picker brings a white analog clock that has nothing to do with the rest of
/// the app, so this draws a compact month grid and a small time field instead.
struct MontraDateTimePicker: View {
    @Binding var date: Date
    var showsTime: Bool = true
    var range: ClosedRange<Date>?

    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @FocusState private var isTimeFocused: Bool
    @State private var displayedMonth: Date
    @State private var timeText: String

    private static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = AppLocalization.locale
        calendar.firstWeekday = 2
        calendar.timeZone = .current
        return calendar
    }()

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = AppLocalization.locale
        formatter.dateFormat = "HH:mm"
        formatter.timeZone = .current
        return formatter
    }()

    init(date: Binding<Date>, showsTime: Bool = true, range: ClosedRange<Date>? = nil) {
        _date = date
        self.showsTime = showsTime
        self.range = range
        _displayedMonth = State(initialValue: date.wrappedValue)
        _timeText = State(initialValue: Self.timeFormatter.string(from: date.wrappedValue))
    }

    private var calendar: Calendar { Self.calendar }

    var body: some View {
        VStack(spacing: AppStyle.Spacing.xSmall) {
            monthHeader

            HStack(spacing: 2) {
                ForEach(PlanWeekday.allCases) { weekday in
                    Text(weekday.short)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(AppColors.textTertiary)
                        .frame(maxWidth: .infinity)
                }
            }
            .padding(.top, 2)

            LazyVGrid(
                columns: Array(repeating: GridItem(.flexible(), spacing: 2), count: 7),
                spacing: 2
            ) {
                ForEach(gridDates, id: \.self) { day in
                    dayCell(day)
                }
            }

            if showsTime {
                hairline
                timeRow
            }

            hairline
            footer
        }
        .frame(width: 300)
        .onAppear {
            displayedMonth = date
            timeText = Self.timeFormatter.string(from: date)
        }
        .onChange(of: date) { _, newDate in
            if !isTimeFocused {
                timeText = Self.timeFormatter.string(from: newDate)
            }
        }
        .onDisappear(perform: commitTime)
    }

    // MARK: - Header

    private var monthHeader: some View {
        HStack(spacing: AppStyle.Spacing.xxSmall) {
            Text(AppDate.monthYear.string(from: displayedMonth).capitalized(with: AppLocalization.locale))
                .font(AppStyle.Typography.headline)

            Spacer(minLength: AppStyle.Spacing.small)

            monthArrow("chevron.left", label: String(localized: "common.previous_month")) { shiftMonth(-1) }
            monthArrow("chevron.right", label: String(localized: "common.next_month")) { shiftMonth(1) }
        }
    }

    private func monthArrow(_ symbol: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(AppColors.textSecondary)
                .frame(width: 24, height: 24)
                .background(AppColors.fillSecondary.opacity(0.7), in: Circle())
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .pointingHandOnHover()
        .accessibilityLabel(label)
    }

    // MARK: - Days

    private func dayCell(_ day: Date) -> some View {
        let isCurrentMonth = calendar.isDate(day, equalTo: displayedMonth, toGranularity: .month)
        return CalendarDayCell(
            date: day,
            isSelected: calendar.isDate(day, inSameDayAs: date),
            isToday: calendar.isDateInToday(day),
            isCurrentMonth: isCurrentMonth,
            isEnabled: isEnabled(day),
            action: { select(day) }
        )
    }

    private var gridDates: [Date] {
        guard let monthStart = calendar.date(from: calendar.dateComponents([.year, .month], from: displayedMonth)),
              let start = calendar.date(
                byAdding: .day,
                value: -((calendar.component(.weekday, from: monthStart) - calendar.firstWeekday + 7) % 7),
                to: monthStart
              )
        else { return [] }
        return (0..<42).compactMap { calendar.date(byAdding: .day, value: $0, to: start) }
    }

    // MARK: - Time

    private var timeRow: some View {
        HStack(spacing: AppStyle.Spacing.xSmall) {
            Text(String(localized: "common.time"))
                .font(AppStyle.Typography.callout)
                .foregroundStyle(AppColors.textSecondary)

            Spacer(minLength: AppStyle.Spacing.small)

            TextField(String(localized: "common.hh_mm"), text: $timeText)
                .textFieldStyle(.plain)
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .multilineTextAlignment(.center)
                .frame(width: 58, height: 26)
                .background(
                    AppColors.surfaceRaised,
                    in: RoundedRectangle(cornerRadius: AppStyle.Radius.md, style: .continuous)
                )
                .overlay {
                    RoundedRectangle(cornerRadius: AppStyle.Radius.md, style: .continuous)
                        .strokeBorder(
                            isTimeFocused ? AppColors.actionPrimary : AppColors.borderSubtle,
                            lineWidth: isTimeFocused ? 1 : 0.5
                        )
                }
                .focused($isTimeFocused)
                .onSubmit {
                    commitTime()
                    isTimeFocused = false
                }
                .onExitCommand {
                    timeText = Self.timeFormatter.string(from: date)
                    isTimeFocused = false
                }
                .onChange(of: timeText) { _, newValue in
                    let filtered = String(newValue.filter { $0.isNumber || $0 == ":" }.prefix(5))
                    if filtered != newValue { timeText = filtered }
                }

            Text(String(localized: "common.hh_mm"))
                .font(AppStyle.Typography.metadata)
                .foregroundStyle(AppColors.textTertiary)
        }
    }

    private var footer: some View {
        HStack(spacing: AppStyle.Spacing.small) {
            Button(showsTime ? String(localized: "common.now") : String(localized: "date.today")) { setNow() }
                .buttonStyle(.montra(.quiet, size: .small))

            Spacer(minLength: AppStyle.Spacing.small)

            Button(String(localized: "common.done")) {
                commitTime()
                dismiss()
            }
            .buttonStyle(.montra(.primary, size: .small))
        }
    }

    private var hairline: some View {
        Rectangle()
            .fill(AppColors.borderSubtle)
            .frame(height: 0.5)
            .padding(.vertical, 1)
    }

    // MARK: - Actions

    private func shiftMonth(_ delta: Int) {
        guard let next = calendar.date(byAdding: .month, value: delta, to: displayedMonth) else { return }
        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.15)) {
            displayedMonth = next
        }
    }

    private func select(_ day: Date) {
        var components = calendar.dateComponents([.year, .month, .day], from: day)
        // Typing a time does not commit until Return or focus loss, but clicking
        // a day must not throw the typed time away: use it when it is valid.
        if showsTime, let parsed = Self.parseTime(timeText) {
            components.hour = parsed.hour
            components.minute = parsed.minute
        } else {
            let time = calendar.dateComponents([.hour, .minute], from: date)
            components.hour = time.hour
            components.minute = time.minute
        }
        guard let selected = calendar.date(from: components) else { return }

        let clamped = clampedToRange(selected)
        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.15)) {
            date = clamped
        }

        let month = calendar.date(from: calendar.dateComponents([.year, .month], from: clamped)) ?? displayedMonth
        if !calendar.isDate(month, equalTo: displayedMonth, toGranularity: .month) {
            withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.15)) {
                displayedMonth = month
            }
        }
        timeText = Self.timeFormatter.string(from: clamped)
    }

    private func setNow() {
        let now = clampedToRange(.now)
        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.15)) {
            date = now
            displayedMonth = now
        }
        timeText = Self.timeFormatter.string(from: now)
    }

    private func commitTime() {
        guard showsTime, let parsed = Self.parseTime(timeText) else {
            timeText = Self.timeFormatter.string(from: date)
            return
        }

        var components = calendar.dateComponents([.year, .month, .day], from: date)
        components.hour = parsed.hour
        components.minute = parsed.minute
        guard let updated = calendar.date(from: components) else { return }

        let clamped = clampedToRange(updated)
        if clamped != date {
            withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.15)) {
                date = clamped
            }
        }
        timeText = Self.timeFormatter.string(from: clamped)
    }

    private func isEnabled(_ day: Date) -> Bool {
        guard let range else { return true }
        let start = calendar.startOfDay(for: day)
        let end = calendar.date(byAdding: .day, value: 1, to: start)?.addingTimeInterval(-1) ?? start
        return end >= range.lowerBound && start <= range.upperBound
    }

    private func clampedToRange(_ value: Date) -> Date {
        guard let range else { return value }
        if value < range.lowerBound { return range.lowerBound }
        if value > range.upperBound { return range.upperBound }
        return value
    }

    private static func parseTime(_ text: String) -> (hour: Int, minute: Int)? {
        let digits = text.filter(\.isNumber)
        guard !digits.isEmpty else { return nil }

        var hour = 0
        var minute = 0
        if let colon = text.firstIndex(of: ":") {
            hour = Int(text[..<colon].filter(\.isNumber)) ?? 0
            minute = Int(text[text.index(after: colon)...].filter(\.isNumber)) ?? 0
        } else if digits.count <= 2 {
            hour = Int(digits) ?? 0
        } else {
            hour = Int(digits.dropLast(2)) ?? 0
            minute = Int(digits.suffix(2)) ?? 0
        }

        guard (0...23).contains(hour), (0...59).contains(minute) else { return nil }
        return (hour, minute)
    }
}

private struct CalendarDayCell: View {
    let date: Date
    let isSelected: Bool
    let isToday: Bool
    let isCurrentMonth: Bool
    let isEnabled: Bool
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            Text("\(Calendar.current.component(.day, from: date))")
                .font(.system(size: 12, weight: isSelected ? .semibold : .regular, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(foreground)
                .frame(maxWidth: .infinity)
                .frame(height: 30)
                .background {
                    if isSelected {
                        Circle().fill(AppColors.actionPrimary).frame(width: 28, height: 28)
                    } else if isHovering && isEnabled {
                        Circle().fill(AppColors.fillSecondary).frame(width: 28, height: 28)
                    } else if isToday {
                        Circle().strokeBorder(AppColors.borderStrong, lineWidth: 1).frame(width: 28, height: 28)
                    }
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.3)
        .onHover { isHovering = $0 }
        .pointingHandOnHover()
        .accessibilityLabel(Text(AppDate.fullDay.string(from: date)))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var foreground: Color {
        if isSelected { return AppColors.surfaceBase }
        if !isCurrentMonth { return AppColors.textTertiary }
        return AppColors.textPrimary
    }
}
