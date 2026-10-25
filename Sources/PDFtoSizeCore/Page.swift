import CoreGraphics
import Foundation

public enum CompressError: LocalizedError {
    case cannotOpen(String)
    case locked(String)
    case noPages
    case cannotWrite(String)

    public var errorDescription: String? {
        switch self {
        case .cannotOpen(let name): return "Cannot open \(name)."
        case .locked(let name): return "\(name) is password protected."
        case .noPages: return "There are no pages to compress."
        case .cannotWrite(let name): return "Cannot write \(name)."
        }
    }
}

/// One page of one input file. `number` starts at 1, like CGPDFDocument.
struct PageRef {
    let url: URL
    let number: Int
}

func openPDF(_ url: URL) throws -> CGPDFDocument {
    guard let doc = CGPDFDocument(url as CFURL) else { throw CompressError.cannotOpen(url.lastPathComponent) }
    if doc.isEncrypted, !doc.isUnlocked, !doc.unlockWithPassword("") {
        throw CompressError.locked(url.lastPathComponent)
    }
    return doc
}

func pageRefs(_ urls: [URL]) throws -> [PageRef] {
    let refs = try urls.flatMap { url -> [PageRef] in
        let doc = try openPDF(url)
        return (0..<doc.numberOfPages).map { PageRef(url: url, number: $0 + 1) }
    }
    if refs.isEmpty { throw CompressError.noPages }
    return refs
}

extension CGPDFPage {
    /// Page size as a viewer shows it: crop box, with /Rotate applied.
    var outputSize: CGSize {
        let box = getBoxRect(.cropBox)
        return rotationAngle % 180 == 0 ? box.size : CGSize(width: box.height, height: box.width)
    }

    func draw(in ctx: CGContext, size: CGSize) {
        let rect = CGRect(origin: .zero, size: size)
        ctx.saveGState()
        ctx.clip(to: rect)
        ctx.concatenate(getDrawingTransform(.cropBox, rect: rect, rotate: 0, preserveAspectRatio: true))
        ctx.drawPDFPage(self)
        ctx.restoreGState()
    }
}
