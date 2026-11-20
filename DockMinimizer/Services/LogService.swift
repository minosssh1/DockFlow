import Foundation
import Cocoa

/// 日志级别
enum LogLevel: String {
    case debug = "DEBUG"
    case info = "INFO"
    case warning = "WARN"
    case error = "ERROR"
}

/// 统一日志服务 (энергоэффективное кэширование и ограничение размера)
class LogService {
    static let shared = LogService()

    private let logDirectory: URL
    private let logFileURL: URL
    private let fileManager = FileManager.default
    private let dateFormatter: DateFormatter
    private let maxLogFileSize: UInt64 = 256 * 1024 // 256 KB макс

    /// Кэшированное значение для исключения частых чтений из UserDefaults
    private var _cachedLoggingEnabled: Bool?
    var loggingEnabled: Bool {
        get {
            if let cached = _cachedLoggingEnabled { return cached }
            let val = UserDefaults.standard.bool(forKey: "loggingEnabled")
            _cachedLoggingEnabled = val
            return val
        }
        set {
            _cachedLoggingEnabled = newValue
            UserDefaults.standard.set(newValue, forKey: "loggingEnabled")
            if newValue {
                log(category: "LogService", message: "Логирование включено")
            }
        }
    }

    private init() {
        // 日志目录: ~/Library/Logs/DockMinimizer/
        logDirectory = fileManager.urls(for: .libraryDirectory, in: .userDomainMask)
            .first!
            .appendingPathComponent("Logs")
            .appendingPathComponent("DockMinimizer")

        logFileURL = logDirectory.appendingPathComponent("app.log")

        // 日期格式化
        dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd HH:mm:ss"

        // 确保目录存在
        try? fileManager.createDirectory(at: logDirectory, withIntermediateDirectories: true)

        // Ограничиваем размер логов при запуске
        checkLogFileSize()
    }

    /// Проверяет размер лог-файла и сбрасывает, если он превышает допустимый лимит
    private func checkLogFileSize() {
        if let attrs = try? fileManager.attributesOfItem(atPath: logFileURL.path),
           let size = attrs[.size] as? UInt64,
           size > maxLogFileSize {
            try? fileManager.removeItem(at: logFileURL)
        }
    }

    /// 写入日志
    func log(level: LogLevel = .info, category: String, message: String) {
        guard loggingEnabled else { return }

        let timestamp = dateFormatter.string(from: Date())
        let logLine = "[\(timestamp)] [\(level.rawValue)] [\(category)] \(message)\n"

        autoreleasepool {
            if let data = logLine.data(using: .utf8) {
                if fileManager.fileExists(atPath: logFileURL.path) {
                    if let fileHandle = try? FileHandle(forWritingTo: logFileURL) {
                        fileHandle.seekToEndOfFile()
                        fileHandle.write(data)
                        fileHandle.closeFile()
                    }
                } else {
                    try? data.write(to: logFileURL)
                }
            }
        }

        #if DEBUG
        print(logLine, terminator: "")
        #endif
    }

    /// 在 Finder 中打开日志目录
    func openLogFolder() {
        try? fileManager.createDirectory(at: logDirectory, withIntermediateDirectories: true)
        NSWorkspace.shared.open(logDirectory)
    }

    /// 清理所有日志
    func clearLogs() {
        try? fileManager.removeItem(at: logFileURL)
        log(category: "LogService", message: "Логи очищены")
    }

    /// 获取日志文件路径（用于显示）
    var logFilePath: String {
        return logFileURL.path
    }
}
