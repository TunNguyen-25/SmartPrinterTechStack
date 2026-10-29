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
    func makeUIViewController(context: Context) -> UINavigationController {
        let navigation = UINavigationController()
        let coordinator = PrintFlowCoordinator(container: PrintFlowContainer(), navigationController: navigation)
        navigation.viewControllers = [HomeViewController(samples: SampleDocuments.make(), onPick: coordinator.open)]
        return navigation
    }

    func updateUIViewController(_ controller: UINavigationController, context: Context) {}
}
