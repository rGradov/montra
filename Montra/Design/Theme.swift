import AppKit
import CoreText
import SwiftUI

// MARK: - Colour tokens
//
// The palette uses warm graphite neutrals, a light primary action, and
// semantic status colors. Every token has a light and a dark value.

enum AppColors {
    // Text
    static let textPrimary = Color(light: 0x2E2D2B, dark: 0xECEAE6)
    static let textSecondary = Color(light: 0x64625E, dark: 0xA6A39D)
    static let textTertiary = Color(light: 0x85827C, dark: 0x807D78)

    // Surfaces
    static let surfaceBase = Color(light: 0xF6F5F3, dark: 0x171615)
    static let surfaceCard = Color(light: 0xFFFFFF, dark: 0x1E1D1C)
    static let surfaceRaised = Color(light: 0xFFFFFF, dark: 0x2B2A28)
    static let surfaceCardHover = Color(light: 0xF4F2EF, dark: 0x2A2927)

    // Fills
    static let fillSecondary = Color(light: 0xEFEDEA, dark: 0x282725)
    static let fillSecondaryHover = Color(light: 0xE8E6E2, dark: 0x2F2E2C)
    static let fillSecondaryPressed = Color(light: 0xDFDCD8, dark: 0x373533)

    // Borders
    static let borderSubtle = Color(light: 0xE6E3DF, dark: 0x302F2D)
    static let borderStrong = Color(light: 0xD5D2CD, dark: 0x3D3B38)

    // Actions
    static let actionPrimary = Color(nsColor: actionPrimaryNSColor)
    static let actionPrimaryHover = Color(light: 0x42403D, dark: 0xF6F4F1)
    static let actionPrimaryPressed = Color(light: 0x2A2927, dark: 0xD8D5D0)
    static let onActionPrimary = Color(light: 0xFFFFFF, dark: 0x171615)
    static let actionDestructive = Color(light: 0xD1312A, dark: 0xD9372D)
    static let actionDestructiveHover = Color(light: 0xBC2B25, dark: 0xE2453B)
    static let actionDestructivePressed = Color(light: 0xA92620, dark: 0xC4302A)
    static let accent = Color(light: 0x0A6ED1, dark: 0x4C9EEA)

    // Status
    static let statusSafeText = Color(light: 0x1F7A35, dark: 0x5FD36B)
    static let statusSafeFill = Color(light: 0xE6F4EA, dark: 0x1B2E22)
    static let statusCheckText = Color(light: 0x8A5300, dark: 0xF2B84B)
    static let statusCheckFill = Color(light: 0xFAEEDA, dark: 0x332910)
    static let statusDangerText = Color(light: 0xB4302A, dark: 0xF47468)
    static let statusDangerFill = Color(light: 0xFBE8E5, dark: 0x321B19)
    static let statusUnsureText = Color(light: 0x5A5853, dark: 0xA9A6A0)
    static let statusUnsureFill = Color(light: 0xEFEDEA, dark: 0x282725)

    // Overlays
    static let scrim = Color.black.opacity(0.38)

    /// Colours for the balance bar, account tiles and charts. Okabe–Ito, so any
    /// two neighbours stay distinct with any kind of colour vision.
    enum Chart {
        static let sky = Color(light: 0x56B4E9, dark: 0x6CC3F0)
        static let blue = Color(light: 0x0072B2, dark: 0x3A94D0)
        static let amber = Color(light: 0xE69F00, dark: 0xF0B020)
        static let vermillion = Color(light: 0xD55E00, dark: 0xE8772A)
        static let purple = Color(light: 0xCC79A7, dark: 0xDA93BA)
        static let teal = Color(light: 0x009E73, dark: 0x35B98D)
        static let green = Color(light: 0x2C8A3E, dark: 0x4FC261)

        // Deeper shades so a white glyph stays legible on the tile.
        static let skyTile = Color(light: 0x3399D3, dark: 0x3A9BD5)
        static let blueTile = Color(light: 0x0072B2, dark: 0x1E78BA)
        static let purpleTile = Color(light: 0xB35A8D, dark: 0xBE6C9C)
        static let tealTile = Color(light: 0x00856A, dark: 0x109C7C)

        /// Unallocated money on a bar, and "nothing here yet" tiles.
        static let freeSpace = Color(light: 0xDAD7D2, dark: 0x4E4B47)
        static let neutralTile = Color(light: 0x8C8983, dark: 0x6E6B66)
    }

    static var controlAccentNSColor: NSColor { actionPrimaryNSColor }

    private static let actionPrimaryNSColor = NSColor(light: 0x353431, dark: 0xECEAE6)
}

extension NSColor {
    static func hex(_ value: UInt32, alpha: CGFloat = 1) -> NSColor {
        let red = CGFloat((value >> 16) & 0xFF) / 255
        let green = CGFloat((value >> 8) & 0xFF) / 255
        let blue = CGFloat(value & 0xFF) / 255
        return NSColor(srgbRed: red, green: green, blue: blue, alpha: alpha)
    }

    convenience init(light: UInt32, dark: UInt32) {
        let light = NSColor.hex(light)
        let dark = NSColor.hex(dark)
        self.init(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light
        }
    }
}

extension Color {
    init(light: UInt32, dark: UInt32) {
        self.init(nsColor: NSColor(light: light, dark: dark))
    }
}

// MARK: - Metrics and type

enum AppStyle {
    enum Radius {
        static let xs: CGFloat = 4
        static let sm: CGFloat = 6
        static let md: CGFloat = 8
        /// Cards, list rows, sheets.
        static let lg: CGFloat = 14
        static let xl: CGFloat = 18
    }

    enum IconTile {
        static let size: CGFloat = 28
        static let cornerRadiusRatio: CGFloat = 0.26

        static func shape(size: CGFloat = size) -> RoundedRectangle {
            RoundedRectangle(cornerRadius: size * cornerRadiusRatio, style: .continuous)
        }
    }

    enum Control {
        static let height: CGFloat = 28
    }

    enum Spacing {
        static let xxxSmall: CGFloat = 2
        static let xxSmall: CGFloat = 4
        static let xxSmallPlus: CGFloat = 6
        static let xSmall: CGFloat = 8
        static let small: CGFloat = 12
        static let medium: CGFloat = 16
        static let large: CGFloat = 24
        static let xLarge: CGFloat = 32
    }

    enum Row {
        static let compactHeight: CGFloat = 36
        static let parentHeight: CGFloat = 44
        static let listRowMinHeight: CGFloat = 52
        static let listIconFrameSize: CGFloat = 28
        static let cardHorizontalPadding: CGFloat = 14
    }

    /// Layers that float above the page rather than sitting in it.
    enum Elevation {
        static let floatingColor = Color.black.opacity(0.28)
        static let floatingRadius: CGFloat = 18
        static let floatingY: CGFloat = 8
    }

    /// One step of the type scale: family, size, weight and (for Onest) tracking.
    struct TextStyle: Hashable {
        enum Family: Hashable {
            case onest
            case rounded
            case monospaced
        }

        let family: Family
        let size: CGFloat
        let weight: Font.Weight
        let tracking: CGFloat

        var font: Font {
            switch family {
            case .onest: AppFonts.onest(size: size, weight: weight)
            case .rounded: .system(size: size, weight: weight, design: .rounded)
            case .monospaced: .system(size: size, weight: weight, design: .monospaced)
            }
        }

        func weight(_ weight: Font.Weight) -> TextStyle {
            TextStyle(family: family, size: size, weight: weight, tracking: tracking)
        }

        /// SF Rounded at this style's size and weight: every figure in the app.
        var numbers: TextStyle {
            TextStyle(family: .rounded, size: size, weight: weight, tracking: 0)
        }

        func monospaced() -> TextStyle {
            TextStyle(family: .monospaced, size: size, weight: weight, tracking: 0)
        }
    }

    enum Typography {
        /// The welcome flow's wordmark, the size the reference uses there.
        static let displayLarge = TextStyle(family: .rounded, size: 56, weight: .bold, tracking: 0)
        /// A page's or card's focal figure, one step below the welcome wordmark.
        static let displayMedium = TextStyle(family: .rounded, size: 44, weight: .bold, tracking: 0)
        /// The biggest figure on a screen: the balance on a finished step.
        static let display = TextStyle(family: .rounded, size: 36, weight: .bold, tracking: 0)
        /// A page's hero figure.
        static let title = onest(26, .semibold, tracking: 0)
        static let pageTitle = onest(20, .semibold, tracking: 0)
        static let sectionTitle = onest(15, .semibold, tracking: 0.1)
        /// Row titles, buttons.
        static let headline = onest(13, .semibold, tracking: 0.15)
        static let body = onest(13, tracking: 0.15)
        static let rowTitle = onest(13, .medium, tracking: 0.15)
        /// Helper text under a row title, descriptions.
        static let callout = onest(12, tracking: 0.25)
        /// Dates, counts, secondary metadata.
        static let metadata = onest(11, tracking: 0.3)
        static let metadataEmphasis = onest(11, .medium, tracking: 0.3)
        /// Badges and count pills.
        static let micro = onest(10, .semibold, tracking: 0.4)

        private static func onest(_ size: CGFloat, _ weight: Font.Weight = .regular, tracking: CGFloat) -> TextStyle {
            TextStyle(family: .onest, size: size, weight: weight, tracking: tracking)
        }
    }
}

extension View {
    func font(_ style: AppStyle.TextStyle) -> some View {
        self.font(style.font).tracking(style.tracking)
    }
}

extension Text {
    func font(_ style: AppStyle.TextStyle) -> Text {
        self.font(style.font).tracking(style.tracking)
    }
}

// MARK: - Onest
//
// Onest is bundled with its ten digits removed (as in the reference), so a
// digit inside ordinary text falls back to the system face, and every figure in
// the UI uses SF Rounded through `TextStyle.numbers`.
//
// The font is registered from a copy in Application Support: CoreText reads the
// path again while the app runs, and a debug build can lose its bundle.

enum AppFonts {
    private static let resourceName = "OnestText"
    private static var registration: Bool?

    @discardableResult
    static func register() -> Bool {
        if let registration { return registration }
        let result = registerOnce()
        registration = result
        return result
    }

    private static func registerOnce() -> Bool {
        guard let bundled = bundleURL() else { return false }
        let url = stableCopy(of: bundled) ?? bundled
        var error: Unmanaged<CFError>?
        return CTFontManagerRegisterFontsForURL(url as CFURL, .process, &error)
    }

    private static func bundleURL() -> URL? {
        Bundle.main.url(forResource: resourceName, withExtension: "ttf")
            ?? Bundle.main.url(forResource: resourceName, withExtension: "ttf", subdirectory: "Fonts")
    }

    private static var stableFolder: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        return base.appendingPathComponent("Montra/Fonts", isDirectory: true)
    }

    private static func stableCopy(of bundled: URL) -> URL? {
        let copy = stableFolder.appendingPathComponent(bundled.lastPathComponent)
        do {
            let data = try Data(contentsOf: bundled)
            if (try? Data(contentsOf: copy)) != data {
                try FileManager.default.createDirectory(at: stableFolder, withIntermediateDirectories: true)
                try data.write(to: copy, options: .atomic)
            }
            return copy
        } catch {
            return nil
        }
    }

    static func onest(size: CGFloat, weight: Font.Weight = .regular) -> Font {
        register()
            ? Font.custom("Onest", size: size).weight(weight)
            : Font.system(size: size, weight: weight)
    }
}
