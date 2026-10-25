import Foundation
import PDFtoSizeCore

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data((message + "\n").utf8))
    exit(1)
}

/// "1MB", "500kb", "1200000". MB and KB are decimal, the safe reading of a portal limit.
func parseSize(_ text: String) -> Int? {
    let t = text.lowercased()
    for (suffix, unit) in [("mb", 1_000_000.0), ("kb", 1_000.0), ("b", 1.0)] where t.hasSuffix(suffix) {
        return Double(t.dropLast(suffix.count)).map { Int($0 * unit) }
    }
    return Int(t)
}

func fmt(_ bytes: Int) -> String { ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file) }

var target = 1_000_000
var strong = false
var files: [URL] = []
var args = CommandLine.arguments.dropFirst().makeIterator()
while let arg = args.next() {
    switch arg {
    case "--target":
        guard let value = args.next(), let bytes = parseSize(value) else { fail("--target needs a size, e.g. 1MB") }
        target = bytes
    case "--strong": strong = true
    default: files.append(URL(fileURLWithPath: arg))
    }
}
if files.isEmpty { fail("usage: pdftosize [--target 1MB] [--strong] file.pdf [more.pdf ...]") }

do {
    let outcome = try Compressor.run(inputs: files, target: target, allowStrong: strong)
    for p in outcome.pages { print(String(format: "%3d  %-34@ %-26@ %@", p.number, p.source as NSString, p.method as NSString, fmt(p.bytes))) }
    let sizes = "\(fmt(outcome.originalBytes)) -> \(fmt(outcome.resultBytes)), target \(fmt(outcome.target))"
    switch outcome.status {
    case .done(let url): print("Target met: \(sizes)\n\(url.path)")
    case .missed(let url): print("Target missed: \(sizes)\n\(url.path)")
    case .needsConsent: print("Safe compression stops at \(fmt(outcome.resultBytes)), target \(fmt(outcome.target)). Stronger compression gets to \(fmt(outcome.strongBytes ?? 0)): add --strong.")
    case .alreadyFits: print("Already fits: \(sizes)")
    case .notSmaller: print("Would not get smaller; original kept: \(sizes)")
    }
} catch {
    fail(error.localizedDescription)
}
