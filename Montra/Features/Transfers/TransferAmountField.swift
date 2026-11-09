import SwiftUI

/// A large amount field with the currency code at the trailing edge. Shared by
/// the transfer tab so both sides use the same field as the rest of the app.
struct TransferAmountField: View {
    let title: String
    @Binding var text: String
    let currency: Currency?

    @FocusState private var isFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: AppStyle.Spacing.xxSmallPlus) {
            FieldLabel(title: title)

            HStack(spacing: AppStyle.Spacing.small) {
                TextField("0", text: $text)
                    .textFieldStyle(.plain)
                    .font(.system(size: 22, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .focused($isFocused)
                    .onChange(of: text) { _, newValue in
                        let filtered = String(newValue.filter { $0.isNumber || $0 == "," || $0 == "." })
                        if filtered != newValue { text = filtered }
                    }

                Spacer(minLength: AppStyle.Spacing.small)

                if let currency {
                    ZStack(alignment: .trailing) {
                        Text(currency.code)
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                            .foregroundStyle(AppColors.textSecondary)
                            .id(currency)
                            .transition(.asymmetric(
                                insertion: .offset(y: 6).combined(with: .opacity),
                                removal: .offset(y: -6).combined(with: .opacity)
                            ))
                    }
                    .frame(width: 44, alignment: .trailing)
                    .animation(AppMotion.row, value: currency)
                }
            }
            .padding(.horizontal, AppStyle.Spacing.small)
            .frame(height: 44)
            .background(
                AppColors.surfaceRaised,
                in: RoundedRectangle(cornerRadius: AppStyle.Radius.md, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: AppStyle.Radius.md, style: .continuous)
                    .strokeBorder(
                        isFocused ? AppColors.actionPrimary : AppColors.borderSubtle,
                        lineWidth: isFocused ? 1 : 0.5
                    )
            }
            .animation(.easeInOut(duration: 0.15), value: isFocused)
        }
    }
}
