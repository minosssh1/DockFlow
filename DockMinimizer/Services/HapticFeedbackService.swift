import AppKit
import os

/// Haptic feedback service for Force Touch and Magic Trackpad devices.
final class HapticFeedbackService: ObservableObject {
    static let shared = HapticFeedbackService()

    private static let prefKey = "hapticFeedbackEnabled"
    private let enabledLock = OSAllocatedUnfairLock<Bool>(initialState: true)

    @Published var isEnabled: Bool {
        didSet {
            enabledLock.withLock { $0 = isEnabled }
            UserDefaults.standard.set(isEnabled, forKey: Self.prefKey)
        }
    }

    private init() {
        let initial = Self.readDefault()
        self.isEnabled = initial
        self.enabledLock.withLock { $0 = initial }
    }

    private static func readDefault() -> Bool {
        UserDefaults.standard.object(forKey: prefKey) == nil || UserDefaults.standard.bool(forKey: prefKey)
    }

    /// Refreshes state after legacy preferences migration.
    func reloadPreference() {
        let val = Self.readDefault()
        enabledLock.withLock { $0 = val }
        if Thread.isMainThread {
            if isEnabled != val { isEnabled = val }
        } else {
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                if self.isEnabled != val { self.isEnabled = val }
            }
        }
    }

    /// Plays a gentle generic tap on the trackpad.
    func playTap() {
        guard enabledLock.withLock({ $0 }) else { return }
        DispatchQueue.main.async {
            NSHapticFeedbackManager.defaultPerformer.perform(.generic, performanceTime: .now)
        }
    }

    /// Plays a stronger alignment haptic click.
    func playAction() {
        guard enabledLock.withLock({ $0 }) else { return }
        DispatchQueue.main.async {
            NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
        }
    }
}
