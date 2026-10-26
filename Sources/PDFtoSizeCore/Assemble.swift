import CoreGraphics
import Foundation
import PDFKit

/// What one output page is made of.
enum Piece {
    case vector(PageRef, CGSize)   // the original page, copied as it is
    case jpeg(Data, CGSize)        // a rendered picture of the page
    case mono(CGImage, CGSize)     // the same picture as 1-bit black and white

    var size: CGSize {
        switch self {
        case .vector(_, let size), .jpeg(_, let size), .mono(_, let size): return size
        }
    }
}

/// Builds the result with PDFKit. A kept page is copied from its source file as it is, so it keeps its own
/// streams, links and form fields, and its size stays the size it had. A picture page is drawn once.
func assemble(_ pieces: [Piece]) throws -> Data {
    let out = PDFDocument()
    var sources: [URL: PDFDocument] = [:]
    for piece in pieces {
        let page: PDFPage?
        switch piece {
        case .vector(let ref, _):
            let doc = try sources[ref.url] ?? openPDFKit(ref.url)
            sources[ref.url] = doc
            page = doc.page(at: ref.number - 1)?.copy() as? PDFPage
        case .jpeg, .mono:
            page = PDFDocument(data: try pictureWithOnePage(piece))?.page(at: 0)
        }
        guard let page else { throw CompressError.cannotWrite("PDF data") }
        out.insert(page, at: out.pageCount)
    }
    guard let data = out.dataRepresentation() else { throw CompressError.cannotWrite("PDF data") }
    return data
}

func openPDFKit(_ url: URL) throws -> PDFDocument {
    guard let doc = PDFDocument(url: url) else { throw CompressError.cannotOpen(url.lastPathComponent) }
    if doc.isLocked, !doc.unlock(withPassword: "") { throw CompressError.locked(url.lastPathComponent) }
    return doc
}

private func pictureWithOnePage(_ piece: Piece) throws -> Data {
    let out = NSMutableData()
    var box = CGRect(origin: .zero, size: piece.size)
    guard let consumer = CGDataConsumer(data: out), let ctx = CGContext(consumer: consumer, mediaBox: &box, nil)
    else { throw CompressError.cannotWrite("PDF data") }
    ctx.beginPage(mediaBox: &box)
    switch piece {
    case .jpeg(let data, _):
        // The JPEG-source initializer lets Quartz embed the bytes as they are, with no re-encode.
        if let provider = CGDataProvider(data: data as CFData),
           let image = CGImage(jpegDataProviderSource: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent) {
            ctx.draw(image, in: box)
        }
    case .mono(let image, _):
        ctx.draw(image, in: box)
    case .vector:
        break
    }
    ctx.endPage()
    ctx.closePDF()
    return out as Data
}
