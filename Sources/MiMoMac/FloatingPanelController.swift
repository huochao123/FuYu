import AppKit
import Combine
import SwiftUI

@MainActor
final class FloatingPanelController: NSObject, NSWindowDelegate {
    private let state: AppState
    private let preferences: AssistantPreferences
    private let panel: FloatingPanel
    private var mode: AppState.OverlayMode = .orb
    private var isResizing = false
    private var dragStartFrame: NSRect?
    private var cancellables: Set<AnyCancellable> = []

    private let sizes: [AppState.OverlayMode: NSSize] = [
        .orb: NSSize(width: 62, height: 62),
        .voice: NSSize(width: 430, height: 82),
        .response: NSSize(width: 388, height: 182),
        .task: NSSize(width: 374, height: 166),
        .approval: NSSize(width: 388, height: 174)
    ]

    init(
        state: AppState,
        preferences: AssistantPreferences,
        showSettings: @escaping () -> Void,
        quitApp: @escaping () -> Void
    ) {
        self.state = state
        self.preferences = preferences
        panel = FloatingPanel(
            contentRect: NSRect(origin: .zero, size: sizes[.orb] ?? NSSize(width: 62, height: 62)),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        super.init()

        panel.delegate = self
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.hidesOnDeactivate = false
        // SwiftUI owns both click and drag handling. Letting AppKit move a
        // borderless panel by its background can consume the button mouse-up.
        panel.isMovable = false
        panel.isMovableByWindowBackground = false

        let root = AssistantRootView(
            state: state,
            preferences: preferences,
            layoutChanged: { [weak self] mode in self?.setMode(mode) },
            orbDragChanged: { [weak self] translation in self?.dragOrb(by: translation) },
            orbDragEnded: { [weak self] in self?.finishOrbDrag() },
            showSettings: showSettings,
            quitApp: quitApp
        )
        let hostingView = TransparentHostingView(rootView: root)
        hostingView.wantsLayer = true
        hostingView.layer?.backgroundColor = NSColor.clear.cgColor
        hostingView.layer?.isOpaque = false
        panel.contentView = hostingView
        applyContentMask(for: .orb)

        positionInitially()
        preferences.$floatingPlacement
            .removeDuplicates()
            .dropFirst()
            .sink { [weak self] _ in self?.moveToPreferredPlacement(animated: true) }
            .store(in: &cancellables)
        Publishers.CombineLatest3(state.$isExpanded, state.$phase, state.$showPermission)
            .dropFirst()
            .sink { [weak self] _, _, _ in
                DispatchQueue.main.async { [weak self] in
                    self?.synchronizePresentation()
                }
            }
            .store(in: &cancellables)
    }

    func show() {
        panel.orderFrontRegardless()
    }

    func showExpanded() {
        state.isExpanded = true
        setMode(state.overlayMode)
        show()
    }

    private func synchronizePresentation() {
        setMode(state.overlayMode)
        panel.orderFrontRegardless()
    }

    private func setMode(_ newMode: AppState.OverlayMode) {
        guard mode != newMode, let size = sizes[newMode] else { return }
        let oldFrame = panel.frame
        mode = newMode

        guard let screen = panel.screen ?? NSScreen.main else { return }
        let visible = screen.visibleFrame
        let margin: CGFloat = 18
        let x: CGFloat
        let y: CGFloat
        switch preferences.floatingPlacement {
        case .notch:
            x = visible.midX - size.width / 2
            y = visible.maxY - size.height - 8
        case .bottomRight:
            x = visible.maxX - 24 - size.width
            y = min(max(visible.minY + 92, visible.minY + margin), visible.maxY - size.height - margin)
        case .custom:
            let rightAnchored = oldFrame.midX >= visible.midX
            x = rightAnchored ? visible.maxX - margin - size.width : visible.minX + margin
            y = min(
                max(oldFrame.midY - size.height / 2, visible.minY + margin),
                visible.maxY - size.height - margin
            )
        }

        isResizing = true
        applyContentMask(for: newMode)
        panel.setFrame(NSRect(x: x, y: y, width: size.width, height: size.height), display: true, animate: true)
        isResizing = false
    }

    private func applyContentMask(for mode: AppState.OverlayMode) {
        let radius: CGFloat
        switch mode {
        case .orb:
            radius = (sizes[.orb]?.height ?? 62) / 2
        case .voice:
            radius = 0
        case .response:
            radius = 26
        case .task:
            radius = 25
        case .approval:
            radius = 26
        }
        panel.contentView?.wantsLayer = true
        panel.contentView?.layer?.backgroundColor = NSColor.clear.cgColor
        panel.contentView?.layer?.cornerRadius = radius
        panel.contentView?.layer?.cornerCurve = .continuous
        panel.contentView?.layer?.masksToBounds = true
    }

    private func positionInitially() {
        guard let screen = NSScreen.main, let size = sizes[.orb] else { return }
        let origin = preferredOrigin(for: preferences.floatingPlacement, screen: screen, size: size)
        panel.setFrame(NSRect(origin: origin, size: size), display: true)
    }

    private func moveToPreferredPlacement(animated: Bool) {
        guard mode == .orb,
              let screen = panel.screen ?? NSScreen.main,
              let size = sizes[.orb] else { return }
        let origin = preferredOrigin(for: preferences.floatingPlacement, screen: screen, size: size)
        isResizing = true
        panel.setFrame(NSRect(origin: origin, size: size), display: true, animate: animated)
        isResizing = false
    }

    private func preferredOrigin(
        for placement: FloatingPlacement,
        screen: NSScreen,
        size: NSSize
    ) -> NSPoint {
        let visible = screen.visibleFrame
        let raw: NSPoint
        switch placement {
        case .notch:
            raw = NSPoint(x: visible.midX - size.width / 2, y: visible.maxY - size.height - 8)
        case .bottomRight:
            raw = NSPoint(x: visible.maxX - size.width - 24, y: visible.minY + 92)
        case .custom:
            let savedX = UserDefaults.standard.object(forKey: "floatingOrbX") as? Double
            let savedY = UserDefaults.standard.object(forKey: "floatingOrbY") as? Double
            raw = NSPoint(
                x: savedX ?? visible.midX - size.width / 2,
                y: savedY ?? visible.maxY - size.height - 8
            )
        }
        return NSPoint(
            x: min(max(raw.x, visible.minX), visible.maxX - size.width),
            y: min(max(raw.y, visible.minY), visible.maxY - size.height)
        )
    }

    private func dragOrb(by translation: CGSize) {
        guard mode == .orb, let screen = panel.screen ?? NSScreen.main else { return }
        if dragStartFrame == nil { dragStartFrame = panel.frame }
        guard let start = dragStartFrame else { return }

        let visible = screen.visibleFrame
        let proposed = NSPoint(
            x: start.origin.x + translation.width,
            y: start.origin.y - translation.height
        )
        let clamped = NSPoint(
            x: min(max(proposed.x, visible.minX), visible.maxX - start.width),
            y: min(max(proposed.y, visible.minY), visible.maxY - start.height)
        )
        panel.setFrameOrigin(clamped)
    }

    private func finishOrbDrag() {
        dragStartFrame = nil
        UserDefaults.standard.set(panel.frame.origin.x, forKey: "floatingOrbX")
        UserDefaults.standard.set(panel.frame.origin.y, forKey: "floatingOrbY")
        preferences.floatingPlacement = .custom
    }

    func windowDidMove(_ notification: Notification) {
        guard !isResizing, mode == .orb else { return }
        UserDefaults.standard.set(panel.frame.origin.x, forKey: "floatingOrbX")
        UserDefaults.standard.set(panel.frame.origin.y, forKey: "floatingOrbY")
    }
}

final class FloatingPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

final class TransparentHostingView<Content: View>: NSHostingView<Content> {
    override var isOpaque: Bool { false }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
        layer?.isOpaque = false
        window?.isOpaque = false
        window?.backgroundColor = .clear
    }
}
