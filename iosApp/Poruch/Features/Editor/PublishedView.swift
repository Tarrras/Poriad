import EventKit
import SwiftUI
import Shared

/// «Подію створено» (docs/organizers-1.5.md, 1.6): на квиток падає штамп, далі — поширити, скопіювати посилання, додати
/// в календар. «Готово» чи змах униз — на деталі події. Редактор показує його замість себе, щойно публікація скінчилась:
/// друга шторка поверх тієї, що закривається, SwiftUI не показав би.
struct PublishedView: View {
    let published: PublishedEvent
    let done: () -> Void
    @EnvironmentObject var model: AppModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var notice: Notice?
    @State private var share: ShareItems?
    /// Тимчасова тека файлів «Поширити анонс»: прибираємо, щойно меню закрили.
    @State private var folder: URL?
    @State private var preparing = false
    @State private var calendar: CalendarSession?

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
                    .frame(width: 300, height: 200)
                    .decorative()
                VStack(spacing: Space.sm) {
                    Text(Copy.published_title).font(PoruchFont.brandDisplay).kerning(-0.5).foregroundStyle(Palette.ink)
                        .multilineTextAlignment(.center).accessibilityAddTraits(.isHeader)
                    Text(TitleRules.shared.display(title: published.title)).font(PoruchFont.subhead).foregroundStyle(Palette.inkSecondary)
                        .multilineTextAlignment(.center)
                }
                VStack(spacing: Space.md) {
                    PrimaryButton(title: shareTitle, glyph: PoruchIcons.share, loading: preparing, enabled: !preparing) { shareTapped() }
                    SecondaryButton(title: Copy.published_copy_link, glyph: PoruchIcons.link) { copyLink() }
                        .frame(maxWidth: .infinity)
                    SecondaryButton(title: Copy.published_calendar, glyph: PoruchIcons.calendar) { addToCalendar() }
                        .frame(maxWidth: .infinity)
                    Button(Copy.published_done, action: done)
                        .font(PoruchFont.button).foregroundStyle(Palette.inkSecondary)
                        .frame(maxWidth: .infinity).frame(minHeight: 44)
                }
            }
            .padding(Space.page).padding(.top, Space.section)
        }
        .background(Palette.canvas)
        .notice(notice) { notice = nil }
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

    /// Системний редактор календаря: людина сама обирає календар і зберігає, доступу до календаря не питаємо.
    private func addToCalendar() {
        model.app.publishDone(action: .calendar)
        calendar = CalendarSession(store: EKEventStore())
    }
}
