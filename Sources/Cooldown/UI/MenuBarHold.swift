import AppKit

/// Keeps an auto-hiding menu bar on screen while the panel is open, the way a menu or a
/// Control Center popover does.
///
/// With "Automatically hide and show the menu bar" on, the WindowServer slides the bar
/// away as soon as the pointer leaves it, and AppKit gives an app no public way to stop
/// that: `NSApp.presentationOptions` cannot drop `.autoHideMenuBar` once the system
/// preference sets it, and only NSMenu's own tracking session holds the bar (which blocks
/// the main queue for as long as the menu is open). The WindowServer does expose a
/// per-display override through SkyLight, which is what this uses. It is resolved by
/// name at launch, so on a macOS that no longer has it the bar simply hides as before.
@MainActor
enum MenuBarHold {
    private typealias MainConnectionID = @convention(c) () -> Int32
    private typealias SetOverride = @convention(c) (Int32, CGDirectDisplayID, Bool) -> Int32

    private static let skyLight: (connection: Int32, setOverride: SetOverride)? = {
        guard let handle = dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight", RTLD_NOW),
              let mainConnection = dlsym(handle, "SLSMainConnectionID"),
              let setOverride = dlsym(handle, "SLSSetMenuBarVisibilityOverrideOnDisplay")
        else { return nil }
        let connection = unsafeBitCast(mainConnection, to: MainConnectionID.self)()
        return (connection, unsafeBitCast(setOverride, to: SetOverride.self))
    }()

    private static var heldDisplay: CGDirectDisplayID?

    /// Holds the bar on the display that shows `screen` until `release()`.
    static func hold(on screen: NSScreen?) {
        guard let skyLight else { return }
        let display = screen.flatMap { $0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID }
            ?? CGMainDisplayID()
        if let heldDisplay, heldDisplay != display { release() }
        _ = skyLight.setOverride(skyLight.connection, display, true)
        heldDisplay = display
    }

    /// Lets the bar hide itself again. Safe to call when nothing is held.
    static func release() {
        guard let skyLight, let display = heldDisplay else { return }
        _ = skyLight.setOverride(skyLight.connection, display, false)
        heldDisplay = nil
    }
}
