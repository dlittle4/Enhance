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
    }
}
 