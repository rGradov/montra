import SwiftUI

// MARK: - Buttons
//
// One pill for every action. `.primary` is the single main action on a screen,
// `.secondary` everything else, `.quiet` inline links, `.destructive` deletes.
// Controls that hold a value (pickers, fields) use a rounded rectangle instead,
// so shape alone tells an action from a setting.

struct MontraButtonStyle: ButtonStyle {
    enum Role {
        case primary
        case secondary
        case destructive
        case quiet
        case soft
    }

    enum Size {
        case small
        case regular
        case large
    }

    enum Width {
        case fit
        case fill
        case fixed(CGFloat)
        case square
    }

    var role: Role = .secondary
    var size: Size = .regular
    var width: Width = .fit

    func makeBody(configuration: Configuration) -> some View {
        MontraButtonBody(configuration: configuration, role: role, size: size, width: width)
    }

    private struct MontraButtonBody: View {
        let configuration: ButtonStyle.Configuration
        let role: Role
        let size: Size
        let width: Width

        @Environment(\.isEnabled) private var isEnabled
        @Environment(\.accessibilityReduceMotion) private var reduceMotion
        @State private var isHovering = false

        var body: some View {
            sizedLabel
                .font(font)
                .foregroundStyle(foreground)
                .tint(foreground)
                .lineLimit(1)
                .padding(.horizontal, isSquare ? 0 : horizontalPadding)
                .frame(height: height)
                .background(background, in: Capsule(style: .continuous))
                .overlay {
                    if let border {
                        Capsule(style: .continuous).strokeBorder(border, lineWidth: 1)
                    }
                }
                .contentShape(Capsule(style: .continuous))
                .opacity(isEnabled ? 1 : 0.45)
                .onHover { isHovering = $0 }
                .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: isHovering)
                .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: configuration.isPressed)
                .animation(reduceMotion ? nil : .easeInOut(duration: 0.28), value: isEnabled)
        }

        @ViewBuilder
        private var sizedLabel: some View {
            switch width {
            case .fit:
                configuration.label
            case .fill:
                configuration.label.frame(maxWidth: .infinity)
            case .fixed(let value):
                configuration.label.frame(width: max(0, value - horizontalPadding * 2))
            case .square:
                configuration.label.frame(width: height)
            }
        }

        private var isSquare: Bool {
            if case .square = width { return true }
            return false
        }

        private var height: CGFloat {
            #if os(iOS)
            // Touch-first sizes. The macOS metrics stay exactly as they were.
            switch size {
            case .small: 32
            case .regular: 44
            case .large: 50
            }
            #else
            switch size {
            case .small: 24
            case .regular: 30
            case .large: 38
            }
            #endif
        }

        private var horizontalPadding: CGFloat {
            #if os(iOS)
            switch size {
            case .small: 12
            case .regular: 16
            case .large: 22
            }
            #else
            switch size {
            case .small: 10
            case .regular: 14
            case .large: 20
            }
            #endif
        }

        private var font: AppStyle.TextStyle {
            switch size {
            case .small: AppStyle.Typography.callout.weight(.semibold)
            case .regular: AppStyle.Typography.headline
            case .large: AppStyle.Typography.sectionTitle
            }
        }

        private var isActive: Bool { isEnabled && isHovering }

        private var foreground: Color {
            switch role {
            case .primary: AppColors.onActionPrimary
            case .secondary: AppColors.textPrimary
            case .destructive: .white
            case .quiet, .soft: isActive ? AppColors.textPrimary : AppColors.textSecondary
            }
        }

        private var background: Color {
            let pressed = configuration.isPressed
            switch role {
            case .primary:
                return pressed ? AppColors.actionPrimaryPressed : (isActive ? AppColors.actionPrimaryHover : AppColors.actionPrimary)
            case .secondary:
                return pressed ? AppColors.fillSecondaryPressed : (isActive ? AppColors.fillSecondaryHover : AppColors.fillSecondary)
            case .destructive:
                return pressed ? AppColors.actionDestructivePressed : (isActive ? AppColors.actionDestructiveHover : AppColors.actionDestructive)
            case .quiet:
                return pressed ? AppColors.fillSecondaryPressed : (isActive ? AppColors.fillSecondaryHover : .clear)
            case .soft:
                return pressed ? AppColors.fillSecondaryPressed : (isActive ? AppColors.fillSecondaryHover : AppColors.fillSecondary)
            }
        }

        private var border: Color? {
            role == .secondary ? AppColors.borderStrong : nil
        }
    }
}

extension ButtonStyle where Self == MontraButtonStyle {
    static func montra(
        _ role: MontraButtonStyle.Role = .secondary,
        size: MontraButtonStyle.Size = .regular,
        width: MontraButtonStyle.Width = .fit
    ) -> MontraButtonStyle {
        MontraButtonStyle(role: role, size: size, width: width)
    }
}

// MARK: - Cards

/// A grouped card: rows stacked edge to edge on one fill, rounded, hairline rim.
struct InsetCard<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) { content }
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                AppColors.fillSecondary,
                in: RoundedRectangle(cornerRadius: AppStyle.Radius.lg, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: AppStyle.Radius.lg, style: .continuous)
                    .strokeBorder(AppColors.borderSubtle, lineWidth: 0.5)
            }
    }
}

/// The quieter card the reference uses on its Overview: one step above the page,
/// no strong fill, so a long list of figures stays calm.
struct OverviewCard<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: AppStyle.Radius.lg, style: .continuous)
        VStack(alignment: .leading, spacing: 0) { content }
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(shape.fill(AppColors.surfaceCard))
            .clipShape(shape)
            .overlay(shape.strokeBorder(AppColors.borderSubtle, lineWidth: 0.5))
    }
}

struct InsetCardDivider: View {
    var horizontalInset: CGFloat = AppStyle.Spacing.medium

    var body: some View {
        Rectangle()
            .fill(AppColors.borderSubtle)
            .frame(height: 0.5)
            .padding(.horizontal, horizontalInset)
    }
}

// MARK: - Icon tile

enum AppIconSymbol {
    static func resolved(_ name: String) -> String {
        switch name {
        case "hand.heart.fill": "heart.circle.fill"
        case "cigarette.fill": "smoke.fill"
        default: name
        }
    }
}

/// An account's glyph is one stored string: an SF Symbol name or an emoji. A
/// symbol name is plain ASCII, so any non-ASCII scalar means the person picked
/// an emoji and the UI draws it as text instead of looking it up as a symbol.
/// Category icons share the field and, since the unified appearance picker, can
/// be an emoji too.
enum AppIconGlyph {
    static func isEmoji(_ value: String) -> Bool {
        !value.isEmpty && value.unicodeScalars.contains { $0.value > 0x7F }
    }
}

/// The 28pt tile from the reference: colour, soft top-to-bottom gradient, a
/// hairline rim and a white glyph. `symbol` empty draws the dashed "free" tile.
struct IconTile: View {
    var symbol: String?
    var color: Color
    var size: CGFloat = AppStyle.IconTile.size
    /// A custom asset that replaces the glyph when the user supplies one.
    var imageName: String?

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: size * AppStyle.IconTile.cornerRadiusRatio, style: .continuous)
    }

    private var tileBackground: some View {
        shape
            .fill(color)
            .overlay(shape.fill(LinearGradient(colors: [.white.opacity(0.22), .white.opacity(0)],
                                               startPoint: .top, endPoint: .bottom)))
            .overlay(shape.fill(LinearGradient(colors: [.black.opacity(0), .black.opacity(0.12)],
                                               startPoint: .top, endPoint: .bottom)))
    }

    private var rim: some View {
        shape.strokeBorder(
            LinearGradient(colors: [.white.opacity(0.35), .black.opacity(0.12)],
                           startPoint: .top, endPoint: .bottom),
            lineWidth: 0.5
        )
    }

    var body: some View {
        Group {
            if let imageName, AppAssets.image(named: imageName) != nil {
                Image(imageName)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
            } else if let symbol, !symbol.isEmpty, let asset = AppAssets.image(named: symbol) {
                // A custom asset the user added under the icon's name: it is the
                // whole tile, drawn as supplied.
                Image(platformImage: asset)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
                    .frame(width: size, height: size)
            } else if let symbol, !symbol.isEmpty, AppIconGlyph.isEmoji(symbol) {
                // An emoji keeps the colour tile: the tint still names the
                // account in the bar and charts, the glyph names it in lists.
                Text(symbol)
                    .font(.system(size: size * 0.5))
                    .frame(width: size, height: size)
                    .background { tileBackground }
                    .overlay { rim }
            } else if let symbol, !symbol.isEmpty {
                Image(systemName: AppIconSymbol.resolved(symbol))
                    .font(.system(size: size * 0.46, weight: .medium))
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.18), radius: 0.5, y: 0.5)
                    .frame(width: size, height: size)
                    .background { tileBackground }
                    .overlay { rim }
            } else {
                shape
                    .strokeBorder(color, style: StrokeStyle(lineWidth: 1.5, dash: [3, 2.5]))
                    .frame(width: size, height: size)
            }
        }
        .frame(width: size, height: size)
        .clipShape(shape)
        .accessibilityHidden(true)
    }
}

/// The account's glyph where there is no tile: a tight row, the balance bar's
/// hover line. An SF Symbol takes the account's colour; an emoji has its own.
struct AccountGlyph: View {
    let icon: String
    let color: Color
    var size: CGFloat = 12

    var body: some View {
        Group {
            if AppIconGlyph.isEmoji(icon) {
                Text(icon)
                    .font(.system(size: size + 1))
            } else {
                Image(systemName: AppIconSymbol.resolved(icon))
                    .font(.system(size: size, weight: .medium))
                    .foregroundStyle(color)
            }
        }
        .accessibilityHidden(true)
    }
}

// MARK: - Badge

struct AppBadge: View {
    enum Tone {
        case neutral
        case accent
        case safe
        case warning
        case danger
    }

    let text: String
    var tone: Tone = .neutral

    var body: some View {
        Text(text)
            .font(AppStyle.Typography.metadataEmphasis)
            .foregroundStyle(foregroundColor)
            .lineLimit(1)
            .padding(.horizontal, AppStyle.Spacing.xxSmallPlus)
            .padding(.vertical, AppStyle.Spacing.xxxSmall)
            .background(backgroundColor, in: RoundedRectangle(cornerRadius: AppStyle.Radius.sm, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: AppStyle.Radius.sm, style: .continuous)
                    .strokeBorder(borderColor, lineWidth: 0.5)
            }
    }

    private var foregroundColor: Color {
        switch tone {
        case .accent: return AppColors.textSecondary
        case .neutral: return AppColors.statusUnsureText
        case .safe: return AppColors.statusSafeText
        case .warning: return AppColors.statusCheckText
        case .danger: return AppColors.statusDangerText
        }
    }

    private var backgroundColor: Color {
        switch tone {
        case .accent: return AppColors.fillSecondary
        case .neutral: return AppColors.statusUnsureFill
        case .safe: return AppColors.statusSafeFill
        case .warning: return AppColors.statusCheckFill
        case .danger: return AppColors.statusDangerFill
        }
    }

    private var borderColor: Color {
        switch tone {
        case .accent: return AppColors.borderSubtle
        case .neutral: return AppColors.statusUnsureText.opacity(0.22)
        case .safe: return AppColors.statusSafeText.opacity(0.22)
        case .warning: return AppColors.statusCheckText.opacity(0.22)
        case .danger: return AppColors.statusDangerText.opacity(0.22)
        }
    }
}

// MARK: - Filter chip

enum FilterChipStyle {
    case dropdown
    case tab
}

enum FilterChipTier {
    case neutral
    case safe
    case checkFirst

    var selectedBackground: Color {
        switch self {
        case .neutral: return AppColors.surfaceRaised
        case .safe: return AppColors.statusSafeFill
        case .checkFirst: return AppColors.statusCheckFill
        }
    }

    var selectedForeground: Color {
        switch self {
        case .neutral: return AppColors.textPrimary
        case .safe: return AppColors.statusSafeText
        case .checkFirst: return AppColors.statusCheckText
        }
    }
}

struct FilterChip: View {
    var style: FilterChipStyle = .tab
    let label: String
    var isSelected: Bool = false
    var tier: FilterChipTier = .neutral
    var leadingSystemImage: String?
    var count: Int?
    /// Fill for an unselected chip, for chips that live on a grouped card.
    var unselectedBackground: Color?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: AppStyle.Spacing.xxSmallPlus) {
            if let leadingSystemImage {
                Image(systemName: leadingSystemImage)
                    .font(AppStyle.Typography.callout.weight(.medium))
                    .foregroundStyle(foregroundColor)
                    .frame(width: 14, height: 14)
                    .clipped()
                    .accessibilityHidden(true)
            }

            if !label.isEmpty {
                labelView
            }

            if style == .dropdown {
                Image(systemName: "chevron.down")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(AppColors.textSecondary)
                    .accessibilityHidden(true)
            } else if let count {
                Text("\(count)")
                    .font(AppStyle.Typography.rowTitle.numbers)
                    .monospacedDigit()
                    .contentTransition(reduceMotion ? .identity : .numericText())
                    .foregroundStyle(countColor)
            }
        }
        .font(AppStyle.Typography.body)
        .foregroundStyle(foregroundColor)
        .padding(.horizontal, AppStyle.Spacing.small)
        .padding(.vertical, AppStyle.Spacing.xxSmallPlus)
        .background {
            Capsule(style: .continuous).fill(backgroundColor)
        }
        .overlay {
            Capsule(style: .continuous).strokeBorder(
                style == .tab && isSelected ? AppColors.borderStrong : AppColors.borderSubtle,
                lineWidth: 1
            )
        }
        .contentShape(Capsule(style: .continuous))
        .accessibilityAddTraits(style == .tab && isSelected ? .isSelected : [])
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.15), value: isSelected)
    }

    @ViewBuilder
    private var labelView: some View {
        if style == .tab {
            ZStack(alignment: .leading) {
                Text(label)
                    .font(AppStyle.Typography.headline)
                    .opacity(0)
                    .accessibilityHidden(true)
                Text(label)
                    .font(AppStyle.Typography.body.weight(isSelected ? .semibold : .regular))
            }
            .animation(nil, value: isSelected)
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
        } else {
            Text(figures: label, style: AppStyle.Typography.body)
                .lineLimit(1)
        }
    }

    private var backgroundColor: Color {
        if style == .tab, isSelected { return tier.selectedBackground }
        return unselectedBackground ?? AppColors.fillSecondary
    }

    private var foregroundColor: Color {
        if style == .tab, isSelected { return tier.selectedForeground }
        return AppColors.textSecondary
    }

    private var countColor: Color {
        if style == .tab, isSelected { return tier.selectedForeground }
        return AppColors.textTertiary
    }
}

// MARK: - Page header

/// A page header's title and subtitle arrive with a short rise and blur, the
/// subtitle a beat later. Coming back to a page replays it, so a tab switch has
/// the same small motion as the reference.
private struct PageHeaderRevealModifier: ViewModifier {
    var delay: Double = 0
    var distance: CGFloat = 4
    /// Bumping the token replays the reveal, so a change made behind a sheet is
    /// still seen when the sheet closes.
    var token: Int = 0
    /// Header text during a route morph must be visible immediately; otherwise
    /// the matched geometry animates an invisible label.
    var revealsOnAppear: Bool = true

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var revealed: Bool

    init(delay: Double = 0, distance: CGFloat = 4, token: Int = 0, revealsOnAppear: Bool = true) {
        self.delay = delay
        self.distance = distance
        self.token = token
        self.revealsOnAppear = revealsOnAppear
        _revealed = State(initialValue: !revealsOnAppear)
    }

    func body(content: Content) -> some View {
        content
            .opacity(revealed ? 1 : 0)
            .offset(y: revealed ? 0 : distance)
            .blur(radius: revealed ? 0 : 2)
            .onAppear {
                if revealsOnAppear { reveal() }
            }
            .onChange(of: token) { _, _ in
                guard !reduceMotion else { return }
                var transaction = Transaction()
                transaction.disablesAnimations = true
                withTransaction(transaction) { revealed = false }
                reveal()
            }
    }

    private func reveal() {
        guard !revealed else { return }
        if reduceMotion {
            revealed = true
        } else {
            withAnimation(.easeOut(duration: 0.36).delay(delay)) {
                revealed = true
            }
        }
    }
}

extension View {
    func pageHeaderReveal(
        delay: Double = 0,
        distance: CGFloat = 4,
        token: Int = 0,
        revealsOnAppear: Bool = true
    ) -> some View {
        modifier(PageHeaderRevealModifier(
            delay: delay,
            distance: distance,
            token: token,
            revealsOnAppear: revealsOnAppear
        ))
    }
}

private struct PageHeaderNamespaceKey: EnvironmentKey {
    static let defaultValue: Namespace.ID? = nil
}

extension EnvironmentValues {
    var pageHeaderNamespace: Namespace.ID? {
        get { self[PageHeaderNamespaceKey.self] }
        set { self[PageHeaderNamespaceKey.self] = newValue }
    }
}

struct PageHeader<Trailing: View>: View {
    let title: String
    var subtitle: String?
    /// A quiet way back when the page is a subpage of another one.
    var backTitle: String?
    var onBack: (() -> Void)?
    /// Bumped when the page's subject changed while the page was not visible
    /// (for example, a period edited in its sheet): the subtitle replays.
    var subtitleToken: Int = 0
    @ViewBuilder var trailing: () -> Trailing

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.pageHeaderNamespace) private var headerNamespace

    init(
        title: String,
        subtitle: String? = nil,
        backTitle: String? = nil,
        onBack: (() -> Void)? = nil,
        subtitleToken: Int = 0,
        @ViewBuilder trailing: @escaping () -> Trailing = { EmptyView() }
    ) {
        self.title = title
        self.subtitle = subtitle
        self.backTitle = backTitle
        self.onBack = onBack
        self.subtitleToken = subtitleToken
        self.trailing = trailing
    }

    var body: some View {
        VStack(alignment: .leading, spacing: AppStyle.Spacing.xxSmall) {
            if let backTitle, let onBack {
                morph(
                    Button(action: onBack) {
                        Label(backTitle, systemImage: "chevron.left")
                    }
                    .buttonStyle(.montra(.quiet, size: .small))
                    .padding(.bottom, 2),
                    id: "page-back"
                )
            } else {
                // Reserve the back row on top-level pages, so every route's title
                // and subtitle sit on exactly the same lines.
                Button {} label: {
                    Label(String(localized: "navigation.overview"), systemImage: "chevron.left")
                }
                .buttonStyle(.montra(.quiet, size: .small))
                .opacity(0)
                .disabled(true)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
                .padding(.bottom, 2)
            }

            HStack(alignment: .top, spacing: AppStyle.Spacing.medium) {
                VStack(alignment: .leading, spacing: AppStyle.Spacing.xxSmall) {
                    morph(
                        Text(title)
                            .font(AppStyle.Typography.pageTitle)
                            .lineLimit(1)
                            .truncationMode(.tail),
                        id: "page-title"
                    )

                    Group {
                        if let subtitle, !subtitle.isEmpty {
                            morph(
                                Text(figures: subtitle, style: AppStyle.Typography.metadata)
                                    .monospacedDigit()
                                    .foregroundStyle(AppColors.textSecondary)
                                    .lineLimit(2)
                                    .fixedSize(horizontal: false, vertical: true)
                                    .contentTransition(reduceMotion ? .identity : .numericText())
                                    .animation(reduceMotion ? nil : .easeInOut(duration: 0.45), value: subtitle)
                                    .pageHeaderReveal(
                                        delay: 0.07,
                                        distance: 4,
                                        token: subtitleToken,
                                        revealsOnAppear: false
                                    ),
                                id: "page-subtitle"
                            )
                        } else {
                            Color.clear
                        }
                    }
                    .frame(height: 28, alignment: .topLeading)
                }

                Spacer(minLength: AppStyle.Spacing.medium)

                morph(
                    HStack(spacing: AppStyle.Spacing.xSmall) { trailing() }
                        .padding(.top, 1),
                    id: "page-actions"
                )
            }
        }
        .padding(.horizontal, AppDetailPageLayout.horizontalInset)
        .padding(.top, AppDetailPageLayout.topContentInset)
        .padding(.bottom, AppStyle.Spacing.small)
    }

    @ViewBuilder
    private func morph<Content: View>(_ content: Content, id: String) -> some View {
        if let headerNamespace {
            content.matchedGeometryEffect(id: id, in: headerNamespace)
        } else {
            content
        }
    }
}

enum AppDetailPageLayout {
    static let horizontalInset: CGFloat = AppStyle.Spacing.large
    static let topContentInset: CGFloat = 20
    static let verticalPadding: CGFloat = AppStyle.Spacing.small
}

struct SectionLabel: View {
    let title: String
    var trailing: String?

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(AppStyle.Typography.headline)
                .foregroundStyle(AppColors.textSecondary)
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: AppStyle.Spacing.small)
            if let trailing {
                Text(figures: trailing, style: AppStyle.Typography.metadata)
                    .foregroundStyle(AppColors.textTertiary)
            }
        }
        .padding(.horizontal, AppStyle.Spacing.xxSmall)
    }
}

// MARK: - Row chrome

/// Hover + press feedback for a card row. The row is a `Button` with `.plain`
/// style, so the entire surface is one target and the pointer becomes a hand.
struct CardRowChrome: ViewModifier {
    var isHovered: Bool
    var isEmphasized: Bool = false
    var cornerRadius: CGFloat = 0

    func body(content: Content) -> some View {
        content
            .background {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(isEmphasized || isHovered ? AppColors.fillSecondary.opacity(0.5) : .clear)
            }
            .contentShape(Rectangle())
    }
}

extension View {
    /// Points-at hand for a clickable row, pushed and popped symmetrically so a
    /// row that disappears under the pointer cannot leave the cursor stuck.
    func pointingHandOnHover(_ enabled: Bool = true) -> some View {
        modifier(PointingHandModifier(enabled: enabled))
    }
}

private struct PointingHandModifier: ViewModifier {
    let enabled: Bool

    func body(content: Content) -> some View {
        #if os(macOS)
        PointingHandCursorBody(content: content, enabled: enabled)
        #else
        content.platformPointerHover(enabled)
        #endif
    }
}

#if os(macOS)
private struct PointingHandCursorBody<Content: View>: View {
    let content: Content
    let enabled: Bool
    @State private var isPushed = false

    var body: some View {
        content.onHover { hovering in
            guard enabled else { return }
            if hovering, !isPushed {
                NSCursor.pointingHand.push()
                isPushed = true
            } else if !hovering, isPushed {
                NSCursor.pop()
                isPushed = false
            }
        }
        .onDisappear {
            if isPushed {
                NSCursor.pop()
                isPushed = false
            }
        }
    }
}
#endif

// MARK: - Switch
//
// The reference's switch is a dark track with a white knob, not the system's
// pale one, so the tint on a dark card stays quiet until it is on.

struct MontraSwitchStyle: ToggleStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        Button {
            withAnimation(reduceMotion ? nil : .easeOut(duration: 0.15)) {
                configuration.isOn.toggle()
            }
        } label: {
            Capsule(style: .continuous)
                .fill(configuration.isOn ? AppColors.statusSafeText : AppColors.fillSecondaryPressed)
                .frame(width: 38, height: 22)
                .overlay {
                    Capsule(style: .continuous)
                        .strokeBorder(AppColors.borderStrong.opacity(0.55), lineWidth: 0.5)
                }
                .overlay(alignment: configuration.isOn ? .trailing : .leading) {
                    Circle()
                        .fill(.white)
                        .frame(width: 18, height: 18)
                        .padding(2)
                        .shadow(color: .black.opacity(0.22), radius: 1, y: 0.5)
                }
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .pointingHandOnHover()
        .accessibilityValue(configuration.isOn ? String(localized: "common.on") : String(localized: "common.off"))
    }
}

extension ToggleStyle where Self == MontraSwitchStyle {
    static var montraSwitch: MontraSwitchStyle { MontraSwitchStyle() }
}

// MARK: - Small controls

struct InfoButton: View {
    let title: String
    let text: String
    @State private var isShowing = false

    var body: some View {
        Button {
            isShowing.toggle()
        } label: {
            Image(systemName: "info.circle")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(AppColors.textTertiary)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .popover(isPresented: $isShowing, arrowEdge: .bottom) {
            Text(text)
                .font(AppStyle.Typography.callout)
                .foregroundStyle(AppColors.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(AppStyle.Spacing.medium)
                .frame(width: 260, alignment: .leading)
        }
    }
}

/// A native checkbox, drawn the way the reference draws row selection.
struct RowCheckbox: View {
    let isOn: Bool
    var accessibilityLabel: String

    var body: some View {
        #if os(macOS)
        Toggle(accessibilityLabel, isOn: .constant(isOn))
            .labelsHidden()
            #if os(macOS)
            .toggleStyle(.checkbox)
            #else
            .toggleStyle(.touchCheckbox)
            #endif
            .tint(AppColors.actionPrimary)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
            .frame(width: 14)
        #else
        RoundedRectangle(cornerRadius: 3.5, style: .continuous)
            .fill(isOn ? AppColors.actionPrimary : .clear)
            .overlay {
                RoundedRectangle(cornerRadius: 3.5, style: .continuous)
                    .strokeBorder(isOn ? .clear : AppColors.borderStrong, lineWidth: 1)
            }
            .overlay {
                if isOn {
                    Image(systemName: "checkmark")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(AppColors.onActionPrimary)
                }
            }
            .frame(width: 14, height: 14)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        #endif
    }
}

/// The same checkbox idea on touch platforms: a 22 pt target with a clear
/// on/off state, since the native `.checkbox` toggle style is macOS-only.
struct TouchCheckboxStyle: ToggleStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        Button {
            withAnimation(reduceMotion ? nil : .easeOut(duration: 0.12)) {
                configuration.isOn.toggle()
            }
        } label: {
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .fill(configuration.isOn ? AppColors.actionPrimary : .clear)
                .overlay {
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .strokeBorder(
                            configuration.isOn ? .clear : AppColors.borderStrong,
                            lineWidth: 1.25
                        )
                }
                .overlay {
                    if configuration.isOn {
                        Image(systemName: "checkmark")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(AppColors.onActionPrimary)
                    }
                }
                .frame(width: 22, height: 22)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityValue(configuration.isOn ? String(localized: "common.on") : String(localized: "common.off"))
    }
}

extension ToggleStyle where Self == TouchCheckboxStyle {
    static var touchCheckbox: TouchCheckboxStyle { TouchCheckboxStyle() }
}

// MARK: - Empty state

struct EmptyState: View {
    let symbol: String
    let title: String
    let message: String
    var actionTitle: String?
    var action: (() -> Void)?

    var body: some View {
        VStack(spacing: AppStyle.Spacing.small) {
            ZStack {
                RoundedRectangle(cornerRadius: AppStyle.Radius.md, style: .continuous)
                    .strokeBorder(AppColors.borderStrong, style: StrokeStyle(lineWidth: 1.2, dash: [4, 3]))
                    .frame(width: 40, height: 40)
                Image(systemName: symbol)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(AppColors.textTertiary)
            }

            VStack(spacing: AppStyle.Spacing.xxxSmall) {
                Text(title)
                    .font(AppStyle.Typography.sectionTitle)
                Text(message)
                    .font(AppStyle.Typography.callout)
                    .foregroundStyle(AppColors.textSecondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .buttonStyle(.montra(.secondary, size: .small))
                    .padding(.top, AppStyle.Spacing.xxSmall)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, AppStyle.Spacing.xLarge)
        .padding(.horizontal, AppStyle.Spacing.large)
    }
}

// MARK: - Figures in Onest text

extension Text {
    /// Builds a `Text` from `string` with every figure in SF Rounded, so a
    /// sentence like "12 transactions · −1,240.50 Br" shows its numbers the way the
    /// rest of the app does. Onest itself has no digits.
    init(figures string: String, style: AppStyle.TextStyle) {
        let figure = #/[0-9](?:[.,:/\s]?[0-9])*(?:\s?(?:Br|€|\$|₮|₿|Ξ|%|USDC))?/#
        var text = Text(verbatim: "")
        var index = string.startIndex
        for match in string.matches(of: figure) {
            text = text + Text(verbatim: String(string[index..<match.range.lowerBound])).font(style)
            text = text + Text(verbatim: String(match.output)).font(style.numbers)
            index = match.range.upperBound
        }
        self = text + Text(verbatim: String(string[index...])).font(style)
    }
}

// MARK: - Flow layout

/// Wraps chips onto as many lines as they need, keeping their natural width.
struct FlowLayout: Layout {
    var spacing: CGFloat = AppStyle.Spacing.xSmall
    var lineSpacing: CGFloat = AppStyle.Spacing.xSmall

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0
        var y: CGFloat = 0
        var lineHeight: CGFloat = 0
        var widest: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0, x + spacing + size.width > maxWidth {
                x = 0
                y += lineHeight + lineSpacing
                lineHeight = 0
            }
            if x > 0 { x += spacing }
            x += size.width
            lineHeight = max(lineHeight, size.height)
            widest = max(widest, x)
        }
        return CGSize(width: min(widest, maxWidth), height: y + lineHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var lineHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > bounds.minX, x + spacing + size.width > bounds.maxX {
                x = bounds.minX
                y += lineHeight + lineSpacing
                lineHeight = 0
            }
            if x > bounds.minX { x += spacing }
            subview.place(at: CGPoint(x: x, y: y), anchor: .topLeading, proposal: ProposedViewSize(size))
            x += size.width
            lineHeight = max(lineHeight, size.height)
        }
    }
}

// MARK: - Animations shared across screens

enum AppMotion {
    /// Numbers rolling to a new value, as on the reference Overview.
    static let number = Animation.easeInOut(duration: 0.45)
    /// The balance bar's segments.
    static let bar = Animation.easeOut(duration: 0.6)
    /// A row appearing or disappearing.
    static let row = Animation.easeInOut(duration: 0.22)
    /// A whole page swapping.
    static let page = Animation.easeInOut(duration: 0.22)
    /// Route changes: the page crossfades while the shared header elements morph.
    static let route = Animation.spring(response: 0.4, dampingFraction: 0.92)
    /// Layout changes behind a toggle in Settings.
    static let layout = Animation.spring(response: 0.28, dampingFraction: 0.9)
    /// A row being added: a short spring, not a bounce.
    static let insert = Animation.spring(response: 0.34, dampingFraction: 0.86)
    /// The highlight fading off a freshly added row.
    static let highlight = Animation.easeOut(duration: 0.9)
    /// A hero hand-off: a decelerating move that arrives exactly on its target,
    /// so the element waiting there can take over without a jump. The curve is a
    /// plain ease-out rather than a snap: it covers about a quarter of the trip
    /// in the first tenth of the time, so the eye can follow the element the
    /// whole way instead of seeing it jump and then wait.
    static func heroFlight(duration: TimeInterval) -> Animation {
        .timingCurve(0.22, 0.61, 0.36, 1, duration: duration)
    }

    static let heroFlightDuration: TimeInterval = 0.56
}

/// The soft veil a just-added row wears for a moment.
struct NewRowVeil: View {
    let isNew: Bool
    let cornerRadius: CGFloat

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(AppColors.textPrimary.opacity(isNew ? 0.045 : 0))
            .animation(AppMotion.highlight, value: isNew)
            .allowsHitTesting(false)
    }
}
