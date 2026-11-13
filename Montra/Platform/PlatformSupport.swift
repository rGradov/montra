import SwiftUI

#if os(macOS)
import AppKit
typealias PlatformImage = NSImage
#else
import UIKit
typealias PlatformImage = UIImage
#endif

/// Small, explicit answers to "which platform is this?" for the few places
/// where the shared UI must branch. Keep this list short: screens should be
/// shared, and only genuinely platform-shaped behavior belongs here.
enum AppPlatform {
    static var isMac: Bool {
        #if os(macOS)
        true
        #else
        false
        #endif
    }

    static var isPhone: Bool {
        #if os(iOS)
        UIDevice.current.userInterfaceIdiom == .phone
        #else
        false
        #endif
    }

    static var isPad: Bool {
        #if os(iOS)
        UIDevice.current.userInterfaceIdiom == .pad
        #else
        false
        #endif
    }

    /// The local HTTP server and the MCP bridge are macOS features: iOS cannot
    /// expose a useful loopback server to other apps. The code stays compiled
    /// and the macOS behavior is untouched.
    static var supportsLocalIntegration: Bool { isMac }

    /// The Touch Bar only exists on the Mac.
    static var supportsTouchBar: Bool { isMac }

    /// Window chrome (hidden title bar, fixed width) is a macOS concept.
    static var supportsWindowChrome: Bool { isMac }
}

// MARK: - Colours

#if os(macOS)
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
#else
extension UIColor {
    static func hex(_ value: UInt32, alpha: CGFloat = 1) -> UIColor {
        let red = CGFloat((value >> 16) & 0xFF) / 255
        let green = CGFloat((value >> 8) & 0xFF) / 255
        let blue = CGFloat(value & 0xFF) / 255
        return UIColor(red: red, green: green, blue: blue, alpha: alpha)
    }
}
#endif

extension Color {
    /// A token colour that follows the system appearance on every platform.
    init(light: UInt32, dark: UInt32) {
        #if os(macOS)
        self.init(nsColor: NSColor(light: light, dark: dark))
        #else
        self.init(uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark ? .hex(dark) : .hex(light)
        })
        #endif
    }
}

// MARK: - Images

enum AppAssets {
    /// `nil` when the asset is not in the catalog, so callers can fall back to
    /// an SF Symbol exactly as they do on the Mac.
    static func image(named name: String) -> PlatformImage? {
        #if os(macOS)
        NSImage(named: name)
        #else
        UIImage(named: name)
        #endif
    }

    static func image(contentsOf url: URL) -> PlatformImage? {
        #if os(macOS)
        NSImage(contentsOf: url)
        #else
        UIImage(contentsOfFile: url.path)
        #endif
    }

    static func image(cgImage: CGImage) -> PlatformImage {
        #if os(macOS)
        NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
        #else
        UIImage(cgImage: cgImage)
        #endif
    }
}

extension Image {
    init(platformImage: PlatformImage) {
        #if os(macOS)
        self.init(nsImage: platformImage)
        #else
        self.init(uiImage: platformImage)
        #endif
    }
}

// MARK: - macOS affordances, quietly absent on iOS

extension View {
    /// Tooltips are a pointer affordance. On iOS the same information is already
    /// in the accessibility label, so this becomes a no-op instead of leaking a
    /// macOS-only modifier into the shared screens.
    @ViewBuilder
    func platformHelp(_ text: String) -> some View {
        #if os(macOS)
        self.help(text)
        #else
        self
        #endif
    }

    /// Escape handling is a hardware-keyboard affordance. On iOS `onExitCommand`
    /// does not exist; dismissing a field happens through the keyboard/toolbar.
    @ViewBuilder
    func platformExitCommand(_ action: @escaping () -> Void) -> some View {
        #if os(macOS)
        self.onExitCommand(perform: action)
        #else
        self
        #endif
    }

    /// A hand cursor where the Mac shows one. iPadOS gets its native hover
    /// effect instead; iPhone ignores it.
    @ViewBuilder
    func platformPointerHover(_ enabled: Bool = true) -> some View {
        #if os(macOS)
        self
        #else
        if enabled {
            self.hoverEffect(.automatic)
        } else {
            self
        }
        #endif
    }
}

// MARK: - Appearance

extension SettingsStore.Appearance {
    #if os(macOS)
    var nsAppearance: NSAppearance? {
        switch self {
        case .auto: nil
        case .light: NSAppearance(named: .aqua)
        case .dark: NSAppearance(named: .darkAqua)
        }
    }
    #else
    /// SwiftUI applies this at the root on iOS/iPadOS; UIKit has no global
    /// appearance switch that survives the scene the way NSApplication does.
    var colorScheme: ColorScheme? {
        switch self {
        case .auto: nil
        case .light: .light
        case .dark: .dark
        }
    }
    #endif
}
