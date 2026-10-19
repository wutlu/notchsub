import AppKit
import SwiftUI

/// Menü çubuğunun üstünde, çentiğin tam ortasında duran kenarlıksız panel.
final class NotchPanel: NSPanel {
    init() {
        super.init(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        isFloatingPanel = true
        level = NSWindow.Level(rawValue: NSWindow.Level.mainMenu.rawValue + 3)
        backgroundColor = .clear
        isOpaque = false
        hasShadow = false
        isMovable = false
        hidesOnDeactivate = false
        ignoresMouseEvents = true
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    // Menü çubuğunun üstüne yerleşebilmek için sistemin pencereyi aşağı itmesini engelle.
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect {
        frameRect
    }
}

/// Etkin olmayan panelde ilk tıklamanın da butonlara ulaşması için.
final class FirstMouseHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

/// Bir ekranın çentik ölçüleri.
struct NotchGeometry: Equatable {
    var screenFrame: CGRect
    var notchSize: CGSize
    var hasNotch: Bool

    @MainActor
    static func current() -> (NSScreen, NotchGeometry)? {
        let screen = NSScreen.screens.first { $0.safeAreaInsets.top > 0 } ?? NSScreen.main ?? NSScreen.screens.first
        guard let screen else { return nil }
        let frame = screen.frame
        if screen.safeAreaInsets.top > 0,
           let left = screen.auxiliaryTopLeftArea, let right = screen.auxiliaryTopRightArea {
            let width = frame.width - left.width - right.width
            return (screen, NotchGeometry(
                screenFrame: frame,
                notchSize: CGSize(width: width, height: screen.safeAreaInsets.top),
                hasNotch: true
            ))
        }
        // Çentiksiz ekran: menü çubuğu yüksekliğinde sahte bir çentik.
        let menuBar = max(frame.maxY - screen.visibleFrame.maxY, 24)
        return (screen, NotchGeometry(
            screenFrame: frame,
            notchSize: CGSize(width: 180, height: menuBar),
            hasNotch: false
        ))
    }

    /// Fareyle açılmayı tetikleyen bölge.
    var hotZone: CGRect {
        CGRect(
            x: screenFrame.midX - notchSize.width / 2 - 10,
            y: screenFrame.maxY - notchSize.height,
            width: notchSize.width + 20,
            height: notchSize.height
        )
    }
}
