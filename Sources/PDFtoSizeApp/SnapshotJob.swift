import AppKit
import PDFtoSizeCore
import SwiftUI

/// `PDFtoSizeApp --snapshot out.png [--dark] [--compress [--strong]] [--target 1.5] a.pdf b.pdf`
/// Draws the window content and writes a PNG, so the UI can be checked without a screen.
@MainActor
struct SnapshotJob {
    private static let WIDTH: CGFloat = 760
    private static let SCALE: CGFloat = 2
    private static let SETTLE_SECONDS = 0.4

    let arguments: [String]

    init?(arguments: [String]) {
        guard arguments.contains("--snapshot") else { return nil }
        self.arguments = arguments
    }

    private func value(after flag: String) -> String? {
        arguments.firstIndex(of: flag).flatMap { arguments.indices.contains($0 + 1) ? arguments[$0 + 1] : nil }
    }

    func run() -> Int32 {
        guard let output = value(after: "--snapshot") else { return 1 }
        _ = NSApplication.shared
        NSApp.appearance = NSAppearance(named: arguments.contains("--dark") ? .darkAqua : .aqua)
        let model = AppModel()
        model.add(arguments.dropFirst().map { URL(fileURLWithPath: $0) })
        if let target = value(after: "--target").flatMap(Double.init) { model.targetValue = target }
        if arguments.contains("--compress") {
            model.allowStrong = arguments.contains("--strong")
            do {
                let outcome = try Compressor.run(inputs: model.files.map(\.url), target: model.targetBytes, allowStrong: model.allowStrong)
                model.phase = .finished(outcome)
            } catch {
                model.phase = .failed(error.localizedDescription)
            }
        }
        return write(ContentView(model: model).content.background(Color(nsColor: .windowBackgroundColor)), to: output) ? 0 : 1
    }

    private func write<V: View>(_ view: V, to path: String) -> Bool {
        let width = SnapshotJob.WIDTH
        let host = NSHostingView(rootView: view.frame(width: width))
        host.frame = NSRect(x: 0, y: 0, width: width, height: 100)
        let window = NSWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.appearance = NSApp.appearance
        window.contentView = host
        host.layoutSubtreeIfNeeded()
        let size = NSSize(width: width, height: ceil(host.fittingSize.height))
        window.setContentSize(size)
        host.frame = NSRect(origin: .zero, size: size)
        host.layoutSubtreeIfNeeded()
        // Let SwiftUI finish its layout passes before drawing.
        RunLoop.current.run(until: Date().addingTimeInterval(SnapshotJob.SETTLE_SECONDS))
        host.layoutSubtreeIfNeeded()

        guard let bitmap = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: Int(size.width * SnapshotJob.SCALE), pixelsHigh: Int(size.height * SnapshotJob.SCALE),
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
        ) else { return false }
        bitmap.size = size
        host.cacheDisplay(in: host.bounds, to: bitmap)
        guard let png = bitmap.representation(using: .png, properties: [:]) else { return false }
        do {
            try png.write(to: URL(fileURLWithPath: path))
            print("Wrote \(path) (\(Int(size.width))x\(Int(size.height)) points)")
            return true
        } catch {
            print("Could not write \(path): \(error)")
            return false
        }
    }
}
