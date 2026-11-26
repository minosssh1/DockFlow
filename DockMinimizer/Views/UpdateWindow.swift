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
    @ObservedObject private var lm = LocalizationManager.shared
    @ObservedObject var viewModel: UpdateProgressViewModel
    let targetVersion: String

    var body: some View {
        VStack(spacing: 16) {
            HStack(spacing: 14) {
                if let icon = NSImage(named: "AppIcon") {
                    Image(nsImage: icon)
                        .resizable()
                        .frame(width: 48, height: 48)
                } else {
                    Image(systemName: "arrow.down.circle.fill")
                        .font(.system(size: 40))
                        .foregroundColor(.accentColor)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(L10n.updateWindowHeader(version: targetVersion))
                        .font(.system(size: 15, weight: .semibold))
                    Text(viewModel.stageTitle)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(viewModel.isFailed ? .red : .primary)
                }

                Spacer()
            }

            VStack(alignment: .leading, spacing: 6) {
                if viewModel.isIndeterminate {
                    ProgressView()
                        .progressViewStyle(.linear)
                } else {
                    ProgressView(value: viewModel.progress, total: 1.0)
                        .progressViewStyle(.linear)
                }

                HStack {
                    Text(viewModel.stageDetail)
                        .font(.system(size: 11))
                        .foregroundColor(viewModel.isFailed ? .red : .secondary)
                    Spacer()
                    if !viewModel.isIndeterminate && !viewModel.isFailed {
                        Text("\(Int(viewModel.progress * 100))%")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(.secondary)
                    }
                }
            }

            Divider()

            HStack {
                if viewModel.isFailed {
                    Button(L10n.updateDownloadManually) {
                        viewModel.onManualDownload?()
                    }
                    Spacer()
                    Button(L10n.updateRetry) {
                        viewModel.onRetry?()
                    }
                    Button(L10n.close) {
                        viewModel.onCancel?()
                    }
                } else {
                    Spacer()
                    Button(L10n.updateCancel) {
                        viewModel.onCancel?()
                    }
                    .keyboardShortcut(.cancelAction)
                }
            }
        }
        .padding(20)
        .frame(width: 420)
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
