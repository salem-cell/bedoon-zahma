import Analytics
import DesignSystem
import Domain
import SwiftUI

@MainActor @Observable
final class PlaceDetailsViewModel {
    let placeID: String
    let kindID: String
    var place: NearbyPlace?
    var isFavorite = false
    var isLoading = true
    var error: AppError?
    var galleryIndex = 0
    private var env: AppEnvironment?

    init(placeID: String, kindID: String) { self.placeID = placeID; self.kindID = kindID }

    func bind(_ env: AppEnvironment) {
        guard self.env == nil else { return }
        self.env = env
        Task { [self] in await load() }
    }

    func load() async {
        guard let env else { return }
        isLoading = true
        error = nil
        do {
            var p = try await env.places.placeDetails(placeID: placeID, level: .full, languageCode: env.languageCode, sessionToken: nil)
            isFavorite = await env.favorites.isFavorite(placeID)
            // ETA الفعلي: Route Matrix لعنصر واحد (التفاصيل لا ترجع routingSummaries بلا أصل).
            if p.drivingETASeconds == nil, let here = try? await env.location.currentLocation() {
                if let r = try? await env.travelTime.travelTimes(from: here, to: [p.coordinate], trafficAware: true).first, r.routeExists {
                    p.drivingETASeconds = r.durationSeconds
                    p.distanceMeters = r.distanceMeters ?? p.distanceMeters
                }
            }
            place = p
            if p.businessStatus == .closedTemporarily { error = .placeTemporarilyClosed }
        } catch let e as AppError where e != .cancelled {
            error = e
        } catch {}
        isLoading = false
    }

    func toggleFavorite() {
        guard let env else { return }
        Task { [self] in
            isFavorite = await env.favorites.toggle(placeID: placeID, kindID: kindID)
            env.analytics.track(Events.placeSaved(kind: kindID, saved: isFavorite))
        }
    }
}

struct PlaceDetailsView: View {
    @Environment(\.appEnv) private var env
    @Environment(AppRouter.self) private var router
    @Environment(TripState.self) private var trip
    @Environment(\.openURL) private var openURL
    @State private var vm: PlaceDetailsViewModel

    init(placeID: String, kindID: String) { _vm = State(initialValue: PlaceDetailsViewModel(placeID: placeID, kindID: kindID)) }

    var body: some View {
        ZStack(alignment: .bottom) {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    gallery
                    if let p = vm.place {
                        VStack(alignment: .leading, spacing: 18) {
                            VStack(alignment: .leading, spacing: 6) {
                                HStack {
                                    Text(p.name).font(BZFont.largeTitle).lineLimit(2)
                                    Spacer()
                                    if let price = p.priceLevel?.symbols { Text(price).font(BZFont.caption).foregroundStyle(BZColor.mute) }
                                }
                                HStack(spacing: 6) {
                                    RatingLabel(rating: p.rating, count: p.ratingCount, countSuffix: L("unit.reviews"))
                                    if !p.categoryLabels.isEmpty { Text("· " + p.categoryLabels.joined(separator: " • ")).font(BZFont.caption).foregroundStyle(BZColor.mute) }
                                }
                                HStack(spacing: 10) {
                                    OpenStatusLabel(place: p)
                                    if let today = todayHours(p) { Text("· \(today)").font(BZFont.caption).foregroundStyle(BZColor.mute) }
                                }
                            }
                            if let summary = p.editorialSummary { Text(summary).font(BZFont.bodyRegular).foregroundStyle(BZColor.mute) }

                            HStack(spacing: 10) {
                                actionTile("phone.fill", L("place.call"), enabled: p.phone != nil) { if let t = p.phone, let u = URL(string: "tel:\(t.filter { !$0.isWhitespace })") { openURL(u) } }
                                actionTile("globe", L("place.website"), enabled: p.website != nil) { if let u = p.website { openURL(u) } }
                                actionTile("square.and.arrow.up", L("place.share"), enabled: p.googleMapsURI != nil) { share(p) }
                            }

                            infoCard(p)

                            HStack {
                                // رابط رسمي مجاني: معرّف Google إن وُجد، وإلا بحث باسم المكان وإحداثيته.
                                Button { openURL(p.googleMapsURI ?? GoogleMapsURLs.place(name: p.name, coordinate: p.coordinate)) } label: {
                                    Label(L("place.opengoogle"), systemImage: "arrow.up.forward.square").font(BZFont.caption.weight(.bold)).foregroundStyle(BZColor.ink)
                                }
                                Spacer()
                                if p.googleMapsURI != nil { GoogleAttributionView(compact: true) }
                            }
                        }
                        .padding(20)
                    } else if vm.isLoading {
                        VStack(alignment: .leading, spacing: 12) {
                            RoundedRectangle(cornerRadius: 8).fill(BZColor.sand).frame(width: 220, height: 28)
                            RoundedRectangle(cornerRadius: 8).fill(BZColor.sand).frame(width: 160, height: 16)
                            RoundedRectangle(cornerRadius: 16).fill(BZColor.sand).frame(height: 160)
                        }
                        .padding(20)
                    } else if let e = vm.error {
                        ErrorStateView(title: e.userTitle, message: e.userMessage, retryTitle: L("common.retry")) { Task { await vm.load() } }
                    }
                }
                .padding(.bottom, 130)
            }
            .ignoresSafeArea(edges: .top)

            if let p = vm.place {
                HStack(spacing: 14) {
                    VStack(alignment: .leading, spacing: 2) {
                        if let eta = p.drivingETAMinutes {
                            Text("🚗 " + L("unit.minutes.value", eta)).font(BZFont.font(20, weight: .heavy))
                            Text([p.distanceKm.map { L("unit.km.value", $0) }, L("place.currenttraffic")].compactMap { $0 }.joined(separator: " · ")).font(BZFont.small).foregroundStyle(BZColor.mute)
                        } else {
                            Text(L("place.eta.unknown")).font(BZFont.caption).foregroundStyle(BZColor.mute)
                        }
                    }
                    PrimaryButton(L("place.gonow")) { goNow(p) }
                        .accessibilityIdentifier("place.gonow")
                }
                .padding(.horizontal, 20).padding(.top, 16).padding(.bottom, 24)
                .background(Color.white, in: UnevenRoundedRectangle(topLeadingRadius: 24, topTrailingRadius: 24, style: .continuous))
                .shadow(color: BZColor.ink.opacity(0.1), radius: 30, y: -10)
                .ignoresSafeArea(edges: .bottom)
            }
        }
        .background(BZColor.paper.ignoresSafeArea())
        .bzHideNavBar()
        .onAppear { if let env { vm.bind(env) } }
    }

    private var gallery: some View {
        ZStack(alignment: .top) {
            let photos = vm.place?.photos ?? []
            if photos.isEmpty {
                PlacePhotoView(photo: nil, maxWidthPx: 1200, height: 300)
            } else {
                TabView(selection: $vm.galleryIndex) {
                    ForEach(Array(photos.prefix(8).enumerated()), id: \.offset) { i, ph in
                        PlacePhotoView(photo: ph, maxWidthPx: 1200, height: 300).tag(i)
                    }
                }
                .bzPagedTabs()
                .frame(height: 300)
            }
            HStack {
                RoundIconButton("arrow.forward") { router.pop() }
                Spacer()
                RoundIconButton(vm.isFavorite ? "heart.fill" : "heart", tint: vm.isFavorite ? BZColor.danger : BZColor.ink) { vm.toggleFavorite() }
                    .accessibilityLabel(vm.isFavorite ? L("place.unsave") : L("place.save"))
            }
            .padding(.horizontal, 16).padding(.top, 60)
        }
    }

    private func infoCard(_ p: NearbyPlace) -> some View {
        VStack(spacing: 0) {
            infoRow(L("place.address"), p.address ?? p.shortAddress ?? "—")
            if let hours = p.weekdayHours, !hours.isEmpty { infoRowMultiline(L("place.hours"), hours) }
            let services = serviceLabels(p)
            if !services.isEmpty { infoRow(L("place.services"), services.joined(separator: " · ")) }
            if !p.accessibility.isEmpty { infoRow(L("place.accessibility"), p.accessibility.map { L("access.\($0)") }.joined(separator: " · ")) }
            infoRow(L("place.menu"), p.menuURL != nil ? L("place.menu.open") : L("place.menu.unavailable"), muted: p.menuURL == nil, last: true) {
                if let m = p.menuURL { openURL(m) }
            }
        }
        .padding(.horizontal, 16)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private func infoRow(_ title: String, _ value: String, muted: Bool = false, last: Bool = false, action: (() -> Void)? = nil) -> some View {
        HStack(alignment: .top) {
            Text(title).font(BZFont.caption).foregroundStyle(BZColor.mute)
            Spacer()
            Text(value).font(BZFont.caption.weight(.semibold)).foregroundStyle(muted ? BZColor.mute : BZColor.ink).multilineTextAlignment(.trailing)
        }
        .padding(.vertical, 13)
        .overlay(alignment: .bottom) { if !last { Rectangle().fill(BZColor.sand).frame(height: 1) } }
        .contentShape(Rectangle())
        .onTapGesture { action?() }
    }

    private func infoRowMultiline(_ title: String, _ lines: [String]) -> some View {
        HStack(alignment: .top) {
            Text(title).font(BZFont.caption).foregroundStyle(BZColor.mute)
            Spacer()
            VStack(alignment: .trailing, spacing: 3) { ForEach(lines, id: \.self) { Text($0).font(BZFont.small.weight(.semibold)) } }
        }
        .padding(.vertical, 13)
        .overlay(alignment: .bottom) { Rectangle().fill(BZColor.sand).frame(height: 1) }
    }

    private func actionTile(_ icon: String, _ title: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: icon).font(.system(size: 18))
                Text(title).font(BZFont.small.weight(.semibold))
            }
            .frame(maxWidth: .infinity).padding(.vertical, 12)
            .background(Color.white, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .foregroundStyle(enabled ? BZColor.ink : BZColor.mute.opacity(0.5))
        }
        .disabled(!enabled)
        .buttonStyle(PressableStyle())
    }

    private func serviceLabels(_ p: NearbyPlace) -> [String] {
        var out: [String] = []
        if p.attributes.contains(.dineIn) { out.append(L("service.dinein")) }
        if p.attributes.contains(.outdoorSeating) { out.append(L("service.outdoor")) }
        if p.attributes.contains(.takeout) { out.append(L("service.takeout")) }
        if p.attributes.contains(.delivery) { out.append(L("service.delivery")) }
        if p.attributes.contains(.reservable) { out.append(L("service.reservable")) }
        return out
    }

    private func todayHours(_ p: NearbyPlace) -> String? {
        guard let hours = p.weekdayHours, !hours.isEmpty else { return nil }
        // weekdayDescriptions تبدأ بالإثنين (ترتيب Google) — نختار سطر اليوم.
        let weekday = Calendar(identifier: .gregorian).component(.weekday, from: Date()) // 1 = الأحد
        let index = (weekday + 5) % 7
        guard index < hours.count else { return nil }
        let line = hours[index]
        return line.split(separator: ":", maxSplits: 1).last.map { String($0).trimmingCharacters(in: .whitespaces) }
    }

    private func share(_ p: NearbyPlace) {
        #if canImport(UIKit)
        guard let url = p.googleMapsURI else { return }
        let vc = UIActivityViewController(activityItems: [p.name, url], applicationActivities: nil)
        UIApplication.shared.connectedScenes.compactMap { ($0 as? UIWindowScene)?.keyWindow }.first?.rootViewController?.present(vc, animated: true)
        #endif
    }

    private func goNow(_ p: NearbyPlace) {
        Task {
            trip.destination = .place(placeID: p.placeID, name: p.name, coordinate: p.coordinate)
            trip.origin = try? await env?.location.currentLocation()
            trip.fromPlaceKindID = vm.kindID
            trip.options = nil
            router.push(.routeOptions)
        }
    }
}
