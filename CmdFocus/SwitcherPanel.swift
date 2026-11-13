import AppKit

/// The floating switcher window. It never becomes key or activates this app, so the
/// app the user is switching away from stays frontmost until a choice is committed.
final class SwitcherPanel: NSPanel {
    struct Item {
        let name: String
        let icon: NSImage?
        let isDimmed: Bool
    }

    private let switcherView = SwitcherView()
    private static let screenMargin: CGFloat = 16

    var onHover: ((Int) -> Void)? {
        get { switcherView.onHover }
        set { switcherView.onHover = newValue }
    }
    var onClick: ((Int) -> Void)? {
        get { switcherView.onClick }
        set { switcherView.onClick = newValue }
    }

    init() {
        super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false  // the glass draws its own
        level = .popUpMenu
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        isMovable = false
        animationBehavior = .none
        contentView = switcherView
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    /// Lays out the items, centers the panel on `screen` and shows it.
    func present(_ items: [Item], selected: Int, on screen: NSScreen) {
        let maxWidth = screen.frame.width - 2 * Self.screenMargin
        let size = switcherView.configure(items, selected: selected, maxWidth: maxWidth)
        let origin = NSPoint(x: (screen.frame.midX - size.width / 2).rounded(),
                             y: (screen.frame.midY - size.height / 2).rounded())
        setFrame(NSRect(origin: origin, size: size), display: true)
        orderFrontRegardless()
    }

    func select(_ index: Int) {
        switcherView.select(index)
    }

}

// MARK: - Layout

/// Metrics for a row of `count` icons, shrunk uniformly when they wouldn't fit in `maxWidth`.
private struct SwitcherLayout {
    var count = 0
    var icon: CGFloat = 128
    var cellPadding: CGFloat = 8
    var inset: CGFloat = 20
    var highlightRadius: CGFloat = 30
    let labelGap: CGFloat = 3
    let labelHeight: CGFloat = 17
    let bottomInset: CGFloat = 11

    init() {}

    init(count: Int, maxWidth: CGFloat) {
        self.count = count
        let idealWidth = CGFloat(count) * (icon + 2 * cellPadding) + 2 * inset
        let scale = min(1, maxWidth / max(idealWidth, 1))
        icon = max(24, (icon * scale).rounded(.down))
        cellPadding = max(3, (cellPadding * scale).rounded(.down))
        inset = max(8, (inset * scale).rounded(.down))
        highlightRadius = max(8, (highlightRadius * scale).rounded())
    }

    var cell: CGFloat { icon + 2 * cellPadding }
    /// Concentric with the selection highlight.
    var cornerRadius: CGFloat { highlightRadius + inset }
    var size: NSSize {
        NSSize(width: CGFloat(count) * cell + 2 * inset,
               height: inset + cell + labelGap + labelHeight + bottomInset)
    }

    func cellFrame(_ index: Int) -> NSRect {
        NSRect(x: inset + CGFloat(index) * cell, y: inset, width: cell, height: cell)
    }

    func index(atX x: CGFloat) -> Int? {
        let index = Int(((x - inset) / cell).rounded(.down))
        return x >= inset && index < count ? index : nil
    }
}

// MARK: - Views

private final class SwitcherView: NSView {
    var onHover: ((Int) -> Void)?
    var onClick: ((Int) -> Void)?

    /// Transparent room around the glass so its shadow isn't clipped by the window edge.
    private static let shadowMargin: CGFloat = 48

    private let glass = NSGlassEffectView()
    private let content = FlippedView()
    private let highlight = HighlightView()
    private let label = NSTextField(labelWithString: "")
    private var iconViews: [NSImageView] = []
    private var names: [String] = []
    private var layout = SwitcherLayout()

    override var isFlipped: Bool { true }

    init() {
        super.init(frame: .zero)
        glass.style = .regular
        glass.contentView = content
        addSubview(glass)

        label.font = .systemFont(ofSize: 13, weight: .medium)
        label.textColor = .labelColor
        label.alignment = .center
        label.lineBreakMode = .byTruncatingTail
        content.addSubview(highlight)
        content.addSubview(label)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    /// Rebuilds the row and returns the size the window needs.
    func configure(_ items: [SwitcherPanel.Item], selected: Int, maxWidth: CGFloat) -> NSSize {
        layout = SwitcherLayout(count: items.count, maxWidth: maxWidth)
        names = items.map(\.name)

        let glassSize = layout.size
        let margin = Self.shadowMargin
        let fullSize = NSSize(width: glassSize.width + 2 * margin, height: glassSize.height + 2 * margin)
        setFrameSize(fullSize)
        glass.frame = NSRect(origin: NSPoint(x: margin, y: margin), size: glassSize)
        glass.cornerRadius = layout.cornerRadius
        content.frame = NSRect(origin: .zero, size: glassSize)
        highlight.cornerRadius = layout.highlightRadius

        while iconViews.count > items.count { iconViews.removeLast().removeFromSuperview() }
        while iconViews.count < items.count {
            let view = NSImageView()
            view.imageScaling = .scaleProportionallyUpOrDown
            content.addSubview(view)
            iconViews.append(view)
        }
        for (index, item) in items.enumerated() {
            let view = iconViews[index]
            view.image = item.icon
            view.alphaValue = item.isDimmed ? 0.35 : 1
            view.frame = layout.cellFrame(index).insetBy(dx: layout.cellPadding, dy: layout.cellPadding)
        }

        select(selected)
        return fullSize
    }

    func select(_ index: Int) {
        guard names.indices.contains(index) else {
            highlight.isHidden = true
            label.isHidden = true
            return
        }
        let cell = layout.cellFrame(index)
        highlight.isHidden = false
        highlight.frame = cell

        // The name is centered under its icon but may spill past the cell, up to the panel edges.
        label.isHidden = false
        label.stringValue = names[index]
        let edge: CGFloat = 10
        let available = layout.size.width - 2 * edge
        // Measured directly, with slack: the label's own intrinsic size comes out too narrow
        // on glass and truncates the name. The text is centered, so extra width is invisible.
        let font = label.font ?? .systemFont(ofSize: 13, weight: .medium)
        let textWidth = (names[index] as NSString).size(withAttributes: [.font: font]).width
        let width = min(textWidth.rounded(.up) + 24, available)
        let x = min(max(cell.midX - width / 2, edge), layout.size.width - edge - width)
        label.frame = NSRect(x: x.rounded(), y: cell.maxY + layout.labelGap,
                             width: width, height: layout.labelHeight)
    }

    // MARK: Mouse

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        // No enter/exit tracking on purpose: only real mouse movement should change the
        // selection, not the panel appearing under a resting pointer.
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseMoved, .activeAlways, .inVisibleRect],
                                       owner: self, userInfo: nil))
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        let local = superview.map { convert(point, from: $0) } ?? point
        return glass.frame.contains(local) ? self : nil
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseMoved(with event: NSEvent) {
        if let index = index(for: event) { onHover?(index) }
    }

    override func mouseUp(with event: NSEvent) {
        if let index = index(for: event) { onClick?(index) }
    }

    private func index(for event: NSEvent) -> Int? {
        let point = convert(event.locationInWindow, from: nil)
        guard glass.frame.contains(point) else { return nil }
        return layout.index(atX: point.x - glass.frame.minX)
    }
}

private final class FlippedView: NSView {
    override var isFlipped: Bool { true }
}

/// The rounded rectangle behind the selected icon.
private final class HighlightView: NSView {
    var cornerRadius: CGFloat = 0 {
        didSet { needsDisplay = true }
    }

    init() {
        super.init(frame: .zero)
        wantsLayer = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override var wantsUpdateLayer: Bool { true }

    override func updateLayer() {
        guard let layer else { return }
        layer.cornerRadius = cornerRadius
        layer.cornerCurve = .continuous
        layer.backgroundColor = NSColor.labelColor.withAlphaComponent(0.14).cgColor
    }
}
