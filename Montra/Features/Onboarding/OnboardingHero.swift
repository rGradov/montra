import AppKit
import ImageIO
import SwiftUI

/// The onboarding hand-offs: the mascot flying into the welcome icon, and the
/// first account flying from the "done" screen into its sidebar row. Both move a
/// single element between two screens instead of cross-fading the screens, so
/// the change reads as one continuous thing.
enum OnboardingHero {
    static let coordinateSpace = "onboarding-hero"

    /// The mascot's box on the intro. The flight starts from it and shrinks.
    static let mascotSize: CGFloat = 320

    /// Where Mori has to come to rest so that it lies exactly on the mascot
    /// painted inside the welcome icon. Landing on that spot is what makes the
    /// hand-off invisible: the icon focuses up underneath the mascot that is
    /// already there, instead of two elements cross-fading.
    static func flight(toArtwork artwork: CGRect) -> MoriFlight? {
        guard artwork.width > 1, artwork.height > 1 else { return nil }

        let box = mascotSize
        let spanOnIcon = MoriArtworkMetrics.artworkEyeSpan * artwork.width
        let scale = spanOnIcon
            / (MoriArtworkMetrics.stillEyeSpan * box * MoriArtworkMetrics.stillEnlargement)
        guard scale > 0 else { return nil }

        let paintedMascot = CGPoint(
            x: artwork.minX + MoriArtworkMetrics.artworkEyeMid.x * artwork.width,
            y: artwork.minY + MoriArtworkMetrics.artworkEyeMid.y * artwork.height
        )
        // The box is placed by its centre, so the mascot inside it has to be
        // measured from that centre, not from the box's top-left corner.
        let eyeMid = MoriArtworkMetrics.stillEyeMidInBox
        return MoriFlight(
            center: CGPoint(
                x: paintedMascot.x - (eyeMid.x - 0.5) * box * scale,
                y: paintedMascot.y - (eyeMid.y - 0.5) * box * scale
            ),
            scale: scale
        )
    }
}

/// Where the mascot comes to rest on the welcome icon, in the hero space.
struct MoriFlight: Equatable {
    let center: CGPoint
    let scale: CGFloat
}

/// The mascot is located inside each PNG by its eyes rather than by the layout
/// box: the two files are cropped differently, and matching the artwork is what
/// keeps the landing seamless. Re-measure these if either PNG is replaced.
enum MoriArtworkMetrics {
    /// `MoriMascot.png`, 700 pt: pupils' midpoint and distance, 0...1 of the file.
    static let stillEyeMid = CGPoint(x: 0.58366, y: 0.54283)
    static let stillEyeSpan: CGFloat = 0.14906

    /// `artwork.png`, 1254 pt: the mascot painted inside the app icon.
    static let artworkEyeMid = CGPoint(x: 0.55767, y: 0.53014)
    static let artworkEyeSpan: CGFloat = 0.11510

    /// The intro enlarges the still slightly: frame 16 of the GIF and the still
    /// are cropped a little differently, and the dissolve between them is only
    /// seamless at this scale.
    static let stillEnlargement: CGFloat = 1.065
    /// Offsets as a fraction of the mascot box, applied after `stillEnlargement`.
    static let stillOffset = CGSize(width: 0.019, height: -0.003)

    /// Where the eyes sit inside the intro's mascot box once both modifiers have
    /// been applied, 0...1 of the box.
    static let stillEyeMidInBox = CGPoint(
        x: 0.5 + (stillEyeMid.x - 0.5) * stillEnlargement + stillOffset.width,
        y: 0.5 + (stillEyeMid.y - 0.5) * stillEnlargement + stillOffset.height
    )
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

/// The mascot's frame on the intro, so the flight can start from exactly where
/// the mascot already is.
struct OnboardingIntroMascotKey: PreferenceKey {
    static var defaultValue: CGRect?

    static func reduce(value: inout CGRect?, nextValue: () -> CGRect?) {
        value = nextValue() ?? value
    }
}

/// The welcome icon's frame, so the flight knows where to land.
struct OnboardingWelcomeArtworkKey: PreferenceKey {
    static var defaultValue: CGRect?

    static func reduce(value: inout CGRect?, nextValue: () -> CGRect?) {
        value = nextValue() ?? value
    }
}

/// While the mascot is still on its way, the welcome icon waits out of focus, so
/// the flying mascot is the only Mori on screen. It focuses up as the mascot
/// lands, which is what reads as one continuous element.
private struct WelcomeArtworkWaitsForMoriKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    var welcomeArtworkWaitsForMori: Bool {
        get { self[WelcomeArtworkWaitsForMoriKey.self] }
        set { self[WelcomeArtworkWaitsForMoriKey.self] = newValue }
    }
}

/// Debug only: freezes the hand-off at a given point so a capture can render it
/// step by step. The app never sets this, so the shipped motion is untouched.
private struct MoriFlightPreviewKey: EnvironmentKey {
    static let defaultValue: CGFloat? = nil
}

extension EnvironmentValues {
    var moriFlightPreview: CGFloat? {
        get { self[MoriFlightPreviewKey.self] }
        set { self[MoriFlightPreviewKey.self] = newValue }
    }
}

/// The still mascot, drawn exactly as the intro leaves it, so the flight can
/// pick it up and put it down again without a seam.
struct MoriStillLayer: View {
    let size: CGFloat

    var body: some View {
        Group {
            if let image = MoriArtwork.stillImage() {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
                    .scaleEffect(MoriArtworkMetrics.stillEnlargement)
                    .offset(
                        x: size * MoriArtworkMetrics.stillOffset.width,
                        y: size * MoriArtworkMetrics.stillOffset.height
                    )
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

/// Mori in flight: the layers the intro draws, sitting in the mascot's own slot
/// and then moving and shrinking onto the welcome icon.
///
/// The trip is a plain offset from that slot rather than an absolute position:
/// an offset resolves against the mascot's own frame, so wherever the intro
/// happens to sit, the landing is the same place the icon is.
struct MoriFlightView: View {
    /// Where the mascot starts, in the view the flight is measured in.
    let start: CGRect
    let flight: MoriFlight
    /// 0 at take-off, 1 when Mori covers the mascot painted inside the icon.
    let progress: CGFloat
    /// The intro's current glow, so the shadow is unchanged at take-off.
    var glow: Double = 0

    var body: some View {
        MoriStillLayer(size: start.width > 1 ? start.width : OnboardingHero.mascotSize)
            .scaleEffect(scale)
            .shadow(color: OnboardingIntroPalette.warm.opacity(shadowOpacity), radius: 30)
            .offset(x: delta.width * progress, y: delta.height * progress)
    }

    private var delta: CGSize {
        CGSize(
            width: flight.center.x - start.midX,
            height: flight.center.y - start.midY
        )
    }

    private var scale: CGFloat {
        1 + (flight.scale - 1) * progress
    }

    /// The icon's own glow is painted into the artwork, so the intro's drops away
    /// as the mascot arrives.
    private var shadowOpacity: Double {
        max(0, glow * 0.32) * Double(1 - progress)
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

// MARK: - Mascot artwork

enum MoriArtwork {
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

struct MoriFrame {
    let image: NSImage
    let duration: TimeInterval
}

enum OnboardingIntroPalette {
    static let warm = Color(red: 1.0, green: 0.80, blue: 0.42)
    static let lavender = Color(red: 0.76, green: 0.70, blue: 0.95)
}
