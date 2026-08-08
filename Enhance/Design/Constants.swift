import SwiftUI

/// App-wide constants for consistent styling and layout
enum AppConstants {
    /// Spacing values for consistent layout throughout the app
    enum Spacing {
        /// Grid spacing (16pt)
        static let grid: CGFloat = 16
        
        /// Vertical spacing between sections (24pt)
        static let section: CGFloat = 24
        
        /// Standard content padding (20pt)
        static let standard: CGFloat = 24
        
        /// Small spacing for tight layouts (8pt)
        static let small: CGFloat = 8
        
        /// Extra small spacing (4pt)
        static let xsmall: CGFloat = 4
        
        /// Large spacing (32pt)
        static let large: CGFloat = 32
    }
    
    /// Standard corner radius values
    enum CornerRadius {
        /// Standard corner radius (8pt)
        static let standard: CGFloat = 8
        
        /// Large corner radius (12pt)
        static let large: CGFloat = 12
        
        /// Circle radius for buttons (100pt)
        static let circle: CGFloat = 100
    }
    
    /// Animation durations
    enum Animation {
        /// Standard animation duration (0.3s)
        static let standard: Double = 0.3
        
        /// Quick animation duration (0.15s)
        static let quick: Double = 0.15
        
        /// Slow animation duration (0.6s)
        static let slow: Double = 0.6
    }
    
    /// Zoom scale constants
    enum Zoom {
        /// Maximum zoom scale allowed in the app (50.0)
        static let maxScale: CGFloat = 50.0
    }

    /// Layout-specific constants
    enum Layout {
        /// Height for GIF thumbnails in the gallery (160pt)
        static let gifThumbnailHeight: CGFloat = 160
        
        /// Preload margin for lazy loading content in scroll views (200pt)
        static let preloadMargin: CGFloat = 200

        /// Height of the effect category icon row (42pt)
        static let categoryTabsHeight: CGFloat = 42

        /// Bounds on the side of a square effect card.
        ///
        /// The upper bound is the Figma size; the lower is the smallest at which a
        /// two-line effect name still fits legibly.
        static let effectCardMaxSize: CGFloat = 110
        static let effectCardMinSize: CGFloat = 64

        /// Side of a square effect card, given the height available to the whole
        /// controls area (category tabs plus the card gallery).
        ///
        /// Cards are square, so the *vertical* budget decides their size. A fixed
        /// constant large enough for a 6.9" screen overflows a 4.7" one, and the browse
        /// state — unlike the detail panel — has no scroll to fall back on. Deriving the
        /// size from measured space means one layout adapts instead of special-casing
        /// short devices.
        static func effectCardSize(forControlsHeight controlsHeight: CGFloat) -> CGFloat {
            let forCards = controlsHeight - categoryTabsHeight - Spacing.small
            return min(effectCardMaxSize, max(effectCardMinSize, forCards))
        }

        /// Height of one control row in the effect detail panel (44pt)
        static let parameterRowHeight: CGFloat = 44

        /// Corner radius for the effect detail panel and effect cards (20pt)
        static let panelCornerRadius: CGFloat = 20
    }
}
 