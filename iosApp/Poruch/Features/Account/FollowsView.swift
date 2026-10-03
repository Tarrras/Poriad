import SwiftUI
import Shared

/// Маршрут підписок у стеку: з профілю й з головної це повний екран, а не шторка.
struct FollowsRoute: Hashable {}

/// Підписки окремим екраном: список може бути довгим, і в профілі йому не місце. Тап по закладу веде на мапу, по
/// організатору — до його картки, «Не стежити» — відписка.
struct FollowsView: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openMap) private var openMap
    /// Картка організатора з рядка підписки. Див. `personSheet`.
    @State private var showingPerson = false

    private var follows: [Follow] { model.state?.library.follows ?? [] }

    var body: some View {
        VStack(spacing: 0) {
            PageHeader(title: "Підписки", back: { dismiss() })
            if follows.isEmpty {
                EmptyState(
                    symbol: "bell", title: "Ви ні за ким не стежите",
                    message: "Натисніть «Стежити» на закладі чи в організатора — і ми скажемо, коли в них зʼявиться щось нове."
                ).padding(.top, Space.section)
                Spacer(minLength: 0)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: Space.md) {
                        Text("Скажемо, коли в них зʼявиться щось нове").font(PoruchFont.subhead).foregroundStyle(Palette.inkSecondary)
                        GroupedRows {
                            ForEach(Array(follows.enumerated()), id: \.element.targetId) { position, follow in
                                if position > 0 { Divider().overlay(Palette.hairline).padding(.leading, Space.lg + 40 + Space.md) }
                                followRow(follow)
                            }
                        }
                    }
                    .padding(.horizontal, Space.page).padding(.bottom, Space.section)
                }
            }
        }
        .background(Palette.canvas)
        .hidesTabBar()
        .toolbar(.hidden, for: .navigationBar)
        .navigationBarBackButtonHidden()
        .personSheet(model, isPresented: $showingPerson)
    }

    private func followRow(_ follow: Follow) -> some View {
        let organizer = follow.kind == .organizer
        let artist = follow.kind == .artist
        let upcoming = Int(follow.upcoming)
        let caption = [organizer ? "Організатор" : artist ? "" : follow.city, "\(upcoming) \(ukrainianPlural(upcoming, "подія", "події", "подій"))"]
            .filter { !$0.isEmpty }.joined(separator: " · ")
        let label = HStack(spacing: Space.md) {
            if organizer {
                Avatar(name: follow.name, url: follow.avatarUrl, size: 40)
            } else if artist {
                Image(systemName: "person").font(.system(size: 17, weight: .medium)).foregroundStyle(Palette.ink)
                    .frame(width: 40, height: 40)
                    .background(Palette.surfaceMuted, in: RoundedRectangle(cornerRadius: Corner.xs, style: .continuous))
            } else {
                Image(systemName: "mappin.and.ellipse").font(.system(size: 17, weight: .medium)).foregroundStyle(Palette.ink)
                    .frame(width: 40, height: 40)
                    .background(Palette.surfaceMuted, in: RoundedRectangle(cornerRadius: Corner.xs, style: .continuous))
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(follow.name).font(PoruchFont.serifTitle3).kerning(-0.1).foregroundStyle(Palette.ink)
                    .multilineTextAlignment(.leading).lineLimit(2)
                Text(caption).font(PoruchFont.caption).foregroundStyle(Palette.inkSecondary).lineLimit(1)
            }
            Spacer(minLength: 0)
        }.contentShape(Rectangle())
        return HStack(spacing: Space.md) {
            // Артист відкривається стеком, як і подія: рядок — посилання, а не кнопка.
            if artist {
                NavigationLink(value: ArtistRoute(id: follow.targetId, name: follow.name, kind: follow.artistKind)) { label }.buttonStyle(.plain)
            } else {
                Button {
                    if organizer {
                        showingPerson = true
                        model.app.openPerson(userId: follow.targetId)
                    } else {
                        model.app.openPlace(placeId: follow.targetId)
                        openMap()
                    }
                } label: { label }.buttonStyle(.plain)
            }
            Button {
                model.app.setFollowing(kind: follow.kind, targetId: follow.targetId, name: follow.name, following: false)
            } label: {
                Text("Не стежити").font(PoruchFont.button).foregroundStyle(Palette.ink)
                    .frame(minHeight: 44).contentShape(Rectangle())
            }
            .buttonStyle(.plain).fixedSize()
            .accessibilityLabel("Не стежити: \(follow.name)")
        }
        .padding(.horizontal, Space.lg).padding(.vertical, Space.md)
    }
}
