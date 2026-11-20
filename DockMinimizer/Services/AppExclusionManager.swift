import Foundation
import Cocoa

/// Элемент приложения-исключения для отображения в UI
struct ExcludedAppItem: Identifiable, Equatable {
    var id: String { bundleIdentifier }
    let bundleIdentifier: String
    let name: String
    let icon: NSImage
}

/// Управляет списком приложений, исключённых из принудительного закрытия по ⌘Q
class AppExclusionManager: ObservableObject {
    static let shared = AppExclusionManager()

    private let storageKey = "quitOnCloseExcludedBundleIDs"

    // Предустановленные популярные приложения для новых пользователей
    private let defaultExcludedBundleIDs: [String] = [
        "ru.keepcoder.Telegram",
        "com.tdesktop.Telegram",
        "com.hnc.Discord",
        "com.spotify.client",
        "com.apple.Music"
    ]

    @Published var showSheet: Bool = false

    @Published var excludedBundleIDs: [String] = [] {
        didSet {
            UserDefaults.standard.set(excludedBundleIDs, forKey: storageKey)
            _cachedSet = Set(excludedBundleIDs)
        }
    }

    private var _cachedSet: Set<String> = []

    private init() {
        if let saved = UserDefaults.standard.stringArray(forKey: storageKey) {
            excludedBundleIDs = saved
        } else {
            excludedBundleIDs = defaultExcludedBundleIDs
            UserDefaults.standard.set(defaultExcludedBundleIDs, forKey: storageKey)
        }
        _cachedSet = Set(excludedBundleIDs)
    }

    /// Проверяет, находится ли приложение в списке исключений
    func isExcluded(bundleIdentifier: String) -> Bool {
        return _cachedSet.contains(bundleIdentifier)
    }

    /// Добавляет приложение по Bundle Identifier
    func addApp(bundleIdentifier: String) {
        guard !excludedBundleIDs.contains(bundleIdentifier) else { return }
        excludedBundleIDs.append(bundleIdentifier)
    }

    /// Удаляет приложение из исключений
    func removeApp(bundleIdentifier: String) {
        excludedBundleIDs.removeAll { $0 == bundleIdentifier }
    }

    /// Возвращает список элементов с иконками и именами для отображения в настройках
    func getExcludedAppItems() -> [ExcludedAppItem] {
        return excludedBundleIDs.map { bid in
            if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bid) {
                let name = FileManager.default.displayName(atPath: url.path)
                let icon = NSWorkspace.shared.icon(forFile: url.path)
                return ExcludedAppItem(bundleIdentifier: bid, name: name, icon: icon)
            } else {
                let fallbackName = bid.components(separatedBy: ".").last?.capitalized ?? bid
                let fallbackIcon = NSWorkspace.shared.icon(for: .applicationBundle)
                return ExcludedAppItem(bundleIdentifier: bid, name: fallbackName, icon: fallbackIcon)
            }
        }
    }

    /// Открывает диалог выбора приложения из /Applications
    func addAppViaFilePicker() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.prompt = "Добавить"
        panel.message = "Выберите приложение, которое не должно закрываться по крестику"

        NSApplication.shared.activate(ignoringOtherApps: true)
        if panel.runModal() == .OK, let url = panel.url {
            let bundle = Bundle(url: url)
            let bid = bundle?.bundleIdentifier ?? url.deletingPathExtension().lastPathComponent
            addApp(bundleIdentifier: bid)
        }
    }
}
