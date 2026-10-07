import Analytics
import DesignSystem
import Domain
import SwiftUI

@MainActor @Observable
final class SearchViewModel {
    var query = ""
    var suggestions: [SearchSuggestion] = []
    var recents: [RecentSearch] = []
    var home: SavedAddress?
    var work: SavedAddress?
    var isLoading = false
    var error: AppError?
    /// رمز جلسة Autocomplete — يتجدد بعد كل اختيار (للفوترة بالجلسة).
    private(set) var sessionToken = UUID().uuidString
    private var env: AppEnvironment?
    private var searchTask: Task<Void, Never>?
    private var origin: Coordinate?

    func bind(_ env: AppEnvironment) {
        guard self.env == nil else { return }
        self.env = env
        Task { [self] in
            recents = await env.recents.all()
            home = await env.savedAddresses.get(.home)
            work = await env.savedAddresses.get(.work)
            origin = try? await env.location.currentLocation()
        }
    }

    func queryChanged() {
        searchTask?.cancel()
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard q.count >= 2, let env else { suggestions = []; isLoading = false; return }
        isLoading = true
        searchTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(300)) // debounce
            guard !Task.isCancelled, let self else { return }
            do {
                let cfg = await env.remoteConfig.config
                let req = AutocompleteRequest(input: q, origin: origin, biasCenter: origin, regionCodes: cfg.searchRegionCodes, languageCode: env.languageCode, sessionToken: sessionToken)
                let res = try await env.places.autocomplete(req)
                guard !Task.isCancelled else { return }
                suggestions = res
                error = nil
                env.analytics.track(Events.destinationSearched(hasResults: !res.isEmpty))
            } catch let e as AppError where e != .cancelled {
                error = e
            } catch {}
            isLoading = false
        }
    }

    /// اختيار اقتراح: نحفظه في السجل ونحوّله إلى وجهة. الإحداثية تُجلب (Essentials) لرسم الوجهة على الخريطة.
    func select(_ s: SearchSuggestion) async -> Destination? {
        guard let env else { return nil }
        await env.recents.add(RecentSearch(placeID: s.placeID, displayName: s.mainText, secondaryText: s.secondaryText))
        let token = sessionToken
        sessionToken = UUID().uuidString
        let coord = try? await env.places.placeDetails(placeID: s.placeID, level: .basic, languageCode: env.languageCode, sessionToken: token).coordinate
        return .place(placeID: s.placeID, name: s.mainText, coordinate: coord)
    }

    func select(recent r: RecentSearch) async -> Destination? {
        guard let env else { return nil }
        await env.recents.add(RecentSearch(placeID: r.placeID, displayName: r.displayName, secondaryText: r.secondaryText))
        let coord = try? await env.places.placeDetails(placeID: r.placeID, level: .basic, languageCode: env.languageCode, sessionToken: nil).coordinate
        return .place(placeID: r.placeID, name: r.displayName, coordinate: coord)
    }

    func select(saved a: SavedAddress) async -> Destination? {
        guard let env else { return nil }
        let coord = try? await env.places.placeDetails(placeID: a.placeID, level: .basic, languageCode: env.languageCode, sessionToken: nil).coordinate
        return .place(placeID: a.placeID, name: a.label, coordinate: coord)
    }

    func clearHistory() async {
        await env?.recents.clear()
        recents = []
    }
}

struct SearchView: View {
    @Environment(\.appEnv) private var env
    @Environment(AppRouter.self) private var router
    @Environment(TripState.self) private var trip
    @State private var vm = SearchViewModel()
    @FocusState private var focused: Bool

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                RoundIconButton("arrow.forward") { router.pop() }
                HStack(spacing: 10) {
                    Image(systemName: "magnifyingglass").foregroundStyle(BZColor.mute)
                    TextField(L("search.placeholder"), text: $vm.query)
                        .accessibilityIdentifier("search.field")
                        .font(BZFont.body)
                        .focused($focused)
                        .submitLabel(.search)
                        .autocorrectionDisabled()
                        .onChange(of: vm.query) { _, _ in vm.queryChanged() }
                    if !vm.query.isEmpty {
                        Button { vm.query = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(BZColor.mute) }
                    }
                }
                .padding(.horizontal, 16).padding(.vertical, 12)
                .background(Color.white, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(BZColor.green, lineWidth: 2))
            }
            .padding(.horizontal, 20).padding(.top, 8)

            HStack(spacing: 10) {
                shortcut(L("search.home"), vm.home?.label ?? L("search.notset")) { if let h = vm.home { go { await vm.select(saved: h) } } }
                shortcut(L("search.work"), vm.work?.label ?? L("search.notset")) { if let w = vm.work { go { await vm.select(saved: w) } } }
                shortcut(L("search.pick"), L("search.frommap")) { router.push(.mapPicker) }
            }
            .padding(.horizontal, 20).padding(.top, 20)

            List {
                if vm.query.count >= 2 {
                    Section {
                        if vm.isLoading && vm.suggestions.isEmpty {
                            ForEach(0..<3, id: \.self) { _ in row(icon: "circle.dotted", name: "………", sub: nil, dist: nil).redacted(reason: .placeholder) }
                        } else if vm.suggestions.isEmpty, let e = vm.error {
                            ErrorStateView(title: e.userTitle, message: e.userMessage, retryTitle: L("common.retry")) { vm.queryChanged() }
                        } else if vm.suggestions.isEmpty {
                            EmptyStateView(title: L("search.noresults"), systemImage: "magnifyingglass")
                        }
                        ForEach(vm.suggestions) { s in
                            Button { go { await vm.select(s) } } label: {
                                row(icon: "mappin.circle", name: s.mainText, sub: s.secondaryText, dist: s.distanceMeters.map(formatKm))
                            }
                            .accessibilityIdentifier("search.result.\(s.placeID)")
                        }
                    } header: { header(L("search.results"), clear: false) }
                } else {
                    Section {
                        if vm.recents.isEmpty { EmptyStateView(title: L("search.norecents"), systemImage: "clock") }
                        ForEach(vm.recents) { r in
                            Button { go { await vm.select(recent: r) } } label: {
                                row(icon: "clock.arrow.circlepath", name: r.displayName, sub: r.secondaryText, dist: nil)
                            }
                        }
                    } header: { header(L("search.recent"), clear: !vm.recents.isEmpty) }
                }
                Section { GoogleAttributionView(compact: true).frame(maxWidth: .infinity, alignment: .trailing).listRowBackground(Color.clear) }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .padding(.top, 8)
        }
        .background(BZColor.paper.ignoresSafeArea())
        .bzHideNavBar()
        .onAppear { if let env { vm.bind(env) }; focused = true }
    }

    private func go(_ pick: @escaping () async -> Destination?) {
        Task {
            guard let dest = await pick(), let env else { return }
            trip.destination = dest
            trip.origin = try? await env.location.currentLocation()
            trip.fromPlaceKindID = nil
            trip.options = nil
            router.push(.routeOptions)
        }
    }

    private func shortcut(_ title: String, _ value: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(BZFont.small).foregroundStyle(BZColor.mute)
                Text(value).font(BZFont.caption.weight(.bold)).lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 14).padding(.vertical, 12)
            .background(Color.white, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(PressableStyle())
    }

    private func header(_ title: String, clear: Bool) -> some View {
        HStack {
            Text(title).font(BZFont.caption.weight(.semibold)).foregroundStyle(BZColor.mute)
            Spacer()
            if clear { Button(L("search.clear")) { Task { await vm.clearHistory() } }.font(BZFont.small).foregroundStyle(BZColor.mute) }
        }
        .textCase(nil)
    }

    private func row(icon: String, name: String, sub: String?, dist: String?) -> some View {
        HStack(spacing: 14) {
            Image(systemName: icon).foregroundStyle(BZColor.mute).frame(width: 40, height: 40).background(Color.white, in: RoundedRectangle(cornerRadius: 12))
            VStack(alignment: .leading, spacing: 2) {
                Text(name).font(BZFont.body.weight(.bold)).lineLimit(1)
                if let sub { Text(sub).font(BZFont.small).foregroundStyle(BZColor.mute).lineLimit(1) }
            }
            Spacer()
            if let dist { Text(dist).font(BZFont.mono).foregroundStyle(BZColor.mute) }
        }
        .padding(.vertical, 4)
        .foregroundStyle(BZColor.ink)
    }
}

func formatKm(_ meters: Int) -> String {
    let km = Double(meters) / 1000
    return km < 10 ? String(format: "%.1f km", km) : String(format: "%.0f km", km)
}

/// اختيار نقطة من الخريطة: الدبوس ثابت في المنتصف والخريطة تتحرك.
struct MapPickerView: View {
    @Environment(\.appEnv) private var env
    @Environment(AppRouter.self) private var router
    @Environment(TripState.self) private var trip
    @State private var center: Coordinate?

    var body: some View {
        ZStack {
            if let env, let start = center ?? trip.origin {
                env.maps.pickerMap(initial: start) { center = $0 }
            } else { BZColor.mapBase.ignoresSafeArea() }
            Image(systemName: "mappin").font(.system(size: 40, weight: .bold)).foregroundStyle(BZColor.green).offset(y: -20).allowsHitTesting(false)
            VStack {
                ScreenHeader(title: L("search.frommap"))
                Spacer()
                PrimaryButton(L("picker.confirm")) {
                    guard let c = center ?? trip.origin else { return }
                    trip.destination = .coordinate(c, label: L("picker.pinned"))
                    trip.fromPlaceKindID = nil
                    trip.options = nil
                    router.pop()
                    router.pop()
                    router.push(.routeOptions)
                }
                .padding(20)
            }
        }
        .bzHideNavBar()
        .task { if center == nil { center = try? await env?.location.currentLocation() } }
    }
}
