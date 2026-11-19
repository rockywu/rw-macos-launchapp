import Foundation

enum AppLanguage: String {
    case english = "en"
    case chinese = "zh-Hans"

    static func system(preferredLanguages: [String] = Locale.preferredLanguages) -> Self {
        // Follow the primary system language. Unsupported languages use English.
        guard let first = preferredLanguages.first,
              Locale(identifier: first).language.languageCode?.identifier == "zh" else { return .english }
        return .chinese
    }

    private static let chineseBundle = Bundle.main.url(forResource: "zh-Hans", withExtension: "lproj")
        .flatMap { Bundle(url: $0) }

    func text(_ english: String) -> String {
        guard self == .chinese else { return english }
        return Self.chineseBundle?.localizedString(forKey: english, value: english, table: nil) ?? english
    }
}

enum LanguagePreference: String, CaseIterable {
    case system, english, chinese

    var language: AppLanguage {
        switch self {
        case .system: return .system()
        case .english: return .english
        case .chinese: return .chinese
        }
    }

    func label(in language: AppLanguage) -> String {
        switch self {
        case .system: return language.text("System")
        case .english: return "English"
        case .chinese: return "简体中文"
        }
    }
}
