import SwiftUI

// Extension for detecting visibility of views in a ScrollView
extension View {
    func viewVisibilityDetector(update: @escaping (Bool) -> Void) -> some View {
        self.overlay(
            VisibilityDetector(update: update)
        )
    }
}

// Helper struct to detect if a view is visible in a ScrollView
struct VisibilityDetector: UIViewRepresentable {
    let update: (Bool) -> Void
    
    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.backgroundColor = .clear
        view.isUserInteractionEnabled = false
        return view
    }
    
    func updateUIView(_ uiView: UIView, context: Context) {
        DispatchQueue.main.async {
            // Find the scroll view in the view hierarchy
            var scrollView: UIScrollView?
            var currentView = uiView.superview
            
            // Navigate up the view hierarchy looking for a scroll view
            while currentView != nil && scrollView == nil {
                if let sv = currentView as? UIScrollView {
                    scrollView = sv
                    break
                }
                currentView = currentView?.superview
            }
            
            guard let scrollView = scrollView else {
                // If we can't find a scroll view, assume the view is visible
                update(true)
                return
            }
            
            // Check if the view is visible in the scrollview with a margin
            // This provides a buffer so GIFs start loading slightly before they're visible
            let viewFrame = uiView.convert(uiView.bounds, to: scrollView)
            let scrollViewBounds = scrollView.bounds
            
            // Add a margin to the scroll bounds to pre-load items that are about to appear
            let preloadMargin = AppConstants.Layout.preloadMargin
            let extendedBounds = scrollViewBounds.insetBy(dx: -preloadMargin, dy: -preloadMargin)
            
            let isVisible = extendedBounds.intersects(viewFrame)
            update(isVisible)
        }
    }
}
