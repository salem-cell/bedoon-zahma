import DesignSystem
import Domain
import SwiftUI

@MainActor @Observable
final class FavoritesViewModel {
    enum Tab: String, CaseIterable { case all, restaurants, cafes }
    var tab: Tab = .all
    var items: [(fav: FavoritePlace, place: NearbyPlace)] = []
    var isLoading = true
    var error: AppError?
    private var env: AppEnvironment?

    func bind(_ env: AppEnvironment) {
        guard self.env == nil else { return }
        self.env = env
        Task { [self] in await load() }
    }

    /// نخزّن المعرّفات فقط؛ التفاصيل تُجلب الآن (Place Details «card») مع ETA عبر Route Matrix بدفعة واحدة.
    func load() async {
        guard let env else { return }
        isLoading = true
        let favs = await env.favorites.all()
        let places = env.places
        let lang = env.languageCode
        var out: [(FavoritePlace, NearbyPlace)] = []
        await withTaskGroup(of: (FavoritePlace, NearbyPlace?).self) { group in
            for f in favs {
                group.addTask { (f, try? await places.placeDetails(placeID: f.placeID, level: .card, languageCode: lang, sessionToken: nil)) }
            }
            for await (f, p) in group { if let p { out.append((f, p)) } }
        }
        out.sort { $0.0.savedAt > $1.0.savedAt }
        if let here = try? await env.location.currentLocation(), !out.isEmpty {
            let coords = out.map { $0.1.coordinate }
            if let results = try? await env.travelTime.travelTimes(from: here, to: Array(coords.prefix(env.travelTime.maxElementsPerRequest)), trafficAware: true) {
                for r in results where r.routeExists && r.destinationIndex < out.count {
                    out[r.destinationIndex].1.drivingETASeconds = r.durationSeconds
                    out[r.destinationIndex].1.distanceMeters = r.distanceMeters
                }
            }
        }
        items = out.map { (fav: $0.0, place: $0.1) }
        isLoading = false
    }

    var filtered: [(fav: FavoritePlace, place: NearbyPlace)] {
        switch tab {
        case .all: return items
        case .restaurants: return items.filter { $0.fav.kindID == "restaurants" }
        case .cafes: return items.filter { $0.fav.kindID == "cafes" }
        }
    }
}

struct FavoritesView: View {
    @Environment(\.appEnv) private var env
    @Environment(AppRouter.self) private var router
    @State private var vm = FavoritesViewModel()

    var body: some View {
        VStack(spacing: 0) {
            ScreenHeader(title: L("favorites.title")).padding(.top, 8)
            HStack(spacing: 8) {
                ForEach(FavoritesViewModel.Tab.allCases, id: \.self) { t in
                    Chip(L("favorites.tab.\(t.rawValue)"), selected: vm.tab == t) { vm.tab = t }
                }
                Spacer()
            }
            .padding(.horizontal, 20).padding(.top, 16)
            ScrollView {
                LazyVStack(spacing: 10) {
                    if vm.isLoading {
                        ForEach(0..<3, id: \.self) { _ in RoundedRectangle(cornerRadius: 18).fill(BZColor.sand).frame(height: 94) }
                    } else if vm.filtered.isEmpty {
                        EmptyStateView(title: L("favorites.empty"), systemImage: "heart")
                    } else {
                        ForEach(vm.filtered, id: \.fav.placeID) { item in
                            PlaceMiniCard(place: item.place) { router.push(.place(placeID: item.fav.placeID, kindID: item.fav.kindID)) }
                        }
                        GoogleAttributionView(compact: true).frame(maxWidth: .infinity, alignment: .trailing)
                    }
                }
                .padding(.horizontal, 20).padding(.vertical, 16)
            }
        }
        .background(BZColor.paper.ignoresSafeArea())
        .bzHideNavBar()
        .onAppear { if let env { vm.bind(env) } }
    }
}
