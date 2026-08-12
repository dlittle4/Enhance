import Foundation

/// The cell shape PIXELATE mosaics into.
///
/// Modelled as a type rather than stored in `parameterValues: [String: Double]`. That store
/// holds scalars a slider produces, and the tempting shortcut — persisting the case *index*
/// as a Double — is a trap: reordering or inserting a case silently reinterprets every
/// previously stored value, and because the store is keyed by string it surfaces as a wrong
/// setting rather than a decode error. See LEARNINGS 2026-08-10.
///
/// `public` only because `PixelateEffect`'s initialiser is, unlike the otherwise-identical
/// `LaserColor`, whose consumers (`DuotoneEffect`, `ColoredEdgesEffect`) have internal inits.
/// One module, so this is a visibility formality rather than a real boundary.
public enum PixelShape: String, CaseIterable, Identifiable, Hashable {
    case square = "SQUARE"
    case hex    = "HEX"

    public var id: String { rawValue }

    /// The Core Image filter that produces this cell shape. Both take the same centre and
    /// scale parameters, which is what makes hex nearly free.
    public var filterName: String {
        switch self {
        case .square: return "CIPixellate"
        case .hex:    return "CIHexagonalPixellate"
        }
    }
}
