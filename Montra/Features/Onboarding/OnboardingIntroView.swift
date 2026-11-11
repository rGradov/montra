import AppKit
import AVFoundation
import ImageIO
import SwiftUI

// MARK: - Timeline
//
// The soundtrack is a short "story logo": it starts almost silent, swells, and
// peaks at 2.24 s. The intro is cut around that peak: the warm light gathers
// first, the mascot's own appearance animation starts a beat before the peak so
// Mori pops exactly on it, and the mascot then travels into the welcome icon
// once the music settles.
private enum OnboardingIntroTiming {
    /// The glow starts gathering while the track is still quiet.
    static let glowStarts: TimeInterval = 0.35
    /// The GIF's crescent frame fades in while the music swells.
    static let preludeStarts: TimeInterval = 1.15
    /// The mascot starts appearing here: its third frame crosses the 2.24 s peak.
    static let revealStarts: TimeInterval = 2.04
    static let captionAppears: TimeInterval = 3.20
    static let dismissStarts: TimeInterval = 4.35
    /// The mascot's trip into the welcome icon. The icon takes over as it lands.
    static let flight: TimeInterval = AppMotion.heroFlightDuration
    /// A quick trip when the person asked to skip.
    static let flightQuick: TimeInterval = 0.34
    /// The intro's own backdrop and copy getting out of the way.
    static let stepAside: TimeInterval = 0.45
    /// The copy goes sooner than the backdrop, so it is not still on screen
    /// while the mascot is already moving.
    static let copyAside: TimeInterval = 0.2
    /// The mascot dissolving into the icon that is focusing up underneath it.
    static let mascotFade: TimeInterval = 0.18
    static let mascotFadeQuick: TimeInterval = 0.12
    /// Music has fallen back to near silence by now, so the hand-off is clean.
    static let musicFadeOut: TimeInterval = 0.7
}

// MARK: - Intro

/// The first thing a new person sees: a warm glow gathers, the crescent prelude
/// wakes up, Mori pops in on the soundtrack's peak, and the mascot then flies
/// into the welcome icon as one continuous element instead of cross-fading.
/// Space, Escape or the corner button skips straight to it.
struct OnboardingIntroView: View {
    private let playsSound: Bool
    let onFinished: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.moriFlightPreview) private var previewProgress
    @State private var soundtrack = OnboardingSoundtrack()
    @State private var glow: Double = 0
    @State private var showsPrelude = false
    @State private var revealsMori = false
    @State private var showsCaption = false
    @State private var isDismissing = false
    @State private var isMuted = false
    @State private var didStart = false

    /// Where the welcome icon sits. The root view hands this down once the
    /// welcome step has reported its icon's frame.
    private let landing: MoriFlight?
    @State private var target: MoriFlight?
    /// The mascot's frame, so the flight can start from the exact spot the
    /// mascot is already drawn on.
    @State private var mascotFrame: CGRect = .zero
    @State private var isFlying = false
    @State private var flightProgress: CGFloat = 0
    @State private var flightOpacity: Double = 1

    private let mascotSize = OnboardingHero.mascotSize

    init(
        playsSound: Bool = true,
        landing: MoriFlight? = nil,
        onFinished: @escaping () -> Void
    ) {
        self.playsSound = playsSound
        self.landing = landing
        self.onFinished = onFinished
    }

    var body: some View {
        ZStack {
            backdrop
                .opacity(stepAsideOpacity)

            VStack(spacing: AppStyle.Spacing.medium + 4) {
                // The flight layer sits in the mascot's own slot, so the copy
                // below it cannot move while the mascot travels. Only the intro's
                // own layers step aside; the mascot that flies stays at full
                // strength until it lands.
                ZStack {
                    mascot
                        .opacity(showsFlight ? 0 : stepAsideOpacity)

                    if showsFlight, let target {
                        MoriFlightView(
                            start: mascotFrame,
                            flight: target,
                            progress: shownProgress,
                            glow: glow
                        )
                        .opacity(previewProgress == nil ? flightOpacity : 1)
                    }
                }

                caption
                    .opacity(copyAsideOpacity)
                    .animation(.easeOut(duration: OnboardingIntroTiming.copyAside), value: isDismissing)
            }
            .offset(y: -6)

            controls
                .opacity(copyAsideOpacity)
                .animation(.easeOut(duration: OnboardingIntroTiming.copyAside), value: isDismissing)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // Reduce Motion, and a run that never measured the icon, keep the plain
        // crossfade this screen used to have.
        .modifier(IntroCrossfade(isActive: isDismissing && !showsFlight))
        .onPreferenceChange(OnboardingIntroMascotKey.self) { frame in
            guard let frame, frame.width > 1 else { return }
            mascotFrame = frame
        }
        .onChange(of: landing, initial: true) { _, newValue in
            guard let newValue else { return }
            target = newValue
        }
        .background {
            // Keyboard access without a visible control taking focus.
            Group {
                Button(String(localized: "common.skip"), action: skip).keyboardShortcut(.space, modifiers: [])
                Button(String(localized: "common.skip"), action: skip).keyboardShortcut(.escape, modifiers: [])
            }
            .frame(width: 0, height: 0)
            .opacity(0)
            .accessibilityHidden(true)
        }
        .task {
            guard previewProgress != nil else {
                await runTimeline()
                return
            }
            // A frozen render shows the screen as the hand-off finds it: the
            // intro at rest, with the flight layer driven by the given progress.
            showsPrelude = true
            revealsMori = true
            showsCaption = true
            glow = 0.7
        }
        .onDisappear { soundtrack.stop() }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(String(localized: "common.meet_mori"))
    }

    // MARK: Hand-off state

    /// The backdrop steps aside so the mascot can carry the transition; a frozen
    /// render derives the same fade from its progress.
    private var stepAsideOpacity: Double {
        stepAsideOpacity(over: OnboardingIntroTiming.stepAside)
    }

    private var copyAsideOpacity: Double {
        stepAsideOpacity(over: OnboardingIntroTiming.copyAside)
    }

    private func stepAsideOpacity(over duration: TimeInterval) -> Double {
        guard let previewProgress else { return isDismissing ? 0 : 1 }
        let elapsed = previewProgress * OnboardingIntroTiming.flight
        return 1 - min(1, elapsed / duration)
    }

    private var showsFlight: Bool {
        previewProgress != nil || isFlying
    }

    private var shownProgress: CGFloat {
        previewProgress ?? flightProgress
    }

    // MARK: Visuals

    private var backdrop: some View {
        ZStack {
            AppColors.surfaceBase
                .ignoresSafeArea()

            // The glow is wider than the window. A GeometryReader takes the size
            // it is offered and lets the glow overflow it, so the backdrop cannot
            // stretch the intro's layout: if it did, the intro would sit off the
            // window's origin and every coordinate the mascot flies to would be
            // shifted with it.
            GeometryReader { proxy in
                glowField
                    .position(x: proxy.size.width / 2, y: proxy.size.height / 2)
                IntroSparkles()
                    .frame(width: 620, height: 540)
                    .opacity(glow)
                    .position(x: proxy.size.width / 2, y: proxy.size.height / 2)
            }
            .allowsHitTesting(false)
        }
    }

    private var mascot: some View {
        MoriRevealView(size: mascotSize, isPrelude: showsPrelude, isRevealing: revealsMori, isPinned: showsFlight)
            .opacity(revealsMori ? 1 : (showsPrelude ? 0.62 : 0))
            .scaleEffect(revealsMori ? 1 : (showsPrelude ? 0.92 : 0.965))
            .blur(radius: revealsMori ? 0 : (showsPrelude ? 1.5 : 8))
            .shadow(color: OnboardingIntroPalette.warm.opacity(glow * 0.32), radius: 30)
            .accessibilityLabel(String(localized: "common.mori"))
            .accessibilityHidden(!revealsMori)
    }

    private var glowField: some View {
        RadialGradient(
            stops: [
                .init(color: OnboardingIntroPalette.warm.opacity(0.74 * glow), location: 0),
                .init(color: OnboardingIntroPalette.warm.opacity(0.30 * glow), location: 0.38),
                .init(color: OnboardingIntroPalette.lavender.opacity(0.10 * glow), location: 0.70),
                .init(color: .clear, location: 1),
            ],
            center: .center,
            startRadius: 12,
            endRadius: 380
        )
        .frame(width: 880, height: 880)
        .blur(radius: 52)
        .scaleEffect(0.72 + 0.28 * glow)
    }

    private var caption: some View {
        VStack(spacing: AppStyle.Spacing.xxSmallPlus) {
            Text(String(localized: "onboarding.intro.hi_im_mori"))
                .font(AppStyle.Typography.title)
                .foregroundStyle(AppColors.textPrimary)
            Text(String(localized: "onboarding.intro.ill_show_you_around_in"))
                .font(AppStyle.Typography.body)
                .foregroundStyle(AppColors.textSecondary)
        }
        .multilineTextAlignment(.center)
        .opacity(showsCaption ? 1 : 0)
        .offset(y: showsCaption ? 0 : 10)
        .blur(radius: showsCaption ? 0 : 5)
        .accessibilityElement(children: .combine)
        .accessibilityHidden(!showsCaption)
    }

    private var controls: some View {
        VStack {
            Spacer()
            HStack(alignment: .center) {
                Button(action: toggleMute) {
                    Image(systemName: isMuted ? "speaker.slash.fill" : "speaker.wave.1.fill")
                        .font(.system(size: 11, weight: .semibold))
                        .frame(width: 24, height: 24)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(AppColors.textTertiary)
                .pointingHandOnHover()
                .help(isMuted ? String(localized: "onboarding.intro.turn_sound_on") : String(localized: "onboarding.intro.turn_sound_off"))
                .accessibilityLabel(isMuted ? String(localized: "onboarding.intro.turn_sound_on") : String(localized: "onboarding.intro.turn_sound_off"))

                Spacer()

                Button(String(localized: "common.skip"), action: skip)
                    .buttonStyle(.plain)
                    .font(AppStyle.Typography.metadata)
                    .foregroundStyle(AppColors.textSecondary)
                    .pointingHandOnHover()
                    .accessibilityLabel(String(localized: "common.skip_onboarding"))
            }
            .padding(.horizontal, AppStyle.Spacing.xLarge)
            .padding(.bottom, AppStyle.Spacing.large)
        }
    }

    // MARK: Timeline

    @MainActor
    private func runTimeline() async {
        guard !didStart else { return }
        didStart = true
        if playsSound { soundtrack.start() }

        await pause(OnboardingIntroTiming.glowStarts)
        withAnimation(.easeIn(duration: 1.2)) { glow = 0.55 }

        // The crescent from the GIF's first frame is the prelude: the magic
        // gathers there before Mori actually appears.
        await pause(OnboardingIntroTiming.preludeStarts - OnboardingIntroTiming.glowStarts)
        withAnimation(.easeOut(duration: 0.9)) { showsPrelude = true }
        withAnimation(.easeInOut(duration: 0.9)) { glow = 0.80 }

        // A beat before the peak, so the mascot's third frame lands on it.
        await pause(OnboardingIntroTiming.revealStarts - OnboardingIntroTiming.preludeStarts)
        withAnimation(.easeOut(duration: 0.22)) { revealsMori = true }
        withAnimation(.easeOut(duration: 0.5)) { glow = 1 }

        await pause(0.62)
        withAnimation(.easeInOut(duration: 1.8)) { glow = 0.70 }

        await pause(OnboardingIntroTiming.captionAppears - 2.66)
        withAnimation(.easeOut(duration: 0.7)) { showsCaption = true }

        await pause(OnboardingIntroTiming.dismissStarts - OnboardingIntroTiming.captionAppears)
        dismiss()
    }

    @MainActor
    private func pause(_ duration: TimeInterval) async {
        try? await Task.sleep(for: .seconds(duration))
        if Task.isCancelled { return }
    }

    private func dismiss() {
        handOff(quick: false)
    }

    /// Gives up the screen. When both ends of the trip are known the mascot flies
    /// into the welcome icon and the icon takes over as it lands, so nothing
    /// cross-fades; otherwise the screen fades away as it always did.
    private func handOff(quick: Bool) {
        guard !isDismissing else { return }
        if playsSound {
            let fade = quick ? 0.32 : OnboardingIntroTiming.musicFadeOut
            soundtrack.fadeOutAndStop(after: fade)
        }

        guard target != nil, !reduceMotion, mascotFrame.width > 1 else {
            withAnimation(.easeInOut(duration: OnboardingIntroTiming.musicFadeOut)) { isDismissing = true }
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(OnboardingIntroTiming.musicFadeOut + 0.1))
                onFinished()
            }
            return
        }

        let duration = quick ? OnboardingIntroTiming.flightQuick : OnboardingIntroTiming.flight
        let fade = quick ? OnboardingIntroTiming.mascotFadeQuick : OnboardingIntroTiming.mascotFade

        // The backdrop and the copy step aside while the mascot, and only the
        // mascot, carries the transition.
        withAnimation(.easeInOut(duration: quick ? 0.3 : OnboardingIntroTiming.stepAside)) { isDismissing = true }
        isFlying = true

        Task { @MainActor in
            // Mount the mascot on the frame it is already on, then let it go.
            try? await Task.sleep(for: .seconds(0.02))
            withAnimation(AppMotion.heroFlight(duration: duration)) { flightProgress = 1 }

            try? await Task.sleep(for: .seconds(duration))
            // The mascot has landed on the icon. It dissolves while the icon is
            // still out of focus, so the painted mascot takes its place unseen.
            withAnimation(.easeOut(duration: fade)) { flightOpacity = 0 }

            try? await Task.sleep(for: .seconds(fade + 0.02))
            onFinished()
        }
    }

    private func skip() {
        guard !isDismissing else { return }
        handOff(quick: true)
    }

    private func toggleMute() {
        guard playsSound, !isDismissing else { return }
        isMuted.toggle()
        soundtrack.setMuted(isMuted)
    }
}

/// The hand-off this screen used before the mascot flew: the whole intro fades
/// and softens away. Kept for Reduce Motion and for runs with no measured icon.
private struct IntroCrossfade: ViewModifier {
    let isActive: Bool

    func body(content: Content) -> some View {
        content
            .opacity(isActive ? 0 : 1)
            .blur(radius: isActive ? 7 : 0)
            .scaleEffect(isActive ? 1.015 : 1)
    }
}

// MARK: - Mascot

/// Plays the 16-frame GIF at its native 25 fps, then settles on the crisp
/// mascot still and lets it float, so a 0.64 s pop does not end abruptly.
private struct MoriRevealView: View {
    let size: CGFloat
    let isPrelude: Bool
    let isRevealing: Bool
    /// Held still while the mascot is in flight, so it leaves from and lands on
    /// exactly the frame the flight measured.
    var isPinned = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.moriFlightPreview) private var previewProgress
    @State private var frameImage: NSImage?
    @State private var showsStill = false
    @State private var floats = false
    @State private var isPlaying = false

    var body: some View {
        ZStack {
            if let frameImage {
                Image(nsImage: frameImage)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
                    .opacity(showsStill ? 0 : 1)
            }

            MoriStillLayer(size: size)
                .opacity(showsStill ? 1 : 0)
        }
        .frame(width: size, height: size)
        // The flight has to start from where the mascot is drawn, float included.
        .background {
            GeometryReader { proxy in
                Color.clear.preference(
                    key: OnboardingIntroMascotKey.self,
                    value: proxy.frame(in: .named(OnboardingHero.coordinateSpace))
                        .offsetBy(dx: 0, dy: floatOffset)
                )
            }
        }
        .offset(y: floatOffset)
        // Decode the GIF up front, while the screen is still empty: decoding at
        // the peak would land a hitch exactly on the music.
        .task {
            _ = MoriArtwork.stillImage()
            frameImage = MoriArtwork.frames().first?.image
        }
        .task(id: isRevealing) {
            guard isRevealing else { return }
            await play()
        }
    }

    private func play() async {
        guard !isPlaying else { return }
        isPlaying = true

        // A render with no real time to spare wants the mascot at rest, not
        // caught mid-dissolve from the GIF to the still.
        if rendersMascotAtRest {
            showsStill = true
            return
        }

        let frames = MoriArtwork.frames()

        guard !frames.isEmpty else {
            withAnimation(.easeOut(duration: 0.5)) { showsStill = true }
            startFloating()
            return
        }

        for frame in frames {
            guard !Task.isCancelled else { return }
            frameImage = frame.image
            try? await Task.sleep(for: .seconds(frame.duration))
        }
        guard !Task.isCancelled else { return }

        withAnimation(.easeInOut(duration: 0.45)) { showsStill = true }
        startFloating()
    }

    /// The QA renders block the main thread to take their shots, which starves
    /// the GIF, so they show the mascot at rest instead of half-way through its
    /// appearance. The app itself never takes this path.
    private var rendersMascotAtRest: Bool {
        previewProgress != nil || CommandLine.arguments.contains("-intro-snapshots")
    }

    private var floatOffset: CGFloat {
        floats && !isPinned ? -4 : 0
    }

    private func startFloating() {
        guard !reduceMotion, !isPinned else { return }
        withAnimation(.easeInOut(duration: 3.4).repeatForever(autoreverses: true)) {
            floats = true
        }
    }
}

// MARK: - Sparkles

private struct IntroSparkles: View {
    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let height = proxy.size.height

            ZStack {
                IntroSparkle(size: 9, delay: 0.95, tint: OnboardingIntroPalette.warm)
                    .position(x: width * 0.19, y: height * 0.30)
                IntroSparkle(size: 13, delay: 1.10, tint: OnboardingIntroPalette.warm)
                    .position(x: width * 0.80, y: height * 0.17)
                IntroSparkle(size: 7, delay: 1.30, tint: OnboardingIntroPalette.lavender)
                    .position(x: width * 0.86, y: height * 0.64)
                IntroSparkle(size: 10, delay: 1.45, tint: OnboardingIntroPalette.warm)
                    .position(x: width * 0.12, y: height * 0.69)
                IntroSparkle(size: 6, delay: 1.65, tint: OnboardingIntroPalette.lavender)
                    .position(x: width * 0.30, y: height * 0.07)
                IntroSparkle(size: 8, delay: 1.85, tint: OnboardingIntroPalette.warm)
                    .position(x: width * 0.66, y: height * 0.93)
            }
        }
    }
}

private struct IntroSparkle: View {
    let size: CGFloat
    let delay: Double
    let tint: Color

    @State private var appeared = false
    @State private var twinkles = false

    var body: some View {
        FourPointStar()
            .fill(tint)
            .frame(width: size, height: size)
            .opacity(appeared ? (twinkles ? 0.45 : 0.95) : 0)
            .scaleEffect(twinkles ? 0.82 : 1)
            .task {
                try? await Task.sleep(for: .seconds(delay))
                withAnimation(.easeOut(duration: 0.6)) { appeared = true }
                try? await Task.sleep(for: .seconds(0.6))
                guard !Task.isCancelled else { return }
                withAnimation(.easeInOut(duration: 2.1).repeatForever(autoreverses: true)) {
                    twinkles = true
                }
            }
    }
}

private struct FourPointStar: Shape {
    func path(in rect: CGRect) -> Path {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let halfWidth = rect.width / 2
        let halfHeight = rect.height / 2
        let pull = 0.16

        var path = Path()
        path.move(to: CGPoint(x: center.x, y: rect.minY))
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX, y: center.y),
            control: CGPoint(x: center.x + halfWidth * pull, y: center.y - halfHeight * pull)
        )
        path.addQuadCurve(
            to: CGPoint(x: center.x, y: rect.maxY),
            control: CGPoint(x: center.x + halfWidth * pull, y: center.y + halfHeight * pull)
        )
        path.addQuadCurve(
            to: CGPoint(x: rect.minX, y: center.y),
            control: CGPoint(x: center.x - halfWidth * pull, y: center.y + halfHeight * pull)
        )
        path.addQuadCurve(
            to: CGPoint(x: center.x, y: rect.minY),
            control: CGPoint(x: center.x - halfWidth * pull, y: center.y - halfHeight * pull)
        )
        path.closeSubpath()
        return path
    }
}

// MARK: - Sound

/// Owns the intro track. Starts from silence, fades up under the animation and
/// fades out while the mascot travels to the welcome icon. Muting only affects
/// this player.
final class OnboardingSoundtrack {
    private var player: AVAudioPlayer?
    private var stopTask: Task<Void, Never>?
    private var isMuted = false

    private let targetVolume: Float = 0.95

    func start() {
        guard player == nil else { return }
        // Snapshot and animation runs render the intro without sound.
        guard !CommandLine.arguments.contains("-intro-snapshots"),
              !CommandLine.arguments.contains("-animate-onboarding-intro") else { return }
        guard let url = Bundle.main.url(forResource: "OnboardingTheme", withExtension: "wav") else { return }
        guard let player = try? AVAudioPlayer(contentsOf: url) else { return }

        self.player = player
        player.volume = 0
        player.prepareToPlay()
        player.play()
        player.setVolume(isMuted ? 0 : targetVolume, fadeDuration: 0.9)
    }

    func setMuted(_ muted: Bool) {
        isMuted = muted
        player?.setVolume(muted ? 0 : targetVolume, fadeDuration: 0.3)
    }

    func fadeOutAndStop(after duration: TimeInterval) {
        guard let player else { return }
        stopTask?.cancel()
        player.setVolume(0, fadeDuration: duration)

        stopTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(duration + 0.1))
            guard !Task.isCancelled else { return }
            self?.player?.stop()
            self?.player = nil
        }
    }

    func stop() {
        stopTask?.cancel()
        stopTask = nil
        player?.stop()
        player = nil
    }

    deinit {
        player?.stop()
    }
}
