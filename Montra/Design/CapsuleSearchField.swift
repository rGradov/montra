import SwiftUI
#if os(macOS)
import AppKit
#endif

/// The search capsule from the reference: magnifier, plain field, clear button,
/// a focus border, Escape to clear. Clicking anywhere in the capsule focuses it,
/// and a click outside gives focus back to the window.
struct CapsuleSearchField: View {
    @Binding var query: String
    var prompt: String = String(localized: "common.search")
    var width: CGFloat = 220
    /// Incrementing this focuses the field, so ⌘F can reach it from the page.
    var focusToken: Int = 0

    @FocusState private var isFocused: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    #if os(macOS)
    @State private var outsideClickMonitor: Any?
    #endif

    private var hasText: Bool { !query.isEmpty }

    var body: some View {
        HStack(spacing: AppStyle.Spacing.xxSmallPlus) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(AppColors.textSecondary)
                .frame(width: 14, height: 14)
                .accessibilityHidden(true)

            TextField(prompt, text: $query)
                .textFieldStyle(.plain)
                .font(AppStyle.Typography.body)
                .foregroundStyle(AppColors.textPrimary)
                .focused($isFocused)
                .focusEffectDisabled()
                .accessibilityLabel(String(localized: "common.search_transactions"))
                .platformExitCommand {
                    if hasText {
                        query = ""
                    } else {
                        isFocused = false
                    }
                }

            if hasText {
                Button {
                    query = ""
                    isFocused = true
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(AppColors.textTertiary)
                }
                .buttonStyle(.plain)
                .contentShape(Rectangle())
                .platformHelp(String(localized: "common.clear_search"))
                .accessibilityLabel(String(localized: "common.clear_search"))
                .transition(.opacity)
            }
        }
        .padding(.horizontal, AppStyle.Spacing.small)
        .padding(.vertical, AppStyle.Spacing.xxSmallPlus)
        .frame(width: width)
        .background {
            Capsule(style: .continuous).fill(AppColors.fillSecondary)
        }
        .overlay {
            Capsule(style: .continuous)
                .strokeBorder(isFocused ? AppColors.actionPrimary : AppColors.borderSubtle, lineWidth: 1)
        }
        .contentShape(Capsule(style: .continuous))
        .onTapGesture { isFocused = true }
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.15), value: isFocused)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.15), value: hasText)
        .onChange(of: focusToken) { _, _ in isFocused = true }
        .onChange(of: isFocused) { _, focused in
            if focused {
                installOutsideClickResign()
            } else {
                removeOutsideClickResign()
            }
        }
        .onDisappear { removeOutsideClickResign() }
    }

    /// SwiftUI keeps a focused field's first responder when the click lands on
    /// something non-focusable. Resigning on any outside mouse-down makes the
    /// focus border behave the way a search field should.
    private func installOutsideClickResign() {
        #if os(macOS)
        guard outsideClickMonitor == nil else { return }
        outsideClickMonitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown) { event in
            guard let window = event.window,
                  let hitView = window.contentView?.hitTest(event.locationInWindow),
                  hitView !== window.firstResponder
            else { return event }
            window.makeFirstResponder(nil)
            return event
        }
        #endif
    }

    private func removeOutsideClickResign() {
        #if os(macOS)
        if let monitor = outsideClickMonitor {
            NSEvent.removeMonitor(monitor)
            outsideClickMonitor = nil
        }
        #endif
    }
}
