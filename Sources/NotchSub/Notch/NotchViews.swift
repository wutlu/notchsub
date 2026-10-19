import SwiftUI

/// Üst kenarı ekrana yapışık, üst köşeleri içbükey, alt köşeleri yuvarlak çentik şekli.
struct NotchShape: Shape {
    var earRadius: CGFloat
    var bottomRadius: CGFloat

    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(earRadius, bottomRadius) }
        set { earRadius = newValue.first; bottomRadius = newValue.second }
    }

    func path(in rect: CGRect) -> Path {
        let w = rect.width, h = rect.height
        let e = earRadius, b = min(bottomRadius, h / 2)
        var path = Path()
        path.move(to: CGPoint(x: 0, y: 0))
        path.addQuadCurve(to: CGPoint(x: e, y: e), control: CGPoint(x: e, y: 0))
        path.addLine(to: CGPoint(x: e, y: h - b))
        path.addQuadCurve(to: CGPoint(x: e + b, y: h), control: CGPoint(x: e, y: h))
        path.addLine(to: CGPoint(x: w - e - b, y: h))
        path.addQuadCurve(to: CGPoint(x: w - e, y: h - b), control: CGPoint(x: w - e, y: h))
        path.addLine(to: CGPoint(x: w - e, y: e))
        path.addQuadCurve(to: CGPoint(x: w, y: 0), control: CGPoint(x: w - e, y: 0))
        path.closeSubpath()
        return path
    }
}

struct NotchActions {
    var togglePause: () -> Void
    var openSettings: () -> Void
    var collapse: () -> Void
    var clear: () -> Void
}

struct NotchRootView: View {
    let state: NotchState
    let store: SubtitleStore
    let settings: AppSettings
    let translator: AppleTranslator
    let actions: NotchActions

    var body: some View {
        let size = state.currentSize
        ZStack(alignment: .top) {
            NotchShape(earRadius: state.earRadius, bottomRadius: state.isExpanded ? 24 : 10)
                .fill(Color.black)
                .frame(width: size.width, height: size.height)
                .shadow(color: .black.opacity(state.isExpanded ? 0.35 : 0), radius: 12, y: 4)

            if state.isExpanded {
                ExpandedContent(store: store, settings: settings, translator: translator, actions: actions)
                    .padding(.top, state.geometry.notchSize.height + 4)
                    .padding(.horizontal, state.earRadius + 18)
                    .padding(.bottom, 14)
                    .frame(width: size.width, height: size.height, alignment: .top)
                    .transition(.opacity.combined(with: .scale(scale: 0.96, anchor: .top)))

                // Açıkken çentiğin kendisine tıklamak bölmeyi kapatır.
                Color.clear
                    .frame(width: state.geometry.notchSize.width, height: state.geometry.notchSize.height)
                    .contentShape(Rectangle())
                    .onTapGesture(perform: actions.collapse)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(alignment: .topLeading) { TranslationHost(translator: translator) }
        .animation(.spring(response: 0.42, dampingFraction: 0.8), value: state.isExpanded)
        .animation(.easeInOut(duration: 0.2), value: state.expandedSize)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: state.isHovering)
        .environment(\.colorScheme, .dark)
    }
}

private struct ExpandedContent: View {
    let store: SubtitleStore
    let settings: AppSettings
    let translator: AppleTranslator
    let actions: NotchActions

    var body: some View {
        VStack(spacing: 10) {
            HeaderBar(store: store, settings: settings, translator: translator, actions: actions)
            SubtitleBody(store: store, settings: settings, translator: translator, openSettings: actions.openSettings)
        }
    }
}

// MARK: - Üst bar

private struct HeaderBar: View {
    let store: SubtitleStore
    let settings: AppSettings
    let translator: AppleTranslator
    let actions: NotchActions

    var body: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(statusColor)
                .frame(width: 7, height: 7)
                .shadow(color: statusColor.opacity(0.8), radius: store.isCapturing ? 4 : 0)
            Text(statusText)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.white.opacity(0.75))
                .lineLimit(1)
            if store.isCapturing {
                LevelMeter(level: store.level)
            }
            Spacer(minLength: 8)
            Text(verbatim: "\(settings.source.short) → \(settings.target.short)")
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(.white.opacity(0.6))
                .padding(.horizontal, 7)
                .padding(.vertical, 2)
                .background(Capsule().fill(.white.opacity(0.1)))
            IconButton(symbol: store.wantsListening ? "pause.fill" : "play.fill",
                       help: store.wantsListening ? L("Pause") : L("Start"), action: actions.togglePause)
            IconButton(symbol: "trash", help: L("Clear"), action: actions.clear)
            IconButton(symbol: "gearshape.fill", help: L("Settings"), action: actions.openSettings)
            IconButton(symbol: "chevron.up", help: L("Close"), action: actions.collapse)
        }
        .frame(height: 20)
    }

    private var statusColor: Color {
        if store.errorMessage != nil { return .orange }
        if store.isCapturing { return .red }
        switch store.engineState {
        case .downloading, .loading: return .yellow
        case .failed: return .orange
        default: return .gray
        }
    }

    private var statusText: String {
        if let error = store.errorMessage { return error }
        switch store.engineState {
        case let .downloading(progress): return L("Downloading model %d%%", Int(progress * 100))
        case .loading: return L("Preparing model (first launch can take a few minutes)…")
        case let .failed(message): return L("Model error: %@", message)
        case .idle: return L("Starting…")
        case .ready: break
        }
        if store.isCapturing { return L("Live") }
        return store.wantsListening ? L("Starting…") : L("Paused")
    }
}

private struct IconButton: View {
    let symbol: String
    let help: String
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white.opacity(hovering ? 1 : 0.6))
                .frame(width: 22, height: 20)
                .background(RoundedRectangle(cornerRadius: 5).fill(.white.opacity(hovering ? 0.14 : 0)))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help)
        .onHover { hovering = $0 }
    }
}

private struct LevelMeter: View {
    let level: Float

    var body: some View {
        let normalized = CGFloat(min(1, sqrt(max(0, level)) * 2.2))
        HStack(spacing: 2) {
            ForEach(0 ..< 5) { index in
                Capsule()
                    .fill(Color.white.opacity(normalized > CGFloat(index) / 5 ? 0.8 : 0.18))
                    .frame(width: 3, height: 4 + CGFloat(index) * 2)
            }
        }
        .animation(.linear(duration: 0.08), value: normalized)
    }
}

// MARK: - Altyazılar

private struct SubtitleBody: View {
    let store: SubtitleStore
    let settings: AppSettings
    let translator: AppleTranslator
    let openSettings: () -> Void

    private var isEmpty: Bool { store.lines.isEmpty && store.partialOriginal.isEmpty }

    var body: some View {
        Group {
            if isEmpty {
                EmptyState(
                    isCapturing: store.isCapturing,
                    notice: notice,
                    openSettings: openSettings
                )
            } else {
                subtitles
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipped()
    }

    private var subtitles: some View {
        let visible = Array(store.lines.suffix(store.partialOriginal.isEmpty ? 3 : 2))
        return VStack(spacing: 10) {
            if let notice {
                NoticePill(text: notice, action: openSettings)
            }
            Spacer(minLength: 0)
            ForEach(Array(visible.enumerated()), id: \.element.id) { index, line in
                let isLatest = store.partialOriginal.isEmpty && index == visible.count - 1
                SubtitleEntry(
                    original: line.original,
                    translation: line.translation,
                    needsTranslation: line.needsTranslation,
                    isPartial: false,
                    settings: settings
                )
                .opacity(isLatest ? 1 : 0.55)
            }
            if !store.partialOriginal.isEmpty {
                SubtitleEntry(
                    original: store.partialOriginal,
                    translation: store.partialTranslation,
                    needsTranslation: store.partialNeedsTranslation,
                    isPartial: true,
                    settings: settings
                )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        .animation(.easeOut(duration: 0.18), value: store.lines)
    }

    private var notice: String? {
        switch translator.packStatus {
        case .notInstalled: L("%@ translation pack is not installed", settings.target.name)
        case .unsupported: L("This language pair can’t be translated on-device")
        default: nil
        }
    }
}

private struct EmptyState: View {
    let isCapturing: Bool
    let notice: String?
    let openSettings: () -> Void

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: isCapturing ? "waveform" : "captions.bubble")
                .font(.system(size: 22, weight: .medium))
                .foregroundStyle(.white.opacity(0.3))
                .symbolEffect(.variableColor.iterative, isActive: isCapturing)
            Text(isCapturing ? L("Waiting for speech on your Mac…") : L("Subtitles will appear here"))
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.white.opacity(0.4))
            if let notice {
                NoticePill(text: notice, action: openSettings)
                    .padding(.top, 4)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct NoticePill: View {
    let text: String
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 10))
                Text(text)
                Text(L("Download in Settings"))
                    .fontWeight(.semibold)
            }
            .font(.system(size: 11.5))
            .foregroundStyle(Color.orange)
            .padding(.horizontal, 12)
            .padding(.vertical, 5)
            .background(Capsule().fill(Color.orange.opacity(hovering ? 0.22 : 0.14)))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}

private struct SubtitleEntry: View {
    let original: String
    let translation: String?
    let needsTranslation: Bool
    let isPartial: Bool
    let settings: AppSettings

    var body: some View {
        let size = settings.fontSize
        VStack(spacing: 3) {
            if needsTranslation {
                Text(translation ?? "…")
                    .font(.system(size: size, weight: .semibold))
                    .foregroundStyle(.white.opacity(isPartial ? 0.75 : (translation == nil ? 0.4 : 1)))
                if settings.showOriginal {
                    Text(original)
                        .font(.system(size: size * 0.78))
                        .italic(isPartial)
                        .foregroundStyle(.white.opacity(isPartial ? 0.4 : 0.55))
                }
            } else {
                Text(original)
                    .font(.system(size: size, weight: .semibold))
                    .foregroundStyle(.white.opacity(isPartial ? 0.75 : 1))
            }
        }
        .lineLimit(2)
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity, alignment: .center)
        .fixedSize(horizontal: false, vertical: true)
    }
}
