import Foundation
import Cocoa
import UniformTypeIdentifiers
import os

/// Excluded application entry displayed in the exclusions UI.
struct ExcludedAppItem: Identifiable, Equatable {
    var id: String { bundleIdentifier }
    let bundleIdentifier: String
    let name: String
    let icon: NSImage
}

/// Manages applications excluded from automatic Command+Q quit-on-close.
final class AppExclusionManager: ObservableObject {
    static let shared = AppExclusionManager()

    private let storageKey = "quitOnCloseExcludedBundleIDs"

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
            cacheLock.withLock { $0 = Set(excludedBundleIDs) }
            refreshCachedItems()
        }
    }

    @Published private(set) var excludedAppItems: [ExcludedAppItem] = []

    private let cacheLock = OSAllocatedUnfairLock<Set<String>>(initialState: [])

    private init() {
        if let saved = UserDefaults.standard.stringArray(forKey: storageKey) {
            excludedBundleIDs = saved
        } else {
            excludedBundleIDs = defaultExcludedBundleIDs
            UserDefaults.standard.set(defaultExcludedBundleIDs, forKey: storageKey)
        }
        cacheLock.withLock { $0 = Set(excludedBundleIDs) }
        refreshCachedItems()
    }

    /// Refreshes cached list after legacy preferences migration.
    func reloadPreference() {
        if let saved = UserDefaults.standard.stringArray(forKey: storageKey),
           saved != excludedBundleIDs {
            excludedBundleIDs = saved
        }
    }

    /// Thread-safe check whether a bundle identifier is excluded from quit-on-close.
    func isExcluded(bundleIdentifier: String) -> Bool {
        cacheLock.withLock { $0.contains(bundleIdentifier) }
    }

    /// Adds an application bundle identifier to the exclusions list.
    func addApp(bundleIdentifier: String) {
        guard !excludedBundleIDs.contains(bundleIdentifier) else { return }
        excludedBundleIDs.append(bundleIdentifier)
    }

    /// Removes an application bundle identifier from the exclusions list.
    func removeApp(bundleIdentifier: String) {
        excludedBundleIDs.removeAll { $0 == bundleIdentifier }
    }

    /// Resolves display names and icons outside SwiftUI body evaluation.
    private func refreshCachedItems() {
        excludedAppItems = excludedBundleIDs.map { bid in
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

    /// Opens an application picker sheet/panel scoped to /Applications.
    func addAppViaFilePicker() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.prompt = L10n.filePickerAddButton
        panel.message = L10n.filePickerMessage

        NSApplication.shared.activate(ignoringOtherApps: true)
        if panel.runModal() == .OK, let url = panel.url {
            if let bid = Bundle(url: url)?.bundleIdentifier {
                addApp(bundleIdentifier: bid)
            }
        }
    }
}
