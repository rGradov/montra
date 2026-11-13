import SwiftUI

/// What the current page wants in the one shared detail header. It lives
/// outside the route transition, so the title never cross-fades with the whole
/// page. `trailing` carries the page's own actions and closures.
struct DetailHeaderConfig {
    var title: String
    var subtitle: String?
    var backTitle: String?
    var onBack: (() -> Void)?
    var trailing: AnyView
}

@MainActor
final class DetailHeaderHost: ObservableObject {
    @Published var config = DetailHeaderConfig(
        title: "",
        subtitle: nil,
        backTitle: nil,
        onBack: nil,
        trailing: AnyView(EmptyView())
    )
}

/// The single header for every detail route: it stays mounted while the body
/// cross-fades, and only the title/subtitle animate from old to new.
struct SharedDetailHeader: View {
    @ObservedObject var host: DetailHeaderHost

    var body: some View {
        let config = host.config

        VStack(alignment: .leading, spacing: AppStyle.Spacing.xxSmall) {
            backRow(config)

            #if os(iOS)
            // A page's actions are laid out beside its title on the Mac and on a
            // wide iPad page. On a phone they do not fit there, so they drop to
            // their own row instead of being squeezed into a truncated strip.
            ViewThatFits(in: .horizontal) {
                titleRow(config)
                stackedRow(config)
            }
            #else
            titleRow(config)
            #endif
        }
        .padding(.horizontal, AppDetailPageLayout.horizontalInset)
        .padding(.top, AppDetailPageLayout.topContentInset)
        .padding(.bottom, AppStyle.Spacing.small)
        .background(AppColors.surfaceBase)
    }

    private func backRow(_ config: DetailHeaderConfig) -> some View {
        Group {
            if let backTitle = config.backTitle, let onBack = config.onBack {
                Button(action: onBack) {
                    Label(backTitle, systemImage: "chevron.left")
                }
                .buttonStyle(.montra(.quiet, size: .small))
            } else {
                // Keep the back row reserved on top-level pages so the title and
                // subtitle never change height between routes.
                Button {} label: {
                    Label(String(localized: "navigation.overview"), systemImage: "chevron.left")
                }
                .buttonStyle(.montra(.quiet, size: .small))
                .opacity(0)
                .disabled(true)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
            }
        }
        .padding(.bottom, 2)
    }

    private func titleBlock(_ config: DetailHeaderConfig) -> some View {
        VStack(alignment: .leading, spacing: AppStyle.Spacing.xxSmall) {
            AnimatedPageTitle(title: config.title)

            Group {
                if let subtitle = config.subtitle, !subtitle.isEmpty {
                    AnimatedHeaderSubtitle(text: subtitle)
                } else {
                    Color.clear
                }
            }
            // The Mac keeps the exact reserved height it always had. On iOS the
            // subtitle may need a second line at larger Dynamic Type sizes, so it
            // reserves a minimum instead of a fixed height.
            .modifier(HeaderSubtitleHeight())
        }
    }

    private func titleRow(_ config: DetailHeaderConfig) -> some View {
        HStack(alignment: .top, spacing: AppStyle.Spacing.medium) {
            titleBlock(config)

            Spacer(minLength: AppStyle.Spacing.medium)

            config.trailing
                .padding(.top, 1)
        }
    }

    #if os(iOS)
    /// Title, then the page's actions on their own line. The actions scroll
    /// sideways when even a full row is not enough (a narrow phone in landscape
    /// with three header buttons), so nothing is ever clipped or scaled down.
    private func stackedRow(_ config: DetailHeaderConfig) -> some View {
        VStack(alignment: .leading, spacing: AppStyle.Spacing.xSmall) {
            titleBlock(config)

            ScrollView(.horizontal) {
                config.trailing
                    .padding(.top, 1)
                    .padding(.bottom, 2)
            }
            .scrollIndicators(.hidden)
            .scrollBounceBehavior(.basedOnSize)
        }
    }
    #endif
}

/// The subtitle's reserved height: fixed on the Mac (unchanged), a minimum on
/// iOS so large text sizes are not clipped.
private struct HeaderSubtitleHeight: ViewModifier {
    func body(content: Content) -> some View {
        #if os(iOS)
        content.frame(minHeight: 28, alignment: .topLeading)
        #else
        content.frame(height: 28, alignment: .topLeading)
        #endif
    }
}

/// Page titles: one line at their natural width on the Mac, where the window
/// always has room. On iOS a title can be longer than the screen (an account
/// name), so it may wrap to a second line and truncates only after that.
private struct PageTitleWidth: ViewModifier {
    static var lineLimit: Int {
        #if os(iOS)
        2
        #else
        1
        #endif
    }

    func body(content: Content) -> some View {
        #if os(iOS)
        content.frame(maxWidth: .infinity, alignment: .leading)
        #else
        content.fixedSize(horizontal: true, vertical: false)
        #endif
    }
}

extension View {
    /// The room a scrolling page leaves under its last row for the floating
    /// shell bar. The bar's height belongs to the shell, which publishes it as
    /// safe area, so this only adds breathing space on top of that safe area and
    /// never hard-codes a height.
    @ViewBuilder
    func shellBottomRoom(_ extra: CGFloat = 0) -> some View {
        #if os(iOS)
        self.safeAreaPadding(.bottom, AppStyle.Spacing.small + extra)
        #else
        self
        #endif
    }
}

/// The outgoing title fades as it moves up. The incoming title rises into
/// place. A persistent view keeps the text from appearing twice.
struct AnimatedPageTitle: View {
    let title: String

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var displayedTitle: String
    @State private var previousTitle: String?
    @State private var previousTitleVisible = false
    @State private var titleVisible = true
    @State private var animationToken = 0

    init(title: String) {
        self.title = title
        _displayedTitle = State(initialValue: title)
    }

    var body: some View {
        ZStack(alignment: .leading) {
            if let previousTitle {
                titleText(previousTitle)
                    .opacity(previousTitleVisible ? 1 : 0)
                    .offset(y: previousTitleVisible ? 0 : -5)
                    .blur(radius: previousTitleVisible ? 0 : 1.5)
            }

            titleText(displayedTitle)
                .opacity(titleVisible || reduceMotion ? 1 : 0)
                .offset(y: titleVisible || reduceMotion ? 0 : 6)
                .blur(radius: titleVisible || reduceMotion ? 0 : 0.8)
                .animation(titleAnimation, value: titleVisible)
                .id(animationToken)
        }
        .modifier(PageTitleWidth())
        .accessibilityRepresentation {
            Text(title)
                .accessibilityAddTraits(.isHeader)
        }
        .onChange(of: title) { _, newTitle in
            animateTitleChange(to: newTitle)
        }
    }

    private func titleText(_ value: String) -> some View {
        Text(value)
            .font(AppStyle.Typography.pageTitle)
            .lineLimit(PageTitleWidth.lineLimit)
            .truncationMode(.tail)
            .multilineTextAlignment(.leading)
    }

    private func animateTitleChange(to newTitle: String) {
        guard newTitle != displayedTitle else { return }

        if reduceMotion {
            displayedTitle = newTitle
            previousTitle = nil
            titleVisible = true
            return
        }

        previousTitle = displayedTitle
        previousTitleVisible = true

        var transaction = Transaction()
        transaction.animation = nil
        withTransaction(transaction) {
            displayedTitle = newTitle
            animationToken += 1
            titleVisible = false
        }
        let currentToken = animationToken

        withAnimation(.easeOut(duration: 0.16)) {
            previousTitleVisible = false
        }
        withAnimation(.spring(response: 0.28, dampingFraction: 0.78, blendDuration: 0.04)) {
            titleVisible = true
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.28) {
            guard animationToken == currentToken else { return }
            previousTitle = nil
        }
    }

    private var titleAnimation: Animation? {
        guard !reduceMotion else { return nil }
        return .spring(response: 0.28, dampingFraction: 0.8, blendDuration: 0.04)
    }
}

/// Same idea one step quieter for the subtitle: a short fade/rise, never two
/// overlapping page fades.
struct AnimatedHeaderSubtitle: View {
    let text: String

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var displayedText: String
    @State private var previousText: String?
    @State private var previousVisible = false
    @State private var textVisible = true
    @State private var animationToken = 0

    init(text: String) {
        self.text = text
        _displayedText = State(initialValue: text)
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            if let previousText {
                subtitle(previousText)
                    .opacity(previousVisible ? 1 : 0)
                    .offset(y: previousVisible ? 0 : -3)
                    .blur(radius: previousVisible ? 0 : 1)
            }

            subtitle(displayedText)
                .opacity(textVisible || reduceMotion ? 1 : 0)
                .offset(y: textVisible || reduceMotion ? 0 : 4)
                .blur(radius: textVisible || reduceMotion ? 0 : 0.6)
                .animation(textAnimation, value: textVisible)
                .id(animationToken)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .onChange(of: text) { _, newText in
            animateTextChange(to: newText)
        }
    }

    private func subtitle(_ value: String) -> some View {
        Text(figures: value, style: AppStyle.Typography.metadata)
            .monospacedDigit()
            .foregroundStyle(AppColors.textSecondary)
            .lineLimit(2)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func animateTextChange(to newText: String) {
        guard newText != displayedText else { return }

        if reduceMotion {
            displayedText = newText
            previousText = nil
            textVisible = true
            return
        }

        previousText = displayedText
        previousVisible = true

        var transaction = Transaction()
        transaction.animation = nil
        withTransaction(transaction) {
            displayedText = newText
            animationToken += 1
            textVisible = false
        }
        let currentToken = animationToken

        withAnimation(.easeOut(duration: 0.16)) {
            previousVisible = false
        }
        withAnimation(.spring(response: 0.3, dampingFraction: 0.82, blendDuration: 0.04)) {
            textVisible = true
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            guard animationToken == currentToken else { return }
            previousText = nil
        }
    }

    private var textAnimation: Animation? {
        guard !reduceMotion else { return nil }
        return .spring(response: 0.3, dampingFraction: 0.84, blendDuration: 0.04)
    }
}
