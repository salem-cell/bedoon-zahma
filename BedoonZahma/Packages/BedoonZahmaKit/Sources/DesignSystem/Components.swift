import SwiftUI

// MARK: - الأزرار

public struct PrimaryButton: View {
    var title: String
    var color: Color
    var foreground: Color
    var action: () -> Void

    public init(_ title: String, color: Color = BZColor.green, foreground: Color = BZColor.ink, action: @escaping () -> Void) {
        self.title = title; self.color = color; self.foreground = foreground; self.action = action
    }

    public var body: some View {
        Button(action: action) {
            Text(title)
                .font(BZFont.headline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 17)
                .background(color, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                .foregroundStyle(foreground)
        }
        .buttonStyle(PressableStyle())
    }
}

public struct PressableStyle: ButtonStyle {
    public init() {}
    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .opacity(configuration.isPressed ? 0.9 : 1)
            .animation(.easeOut(duration: 0.1), value: configuration.isPressed)
    }
}

public struct RoundIconButton: View {
    var systemName: String
    var tint: Color
    var action: () -> Void
    public init(_ systemName: String, tint: Color = BZColor.ink, action: @escaping () -> Void) {
        self.systemName = systemName; self.tint = tint; self.action = action
    }
    public var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 44, height: 44)
                .background(Color.white, in: Circle())
                .shadow(color: BZColor.ink.opacity(0.1), radius: 8, y: 3)
        }
        .buttonStyle(PressableStyle())
    }
}

// MARK: - الشرائح والمقاطع

public struct Chip: View {
    var title: String
    var selected: Bool
    var selectedColor: Color
    var action: () -> Void
    public init(_ title: String, selected: Bool, selectedColor: Color = BZColor.sky, action: @escaping () -> Void) {
        self.title = title; self.selected = selected; self.selectedColor = selectedColor; self.action = action
    }
    public var body: some View {
        Button(action: action) {
            Text(title)
                .font(BZFont.caption.weight(.semibold))
                .lineLimit(1)
                .padding(.horizontal, 14).padding(.vertical, 8)
                .background(selected ? selectedColor : Color.white, in: Capsule())
                .foregroundStyle(selected ? .white : BZColor.ink)
                .overlay(Capsule().strokeBorder(selected ? selectedColor : BZColor.line, lineWidth: 1))
        }
        .buttonStyle(PressableStyle())
    }
}

public struct SegmentedPill<T: Hashable>: View {
    var options: [(T, String)]
    @Binding var selection: T
    public init(options: [(T, String)], selection: Binding<T>) { self.options = options; _selection = selection }
    public var body: some View {
        HStack(spacing: 0) {
            ForEach(options, id: \.0) { value, label in
                Button { withAnimation(.easeOut(duration: 0.15)) { selection = value } } label: {
                    Text(label)
                        .font(BZFont.caption.weight(.bold))
                        .padding(.horizontal, 14).padding(.vertical, 7)
                        .background(selection == value ? BZColor.sky : .clear, in: Capsule())
                        .foregroundStyle(selection == value ? .white : BZColor.ink)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(3)
        .background(Color(hex: 0xE9ECEA), in: Capsule())
    }
}

public struct TimeFilterButton: View {
    var title: String
    var selected: Bool
    var action: () -> Void
    public init(_ title: String, selected: Bool, action: @escaping () -> Void) { self.title = title; self.selected = selected; self.action = action }
    public var body: some View {
        Button(action: action) {
            Text(title)
                .font(BZFont.caption.weight(.bold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 11)
                .background(selected ? BZColor.sky : Color.white, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(selected ? BZColor.sky : BZColor.line, lineWidth: 1.5))
                .foregroundStyle(selected ? .white : BZColor.ink)
        }
        .buttonStyle(PressableStyle())
    }
}

// MARK: - البطاقات والأوراق

public struct CardContainer<Content: View>: View {
    var padding: CGFloat
    var content: Content
    public init(padding: CGFloat = 16, @ViewBuilder content: () -> Content) { self.padding = padding; self.content = content() }
    public var body: some View {
        content
            .padding(padding)
            .background(BZColor.card, in: RoundedRectangle(cornerRadius: BZRadius.card, style: .continuous))
            .shadow(color: BZColor.ink.opacity(0.05), radius: 10, y: 2)
    }
}

public struct SheetGrabber: View {
    public init() {}
    public var body: some View {
        Capsule().fill(Color(hex: 0xDCE1DF)).frame(width: 40, height: 5).frame(maxWidth: .infinity).padding(.top, 10)
    }
}

/// ورقة سفلية خفيفة تُرسم فوق المحتوى (لا تستخدم .sheet لتبقى الخريطة ظاهرة).
public struct BottomPanel<Content: View>: View {
    var content: Content
    public init(@ViewBuilder content: () -> Content) { self.content = content() }
    public var body: some View {
        VStack(spacing: 12) {
            SheetGrabber()
            content
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 34)
        .background(Color.white, in: UnevenRoundedRectangle(topLeadingRadius: BZRadius.sheet, topTrailingRadius: BZRadius.sheet, style: .continuous))
        .shadow(color: BZColor.ink.opacity(0.12), radius: 30, y: -10)
    }
}

// MARK: - الحالات

public struct SkeletonCard: View {
    public init() {}
    @State private var phase = false
    public var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            RoundedRectangle(cornerRadius: 12).fill(BZColor.sand).frame(height: 170)
            RoundedRectangle(cornerRadius: 6).fill(BZColor.sand).frame(width: 160, height: 18)
            RoundedRectangle(cornerRadius: 6).fill(BZColor.sand).frame(width: 110, height: 14)
            RoundedRectangle(cornerRadius: 6).fill(BZColor.sand).frame(width: 220, height: 14)
        }
        .padding(14)
        .background(Color.white, in: RoundedRectangle(cornerRadius: BZRadius.card, style: .continuous))
        .opacity(phase ? 0.55 : 1)
        .onAppear { withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) { phase = true } }
        .accessibilityHidden(true)
    }
}

public struct EmptyStateView: View {
    var title: String
    var subtitle: String?
    var systemImage: String
    public init(title: String, subtitle: String? = nil, systemImage: String = "mappin.slash") {
        self.title = title; self.subtitle = subtitle; self.systemImage = systemImage
    }
    public var body: some View {
        VStack(spacing: 10) {
            Image(systemName: systemImage).font(.system(size: 34)).foregroundStyle(BZColor.mute)
            Text(title).font(BZFont.headline).multilineTextAlignment(.center)
            if let subtitle { Text(subtitle).font(BZFont.bodyRegular).foregroundStyle(BZColor.mute).multilineTextAlignment(.center) }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 60).padding(.horizontal, 24)
    }
}

public struct ErrorStateView: View {
    var title: String
    var message: String?
    var retryTitle: String?
    var retry: (() -> Void)?
    public init(title: String, message: String? = nil, retryTitle: String? = nil, retry: (() -> Void)? = nil) {
        self.title = title; self.message = message; self.retryTitle = retryTitle; self.retry = retry
    }
    public var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle").font(.system(size: 32)).foregroundStyle(BZColor.orangeDark)
            Text(title).font(BZFont.headline).multilineTextAlignment(.center)
            if let message { Text(message).font(BZFont.bodyRegular).foregroundStyle(BZColor.mute).multilineTextAlignment(.center) }
            if let retry, let retryTitle {
                Button(retryTitle, action: retry)
                    .font(BZFont.body)
                    .padding(.horizontal, 22).padding(.vertical, 10)
                    .background(BZColor.ink, in: Capsule())
                    .foregroundStyle(.white)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 50).padding(.horizontal, 24)
    }
}

/// إسناد Google المطلوب عند عرض بيانات Places خارج خريطة Google (قوائم، تفاصيل).
/// يُفضَّل شعار Google Maps الرسمي (أصل `GoogleMapsLogo` في Assets)؛ النص بديل عند ضيق المساحة.
public struct GoogleAttributionView: View {
    var compact: Bool
    public init(compact: Bool = false) { self.compact = compact }
    public var body: some View {
        HStack(spacing: 4) {
            #if canImport(UIKit)
            if let ui = UIImage(named: "GoogleMapsLogo") {
                Image(uiImage: ui).resizable().scaledToFit().frame(height: compact ? 16 : 20)
            } else {
                Text("Google Maps").font(.system(size: compact ? 11 : 13, weight: .semibold)).foregroundStyle(BZColor.mute)
            }
            #else
            Text("Google Maps").font(.system(size: compact ? 11 : 13, weight: .semibold)).foregroundStyle(BZColor.mute)
            #endif
        }
        .padding(.horizontal, 10).padding(.vertical, 5)
        .accessibilityLabel("Google Maps")
    }
}

public struct RatingLabel: View {
    var rating: Double?
    var count: Int?
    var countSuffix: String
    public init(rating: Double?, count: Int?, countSuffix: String) { self.rating = rating; self.count = count; self.countSuffix = countSuffix }
    public var body: some View {
        HStack(spacing: 6) {
            if let rating {
                Text("⭐ \(rating.formatted(.number.precision(.fractionLength(1))))").font(BZFont.caption.weight(.heavy)).foregroundStyle(BZColor.orangeDark)
                if let count { Text("(\(count.formatted(.number.grouping(.automatic))) \(countSuffix))").font(BZFont.caption).foregroundStyle(BZColor.mute) }
            } else {
                Text("—").font(BZFont.caption).foregroundStyle(BZColor.mute)
            }
        }
    }
}
