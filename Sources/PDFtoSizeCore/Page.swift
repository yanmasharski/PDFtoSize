import CoreGraphics
import Foundation
import ImageIO

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

/// File types the app takes. Photos from iPhone (HEIC, JPEG), Android (JPEG, WebP) and scanners (PNG, TIFF) become one page each.
public let photoExtensions: Set<String> = ["jpg", "jpeg", "png", "heic", "heif", "webp", "tif", "tiff", "bmp", "gif"]
public func isSupportedInput(_ url: URL) -> Bool {
    let ext = url.pathExtension.lowercased()
    return ext == "pdf" || photoExtensions.contains(ext)
}
func isPhoto(_ url: URL) -> Bool { photoExtensions.contains(url.pathExtension.lowercased()) }

/// One page of one input file. `number` starts at 1, like CGPDFDocument. A photo has one page.
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
        if isPhoto(url) {
            _ = try openContent(PageRef(url: url, number: 1))   // fails early on a file that is not an image
            return [PageRef(url: url, number: 1)]
        }
        let doc = try openPDF(url)
        return (0..<doc.numberOfPages).map { PageRef(url: url, number: $0 + 1) }
    }
    if refs.isEmpty { throw CompressError.noPages }
    return refs
}

/// What is drawn on a page: a PDF page, or a photo (with the camera rotation already applied).
enum Content {
    case pdf(CGPDFDocument, CGPDFPage)
    case photo(CGImage)

    /// Page size in points. A PDF page is shown as a viewer shows it: crop box, with /Rotate applied.
    /// A photo gets the long side of an A4 sheet, so one pixel scale fits all inputs.
    var outputSize: CGSize {
        switch self {
        case .pdf(_, let page):
            let box = page.getBoxRect(.cropBox)
            return page.rotationAngle % 180 == 0 ? box.size : CGSize(width: box.height, height: box.width)
        case .photo(let image):
            let scale = 842 / CGFloat(max(image.width, image.height))
            return CGSize(width: (CGFloat(image.width) * scale).rounded(), height: (CGFloat(image.height) * scale).rounded())
        }
    }

    func draw(in ctx: CGContext, size: CGSize) {
        let rect = CGRect(origin: .zero, size: size)
        switch self {
        case .pdf(_, let page):
            ctx.saveGState()
            ctx.clip(to: rect)
            ctx.concatenate(page.getDrawingTransform(.cropBox, rect: rect, rotate: 0, preserveAspectRatio: true))
            ctx.drawPDFPage(page)
            ctx.restoreGState()
        case .photo(let image):
            ctx.draw(image, in: rect)
        }
    }
}

func openContent(_ ref: PageRef) throws -> Content {
    if isPhoto(ref.url) {
        guard let source = CGImageSourceCreateWithURL(ref.url as CFURL, nil),
              let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let w = props[kCGImagePropertyPixelWidth] as? Int, let h = props[kCGImagePropertyPixelHeight] as? Int,
              // The thumbnail call at full size is the way to get the picture turned the way the camera meant it.
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                  kCGImageSourceCreateThumbnailFromImageAlways: true,
                  kCGImageSourceCreateThumbnailWithTransform: true,
                  kCGImageSourceThumbnailMaxPixelSize: max(w, h),
              ] as CFDictionary)
        else { throw CompressError.cannotOpen(ref.url.lastPathComponent) }
        return .photo(image)
    }
    let doc = try openPDF(ref.url)
    guard let page = doc.page(at: ref.number) else { throw CompressError.cannotOpen(ref.url.lastPathComponent) }
    return .pdf(doc, page)
}
