import DesignSystem
import Domain
import SwiftUI

/// صورة مكان بثلاث طبقات حقيقية، بالترتيب:
/// 1) صورة المزوّد (Google Place Photos عبر الخادم، بلا تخزين على القرص) مع إسناد المصوّر.
/// 2) عند غيابها أو فشلها: مشهد شارع حقيقي من Apple Look Around لموقع المكان (إن توفرت التغطية).
/// 3) وإلا: بديل مخطط بأيقونة الفئة — لا نعرض صورة لا تخص المكان أبدًا.
struct PlacePhotoView: View {
    var photo: PhotoReference?
    var maxWidthPx: Int
    var height: CGFloat
    var showAttribution: Bool = true
    /// يفعّل طبقتَي البديل (Look Around وأيقونة الفئة) بمعلومات المكان.
    var fallback: PlacePhotoFallback? = nil
    @Environment(\.appEnv) private var env
    @State private var providerFailed = false

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            if let photo, !providerFailed, let url = env?.places.photoURL(for: photo, maxWidthPx: maxWidthPx) {
                RemoteImage(url: url, onFailure: { providerFailed = true }) { secondary }
                if showAttribution, let a = photo.authorAttributions.first {
                    Text(a.displayName)
                        .font(.system(size: 10, weight: .medium))
                        .padding(.horizontal, 8).padding(.vertical, 4)
                        .background(.black.opacity(0.45), in: Capsule())
                        .foregroundStyle(.white)
                        .padding(8)
                        .accessibilityLabel(L("photo.by", a.displayName))
                }
            } else {
                secondary
            }
        }
        .frame(height: height)
        .clipped()
    }

    @ViewBuilder private var secondary: some View {
        if let fallback {
            LookAroundCoverView(placeID: fallback.placeID, coordinate: fallback.coordinate, size: CGSize(width: CGFloat(maxWidthPx) / 2, height: height), showBadge: showAttribution) {
                placeholder(icon: fallback.icon)
            }
        } else {
            placeholder(icon: "photo")
        }
    }

    private func placeholder(icon: String) -> some View {
        ZStack {
            LinearGradient(colors: [Color(hex: 0xE4E7E5), Color(hex: 0xECEFED)], startPoint: .topLeading, endPoint: .bottomTrailing)
            Image(systemName: icon).font(.system(size: 26)).foregroundStyle(BZColor.mute.opacity(0.6))
        }
    }
}

/// بيانات البديل الحقيقي لصورة المكان.
struct PlacePhotoFallback {
    var placeID: String
    var coordinate: Coordinate
    var icon: String

    init(place: NearbyPlace) {
        placeID = place.placeID
        coordinate = place.coordinate
        icon = PlacePhotoFallback.icon(for: place)
    }

    /// أيقونة الفئة من primaryType/types فقط.
    static func icon(for place: NearbyPlace) -> String {
        let all = ([place.primaryType].compactMap { $0 } + place.types)
        if all.contains(where: { $0.contains("cafe") || $0.contains("coffee") || $0.contains("tea_house") }) { return "cup.and.saucer.fill" }
        if all.contains(where: { $0.contains("bakery") || $0.contains("dessert") || $0.contains("ice_cream") }) { return "birthday.cake.fill" }
        if all.contains(where: { $0.contains("restaurant") || $0.contains("food") || $0.contains("steak") }) { return "fork.knife" }
        return "mappin.and.ellipse"
    }
}

/// بطاقة مكان في القائمة: صورة كبيرة، اسم، تقييم وعدد، تصنيف، ETA ومسافة، حي، حالة الفتح، مستوى السعر.
struct PlaceCardView: View {
    var place: NearbyPlace
    var isFavorite: Bool
    var onFavorite: () -> Void
    var onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 0) {
                ZStack(alignment: .topLeading) {
                    PlacePhotoView(photo: place.coverPhoto, maxWidthPx: 800, height: 170, fallback: PlacePhotoFallback(place: place))
                    HStack {
                        Button(action: onFavorite) {
                            Image(systemName: isFavorite ? "heart.fill" : "heart")
                                .foregroundStyle(isFavorite ? BZColor.danger : BZColor.ink)
                                .frame(width: 36, height: 36)
                                .background(Color.white, in: Circle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(isFavorite ? L("place.unsave") : L("place.save"))
                        Spacer()
                    }
                    .padding(12)
                    if let eta = place.drivingETAMinutes {
                        HStack(spacing: 6) {
                            Text("🚗")
                            Text(L("unit.minutes.value", eta)).font(BZFont.caption.weight(.bold))
                            if let km = place.distanceKm { Text("· " + L("unit.km.value", km)).font(BZFont.caption).foregroundStyle(BZColor.skyTint) }
                        }
                        .padding(.horizontal, 12).padding(.vertical, 5)
                        .background(BZColor.sky, in: Capsule())
                        .foregroundStyle(.white)
                        .padding(12)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                    }
                }
                .frame(height: 170)

                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text(place.name).font(BZFont.headline).lineLimit(1)
                        Spacer()
                        if let p = place.priceLevel?.symbols { Text(p).font(BZFont.caption).foregroundStyle(BZColor.mute) }
                    }
                    RatingLabel(rating: place.rating, count: place.ratingCount, countSuffix: L("unit.reviews"))
                    if !place.categoryLabels.isEmpty {
                        Text(place.categoryLabels.joined(separator: " • ")).font(BZFont.caption).foregroundStyle(BZColor.mute).lineLimit(1)
                    }
                    HStack {
                        if let hood = place.neighborhood ?? place.shortAddress { Text("📍 \(hood)").font(BZFont.caption).foregroundStyle(BZColor.mute).lineLimit(1) }
                        Spacer()
                        OpenStatusLabel(place: place)
                    }
                }
                .padding(.horizontal, 16).padding(.top, 14).padding(.bottom, 16)
            }
            .background(Color.white, in: RoundedRectangle(cornerRadius: BZRadius.card, style: .continuous))
            .clipShape(RoundedRectangle(cornerRadius: BZRadius.card, style: .continuous))
            .shadow(color: BZColor.ink.opacity(0.05), radius: 10, y: 2)
            .foregroundStyle(BZColor.ink)
        }
        .buttonStyle(PressableStyle())
    }
}

struct OpenStatusLabel: View {
    var place: NearbyPlace
    var body: some View {
        if place.businessStatus == .closedTemporarily {
            Text(L("place.closedtemp")).font(BZFont.caption.weight(.bold)).foregroundStyle(BZColor.orangeDark)
        } else if let open = place.openNow {
            Text(open ? L("place.open") : L("place.closed")).font(BZFont.caption.weight(.bold)).foregroundStyle(open ? BZColor.greenDark : BZColor.orangeDark)
        }
    }
}

/// بطاقة مصغّرة (الخريطة/المفضلة).
struct PlaceMiniCard: View {
    var place: NearbyPlace
    var onTap: () -> Void
    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                PlacePhotoView(photo: place.coverPhoto, maxWidthPx: 200, height: 70, showAttribution: false, fallback: PlacePhotoFallback(place: place))
                    .frame(width: 70).clipShape(RoundedRectangle(cornerRadius: 12))
                VStack(alignment: .leading, spacing: 4) {
                    Text(place.name).font(BZFont.body.weight(.heavy)).lineLimit(1)
                    RatingLabel(rating: place.rating, count: place.ratingCount, countSuffix: "")
                    HStack(spacing: 4) {
                        if let eta = place.drivingETAMinutes { Text("🚗 " + L("unit.minutes.value", eta)) }
                        if let hood = place.neighborhood { Text("· \(hood)") }
                    }
                    .font(BZFont.caption).foregroundStyle(BZColor.mute).lineLimit(1)
                }
                Spacer()
                Image(systemName: "chevron.backward").foregroundStyle(BZColor.mute)
            }
            .padding(12)
            .background(Color.white, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .foregroundStyle(BZColor.ink)
        }
        .buttonStyle(PressableStyle())
    }
}

extension NearbyPlace {
    /// تسميات التصنيف المعروضة — من primaryType/types فقط (لا نخترع).
    var categoryLabels: [String] {
        let known: [String: String] = [
            "coffee_shop": L("cat.specialty_coffee"), "coffee_roastery": L("cat.specialty_coffee"), "cafe": L("cat.cafe"),
            "bakery": L("cat.bakery"), "dessert_shop": L("cat.desserts"), "ice_cream_shop": L("cat.desserts"), "tea_house": L("cat.tea"),
            "breakfast_restaurant": L("cat.breakfast"), "brunch_restaurant": L("cat.breakfast"),
            "hamburger_restaurant": L("cat.burger"), "pizza_restaurant": L("cat.pizza"), "italian_restaurant": L("cat.italian"),
            "barbecue_restaurant": L("cat.grills"), "steak_house": L("cat.grills"), "shawarma_restaurant": L("cat.shawarma"),
            "seafood_restaurant": L("cat.seafood"), "indian_restaurant": L("cat.indian"), "asian_restaurant": L("cat.asian"),
            "chinese_restaurant": L("cat.asian"), "japanese_restaurant": L("cat.asian"), "sushi_restaurant": L("cat.asian"),
            "thai_restaurant": L("cat.asian"), "middle_eastern_restaurant": L("cat.middle_eastern"), "lebanese_restaurant": L("cat.middle_eastern"),
            "fast_food_restaurant": L("cat.fastfood"), "restaurant": L("cat.restaurant"),
        ]
        var out: [String] = []
        for t in ([primaryType].compactMap { $0 } + types) {
            if let l = known[t], !out.contains(l) { out.append(l) }
            if out.count == 2 { break }
        }
        return out
    }
}

extension PlaceCategory {
    var title: String { L("cat.\(id)") }
}

extension PlaceSort {
    var title: String {
        switch self {
        case .best: return L("sort.best"); case .rating: return L("sort.rating"); case .ratingCount: return L("sort.count")
        case .eta: return L("sort.eta"); case .distance: return L("sort.distance")
        }
    }
    var subtitle: String {
        switch self {
        case .best: return L("sort.best.sub"); case .rating: return L("sort.rating.sub"); case .ratingCount: return L("sort.count.sub")
        case .eta: return L("sort.eta.sub"); case .distance: return L("sort.distance.sub")
        }
    }
}
