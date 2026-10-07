import SwiftUI

/// هوية «مشوارك أسهل» — اتجاه «بوابة الوصول»: أخضر المسار، سماء، برتقالي للتنبيهات، ليل للنص.
public enum BZColor {
    public static let green = Color(hex: 0x15B98F)
    public static let greenDark = Color(hex: 0x0E8F6E)
    public static let greenTint = Color(hex: 0xE3F7F1)
    public static let sky = Color(hex: 0x20A6D8)
    public static let skyTint = Color(hex: 0xE3F3FA)
    public static let orange = Color(hex: 0xF2994A)
    public static let orangeDark = Color(hex: 0xD97A2B)
    public static let orangeTint = Color(hex: 0xFDEEDF)
    public static let ink = Color(hex: 0x0E1C22)
    public static let night = Color(hex: 0x12343E)
    public static let mute = Color(hex: 0x6B7A78)
    public static let sand = Color(hex: 0xEDEBE6)
    public static let paper = Color(hex: 0xFAF8F4)
    public static let mapBase = Color(hex: 0xEEF1EF)
    public static let line = Color(hex: 0xE2E5E3)
    public static let chipBg = Color(hex: 0xF1F3F2)
    public static let danger = Color(hex: 0xC0392B)
    public static let card = Color.white
}

public enum BZFont {
    /// الخط العربي الأساسي: نعتمد خط النظام (SF Arabic) افتراضيًا، ويمكن تبديله بـ Noto Kufi Arabic عند تضمينه.
    public static var family: String? = nil

    public static func font(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        if let family { return .custom(family, size: size).weight(weight) }
        return .system(size: size, weight: weight, design: .default)
    }

    public static let largeTitle = font(26, weight: .heavy)
    public static let title = font(22, weight: .heavy)
    public static let headline = font(18, weight: .bold)
    public static let body = font(16, weight: .semibold)
    public static let bodyRegular = font(15, weight: .regular)
    public static let caption = font(13, weight: .medium)
    public static let small = font(12, weight: .regular)
    public static let mono = Font.system(size: 11, weight: .medium, design: .monospaced)
}

public enum BZRadius {
    public static let card: CGFloat = 20
    public static let control: CGFloat = 16
    public static let chip: CGFloat = 999
    public static let sheet: CGFloat = 28
}

public enum BZShadow {
    public static func soft<V: View>(_ v: V) -> some View { v.shadow(color: BZColor.ink.opacity(0.10), radius: 12, x: 0, y: 4) }
    public static func strong<V: View>(_ v: V) -> some View { v.shadow(color: BZColor.ink.opacity(0.14), radius: 20, x: 0, y: 8) }
}

public extension Color {
    init(hex: UInt32, alpha: Double = 1) {
        self.init(.sRGB, red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255, blue: Double(hex & 0xFF) / 255, opacity: alpha)
    }
}

/// رمز «بوابة الوصول» (الدبوس المفتوح) — SVG الهوية مرسوم بـ Path.
public struct BZLogo: View {
    public var color: Color
    public init(color: Color = BZColor.green) { self.color = color }

    public var body: some View {
        GeometryReader { geo in
            let s = min(geo.size.width, geo.size.height) / 100
            ZStack {
                Path { p in
                    // قوس ثلاثة أرباع الدائرة + ذيل + نقطة مركزية
                    p.addArc(center: CGPoint(x: 50 * s, y: 50 * s), radius: 32 * s, startAngle: .degrees(165), endAngle: .degrees(75), clockwise: false)
                }
                .stroke(color, style: StrokeStyle(lineWidth: 10 * s, lineCap: .round, lineJoin: .round))
                Path { p in
                    p.move(to: CGPoint(x: 12 * s, y: 88 * s))
                    p.addLine(to: CGPoint(x: 50 * s, y: 50 * s))
                }
                .stroke(color, style: StrokeStyle(lineWidth: 10 * s, lineCap: .round))
                Circle().fill(color).frame(width: 14 * s, height: 14 * s).position(x: 50 * s, y: 50 * s)
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .accessibilityHidden(true)
    }
}
