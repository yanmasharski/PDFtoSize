import CoreGraphics
import Foundation

public enum Status {
    case done(URL)        // target met, file written
    case missed(URL)      // target not reachable; the smallest result was written
    case needsConsent     // only the stronger levels reach the target; nothing written yet
    case alreadyFits      // single input already under the target; nothing written
    case notSmaller       // single input would not shrink; nothing written
}

public enum Treatment {
    case kept, smaller, gray, blackWhite
}

public struct PageReport {
    public let number: Int          // position in the result, from 1
    public let url: URL
    public let pageInFile: Int
    public let treatment: Treatment
    public let method: String       // plain-language description
    public let bytes: Int           // size of this page in the result
    public let originalBytes: Int   // size of this page before, as it was
    public let alreadyCompact: Bool // no smaller version of this page was found

    public var source: String { "\(url.lastPathComponent) p.\(pageInFile)" }
}

public struct Outcome {
    public let status: Status
    public let target: Int
    public let originalBytes: Int
    public let resultBytes: Int
    public let strongBytes: Int?   // with .needsConsent: how small the stronger levels get
    public let pages: [PageReport]
}

/// One way to produce one page. A page's candidates form a ladder from best quality to smallest.
struct Candidate {
    let piece: Piece
    let bytes: Int
    let loss: Double      // quality given up; 0 = original
    let method: String
    let treatment: Treatment
}

enum Tier { case safe, strong }

// Page pictures are sized by their long side in pixels. "A4 dpi" is that size spread over an A4 long side
// (11.69 in), so pages of any physical size are judged by the same readability scale.
// Safe: colors kept, text stays crisp. Strong: needs the user's consent.
private let a4LongSide = 11.69
private let safeMinDpi = 150.0
private let strongMinDpi = 95.0
private let sizeStep = 0.8            // each smaller picture is 20% smaller than the one before
private let grayPenalty = 0.25
private let monoPenalty = 0.8
private let maxIterations = 5

public enum Compressor {
    public static func run(inputs: [URL], target: Int, allowStrong: Bool,
                           progress: @escaping (Double, String) -> Void = { _, _ in }) throws -> Outcome {
        let original = inputs.reduce(0) { $0 + fileSize($1) }
        func outcome(_ status: Status, bytes: Int = 0, strong: Int? = nil, pages: [PageReport] = []) -> Outcome {
            Outcome(status: status, target: target, originalBytes: original, resultBytes: bytes, strongBytes: strong, pages: pages)
        }
        if inputs.count == 1, !isPhoto(inputs[0]), original <= target { return outcome(.alreadyFits, bytes: original) }

        let refs = try pageRefs(inputs)
        progress(0, "Analyzing \(refs.count) pages…")
        let tiers: [Tier] = allowStrong ? [.safe, .strong] : [.safe]
        var candidates = gather(refs, tiers: tiers) { progress($0 * 0.8, "Analyzing pages…") }

        if let i = candidates.firstIndex(where: \.isEmpty) { throw CompressError.cannotOpen(refs[i].url.lastPathComponent) }
        progress(0.8, "Fitting to the target…")
        var result = try fit(ladders(candidates), refs: refs, target: target)

        if result.best == nil, !allowStrong {
            // Would stronger levels help? Ask the user before using them.
            let more = gather(refs, tiers: [.strong]) { progress(0.8 + $0 * 0.15, "Checking stronger levels…") }
            candidates = zip(candidates, more).map { $0 + $1 }
            let probe = try fit(ladders(candidates), refs: refs, target: target)
            if probe.smallest.data.count < result.smallest.data.count * 95 / 100 {
                return outcome(.needsConsent, bytes: result.smallest.data.count, strong: probe.smallest.data.count, pages: result.smallest.pages)
            }
        }

        let chosen = result.best ?? result.smallest
        if inputs.count == 1, !isPhoto(inputs[0]), chosen.data.count >= original || chosen.pages.allSatisfy({ $0.treatment == .kept }) { return outcome(.notSmaller, bytes: chosen.data.count) }
        let url = outputURL(for: inputs)
        do { try chosen.data.write(to: url, options: .atomic) } catch { throw CompressError.cannotWrite(url.lastPathComponent) }
        progress(1, "Done")
        let pages = normalized(chosen.pages, resultBytes: chosen.data.count, fileSizes: Dictionary(uniqueKeysWithValues: inputs.map { ($0, fileSize($0)) }))
        return outcome(result.best != nil ? .done(url) : .missed(url), bytes: chosen.data.count, pages: pages)
    }
}

/// Page sizes are measured one page at a time, so fonts and file overhead are counted per page.
/// "Before" adds up to the real input file. A kept page is the same page, so "after" = "before".
/// The pages that changed share the rest of the real result.
func normalized(_ pages: [PageReport], resultBytes: Int, fileSizes: [URL: Int]) -> [PageReport] {
    var beforeSums: [URL: Int] = [:]
    for p in pages { beforeSums[p.url, default: 0] += p.originalBytes }
    func before(_ p: PageReport) -> Int { (fileSizes[p.url] ?? 0) * p.originalBytes / max(beforeSums[p.url] ?? 1, 1) }
    let keptBytes = pages.filter { $0.treatment == .kept }.reduce(0) { $0 + before($1) }
    let changedSum = max(pages.filter { $0.treatment != .kept }.reduce(0) { $0 + $1.bytes }, 1)
    let changedBudget = max(resultBytes - keptBytes, 0)
    return pages.map { p in
        let b = before(p)
        return PageReport(number: p.number, url: p.url, pageInFile: p.pageInFile, treatment: p.treatment, method: p.method,
                          bytes: p.treatment == .kept ? b : p.bytes * changedBudget / changedSum,
                          originalBytes: b, alreadyCompact: p.alreadyCompact)
    }
}

struct Fit {
    let data: Data
    let pages: [PageReport]
    let loss: Double
}

/// Sorts by quality, then keeps only candidates that are strictly smaller than the one before.
func ladders(_ candidates: [[Candidate]]) -> [[Candidate]] {
    candidates.map { list in
        var kept: [Candidate] = []
        for c in list.sorted(by: { $0.loss < $1.loss }) where kept.last.map({ c.bytes < $0.bytes }) ?? true {
            kept.append(c)
        }
        return kept
    }
}

/// Starts every page at its best candidate, then steps down the page where
/// one step costs the least quality per byte saved, until the estimate fits the budget.
func pick(_ ladders: [[Candidate]], budget: Int) -> [Int] {
    var index = Array(repeating: 0, count: ladders.count)
    var total = ladders.reduce(0) { $0 + ($1.first?.bytes ?? 0) }
    while total > budget {
        var best = -1
        var bestCost = Double.infinity
        for (i, ladder) in ladders.enumerated() where index[i] + 1 < ladder.count {
            let a = ladder[index[i]], b = ladder[index[i] + 1]
            let cost = (b.loss - a.loss) / Double(a.bytes - b.bytes)
            if cost < bestCost { bestCost = cost; best = i }
        }
        if best < 0 { break }
        total -= ladders[best][index[best]].bytes - ladders[best][index[best] + 1].bytes
        index[best] += 1
    }
    return index
}

/// Page estimates ignore shared fonts and file overhead, so the real size differs.
/// Build the real file, compare it with the target, adjust the budget, repeat.
func fit(_ ladders: [[Candidate]], refs: [PageRef], target: Int) throws -> (best: Fit?, smallest: Fit) {
    var budget = target
    var best: Fit?
    var smallest: Fit?
    var tried: [[Int]] = []
    for _ in 0..<maxIterations {
        let choice = pick(ladders, budget: budget)
        if tried.contains(choice) { break }
        tried.append(choice)

        let picked = zip(ladders, choice).map { $0[$1] }
        let data = try assemble(picked.map(\.piece))
        let pages = picked.enumerated().map { i, c in
            PageReport(number: i + 1, url: refs[i].url, pageInFile: refs[i].number, treatment: c.treatment,
                       method: c.method, bytes: c.bytes, originalBytes: ladders[i][0].bytes,
                       alreadyCompact: ladders[i].count == 1)
        }
        let f = Fit(data: data, pages: pages, loss: picked.reduce(0) { $0 + $1.loss })
        if smallest == nil || data.count < smallest!.data.count { smallest = f }
        if data.count <= target, best == nil || f.loss < best!.loss { best = f }

        let ratio = Double(target) / Double(data.count)
        if data.count <= target, ratio < 1.03 { break }
        budget = Int(Double(budget) * ratio * (data.count > target ? 0.99 : 1))
    }
    return (best, smallest!)
}

private func gather(_ refs: [PageRef], tiers: [Tier], progress: (Double) -> Void) -> [[Candidate]] {
    var out = [[Candidate]](repeating: [], count: refs.count)
    let lock = NSLock()
    var done = 0
    out.withUnsafeMutableBufferPointer { buf in
        DispatchQueue.concurrentPerform(iterations: refs.count) { i in
            buf[i] = tiers.flatMap { candidates(for: refs[i], tier: $0) }
            lock.lock(); done += 1; let d = done; lock.unlock()
            progress(Double(d) / Double(refs.count))
        }
    }
    return out
}

private func candidates(for ref: PageRef, tier: Tier) -> [Candidate] {
    // Each worker opens its own document: CGPDFDocument is not shared between threads.
    guard let page = try? openContent(ref) else { return [] }
    let size = page.outputSize
    let longPts = Double(max(size.width, size.height))
    var out: [Candidate] = []
    var renders: [String: CGImage] = [:]

    // The picture sizes to try. A scan starts at the size of its own image and shrinks by 20% steps,
    // never above it. A page without a big image starts at 220 A4 dpi.
    var native: Double?
    switch page {
    case .pdf(_, let pdfPage):
        if let img = largestImage(pdfPage), Double(img.width * img.height) >= 0.25 * Double(size.width * size.height) {
            native = Double(max(img.width, img.height))
        }
    case .photo(let image):
        native = Double(max(image.width, image.height))
    }
    var longSides: [Double] = []
    var side = native ?? 220 * a4LongSide
    while side / a4LongSide >= strongMinDpi {
        longSides.append(side)
        side *= sizeStep
    }

    func picture(_ longSide: Double, gray: Bool) -> CGImage? {
        let key = "\(longSide)-\(gray)"
        if let cached = renders[key] { return cached }
        let image = render(page, dpi: longSide * 72 / longPts, gray: gray)
        renders[key] = image
        return image
    }
    func loss(_ longSide: Double, _ extra: Double) -> Double { log(300 / (longSide / a4LongSide)) + extra }

    func jpegCandidate(_ longSide: Double, _ quality: Double, gray: Bool) {
        guard let image = picture(longSide, gray: gray), let data = jpeg(image, quality: quality) else { return }
        let what = gray ? "Gray" : (isPhoto(ref.url) ? "Photo" : "Smaller picture")
        let method = "\(what), \(Int(longSide)) px, quality \(Int(quality * 100))"
        out.append(Candidate(piece: .jpeg(data, size), bytes: data.count,
                             loss: loss(longSide, (1 - quality) + (gray ? grayPenalty : 0)), method: method,
                             treatment: gray ? .gray : .smaller))
    }

    switch tier {
    case .safe:
        let piece = Piece.vector(ref, size)
        // A photo has no "as it was" page: it is always a new picture.
        if !isPhoto(ref.url), let bytes = try? assemble([piece]).count {
            out.append(Candidate(piece: piece, bytes: bytes, loss: 0, method: "Kept as it was", treatment: .kept))
        }
        var sides = longSides.filter { $0 / a4LongSide >= safeMinDpi }
        // A small photo is below the safe size already, but it must still become a page.
        if sides.isEmpty, isPhoto(ref.url), let native { sides = [native] }
        for l in sides {
            for q in [0.7, 0.5] { jpegCandidate(l, q, gray: false) }
        }
    case .strong:
        let gray = isColorless(page)
        for l in longSides where l / a4LongSide < safeMinDpi {
            jpegCandidate(l, 0.5, gray: false)
            if gray { jpegCandidate(l, 0.5, gray: true) }
        }
        if gray {
            // Text pages: black and white at 200 and 150 A4 dpi (never above the scan's own size).
            for dpi in [200.0, 150.0] {
                let l = min(dpi * a4LongSide, native ?? .infinity)
                guard let g = picture(l, gray: true), let mono = monochrome(g) else { continue }
                let piece = Piece.mono(mono, size)
                guard let bytes = try? assemble([piece]).count else { continue }
                out.append(Candidate(piece: piece, bytes: bytes, loss: loss(l, monoPenalty), method: "Black & white, \(Int(l)) px", treatment: .blackWhite))
            }
        }
    }
    return out
}

private func fileSize(_ url: URL) -> Int {
    (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
}

private func outputURL(for inputs: [URL]) -> URL {
    let dir = inputs[0].deletingLastPathComponent()
    let base = inputs.count == 1 ? inputs[0].deletingPathExtension().lastPathComponent + "-compressed" : "merged-compressed"
    var url = dir.appendingPathComponent(base + ".pdf")
    var n = 2
    while FileManager.default.fileExists(atPath: url.path) {
        url = dir.appendingPathComponent("\(base)-\(n).pdf")
        n += 1
    }
    return url
}
