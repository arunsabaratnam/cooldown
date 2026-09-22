import AppKit
import Combine
import SwiftUI

@main
struct CooldownApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    // Everything visible is AppKit-owned (the status item, its panel, the Settings
    // window), so the one scene SwiftUI insists on is an empty one that never opens.
    var body: some Scene {
        SwiftUI.Settings { EmptyView() }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: StatusItemController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = StatusItemController(store: UsageStore())
    }
}

/// The menu bar icon and the panel it opens.
///
/// This used to be a SwiftUI `MenuBarExtra`, but that window closes whenever the menu bar
/// does, which with "Automatically hide and show the menu bar" turned on means the moment
/// the pointer drifts down. This panel stays until you click the icon again, click
/// somewhere else, or press Esc.
@MainActor
final class StatusItemController: NSObject {
    static weak var shared: StatusItemController?

    private let store: UsageStore
    private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let panel: FloatingPanel
    private let hosting: NSHostingView<MenuContentView>
    private var cancellables = Set<AnyCancellable>()
    private var outsideClickMonitor: Any?
    private var keyMonitor: Any?

    init(store: UsageStore) {
        self.store = store
        hosting = NSHostingView(rootView: MenuContentView(store: store))
        panel = FloatingPanel(
            contentRect: NSRect(x: 0, y: 0, width: 352, height: 400),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: true
        )
        super.init()
        Self.shared = self

        panel.contentView = hosting
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .statusBar
        panel.hidesOnDeactivate = false
        panel.isMovable = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        if let button = item.button {
            button.target = self
            button.action = #selector(togglePanel)
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
            button.imagePosition = .imageLeading
        }

        store.objectWillChange
            .sink { [weak self] _ in
                // objectWillChange fires before the change lands; read it on the next turn.
                DispatchQueue.main.async { self?.refresh() }
            }
            .store(in: &cancellables)
        refresh()
    }

    private func refresh() {
        guard let button = item.button else { return }
        button.image = MenuBarIconRenderer.icon(for: store)
        let title = store.menuBarTitle
        button.title = title.isEmpty ? "" : " " + title
        button.font = NSFont.monospacedDigitSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
        button.setAccessibilityLabel(MenuBarIconRenderer.accessibilityText(for: store))
        if panel.isVisible { fitPanel(anchoredTop: panel.frame.maxY) }
    }

    @objc private func togglePanel() {
        panel.isVisible ? hidePanel() : showPanel()
    }

    private func showPanel() {
        guard let button = item.button, let buttonWindow = button.window else { return }
        store.panelAppeared()
        let buttonFrame = buttonWindow.convertToScreen(button.convert(button.bounds, to: nil))
        fitPanel(anchoredTop: buttonFrame.minY - 6, centeredOn: buttonFrame.midX, screen: buttonWindow.screen)
        panel.makeKeyAndOrderFront(nil)
        button.highlight(true)

        outsideClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            Task { @MainActor in self?.hidePanel() }
        }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.keyCode == 53 { // Esc
                self?.hidePanel()
                return nil
            }
            return event
        }
    }

    func hidePanel() {
        guard panel.isVisible else { return }
        panel.orderOut(nil)
        item.button?.highlight(false)
        store.panelDisappeared()
        if let outsideClickMonitor { NSEvent.removeMonitor(outsideClickMonitor) }
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        outsideClickMonitor = nil
        keyMonitor = nil
    }

    /// Sizes the panel to its content, keeping its top edge where it is.
    private func fitPanel(anchoredTop top: CGFloat, centeredOn midX: CGFloat? = nil, screen: NSScreen? = nil) {
        hosting.layoutSubtreeIfNeeded()
        let size = hosting.fittingSize
        let visible = (screen ?? panel.screen ?? NSScreen.main)?.visibleFrame ?? .zero
        var x = midX.map { $0 - size.width / 2 } ?? panel.frame.minX
        x = min(max(x, visible.minX + 8), visible.maxX - size.width - 8)
        panel.setFrame(NSRect(x: x, y: top - size.height, width: size.width, height: size.height), display: true)
    }
}

/// A borderless panel that can take clicks and key presses without making Cooldown the
/// active app, so whatever you were working in keeps its focus.
final class FloatingPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
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
        StatusItemController.shared?.hidePanel()
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

/// Draws the 16 pt menu bar glyph. Untinted it is a template image, so macOS colours it
/// to match the menu bar; tinted it takes the theme's accent and stops adapting.
enum MenuBarIconRenderer {
    @MainActor
    static func icon(for store: UsageStore) -> NSImage {
        let tint: NSColor? = store.settings.tintMenuBarIcon && store.settings.theme != .mono
            ? NSColor(store.settings.theme.theme.accent)
            : nil
        if store.nothingConnected && store.lastRefresh != nil {
            return notConnected(tint: tint)
        }
        switch store.settings.menuBarIcon {
        case .ring: return ring(fraction: store.tightestFiveHourFraction, tint: tint)
        case .twinBars: return bars(fractions: store.fiveHourFractions, tint: tint)
        }
    }

    @MainActor
    static func accessibilityText(for store: UsageStore) -> String {
        guard let fraction = store.tightestFiveHourFraction else { return "Cooldown" }
        return "Cooldown, \(Int((fraction * 100).rounded()))% of the 5-hour window left"
    }

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
