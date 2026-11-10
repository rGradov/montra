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
        if let animateIndex = arguments.firstIndex(of: "-animate-onboarding-intro"),
           arguments.indices.contains(animateIndex + 1) {
            let directory = URL(fileURLWithPath: arguments[animateIndex + 1], isDirectory: true)
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            renderHandOff(into: directory)
            return true
        }

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
            // checked: the mascot's flight, the landing, and the flow alone.
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

            // The dismiss starts at 4.35 s: these catch the mascot in the air,
            // covering the icon, and the welcome step on its own.
            let rootMoments: [(String, TimeInterval)] = [
                ("06a-flight", 4.55),
                ("06b-landed", 5.05),
                ("06c-welcome", 7.00),
            ]
            let rootStart = Date()
            for (name, moment) in rootMoments {
                let remaining = moment - Date().timeIntervalSince(rootStart)
                if remaining > 0 {
                    RunLoop.current.run(until: Date().addingTimeInterval(remaining))
                }
                rootHosting.layoutSubtreeIfNeeded()
                guard let rep = rootHosting.bitmapImageRepForCachingDisplay(in: rootHosting.bounds) else { continue }
                rootHosting.cacheDisplay(in: rootHosting.bounds, to: rep)
                let suffix = scheme == .dark ? "dark" : "light"
                let url = directory.appendingPathComponent("intro-\(name)-\(suffix).png")
                try? rep.representation(using: .png, properties: [:])?.write(to: url)
            }
            rootWindow.orderOut(nil)

            application.appearance = previous
        }
        return true
    }

    /// Debug-only: renders the mascot's hand-off step by step, so the flight can
    /// be inspected frame by frame without screen capture. The hand-off is a
    /// single animation, so it is rendered frozen at each step instead of being
    /// sampled in real time; the geometry and the fades are the shipped ones.
    /// `Montra -animate-onboarding-intro /tmp/montra-handoff`
    private static func renderHandOff(into directory: URL) {
        let defaults = UserDefaults(suiteName: "montra.handoff.animation") ?? .standard
        defaults.removePersistentDomain(forName: "montra.handoff.animation")
        let settings = SettingsStore(defaults: defaults)
        settings.appearance = .dark
        settings.primaryCurrency = .byn
        let rates = RateStore(preview: ExchangeRates(
            bynPerUnit: [.byn: 1, .usd: 3.0010, .eur: 3.3460, .usdc: 3.0034, .usdt: 2.9963, .btc: 227_358, .eth: 6_705],
            date: Calendar.current.date(byAdding: .day, value: -1, to: .now),
            fetchedAt: .now,
            source: .nbrb
        ))
        let container = ModelContainerFactory.make(inMemory: true)

        NSApp.appearance = NSAppearance(named: .darkAqua)
        let size = CGSize(width: AppWindowLayout.width, height: AppWindowLayout.defaultHeight)
        let progress = HandOffProgress()
        let content = HandOffPreview(progress: progress)
            .frame(width: size.width, height: size.height, alignment: .topLeading)
            .environment(\.colorScheme, .dark)
            .environmentObject(settings)
            .environmentObject(rates)
            .modelContainer(container)
        let hosting = NSHostingView(rootView: content)
        hosting.frame = CGRect(origin: .zero, size: size)
        let window = NSWindow(
            contentRect: CGRect(origin: .zero, size: size),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.appearance = NSAppearance(named: .darkAqua)
        window.backgroundColor = .clear
        window.contentView = hosting
        window.setFrameOrigin(NSPoint(x: 20, y: 20))
        window.orderFrontRegardless()

        // The first layout pass is what measures the mascot and the icon.
        RunLoop.current.run(until: Date().addingTimeInterval(0.4))
        hosting.layoutSubtreeIfNeeded()

        let steps = OnboardingHandOffCapture.steps
        for index in -1...steps {
            // A negative value renders the screen before the hand-off, as the
            // reference each step is compared with.
            progress.value = CGFloat(index) / CGFloat(steps)
            // Let the frozen value reach the intro and be laid out.
            RunLoop.current.run(until: Date().addingTimeInterval(0.06))
            hosting.layoutSubtreeIfNeeded()
            guard let rep = hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds) else { continue }
            hosting.cacheDisplay(in: hosting.bounds, to: rep)
            let url = directory.appendingPathComponent(String(format: "frame_%03d.tiff", index + 1))
            try? rep.tiffRepresentation?.write(to: url)
        }

        // The two states the flight hands over to: the icon still waiting out of
        // focus with the mascot gone, and the welcome screen in focus. They come
        // from the flow on its own, so they are the same views the app shows.
        for (offset, waits) in [(0, true), (1, false)] {
            let state = HandOffPreview(progress: progress, welcomesOnly: true, waitsForMori: waits)
                .frame(width: size.width, height: size.height, alignment: .topLeading)
                .environment(\.colorScheme, .dark)
                .environmentObject(settings)
                .environmentObject(rates)
                .modelContainer(container)
            let stateHosting = NSHostingView(rootView: state)
            stateHosting.frame = CGRect(origin: .zero, size: size)
            window.contentView = stateHosting
            stateHosting.layoutSubtreeIfNeeded()
            // Long enough for the staggered reveal of this screen to finish.
            RunLoop.current.run(until: Date().addingTimeInterval(1.2))
            stateHosting.layoutSubtreeIfNeeded()
            guard let rep = stateHosting.bitmapImageRepForCachingDisplay(in: stateHosting.bounds) else { continue }
            stateHosting.cacheDisplay(in: stateHosting.bounds, to: rep)
            let url = directory.appendingPathComponent(String(format: "frame_%03d.tiff", steps + 2 + offset))
            try? rep.tiffRepresentation?.write(to: url)
        }
        window.orderOut(nil)
    }
}

/// Drives the frozen hand-off for the capture.
@MainActor
final class HandOffProgress: ObservableObject {
    @Published var value: CGFloat = 0
}

/// The real root view with the hand-off frozen at `progress`, so each capture is
/// a deterministic frame of the same animation. With `welcomesOnly` it renders
/// the welcome step on its own, in the state the mascot hands over to.
private struct HandOffPreview: View {
    @ObservedObject var progress: HandOffProgress
    var welcomesOnly = false
    var waitsForMori = false

    @ViewBuilder
    var body: some View {
        if welcomesOnly {
            OnboardingFlowView(initialStep: .welcome, onFinish: {})
                .environment(\.welcomeArtworkWaitsForMori, waitsForMori)
                .background(AppColors.surfaceBase)
        } else {
            AppRootView(needsOnboarding: true)
                .environment(\.moriFlightPreview, progress.value < 0 ? nil : progress.value)
        }
    }
}

/// The window of the hand-off that the frame capture records, and that the
/// review video is cut from.
enum OnboardingHandOffCapture {
    /// How many stills the flight is cut into.
    static let steps: Int = 36
}
