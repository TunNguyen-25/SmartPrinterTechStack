import SwiftUI
import PrintFlowKit

@main
struct PrintFlowDemoApp: App {
    init() { SelfTest.runIfRequested() }

    var body: some Scene {
        WindowGroup {
            RootView().ignoresSafeArea()
        }
    }
}

/// Dựng container + coordinator một lần, gắn vào navigation controller gốc.
private struct RootView: UIViewControllerRepresentable {
    final class Coordinator {
        var flow: PrintFlowCoordinator?
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIViewController(context: Context) -> UINavigationController {
        let navigation = UINavigationController()
        let container = PrintFlowContainer()
        SampleDocuments.seedIfEmpty(container.library)
        let coordinator = PrintFlowCoordinator(container: container, navigationController: navigation)
        context.coordinator.flow = coordinator
        coordinator.start()
        return navigation
    }

    func updateUIViewController(_ controller: UINavigationController, context: Context) {}
}
