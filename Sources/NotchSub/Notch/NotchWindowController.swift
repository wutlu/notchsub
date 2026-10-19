import AppKit
import SwiftUI

/// Paneli konumlandırır, fareyi izler ve bölmeyi açıp kapatır.
@MainActor
final class NotchWindowController {
    let state = NotchState()
    var onExpand: (() -> Void)?
    var onCollapse: (() -> Void)?
    /// `true` döndüğü sürece dışarı tıklanınca bölme kapanmaz.
    var shouldStayOpen: () -> Bool = { false }

    private let panel = NotchPanel()
    private var timer: Timer?
    private var clickMonitor: Any?

    init<Content: View>(content: (NotchState) -> Content) {
        let hosting = FirstMouseHostingView(rootView: content(state))
        hosting.sizingOptions = []
        panel.contentView = hosting

        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.layout() }
        }
    }

    func show(fontSize: Double, showOriginal: Bool) {
        updateSize(fontSize: fontSize, showOriginal: showOriginal)
        panel.orderFrontRegardless()
        startTracking()
    }

    func updateSize(fontSize: Double, showOriginal: Bool) {
        if let (_, geometry) = NotchGeometry.current() { state.geometry = geometry }
        state.expandedSize = NotchState.expandedSize(
            notch: state.geometry.notchSize, fontSize: fontSize, showOriginal: showOriginal
        )
        layout()
    }

    private func layout() {
        if let (_, geometry) = NotchGeometry.current() { state.geometry = geometry }
        let size = state.expandedSize
        let screen = state.geometry.screenFrame
        panel.setFrame(
            CGRect(x: screen.midX - size.width / 2, y: screen.maxY - size.height, width: size.width, height: size.height),
            display: true
        )
    }

    // MARK: - Fare takibi

    private func startTracking() {
        // Tıklayarak açma: panel kapalıyken tıklamalar menü çubuğuna gider, global izleyici yakalar.
        // (Fare tıklamalarını izlemek erişilebilirlik izni gerektirmez.)
        clickMonitor = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDown) { [weak self] _ in
            MainActor.assumeIsolated { self?.handleClick(at: NSEvent.mouseLocation) }
        }

        // Üzerine gelince çentiği hafifçe büyüt: tıklanabilir olduğunu belli et.
        timer?.invalidate()
        let timer = Timer(timeInterval: 1.0 / 30, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.updateHover() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func updateHover() {
        let hovering = !state.isExpanded && state.geometry.hotZone.contains(NSEvent.mouseLocation)
        if state.isHovering != hovering { state.isHovering = hovering }
    }

    private func handleClick(at point: CGPoint) {
        if !state.isExpanded {
            if state.geometry.hotZone.contains(point) { expand() }
        } else if !panel.frame.contains(point), !shouldStayOpen() {
            collapse(userInitiated: false)
        }
    }

    func expand() {
        guard !state.isExpanded else { return }
        layout()
        state.isHovering = false
        state.isExpanded = true
        panel.ignoresMouseEvents = false
        onExpand?()
    }

    func collapse(userInitiated: Bool) {
        guard state.isExpanded else { return }
        state.isExpanded = false
        panel.ignoresMouseEvents = true
        onCollapse?()
    }

    func toggle() {
        state.isExpanded ? collapse(userInitiated: true) : expand()
    }
}
