import Foundation
import SwiftUI
import Combine

enum AppLanguage: String, CaseIterable, Identifiable {
    case system = ""
    case english = "en"
    case russian = "ru"
    case simplifiedChinese = "zh-Hans"
    case ukrainian = "uk"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .system:
            switch LocalizationManager.effectiveLanguageCode() {
            case "ru": return "🌐 Системный"
            case "uk": return "🌐 Системна"
            case "zh-Hans": return "🌐 跟随系统"
            default: return "🌐 System"
            }
        case .english: return "🇺🇸 English"
        case .russian: return "🇷🇺 Русский"
        case .simplifiedChinese: return "🇨🇳 简体中文"
        case .ukrainian: return "🇺🇦 Українська"
        }
    }
}

class LocalizationManager: ObservableObject {
    static let shared = LocalizationManager()

    @Published var currentLanguage: AppLanguage {
        didSet {
            UserDefaults.standard.set(currentLanguage.rawValue, forKey: "appLanguage")
        }
    }

    private init() {
        let saved = UserDefaults.standard.string(forKey: "appLanguage") ?? ""
        self.currentLanguage = AppLanguage(rawValue: saved) ?? .system
    }

    func reloadPreference() {
        let saved = UserDefaults.standard.string(forKey: "appLanguage") ?? ""
        let target = AppLanguage(rawValue: saved) ?? .system
        if currentLanguage != target {
            currentLanguage = target
        }
    }

    static func effectiveLanguageCode() -> String {
        let saved = UserDefaults.standard.string(forKey: "appLanguage") ?? ""
        if !saved.isEmpty {
            return saved
        }
        let preferred = Locale.preferredLanguages.first?.lowercased() ?? "en"
        if preferred.hasPrefix("uk") {
            return "uk"
        } else if preferred.hasPrefix("ru") {
            return "ru"
        } else if preferred.hasPrefix("zh") {
            return "zh-Hans"
        } else {
            return "en"
        }
    }

    var activeLanguageCode: String {
        if currentLanguage == .system {
            return Self.effectiveLanguageCode()
        }
        return currentLanguage.rawValue
    }

    func text(ru: String, en: String, zh: String, uk: String) -> String {
        switch activeLanguageCode {
        case "en": return en
        case "zh-Hans": return zh
        case "uk": return uk
        default: return ru
        }
    }
}

enum L10n {
    private static var lm: LocalizationManager { LocalizationManager.shared }

    // Header
    static var subtitle: String {
        lm.text(
            ru: "Управление Доком и закрытие окон (⌘Q)",
            en: "Dock window management and quit on close (⌘Q)",
            zh: "Dock 窗口管理与快捷退出 (⌘Q)",
            uk: "Керування Доком та закриття вікон (⌘Q)"
        )
    }

    static var runningInBackground: String {
        lm.text(
            ru: "Работает в фоновом режиме",
            en: "Running in background",
            zh: "后台运行中",
            uk: "Працює у фоновому режимі"
        )
    }

    // Section 1
    static var genieTitle: String {
        lm.text(
            ru: "Эффект Джинна в Доке",
            en: "Genie Effect in Dock",
            zh: "Dock 神奇效果",
            uk: "Ефект Джина в Доку"
        )
    }

    static var genieSubtitle: String {
        lm.text(
            ru: "Клик по иконке активного приложения в Доке плавно сворачивает его с анимацией",
            en: "Clicking the active app icon in Dock smoothly minimizes it with animation",
            zh: "点击 Dock 中活动应用的图标以动画平滑最小化窗口",
            uk: "Клік по іконці активної програми в Доку плавно згортає її з анімацією"
        )
    }

    static var hapticTitle: String {
        lm.text(
            ru: "Тактильный отклик (Haptic)",
            en: "Haptic Feedback",
            zh: "触觉反馈 (Haptic)",
            uk: "Тактильний відгук (Haptic)"
        )
    }

    static var hapticSubtitle: String {
        lm.text(
            ru: "Виброотклик трекпада Force Touch при сворачивании и закрытии окон",
            en: "Force Touch trackpad vibration when minimizing or closing windows",
            zh: "最小化或关闭窗口时 Force Touch 触控板震动反馈",
            uk: "Вібровідгук трекпада Force Touch при згортанні та закритті вікон"
        )
    }

    static var middleClickTitle: String {
        lm.text(
            ru: "Клик колёсиком по Доку",
            en: "Middle-Click on Dock",
            zh: "Dock 图标中键点击",
            uk: "Клік коліщатком по Доку"
        )
    }

    static var middleClickSubtitle: String {
        lm.text(
            ru: "Действие при среднем клике по иконке приложения",
            en: "Action when middle-clicking an application icon",
            zh: "中键点击应用程序图标时的操作",
            uk: "Дія при середньому кліку по іконці програми"
        )
    }

    static var middleClickNewWindow: String {
        lm.text(
            ru: "Новое окно (⌘N)",
            en: "New Window (⌘N)",
            zh: "新建窗口 (⌘N)",
            uk: "Нове вікно (⌘N)"
        )
    }

    static var middleClickQuitApp: String {
        lm.text(
            ru: "Завершить (⌘Q)",
            en: "Quit App (⌘Q)",
            zh: "退出程序 (⌘Q)",
            uk: "Завершити (⌘Q)"
        )
    }

    static var middleClickHideApp: String {
        lm.text(
            ru: "Скрыть (⌘H)",
            en: "Hide (⌘H)",
            zh: "隐藏程序 (⌘H)",
            uk: "Сховати (⌘H)"
        )
    }

    static var middleClickDisabled: String {
        lm.text(
            ru: "Отключено",
            en: "Disabled",
            zh: "已禁用",
            uk: "Вимкнено"
        )
    }

    static var quitOnCloseTitle: String {
        lm.text(
            ru: "Полное закрытие по крестику (⌘Q)",
            en: "Quit on Close Button (⌘Q)",
            zh: "点击红叉彻底退出 (⌘Q)",
            uk: "Повне закриття по хрестику (⌘Q)"
        )
    }

    static var quitOnCloseSubtitle: String {
        lm.text(
            ru: "Завершает приложение, когда закрывается его последнее окно. Вкладки сохраняются!",
            en: "Quits the app when its last window is closed. Tabs and sessions are preserved!",
            zh: "关闭最后一个窗口时彻底退出应用。标签页和会话完好保留！",
            uk: "Завершує програму при закритті її останнього вікна. Вкладки зберігаються!"
        )
    }

    static var exclusionsTitle: String {
        lm.text(
            ru: "Исключения закрытия (⌘Q)",
            en: "Close Exclusions (⌘Q)",
            zh: "退出排除列表 (⌘Q)",
            uk: "Винятки закриття (⌘Q)"
        )
    }

    static func exclusionsSubtitle(count: Int) -> String {
        switch lm.activeLanguageCode {
        case "en":
            return "\(count) apps stay running in background"
        case "zh-Hans":
            return "\(count) 个应用保持后台运行"
        case "uk":
            return "\(count) програм залишаються працювати у фоні"
        default:
            return "\(count) приложений остаются работать в фоне"
        }
    }

    static var configure: String {
        lm.text(
            ru: "Настроить...",
            en: "Configure...",
            zh: "设置...",
            uk: "Налаштувати..."
        )
    }

    // Section 2: System Settings
    static var launchAtLoginTitle: String {
        lm.text(
            ru: "Запуск при входе в систему",
            en: "Launch at Login",
            zh: "开机自启动",
            uk: "Запуск під час входу в систему"
        )
    }

    static var launchAtLoginSubtitle: String {
        lm.text(
            ru: "Автоматически запускать DockFlow при включении Mac",
            en: "Automatically start DockFlow when you log in",
            zh: "Mac 开机时自动启动 DockFlow",
            uk: "Автоматично запускати DockFlow при включенні Mac"
        )
    }

    static var showPanelOnLaunchTitle: String {
        lm.text(
            ru: "Показывать окно при старте",
            en: "Show Panel on Launch",
            zh: "启动时显示设置窗口",
            uk: "Показувати вікно під час старту"
        )
    }

    static var showPanelOnLaunchSubtitle: String {
        lm.text(
            ru: "Открывать это окно настроек при каждом запуске системы",
            en: "Open this settings window whenever the system starts",
            zh: "每次系统启动时显示此设置窗口",
            uk: "Відкривати це вікно налаштувань під час кожного запуску системи"
        )
    }

    static var languageTitle: String {
        lm.text(
            ru: "Язык интерфейса",
            en: "Interface Language",
            zh: "界面语言",
            uk: "Мова інтерфейсу"
        )
    }

    static var languageSubtitle: String {
        lm.text(
            ru: "Выберите язык приложения",
            en: "Select application language",
            zh: "选择应用程序语言",
            uk: "Виберіть мову програми"
        )
    }

    // Section 3: Accessibility
    static var accessibilityTitle: String {
        lm.text(
            ru: "Универсальный доступ",
            en: "Accessibility",
            zh: "辅助功能权限",
            uk: "Універсальний доступ"
        )
    }

    static var accessibilityGranted: String {
        lm.text(
            ru: "Доступ предоставлен, все системные функции активны",
            en: "Permission granted, all system features active",
            zh: "已获得权限，所有系统功能正常运作",
            uk: "Доступ надано, всі системні функції активні"
        )
    }

    static var accessibilityRequired: String {
        lm.text(
            ru: "Требуется разрешение для перехвата кликов по Доку",
            en: "Permission required to intercept Dock clicks",
            zh: "需要权限以检测和处理 Dock 点击",
            uk: "Потрібен дозвіл для перехоплення кліків по Доку"
        )
    }

    static var setup: String {
        lm.text(
            ru: "Настроить",
            en: "Configure",
            zh: "去设置",
            uk: "Налаштувати"
        )
    }

    // Footer
    static var close: String {
        lm.text(
            ru: "Закрыть",
            en: "Close",
            zh: "关闭",
            uk: "Закрити"
        )
    }

    static var quitApp: String {
        lm.text(
            ru: "Завершить",
            en: "Quit",
            zh: "退出程序",
            uk: "Завершити"
        )
    }

    static var done: String {
        lm.text(
            ru: "Готово",
            en: "Done",
            zh: "完成",
            uk: "Готово"
        )
    }

    // Exclusions Sheet
    static var exclusionsHeaderTitle: String {
        lm.text(
            ru: "Исключения закрытия по крестику",
            en: "Quit on Close Exclusions",
            zh: "红叉退出排除列表",
            uk: "Винятки закриття по хрестику"
        )
    }

    static var exclusionsHeaderSubtitle: String {
        lm.text(
            ru: "Эти приложения не завершаются (⌘Q) при закрытии окна и продолжают работать в фоне",
            en: "These apps will not quit (⌘Q) when their window is closed and will stay in background",
            zh: "关闭窗口时这些应用不会退出 (⌘Q)，而是继续在后台运行",
            uk: "Ці програми не завершуються (⌘Q) при закритті вікна та продовжують працювати у фоні"
        )
    }

    static var exclusionsEmptyTitle: String {
        lm.text(
            ru: "Список исключений пуст",
            en: "Exclusions list is empty",
            zh: "排除列表为空",
            uk: "Список винятків порожній"
        )
    }

    static var exclusionsEmptySubtitle: String {
        lm.text(
            ru: "Все приложения будут завершаться по крестику",
            en: "All applications will quit when close button is clicked",
            zh: "所有应用在点击红叉时都将退出",
            uk: "Всі програми будуть завершуватися по хрестику"
        )
    }

    static var quickAdd: String {
        lm.text(
            ru: "Быстрое добавление:",
            en: "Quick Add:",
            zh: "快速添加：",
            uk: "Швидке додавання:"
        )
    }

    static var addApplication: String {
        lm.text(
            ru: "Добавить приложение...",
            en: "Add Application...",
            zh: "添加应用程序...",
            uk: "Додати програму..."
        )
    }

    static var deleteHelp: String {
        lm.text(
            ru: "Удалить из исключений",
            en: "Remove from exclusions",
            zh: "从排除列表中移除",
            uk: "Видалити з винятків"
        )
    }

    static var musicPreset: String {
        lm.text(
            ru: "Музыка",
            en: "Music",
            zh: "音乐",
            uk: "Музика"
        )
    }

    // Menu Bar Menu
    static var dockFlowActive: String {
        lm.text(
            ru: "DockFlow активен",
            en: "DockFlow is active",
            zh: "DockFlow 运行中",
            uk: "DockFlow активний"
        )
    }

    static var settings: String {
        lm.text(
            ru: "Настройки...",
            en: "Settings...",
            zh: "设置...",
            uk: "Налаштування..."
        )
    }

    static var quitOnCloseMenu: String {
        lm.text(
            ru: "Закрывать по крестику (⌘Q)",
            en: "Quit on close (⌘Q)",
            zh: "红叉退出 (⌘Q)",
            uk: "Закривати по хрестику (⌘Q)"
        )
    }

    static var checkPermissions: String {
        lm.text(
            ru: "Проверить разрешения",
            en: "Check Permissions",
            zh: "检查权限",
            uk: "Перевірити дозволи"
        )
    }

    static var viewLogs: String {
        lm.text(
            ru: "Журнал работы",
            en: "View Logs",
            zh: "查看日志",
            uk: "Журнал роботи"
        )
    }

    static var checkForUpdates: String {
        lm.text(
            ru: "Проверить обновления...",
            en: "Check for Updates...",
            zh: "检查更新...",
            uk: "Перевірити оновлення..."
        )
    }

    static var quit: String {
        lm.text(
            ru: "Завершить DockFlow (⌘Q)",
            en: "Quit DockFlow (⌘Q)",
            zh: "退出 DockFlow (⌘Q)",
            uk: "Завершити DockFlow (⌘Q)"
        )
    }

    static var updateAvailable: String {
        lm.text(
            ru: "Доступно обновление",
            en: "Update Available",
            zh: "有新版本可用",
            uk: "Доступне оновлення"
        )
    }

    static var updateError: String {
        lm.text(
            ru: "Ошибка проверки обновлений",
            en: "Update Check Error",
            zh: "检查更新失败",
            uk: "Помилка перевірки оновлень"
        )
    }

    static var alreadyUpToDate: String {
        lm.text(
            ru: "У вас установлена последняя версия",
            en: "You're up to date",
            zh: "已是最新版本",
            uk: "У вас встановлена остання версія"
        )
    }

    static var currentVersion: String {
        lm.text(
            ru: "Текущая версия",
            en: "Current version",
            zh: "当前版本",
            uk: "Поточна версія"
        )
    }

    // System alerts & notifications
    static var permissionRequiredTitle: String {
        lm.text(
            ru: "Требуется Универсальный доступ",
            en: "Accessibility Permission Required",
            zh: "需要辅助功能权限",
            uk: "Потрібен Універсальний доступ"
        )
    }

    static var permissionRequiredMessage: String {
        lm.text(
            ru: "DockFlow нужен доступ к Универсальному доступу для сворачивания окон через Док и полного закрытия по крестику.",
            en: "DockFlow requires accessibility permission to monitor and operate windows of applications.",
            zh: "DockFlow 需要辅助功能权限以监控和操作应用程序窗口。",
            uk: "DockFlow потрібен доступ до Універсального доступу для згортання вікон через Док та повного закриття по хрестику."
        )
    }

    static var openSystemSettings: String {
        lm.text(
            ru: "Открыть Системные настройки",
            en: "Open System Settings",
            zh: "打开系统设置",
            uk: "Відкрити Системні параметри"
        )
    }

    static var later: String {
        lm.text(
            ru: "Позже",
            en: "Later",
            zh: "稍后",
            uk: "Пізніше"
        )
    }

    static var permissionGrantedTitle: String {
        lm.text(
            ru: "Доступ предоставлен",
            en: "Permission Granted",
            zh: "权限已获得",
            uk: "Доступ надано"
        )
    }

    static var permissionGrantedMessage: String {
        lm.text(
            ru: "DockFlow получил разрешение Универсального доступа и полностью готов к работе.",
            en: "DockFlow has been granted accessibility permission and is fully operational.",
            zh: "DockFlow 已获得辅助功能权限，所有功能正常可用。",
            uk: "DockFlow отримав дозвіл Універсального доступу і повністю готовий до роботи."
        )
    }

    static var permissionGrantedNotificationTitle: String {
        lm.text(
            ru: "Доступ предоставлен",
            en: "Permission Granted",
            zh: "权限已授权",
            uk: "Доступ надано"
        )
    }

    static var permissionGrantedNotificationBody: String {
        lm.text(
            ru: "Разрешение получено, все функции DockFlow активны.",
            en: "Accessibility permission granted, DockFlow is now active.",
            zh: "已获得辅助功能权限，DockFlow 已启用。",
            uk: "Дозвіл отримано, всі функції DockFlow активні."
        )
    }

    static var permissionRevoked: String {
        lm.text(
            ru: "Доступ отозван",
            en: "Permission Revoked",
            zh: "权限被撤销",
            uk: "Доступ відкликано"
        )
    }

    static var permissionRevokedMessage: String {
        lm.text(
            ru: "Разрешение Универсального доступа отозвано в настройках.",
            en: "Accessibility permission was revoked in system settings.",
            zh: "系统设置中辅助功能权限已被撤销。",
            uk: "Дозвіл Універсального доступу відкликано в налаштуваннях."
        )
    }

    static var ok: String {
        lm.text(
            ru: "ОК",
            en: "OK",
            zh: "确定",
            uk: "ОК"
        )
    }

    static var settingsWindowTitle: String { "DockFlow" }

    // Additional Settings Controls
    static var loggingTitle: String {
        lm.text(
            ru: "Диагностический журнал",
            en: "Diagnostic Logging",
            zh: "诊断日志",
            uk: "Діагностичний журнал"
        )
    }

    static var loggingSubtitle: String {
        lm.text(
            ru: "Записывать события работы в ~/Library/Logs/DockFlow/",
            en: "Write runtime diagnostics to ~/Library/Logs/DockFlow/",
            zh: "将运行日志写入 ~/Library/Logs/DockFlow/",
            uk: "Записувати події роботи в ~/Library/Logs/DockFlow/"
        )
    }

    static var updatePolicyTitle: String {
        lm.text(
            ru: "Проверка обновлений",
            en: "Update Check",
            zh: "更新检查",
            uk: "Перевірка оновлень"
        )
    }

    static var updatePolicySubtitle: String {
        lm.text(
            ru: "Частота автоматического поиска новых версий на GitHub",
            en: "How often to check GitHub for new releases",
            zh: "自动在 GitHub 上检查新版本的频率",
            uk: "Частота автоматичного пошуку нових версій на GitHub"
        )
    }

    static var updatePolicyOnStartup: String {
        lm.text(
            ru: "При запуске",
            en: "On Startup",
            zh: "启动时",
            uk: "Під час запуску"
        )
    }

    static var updatePolicyDaily: String {
        lm.text(
            ru: "Ежедневно",
            en: "Daily",
            zh: "每天",
            uk: "Щодня"
        )
    }

    static var updatePolicyWeekly: String {
        lm.text(
            ru: "Еженедельно",
            en: "Weekly",
            zh: "每周",
            uk: "Щотижня"
        )
    }

    static var updatePolicyDisabled: String {
        lm.text(
            ru: "Отключено",
            en: "Disabled",
            zh: "已禁用",
            uk: "Вимкнено"
        )
    }

    // File Picker & Exclusions Window
    static var exclusionsWindowTitle: String {
        lm.text(
            ru: "Исключения закрытия (⌘Q) — DockFlow",
            en: "Quit Exclusions (⌘Q) — DockFlow",
            zh: "退出排除列表 (⌘Q) — DockFlow",
            uk: "Винятки закриття (⌘Q) — DockFlow"
        )
    }

    static var filePickerAddButton: String {
        lm.text(
            ru: "Добавить",
            en: "Add",
            zh: "添加",
            uk: "Додати"
        )
    }

    static var filePickerMessage: String {
        lm.text(
            ru: "Выберите приложение, которое не должно завершаться по крестику",
            en: "Choose an application that should stay running when its window is closed",
            zh: "选择关闭窗口后仍保留后台运行的应用程序",
            uk: "Виберіть програму, яка не повинна завершуватися по хрестику"
        )
    }

    // OTA Update Alerts & Progress Window
    static var updateAlertTitle: String {
        lm.text(
            ru: "Доступно обновление DockFlow!",
            en: "DockFlow Update Available!",
            zh: "DockFlow 有新版本可用！",
            uk: "Доступне оновлення DockFlow!"
        )
    }

    static func updateAlertMessage(current: String, latest: String) -> String {
        switch lm.activeLanguageCode {
        case "en":
            return "Current version: \(current)\nLatest version: \(latest)\n\nWould you like to install this update now?"
        case "zh-Hans":
            return "当前版本：\(current)\n最新版本：\(latest)\n\n是否立即安装更新？"
        case "uk":
            return "Поточна версія: \(current)\nНова версія: \(latest)\n\nБажаєте встановити оновлення зараз?"
        default:
            return "Текущая версия: \(current)\nНовая версия: \(latest)\n\nХотите установить обновление сейчас?"
        }
    }

    static var updateNow: String {
        lm.text(
            ru: "Обновить сейчас",
            en: "Update Now",
            zh: "立即更新",
            uk: "Оновити зараз"
        )
    }

    static var updateWindowTitle: String {
        lm.text(
            ru: "Обновление DockFlow",
            en: "Updating DockFlow",
            zh: "正在更新 DockFlow",
            uk: "Оновлення DockFlow"
        )
    }

    static func updateWindowHeader(version: String) -> String {
        switch lm.activeLanguageCode {
        case "en":
            return "Updating DockFlow \(version)"
        case "zh-Hans":
            return "正在更新 DockFlow \(version)"
        case "uk":
            return "Оновлення DockFlow \(version)"
        default:
            return "Обновление DockFlow \(version)"
        }
    }

    static var updateStagePreparing: String {
        lm.text(
            ru: "Подготовка...",
            en: "Preparing...",
            zh: "准备中...",
            uk: "Підготовка..."
        )
    }

    static var updateStageInit: String {
        lm.text(
            ru: "Инициализация соединения...",
            en: "Initializing connection...",
            zh: "正在初始化连接...",
            uk: "Ініціалізація з'єднання..."
        )
    }

    static var updateStageConnecting: String {
        lm.text(
            ru: "Этап 1 из 3: Подключение к GitHub...",
            en: "Step 1 of 3: Connecting to GitHub...",
            zh: "第 1 步（共 3 步）：正在连接 GitHub...",
            uk: "Крок 1 з 3: Підключення до GitHub..."
        )
    }

    static var updateStageSecureConnection: String {
        lm.text(
            ru: "Установка безопасного соединения...",
            en: "Establishing secure connection...",
            zh: "正在建立安全连接...",
            uk: "Встановлення захищеного з'єднання..."
        )
    }

    static var updateStageDownloading: String {
        lm.text(
            ru: "Этап 1 из 3: Скачивание обновления...",
            en: "Step 1 of 3: Downloading update...",
            zh: "第 1 步（共 3 步）：正在下载更新...",
            uk: "Крок 1 з 3: Завантаження оновлення..."
        )
    }

    static func updateDownloadProgress(writtenMB: Double, totalMB: Double, percent: Int) -> String {
        switch lm.activeLanguageCode {
        case "en":
            return String(format: "Downloaded %.1f MB of %.1f MB (%d%%)", writtenMB, totalMB, percent)
        case "zh-Hans":
            return String(format: "已下载 %.1f MB / %.1f MB (%d%%)", writtenMB, totalMB, percent)
        case "uk":
            return String(format: "Завантажено %.1f МБ з %.1f МБ (%d%%)", writtenMB, totalMB, percent)
        default:
            return String(format: "Загружено %.1f МБ из %.1f МБ (%d%%)", writtenMB, totalMB, percent)
        }
    }

    static func updateDownloadProgressUnknown(writtenMB: Double) -> String {
        switch lm.activeLanguageCode {
        case "en":
            return String(format: "Downloaded %.1f MB", writtenMB)
        case "zh-Hans":
            return String(format: "已下载 %.1f MB", writtenMB)
        case "uk":
            return String(format: "Завантажено %.1f МБ", writtenMB)
        default:
            return String(format: "Загружено %.1f МБ", writtenMB)
        }
    }

    static var updateStageVerifying: String {
        lm.text(
            ru: "Этап 2 из 3: Проверка SHA-256 и установка...",
            en: "Step 2 of 3: Verifying SHA-256 & installing...",
            zh: "第 2 步（共 3 步）：正在校验 SHA-256 并安装...",
            uk: "Крок 2 з 3: Перевірка SHA-256 та встановлення..."
        )
    }

    static var updateStageInstallingDetail: String {
        lm.text(
            ru: "Проверка целостности и подписи образа...",
            en: "Verifying integrity and code signature...",
            zh: "正在校验镜像完整性与签名...",
            uk: "Перевірка цілісності та підпису образу..."
        )
    }

    static var updateStageRestarting: String {
        lm.text(
            ru: "Этап 3 из 3: Перезапуск...",
            en: "Step 3 of 3: Restarting...",
            zh: "第 3 步（共 3 步）：正在重启...",
            uk: "Крок 3 з 3: Перезапуск..."
        )
    }

    static var updateStageRestartingDetail: String {
        lm.text(
            ru: "Запуск обновленной версии DockFlow...",
            en: "Launching updated DockFlow...",
            zh: "正在启动新版 DockFlow...",
            uk: "Запуск оновленої версії DockFlow..."
        )
    }

    static var updateStageFailed: String {
        lm.text(
            ru: "Ошибка загрузки обновления",
            en: "Update Download Failed",
            zh: "更新下载失败",
            uk: "Помилка завантаження оновлення"
        )
    }

    static var updateStageReconnecting: String {
        lm.text(
            ru: "Этап 1 из 3: Повторное подключение...",
            en: "Step 1 of 3: Reconnecting...",
            zh: "第 1 步（共 3 步）：正在重新连接...",
            uk: "Крок 1 з 3: Повторне підключення..."
        )
    }

    static var updateStageRetryingDetail: String {
        lm.text(
            ru: "Повторная инициализация загрузки...",
            en: "Reinitializing download...",
            zh: "正在重新初始化下载...",
            uk: "Повторна ініціалізація завантаження..."
        )
    }

    static var updateDownloadManually: String {
        lm.text(
            ru: "Скачать вручную",
            en: "Download Manually",
            zh: "手动下载",
            uk: "Завантажити вручну"
        )
    }

    static var updateRetry: String {
        lm.text(
            ru: "Повторить",
            en: "Retry",
            zh: "重试",
            uk: "Повторити"
        )
    }

    static var updateCancel: String {
        lm.text(
            ru: "Отмена",
            en: "Cancel",
            zh: "取消",
            uk: "Скасувати"
        )
    }

    static var updateNotificationBody: String {
        lm.text(
            ru: "Нажмите «Проверить обновления...» в менюбаре, чтобы установить новую версию.",
            en: "Click \"Check for Updates...\" in the menu bar to install the new version.",
            zh: "点击菜单栏中的“检查更新...”以安装新版本。",
            uk: "Натисніть «Перевірити оновлення...» в менюбарі, щоб встановити нову версію."
        )
    }

    static var updateChecksumMissingError: String {
        lm.text(
            ru: "В релизе отсутствует файл .sha256 для проверки целостности. Используйте ручную загрузку.",
            en: "Release does not contain a .sha256 verification file. Please download manually.",
            zh: "该版本缺少 .sha256 校验文件，请手动下载更新。",
            uk: "У релізі відсутній файл .sha256 для перевірки цілісності. Скористайтеся ручним завантаженням."
        )
    }

    static var updateChecksumMismatchError: String {
        lm.text(
            ru: "Контрольная сумма SHA-256 загруженного образа не совпадает! Обновление отменено.",
            en: "Downloaded DMG SHA-256 checksum mismatch! Update aborted for safety.",
            zh: "下载的 DMG 校验和不匹配，出于安全考虑已取消更新！",
            uk: "Контрольна сума SHA-256 завантаженого образу не збігається! Оновлення скасовано."
        )
    }
}
