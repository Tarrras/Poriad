import SwiftUI
import Shared

/// Підпис артиста на екрані «Ви стежите»: є подія в місті — «сб 14.12 · назва»; нема — тур іншими містами; нема ніде —
/// без анонсів. Дати в місті на головній — рядками «Ваше» (`HomePersonalSection`), решта видно тут.
func radarLine(_ row: ArtistRadar) -> String {
    if let next = row.next, let date = parseEventDate(next.startsAt) {
        return formatter(zone: next.timeZone, "EE d.MM").string(from: date) + " · " + next.displayTitle
    }
    if !row.elsewhere.isEmpty {
        let cities = row.elsewhere.map { city in
            parseEventDate(city.startsAt).map { city.city + " " + formatter(zone: "Europe/Kyiv", "d.MM").string(from: $0) } ?? city.city
        }
        return Copy.radar_elsewhere(cities.joined(separator: ", "))
    }
    return Copy.radar_quiet
}

/**
 * «За ким стежити?» (docs/artist-radar.md): хто їде в місто людини, найбільше вечорів першими. Вибір кількох, «Стежити за 3».
 * Хто вже в підписках — позначений і тут не знімається.
 */
struct RadarPickerSheet: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var picked: [String: PopularArtist] = [:]

    private var artists: [PopularArtist]? { model.state?.popularArtists }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.lg) {
                VStack(alignment: .leading, spacing: Space.xs) {
                    Text(Copy.radar_ask_title).font(PoruchFont.brandTitle1).kerning(-0.4).foregroundStyle(Palette.ink)
                    Text(Copy.radar_picker_hint).font(PoruchFont.subhead).foregroundStyle(Palette.inkSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                PopularArtistChips(picked: $picked, dates: true)
            }
            .padding(.horizontal, Space.page).padding(.top, Space.xl).padding(.bottom, Space.section)
        }
        .scrollDismissesKeyboard(.interactively)
        .safeAreaInset(edge: .bottom) {
            if !picked.isEmpty {
                PrimaryButton(title: Copy.radar_picker_follow("\(picked.count)"), glyph: PoruchIcons.bell) { follow() }
                    .padding(.horizontal, Space.page).padding(.vertical, Space.md)
                    // Чипи прокручуються під кнопкою, а не просвічують між нею й краєм.
                    .background(Palette.canvas)
            }
        }
        .background(Palette.canvas)
        .presentationDragIndicator(.visible)
        .task { model.app.loadPopularArtists(everywhere: false) }
        .onDisappear {
            model.app.radarPickerClosed(shown: Int32(artists?.count ?? 0), picked: Int32(picked.count), from: "picker")
        }
    }

    private func follow() {
        model.app.followArtists(picked: Array(picked.values), from: "picker")
        dismiss()
    }
}

/**
 * Пошук і чипи артистів: без запиту — хто виступає ([AppState.popularArtists]), із запитом — збіги по всій країні
 * ([AppState.artistMatches]). Вибір кількох у [picked]; хто вже в підписках — позначений і тут не знімається.
 * [dates] — найближча дата в місті; в онбордингу список по країні, і дата з іншого міста збивала б.
 */
struct PopularArtistChips: View {
    @EnvironmentObject private var model: AppModel
    @Binding var picked: [String: PopularArtist]
    let dates: Bool
    /// Скільки популярних показати без пошуку: в онбордингу під ними ще райони, і довгий список ховав їх за кількома
    /// екранами. Решту знаходить поле.
    var limit: Int? = nil
    @State private var query = ""

    private var searching: Bool { query.trimmingCharacters(in: .whitespaces).count >= Int(DiscoveryRules.shared.MIN_ARTIST_QUERY) }

    /// Без запиту обрані пошуком стоять першими: інакше вони зникали б, лишаючись у «Стежити за N».
    private var shown: [PopularArtist]? {
        if searching { return model.state?.artistMatches }
        guard let popular = model.state?.popularArtists else { return nil }
        let head = limit.map { Array(popular.prefix($0)) } ?? popular
        let ids = Set(head.map(\.artistId))
        return picked.values.filter { !ids.contains($0.artistId) }.sorted { $0.name < $1.name } + head
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.lg) {
            SearchField(text: $query, placeholder: Copy.radar_search, label: Copy.radar_search)
                .autocorrectionDisabled()
                .onChange(of: query) { _, text in model.app.searchArtists(text: text) }
            if let shown {
                if shown.isEmpty {
                    Text(searching ? Copy.radar_search_empty(query.trimmingCharacters(in: .whitespaces)) : Copy.radar_picker_empty)
                        .font(PoruchFont.bodyText).foregroundStyle(Palette.inkSecondary)
                } else {
                    FlowLayout(spacing: Space.sm) { ForEach(shown, id: \.artistId) { chip($0) } }
                }
            } else {
                ProgressView().tint(Palette.ink).frame(maxWidth: .infinity).padding(.top, Space.xl)
            }
        }
    }

    private func chip(_ artist: PopularArtist) -> some View {
        let followed = model.state?.isFollowing(kind: .artist, targetId: artist.artistId) == true
        let date = dates ? artist.firstAt.flatMap(parseEventDate).map { formatter(zone: "Europe/Kyiv", "d.MM").string(from: $0) } : nil
        return RadarChip(name: artist.name, date: date, on: followed || picked[artist.artistId] != nil) {
            picked[artist.artistId] = picked[artist.artistId] == nil ? artist : nil
        }
        .disabled(followed)
    }
}

/// Чип артиста радару: обраний (чи той, за ким стежать) — чорнилом із галочкою; ні — з гліфом [off], якщо він є.
struct RadarChip: View {
    let name: String
    var date: String?
    let on: Bool
    /// Тло невибраного: у шторці — картка, на картці деталей — `surfaceMuted`, як «Стежити» на закладі.
    var offFill: Color = Palette.surface
    var off: PoruchGlyph?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: Space.xs) {
                if on { PoruchIcon(glyph: PoruchIcons.check, size: 14) } else if let off { PoruchIcon(glyph: off, size: 14) }
                Text(name).font(PoruchFont.label).multilineTextAlignment(.leading)
                if let date { Text(date).font(PoruchFont.caption).opacity(0.7) }
            }
            .foregroundStyle(on ? Palette.onBrand : Palette.ink)
            .padding(.horizontal, Space.lg).frame(minHeight: 44)
            .background(on ? Palette.ink : offFill, in: Capsule())
            .contentShape(Capsule())
        }
        .buttonStyle(PressableStyle())
        .accessibilityAddTraits(on ? .isSelected : [])
    }
}
