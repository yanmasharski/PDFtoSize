import AppKit
import PDFtoSizeCore
import SwiftUI

struct ContentView: View {
    @Bindable var model: AppModel
    @State private var dropping = false

    var body: some View {
        Group {
            if model.files.isEmpty { emptyState } else { ScrollView { content } }
        }
        .toolbar {
            ToolbarItemGroup {
                Button("Add Files", systemImage: "plus", action: choose)
                    .disabled(model.isWorking)
                Button(action: model.run) {
                    Label("Compress to \(sizeText(model.targetBytes))", systemImage: "arrow.down.right.and.arrow.up.left")
                        .labelStyle(.titleAndIcon)
                }
                .buttonStyle(.borderedProminent)
                .disabled(model.files.isEmpty || model.isWorking || model.targetBytes <= 0)
            }
        }
        .overlay { if dropping { RoundedRectangle(cornerRadius: 8).stroke(Color.accentColor, lineWidth: 3).padding(4) } }
        .dropDestination(for: URL.self) { urls, _ in
            model.add(urls)
            return true
        } isTargeted: { dropping = $0 }
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "arrow.down.doc")
                .font(.system(size: 56))
                .foregroundStyle(.secondary)
            Text("Make your PDFs fit").font(.title2)
            Text("Drop PDF files and photos here (iPhone, Android, scans). They are joined into one PDF and shrunk to the size you choose.\nYour originals are never changed.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            Button("Add Files", action: choose)
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .keyboardShortcut(.defaultAction)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    var content: some View {
        VStack(alignment: .leading, spacing: 16) {
            SizeBarsView(files: model.files, outcome: model.outcome, target: model.targetBytes)
            settings
            status
            ForEach(Array(model.files.enumerated()), id: \.element.id) { index, file in
                FileSectionView(file: file, color: fileColor(index), pages: pages(of: file), expandsByDefault: model.files.count == 1)
                    .contextMenu { Button("Remove") { model.files.removeAll { $0.id == file.id } } }
            }
        }
        .padding(20)
    }

    private var settings: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Target size")
                TextField("", value: $model.targetValue, format: .number)
                    .frame(width: 70)
                    .multilineTextAlignment(.trailing)
                Picker("", selection: $model.unit) {
                    ForEach(SizeUnit.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }
                .labelsHidden()
                .frame(width: 70)
            }
            Toggle("Allow stronger compression", isOn: $model.allowStrong)
            Text("Gray, black & white and smaller pictures. Colors of stamps and signatures can be lost. The result list shows what happened to each page.")
                .font(.caption).foregroundStyle(.secondary)
        }
        .disabled(model.isWorking)
    }

    @ViewBuilder private var status: some View {
        switch model.phase {
        case .idle:
            EmptyView()
        case .working(let fraction, let text):
            VStack(alignment: .leading, spacing: 6) {
                ProgressView(value: fraction)
                Text(text).font(.caption).foregroundStyle(.secondary)
            }
        case .failed(let message):
            BannerView(systemImage: "xmark.octagon.fill", tint: .red, text: message)
        case .finished(let outcome):
            outcomeBanner(outcome)
        }
    }

    @ViewBuilder private func outcomeBanner(_ o: Outcome) -> some View {
        switch o.status {
        case .done(let url):
            BannerView(systemImage: "checkmark.circle.fill", tint: .green, text: "Target met: \(sizeText(o.resultBytes)) of \(sizeText(o.target)). Saved as \(url.lastPathComponent).") {
                Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([url]) }
            }
        case .missed(let url):
            BannerView(systemImage: "exclamationmark.triangle.fill", tint: .orange, text: "Target missed. The smallest possible result is \(sizeText(o.resultBytes)); target \(sizeText(o.target)).") {
                Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([url]) }
            }
        case .needsConsent:
            BannerView(systemImage: "lock.fill", tint: .orange, text: "Safe compression stops at \(sizeText(o.resultBytes)). Stronger compression gets to \(sizeText(o.strongBytes ?? 0)); target \(sizeText(o.target)).") {
                Button("Allow and retry", action: model.retryWithStrong)
            }
        case .alreadyFits:
            BannerView(systemImage: "checkmark.circle", tint: .secondary, text: "This file already fits: \(sizeText(o.originalBytes)).")
        case .notSmaller:
            BannerView(systemImage: "info.circle", tint: .secondary, text: "Compression would not make this file smaller. Nothing was written.")
        }
    }

    private func pages(of file: InputFile) -> [PageReport] {
        guard let outcome = model.outcome, outcome.status.wroteFile else { return [] }
        return outcome.pages.filter { $0.url == file.url }
    }

    private func choose() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.pdf, .image]
        panel.allowsMultipleSelection = true
        if panel.runModal() == .OK { model.add(panel.urls) }
    }
}
