import SwiftUI
import Shared

/// Рядок «Ваших артистів»: є подія в місті — «сб 14.12 · назва»; нема — тур іншими містами; нема ніде — без анонсів.
private func radarLine(_ row: ArtistRadar) -> String {
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
 * «Ваші артисти» на головній (docs/artist-radar.md): хто їде в місто — з датою, тап веде на подію; решта — тур чи «Поки
 * нових анонсів нема», тап веде на артиста. До п'яти рядків, решта розгортається тут же. Гість теж: стежить без входу.
 */
struct HomeRadarSection: View {
    let rows: [ArtistRadar]
    let open: (String) -> Void
    let add: () -> Void
    @State private var all = false

    private var shown: [ArtistRadar] { all ? rows : Array(rows.prefix(Int(RadarRules.shared.HOME_ROWS))) }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.md) {
            SectionHeader(title: Copy.radar_title, actionLabel: Copy.radar_add, action: add)
            GroupedRows {
                ForEach(Array(shown.enumerated()), id: \.element.artistId) { index, row in
                    if index > 0 { Divider().overlay(Palette.hairline).padding(.leading, Space.lg) }
                    if let next = row.next {
                        Button { open(next.eventId) } label: { line(row) }.buttonStyle(PressableStyle(pressedScale: 1))
                    } else {
                        NavigationLink(value: ArtistRoute(id: row.artistId, name: row.name, kind: row.kind)) { line(row) }
                            .buttonStyle(PressableStyle(pressedScale: 1))
                    }
                }
            }
            if !all && rows.count > shown.count {
                Button { withMotion { all = true } } label: {
                    Text(Copy.radar_more("\(rows.count - shown.count)")).font(PoruchFont.button).foregroundStyle(Palette.ink).tapTarget()
                }
                .buttonStyle(.plain).frame(maxWidth: .infinity)
            }
        }
        .padding(.horizontal, Space.page)
    }

    private func line(_ row: ArtistRadar) -> some View {
        HStack(spacing: Space.md) {
            VStack(alignment: .leading, spacing: 2) {
                Text(row.name).font(PoruchFont.cardName).foregroundStyle(Palette.ink).multilineTextAlignment(.leading)
                Text(radarLine(row)).font(PoruchFont.caption).foregroundStyle(row.next != nil ? Palette.ink : Palette.inkSecondary)
                    .multilineTextAlignment(.leading).lineLimit(2)
            }
            Spacer(minLength: Space.sm)
            PoruchIcon(glyph: PoruchIcons.chevronRight, size: 16).foregroundStyle(Palette.inkTertiary)
        }
        .padding(.horizontal, Space.lg).padding(.vertical, Space.md).contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

/**
 * «За ким стежити?» (docs/artist-radar.md): хто їде в місто людини, найбільше вечорів першими. Вибір кількох, «Стежити за 3».
 * Хто вже в підписках — позначений і тут не знімається.
 */
struct RadarPickerSheet: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var picked: Set<String> = []

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
        model.app.followArtists(picked: (artists ?? []).filter { picked.contains($0.artistId) }, from: "picker")
        dismiss()
    }
}

/**
 * Хто виступає ([AppState.popularArtists]) чипами: вибір кількох у [picked]; хто вже в підписках — позначений і тут не
 * знімається. [dates] — найближча дата в місті; в онбордингу список по країні, і дата з іншого міста збивала б.
 */
struct PopularArtistChips: View {
    @EnvironmentObject private var model: AppModel
    @Binding var picked: Set<String>
    let dates: Bool

    var body: some View {
        if let artists = model.state?.popularArtists {
            if artists.isEmpty {
                Text(Copy.radar_picker_empty).font(PoruchFont.bodyText).foregroundStyle(Palette.inkSecondary)
            } else {
                FlowLayout(spacing: Space.sm) { ForEach(artists, id: \.artistId) { chip($0) } }
            }
        } else {
            ProgressView().tint(Palette.ink).frame(maxWidth: .infinity).padding(.top, Space.xl)
        }
    }

    private func chip(_ artist: PopularArtist) -> some View {
        let followed = model.state?.isFollowing(kind: .artist, targetId: artist.artistId) == true
        let date = dates ? artist.firstAt.flatMap(parseEventDate).map { formatter(zone: "Europe/Kyiv", "d.MM").string(from: $0) } : nil
        return RadarChip(name: artist.name, date: date, on: followed || picked.contains(artist.artistId)) {
            if picked.contains(artist.artistId) { picked.remove(artist.artistId) } else { picked.insert(artist.artistId) }
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
