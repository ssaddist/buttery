import Foundation

enum AppLanguage: String, Codable, CaseIterable, Identifiable {
    case en, ru

    var id: String { rawValue }
    var title: String { self == .ru ? "Русский" : "English" }

    func t(_ en: String, _ ru: String) -> String { self == .ru ? ru : en }
}
