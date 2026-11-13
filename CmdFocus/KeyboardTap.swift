import AppKit

/// A session-wide keyboard event tap. Lets the switcher see Cmd+Tab before the
/// system does and swallow it, which is what keeps the built-in switcher from appearing.
/// Requires the Accessibility permission.
final class KeyboardTap {
    /// Return `true` to swallow the event, `false` to let it through untouched.
    var handler: ((CGEventType, CGEvent) -> Bool)?
    /// Called when the system re-enabled the tap after disabling it (timeout or secure input).
    var onReenabled: (() -> Void)?

    private var port: CFMachPort?
    private var source: CFRunLoopSource?

    var isRunning: Bool { port != nil }

    /// Returns `false` when the tap couldn't be created, which means the permission is missing.
    @discardableResult
    func start() -> Bool {
        guard port == nil else { return true }

        let mask: CGEventMask = [CGEventType.keyDown, .keyUp, .flagsChanged]
            .reduce(0) { $0 | (1 << CGEventMask($1.rawValue)) }

        guard let port = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: keyboardTapCallback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else { return false }

        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, port, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: port, enable: true)
        self.port = port
        self.source = source
        return true
    }

    func stop() {
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        if let port { CGEvent.tapEnable(tap: port, enable: false) }
        source = nil
        port = nil
    }

    fileprivate func receive(_ type: CGEventType, _ event: CGEvent) -> Bool {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let port { CGEvent.tapEnable(tap: port, enable: true) }
            onReenabled?()
            return false
        }
        return handler?(type, event) ?? false
    }
}

/// The tap's source is on the main run loop, so this always runs on the main thread.
private nonisolated func keyboardTapCallback(
    proxy: CGEventTapProxy, type: CGEventType, event: CGEvent, userInfo: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    guard let userInfo else { return Unmanaged.passUnretained(event) }
    // Safe to hand across: we're already on the main thread and nothing else touches these here.
    nonisolated(unsafe) let tapPointer = userInfo
    nonisolated(unsafe) let tappedEvent = event
    let swallow = MainActor.assumeIsolated {
        Unmanaged<KeyboardTap>.fromOpaque(tapPointer).takeUnretainedValue().receive(type, tappedEvent)
    }
    return swallow ? nil : Unmanaged.passUnretained(event)
}
