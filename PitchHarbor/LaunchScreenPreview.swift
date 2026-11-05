// Debug-only bridge for inspecting the compiled native launch storyboard.
// Normal startup uses the storyboard configured in Xcode, not this preview view.

#if DEBUG
    import SwiftUI

    /// Displays the actual compiled launch storyboard for visual checks. The OS
    /// owns the real launch screen; this is never part of production startup.
    struct LaunchScreenPreview: UIViewControllerRepresentable {
        func makeUIViewController(context: Context) -> UIViewController {
            UIStoryboard(name: "LaunchScreen", bundle: .main).instantiateInitialViewController()!
        }
        func updateUIViewController(_ controller: UIViewController, context: Context) {}
    }

    #Preview("Native launch screen") {
        LaunchScreenPreview().ignoresSafeArea()
    }
#endif
