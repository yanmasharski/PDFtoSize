import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

func render(_ page: Content, dpi: Double, gray: Bool) -> CGImage? {
    let size = page.outputSize
    let scale = dpi / 72
    let w = max(1, Int((size.width * scale).rounded()))
    let h = max(1, Int((size.height * scale).rounded()))
    let space = gray ? CGColorSpaceCreateDeviceGray() : CGColorSpaceCreateDeviceRGB()
    let info = gray ? CGImageAlphaInfo.none.rawValue : CGImageAlphaInfo.noneSkipLast.rawValue
    guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                              space: space, bitmapInfo: info) else { return nil }
    ctx.setFillColor(CGColor(gray: 1, alpha: 1))
    ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
    ctx.interpolationQuality = .high
    ctx.scaleBy(x: CGFloat(w) / size.width, y: CGFloat(h) / size.height)
    page.draw(in: ctx, size: size)
    return ctx.makeImage()
}

func jpeg(_ image: CGImage, quality: Double) -> Data? {
    let data = NSMutableData()
    guard let dest = CGImageDestinationCreateWithData(data, UTType.jpeg.identifier as CFString, 1, nil) else { return nil }
    CGImageDestinationAddImage(dest, image, [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary)
    return CGImageDestinationFinalize(dest) ? data as Data : nil
}

/// True when under 3% of the pixels have a visible tint. Cheap: one 50 dpi render, one pass over the bytes.
/// Real contract scans measured 0.6-1.6% (blue ink, stamps), so the limit leaves room for them.
/// A colored stamp or signature is lost in gray or black and white, which is why those need the user's consent.
func isColorless(_ page: Content) -> Bool {
    guard let img = render(page, dpi: 50, gray: false),
          let data = img.dataProvider?.data,
          let p = CFDataGetBytePtr(data) else { return false }
    var tinted = 0
    for y in 0..<img.height {
        var o = y * img.bytesPerRow
        for _ in 0..<img.width {
            let r = Int(p[o]), g = Int(p[o + 1]), b = Int(p[o + 2])
            if max(r, g, b) - min(r, g, b) > 32 { tinted += 1 }
            o += 4
        }
    }
    return Double(tinted) / Double(img.width * img.height) < 0.03
}

private final class ImageSizes {
    var largest = (width: 0, height: 0)
}

/// Pixel size of the largest image XObject listed on the page itself.
/// shortcut: resources inherited from the page tree and images inside form XObjects are not seen; look into them if real files need it.
func largestImage(_ page: CGPDFPage) -> (width: Int, height: Int)? {
    var resources: CGPDFDictionaryRef?
    var xobjects: CGPDFDictionaryRef?
    guard let dict = page.dictionary,
          CGPDFDictionaryGetDictionary(dict, "Resources", &resources), let resources,
          CGPDFDictionaryGetDictionary(resources, "XObject", &xobjects), let xobjects else { return nil }
    let sizes = ImageSizes()
    CGPDFDictionaryApplyFunction(xobjects, { _, object, info in
        var stream: CGPDFStreamRef?
        var w: CGPDFInteger = 0, h: CGPDFInteger = 0
        guard CGPDFObjectGetValue(object, .stream, &stream), let stream,
              let d = CGPDFStreamGetDictionary(stream),
              CGPDFDictionaryGetInteger(d, "Width", &w), CGPDFDictionaryGetInteger(d, "Height", &h) else { return }
        let sizes = Unmanaged<ImageSizes>.fromOpaque(info!).takeUnretainedValue()
        if w * h > sizes.largest.width * sizes.largest.height { sizes.largest = (w, h) }
    }, Unmanaged.passUnretained(sizes).toOpaque())
    return sizes.largest.width > 0 ? sizes.largest : nil
}

/// Black and white by local threshold: a pixel is ink when it is clearly darker than its
/// neighborhood, so uneven scan lighting does not turn into black blobs. 1 bit per pixel.
func monochrome(_ gray: CGImage) -> CGImage? {
    guard let data = gray.dataProvider?.data, let p = CFDataGetBytePtr(data) else { return nil }
    let w = gray.width, h = gray.height, stride = gray.bytesPerRow
    let iw = w + 1
    var integral = [UInt32](repeating: 0, count: iw * (h + 1))
    for y in 0..<h {
        var row: UInt32 = 0
        for x in 0..<w {
            row += UInt32(p[y * stride + x])
            integral[(y + 1) * iw + x + 1] = integral[y * iw + x + 1] &+ row
        }
    }
    let r = max(8, max(w, h) / 40)
    let rowBytes = (w + 7) / 8
    var bits = [UInt8](repeating: 0xFF, count: rowBytes * h)
    for y in 0..<h {
        let y0 = max(0, y - r), y1 = min(h, y + r + 1)
        for x in 0..<w {
            let x0 = max(0, x - r), x1 = min(w, x + r + 1)
            let sum = Int(integral[y1 * iw + x1]) - Int(integral[y0 * iw + x1]) - Int(integral[y1 * iw + x0]) + Int(integral[y0 * iw + x0])
            let mean = sum / ((x1 - x0) * (y1 - y0))
            let v = Int(p[y * stride + x])
            if v * 100 < mean * 85 || v < 80 { bits[y * rowBytes + x >> 3] &= ~(0x80 >> UInt8(x & 7)) }
        }
    }
    guard let provider = CGDataProvider(data: Data(bits) as CFData) else { return nil }
    return CGImage(width: w, height: h, bitsPerComponent: 1, bitsPerPixel: 1, bytesPerRow: rowBytes,
                   space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGBitmapInfo(rawValue: 0), provider: provider,
                   decode: nil, shouldInterpolate: false, intent: .defaultIntent)
}
