import SwiftUI
import Shared

/// Набір карток для `fullScreenCover(item:)`: сам стос — масив, а шторці потрібен ідентифікатор.
struct DeckCards: Identifiable {
    let id = UUID()
    let events: [Event]
}

/// Стос «Ваш тиждень» (docs/return-hooks.md, хвиля 2): «так/ні» по найближчих подіях «Для вас», «так» — закладка.
/// Наприкінці — «Нагадати мені» з системним питанням про сповіщення під зрозумілу обіцянку. Змах — лише прискорювач:
/// кнопки «Ні» й «Так» завжди є, а «зменшити рух» прибирає політ картки.
struct DeckView: View {
    @Environment(\.appModel) private var appModel
    private var model: AppModel { appModel! }
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let cards: [Event]
    let onDone: () -> Void
    @State private var index = 0
    @State private var kept: [Event] = []
    @State private var drag: CGFloat = 0
    /// Картка ще летить: другий тап у цей час — подвійний тап, а не відповідь на наступну.
    @State private var flying = false
    /// Систему вже питали або дозволено: тоді наприкінці лише «Готово».
    @State private var askable = false

    private var finished: Bool { index >= cards.count }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.lg) {
            HStack {
                if !finished {
                    Text(Copy.deck_progress("\(index + 1)", "\(cards.count)")).font(PoruchFont.subhead).foregroundStyle(Palette.inkTertiary)
                }
                Spacer()
                if !finished {
                    Button { close(skipped: true) } label: {
                        Text(Copy.onboarding_skip).font(PoruchFont.button).foregroundStyle(Palette.inkSecondary).tapTarget()
                    }.buttonStyle(.plain)
                }
            }
            if finished { summary } else { stack }
        }
        .padding(.horizontal, Space.page).padding(.top, Space.md).padding(.bottom, Space.lg)
        .background(Palette.canvas.ignoresSafeArea())
        .task { askable = await NotificationPermission.askable() }
    }

    private var stack: some View {
        VStack(alignment: .leading, spacing: Space.lg) {
            VStack(alignment: .leading, spacing: Space.xs) {
                Text(Copy.deck_title).font(PoruchFont.brandTitle1).kerning(-0.4).foregroundStyle(Palette.ink)
                Text(Copy.deck_subtitle).font(PoruchFont.subhead).foregroundStyle(Palette.inkSecondary)
            }
            Spacer(minLength: 0)
            // Квиток і під ним — що це за подія: людина має розуміти, що їй пропонують, а не вгадувати з назви.
            VStack(alignment: .leading, spacing: Space.md) {
                EventHeroCard(event: cards[index], height: 300) {}
                    .allowsHitTesting(false)
                about(cards[index])
            }
                .contentShape(Rectangle())
                .offset(x: drag)
                .rotationEffect(.degrees(reduceMotion ? 0 : Double(drag / 30)))
                .gesture(
                    DragGesture()
                        .onChanged { drag = $0.translation.width }
                        .onEnded { value in
                            if abs(value.translation.width) > 110 { answer(value.translation.width > 0) }
                            else { withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { drag = 0 } }
                        }
                )
                .id(cards[index].id)
                .transition(.opacity)
            Spacer(minLength: 0)
            HStack(spacing: Space.md) {
                SecondaryButton(title: Copy.deck_no) { answer(false) }
                PrimaryButton(title: Copy.deck_yes, glyph: PoruchIcons.bookmark) { answer(true) }
            }
        }
    }

    /// Що це за подія: речення «що це», уривок опису й ціна — щоб «так» було рішенням, а не вгадуванням з назви.
    @ViewBuilder
    private func about(_ event: Event) -> some View {
        let about = event.about
        VStack(alignment: .leading, spacing: Space.xs) {
            if let line = about.line {
                Text(line).font(PoruchFont.cardName).kerning(-0.2).foregroundStyle(Palette.ink)
                    .lineLimit(2).fixedSize(horizontal: false, vertical: true)
            }
            if let excerpt = about.excerpt {
                Text(excerpt).font(PoruchFont.subhead).foregroundStyle(Palette.inkSecondary)
                    .lineLimit(3).fixedSize(horizontal: false, vertical: true)
            }
            if let listing = event.listing, listing.isFree?.boolValue == true || listing.priceMin != nil {
                Text(listingPrice(listing)).font(PoruchFont.caption).foregroundStyle(Palette.inkTertiary)
            }
        }
    }

    private var summary: some View {
        VStack(alignment: .leading, spacing: Space.lg) {
            VStack(alignment: .leading, spacing: Space.xs) {
                Text(kept.isEmpty ? Copy.deck_empty_title : Copy.deck_done_title).font(PoruchFont.brandTitle1).kerning(-0.4).foregroundStyle(Palette.ink)
                Text(kept.isEmpty ? Copy.deck_empty_body : Copy.deck_done_body).font(PoruchFont.subhead).foregroundStyle(Palette.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            ScrollView {
                VStack(spacing: 0) {
                    ForEach(Array(kept.enumerated()), id: \.element.id) { i, event in
                        if i > 0 { Divider().overlay(Palette.hairline) }
                        VStack(alignment: .leading, spacing: 2) {
                            Text(event.displayTitle).font(PoruchFont.cardName).kerning(-0.2).foregroundStyle(Palette.ink).lineLimit(2)
                            EventDescriptor(event: event, placeFirst: true)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading).padding(Space.lg)
                    }
                }
                .cardSurface()
            }
            .opacity(kept.isEmpty ? 0 : 1)
            if !kept.isEmpty && askable {
                PrimaryButton(title: Copy.deck_remind, glyph: PoruchIcons.bell) {
                    UserDefaults.standard.set(true, forKey: "poruch.digestAsked")
                    NotificationPermission.request { granted in
                        model.app.digestPromptAnswered(granted: granted, from: "deck")
                        if granted { PushDelegate.registerIfAllowed() }
                        close(skipped: false)
                    }
                }
                Button { model.app.digestPromptAnswered(granted: false, from: "deck"); close(skipped: false) } label: {
                    Text(Copy.digest_prompt_no).font(PoruchFont.button).foregroundStyle(Palette.inkSecondary).tapTarget()
                }.buttonStyle(.plain).frame(maxWidth: .infinity)
            } else {
                PrimaryButton(title: Copy.deck_finish) { close(skipped: false) }
            }
        }
    }

    private func answer(_ yes: Bool) {
        guard !flying, index < cards.count else { return }
        let event = cards[index]
        model.app.deckAnswered(id: event.id, yes: yes, position: Int32(index))
        if yes { kept.append(event) }
        let away: CGFloat = yes ? 600 : -600
        if reduceMotion {
            drag = 0; index += 1
        } else {
            flying = true
            withAnimation(.easeIn(duration: 0.18)) { drag = away }
            Task {
                try? await Task.sleep(for: .milliseconds(180))
                drag = 0
                withAnimation(.easeOut(duration: 0.2)) { index += 1 }
                flying = false
            }
        }
    }

    private func close(skipped: Bool) {
        model.app.deckDone(yesCount: Int32(kept.count), shown: Int32(min(index + (skipped ? 1 : 0), cards.count)), skipped: skipped)
        onDone()
    }
}
