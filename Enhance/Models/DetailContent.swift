import UIKit

enum DetailContent {
    case newImage(UIImage)
    /// URL, gallery index, PHAsset local identifier
    case existingGif(URL, Int, String)
}
