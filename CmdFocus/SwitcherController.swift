import AppKit

/// Runs a switching session: from the first Cmd+Tab until Command is released
/// (or the session is cancelled), mirroring the built-in switcher's behavior.
final class SwitcherController: NSObject {
    private enum Key {
        static let tab: Int64 = 48
        static let returnKey: Int64 = 36
        static let keypadEnter: Int64 = 76
        static let escape: Int64 = 53
        static let leftArrow: Int64 = 123
        static let rightArrow: Int64 = 124
        static let home: Int64 = 115
        static let end: Int64 = 119
    }

    /// A quick Cmd+Tab tap switches without ever showing the panel, like the built-in switcher.
    private static let showDelay: TimeInterval = 0.1

    private let catalog = AppCatalog()
    private let panel = SwitcherPanel()

    private var apps: [NSRunningApplication] = []
    private var selected = 0
    private var isActive = false
    /// Apps asked to quit that haven't exited yet (they may be showing a save prompt).
    private var quitting = Set<pid_t>()
    /// Keys whose key-down we swallowed, so the matching key-up is swallowed too.
    private var swallowedKeys = Set<Int64>()
    private var showTimer: Timer?
    private var commandWatchdog: Timer?

    override init() {
        super.init()
        panel.onHover = { [weak self] index in self?.hover(index) }
        panel.onClick = { [weak self] index in self?.click(index) }

        let center = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didTerminateApplicationNotification, NSWorkspace.didHideApplicationNotification] {
            center.addObserver(self, selector: #selector(appWentAway(_:)), name: name, object: nil)
        }
    }

    // MARK: - Keyboard

    /// Handles an event from the keyboard tap. Returns `true` to swallow it.
    func handle(_ type: CGEventType, _ event: CGEvent) -> Bool {
        switch type {
        case .flagsChanged:
            if isActive, !event.flags.contains(.maskCommand) { commit() }
            return false

        case .keyDown:
            let code = event.getIntegerValueField(.keyboardEventKeycode)
            let isRepeat = event.getIntegerValueField(.keyboardEventAutorepeat) != 0
            if isActive {
                swallowedKeys.insert(code)
                handleSessionKey(code, event: event, isRepeat: isRepeat)
                return true
            }
            let flags = event.flags
            guard code == Key.tab, flags.contains(.maskCommand),
                  flags.isDisjoint(with: [.maskControl, .maskAlternate]) else { return false }
            swallowedKeys.insert(code)
            if !isRepeat { begin(backward: flags.contains(.maskShift)) }
            return true

        case .keyUp:
            let code = event.getIntegerValueField(.keyboardEventKeycode)
            return swallowedKeys.remove(code) != nil || isActive

        default:
            return false
        }
    }

    private func handleSessionKey(_ code: Int64, event: CGEvent, isRepeat: Bool) {
        // A held key runs to the end of the row and stops; a fresh press wraps around.
        let wrap = !isRepeat
        switch code {
        case Key.tab:
            move(by: event.flags.contains(.maskShift) ? -1 : 1, wrap: wrap)
        case Key.rightArrow:
            move(by: 1, wrap: wrap)
        case Key.leftArrow:
            move(by: -1, wrap: wrap)
        case Key.home:
            select(0)
        case Key.end:
            select(apps.count - 1)
        case Key.returnKey, Key.keypadEnter:
            commit()
        case Key.escape:
            cancel()
        default:
            // Matched by character rather than key position so non-QWERTY layouts work.
            switch NSEvent(cgEvent: event)?.charactersIgnoringModifiers?.lowercased() {
            case "`", "~":
                move(by: -1, wrap: wrap)
            case "q" where !isRepeat:
                quitSelected()
            case "h" where !isRepeat:
                hideSelected()
            case ".":
                cancel()
            default:
                break
            }
        }
    }

    /// Ends any session without switching. Used when the keyboard tap is interrupted or removed,
    /// since the Command release may have been missed.
    func cancel() {
        guard isActive else { return }
        end()
    }

    // MARK: - Session

    private func begin(backward: Bool) {
        apps = catalog.switchableApps()
        quitting.removeAll()
        guard !apps.isEmpty else { return }

        // The frontmost app leads the list when it qualifies, so the first press lands on the
        // previous app. If the frontmost app has no windows it isn't listed, and the first
        // press lands on the most recent app that does.
        let frontmost = NSWorkspace.shared.frontmostApplication?.processIdentifier
        let frontmostListed = apps[0].processIdentifier == frontmost
        if backward {
            selected = apps.count - 1
        } else {
            selected = frontmostListed && apps.count > 1 ? 1 : 0
        }
        isActive = true

        showTimer = scheduleTimer(after: Self.showDelay, repeats: false, #selector(showTimerFired))
        // Safety net: if the Command release never reaches the tap (secure input, a tap
        // timeout), notice it here instead of leaving the panel stuck on screen.
        commandWatchdog = scheduleTimer(after: 0.05, repeats: true, #selector(checkCommandStillDown))
    }

    private func end() {
        isActive = false
        showTimer?.invalidate()
        showTimer = nil
        commandWatchdog?.invalidate()
        commandWatchdog = nil
        panel.orderOut(nil)
        apps = []
        quitting.removeAll()
    }

    private func commit() {
        guard isActive else { return }
        let target = apps.indices.contains(selected) ? apps[selected] : nil
        end()
        guard let target, !target.isTerminated, !target.isActive else { return }
        target.activate(options: [.activateAllWindows])
    }

    private func move(by delta: Int, wrap: Bool) {
        guard !apps.isEmpty else { return }
        var index = selected + delta
        if wrap {
            index = (index % apps.count + apps.count) % apps.count
        } else {
            index = min(max(index, 0), apps.count - 1)
        }
        select(index)
    }

    private func select(_ index: Int) {
        guard apps.indices.contains(index) else { return }
        selected = index
        if panel.isVisible {
            panel.select(index)
        } else {
            showPanel()
        }
    }

    private func quitSelected() {
        guard apps.indices.contains(selected) else { return }
        let app = apps[selected]
        // The icon stays (dimmed) until the app actually exits; it may refuse or ask to save.
        if app.terminate() { quitting.insert(app.processIdentifier) }
        showPanel()
    }

    private func hideSelected() {
        guard apps.indices.contains(selected) else { return }
        let app = apps[selected]
        if app.hide() { remove(app) }
    }

    private func remove(_ app: NSRunningApplication) {
        guard let index = apps.firstIndex(where: { $0.processIdentifier == app.processIdentifier }) else { return }
        apps.remove(at: index)
        quitting.remove(app.processIdentifier)
        guard !apps.isEmpty else {
            end()
            return
        }
        if index < selected { selected -= 1 }
        selected = min(selected, apps.count - 1)
        showPanel()
    }

    @objc private func appWentAway(_ note: Notification) {
        guard isActive,
              let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
        remove(app)
    }

    // MARK: - Mouse

    private func hover(_ index: Int) {
        guard isActive, index != selected else { return }
        select(index)
    }

    private func click(_ index: Int) {
        guard isActive, apps.indices.contains(index) else { return }
        selected = index
        commit()
    }

    // MARK: - Panel

    /// Shows the panel, or refreshes it if it's already up.
    private func showPanel() {
        showTimer?.invalidate()
        showTimer = nil
        // Stay on the same display while the panel is up; otherwise use the one with keyboard focus.
        guard isActive,
              let screen = (panel.isVisible ? panel.screen : nil) ?? NSScreen.main ?? NSScreen.screens.first
        else { return }
        let items = apps.map { app in
            SwitcherPanel.Item(name: app.localizedName ?? app.bundleIdentifier ?? "",
                               icon: app.icon,
                               isDimmed: quitting.contains(app.processIdentifier))
        }
        panel.present(items, selected: selected, on: screen)
    }

    @objc private func showTimerFired() {
        showPanel()
    }

    @objc private func checkCommandStillDown() {
        if !CGEventSource.flagsState(.combinedSessionState).contains(.maskCommand) { commit() }
    }

    private func scheduleTimer(after interval: TimeInterval, repeats: Bool, _ selector: Selector) -> Timer {
        let timer = Timer(timeInterval: interval, target: self, selector: selector, userInfo: nil, repeats: repeats)
        RunLoop.main.add(timer, forMode: .common)
        return timer
    }

    // MARK: - Debug

    #if DEBUG
    /// Shows the panel and leaves it up, without needing the keyboard tap. For checking the look.
    func showDemo() {
        apps = catalog.switchableApps()
        guard !apps.isEmpty else { return }
        selected = min(1, apps.count - 1)
        isActive = true
        showPanel()
    }

    func debugListing() -> String {
        catalog.switchableApps().map { $0.localizedName ?? "?" }.joined(separator: "\n")
    }
    #endif
}
