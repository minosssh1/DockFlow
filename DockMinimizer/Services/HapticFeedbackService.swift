import AppKit

/// Сервис тактильного отклика (Haptic Feedback) для трекпадов Force Touch и Magic Trackpad
class HapticFeedbackService {
    static let shared = HapticFeedbackService()

    private var _cachedEnabled: Bool?
    var isEnabled: Bool {
        get {
            if let cached = _cachedEnabled { return cached }
            let key = "hapticFeedbackEnabled"
            let val = UserDefaults.standard.object(forKey: key) == nil || UserDefaults.standard.bool(forKey: key)
            _cachedEnabled = val
            return val
        }
        set {
            _cachedEnabled = newValue
            UserDefaults.standard.set(newValue, forKey: "hapticFeedbackEnabled")
        }
    }

    private init() {}

    /// Лёгкий тактильный клик (при сворачивании, среднем клике или закрытии)
    func playTap() {
        guard isEnabled else { return }
        NSHapticFeedbackManager.defaultPerformer.perform(.generic, performanceTime: .now)
    }

    /// Более выраженный тактильный щелчок
    func playAction() {
        guard isEnabled else { return }
        NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
    }
}
