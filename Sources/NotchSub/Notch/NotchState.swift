import CoreGraphics
import Observation

@MainActor
@Observable
final class NotchState {
    var isExpanded = false
    var isHovering = false
    var geometry = NotchGeometry(screenFrame: .zero, notchSize: CGSize(width: 180, height: 32), hasNotch: false)
    var expandedSize = CGSize(width: 640, height: 200)

    /// Üst köşelerdeki içbükey "kulak" yarıçapı.
    var earRadius: CGFloat { isExpanded ? 14 : 6 }

    var collapsedSize: CGSize {
        let grow: CGFloat = isHovering ? 1 : 0
        return CGSize(width: geometry.notchSize.width + 12 + grow * 16, height: geometry.notchSize.height + grow * 5)
    }

    var currentSize: CGSize { isExpanded ? expandedSize : collapsedSize }

    /// Altyazı alanının yüksekliğini yazı boyutuna göre hesaplar.
    static func expandedSize(notch: CGSize, fontSize: Double, showOriginal: Bool) -> CGSize {
        let translationLine = fontSize * 1.3
        let originalLine = showOriginal ? fontSize * 0.78 * 1.3 + 2 : 0
        let entry = translationLine * 1.6 + originalLine + 6 // çeviri ~1.6 satır ortalama
        let body = entry * 3
        let header: CGFloat = 26
        let height = notch.height + header + body + 22
        let width = max(notch.width + 360, min(820, 520 + fontSize * 12))
        return CGSize(width: width.rounded(), height: height.rounded())
    }
}
