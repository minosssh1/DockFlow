import Cocoa
import SwiftUI

final class UpdateProgressViewModel: ObservableObject {
    @Published var stageTitle: String = L10n.updateStagePreparing
    @Published var stageDetail: String = L10n.updateStageInit
    @Published var progress: Double = 0.0
    @Published var isIndeterminate: Bool = true
    @Published var isFailed: Bool = false
    @Published var errorMessage: String? = nil

    var onCancel: (() -> Void)?
    var onRetry: (() -> Void)?
    var onManualDownload: (() -> Void)?
}

struct UpdateProgressView: View {
    @Environment(\.colorScheme) private var colorScheme
    @ObservedObject private var lm = LocalizationManager.shared
    @ObservedObject var viewModel: UpdateProgressViewModel
    let targetVersion: String

    private var isDark: Bool { colorScheme == .dark }
    private var bgSurface: Color {
        isDark ? Color(red: 20/255, green: 22/255, blue: 25/255) : Color(red: 248/255, green: 248/255, blue: 250/255)
    }
    private var wellSurface: Color {
        isDark ? Color(red: 27/255, green: 30/255, blue: 35/255) : Color.white
    }
    private var wellBorder: Color {
        isDark ? Color.white.opacity(0.08) : Color.black.opacity(0.08)
    }
    private var primaryFill: Color {
        isDark ? Color(white: 0.94) : Color(white: 0.10)
    }
    private var primaryText: Color {
        isDark ? Color(white: 0.06) : Color.white
    }

    var body: some View {
        VStack(spacing: 14) {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(wellSurface)
                        .frame(width: 44, height: 44)
                        .overlay(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .stroke(wellBorder, lineWidth: 1)
                        )
                    if let icon = NSImage(named: "AppIcon") {
                        Image(nsImage: icon)
                            .resizable()
                            .frame(width: 34, height: 34)
                            .cornerRadius(7)
                    } else {
                        Image(systemName: "arrow.down")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(.primary)
                    }
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text(L10n.updateWindowHeader(version: targetVersion))
                        .font(.custom("Avenir Next", size: 14).weight(.semibold))
                    Text(viewModel.stageTitle)
                        .font(.custom("Avenir Next", size: 12))
                        .foregroundColor(viewModel.isFailed ? Color(red: 220/255, green: 90/255, blue: 90/255) : .secondary)
                }

                Spacer()
            }

            VStack(alignment: .leading, spacing: 8) {
                if viewModel.isIndeterminate {
                    ProgressView()
                        .progressViewStyle(.linear)
                        .tint(isDark ? Color(white: 0.88) : Color(white: 0.16))
                } else {
                    ProgressView(value: viewModel.progress, total: 1.0)
                        .progressViewStyle(.linear)
                        .tint(isDark ? Color(white: 0.88) : Color(white: 0.16))
                }

                HStack {
                    Text(viewModel.stageDetail)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(viewModel.isFailed ? Color(red: 220/255, green: 90/255, blue: 90/255) : .secondary)
                    Spacer()
                    if !viewModel.isIndeterminate && !viewModel.isFailed {
                        Text("\(Int(viewModel.progress * 100))%")
                            .font(.system(size: 11, weight: .semibold, design: .monospaced))
                            .foregroundColor(.secondary)
                    }
                }
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(wellSurface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(wellBorder, lineWidth: 1)
            )

            HStack(spacing: 8) {
                if viewModel.isFailed {
                    Button(L10n.updateDownloadManually) {
                        viewModel.onManualDownload?()
                    }
                    .buttonStyle(.plain)
                    .font(.custom("Avenir Next", size: 12))
                    .foregroundColor(.secondary)

                    Spacer()

                    Button(L10n.updateRetry) {
                        viewModel.onRetry?()
                    }
                    .buttonStyle(.plain)
                    .font(.custom("Avenir Next", size: 12).weight(.semibold))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(primaryFill))
                    .foregroundColor(primaryText)

                    Button(L10n.close) {
                        viewModel.onCancel?()
                    }
                    .buttonStyle(.plain)
                    .font(.custom("Avenir Next", size: 12))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(wellSurface))
                    .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(wellBorder, lineWidth: 1))
                } else {
                    Spacer()
                    Button(L10n.updateCancel) {
                        viewModel.onCancel?()
                    }
                    .buttonStyle(.plain)
                    .font(.custom("Avenir Next", size: 12).weight(.medium))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(wellSurface))
                    .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(wellBorder, lineWidth: 1))
                    .keyboardShortcut(.cancelAction)
                }
            }
        }
        .padding(18)
        .frame(width: 420)
        .background(bgSurface)
    }
}

final class UpdateDownloader: NSObject, URLSessionDownloadDelegate {
    private var session: URLSession?
    private var downloadTask: URLSessionDownloadTask?
    private var stageDirectory: URL?

    var onProgress: ((Double, Int64, Int64) -> Void)?
    var onComplete: ((Result<URL, Error>) -> Void)?

    deinit {
        cancel()
    }

    func start(url: URL) {
        // Invalidate any prior session/task before creating a new one (prevents URLSession leaks on retry)
        cancel()

        guard let stageDir = UpdateService.createPrivateStagingDirectory() else {
            onComplete?(.failure(UpdateError.stagingDirectoryError))
            return
        }
        stageDirectory = stageDir

        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 60
        config.timeoutIntervalForResource = 300
        let newSession = URLSession(configuration: config, delegate: self, delegateQueue: .main)
        session = newSession
        downloadTask = newSession.downloadTask(with: url)
        downloadTask?.resume()
    }

    func cancel() {
        downloadTask?.cancel()
        downloadTask = nil
        session?.invalidateAndCancel()
        session = nil
        if let dir = stageDirectory {
            try? FileManager.default.removeItem(at: dir)
            stageDirectory = nil
        }
    }

    /// Transfers ownership of the private staging directory to `UpdateService.applyUpdateAndRestart`
    /// so `windowWillClose` and `deinit` do not delete the downloaded DMG before installation starts.
    func releaseStagingDirectoryForInstall() {
        downloadTask = nil
        session = nil
        stageDirectory = nil
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        let progress: Double
        if totalBytesExpectedToWrite > 0 {
            progress = min(max(Double(totalBytesWritten) / Double(totalBytesExpectedToWrite), 0.0), 1.0)
        } else {
            progress = 0.0
        }
        onProgress?(progress, totalBytesWritten, totalBytesExpectedToWrite)
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didFinishDownloadingTo location: URL
    ) {
        defer {
            session.finishTasksAndInvalidate()
            if self.session === session {
                self.session = nil
                self.downloadTask = nil
            }
        }

        guard let stageDir = stageDirectory ?? UpdateService.createPrivateStagingDirectory() else {
            onComplete?(.failure(UpdateError.stagingDirectoryError))
            return
        }

        let stagedDMG = stageDir.appendingPathComponent("DockFlow_Update.dmg")
        try? FileManager.default.removeItem(at: stagedDMG)
        do {
            try FileManager.default.copyItem(at: location, to: stagedDMG)
            // Keep stageDirectory intact so UpdateService uses it for verification & mounting
            onComplete?(.success(stagedDMG))
        } catch {
            try? FileManager.default.removeItem(at: stageDir)
            stageDirectory = nil
            onComplete?(.failure(error))
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        defer {
            session.finishTasksAndInvalidate()
            if self.session === session {
                self.session = nil
                self.downloadTask = nil
            }
        }
        if let error {
            let nsErr = error as NSError
            if nsErr.code != NSURLErrorCancelled {
                if let dir = stageDirectory {
                    try? FileManager.default.removeItem(at: dir)
                    stageDirectory = nil
                }
                onComplete?(.failure(error))
            }
        }
    }
}
