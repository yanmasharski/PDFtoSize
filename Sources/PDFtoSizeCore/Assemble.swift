import CoreGraphics
import Foundation

/// What one output page is made of.
enum Piece {
    case vector(PageRef, CGSize)   // the original page, redrawn: text and vectors stay sharp
    case jpeg(Data, CGSize)        // a rendered picture of the page
    case mono(CGImage, CGSize)     // the same picture as 1-bit black and white

    var size: CGSize {
        switch self {
        case .vector(_, let size), .jpeg(_, let size), .mono(_, let size): return size
        }
    }
}

func assemble(_ pieces: [Piece]) throws -> Data {
    let out = NSMutableData()
    guard let consumer = CGDataConsumer(data: out),
          let ctx = CGContext(consumer: consumer, mediaBox: nil, [kCGPDFContextCreator: "PDFtoSize"] as CFDictionary)
    else { throw CompressError.cannotWrite("PDF data") }

    var docs: [URL: CGPDFDocument] = [:]
    for piece in pieces {
        var box = CGRect(origin: .zero, size: piece.size)
        ctx.beginPage(mediaBox: &box)
        switch piece {
        case .vector(let ref, let size):
            let doc = try docs[ref.url] ?? openPDF(ref.url)
            docs[ref.url] = doc
            doc.page(at: ref.number)?.draw(in: ctx, size: size)
        case .jpeg(let data, _):
            // The JPEG-source initializer lets Quartz embed the bytes as they are, with no re-encode.
            if let provider = CGDataProvider(data: data as CFData),
               let image = CGImage(jpegDataProviderSource: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent) {
                ctx.draw(image, in: box)
            }
        case .mono(let image, _):
            ctx.draw(image, in: box)
        }
        ctx.endPage()
    }
    ctx.closePDF()
    return out as Data
}
