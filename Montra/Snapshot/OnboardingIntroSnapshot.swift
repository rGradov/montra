import AppKit
import SwiftData
import SwiftUI

// MARK: - Snapshot QA

/// Renders the intro at fixed moments so its pacing and glow can be checked
/// without sitting through it:
/// `Montra -intro-snapshots /tmp/montra-intro`
@MainActor
enum OnboardingIntroSnapshot {
    static func renderIfRequested() -> Bool {
        let arguments = CommandLine.arguments
        guard let flagIndex = arguments.firstIndex(of: "-intro-snapshots"),
              arguments.indices.contains(flagIndex + 1) else { return false }

        let directory = URL(fileURLWithPath: arguments[flagIndex + 1], isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let size = CGSize(width: AppWindowLayout.width, height: AppWindowLayout.defaultHeight)
        let moments: [(String, TimeInterval)] = [
            ("01-gather", 0.95),
            ("01b-prelude", 1.65),
            ("02-pop", 2.30),
            ("03-hold", 2.90),
            ("04-caption", 3.65),
            ("05-crossfade", 4.55),
        ]

        let application = NSApplication.shared
        for scheme in [ColorScheme.light, .dark] {
            let appearance = scheme == .dark ? NSAppearance(named: .darkAqua) : NSAppearance(named: .aqua)
            let previous = application.appearance
            application.appearance = appearance

            let content = OnboardingIntroView(playsSound: false, onFinished: {})
                .frame(width: size.width, height: size.height)
                .environment(\.colorScheme, scheme)
                .background(AppColors.surfaceBase)

            let hosting = NSHostingView(rootView: content)
            hosting.frame = CGRect(origin: .zero, size: size)

            let window = NSWindow(
                contentRect: hosting.frame,
                styleMask: [.borderless],
                backing: .buffered,
                defer: false
            )
            window.appearance = appearance
            window.contentView = hosting
            window.setFrameOrigin(NSPoint(x: 24, y: 24))
            window.orderFrontRegardless()
            hosting.layoutSubtreeIfNeeded()

            let start = Date()
            for (name, moment) in moments {
                let remaining = moment - Date().timeIntervalSince(start)
                if remaining > 0 {
                    RunLoop.current.run(until: Date().addingTimeInterval(remaining))
                }
                hosting.layoutSubtreeIfNeeded()
                guard let rep = hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds) else { continue }
                hosting.cacheDisplay(in: hosting.bounds, to: rep)
                let suffix = scheme == .dark ? "dark" : "light"
                let url = directory.appendingPathComponent("intro-\(name)-\(suffix).png")
                try? rep.representation(using: .png, properties: [:])?.write(to: url)
            }

            window.orderOut(nil)

            // The real composition, so the hand-off to the welcome step can be
            // checked: intro above the flow, then the flow alone at 5.85 s.
            let defaults = UserDefaults(suiteName: "montra.intro.snapshot") ?? .standard
            defaults.removePersistentDomain(forName: "montra.intro.snapshot")
            let settings = SettingsStore(defaults: defaults)
            settings.appearance = scheme == .dark ? .dark : .light
            let container = ModelContainerFactory.make(inMemory: true)
            let rates = RateStore(preview: ExchangeRates(
                bynPerUnit: [.byn: 1, .usd: 3.0010, .eur: 3.3460, .usdc: 3.0034, .usdt: 2.9963, .btc: 227_358, .eth: 6_705],
                date: Calendar.current.date(byAdding: .day, value: -1, to: .now),
                fetchedAt: .now,
                source: .nbrb
            ))
            let root = AppRootView(needsOnboarding: true)
                .frame(width: size.width, height: size.height)
                .environment(\.colorScheme, scheme)
                .environmentObject(settings)
                .environmentObject(rates)
                .modelContainer(container)

            let rootHosting = NSHostingView(rootView: root)
            rootHosting.frame = CGRect(origin: .zero, size: size)
            let rootWindow = NSWindow(
                contentRect: rootHosting.frame,
                styleMask: [.borderless],
                backing: .buffered,
                defer: false
            )
            rootWindow.appearance = appearance
            rootWindow.contentView = rootHosting
            rootWindow.setFrameOrigin(NSPoint(x: 24, y: 24))
            rootWindow.orderFrontRegardless()
            rootHosting.layoutSubtreeIfNeeded()

            RunLoop.current.run(until: Date().addingTimeInterval(5.85))
            rootHosting.layoutSubtreeIfNeeded()
            if let rep = rootHosting.bitmapImageRepForCachingDisplay(in: rootHosting.bounds) {
                rootHosting.cacheDisplay(in: rootHosting.bounds, to: rep)
                let suffix = scheme == .dark ? "dark" : "light"
                let url = directory.appendingPathComponent("intro-06-welcome-\(suffix).png")
                try? rep.representation(using: .png, properties: [:])?.write(to: url)
            }
            rootWindow.orderOut(nil)

            application.appearance = previous
        }
        return true
    }
}
