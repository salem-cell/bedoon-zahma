import Analytics
import DesignSystem
import Domain
import NearbyDiscovery
import SwiftUI

@MainActor @Observable
final class NearbyViewModel {
    enum ViewMode { case list, map }

    let kind: PlaceKind
    var timeFilter: TravelTimeFilter = .fifteenMinutes
    var category: PlaceCategory?
    var sort: PlaceSort = .best
    var mode: ViewMode = .list
    var filterOpen = false
    var isLoading = false
    var error: AppError?
    var result: NearbyResult?
    var favorites: Set<String> = []
    var selectedPinID: String?
    var origin: Coordinate?
    private var env: AppEnvironment?
    private var task: Task<Void, Never>?

    init(kind: PlaceKind) { self.kind = kind }

    var places: [NearbyPlace] { result?.places ?? [] }
    var availableCategories: [PlaceCategory] { result?.availableCategories ?? [] }
    var selectedPinPlace: NearbyPlace? { places.first { $0.placeID == selectedPinID } }

    func bind(_ env: AppEnvironment) {
        guard self.env == nil else { return }
        self.env = env
        env.analytics.track(Events.nearbyOpened(kind: kind.id))
        Task { [self] in
            favorites = Set(await env.favorites.all().map(\.placeID))
            await load()
        }
    }

    func load(center: Coordinate? = nil) async {
        guard let env else { return }
        task?.cancel()
        isLoading = true
        error = nil
        let t = Task { [weak self] in
            guard let self else { return }
            do {
                let o: Coordinate
                if let center { o = center } else { o = try await env.location.currentLocation() }
                origin = o
                let r = try await env.nearby.discover(query(origin: o))
                guard !Task.isCancelled else { return }
                result = r
                if r.candidates.isEmpty { error = .noPlacesFound }
            } catch let e as AppError where e != .cancelled {
                error = e
            } catch {}
            isLoading = false
        }
        task = t
        await t.value
    }

    /// تغيير الوقت/التصنيف/الترتيب: فلترة محلية بلا طلبات جديدة.
    func refine() {
        guard let env, let r = result, let o = origin else { return }
        Task { [self] in result = await env.nearby.refine(query(origin: o), candidates: r.candidates) }
    }

    func setTime(_ f: TravelTimeFilter) { timeFilter = f; env?.analytics.track(Events.nearbyTimeFilterSelected(f)); refine() }
    func setCategory(_ c: PlaceCategory?) { category = c; refine() }
    func setSort(_ s: PlaceSort) { sort = s; env?.analytics.track(Events.placeSortSelected(s)); refine() }

    func toggleFavorite(_ p: NearbyPlace) {
        guard let env else { return }
        Task { [self] in
            let saved = await env.favorites.toggle(placeID: p.placeID, kindID: kind.id)
            if saved { favorites.insert(p.placeID) } else { favorites.remove(p.placeID) }
            env.analytics.track(Events.placeSaved(kind: kind.id, saved: saved))
        }
    }

    private func query(origin: Coordinate) -> NearbyQuery {
        NearbyQuery(origin: origin, kind: kind, timeFilter: timeFilter, category: category, sort: sort, languageCode: env?.languageCode ?? "ar", regionCode: env?.regionCode ?? "SA")
    }

    var countText: String {
        let unit = kind.id == "cafes" ? L("unit.cafe") : L("unit.restaurant")
        return L("nearby.count", places.count, unit, timeFilter.rawValue)
    }

    var countShort: String {
        let unit = kind.id == "cafes" ? L("unit.cafe") : L("unit.restaurant")
        return "\(places.count) \(unit)"
    }
}

/// مقاهيي / مطاعمي: القائمة أولًا، الخريطة ثانوية.
struct NearbyView: View {
    @Environment(\.appEnv) private var env
    @Environment(AppRouter.self) private var router
    @State private var vm: NearbyViewModel

    init(kindID: String) {
        _vm = State(initialValue: NearbyViewModel(kind: PlaceKindCatalog.kind(id: kindID) ?? PlaceKindCatalog.cafes))
    }

    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                ScreenHeader(title: vm.kind.id == "cafes" ? L("nearby.cafes.title") : L("nearby.restaurants.title")) {
                    SegmentedPill(options: [(NearbyViewModel.ViewMode.list, L("nearby.list")), (.map, L("nearby.map"))], selection: $vm.mode)
                }
                .padding(.top, 8)

                HStack(spacing: 8) {
                    ForEach(TravelTimeFilter.allCases) { f in
                        TimeFilterButton(L("nearby.within", f.rawValue), selected: vm.timeFilter == f) { vm.setTime(f) }
                            .accessibilityIdentifier("nearby.time.\(f.rawValue)")
                    }
                }
                .padding(.horizontal, 20).padding(.top, 16)

                if !vm.availableCategories.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            Chip(L("cat.all"), selected: vm.category == nil, selectedColor: BZColor.orange) { vm.setCategory(nil) }
                            ForEach(vm.availableCategories) { c in
                                Chip(c.title, selected: vm.category == c, selectedColor: BZColor.orange) { vm.setCategory(c) }
                            }
                        }
                        .padding(.horizontal, 20)
                    }
                    .padding(.top, 12)
                }

                HStack {
                    Button { vm.filterOpen = true } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "slider.horizontal.3")
                            Text(vm.sort.title).font(BZFont.caption.weight(.bold))
                        }
                        .padding(.horizontal, 14).padding(.vertical, 8)
                        .background(Color.white, in: Capsule())
                        .overlay(Capsule().strokeBorder(BZColor.line))
                        .foregroundStyle(BZColor.ink)
                    }
                    Spacer()
                    if !vm.isLoading { Text(vm.countText).font(BZFont.caption.weight(.semibold)).foregroundStyle(BZColor.mute) }
                }
                .padding(.horizontal, 20).padding(.vertical, 12)

                content
            }

            if vm.filterOpen { filterSheet }
        }
        .background(BZColor.paper.ignoresSafeArea())
        .bzHideNavBar()
        .onAppear { if let env { vm.bind(env) } }
        .animation(.easeOut(duration: 0.2), value: vm.filterOpen)
    }

    @ViewBuilder private var content: some View {
        switch vm.mode {
        case .list:
            ScrollView {
                LazyVStack(spacing: 14) {
                    if vm.isLoading && vm.result == nil {
                        ForEach(0..<3, id: \.self) { _ in SkeletonCard() }
                    } else if let e = vm.error, vm.places.isEmpty, e != .noPlacesFound {
                        ErrorStateView(title: e.userTitle, message: e.userMessage, retryTitle: L("common.retry")) { Task { await vm.load() } }
                    } else if vm.places.isEmpty {
                        EmptyStateView(title: L("nearby.empty", vm.timeFilter.rawValue), subtitle: L("nearby.empty.sub"))
                    } else {
                        ForEach(vm.places) { p in
                            PlaceCardView(place: p, isFavorite: vm.favorites.contains(p.placeID), onFavorite: { vm.toggleFavorite(p) }) {
                                env?.analytics.track(Events.placeOpened(kind: vm.kind.id))
                                router.push(.place(placeID: p.placeID, kindID: vm.kind.id))
                            }
                            .accessibilityIdentifier("place.card.\(p.placeID)")
                        }
                        GoogleAttributionView().frame(maxWidth: .infinity, alignment: .trailing)
                    }
                }
                .padding(.horizontal, 20).padding(.bottom, 40)
            }
            .refreshable { await env?.nearby.invalidate(); await vm.load() }
        case .map:
            ZStack(alignment: .bottom) {
                if let env, let o = vm.origin {
                    env.maps.nearbyMap(center: o, pins: pins, onPinTap: { vm.selectedPinID = $0 }, onRegionMoved: { _ in })
                } else { BZColor.mapBase }
                VStack {
                    Button(L("nearby.searcharea")) { Task { await vm.load() } }
                        .font(BZFont.caption.weight(.bold))
                        .padding(.horizontal, 16).padding(.vertical, 9)
                        .background(Color.white, in: Capsule())
                        .foregroundStyle(BZColor.ink)
                        .shadow(color: BZColor.ink.opacity(0.12), radius: 8, y: 3)
                        .padding(.top, 14)
                    Spacer()
                    if let p = vm.selectedPinPlace {
                        PlaceMiniCard(place: p) { router.push(.place(placeID: p.placeID, kindID: vm.kind.id)) }
                            .padding(16)
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 24))
            .padding(.horizontal, 12)
            .animation(.spring(duration: 0.3), value: vm.selectedPinID)
        }
    }

    private var pins: [MapPin] {
        vm.places.map { MapPin(id: $0.placeID, coordinate: $0.coordinate, title: $0.name, subtitle: $0.rating.map { "⭐ \($0.formatted(.number.precision(.fractionLength(1))))" }, selected: vm.selectedPinID == $0.placeID) }
    }

    private var filterSheet: some View {
        ZStack(alignment: .bottom) {
            BZColor.ink.opacity(0.45).ignoresSafeArea().onTapGesture { vm.filterOpen = false }
            BottomPanel {
                Text(L("filter.title")).font(BZFont.title).frame(maxWidth: .infinity, alignment: .leading)
                VStack(alignment: .leading, spacing: 10) {
                    Text(L("filter.time")).font(BZFont.caption.weight(.semibold)).foregroundStyle(BZColor.mute)
                    HStack(spacing: 8) {
                        ForEach(TravelTimeFilter.allCases) { f in TimeFilterButton(L("nearby.within", f.rawValue), selected: vm.timeFilter == f) { vm.setTime(f) } }
                    }
                }
                VStack(alignment: .leading, spacing: 10) {
                    Text(L("filter.sort")).font(BZFont.caption.weight(.semibold)).foregroundStyle(BZColor.mute)
                    ForEach(PlaceSort.allCases) { s in
                        Button { vm.setSort(s) } label: {
                            HStack {
                                Text(s.title).font(BZFont.body.weight(.bold))
                                Spacer()
                                Text(s.subtitle).font(BZFont.small).opacity(0.8)
                            }
                            .padding(.horizontal, 16).padding(.vertical, 13)
                            .background(vm.sort == s ? BZColor.sky : BZColor.chipBg, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                            .foregroundStyle(vm.sort == s ? .white : BZColor.ink)
                        }
                        .buttonStyle(PressableStyle())
                    }
                }
                PrimaryButton(L("filter.show", vm.countShort)) { vm.filterOpen = false }
            }
            .transition(.move(edge: .bottom))
        }
    }
}
