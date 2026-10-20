import SwiftUI
import Shared

// ---- Рядки видачі пошуку

/// Відступ лінії між рядками видачі пошуку: від тексту, а не від краю.
let resultRowInset: CGFloat = Space.lg + 56 + Space.md

/// Рядок видачі пошуку: обкладинка категорії, дата, назва й «категорія · місце · ціна»; справа —
/// стан кімнати. Кілька рядків збирає `GroupedRows`. Афіша підписана джерелом окремим рядком:
/// атрибуція на картці обов'язкова (docs/event-ingestion.md §8).
struct EventResultRow: View {
    let event: Event
    var waitlisted = false
    /// Назвати місто в підписі: видача з різних міст.
    var withCity = false
    /// Nil — рядок без власної кнопки, для `NavigationLink`: вкладена кнопка забрала б тап.
    var action: (() -> Void)?

    private var subtitle: String {
        var parts = [categoryName(event.category)]
        let place = eventPlace(event, withCity: withCity)
        if !place.isEmpty { parts.append(place) }
        // Невідому ціну не пишемо: «ціну вкаже джерело» посеред рядка нічого не каже.
        if let listing = event.listing, listing.isFree?.boolValue == true || listing.priceMin != nil {
            let price = listingPrice(listing)
            parts.append(price.prefix(1).lowercased() + price.dropFirst())
        }
        return parts.joined(separator: " · ")
    }

    /// Лише те, що міняє рішення: скасування, стан афіші, стан кімнати. Джерело афіші — окремим рядком.
    private var badge: (String, BadgeTone, PoruchGlyph?)? {
        if event.isCancelled { return (Copy.cancelled_short, .danger, nil) }
        if let listing = event.listing { return listingStamp(listing) }
        guard let room = event.gathering, !event.hasEnded(now: nowInstant()) else { return nil }
        if room.joined { return (Copy.going, .success, PoruchIcons.check) }
        if waitlisted { return (Copy.in_queue, .accent, PoruchIcons.queue) }
        if room.isFull { return (Copy.full, .neutral, nil) }
        let seats = Int(room.seatsLeft)
        if room.isScarce { return (Copy.seats_short(seats), .accent, nil) }
        return nil
    }

    var body: some View {
        if let action {
            Button(action: action) { row }
                .buttonStyle(PressableStyle(pressedScale: 1))
                .accessibilityElement(children: .ignore).accessibilityLabel(ticketA11yLabel(event, state: badge?.0))
        } else {
            row.accessibilityElement(children: .ignore).accessibilityLabel(ticketA11yLabel(event, state: badge?.0))
        }
    }

    private var row: some View {
        HStack(spacing: Space.md) {
            StubTile(event: event, size: 56)
            VStack(alignment: .leading, spacing: 2) {
                Text(event.displayTitle).font(PoruchFont.brandTitle3).kerning(-0.1).foregroundStyle(Palette.ink)
                    .multilineTextAlignment(.leading).lineLimit(2)
                Text(subtitle).font(PoruchFont.caption).foregroundStyle(Palette.inkSecondary).lineLimit(1)
                if let artists = artistsLine(event) {
                    Text(artists).font(PoruchFont.caption).foregroundStyle(Palette.inkSecondary).lineLimit(1)
                }
                if let listing = event.listing {
                    let source = Copy.listing_badge(listing.sellerNames)
                    Text(source).font(PoruchFont.overline).foregroundStyle(Palette.inkTertiary).lineLimit(1)
                }
            }
            Spacer(minLength: 0)
            if let badge { TicketStamp(text: badge.0, tone: badge.1, glyph: badge.2) }
        }
        .padding(.horizontal, Space.lg).padding(.vertical, Space.md)
        .contentShape(Rectangle())
    }
}

/// Склад для картки одним рядком: до трьох імен, ведучий окремо («· ведучий Дмитро»), решта «та ще N». Nil — артистів нема.
/// Імена в картці не тапаються: вся картка вже кнопка, тапабельні чипи лише в деталях. Слова ті самі, що в Android `Components.kt`.
func artistsLine(_ event: Event) -> String? {
    let shown = event.cardArtists
    guard !shown.isEmpty else { return nil }
    let performers = shown.filter { $0.role != .host }.map(\.name).joined(separator: ", ")
    let hosts = shown.filter { $0.role == .host }.map(\.name).joined(separator: ", ")
    let line = [performers.isEmpty ? nil : performers, hosts.isEmpty ? nil : Copy.artist_line_host("\(hosts)")].compactMap { $0 }.joined(separator: " · ")
    let more = Int(event.moreArtists)
    return more > 0 ? Copy.digest_more("\(line)", "\(more)") : line
}

/// Вид словом, лише коли він відомий і не людина: `person` без підпису.
func artistKindLabel(_ kind: ArtistKind?) -> String? {
    switch kind {
    case .group: return Copy.artist_kind_group
    case .show: return Copy.artist_kind_show
    case .company: return Copy.artist_kind_company
    default: return nil
    }
}

/// Рядок артиста в пошуку: піктограма людини, ім'я й скільки подій попереду. Тап веде на екран артиста стеком.
struct ArtistRow: View {
    let artist: ArtistHit

    private var subtitle: String {
        let upcoming = Int(artist.upcoming)
        return [artistKindLabel(artist.kind), Copy.place_upcoming(upcoming)]
            .compactMap { $0 }.joined(separator: " · ")
    }

    var body: some View {
        NavigationLink(value: ArtistRoute(id: artist.id, name: artist.name, kind: artist.kind)) {
            HStack(spacing: Space.md) {
                PoruchIcon(glyph: PoruchIcons.person, size: 20).foregroundStyle(Palette.ink)
                    .frame(width: 40, height: 40)
                    .background(Palette.surfaceMuted, in: RoundedRectangle(cornerRadius: Corner.xs, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text(artist.name).font(PoruchFont.brandTitle3).kerning(-0.1).foregroundStyle(Palette.ink).lineLimit(1)
                    Text(subtitle).font(PoruchFont.caption).foregroundStyle(Palette.inkSecondary).lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, Space.lg).padding(.vertical, Space.md)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableStyle(pressedScale: 1))
        .accessibilityElement(children: .combine)
    }
}

/// Секція «Артисти» у видачі пошуку під «Місцями»: до п'яти рядків.
struct ArtistsGroup: View {
    let artists: [ArtistHit]
    var body: some View {
        VStack(alignment: .leading, spacing: Space.sm) {
            GroupLabel(title: Copy.search_artists_group)
            GroupedRows {
                ForEach(Array(artists.prefix(Int(DiscoveryRules.shared.ARTISTS_LIMIT)).enumerated()), id: \.element.id) { position, artist in
                    if position > 0 { Divider().overlay(Palette.hairline).padding(.leading, Space.lg + 40 + Space.md) }
                    ArtistRow(artist: artist)
                }
            }
        }
    }
}

/// Рядок закладу в пошуку: піктограма місця, назва, адреса й скільки подій попереду.
struct PlaceRow: View {
    let place: Place
    var withCity = false
    let action: () -> Void

    private var subtitle: String {
        let address = withCity && !place.city.isEmpty && !place.address.contains(place.city)
            ? [place.city, place.address].filter { !$0.isEmpty }.joined(separator: ", ")
            : place.address
        let upcoming = Int(place.upcoming)
        return [address, Copy.place_upcoming(upcoming)]
            .filter { !$0.isEmpty }.joined(separator: " · ")
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: Space.md) {
                PoruchIcon(glyph: PoruchIcons.pin, size: 20).foregroundStyle(Palette.ink)
                    .frame(width: 40, height: 40)
                    .background(Palette.surfaceMuted, in: RoundedRectangle(cornerRadius: Corner.xs, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text(place.name).font(PoruchFont.brandTitle3).kerning(-0.1).foregroundStyle(Palette.ink).lineLimit(1)
                    Text(subtitle).font(PoruchFont.caption).foregroundStyle(Palette.inkSecondary)
                        .multilineTextAlignment(.leading).lineLimit(2)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, Space.lg).padding(.vertical, Space.md)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableStyle(pressedScale: 1))
        .accessibilityElement(children: .combine)
    }
}

/// Підпис над `GroupedRows` капітеллю: «Події · 7», «Місця». Праворуч — необов'язкова дія.
struct GroupLabel: View {
    let title: String
    var actionLabel: String?
    var action: (() -> Void)?
    var body: some View {
        HStack {
            Text(title.uppercased(with: Locale(identifier: "uk_UA"))).font(PoruchFont.overline).kerning(1.0).foregroundStyle(Palette.inkTertiary)
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: Space.sm)
            if let actionLabel, let action {
                Button(actionLabel, action: action).font(PoruchFont.label).foregroundStyle(Palette.ink)
            }
        }
    }
}

/// Секція «Місця» у видачі пошуку: заклади з тим самим словом. Тап — мапа на закладі.
struct PlacesGroup: View {
    let places: [Place]
    var withCity = false
    let open: (Place) -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: Space.sm) {
            GroupLabel(title: Copy.search_places_group)
            GroupedRows {
                ForEach(Array(places.enumerated()), id: \.element.id) { position, place in
                    if position > 0 { Divider().overlay(Palette.hairline).padding(.leading, Space.lg + 40 + Space.md) }
                    PlaceRow(place: place, withCity: withCity) { open(place) }
                }
            }
        }
    }
}
