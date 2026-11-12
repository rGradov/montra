import SwiftUI

// MARK: - Sheet chrome

struct SheetHeader: View {
    let title: String
    var subtitle: String?
    let onClose: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: AppStyle.Spacing.medium) {
            VStack(alignment: .leading, spacing: AppStyle.Spacing.xxxSmall) {
                Text(title)
                    .font(AppStyle.Typography.sectionTitle)
                if let subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(AppStyle.Typography.callout)
                        .foregroundStyle(AppColors.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Spacer(minLength: AppStyle.Spacing.small)

            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .semibold))
            }
            .buttonStyle(.montra(.secondary, size: .small, width: .square))
            .accessibilityLabel(String(localized: "common.close"))
            .keyboardShortcut(.cancelAction)
        }
        .padding(.horizontal, AppStyle.Spacing.large)
        .padding(.top, AppStyle.Spacing.large)
        .padding(.bottom, AppStyle.Spacing.medium)
    }
}

struct SheetFooter<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        HStack(spacing: AppStyle.Spacing.xSmall) {
            content
        }
        .padding(.horizontal, AppStyle.Spacing.large)
        .padding(.vertical, AppStyle.Spacing.medium)
        .background(AppColors.surfaceBase)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(AppColors.borderSubtle)
                .frame(height: 0.5)
        }
    }
}

// MARK: - Fields

struct FieldLabel: View {
    let title: String
    var trailing: String?

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(AppStyle.Typography.callout.weight(.medium))
                .foregroundStyle(AppColors.textSecondary)
            Spacer(minLength: AppStyle.Spacing.xSmall)
            if let trailing {
                Text(trailing)
                    .font(AppStyle.Typography.metadata)
                    .foregroundStyle(AppColors.textTertiary)
            }
        }
    }
}

struct MontraTextField: View {
    let placeholder: String
    @Binding var text: String
    var axis: Axis = .horizontal
    var lineLimit: ClosedRange<Int> = 1...1
    var height: CGFloat = 32
    var font: AppStyle.TextStyle = AppStyle.Typography.body

    @FocusState private var isFocused: Bool

    var body: some View {
        TextField(placeholder, text: $text, axis: axis)
            .textFieldStyle(.plain)
            .font(font)
            .lineLimit(lineLimit)
            .padding(.horizontal, AppStyle.Spacing.small)
            .padding(.vertical, axis == .vertical ? AppStyle.Spacing.xSmall : 0)
            .frame(minHeight: height, alignment: axis == .vertical ? .top : .center)
            .background(
                AppColors.surfaceRaised,
                in: RoundedRectangle(cornerRadius: AppStyle.Radius.md, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: AppStyle.Radius.md, style: .continuous)
                    .strokeBorder(isFocused ? AppColors.accent : AppColors.borderSubtle,
                                  lineWidth: isFocused ? 1.5 : 0.5)
            }
            .focused($isFocused)
            .animation(.easeOut(duration: 0.12), value: isFocused)
    }
}

/// A picker that holds a value: rounded rectangle, not a pill, so it reads as a
/// setting and never as an action. A popover rather than `Menu`, because `Menu`
/// drops the custom label's background on macOS.
struct DropdownMenu<Option: Hashable>: View {
    let options: [Option]
    let selection: Option
    let selectionLabel: String
    let optionLabel: (Option) -> String
    var fillsWidth = false
    var minimumWidth: CGFloat = 120
    let onSelect: (Option) -> Void

    var body: some View {
        PopoverMenu(
            options: options,
            selection: selection,
            optionLabel: optionLabel,
            minimumWidth: max(minimumWidth, 140),
            fillsWidth: fillsWidth,
            onSelect: onSelect
        ) {
            HStack(spacing: AppStyle.Spacing.xSmall) {
                Text(figures: selectionLabel, style: AppStyle.Typography.body)
                    .lineLimit(1)
                Spacer(minLength: fillsWidth ? AppStyle.Spacing.xSmall : 0)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(AppColors.textSecondary)
            }
            .padding(.horizontal, AppStyle.Spacing.small)
            .frame(height: AppStyle.Control.height)
            .frame(minWidth: minimumWidth, alignment: .leading)
            .frame(maxWidth: fillsWidth ? .infinity : nil, alignment: .leading)
            .background(
                AppColors.surfaceRaised,
                in: RoundedRectangle(cornerRadius: AppStyle.Radius.md, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: AppStyle.Radius.md, style: .continuous)
                    .strokeBorder(AppColors.borderSubtle, lineWidth: 0.5)
            }
            .contentShape(Rectangle())
        }
        .fixedSize(horizontal: !fillsWidth, vertical: true)
        .accessibilityLabel(selectionLabel)
    }
}

/// A popover menu with the app's own rows, the pointer hand and a checkmark on
/// the current value. Any label can open it, so the same menu serves a settings
/// picker, a chip and an icon button.
struct PopoverMenu<Option: Hashable, Label: View>: View {
    let options: [Option]
    let selection: Option?
    let optionLabel: (Option) -> String
    var minimumWidth: CGFloat = 160
    var fillsWidth = false
    let onSelect: (Option) -> Void
    @ViewBuilder let label: () -> Label

    @State private var isPresented = false
    @State private var hovered: Option?

    var body: some View {
        Button {
            isPresented.toggle()
        } label: {
            label()
        }
        .buttonStyle(.plain)
        .pointingHandOnHover()
        .popover(isPresented: $isPresented, arrowEdge: .bottom) {
            menuContent
        }
    }

    private var menuContent: some View {
        VStack(alignment: .leading, spacing: 1) {
            ForEach(Array(options.enumerated()), id: \.offset) { _, option in
                Button {
                    onSelect(option)
                    isPresented = false
                } label: {
                    HStack(spacing: AppStyle.Spacing.xSmall) {
                        Text(optionLabel(option))
                            .font(AppStyle.Typography.body)
                            .lineLimit(1)
                        Spacer(minLength: AppStyle.Spacing.medium)
                        if option == selection {
                            Image(systemName: "checkmark")
                                .font(.system(size: 10, weight: .bold))
                        }
                    }
                    .foregroundStyle(AppColors.textPrimary)
                    .padding(.horizontal, AppStyle.Spacing.xSmall)
                    .frame(height: 24)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        hovered == option ? AppColors.fillSecondary : .clear,
                        in: RoundedRectangle(cornerRadius: AppStyle.Radius.sm, style: .continuous)
                    )
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .onHover { hovering in hovered = hovering ? option : (hovered == option ? nil : hovered) }
            }
        }
        .padding(AppStyle.Spacing.xxSmallPlus)
        .frame(minWidth: minimumWidth)
        .background(AppColors.surfaceRaised)
    }
}

/// A row inside a form: label above, control below, the app's rhythm.
struct FormField<Content: View>: View {
    let title: String
    var trailing: String?
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: AppStyle.Spacing.xxSmallPlus) {
            FieldLabel(title: title, trailing: trailing)
            content
        }
    }
}

/// A date and time that reads like the app's other fields and opens a calendar
/// in a popover. The reference styles every value holder this way, so the native
/// compact picker's own bezel never appears.
struct DatePickerField: View {
    @Binding var date: Date
    var showsTime = true
    var range: ClosedRange<Date>?

    @State private var isPresented = false

    private var text: String {
        showsTime ? AppDate.dayMonthTime.string(from: date) : AppDate.short(date) + " " + String(Calendar.current.component(.year, from: date))
    }

    var body: some View {
        Button {
            isPresented.toggle()
        } label: {
            HStack(spacing: AppStyle.Spacing.xSmall) {
                Text(text)
                    .font(AppStyle.Typography.body)
                    .lineLimit(1)
                Spacer(minLength: AppStyle.Spacing.xSmall)
                Image(systemName: "calendar")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(AppColors.textSecondary)
            }
            .padding(.horizontal, AppStyle.Spacing.small)
            .frame(height: 32)
            .background(
                AppColors.surfaceRaised,
                in: RoundedRectangle(cornerRadius: AppStyle.Radius.md, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: AppStyle.Radius.md, style: .continuous)
                    .strokeBorder(AppColors.borderSubtle, lineWidth: 0.5)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .pointingHandOnHover()
        .popover(isPresented: $isPresented, arrowEdge: .bottom) {
            MontraDateTimePicker(date: $date, showsTime: showsTime, range: range)
                .padding(AppStyle.Spacing.small)
                .background(AppColors.surfaceBase)
        }
    }
}

/// A compact number stepper that holds a value: minus, an editable number, its
/// unit, plus. Typing is for jumping far (1 to 31) without a menu; the buttons
/// stay for the usual one-step changes. Both paths clamp to the range.
struct NumberStepper: View {
    @Binding var value: Int
    let range: ClosedRange<Int>
    var step: Int = 1
    let label: (Int) -> String
    /// Shown after the editable number, for example an ordinal suffix or "days".
    var suffix: (Int) -> String = { _ in "" }
    var accessibilityTitle: String?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @FocusState private var isFocused: Bool
    @State private var text: String = ""
    @State private var outsideClickMonitor: Any?

    private var canDecrease: Bool { value - step >= range.lowerBound }
    private var canIncrease: Bool { value + step <= range.upperBound }
    private var maxDigits: Int { String(range.upperBound).count }

    /// The unit updates as the user types, before they commit the value.
    /// For example, "1 day" changes to "2 days" when they type 2.
    private var previewValue: Int {
        Int(text) ?? value
    }

    var body: some View {
        HStack(spacing: 0) {
            StepButton(
                symbol: "minus",
                enabled: canDecrease,
                help: String(localized: "common.decrease"),
                action: { adjust(-step) }
            )

            ZStack {
                HStack(spacing: suffix(previewValue).hasPrefix("-") ? 0 : AppStyle.Spacing.xxxSmall) {
                    TextField("", text: $text)
                        .textFieldStyle(.plain)
                        .font(AppStyle.Typography.body)
                        .monospacedDigit()
                        .multilineTextAlignment(.center)
                        .frame(width: maxDigits == 2 ? 20 : 30)
                        .focused($isFocused)
                        .focusEffectDisabled()
                        .onSubmit(commit)
                        .onChange(of: text) { _, newValue in
                            let digits = String(newValue.filter(\.isNumber).prefix(maxDigits))
                            if digits != newValue { text = digits }
                        }
                        .onExitCommand {
                            text = "\(value)"
                            isFocused = false
                        }

                    if !suffix(previewValue).isEmpty {
                        Text(suffix(previewValue))
                            .font(AppStyle.Typography.body)
                            .foregroundStyle(AppColors.textSecondary)
                            .lineLimit(1)
                    }
                }
                .opacity(isFocused ? 1 : 0)

                if !isFocused {
                    Text(label(value))
                        .font(AppStyle.Typography.body)
                        .foregroundStyle(AppColors.textPrimary)
                        .contentTransition(reduceMotion ? .identity : .numericText())
                        .lineLimit(1)
                        .allowsHitTesting(false)
                }
            }
            .frame(minWidth: 72)
            .padding(.horizontal, AppStyle.Spacing.xxSmall)
            .contentShape(Rectangle())
            .onTapGesture { isFocused = true }
            .help(String(localized: "common.enter_a_number_from_to \(range.lowerBound) \(range.upperBound)"))
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.12), value: isFocused)

            StepButton(
                symbol: "plus",
                enabled: canIncrease,
                help: String(localized: "common.increase"),
                action: { adjust(step) }
            )
        }
        .frame(height: AppStyle.Control.height)
        .background(
            AppColors.surfaceRaised,
            in: RoundedRectangle(cornerRadius: AppStyle.Radius.md, style: .continuous)
        )
        .clipShape(RoundedRectangle(cornerRadius: AppStyle.Radius.md, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: AppStyle.Radius.md, style: .continuous)
                .strokeBorder(
                    isFocused ? AppColors.actionPrimary : AppColors.borderSubtle,
                    lineWidth: isFocused ? 1 : 0.5
                )
        }
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.15), value: isFocused)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityTitle ?? label(value))
        .accessibilityValue(label(value))
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: adjust(step)
            case .decrement: adjust(-step)
            @unknown default: break
            }
        }
        .onAppear { text = "\(value)" }
        .onChange(of: value) { _, newValue in
            guard !isFocused else { return }
            text = "\(newValue)"
        }
        .onChange(of: isFocused) { _, focused in
            if focused {
                text = "\(value)"
                installOutsideClickResign()
            } else {
                removeOutsideClickResign()
                commit()
            }
        }
        .onDisappear {
            removeOutsideClickResign()
            commit()
        }
    }

    /// Clicking a row or empty space must commit the typed number, and SwiftUI
    /// does not always resign a field's first responder for such clicks.
    private func installOutsideClickResign() {
        guard outsideClickMonitor == nil else { return }
        outsideClickMonitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown) { event in
            guard let window = event.window,
                  let hitView = window.contentView?.hitTest(event.locationInWindow),
                  hitView !== window.firstResponder
            else { return event }
            window.makeFirstResponder(nil)
            return event
        }
    }

    private func removeOutsideClickResign() {
        if let monitor = outsideClickMonitor {
            NSEvent.removeMonitor(monitor)
            outsideClickMonitor = nil
        }
    }

    private func adjust(_ delta: Int) {
        let base = Int(text) ?? value
        let next = min(max(base + delta, range.lowerBound), range.upperBound)
        text = "\(next)"
        guard next != value else { return }
        if reduceMotion {
            value = next
        } else {
            withAnimation(.easeInOut(duration: 0.2)) { value = next }
        }
    }

    private func commit() {
        guard let parsed = Int(text) else {
            text = "\(value)"
            return
        }
        let clamped = min(max(parsed, range.lowerBound), range.upperBound)
        text = "\(clamped)"
        guard clamped != value else { return }
        if reduceMotion {
            value = clamped
        } else {
            withAnimation(.easeInOut(duration: 0.2)) { value = clamped }
        }
    }
}

private struct StepButton: View {
    let symbol: String
    let enabled: Bool
    let help: String
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 10, weight: .semibold))
                .frame(width: 28, height: AppStyle.Control.height)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(enabled ? AppColors.textSecondary : AppColors.textTertiary.opacity(0.35))
        .background(isHovering && enabled ? AppColors.fillSecondaryHover : .clear)
        .disabled(!enabled)
        .onHover { isHovering = $0 }
        .animation(.easeOut(duration: 0.12), value: isHovering)
        .help(help)
        .accessibilityLabel(help)
    }
}

// MARK: - Segmented chips

/// Two or three options where exactly one is on: the reference's chip row.
struct ChipGroup<Value: Hashable>: View {
    let options: [Value]
    let selection: Value
    let label: (Value) -> String
    var icon: ((Value) -> String)?
    let onSelect: (Value) -> Void
    /// Background for unselected options; the selected chip stays raised.
    var chipBackground: Color? = nil

    var body: some View {
        HStack(spacing: AppStyle.Spacing.xSmall) {
            ForEach(options, id: \.self) { option in
                FilterChip(
                    style: .tab,
                    label: label(option),
                    isSelected: option == selection,
                    leadingSystemImage: icon?(option),
                    unselectedBackground: chipBackground
                )
                .onTapGesture { onSelect(option) }
                .accessibilityAddTraits(.isButton)
            }
        }
    }
}
