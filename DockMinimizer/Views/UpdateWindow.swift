import Cocoa
import SwiftUI

class UpdateProgressViewModel: ObservableObject {
    @Published var stageTitle: String = "Подготовка..."
    @Published var stageDetail: String = "Инициализация соединения..."
    @Published var progress: Double = 0.0
    @Published var isIndeterminate: Bool = true
    @Published var isFailed: Bool = false
    @Published var errorMessage: String? = nil

    var onCancel: (() -> Void)?
    var onRetry: (() -> Void)?
    var onManualDownload: (() -> Void)?
}

struct UpdateProgressView: View {
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
                    Text("Обновление DockFlow \(targetVersion)")
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
                    Button("Скачать вручную") {
                        viewModel.onManualDownload?()
                    }
                    Spacer()
                    Button("Повторить") {
                        viewModel.onRetry?()
                    }
                    Button("Закрыть") {
                        viewModel.onCancel?()
                    }
                } else {
                    Spacer()
                    Button("Отмена") {
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

class UpdateDownloader: NSObject, URLSessionDownloadDelegate {
    private var session: URLSession?
    private var downloadTask: URLSessionDownloadTask?

    var onProgress: ((Double, Int64, Int64) -> Void)?
    var onComplete: ((Result<URL, Error>) -> Void)?

    func start(url: URL) {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 60
        config.timeoutIntervalForResource = 300
        session = URLSession(configuration: config, delegate: self, delegateQueue: .main)
        downloadTask = session?.downloadTask(with: url)
        downloadTask?.resume()
    }

    func cancel() {
        downloadTask?.cancel()
        session?.invalidateAndCancel()
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        let progress: Double
        if totalBytesExpectedToWrite > 0 {
            progress = min(max(Double(totalBytesWritten) / Double(totalBytesExpectedToWrite), 0.0), 1.0)
        } else {
            progress = 0.0
        }
        onProgress?(progress, totalBytesWritten, totalBytesExpectedToWrite)
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        let tempDMG = URL(fileURLWithPath: "/tmp/DockFlow_Update.dmg")
        try? FileManager.default.removeItem(at: tempDMG)
        do {
            try FileManager.default.copyItem(at: location, to: tempDMG)
            onComplete?(.success(tempDMG))
        } catch {
            onComplete?(.failure(error))
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error = error {
            if (error as NSError).code != NSURLErrorCancelled {
                onComplete?(.failure(error))
            }
        }
    }
}
