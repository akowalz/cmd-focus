import AppKit

/// Knows which apps belong in the switcher and in what order.
///
/// An app is listed when it is a regular (Dock) app, is not hidden, and has at
/// least one window that is actually showing on some Space. Minimized windows,
/// closed windows and the windows of hidden apps don't count.
final class AppCatalog: NSObject {
    /// Most recently activated first.
    private var recency: [pid_t] = []

    override init() {
        super.init()
        seedRecency()
        let center = NSWorkspace.shared.notificationCenter
        center.addObserver(self, selector: #selector(appActivated(_:)),
                           name: NSWorkspace.didActivateApplicationNotification, object: nil)
        center.addObserver(self, selector: #selector(appTerminated(_:)),
                           name: NSWorkspace.didTerminateApplicationNotification, object: nil)
    }

    /// Apps to show, most recently used first, with the frontmost app leading when it qualifies.
    func switchableApps() -> [NSRunningApplication] {
        let withWindows = Self.pidsWithVisibleWindows()
        let frontmost = NSWorkspace.shared.frontmostApplication?.processIdentifier
        let rank = Dictionary(recency.enumerated().map { ($1, $0) }, uniquingKeysWith: { first, _ in first })

        return NSWorkspace.shared.runningApplications
            .filter { app in
                app.activationPolicy == .regular
                    && !app.isHidden
                    && !app.isTerminated
                    && withWindows.contains(app.processIdentifier)
            }
            .enumerated()
            .sorted { lhs, rhs in
                let l = sortKey(lhs.element, frontmost: frontmost, rank: rank)
                let r = sortKey(rhs.element, frontmost: frontmost, rank: rank)
                return l == r ? lhs.offset < rhs.offset : l < r
            }
            .map(\.element)
    }

    private func sortKey(_ app: NSRunningApplication, frontmost: pid_t?, rank: [pid_t: Int]) -> Int {
        if app.processIdentifier == frontmost { return -1 }
        return rank[app.processIdentifier] ?? Int.max
    }

    // MARK: - Window visibility

    /// Window levels that count as "a window the user can see": normal, floating and modal panels.
    /// Everything else (desktop, Dock, menu bar, status items, overlays) is chrome.
    private static let countedLevels: Set<Int> = [
        Int(CGWindowLevelForKey(.normalWindow)),
        Int(CGWindowLevelForKey(.floatingWindow)),
        Int(CGWindowLevelForKey(.modalPanelWindow)),
    ]
    private static let minimumWindowSide: CGFloat = 50

    /// Process IDs owning at least one window that is showing on any Space.
    static func pidsWithVisibleWindows() -> Set<pid_t> {
        // Ordered-in windows on every Space. Minimized windows, closed-but-retained
        // windows and the windows of hidden apps are ordered out, so they're absent.
        let showing = Set(orderedInWindowNumbers())
        guard !showing.isEmpty,
              let windows = CGWindowListCopyWindowInfo([.optionAll], kCGNullWindowID) as? [[String: Any]]
        else { return [] }

        var pids = Set<pid_t>()
        for window in windows {
            guard let number = window[kCGWindowNumber as String] as? Int, showing.contains(number),
                  let pid = window[kCGWindowOwnerPID as String] as? Int,
                  let level = window[kCGWindowLayer as String] as? Int, countedLevels.contains(level),
                  (window[kCGWindowAlpha as String] as? Double ?? 1) > 0,
                  let boundsDict = window[kCGWindowBounds as String] as? NSDictionary,
                  let bounds = CGRect(dictionaryRepresentation: boundsDict),
                  bounds.width >= minimumWindowSide, bounds.height >= minimumWindowSide
            else { continue }
            pids.insert(pid_t(pid))
        }
        return pids
    }

    /// Front-to-back window numbers of every ordered-in window, across all apps and Spaces.
    private static func orderedInWindowNumbers() -> [Int] {
        (NSWindow.windowNumbers(options: [.allApplications, .allSpaces]) ?? []).map(\.intValue)
    }

    // MARK: - Recency

    /// macOS doesn't expose its own Cmd+Tab ordering, so start from window stacking order
    /// (front to back) and keep it current from activation notifications after that.
    private func seedRecency() {
        var order: [pid_t] = []
        if let front = NSWorkspace.shared.frontmostApplication {
            order.append(front.processIdentifier)
        }
        let showing = Self.orderedInWindowNumbers()
        if let windows = CGWindowListCopyWindowInfo([.optionAll], kCGNullWindowID) as? [[String: Any]] {
            var owner: [Int: pid_t] = [:]
            for window in windows {
                if let number = window[kCGWindowNumber as String] as? Int,
                   let pid = window[kCGWindowOwnerPID as String] as? Int,
                   (window[kCGWindowLayer as String] as? Int) == 0 {
                    owner[number] = pid_t(pid)
                }
            }
            for number in showing {
                if let pid = owner[number], !order.contains(pid) { order.append(pid) }
            }
        }
        recency = order
    }

    @objc private func appActivated(_ note: Notification) {
        guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
        let pid = app.processIdentifier
        recency.removeAll { $0 == pid }
        recency.insert(pid, at: 0)
    }

    @objc private func appTerminated(_ note: Notification) {
        guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
        recency.removeAll { $0 == app.processIdentifier }
    }
}
