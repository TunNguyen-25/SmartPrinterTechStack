import SwiftUI

@main
struct DocumentScannerDemoApp: App {
    init() { SelfTest.runIfRequested() }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
