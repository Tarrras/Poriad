import SwiftUI
import Shared

/// Маршрут екрана артиста. [name] і [kind] — що знаємо з пошуку чи підписок; з пуша лише [id], решту довозять картки подій.
struct ArtistRoute: Hashable {
    let id: String
    var name: String?
    var kind: ArtistKind?
}

/// Екран артиста: ім'я, вид словом, «Стежити» і найближчі події тими самими рядками, що видача пошуку. Порожньо —
/// «Поки нічого не заплановано»: підписка якраз для цього. Стан живе в `AppState.artist`, один слот на весь застосунок,
/// тож після повернення з іншого екрана артиста екран забирає його назад (див. `.task`).
struct ArtistView: View {
    let route: ArtistRoute
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var auth = false

    private var artist: ArtistState? { model.state?.artist.flatMap { $0.id == route.id ? $0 : nil } }
    private var name: String { artist.map(\.name).flatMap { $0.isEmpty ? nil : $0 } ?? route.name ?? "" }
    private var following: Bool { model.state?.isFollowing(kind: .artist, targetId: route.id) == true }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button { dismiss() } label: {
                    Image(systemName: "chevron.left").font(.system(size: 16, weight: .semibold)).foregroundStyle(Palette.ink)
                        .frame(width: 40, height: 40).background(Palette.surface, in: Circle())
                }.buttonStyle(PressableStyle()).accessibilityLabel("Назад")
                Spacer(minLength: 0)
            }.padding(.horizontal, Space.page).padding(.vertical, Space.md)
            ScrollView {
                VStack(alignment: .leading, spacing: Space.lg) {
                    VStack(alignment: .leading, spacing: Space.sm) {
                        Text(name).font(PoruchFont.serifDisplay).kerning(-0.5).foregroundStyle(Palette.ink)
                            .multilineTextAlignment(.leading)
                        if let kind = artistKindLabel(artist?.kind ?? route.kind) {
                            Text(kind).font(PoruchFont.subhead).foregroundStyle(Palette.inkSecondary)
                        }
                        FollowPill(following: following) {
                            guard model.state?.signedIn == true else { auth = true; return }
                            model.app.setFollowing(kind: .artist, targetId: route.id, name: name, following: !following)
                        }
                        Text("Скажемо, коли зʼявиться нова подія").font(PoruchFont.caption).foregroundStyle(Palette.inkTertiary)
                    }
                    events
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, Space.page).padding(.bottom, Space.section)
            }
        }
        .background(Palette.canvas)
        .hidesTabBar()
        .toolbar(.hidden, for: .navigationBar)
        .navigationBarBackButtonHidden()
        // Слот стану один: екран, що став зверху знову, забирає його назад (інакше показав би події іншого артиста).
        .task(id: route.id) {
            if model.state?.artist?.id != route.id { model.app.openArtist(artistId: route.id, name: route.name, kind: route.kind) }
        }
        .sheet(isPresented: $auth) { NavigationStack { AuthView() } }
    }

    @ViewBuilder private var events: some View {
        if let artist, !artist.loading || !artist.events.isEmpty {
            if artist.events.isEmpty {
                EmptyState(
                    symbol: "calendar.badge.exclamationmark", title: "Поки нічого не заплановано",
                    message: "Натисніть «Стежити», і ми скажемо, коли зʼявиться нова подія."
                )
            } else {
                VStack(alignment: .leading, spacing: Space.sm) {
                    SectionHeader(title: "Найближчі події")
                    GroupedRows {
                        ForEach(Array(artist.events.enumerated()), id: \.element.id) { position, event in
                            if position > 0 { Divider().overlay(Palette.hairline).padding(.leading, Space.lg + 56 + Space.md) }
                            NavigationLink(value: EventRoute(id: event.id)) {
                                EventResultRow(event: event, withCity: true)
                            }
                            .buttonStyle(PressableStyle(pressedScale: 1))
                        }
                    }
                }
            }
        } else {
            ProgressView().frame(maxWidth: .infinity).padding(.vertical, Space.section)
        }
    }
}
