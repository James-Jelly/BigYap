import SwiftUI
#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

// MARK: - Hex colors with light/dark variants

#if os(iOS)
extension UIColor {
    fileprivate nonisolated convenience init(rgb: UInt) {
        self.init(
            red: CGFloat((rgb >> 16) & 0xFF) / 255,
            green: CGFloat((rgb >> 8) & 0xFF) / 255,
            blue: CGFloat(rgb & 0xFF) / 255,
            alpha: 1
        )
    }
}
#elseif os(macOS)
extension NSColor {
    fileprivate nonisolated convenience init(rgb: UInt) {
        self.init(
            srgbRed: CGFloat((rgb >> 16) & 0xFF) / 255,
            green: CGFloat((rgb >> 8) & 0xFF) / 255,
            blue: CGFloat(rgb & 0xFF) / 255,
            alpha: 1
        )
    }
}
#endif

extension Color {
    /// A color that resolves differently in light and dark mode, from 24-bit hex.
    /// The dynamic provider is `@Sendable`/`nonisolated` so SwiftUI's async
    /// renderer can resolve it off the main actor without tripping the Swift 6
    /// isolation checker.
    nonisolated init(light: UInt, dark: UInt) {
        #if os(iOS)
        self = Color(uiColor: UIColor { @Sendable traits in
            traits.userInterfaceStyle == .dark ? UIColor(rgb: dark) : UIColor(rgb: light)
        })
        #elseif os(macOS)
        // AppKit's dynamic provider hands back the appearance being drawn in;
        // `bestMatch` is how you ask it "is this a dark one?" without assuming
        // a specific appearance name (vibrant and accessibility variants exist).
        self = Color(nsColor: NSColor(name: nil) { @Sendable appearance in
            let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            return NSColor(rgb: isDark ? dark : light)
        })
        #endif
    }
}

// MARK: - Brand palette ("soft & polished / clean girl")

/// Soft off-white canvas (Pantone 11-4201 TCX "Cloud Dancer"), espresso ink, a
/// single soft blush accent that deepens to rose only when recording, with sage
/// as a calm secondary. Every token has a tuned dark variant.
enum Brand {
    static let canvas = Color(light: 0xF0EEE4, dark: 0x171311)
    static let surface = Color(light: 0xFFFFFF, dark: 0x221D1A)
    static let surfaceMuted = Color(light: 0xF4ECE5, dark: 0x2B2521)

    static let ink = Color(light: 0x3A2F2A, dark: 0xF3ECE5)
    static let inkSecondary = Color(light: 0x8C7D74, dark: 0xB6A99E)
    static let inkTertiary = Color(light: 0xB6A89E, dark: 0x83766C)
    static let hairline = Color(light: 0xEADFD6, dark: 0x382F29)

    // Soft dusty rose in the Pantone 11-1400 TCX "Raindrops on Roses" family.
    // `blush` keeps enough depth to read against the canvas and behind white
    // icons; `blushSoft` is the pale Pantone tint itself.
    static let blush = Color(light: 0xD9A6AC, dark: 0xE0A6AD)
    static let blushSoft = Color(light: 0xECD9DA, dark: 0x3A2A2C)
    static let rose = Color(light: 0xC2606C, dark: 0xD3737F)
    static let sage = Color(light: 0x8FA693, dark: 0x9DB4A1)
    static let sageSoft = Color(light: 0xEAF0EB, dark: 0x26302A)
}

// MARK: - Spacing & shape

enum Spacing {
    static let xs: CGFloat = 4
    static let sm: CGFloat = 8
    static let md: CGFloat = 12
    static let lg: CGFloat = 16
    static let xl: CGFloat = 24
    static let xxl: CGFloat = 32
}

enum Radius {
    static let sm: CGFloat = 12
    static let md: CGFloat = 18
    static let lg: CGFloat = 24
    static let pill: CGFloat = 999
}

// MARK: - Typography (SF Rounded, Dynamic Type driven)

extension Font {
    static func brand(_ style: Font.TextStyle, weight: Font.Weight = .regular) -> Font {
        .system(style, design: .rounded).weight(weight)
    }

    static let brandDisplay = Font.system(.largeTitle, design: .rounded).weight(.semibold)
    static let brandTitle = Font.system(.title2, design: .rounded).weight(.semibold)
    static let brandHeadline = Font.system(.headline, design: .rounded)
    static let brandBody = Font.system(.body, design: .rounded)
    static let brandCaption = Font.system(.caption, design: .rounded)
}

// MARK: - Reusable surface styling

private struct SoftCard: ViewModifier {
    var padding: CGFloat = Spacing.lg
    var radius: CGFloat = Radius.md

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(Brand.surface, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(Brand.hairline, lineWidth: 1)
            )
    }
}

extension View {
    /// A soft, rounded brand card: warm surface, hairline border, continuous corners.
    func softCard(padding: CGFloat = Spacing.lg, radius: CGFloat = Radius.md) -> some View {
        modifier(SoftCard(padding: padding, radius: radius))
    }
}

// MARK: - Primary button style

struct BrandPrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.brand(.headline, weight: .semibold))
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, Spacing.md + 2)
            .background(Brand.blush, in: RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
            .opacity(configuration.isPressed ? 0.85 : 1)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

extension ButtonStyle where Self == BrandPrimaryButtonStyle {
    static var brandPrimary: BrandPrimaryButtonStyle { BrandPrimaryButtonStyle() }
}
