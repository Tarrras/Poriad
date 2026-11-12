import EventKit
import SwiftUI
import Shared

/// «Подію створено» (docs/organizers-1.5.md, 1.6; docs/design-wow-1.5.md, «Застосунки: простота»): на квиток падає
/// штамп, з прорізу під заголовком виїжджає справжній квиток події, далі одна головна дія (поширити), одна другорядна
/// (посилання) і календар текстом. «Готово» вгорі праворуч, як у системних аркушах; воно, змах униз і тап по квитку —
/// на деталі події. Редактор показує його замість себе, щойно публікація скінчилась: друга шторка поверх тієї, що
/// закривається, SwiftUI не показав би.
struct PublishedView: View {
    let published: PublishedEvent
    let done: () -> Void
    @EnvironmentObject var model: AppModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.openURL) private var openURL
    @State private var notice: Notice?
    @State private var share: ShareItems?
    /// Тимчасова тека файлів «Поширити анонс»: прибираємо, щойно меню закрили.
    @State private var folder: URL?
    @State private var preparing = false
    @State private var calendar: CalendarSession?
    /// Квиток події вже виїхав з прорізу.
    @State private var ticketOut = false
    /// Висота квитка — та сама, що в `EventMapCard`: на неї він сховано стоїть над прорізом.
    @ScaledMetric(relativeTo: .body) private var cardHeight = mapCardHeight

    /// Подія з деталей чи «Моїх подій», якщо вже доїхала: жанр для корінця, файли й особисте запрошення.
    private var event: Event? {
        let state = model.state
        return state?.detail.event.flatMap { $0.id == published.id ? $0 : nil }
            ?? state?.library.myEvents.first { $0.id == published.id }
    }

    private var shareTitle: String { published.shareMode == .promote ? Copy.share_promote : Copy.share_friend }

    var body: some View {
        ScrollView {
            VStack(spacing: Space.xl) {
                // Без «зменшити рух» штамп падає раз; з ним — одразу стоїть.
                BrandAnimation(name: "Published", loop: false, still: reduceMotion, stillAt: 1, stub: event.map { categoryStub($0.category) })
                    .frame(width: 200, height: 133)
                    .decorative()
                Text(Copy.published_title).font(PoruchFont.brandDisplay).kerning(-0.5).foregroundStyle(Palette.ink)
                    .multilineTextAlignment(.center).accessibilityAddTraits(.isHeader)
                // Назву несе квиток; поки подія не доїхала в стан — назва словами.
                if let event { slot(event) } else {
                    Text(TitleRules.shared.display(title: published.title)).font(PoruchFont.subhead).foregroundStyle(Palette.inkSecondary)
                        .multilineTextAlignment(.center)
                }
                // Що далі: людина знає, звідки дізнається про тих, хто прийде, і де їх шукати.
                Text(Copy.published_next).font(PoruchFont.caption).foregroundStyle(Palette.inkSecondary)
                    .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
                VStack(spacing: Space.md) {
                    // Маленька компанія (до 12 місць): посилання у свій чат — першим, анонс — другим. Більшій потрібні нові люди.
                    if published.small {
                        PrimaryButton(title: Copy.published_copy_link, glyph: PoruchIcons.link) { copyLink() }
                        SecondaryButton(title: shareTitle, glyph: PoruchIcons.share, enabled: !preparing) { shareTapped() }
                            .frame(maxWidth: .infinity)
                    } else {
                        PrimaryButton(title: shareTitle, glyph: PoruchIcons.share, loading: preparing, enabled: !preparing) { shareTapped() }
                        SecondaryButton(title: Copy.published_copy_link, glyph: PoruchIcons.link) { copyLink() }
                            .frame(maxWidth: .infinity)
                    }
                    Button { addToCalendar() } label: {
                        HStack(spacing: Space.sm) {
                            PoruchIcon(glyph: PoruchIcons.calendar, size: 18)
                            Text(Copy.published_calendar)
                        }
                        .font(PoruchFont.button).foregroundStyle(Palette.inkSecondary)
                        .frame(maxWidth: .infinity).tapTarget()
                    }
                    .buttonStyle(.plain)
                    // Тому, хто веде події не вперше: кабінет на сайті. Тихо, останнім рядком — це не дія цього екрана.
                    if published.cabinet {
                        Button { openCabinet() } label: {
                            HStack(spacing: Space.sm) {
                                PoruchIcon(glyph: PoruchIcons.globe, size: 18)
                                Text(Copy.published_cabinet).multilineTextAlignment(.center)
                            }
                            .font(PoruchFont.button).foregroundStyle(Palette.inkSecondary)
                            .frame(maxWidth: .infinity).tapTarget()
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(.horizontal, Space.page).padding(.bottom, Space.page)
            // Подія доїхала в стан пізніше за екран: проріз розсувається плавно, а не стрибком.
            .animation(reduceMotion ? nil : .easeOut(duration: 0.25), value: event == nil)
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            HStack {
                Spacer()
                Button(Copy.published_done, action: done)
                    .font(PoruchFont.button).foregroundStyle(Palette.ink).tapTarget()
            }
            .padding(.horizontal, Space.page).padding(.top, Space.sm)
            // Хром, як шапка редактора: не росте далі xxLarge.
            .dynamicTypeSize(...DynamicTypeSize.xxLarge)
        }
        .background(Palette.canvas)
        .notice(notice) { notice = nil }
        // Квиток виїжджає, щойно подія є: часто вона доїжджає в стан уже після появи екрана.
        .onAppear { if event != nil { printTicket() } }
        .onChange(of: event == nil) { _, missing in if !missing { printTicket() } }
        .sheet(item: $share, onDismiss: {
            if let folder { try? FileManager.default.removeItem(at: folder) }
            folder = nil
        }) { ActivitySheet(items: $0.items).presentationDetents([.medium, .large]) }
        .sheet(item: $calendar) { session in
            CalendarEditor(
                title: published.title, notes: event?.description_, location: published.location, timeZone: published.timeZone,
                start: Date(timeIntervalSince1970: TimeInterval(published.startMillis) / 1000),
                end: Date(timeIntervalSince1970: TimeInterval(published.endMillis) / 1000), store: session.store
            )
        }
    }

    /// Проріз під заголовком: квиток виїжджає з-під його краю згори, а місце під ним уже є, тож кнопки не стрибають.
    /// Тап — деталі, як «Готово».
    private func slot(_ event: Event) -> some View {
        EventMapCard(event: event, elevation: Elevation.flat, action: done)
            .offset(y: ticketOut ? 0 : -(scaledMapCardHeight(cardHeight) + 6))
            .clipped()
    }

    /// Як на сайті (`.kab-done-ticket`): 1 с після затримки 0,35 с, поки штамп ще падає. «Зменшити рух» — одразу на місці.
    private func printTicket() {
        guard !ticketOut else { return }
        if reduceMotion { ticketOut = true; return }
        withAnimation(.timingCurve(0.25, 0.1, 0.25, 1, duration: 1).delay(0.35)) { ticketOut = true }
    }

    /// «Поширити анонс» — пост для Threads у буфер і меню з ним, фото й відео; «Поділитися з другом» — особисте `?by=`.
    private func shareTapped() {
        guard !preparing else { return }
        model.app.publishDone(action: .share)
        preparing = true
        let known = event
        Task {
            if published.shareMode == .promote {
                // Threads з меню бере лише медіа, тож текст — ще й у буфер.
                UIPasteboard.general.string = published.post
                notice = Notice(text: Copy.threads_copied, isError: false)
                // Медіа — з повних деталей: щойно опублікована подія може ще не мати картки.
                var full = known?.mediaLoaded == true ? known : nil
                if full == nil {
                    await model.reloadEvent(id: published.id)
                    full = model.state?.detail.event.flatMap { $0.id == published.id && $0.mediaLoaded ? $0 : nil }
                }
                let files = FileManager.default.temporaryDirectory.appendingPathComponent("threads-\(UUID().uuidString)", isDirectory: true)
                let downloaded = await SystemActions.download(full.map { $0.media.isEmpty ? $0.imageUrl.map { [$0] } ?? [] : $0.media.map(\.url) } ?? [], into: files)
                folder = files
                share = ShareItems(items: [published.post] + downloaded)
            } else {
                let link = (try? await model.app.inviteLink(eventId: published.id)) ?? published.link
                share = ShareItems(items: [known.map { SystemActions.inviteText(for: $0, link: link) } ?? "\(published.title)\n\(link)"])
            }
            preparing = false
        }
    }

    private func copyLink() {
        model.app.publishDone(action: .theCopy)
        UIPasteboard.general.string = published.link
        notice = Notice(text: Copy.published_link_copied, isError: false)
    }

    private func openCabinet() {
        model.app.publishDone(action: .cabinet)
        if let url = URL(string: LegalLinks.shared.CABINET) { openURL(url) }
    }

    /// Системний редактор календаря: людина сама обирає календар і зберігає, доступу до календаря не питаємо.
    private func addToCalendar() {
        model.app.publishDone(action: .calendar)
        calendar = CalendarSession(store: EKEventStore())
    }
}
