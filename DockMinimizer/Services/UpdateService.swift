import Foundation
import Cocoa
import CryptoKit

/// Automatic update check interval policy.
enum UpdateCheckPolicy: String, CaseIterable {
    case onStartup = "onStartup"
    case daily = "daily"
    case weekly = "weekly"
    case disabled = "disabled"

    var displayName: String {
        switch self {
        case .onStartup: return L10n.updatePolicyOnStartup
        case .daily: return L10n.updatePolicyDaily
        case .weekly: return L10n.updatePolicyWeekly
        case .disabled: return L10n.updatePolicyDisabled
        }
    }

    var checkInterval: TimeInterval? {
        switch self {
        case .onStartup: return nil
        case .daily: return 24 * 60 * 60
        case .weekly: return 7 * 24 * 60 * 60
        case .disabled: return nil
        }
    }
}

struct GitHubAsset: Codable {
    let name: String
    let browserDownloadUrl: String

    enum CodingKeys: String, CodingKey {
        case name
        case browserDownloadUrl = "browser_download_url"
    }
}

struct GitHubRelease: Codable {
    let tagName: String
    let htmlUrl: String
    let name: String?
    let body: String?
    let publishedAt: String?
    let assets: [GitHubAsset]?

    enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case htmlUrl = "html_url"
        case name
        case body
        case publishedAt = "published_at"
        case assets
    }
}

/// Checks GitHub Releases for updates and verifies SHA-256 + code signature before installation.
final class UpdateService: ObservableObject {
    static let shared = UpdateService()

    @Published var isChecking = false
    @Published var updateAvailable = false
    @Published var latestVersion: String?
    @Published var releaseURL: URL?
    @Published var downloadURL: URL?
    @Published var sha256URL: URL?
    @Published var errorMessage: String?

    @Published var checkPolicy: UpdateCheckPolicy {
        didSet {
            UserDefaults.standard.set(checkPolicy.rawValue, forKey: checkPolicyKey)
        }
    }

    let currentVersion: String

    private let githubOwner = "minosssh1"
    private let githubRepo = "DockFlow"

    private var apiURL: URL {
        URL(string: "https://api.github.com/repos/\(githubOwner)/\(githubRepo)/releases/latest")!
    }

    private let lastCheckKey = "lastUpdateCheckTime"
    private let checkPolicyKey = "updateCheckPolicy"

    private init() {
        if let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String {
            currentVersion = version
        } else {
            currentVersion = "2.2.0"
        }

        if let savedPolicy = UserDefaults.standard.string(forKey: checkPolicyKey),
           let policy = UpdateCheckPolicy(rawValue: savedPolicy) {
            checkPolicy = policy
        } else {
            checkPolicy = .onStartup
        }
    }

    func reloadPreference() {
        if let savedPolicy = UserDefaults.standard.string(forKey: checkPolicyKey),
           let policy = UpdateCheckPolicy(rawValue: savedPolicy),
           checkPolicy != policy {
            checkPolicy = policy
        }
    }

    /// Creates a private 0700 staging subdirectory inside the user's Caches folder.
    static func createPrivateStagingDirectory() -> URL? {
        guard let cachesDir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first else {
            return nil
        }
        let dir = cachesDir
            .appendingPathComponent("com.dockflow.app", isDirectory: true)
            .appendingPathComponent("Updates", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        do {
            try FileManager.default.createDirectory(
                at: dir,
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700]
            )
            return dir
        } catch {
            return nil
        }
    }

    /// Checks GitHub Releases API for a newer version.
    func checkForUpdates(force: Bool = false) async {
        let alreadyChecking = await MainActor.run { () -> Bool in
            if self.isChecking { return true }
            return false
        }
        if alreadyChecking { return }

        if !force {
            if checkPolicy == .disabled {
                LogService.shared.log(category: "UpdateService", message: "Update check skipped (disabled)")
                return
            }
            if !shouldCheckForUpdates() {
                LogService.shared.log(category: "UpdateService", message: "Update check skipped (within interval)")
                return
            }
        }

        await MainActor.run {
            isChecking = true
            errorMessage = nil
        }

        LogService.shared.log(category: "UpdateService", message: "Checking updates, current: \(currentVersion)")

        do {
            let release = try await fetchLatestRelease()
            let latestRaw = release.tagName
            let latestClean = latestRaw.hasPrefix("v") ? String(latestRaw.dropFirst()) : latestRaw
            let hasUpdate = isNewerVersion(latestClean, than: currentVersion)

            var foundDmgURL: URL?
            var foundShaURL: URL?
            if let assets = release.assets {
                if let dmgAsset = assets.first(where: { $0.name.hasSuffix(".dmg") }) {
                    foundDmgURL = URL(string: dmgAsset.browserDownloadUrl)
                    let exactShaName = "\(dmgAsset.name).sha256"
                    if let shaAsset = assets.first(where: { $0.name == exactShaName }) ?? assets.first(where: { $0.name.hasSuffix(".sha256") }) {
                        foundShaURL = URL(string: shaAsset.browserDownloadUrl)
                    }
                }
            }

            let finalDmgURL = foundDmgURL
            let finalShaURL = foundShaURL

            await MainActor.run {
                self.latestVersion = latestClean
                self.updateAvailable = hasUpdate
                self.releaseURL = URL(string: release.htmlUrl)
                self.downloadURL = finalDmgURL
                self.sha256URL = finalShaURL
                self.isChecking = false
                UserDefaults.standard.set(Date(), forKey: lastCheckKey)
            }

            LogService.shared.log(category: "UpdateService", message: "Check complete: latest=\(latestClean), available=\(hasUpdate)")
        } catch {
            await MainActor.run {
                self.isChecking = false
                self.errorMessage = error.localizedDescription
            }
            LogService.shared.log(level: .error, category: "UpdateService", message: "Update check failed: \(error.localizedDescription)")
        }
    }

    /// Downloads the release `.sha256` file and verifies the downloaded DMG digest before mounting.
    func verifyDMGChecksum(dmgURL: URL, sha256URL: URL?) async throws {
        guard let sha256URL else {
            throw UpdateError.checksumMissing
        }

        var request = URLRequest(url: sha256URL)
        request.timeoutInterval = 30
        let (shaData, response) = try await URLSession.shared.data(for: request)
        if let httpResp = response as? HTTPURLResponse, httpResp.statusCode != 200 {
            throw UpdateError.checksumMissing
        }

        guard let shaText = String(data: shaData, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
              let expectedHex = shaText.split(whereSeparator: { $0.isWhitespace }).first?.lowercased(),
              expectedHex.count == 64 else {
            throw UpdateError.checksumMissing
        }

        let dmgData = try Data(contentsOf: dmgURL, options: .mappedIfSafe)
        let digest = SHA256.hash(data: dmgData)
        let actualHex = digest.map { String(format: "%02x", $0) }.joined()

        guard actualHex == expectedHex else {
            throw UpdateError.checksumMismatch
        }
    }

    func openReleasePage() {
        if let url = releaseURL {
            NSWorkspace.shared.open(url)
        } else if let url = URL(string: "https://github.com/\(githubOwner)/\(githubRepo)/releases") {
            NSWorkspace.shared.open(url)
        }
    }

    func openGitHubPage() {
        if let url = URL(string: "https://github.com/\(githubOwner)/\(githubRepo)") {
            NSWorkspace.shared.open(url)
        }
    }

    /// Installs the verified DMG onto `Bundle.main.bundlePath` using a private 0700 staging directory.
    func applyUpdateAndRestart(dmgPath: String) throws {
        let dmgURL = URL(fileURLWithPath: dmgPath)
        let stageDirURL = dmgURL.deletingLastPathComponent()
        let scriptURL = stageDirURL.appendingPathComponent("updater.sh")
        let targetAppPath = Bundle.main.bundlePath

        let scriptContent = """
        #!/bin/bash
        set -euo pipefail
        DMG_PATH="$1"
        CALLER_PID="$2"
        TARGET_APP="$3"
        STAGE_DIR="$4"
        MOUNT_DIR="$STAGE_DIR/mount"
        BACKUP_APP="$STAGE_DIR/DockFlow.app.bak"

        # Bounded wait (max 10s) for caller process exit
        if [ -n "$CALLER_PID" ]; then
            WAIT_COUNT=0
            while kill -0 "$CALLER_PID" 2>/dev/null; do
                sleep 0.2
                WAIT_COUNT=$((WAIT_COUNT + 1))
                if [ "$WAIT_COUNT" -ge 50 ]; then
                    break
                fi
            done
        fi

        cleanup() {
            hdiutil detach "$MOUNT_DIR" -force 2>/dev/null || true
            rm -rf "$STAGE_DIR" 2>/dev/null || true
        }
        trap cleanup EXIT

        hdiutil detach "$MOUNT_DIR" -force 2>/dev/null || true
        mkdir -p -m 700 "$MOUNT_DIR"
        hdiutil attach "$DMG_PATH" -nobrowse -mountpoint "$MOUNT_DIR" -readonly

        NEW_APP="$MOUNT_DIR/DockFlow.app"
        if [ ! -d "$NEW_APP" ]; then
            exit 1
        fi

        # Verify code signature integrity & canonical bundle identifier before replacing
        codesign --verify --deep --strict "$NEW_APP"
        SIGN_INFO=$(codesign -dv "$NEW_APP" 2>&1 || true)
        if ! grep -qE "Identifier=com\\.(dockflow\\.app|jacktony\\.dockminimizer)" <<< "$SIGN_INFO"; then
            exit 1
        fi

        rm -rf "$BACKUP_APP"
        if [ -d "$TARGET_APP" ]; then
            mv "$TARGET_APP" "$BACKUP_APP"
        fi

        if ! ditto "$NEW_APP" "$TARGET_APP"; then
            rm -rf "$TARGET_APP"
            if [ -d "$BACKUP_APP" ]; then
                mv "$BACKUP_APP" "$TARGET_APP"
            fi
            exit 1
        fi

        rm -rf "$BACKUP_APP"
        open "$TARGET_APP"
        """

        do {
            try scriptContent.write(to: scriptURL, atomically: true, encoding: .utf8)
            _ = chmod(scriptURL.path, 0o700)

            let currentPID = String(ProcessInfo.processInfo.processIdentifier)
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/bash")
            process.arguments = [scriptURL.path, dmgPath, currentPID, targetAppPath, stageDirURL.path]
            process.standardInput = FileHandle.nullDevice
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
            try process.run()
            NSApplication.shared.terminate(nil)
        } catch {
            LogService.shared.log(level: .error, category: "UpdateService", message: "Failed to launch updater script: \(error.localizedDescription)")
            throw error
        }
    }

    // MARK: - Private Helpers

    private func shouldCheckForUpdates() -> Bool {
        if checkPolicy == .onStartup {
            return true
        }
        guard let interval = checkPolicy.checkInterval else {
            return false
        }
        guard let lastCheck = UserDefaults.standard.object(forKey: lastCheckKey) as? Date else {
            return true
        }
        return Date().timeIntervalSince(lastCheck) >= interval
    }

    private func fetchLatestRelease() async throws -> GitHubRelease {
        var request = URLRequest(url: apiURL)
        request.setValue("application/vnd.github.v3+json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 30

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw UpdateError.invalidResponse
        }
        guard httpResponse.statusCode == 200 else {
            throw UpdateError.httpError(statusCode: httpResponse.statusCode)
        }

        return try JSONDecoder().decode(GitHubRelease.self, from: data)
    }

    /// SemVer comparison supporting pre-release tags (e.g., `1.0.6-beta.1` < `1.0.6`).
    func isNewerVersion(_ newVersion: String, than currentVersion: String) -> Bool {
        func splitVersion(_ raw: String) -> (nums: [Int], pre: String?) {
            let parts = raw.split(separator: "-", maxSplits: 1)
            let core = String(parts[0])
            let pre = parts.count > 1 ? String(parts[1]) : nil
            let nums = core.split(separator: ".").compactMap { Int($0) }
            return (nums, pre)
        }

        let newV = splitVersion(newVersion)
        let curV = splitVersion(currentVersion)
        let maxCount = max(newV.nums.count, curV.nums.count)

        for i in 0..<maxCount {
            let n = i < newV.nums.count ? newV.nums[i] : 0
            let c = i < curV.nums.count ? curV.nums[i] : 0
            if n > c { return true }
            if n < c { return false }
        }

        // Core numbers are equal: stable release (pre == nil) is newer than pre-release
        switch (curV.pre, newV.pre) {
        case (.some, .none):
            return true
        case (.none, .some):
            return false
        case (.some(let curPre), .some(let newPre)):
            return newPre.compare(curPre, options: .numeric) == .orderedDescending
        case (.none, .none):
            return false
        }
    }
}

enum UpdateError: LocalizedError {
    case invalidResponse
    case httpError(statusCode: Int)
    case decodingError
    case stagingDirectoryError
    case checksumMissing
    case checksumMismatch

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "Invalid server response"
        case .httpError(let statusCode):
            return "HTTP error: \(statusCode)"
        case .decodingError:
            return "Failed to parse update information"
        case .stagingDirectoryError:
            return "Failed to create secure staging directory"
        case .checksumMissing:
            return L10n.updateChecksumMissingError
        case .checksumMismatch:
            return L10n.updateChecksumMismatchError
        }
    }
}
