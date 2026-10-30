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
    /// Штамп «ЗБЕРЕЖЕНО» на квитку: 0 — нема, 1 — поставлено. Пружина дає штампу «удар» з легким відскоком.
    @State private var stamp: CGFloat = 0
    /// Систему вже питали або дозволено: тоді наприкінці лише «Готово».
    @State private var askable = false
    /// Шторка з повним описом поточної картки: стос під нею чекає на тій самій картці.
    @State private var reading = false

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
                        // Цілим словом: на AX5 «Пропу-стити» переносилось по складах, хоч місця поруч з «1 з 9» досить.
                        Text(Copy.onboarding_skip).font(PoruchFont.button).foregroundStyle(Palette.inkSecondary).fixedSize().tapTarget()
                    }.buttonStyle(.plain)
                }
            }
            if finished { summary } else { stack }
        }
        .padding(.horizontal, Space.page).padding(.top, Space.md).padding(.bottom, Space.lg)
        .background(Palette.canvas.ignoresSafeArea())
        .task { askable = await NotificationPermission.askable() }
        .sheet(isPresented: $reading) { if index < cards.count { DeckDescription(event: cards[index]) } }
        // Стос із головної теж: інакше перше «Так» відкривало системне питання посеред стосу.
        .onAppear { ReminderPrompt.paused = true }
        .onDisappear { ReminderPrompt.paused = false }
    }

    private var stack: some View {
        VStack(alignment: .leading, spacing: Space.lg) {
            // Не вміщається (великий шрифт, SE) — прокрутка над кнопками, а не «Так» і «Ні» за краєм екрана. Там змаху нема:
            // він забирав вертикальну прокрутку, а відповісти й так можна кнопками.
            ViewThatFits(in: .vertical) {
                question(swipes: true)
                ScrollView { question(swipes: false) }
            }
            HStack(spacing: Space.md) {
                SecondaryButton(title: Copy.deck_no) { answer(false) }
                PrimaryButton(title: Copy.deck_yes, glyph: PoruchIcons.bookmark) { answer(true) }
            }
        }
    }

    private func question(swipes: Bool) -> some View {
        let event = cards[index]
        // Без фото квиток друкований: «що це» й уривок — на самому квитку, і висота за вмістом, а не 300 з порожнім полем.
        let printed = !event.hasCover
        return VStack(alignment: .leading, spacing: Space.lg) {
            VStack(alignment: .leading, spacing: Space.xs) {
                Text(Copy.deck_title).font(PoruchFont.brandTitle1).kerning(-0.4).foregroundStyle(Palette.ink)
                Text(Copy.deck_subtitle).font(PoruchFont.subhead).foregroundStyle(Palette.inkSecondary)
            }
            Spacer(minLength: 0)
            // Квиток і під ним — що це за подія: людина має розуміти, що їй пропонують, а не вгадувати з назви.
            VStack(alignment: .leading, spacing: Space.md) {
                // Тут квиток — не кнопка: VoiceOver читає його текстом, а відповідь — «Так» і «Ні».
                EventHeroCard(event: event, height: printed ? 0 : 300, extra: printed ? AnyView(about(event)) : nil) {}
                    .allowsHitTesting(false)
                    .accessibilityRemoveTraits(.isButton)
                    .accessibilityValue(printed ? aboutText(event) : "")
                    // «Так» штампує квиток, як касир, — стан мовою «Корінця»; посередині обкладинки, а не корінця.
                    // Зі «зменшити рух» штамп лише проявляється, без удару масштабом.
                    .overlay(alignment: .top) {
                        TicketStamp(text: Copy.deck_saved, tone: .success, glyph: PoruchIcons.bookmarkFilled, onFill: !printed)
                            .scaleEffect(reduceMotion ? 1.5 : 2.4 - 0.9 * stamp).opacity(min(stamp, 1))
                            .offset(x: -42).padding(.top, 64)
                            .accessibilityHidden(true)
                    }
                VStack(alignment: .leading, spacing: Space.xs) {
                    if !printed { about(event) }
                    more(event)
                }
            }
                .contentShape(Rectangle())
                .offset(x: drag)
                .rotationEffect(.degrees(reduceMotion ? 0 : Double(drag / 30)))
                .gesture(swipes ? swipe : nil)
                .id(event.id)
                .transition(.opacity)
            Spacer(minLength: 0)
        }
    }

    /// Змах — прискорювач відповіді: праворуч «так», ліворуч «ні».
    private var swipe: some Gesture {
        DragGesture()
            .onChanged { drag = $0.translation.width }
            .onEnded { value in
                if abs(value.translation.width) > 110 { answer(value.translation.width > 0) }
                else { withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { drag = 0 } }
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
                    .lineLimit(4).fixedSize(horizontal: false, vertical: true)
            }
            if let listing = event.listing, listing.isFree?.boolValue == true || listing.priceMin != nil {
                Text(listingPrice(listing)).font(PoruchFont.caption).foregroundStyle(Palette.inkTertiary)
            }
        }
    }

    /// Те саме, що `about`, одним рядком для VoiceOver: на друкованому квитку воно всередині, а квиток читається одним реченням.
    private func aboutText(_ event: Event) -> String {
        let price = event.listing.flatMap { $0.isFree?.boolValue == true || $0.priceMin != nil ? listingPrice($0) : nil }
        return [event.about.line, event.about.excerpt, price].compactMap { $0 }.joined(separator: ". ")
    }

    /// «Детальніше ›» під квитком: уривок обрізаний, а опис агента ховає опис продавця — повністю їх видно в шторці.
    @ViewBuilder
    private func more(_ event: Event) -> some View {
        if !event.displayDescription.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            Button { reading = true } label: {
                HStack(spacing: Space.xs) {
                    Text(Copy.deck_more).font(PoruchFont.button)
                    PoruchIcon(glyph: PoruchIcons.chevronRight, size: 14)
                }
                .foregroundStyle(Palette.ink).tapTarget()
            }
            .buttonStyle(.plain)
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
                // «Не зараз» — теж відповідь: без позначки наступний запуск питав про дайджест удруге.
                Button {
                    UserDefaults.standard.set(true, forKey: "poruch.digestAsked")
                    model.app.digestPromptAnswered(granted: false, from: "deck"); close(skipped: false)
                } label: {
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
        flying = true
        Task {
            if yes {
                withAnimation(reduceMotion ? .easeOut(duration: 0.15) : .spring(response: 0.22, dampingFraction: 0.55)) { stamp = 1 }
                try? await Task.sleep(for: .milliseconds(reduceMotion ? 350 : 280))
            }
            if !reduceMotion {
                withAnimation(.easeIn(duration: 0.18)) { drag = yes ? 600 : -600 }
                try? await Task.sleep(for: .milliseconds(180))
            }
            drag = 0; stamp = 0
            withAnimation(reduceMotion ? nil : .easeOut(duration: 0.2)) { index += 1 }
            flying = false
            // VoiceOver: фокус лишається на «Так», тож відповідь і нову картку кажемо вголос.
            let next = index < cards.count
                ? Copy.deck_a11y_card("\(index + 1)", "\(cards.count)", cards[index].displayTitle) : Copy.deck_a11y_done
            AccessibilityNotification.Announcement(yes ? "\(Copy.deck_saved). \(next)" : next).post()
        }
    }

    private func close(skipped: Bool) {
        model.app.deckDone(yesCount: Int32(kept.count), shown: Int32(min(index + (skipped ? 1 : 0), cards.count)), skipped: skipped)
        onDone()
    }
}

/// Повний опис картки стосу: «що це», опис агента й дозволений опис продавця з посиланням на джерело — як на деталях.
private struct DeckDescription: View {
    let event: Event
    var body: some View {
        let pitch = event.pitch?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let description = event.displayDescription.trimmingCharacters(in: .whitespacesAndNewlines)
        ScrollView {
            VStack(alignment: .leading, spacing: Space.md) {
                Text(event.displayTitle).font(PoruchFont.brandTitle2).kerning(-0.2).foregroundStyle(Palette.ink)
                if let line = event.about.line { Text(line).font(PoruchFont.cardName).foregroundStyle(Palette.ink) }
                if !pitch.isEmpty { Text(pitch).font(PoruchFont.bodyText).foregroundStyle(Palette.ink) }
                if !description.isEmpty {
                    Text(description).font(PoruchFont.lead).foregroundStyle(Palette.inkSecondary).lineSpacing(5)
                }
                if let url = sourceURL(event) {
                    Link(destination: url) {
                        Text(Copy.listing_read_more).font(PoruchFont.button).foregroundStyle(Palette.brand).tapTarget()
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, Space.page).padding(.top, Space.xl).padding(.bottom, Space.section)
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .presentationBackground(Palette.canvas)
    }
}
