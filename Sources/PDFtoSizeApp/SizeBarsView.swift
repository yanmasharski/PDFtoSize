import PDFtoSizeCore
import SwiftUI

/// "Before" and "after" as one bar each, split by input file, on the same scale.
struct SizeBarsView: View {
    private static let BAR_HEIGHT: CGFloat = 22

    let files: [InputFile]
    let outcome: Outcome?
    let target: Int

    var body: some View {
        let before = max(files.reduce(0) { $0 + $1.bytes }, 1)
        let after = afterBytes()
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(headline(before: before)).font(.title3.bold())
                Spacer()
                Text(trailing(before: before)).foregroundStyle(.secondary)
            }
            bar("Before", segments: files.map(\.bytes), scale: before)
            if let after { bar("After", segments: after, scale: before) }
            legend
        }
    }

    private func bar(_ title: String, segments: [Int], scale: Int) -> some View {
        HStack(spacing: 10) {
            Text(title).foregroundStyle(.secondary).frame(width: 48, alignment: .leading)
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Color.primary.opacity(0.06)
                    HStack(spacing: 1) {
                        ForEach(Array(segments.enumerated()), id: \.offset) { index, bytes in
                            fileColor(index).frame(width: geometry.size.width * CGFloat(bytes) / CGFloat(scale))
                        }
                    }
                    if target < scale {
                        Rectangle().fill(.primary).frame(width: 2)
                            .offset(x: geometry.size.width * CGFloat(target) / CGFloat(scale) - 1)
                            .help("Target: \(sizeText(target))")
                    }
                }
            }
            .frame(height: SizeBarsView.BAR_HEIGHT)
            .clipShape(RoundedRectangle(cornerRadius: 6))
        }
    }

    private var legend: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 230), alignment: .leading)], alignment: .leading, spacing: 6) {
            ForEach(Array(files.enumerated()), id: \.offset) { index, file in
                HStack(spacing: 6) {
                    Circle().fill(fileColor(index)).frame(width: 9, height: 9)
                    Text(file.url.deletingPathExtension().lastPathComponent).lineLimit(1).truncationMode(.middle)
                    Text(sizeText(file.bytes)).foregroundStyle(.secondary).monospacedDigit()
                }
                .font(.callout)
            }
            if target < files.reduce(0, { $0 + $1.bytes }) {
                HStack(spacing: 6) {
                    Rectangle().fill(.primary).frame(width: 9, height: 2)
                    Text("Target")
                    Text(sizeText(target)).foregroundStyle(.secondary).monospacedDigit()
                }
                .font(.callout)
            }
        }
    }

    /// Result size per input file, scaled so the segments add up to the real file size.
    private func afterBytes() -> [Int]? {
        guard let outcome, !outcome.pages.isEmpty, outcome.status.wroteFile else { return nil }
        let sums = files.map { file in outcome.pages.filter { $0.url == file.url }.reduce(0) { $0 + $1.bytes } }
        let sum = max(sums.reduce(0, +), 1)
        return sums.map { $0 * outcome.resultBytes / sum }
    }

    private func headline(before: Int) -> String {
        guard let outcome, outcome.status.wroteFile else {
            return "\(files.count) file\(files.count == 1 ? "" : "s"), \(files.reduce(0) { $0 + $1.pages }) pages, \(sizeText(before))"
        }
        return "\(sizeText(before)) → \(sizeText(outcome.resultBytes))"
    }

    private func trailing(before: Int) -> String {
        guard let outcome, outcome.status.wroteFile else { return "Target \(sizeText(target))" }
        let saved = max(before - outcome.resultBytes, 0)
        return "Saved \(sizeText(saved)), \(saved * 100 / before)%"
    }
}

extension Status {
    var wroteFile: Bool {
        switch self {
        case .done, .missed: return true
        default: return false
        }
    }
}
