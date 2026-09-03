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
        /// Every radius passes through here, which is what lets SQUARE CORNERS
        /// (`FeatureFlags.squareCorners`) flatten the whole app from one place.
        static func resolve(_ radius: CGFloat) -> CGFloat {
            FeatureFlags.squareCorners ? 0 : radius
        }

        /// The smallest steps: hairline frames and the filmstrip's thumbs (2, 4, 6pt).
        static var tiny: CGFloat { resolve(2) }
        static var chip: CGFloat { resolve(4) }
        static var small: CGFloat { resolve(6) }

        /// Standard corner radius (8pt)
        static var standard: CGFloat { resolve(8) }

        /// Between standard and large (10pt).
        static var medium: CGFloat { resolve(10) }

        /// Large corner radius (12pt)
        static var large: CGFloat { resolve(12) }

        /// Circle radius for buttons (100pt)
        static var circle: CGFloat { resolve(100) }

        /// A pill: any radius past half the height clamps to a capsule, and 0 is a box. Used
        /// where `RoundedRectangle(cornerRadius: AppConstants.CornerRadius.pill, style: .continuous)` was, so the flag can square it.
        static var pill: CGFloat { resolve(100) }

        /// Controls — segmented toggles, cards, pills (16pt).
        ///
        /// Exported by the design as `Radius/Control`. Kept as `card` in code because 21 call
        /// sites already use that name and the value is unchanged; the alias below carries the
        /// design's name for anyone reading across.
        static var card: CGFloat { resolve(16) }

        /// The design's name for the same 16pt step.
        static var control: CGFloat { card }

        /// The editor canvas's outer frame (28pt) and the photo inside it (24pt).
        ///
        /// New in the 2026-08-12 design. The 4pt difference is what makes the mint border read as
        /// a frame around the photo rather than a stroke on it — matching them collapses that.
        static var canvasOuter: CGFloat { resolve(28) }
        static var canvasInner: CGFloat { resolve(24) }
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
        /// 160pt is the design target — big enough that the thumbnail reads as a preview
        /// of the effect rather than a texture behind a label. The floor is the smallest
        /// at which a two-line effect name is still legible, and short devices land near
        /// it because the card gallery is the only part of the browse state that can give.
        static let effectCardMaxSize: CGFloat = 160
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
            // `Spacing.grid`, not `small`: the tab row now carries a 16pt bottom padding
            // to the carousel, so that is the gap the cards have to give up.
            let forCards = controlsHeight - categoryTabsHeight - Spacing.grid
            return min(effectCardMaxSize, max(effectCardMinSize, forCards))
        }

        /// Height of one control row in the effect detail panel (44pt)
        static let parameterRowHeight: CGFloat = 44

        /// Corner radius for the effect detail panel and effect cards (20pt)
        static let panelCornerRadius: CGFloat = 20
    }
}
 