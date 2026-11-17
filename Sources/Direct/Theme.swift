import AppKit
import CoreText
import SwiftUI
import DirectCore

/// Direct's look: warm paper in light mode, charcoal in dark, one lavender accent,
/// Figtree for the interface and EB Garamond for page titles.
enum Theme {
    static let background = dynamic(light: 0xF6F4EA, dark: 0x111111)
    static let panel = dynamic(light: 0xFFFEF9, dark: 0x171717)
    static let card = dynamic(light: 0xFFFFFF, dark: 0x1C1C1C)
    static let soft = dynamic(light: 0xF3F0E3, dark: 0x202020)
    static let line = dynamic(light: 0xE7E3D3, dark: 0x262626)
    static let field = dynamic(light: 0xF3F0E3, dark: 0x222222)
    static let fieldLine = dynamic(light: 0xE2DECD, dark: 0x2E2E2E)
    static let selected = dynamic(light: 0xEAE6D6, dark: 0x242424)
    static let chip = dynamic(light: 0xF1EEE1, dark: 0x262626)
    static let text = dynamic(light: 0x1D1B16, dark: 0xEDEDED)
    static let secondary = dynamic(light: 0x67635A, dark: 0xA3A3A3)
    static let tertiary = dynamic(light: 0x8E897C, dark: 0x7A7A7A)
    static let accent = dynamic(light: 0xE4D9FF, dark: 0x6E5BD6)
    static let onAccent = dynamic(light: 0x1D1B16, dark: 0xFFFFFF)
    static let accentLine = dynamic(light: 0x1D1B16, dark: 0x6E5BD6)
    static let link = dynamic(light: 0x5B3FD6, dark: 0xB3A6FF)
    static let switchOn = dynamic(light: 0x1F4D3C, dark: 0x6E5BD6)
    static let danger = dynamic(light: 0xB42318, dark: 0xFF8A7A)
    static let good = Color(hex: 0x2E9E5B)

    /// The floating picker and toast stay dark in both appearances, like a HUD.
    enum HUD {
        static let background = Color(hex: 0x161616).opacity(0.97)
        static let tile = Color(hex: 0x2A2A2A)
        static let chip = Color(hex: 0x262626)
        static let line = Color.white.opacity(0.08)
        static let text = Color(hex: 0xF2F2F2)
        static let secondary = Color(hex: 0xA3A3A3)
        static let link = Color(hex: 0xC9BDFF)
        static let accent = Color(hex: 0xE4D9FF)
    }

    static func ui(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        (fontsLoaded ? Font.custom("Figtree", size: size) : Font.system(size: size)).weight(weight)
    }

    static func display(_ size: CGFloat) -> Font {
        fontsLoaded ? Font.custom("EB Garamond", size: size).weight(.medium) : Font.system(size: size, weight: .semibold, design: .serif)
    }

    /// Registers the bundled fonts. Without them (a plain `swift run`) the system fonts stand in.
    static func registerFonts() {
        guard let folder = Bundle.main.resourceURL?.appending(path: "Fonts"),
              let files = try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)
        else { return }
        let fonts = files.filter { $0.pathExtension == "ttf" }
        for font in fonts { CTFontManagerRegisterFontsForURL(font as CFURL, .process, nil) }
        fontsLoaded = !fonts.isEmpty
    }

    nonisolated(unsafe) private static var fontsLoaded = false

    private static func dynamic(light: UInt32, dark: UInt32) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? NSColor(hex: dark) : NSColor(hex: light)
        })
    }
}

extension NSColor {
    convenience init(hex: UInt32) {
        self.init(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
                  blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
    }
}

extension Color {
    init(hex: UInt32) { self.init(nsColor: NSColor(hex: hex)) }
}

// MARK: Building blocks

struct CardBackground: ViewModifier {
    var fill: Color = Theme.card
    var outline: Color = Theme.line
    var radius: CGFloat = 16

    func body(content: Content) -> some View {
        content
            .background(fill, in: RoundedRectangle(cornerRadius: radius))
            .overlay(RoundedRectangle(cornerRadius: radius).strokeBorder(outline, lineWidth: 1))
    }
}

extension View {
    func card(fill: Color = Theme.card, outline: Color = Theme.line, radius: CGFloat = 16) -> some View {
        modifier(CardBackground(fill: fill, outline: outline, radius: radius))
    }
}

/// The one primary action on a screen.
struct AccentButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Theme.ui(14, .semibold))
            .foregroundStyle(Theme.onAccent)
            .padding(.horizontal, 16)
            .frame(height: 34)
            .background(Theme.accent, in: Capsule())
            .overlay(Capsule().strokeBorder(Theme.accentLine, lineWidth: 1))
            .opacity(configuration.isPressed ? 0.8 : 1)
    }
}

struct QuietButtonStyle: ButtonStyle {
    var fill: Color = Theme.chip

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Theme.ui(13, .semibold))
            .padding(.horizontal, 14)
            .frame(height: 32)
            .background(fill, in: Capsule())
            .opacity(configuration.isPressed ? 0.75 : 1)
    }
}

/// A browser icon with the profile's color and initial in the corner.
struct TargetIcon: View {
    var option: TargetOption?
    var browser: String
    var size: CGFloat
    var ring: Color

    init(_ option: TargetOption?, browser: String? = nil, size: CGFloat, ring: Color = Theme.card) {
        self.option = option
        self.browser = browser ?? option?.target.browser ?? ""
        self.size = size
        self.ring = ring
    }

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            if let icon = Catalog.icon(browser) {
                Image(nsImage: icon).resizable().frame(width: size, height: size)
            } else {
                RoundedRectangle(cornerRadius: size * 0.22).fill(Theme.chip).frame(width: size, height: size)
            }
            if let option, let initial = option.initial {
                let badge = max(10, size * (size > 32 ? 0.45 : 0.55))
                Text(initial)
                    .font(.system(size: max(7, badge * 0.5), weight: .bold))
                    .foregroundStyle(option.badgeText)
                    .frame(width: badge, height: badge)
                    .background(option.badge, in: Circle())
                    .overlay(Circle().strokeBorder(ring, lineWidth: 1.5))
                    .offset(x: max(2, size / 10), y: max(2, size / 10))
            }
        }
        .frame(width: size, height: size)
    }
}

/// Icon plus profile name, the way a target is shown everywhere in Direct.
struct TargetLabel: View {
    var target: Target
    var options: [TargetOption]
    var size: CGFloat = 18
    var font: Font = Theme.ui(13, .semibold)

    var body: some View {
        let option = options.first { $0.target == target }
        HStack(spacing: 7) {
            TargetIcon(option, browser: target.browser, size: size)
            Text(option?.title ?? Catalog.label(for: target, in: options)).font(font).lineLimit(1)
        }
    }
}

/// The ⌥ Option style key shown in running text.
struct KeyCap: View {
    var keys: String
    var size: CGFloat = 15

    var body: some View {
        Text(keys)
            .font(Theme.ui(size, .semibold))
            .padding(.horizontal, 10)
            .padding(.vertical, 3)
            .background(Theme.chip, in: RoundedRectangle(cornerRadius: 9))
            .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(Theme.fieldLine, lineWidth: 1))
    }
}

/// The mark, a solid disc with a path cut out, drawn from Support/Mark.svg. scripts/make-icon.swift draws the app icon from the same file.
enum DirectMark {
    /// A template image, so macOS tints it for light, dark and tinted menu bars, and SwiftUI can color it.
    nonisolated static func image(size: CGFloat) -> NSImage {
        // A plain `swift run` has no bundle resources, so the mark falls back to a system circle.
        let source = Bundle.main.url(forResource: "Mark", withExtension: "svg").flatMap(NSImage.init(contentsOf:))
            ?? NSImage(systemSymbolName: "circle", accessibilityDescription: nil)!
        let image = NSImage(size: NSSize(width: size, height: size), flipped: false) { rect in
            source.draw(in: rect)
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "Direct"
        return image
    }

    nonisolated static func menuBarImage() -> NSImage { image(size: 18) }
}
