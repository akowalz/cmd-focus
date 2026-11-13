import AppKit
import ServiceManagement

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let tap = KeyboardTap()
    private let switcher = SwitcherController()
    private var statusItem: NSStatusItem?
    private var permissionTimer: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        #if DEBUG
        if CommandLine.arguments.contains("--list") {
            print(switcher.debugListing())
            exit(0)
        }
        if CommandLine.arguments.contains("--demo") {
            switcher.showDemo()
            return
        }
        #endif

        tap.handler = { [switcher] type, event in switcher.handle(type, event) }
        tap.onReenabled = { [switcher] in switcher.cancel() }
        setUpStatusItem()

        if !AXIsProcessTrusted() {
            // Shows the system prompt and adds the app to the Accessibility list in System Settings.
            _ = AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary)
        }
        reconcilePermission()

        // Keep watching: start as soon as access is granted, and let go of the tap if access is
        // revoked (a live tap owned by an untrusted process can stall keyboard input).
        let timer = Timer(timeInterval: 1, target: self, selector: #selector(reconcilePermission),
                          userInfo: nil, repeats: true)
        RunLoop.main.add(timer, forMode: .common)
        permissionTimer = timer
    }

    @objc private func reconcilePermission() {
        let trusted = AXIsProcessTrusted()
        if trusted, !tap.isRunning {
            tap.start()
        } else if !trusted, tap.isRunning {
            tap.stop()
            switcher.cancel()
        }
        statusItem?.button?.image = NSImage(
            systemSymbolName: tap.isRunning ? "command" : "exclamationmark.triangle",
            accessibilityDescription: "CmdFocus")
    }

    // MARK: - Menu bar

    private func setUpStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        let menu = NSMenu()
        menu.delegate = self
        item.menu = menu
        statusItem = item
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()

        if !tap.isRunning {
            let title = AXIsProcessTrusted()
                ? "Couldn't start — try relaunching CmdFocus"
                : "Accessibility access needed"
            menu.addItem(withTitle: title, action: nil, keyEquivalent: "")
            menu.addItem(withTitle: "Open Accessibility Settings…",
                         action: #selector(openAccessibilitySettings), keyEquivalent: "").target = self
            menu.addItem(.separator())
        }

        let login = menu.addItem(withTitle: "Launch at Login",
                                 action: #selector(toggleLaunchAtLogin), keyEquivalent: "")
        login.target = self
        login.state = SMAppService.mainApp.status == .enabled ? .on : .off

        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit CmdFocus", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
    }

    @objc private func openAccessibilitySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    @objc private func toggleLaunchAtLogin() {
        do {
            if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
            }
        } catch {
            let alert = NSAlert(error: error)
            alert.messageText = "Couldn't change the Launch at Login setting"
            NSApp.activate()
            alert.runModal()
        }
    }
}
