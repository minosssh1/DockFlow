import Foundation
import Cocoa
import os

/// Log severity levels for diagnostic output.
enum LogLevel: String {
    case debug = "DEBUG"
    case info = "INFO"
    case warning = "WARN"
    case error = "ERROR"
}

/// Thread-safe, asynchronous diagnostic logger with automatic file rotation.
final class LogService: ObservableObject {
    static let shared = LogService()

    private let logDirectory: URL
    private let logFileURL: URL
    private let maxLogFileSize: UInt64 = 256 * 1024 // 256 KB max
    private let ioQueue = DispatchQueue(label: "com.dockflow.app.logservice", qos: .utility)
    private let dateFormatter: DateFormatter
    private let enabledLock = OSAllocatedUnfairLock<Bool>(initialState: false)

    @Published var loggingEnabled: Bool {
        didSet {
            enabledLock.withLock { $0 = loggingEnabled }
            UserDefaults.standard.set(loggingEnabled, forKey: "loggingEnabled")
            if loggingEnabled {
                log(category: "LogService", message: "Logging enabled")
            }
        }
    }

    private init() {
        let initialEnabled = UserDefaults.standard.bool(forKey: "loggingEnabled")
        self.loggingEnabled = initialEnabled
        self.enabledLock.withLock { $0 = initialEnabled }

        let logsBase = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask).first!
            .appendingPathComponent("Logs", isDirectory: true)
        logDirectory = logsBase.appendingPathComponent("DockFlow", isDirectory: true)
        logFileURL = logDirectory.appendingPathComponent("app.log")

        dateFormatter = DateFormatter()
        dateFormatter.locale = Locale(identifier: "en_US_POSIX")
        dateFormatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"

        ioQueue.async { [logDirectory, logFileURL, maxLogFileSize] in
            Self.ensureLogDirAndRotateIfNeeded(dir: logDirectory, fileURL: logFileURL, maxSize: maxLogFileSize)
        }
    }

    /// Synchronizes cached state after legacy defaults migration or external defaults updates.
    func reloadPreference() {
        let val = UserDefaults.standard.bool(forKey: "loggingEnabled")
        enabledLock.withLock { $0 = val }
        if Thread.isMainThread {
            if loggingEnabled != val { loggingEnabled = val }
        } else {
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                if self.loggingEnabled != val { self.loggingEnabled = val }
            }
        }
    }

    private static func ensureLogDirAndRotateIfNeeded(dir: URL, fileURL: URL, maxSize: UInt64) {
        let fm = FileManager.default
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        if let attrs = try? fm.attributesOfItem(atPath: fileURL.path),
           let size = attrs[.size] as? UInt64,
           size > maxSize {
            let backupURL = dir.appendingPathComponent("app.log.1")
            try? fm.removeItem(at: backupURL)
            try? fm.moveItem(at: fileURL, to: backupURL)
        }
    }

    /// Appends a log line asynchronously on a serial utility queue without blocking callers.
    func log(level: LogLevel = .info, category: String, message: String) {
        let isEnabled = enabledLock.withLock { $0 }
        guard isEnabled else { return }

        let now = Date()
        ioQueue.async { [weak self] in
            guard let self else { return }
            Self.ensureLogDirAndRotateIfNeeded(dir: self.logDirectory, fileURL: self.logFileURL, maxSize: self.maxLogFileSize)
            let timestamp = self.dateFormatter.string(from: now)
            let logLine = "[\(timestamp)] [\(level.rawValue)] [\(category)] \(message)\n"
            guard let data = logLine.data(using: .utf8) else { return }

            let fm = FileManager.default
            if fm.fileExists(atPath: self.logFileURL.path) {
                if let handle = try? FileHandle(forWritingTo: self.logFileURL) {
                    defer { try? handle.close() }
                    _ = try? handle.seekToEnd()
                    try? handle.write(contentsOf: data)
                }
            } else {
                try? data.write(to: self.logFileURL, options: .atomic)
            }

            #if DEBUG
            print(logLine, terminator: "")
            #endif
        }
    }

    /// Opens the DockFlow log folder in Finder.
    func openLogFolder() {
        ioQueue.sync {
            try? FileManager.default.createDirectory(at: logDirectory, withIntermediateDirectories: true)
        }
        NSWorkspace.shared.open(logDirectory)
    }

    /// Deletes stored log files.
    func clearLogs() {
        ioQueue.async { [logDirectory, logFileURL] in
            try? FileManager.default.removeItem(at: logFileURL)
            try? FileManager.default.removeItem(at: logDirectory.appendingPathComponent("app.log.1"))
        }
    }

    var logFilePath: String {
        logFileURL.path
    }
}
