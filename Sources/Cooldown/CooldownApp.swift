import AppKit
import SwiftUI

@main
@MainActor
struct CooldownApp: App {
    @StateObject private var store = UsageStore()

    var body: some Scene {
        MenuBarExtra {
            MenuContentView(store: store)
        } label: {
            MenuBarLabel(store: store)
        }
        .menuBarExtraStyle(.window)
    }
}

/// The Settings window, kept by hand rather than as a SwiftUI `Settings` scene so the
/// gear menu can open it straight to a pane, and bring it forward: a menu bar app is
/// never the active app on its own, so a window it opens would land behind others.
@MainActor
final class SettingsWindowController {
    static let shared = SettingsWindowController()
    private var window: NSWindow?

    func show(_ pane: SettingsPane, store: UsageStore) {
        store.settingsPane = pane
        if window == nil {
            let window = NSWindow(contentViewController: NSHostingController(rootView: SettingsWindow(store: store)))
            window.title = "Cooldown Settings"
            window.styleMask = [.titled, .closable, .miniaturizable]
            window.isReleasedWhenClosed = false
            window.center()
            self.window = window
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}

struct MenuBarLabel: View {
    @ObservedObject var store: UsageStore

    var body: some View {
        HStack(spacing: 4) {
            Image(nsImage: icon)
            if !store.menuBarTitle.isEmpty {
                Text(store.menuBarTitle)
                    .monospacedDigit()
            }
        }
        .accessibilityLabel(accessibilityText)
    }

    private var tint: NSColor? {
        guard store.settings.tintMenuBarIcon, store.settings.theme != .mono else { return nil }
        return NSColor(store.settings.theme.theme.accent)
    }

    private var icon: NSImage {
        if store.nothingConnected && store.lastRefresh != nil {
            return MenuBarIconRenderer.notConnected(tint: tint)
        }
        switch store.settings.menuBarIcon {
        case .ring:
            return MenuBarIconRenderer.ring(fraction: store.tightestFiveHourFraction, tint: tint)
        case .twinBars:
            return MenuBarIconRenderer.bars(fractions: store.fiveHourFractions, tint: tint)
        }
    }

    private var accessibilityText: String {
        guard let fraction = store.tightestFiveHourFraction else { return "Cooldown" }
        return "Cooldown, \(Int((fraction * 100).rounded()))% of the 5-hour window left"
    }
}

/// Draws the 16 pt menu bar glyph. Untinted it is a template image, so macOS colours it
/// to match the menu bar; tinted it takes the theme's accent and stops adapting.
enum MenuBarIconRenderer {
    private static let size = NSSize(width: 16, height: 16)
    private static let center = NSPoint(x: 8, y: 8)
    private static let radius: CGFloat = 6
    private static let lineWidth: CGFloat = 2.2
    // The gap sits at the bottom: start bottom-left, sweep 270° clockwise.
    private static let startAngle: CGFloat = 225

    static func ring(fraction: Double?, tint: NSColor?) -> NSImage {
        draw(tint: tint) { ink in
            stroke(arc(to: 1), color: ink.withAlphaComponent(0.35))
            guard let fraction else { return }
            if fraction <= 0 {
                let cross = NSBezierPath()
                cross.move(to: NSPoint(x: 5.9, y: 5.9)); cross.line(to: NSPoint(x: 10.1, y: 10.1))
                cross.move(to: NSPoint(x: 10.1, y: 5.9)); cross.line(to: NSPoint(x: 5.9, y: 10.1))
                cross.lineWidth = 1.8
                cross.lineCapStyle = .round
                ink.setStroke()
                cross.stroke()
                return
            }
            stroke(arc(to: max(0.03, fraction)), color: ink)
            if fraction < 0.1 {
                ink.setFill()
                NSBezierPath(ovalIn: NSRect(x: 6.6, y: 6.6, width: 2.8, height: 2.8)).fill()
            }
        }
    }

    static func bars(fractions: [Double?], tint: NSColor?) -> NSImage {
        draw(tint: tint) { ink in
            let shown = Array(fractions.prefix(2))
            let columns: [CGFloat] = shown.count == 1 ? [6.5] : [4.5, 8.5]
            for (index, fraction) in shown.enumerated() {
                let x = columns[index]
                ink.withAlphaComponent(0.35).setFill()
                NSBezierPath(roundedRect: NSRect(x: x, y: 2, width: 3, height: 12), xRadius: 1.5, yRadius: 1.5).fill()
                if let fraction, fraction > 0 {
                    ink.setFill()
                    let height = max(3, 12 * fraction)
                    NSBezierPath(roundedRect: NSRect(x: x, y: 2, width: 3, height: height), xRadius: 1.5, yRadius: 1.5).fill()
                }
            }
        }
    }

    static func notConnected(tint: NSColor?) -> NSImage {
        draw(tint: tint) { ink in
            let circle = NSBezierPath(ovalIn: NSRect(x: 2, y: 2, width: 12, height: 12))
            circle.lineWidth = 1.6
            circle.setLineDash([1.8, 2.2], count: 2, phase: 0)
            ink.withAlphaComponent(0.8).setStroke()
            circle.stroke()
        }
    }

    private static func arc(to fraction: Double) -> NSBezierPath {
        let path = NSBezierPath()
        path.appendArc(
            withCenter: center,
            radius: radius,
            startAngle: startAngle,
            endAngle: startAngle - 270 * CGFloat(min(1, fraction)),
            clockwise: true
        )
        return path
    }

    private static func stroke(_ path: NSBezierPath, color: NSColor) {
        path.lineWidth = lineWidth
        path.lineCapStyle = .round
        color.setStroke()
        path.stroke()
    }

    private static func draw(tint: NSColor?, _ body: @escaping (NSColor) -> Void) -> NSImage {
        let image = NSImage(size: size, flipped: false) { _ in
            body(tint ?? .black)
            return true
        }
        image.isTemplate = tint == nil
        return image
    }
}
