import AppKit
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let settings = AppSettings.shared
    private lazy var controller = AppController(settings: settings)
    private var notch: NotchWindowController!
    private var settingsWindow: SettingsWindowController!
    private var statusItem: NSStatusItem!
    private var listenMenuItem: NSMenuItem!

    func applicationDidFinishLaunching(_ notification: Notification) {
        let controller = controller
        let settings = settings

        settingsWindow = SettingsWindowController { [weak self] in
            AnyView(SettingsView(
                settings: settings,
                store: controller.store,
                translator: controller.translator,
                onLanguagesChanged: { controller.languagesChanged() },
                onModelChanged: { controller.loadModel() },
                onAppearanceChanged: { self?.notch.updateSize(fontSize: settings.fontSize, showOriginal: settings.showOriginal) }
            ))
        }

        notch = NotchWindowController { [unowned self] state in
            NotchRootView(
                state: state,
                store: controller.store,
                settings: settings,
                translator: controller.translator,
                actions: NotchActions(
                    togglePause: { controller.toggleListening() },
                    openSettings: { [weak self] in self?.settingsWindow.show() },
                    collapse: { [weak self] in
                        controller.stopListening()
                        self?.notch.collapse(userInitiated: true)
                    },
                    clear: { controller.store.clearAll() }
                )
            )
        }
        notch.onExpand = { controller.startListening() }
        notch.onCollapse = {
            if !(settings.keepOpenWhileListening && controller.store.wantsListening) {
                controller.stopListening()
            }
        }
        notch.shouldStayOpen = { settings.keepOpenWhileListening && controller.store.wantsListening }
        notch.show(fontSize: settings.fontSize, showOriginal: settings.showOriginal)

        setupStatusItem()
        controller.bootstrap()
        // Geliştirme: `open NotchSub.app --args --open` bölmeyi açık başlatır.
        if CommandLine.arguments.contains("--open") { notch.expand() }
    }

    // MARK: - Menü çubuğu

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(systemSymbolName: "captions.bubble", accessibilityDescription: "NotchSub")

        let menu = NSMenu()
        listenMenuItem = NSMenuItem(title: L("Start Subtitles"), action: #selector(toggleListening), keyEquivalent: "")
        listenMenuItem.target = self
        menu.addItem(listenMenuItem)
        let settingsItem = NSMenuItem(title: L("Settings…"), action: #selector(openSettings), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: L("Quit NotchSub"), action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        menu.delegate = self
        statusItem.menu = menu
    }

    @objc private func toggleListening() {
        if controller.store.wantsListening {
            controller.stopListening()
            notch.collapse(userInitiated: false)
        } else {
            notch.expand()
            controller.startListening()
        }
    }

    @objc private func openSettings() {
        settingsWindow.show()
    }
}

extension AppDelegate: NSMenuDelegate {
    func menuWillOpen(_ menu: NSMenu) {
        listenMenuItem.title = controller.store.wantsListening ? L("Stop Subtitles") : L("Start Subtitles")
    }
}
