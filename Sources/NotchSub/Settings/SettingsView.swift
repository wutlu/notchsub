import AppKit
import SwiftUI
import Translation

struct SettingsView: View {
    @Bindable var settings: AppSettings
    let store: SubtitleStore
    let translator: AppleTranslator
    var onLanguagesChanged: () -> Void
    var onModelChanged: () -> Void
    var onAppearanceChanged: () -> Void

    @State private var downloadConfig: TranslationSession.Configuration?

    var body: some View {
        Form {
            Section(L("Languages")) {
                Picker(L("Spoken language"), selection: $settings.sourceLanguage) {
                    Text(LanguageOption.auto.name).tag(LanguageOption.auto.code)
                    Divider()
                    ForEach(LanguageOption.spokenLanguages) { Text($0.name).tag($0.code) }
                }
                Picker(L("Translate to"), selection: $settings.targetLanguage) {
                    ForEach(targetOptions) { Text($0.name).tag($0.code) }
                }
                LabeledContent(L("Translation pack")) {
                    HStack {
                        Text(packStatusText)
                            .foregroundStyle(translator.packStatus == .installed ? .green : .secondary)
                        if translator.packStatus == .notInstalled {
                            Button(L("Download")) { requestDownload() }
                        }
                    }
                }
            }

            Section(L("Speech recognition model (Whisper, on-device)")) {
                Picker(L("Model"), selection: $settings.modelVariant) {
                    ForEach(ModelOption.all) { option in
                        Text("\(option.name) — \(option.detail)").tag(option.variant)
                    }
                }
                LabeledContent(L("Status")) { Text(engineStatusText).foregroundStyle(.secondary) }
            }

            Section(L("Appearance")) {
                LabeledContent(L("Text size")) {
                    HStack {
                        Slider(value: $settings.fontSize, in: 13 ... 28, step: 1)
                        Text(verbatim: "\(Int(settings.fontSize)) pt").monospacedDigit().frame(width: 44)
                    }
                }
                Toggle(L("Also show original text"), isOn: $settings.showOriginal)
                Toggle(L("Stay open when clicking outside while listening"), isOn: $settings.keepOpenWhileListening)
            }

            Section {
                Text(L("NotchSub only listens to audio your Mac plays — the microphone is never used. On first launch macOS asks for “System Audio Recording” permission. If you denied it, go to System Settings → Privacy & Security → Screen & System Audio Recording."))
                .font(.callout)
                .foregroundStyle(.secondary)
                Button(L("Open Privacy Settings")) {
                    NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AudioCapture")!)
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 520)
        .fixedSize(horizontal: false, vertical: true)
        .onChange(of: settings.sourceLanguage) { onLanguagesChanged() }
        .onChange(of: settings.targetLanguage) { onLanguagesChanged() }
        .onChange(of: settings.modelVariant) { onModelChanged() }
        .onChange(of: settings.fontSize) { onAppearanceChanged() }
        .onChange(of: settings.showOriginal) { onAppearanceChanged() }
        .task { await translator.refreshStatus() }
        .translationTask(downloadConfig) { session in
            try? await session.prepareTranslation()
            await translator.refreshStatus()
            downloadConfig = nil
        }
    }

    /// Seçili dil listede yoksa (ör. desteklenmeyen sistem dili) yine de göster.
    private var targetOptions: [LanguageOption] {
        let list = translator.targetLanguages
        return list.contains(settings.target) ? list : [settings.target] + list
    }

    private func requestDownload() {
        let source = settings.source == .auto ? Locale.Language(identifier: "en") : settings.source.localeLanguage
        downloadConfig = TranslationSession.Configuration(source: source, target: settings.target.localeLanguage)
    }

    private var packStatusText: String {
        switch translator.packStatus {
        case .installed: L("Installed ✓")
        case .notInstalled: L("Not installed")
        case .unsupported: L("Not supported")
        case .sameLanguage: L("Not needed (same language)")
        case .unknown: L("Checking…")
        }
    }

    private var engineStatusText: String {
        switch store.engineState {
        case .idle: L("Idle")
        case let .downloading(progress): L("Downloading %d%%", Int(progress * 100))
        case .loading: L("Preparing…")
        case .ready: L("Ready ✓")
        case let .failed(message): L("Error: %@", message)
        }
    }
}

@MainActor
final class SettingsWindowController {
    private var window: NSWindow?
    private let makeView: () -> AnyView

    init(makeView: @escaping () -> AnyView) {
        self.makeView = makeView
    }

    func show() {
        if window == nil {
            let controller = NSHostingController(rootView: makeView())
            let window = NSWindow(contentViewController: controller)
            window.title = L("NotchSub Settings")
            window.styleMask = [.titled, .closable]
            window.isReleasedWhenClosed = false
            window.center()
            self.window = window
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}
