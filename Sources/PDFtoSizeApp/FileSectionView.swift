import PDFtoSizeCore
import SwiftUI

/// One input file: size before and after, and a row per page when the result is known.
struct FileSectionView: View {
    let file: InputFile
    let color: Color
    let pages: [PageReport]
    /// With one file the page list is the main content; with several it stays closed until asked for.
    let expandsByDefault: Bool

    @State private var isExpanded = false

    var body: some View {
        let after = pages.reduce(0) { $0 + $1.bytes }
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "chevron.right")
                    .rotationEffect(.degrees(isExpanded ? 90 : 0))
                    .frame(width: 14)
                    .opacity(pages.isEmpty ? 0 : 1)
                Circle().fill(color).frame(width: 10, height: 10)
                Text(file.url.lastPathComponent).font(.headline).lineLimit(1).truncationMode(.middle)
                Text("\(file.pages)").foregroundStyle(.secondary)
                if !pages.isEmpty, pages.allSatisfy(\.alreadyCompact) { pill("already compact", .green) }
                Spacer()
                if pages.isEmpty {
                    Text(sizeText(file.bytes)).monospacedDigit()
                } else {
                    MiniBars(before: file.bytes, after: after, scale: file.bytes, color: color).frame(width: 140)
                    Text("\(sizeText(file.bytes)) → \(sizeText(after))").monospacedDigit().frame(width: 150, alignment: .trailing)
                }
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 10)
            .contentShape(Rectangle())
            .onTapGesture { if !pages.isEmpty { withAnimation(.easeInOut(duration: 0.15)) { isExpanded.toggle() } } }

            if isExpanded {
                Divider()
                let largest = pages.map(\.originalBytes).max() ?? 1
                ForEach(pages, id: \.number) { page in
                    PageRowView(page: page, color: color, largest: largest)
                    Divider().padding(.leading, 34)
                }
            }
        }
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 8))
        .onChange(of: pages.isEmpty, initial: true) { _, empty in isExpanded = !empty && expandsByDefault }
    }
}

/// Two thin bars on one scale: what it was (gray) and what it is now (color).
struct MiniBars: View {
    let before: Int
    let after: Int
    let scale: Int
    let color: Color

    var body: some View {
        VStack(spacing: 3) {
            bar(before, .secondary.opacity(0.4))
            bar(after, color)
        }
    }

    private func bar(_ bytes: Int, _ fill: Color) -> some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule().fill(.primary.opacity(0.06))
                Capsule().fill(fill).frame(width: max(3, geometry.size.width * min(1, CGFloat(bytes) / CGFloat(max(scale, 1)))))
            }
        }
        .frame(height: 5)
    }
}

struct PageRowView: View {
    let page: PageReport
    let color: Color
    let largest: Int

    var body: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 8) {
                    Text("Page \(page.pageInFile)")
                    badge
                    if page.alreadyCompact { pill("already compact", .green) }
                }
                Text(page.method).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            MiniBars(before: page.originalBytes, after: page.bytes, scale: largest, color: color).frame(width: 140)
            Text("\(sizeText(page.originalBytes)) → \(sizeText(page.bytes))").monospacedDigit().frame(width: 150, alignment: .trailing)
        }
        .padding(.vertical, 6)
        .padding(.leading, 34)
        .padding(.trailing, 10)
    }

    @ViewBuilder private var badge: some View {
        switch page.treatment {
        case .kept, .smaller: EmptyView()
        case .gray: pill("gray", .orange)
        case .blackWhite: pill("black & white", .orange)
        }
    }

}

func pill(_ text: String, _ tint: Color) -> some View {
    Text(text).font(.caption2.bold()).foregroundStyle(tint)
        .padding(.horizontal, 6).padding(.vertical, 2)
        .background(tint.opacity(0.15), in: Capsule())
}
