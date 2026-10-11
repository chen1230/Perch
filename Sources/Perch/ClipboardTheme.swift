import AppKit
import SwiftUI

/// The five looks for copied text. Daylight is the one the menu starts on.
enum ClipboardTheme: String, CaseIterable, Identifiable {
    case night
    case day
    case lacquer
    case spectrum
    case reflection

    var id: String { rawValue }

    var name: String {
        switch self {
        case .night: L("Night market")
        case .day: L("Daylight")
        case .lacquer: L("Lacquer")
        case .spectrum: L("Spectrum")
        case .reflection: L("Reflection")
        }
    }

    /// Stable colors for a clip, so filtering does not repaint it.
    func accent(for id: UUID) -> Color {
        let palette = Self.palette(self)
        var bytes: UInt8 = 0
        withUnsafeBytes(of: id.uuid) { raw in
            for byte in raw { bytes &+= byte }
        }
        return palette[Int(bytes) % palette.count]
    }

    fileprivate static func palette(_ theme: ClipboardTheme) -> [Color] {
        switch theme {
        case .night, .day:
            return [rgb(226, 168, 96), rgb(224, 125, 134), rgb(73, 181, 166), rgb(142, 134, 216), rgb(198, 177, 90)]
        case .lacquer:
            return [rgb(196, 82, 58), rgb(196, 132, 42), rgb(31, 122, 106), rgb(47, 76, 154), rgb(122, 62, 120)]
        case .spectrum:
            return [rgb(226, 59, 74), rgb(224, 138, 30), rgb(28, 154, 106), rgb(42, 111, 224), rgb(122, 69, 214)]
        case .reflection:
            return [rgb(92, 127, 224), rgb(122, 106, 212), rgb(196, 92, 120), rgb(212, 137, 106), rgb(61, 122, 154)]
        }
    }

    private static func rgb(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat) -> Color {
        Color(red: r / 255, green: g / 255, blue: b / 255)
    }
}

@MainActor
final class ClipboardThemes: ObservableObject {
    static let shared = ClipboardThemes()
    private static let key = "textTheme"

    @Published var current: ClipboardTheme

    private init() {
        current = ClipboardTheme(rawValue: UserDefaults.standard.string(forKey: Self.key) ?? "") ?? .day
    }

    func select(_ theme: ClipboardTheme) {
        guard theme != current else { return }
        current = theme
        UserDefaults.standard.set(theme.rawValue, forKey: Self.key)
    }
}

extension Color {
    /// `fraction` is how much of `other` replaces this color.
    func mixed(with other: Color, fraction: CGFloat) -> Color {
        let base = NSColor(self).usingColorSpace(.sRGB) ?? .black
        let target = NSColor(other).usingColorSpace(.sRGB) ?? .white
        return Color(nsColor: base.blended(withFraction: fraction, of: target) ?? base)
    }
}
