import AppKit
import SwiftUI


struct PDFtoSizeMain: App {
    @State private var model = AppModel()

    init() {
        // Needed when started with `swift run` (no .app bundle).
        NSApplication.shared.setActivationPolicy(.regular)
    }

    var body: some Scene {
        Window("PDF to Size", id: "main") {
            ContentView(model: model)
                .frame(minWidth: 760, minHeight: 600)
                .onAppear {
                    NSApplication.shared.activate()
                    // `PDFtoSize.app/Contents/MacOS/PDFtoSize a.pdf b.pdf` opens with these files.
                    model.add(CommandLine.arguments.dropFirst().map { URL(fileURLWithPath: $0) })
                }
        }
    }
}
