import SwiftUI

/// Names shared by the onboarding "done" screen and the sidebar row, so the
/// account can fly from one to the other as a single hero element.
enum OnboardingHero {
    static let coordinateSpace = "onboarding-hero"
}

struct OnboardingHeroFrame: Equatable {
    let accountID: UUID
    let rect: CGRect
}

/// The frame of the account row on the onboarding "done" screen, in the root
/// coordinate space.
struct OnboardingHeroSourceKey: PreferenceKey {
    static var defaultValue: OnboardingHeroFrame?

    static func reduce(value: inout OnboardingHeroFrame?, nextValue: () -> OnboardingHeroFrame?) {
        value = nextValue() ?? value
    }
}

/// Frames of the sidebar's account rows, keyed by account id.
struct SidebarAccountFramesKey: PreferenceKey {
    static var defaultValue: [UUID: CGRect] = [:]

    static func reduce(value: inout [UUID: CGRect], nextValue: () -> [UUID: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { $1 })
    }
}

/// The account chip while it flies from onboarding into the sidebar. It draws
/// the sidebar row's own content, so swapping it for the real row is invisible.
struct OnboardingAccountHeroChip: View {
    let account: Account
    let masked: Bool
    var showsChrome = true

    var body: some View {
        SidebarAccountRowContent(
            account: account,
            isSelected: false,
            isFocused: false,
            masked: masked
        )
        .background {
            if showsChrome {
                let shape = RoundedRectangle(cornerRadius: SidebarLayout.selectionCornerRadius, style: .continuous)
                shape
                    .fill(AppColors.fillSecondary)
                    .overlay {
                        shape.strokeBorder(AppColors.borderStrong, lineWidth: 0.5)
                    }
                    .shadow(color: .black.opacity(0.30), radius: 14, y: 7)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
