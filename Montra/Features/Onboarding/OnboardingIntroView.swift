import AppKit
import AVFoundation
import ImageIO
import SwiftUI

// MARK: - Timeline
//
// The soundtrack is a short "story logo": it starts almost silent, swells, and
// peaks at 2.24 s. The intro is cut around that peak: the warm light gathers
// first, the mascot's own appearance animation starts a beat before the peak so
// Mori pops exactly on it, and the welcome page follows once the music settles.
private enum OnboardingIntroTiming {
    /// The glow starts gathering while the track is still quiet.
    static let glowStarts: TimeInterval = 0.35
    /// The GIF's crescent frame fades in while the music swells.
    static let preludeStarts: TimeInterval = 1.15
    /// The mascot starts appearing here: its third frame crosses the 2.24 s peak.
    static let revealStarts: TimeInterval = 2.04
    static let captionAppears: TimeInterval = 3.20
    static let dismissStarts: TimeInterval = 4.35
    /// Music has fallen back to near silence by now, so the crossfade is clean.
    static let musicFadeOut: TimeInterval = 0.7
}

// MARK: - Intro

/// The first thing a new person sees: a warm glow gathers, the crescent prelude
/// wakes up, Mori pops in on the soundtrack's peak, and the welcome step fades
/// up underneath. Space, Escape or the corner button skips straight to it.
struct OnboardingIntroView: View {
    private let playsSound: Bool
    let onFinished: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var soundtrack = OnboardingSoundtrack()
    @State private var glow: Double = 0
    @State private var showsPrelude = false
    @State private var revealsMori = false
    @State private var showsCaption = false
    @State private var isDismissing = false
    @State private var isMuted = false
    @State private var didStart = false

    private let mascotSize: CGFloat = 320

    init(playsSound: Bool = true, onFinished: @escaping () -> Void) {
        self.playsSound = playsSound
        self.onFinished = onFinished
    }

    var body: some View {
        ZStack {
            AppColors.surfaceBase
                .ignoresSafeArea()

            glowField
                .allowsHitTesting(false)

            IntroSparkles()
                .frame(width: 620, height: 540)
                .opacity(glow)
                .allowsHitTesting(false)

            VStack(spacing: AppStyle.Spacing.medium + 4) {
                MoriRevealView(size: mascotSize, isPrelude: showsPrelude, isRevealing: revealsMori)
                    .opacity(revealsMori ? 1 : (showsPrelude ? 0.62 : 0))
                    .scaleEffect(revealsMori ? 1 : (showsPrelude ? 0.92 : 0.965))
                    .blur(radius: revealsMori ? 0 : (showsPrelude ? 1.5 : 8))
                    .shadow(color: OnboardingIntroPalette.warm.opacity(glow * 0.32), radius: 30)
                    .accessibilityLabel(String(localized: "common.mori"))
                    .accessibilityHidden(!revealsMori)

                caption
            }
            .offset(y: -6)

            controls
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AppColors.surfaceBase)
        .opacity(isDismissing ? 0 : 1)
        .blur(radius: isDismissing ? 7 : 0)
        .scaleEffect(isDismissing ? 1.015 : 1)
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
        .task { await runTimeline() }
        .onDisappear { soundtrack.stop() }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(String(localized: "common.meet_mori"))
    }

    // MARK: Visuals

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
        guard !isDismissing else { return }
        withAnimation(.easeInOut(duration: OnboardingIntroTiming.musicFadeOut)) { isDismissing = true }
        if playsSound { soundtrack.fadeOutAndStop(after: OnboardingIntroTiming.musicFadeOut) }

        Task { @MainActor in
            try? await Task.sleep(for: .seconds(OnboardingIntroTiming.musicFadeOut + 0.1))
            onFinished()
        }
    }

    private func skip() {
        guard !isDismissing else { return }
        withAnimation(.easeOut(duration: 0.34)) { isDismissing = true }
        if playsSound { soundtrack.fadeOutAndStop(after: 0.32) }

        Task { @MainActor in
            try? await Task.sleep(for: .seconds(0.34))
            onFinished()
        }
    }

    private func toggleMute() {
        guard playsSound, !isDismissing else { return }
        isMuted.toggle()
        soundtrack.setMuted(isMuted)
    }
}

// MARK: - Mascot

/// Plays the 16-frame GIF at its native 25 fps, then settles on the crisp
/// mascot still and lets it float, so a 0.64 s pop does not end abruptly.
private struct MoriRevealView: View {
    let size: CGFloat
    let isPrelude: Bool
    let isRevealing: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var frameImage: NSImage?
    @State private var stillImage: NSImage?
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

            if let stillImage {
                Image(nsImage: stillImage)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
                    // Frame 16 of the GIF and the still are cropped slightly
                    // differently; nudge the still so the dissolve is seamless.
                    .scaleEffect(1.065)
                    .offset(x: size * 0.019, y: -size * 0.003)
                    .opacity(showsStill ? 1 : 0)
            }
        }
        .frame(width: size, height: size)
        .offset(y: floats ? -4 : 0)
        // Decode the GIF up front, while the screen is still empty: decoding at
        // the peak would land a hitch exactly on the music.
        .task {
            stillImage = MoriArtwork.stillImage()
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

        stillImage = MoriArtwork.stillImage()
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

    private func startFloating() {
        guard !reduceMotion else { return }
        withAnimation(.easeInOut(duration: 3.4).repeatForever(autoreverses: true)) {
            floats = true
        }
    }
}

private enum MoriArtwork {
    private static var cachedFrames: [MoriFrame]?
    private static var cachedStill: NSImage?

    static func frames() -> [MoriFrame] {
        if let cachedFrames { return cachedFrames }
        guard let url = Bundle.main.url(forResource: "MoriAppearance", withExtension: "gif"),
              let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return [] }

        let frames: [MoriFrame] = (0..<CGImageSourceGetCount(source)).compactMap { index in
            guard let cgImage = CGImageSourceCreateImageAtIndex(source, index, nil) else { return nil }
            let image = NSImage(
                cgImage: cgImage,
                size: NSSize(width: cgImage.width, height: cgImage.height)
            )

            var duration: TimeInterval = 0.04
            if let properties = CGImageSourceCopyPropertiesAtIndex(source, index, nil) as? [CFString: Any],
               let gif = properties[kCGImagePropertyGIFDictionary] as? [CFString: Any] {
                if let value = gif[kCGImagePropertyGIFUnclampedDelayTime] as? Double, value > 0.01 {
                    duration = value
                } else if let value = gif[kCGImagePropertyGIFDelayTime] as? Double, value > 0.01 {
                    duration = value
                }
            }
            return MoriFrame(image: image, duration: duration)
        }
        cachedFrames = frames
        return frames
    }

    static func stillImage() -> NSImage? {
        if let cachedStill { return cachedStill }
        guard let url = Bundle.main.url(forResource: "MoriMascot", withExtension: "png") else { return nil }
        let image = NSImage(contentsOf: url)
        cachedStill = image
        return image
    }
}

private struct MoriFrame {
    let image: NSImage
    let duration: TimeInterval
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

private enum OnboardingIntroPalette {
    static let warm = Color(red: 1.0, green: 0.80, blue: 0.42)
    static let lavender = Color(red: 0.76, green: 0.70, blue: 0.95)
}

// MARK: - Sound

/// Owns the intro track. Starts from silence, fades up under the animation and
/// fades out while the welcome step appears. Muting only affects this player.
final class OnboardingSoundtrack {
    private var player: AVAudioPlayer?
    private var stopTask: Task<Void, Never>?
    private var isMuted = false

    private let targetVolume: Float = 0.95

    func start() {
        guard player == nil else { return }
        // Snapshot runs render the intro without sound.
        guard !CommandLine.arguments.contains("-intro-snapshots") else { return }
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
