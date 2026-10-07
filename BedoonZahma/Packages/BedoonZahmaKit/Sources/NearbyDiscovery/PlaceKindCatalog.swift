import Domain
import Foundation

/// فهرس الأقسام وتصنيفاتها. كل تصنيف مبني على أنواع Google الرسمية (Table A) أو حقول Atmosphere،
/// ولا يُعرض تصنيف لا يمكن اشتقاقه (مثل «سعودي» — لا يوجد نوع Google موثوق له).
public enum PlaceKindCatalog {
    public static let cafes = PlaceKind(
        id: "cafes",
        includedTypes: [
            "cafe", "coffee_shop", "coffee_roastery", "coffee_stand", "tea_house",
            "bakery", "pastry_shop", "cake_shop", "dessert_shop", "dessert_restaurant", "ice_cream_shop",
            "juice_shop", "breakfast_restaurant", "brunch_restaurant",
        ],
        categories: [
            PlaceCategory(id: "specialty_coffee", matchingTypes: ["coffee_roastery", "coffee_shop", "coffee_stand"]),
            PlaceCategory(id: "breakfast", matchingTypes: ["breakfast_restaurant", "brunch_restaurant"], matchingAttributes: [.servesBreakfast, .servesBrunch]),
            PlaceCategory(id: "desserts", matchingTypes: ["dessert_shop", "dessert_restaurant", "ice_cream_shop", "cake_shop"], matchingAttributes: [.servesDessert]),
            PlaceCategory(id: "bakery", matchingTypes: ["bakery", "pastry_shop"]),
            PlaceCategory(id: "seating", matchingAttributes: [.outdoorSeating, .dineIn]),
        ]
    )

    public static let restaurants = PlaceKind(
        id: "restaurants",
        includedTypes: [
            "restaurant", "hamburger_restaurant", "fast_food_restaurant", "pizza_restaurant", "italian_restaurant",
            "barbecue_restaurant", "steak_house", "shawarma_restaurant", "middle_eastern_restaurant", "lebanese_restaurant",
            "turkish_restaurant", "asian_restaurant", "chinese_restaurant", "japanese_restaurant", "sushi_restaurant",
            "thai_restaurant", "korean_restaurant", "ramen_restaurant", "indian_restaurant", "north_indian_restaurant",
            "south_indian_restaurant", "pakistani_restaurant", "seafood_restaurant", "breakfast_restaurant",
            "brunch_restaurant", "dessert_restaurant",
        ],
        categories: [
            PlaceCategory(id: "burger", matchingTypes: ["hamburger_restaurant"]),
            PlaceCategory(id: "grills", matchingTypes: ["barbecue_restaurant", "steak_house", "korean_barbecue_restaurant", "yakiniku_restaurant"]),
            PlaceCategory(id: "shawarma", matchingTypes: ["shawarma_restaurant", "gyro_restaurant", "kebab_shop"]),
            PlaceCategory(id: "pizza", matchingTypes: ["pizza_restaurant", "pizza_delivery"]),
            PlaceCategory(id: "italian", matchingTypes: ["italian_restaurant"]),
            PlaceCategory(id: "asian", matchingTypes: ["asian_restaurant", "asian_fusion_restaurant", "chinese_restaurant", "japanese_restaurant", "sushi_restaurant", "thai_restaurant", "korean_restaurant", "ramen_restaurant", "vietnamese_restaurant", "indonesian_restaurant", "malaysian_restaurant", "filipino_restaurant"]),
            PlaceCategory(id: "indian", matchingTypes: ["indian_restaurant", "north_indian_restaurant", "south_indian_restaurant", "pakistani_restaurant", "bangladeshi_restaurant"]),
            PlaceCategory(id: "seafood", matchingTypes: ["seafood_restaurant", "fish_and_chips_restaurant", "oyster_bar_restaurant"]),
            PlaceCategory(id: "breakfast", matchingTypes: ["breakfast_restaurant", "brunch_restaurant"], matchingAttributes: [.servesBreakfast, .servesBrunch]),
            PlaceCategory(id: "desserts", matchingTypes: ["dessert_restaurant", "dessert_shop"], matchingAttributes: [.servesDessert]),
        ]
    )

    public static let all: [PlaceKind] = [cafes, restaurants]

    public static func kind(id: String) -> PlaceKind? { all.first { $0.id == id } }

    /// التصنيفات التي لها نتيجة واحدة على الأقل ضمن القائمة الحالية.
    public static func availableCategories(for kind: PlaceKind, in places: [NearbyPlace]) -> [PlaceCategory] {
        kind.categories.filter { c in places.contains { $0.matches(c) } }
    }
}
