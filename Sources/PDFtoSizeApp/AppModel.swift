import CoreGraphics
import SwiftUI
import Foundation
import Observation
import PDFtoSizeCore

enum SizeUnit: String, CaseIterable {
    case mb = "MB", kb = "KB"
    var bytes: Int { self == .mb ? 1_000_000 : 1_000 }
}

struct InputFile: Identifiable {
    let url: URL
    let bytes: Int
    let pages: Int
    var id: URL { url }
}

@MainActor @Observable final class AppModel {
    enum Phase {
        case idle
        case working(Double, String)
        case finished(Outcome)
        case failed(String)
    }

    var files: [InputFile] = [] { didSet { reset() } }
    var targetValue = 1.0 { didSet { reset() } }
    var unit = SizeUnit.mb { didSet { reset() } }
    var allowStrong = false
    var phase = Phase.idle

    var isWorking: Bool { if case .working = phase { return true } else { return false } }
    var targetBytes: Int { Int(targetValue * Double(unit.bytes)) }
    var totalBytes: Int { files.reduce(0) { $0 + $1.bytes } }
    var outcome: Outcome? { if case .finished(let o) = phase { return o } else { return nil } }

    func add(_ urls: [URL]) {
        for url in urls where isSupportedInput(url) && !files.contains(where: { $0.url == url }) {
            let bytes = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
            let pages = isPhotoFile(url) ? 1 : (CGPDFDocument(url as CFURL)?.numberOfPages ?? 0)
            files.append(InputFile(url: url, bytes: bytes, pages: pages))
        }
    }

    func run() {
        let inputs = files.map(\.url), target = targetBytes, strong = allowStrong
        phase = .working(0, "Starting…")
        Task.detached { [model = self] in
            do {
                let outcome = try Compressor.run(inputs: inputs, target: target, allowStrong: strong) { fraction, text in
                    Task { @MainActor in model.progress(fraction, text) }
                }
                await MainActor.run { model.phase = .finished(outcome) }
            } catch {
                await MainActor.run { model.phase = .failed(error.localizedDescription) }
            }
        }
    }

    func retryWithStrong() {
        allowStrong = true
        run()
    }

    // The old result no longer matches the files or the target.
    private func reset() {
        if !isWorking { phase = .idle }
    }

    // A late progress update must not overwrite the finished state.
    fileprivate func progress(_ fraction: Double, _ text: String) {
        if case .working = phase { phase = .working(fraction, text) }
    }
}

func sizeText(_ bytes: Int) -> String {
    ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
}

/// One color per input file, used in the bars and the legend.
func fileColor(_ index: Int) -> Color {
    let palette: [Color] = [.blue, .purple, .orange, .pink, .teal, .indigo, .yellow, .brown]
    return palette[index % palette.count]
}

private func isPhotoFile(_ url: URL) -> Bool { url.pathExtension.lowercased() != "pdf" }
