import Foundation

/// Arayüz metinleri. Anahtarlar İngilizcedir; çeviriler `Resources/Localization/<dil>.lproj` içindedir
/// ve macOS'un sistem diline göre otomatik seçilir.
func L(_ key: String) -> String {
    NSLocalizedString(key, comment: "")
}

func L(_ key: String, _ arguments: CVarArg...) -> String {
    String(format: NSLocalizedString(key, comment: ""), locale: Locale.current, arguments: arguments)
}

let appName = "NotchSub"
