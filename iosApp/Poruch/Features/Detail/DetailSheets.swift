import SwiftUI
import PhotosUI
import EventKit
import Shared

/// Маршрут деталей події: для шляху стосу й для шторки.

// Листи й дрібні view деталей: скарга, оцінка, «Шукаю компанію», кнопки на скримі. Розрізано з EventDetailView.swift.

struct ShareText: Identifiable {
    let text: String
    var id: String { text }
}

/// Системний аркуш «Поділитися». `ShareLink` — лише кнопка, а тут його відкриває створення супутника.
struct ActivitySheet: UIViewControllerRepresentable {
    let items: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}

/// Коротка шторка замість повного редактора: лише час зустрічі, де зустрітись і скільки людей.
/// Назву, місце й кінець сервер бере з афіші.
struct CompanionSheet: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    let event: Event
    private let times: [String]
    @State private var at: Int
    @State private var note = ""
    @State private var capacity = Int(CompanionRules.shared.DEFAULT_CAPACITY)

    init(event: Event) {
        self.event = event
        let now = nowInstant()
        let times = CompanionRules.shared.meetTimes(startsAt: event.startsAt, now: now)
        let fallback = CompanionRules.shared.defaultMeetAt(startsAt: event.startsAt, now: now)
        self.times = times
        _at = State(initialValue: fallback.flatMap { times.firstIndex(of: $0) } ?? 0)
    }

    private var mutating: Bool { model.state?.mutating == true }
    private var meetAt: String? { times.indices.contains(at) ? times[at] : nil }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.lg) {
                Text(Copy.companion_seek).font(PoruchFont.serifTitle2).kerning(-0.2).foregroundStyle(Palette.ink)
                Text(event.displayTitle).font(PoruchFont.serifTitle3).kerning(-0.1).foregroundStyle(Palette.inkSecondary).lineLimit(2)
                Text(Copy.companion_sheet_body)
                    .font(PoruchFont.bodyText).foregroundStyle(Palette.inkSecondary)
                if let meetAt {
                    let lead = (times.count - 1 - at) * Int(CompanionRules.shared.STEP_MINUTES)
                    stepper(Copy.companion_meet_time, value: sessionLabel(EventSession(id: event.id, startsAt: meetAt, timeZone: event.timeZone, cancelled: false)).hour,
                            caption: lead == 0 ? Copy.companion_at_start : Copy.companion_lead("\(leadWords(lead))"),
                            minus: (Copy.companion_earlier, at > 0, { at -= 1 }), plus: (Copy.companion_later, at < times.count - 1, { at += 1 }))
                }
                LabelledField(label: Copy.companion_meet_note, text: $note, placeholder: Copy.companion_meet_note_hint)
                    .onChange(of: note) { _, value in
                        let limit = Int(CompanionRules.shared.NOTE_MAX)
                        if value.count > limit { note = String(value.prefix(limit)) }
                    }
                stepper(Copy.companion_capacity, value: "\(capacity)", caption: nil,
                        minus: (Copy.companion_fewer, capacity > Int(CompanionRules.shared.MIN_CAPACITY), { capacity -= 1 }),
                        plus: (Copy.companion_more, capacity < Int(CompanionRules.shared.MAX_CAPACITY), { capacity += 1 }))
                PrimaryButton(title: Copy.companion_create, symbol: "square.and.arrow.up", loading: mutating,
                              enabled: meetAt != nil && !mutating) {
                    guard let meetAt else { return }
                    model.app.createCompanion(parentId: event.id, meetAt: meetAt, note: note, capacity: Int32(capacity))
                    dismiss()
                }
            }
            .padding(Space.page)
        }
        .background(Palette.canvas)
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }

    private func leadWords(_ minutes: Int) -> String {
        let hours = minutes / 60, rest = minutes % 60
        if hours == 0 { return Copy.duration_minutes("\(rest)") }
        return rest == 0 ? Copy.duration_hours("\(hours)") : Copy.duration_minutes("\(hours) год \(rest)")
    }

    /// Значення з кнопками «−» і «+». Підписи кнопок — для VoiceOver.
    private func stepper(_ label: String, value: String, caption: String?,
                         minus: (String, Bool, () -> Void), plus: (String, Bool, () -> Void)) -> some View {
        HStack(spacing: Space.md) {
            VStack(alignment: .leading, spacing: 2) {
                Text(label.uppercased()).font(PoruchFont.overline).kerning(1.0).foregroundStyle(Palette.inkTertiary)
                Text(value).font(PoruchFont.title2).foregroundStyle(Palette.ink).monospacedDigit()
                if let caption { Text(caption).font(PoruchFont.caption).foregroundStyle(Palette.inkSecondary) }
            }
            Spacer(minLength: 0)
            ForEach([(minus, "minus"), (plus, "plus")], id: \.1) { step, symbol in
                Button(action: step.2) {
                    Image(systemName: symbol).font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(step.1 ? Palette.ink : Palette.inkTertiary)
                        .frame(width: 44, height: 44).background(Palette.surfaceMuted, in: Circle())
                }
                .buttonStyle(PressableStyle()).disabled(!step.1).accessibilityLabel(step.0)
            }
        }
        .padding(.horizontal, Space.lg).padding(.vertical, Space.md)
        .cardSurface()
    }
}

/// Сторінка джерела афіші. Лише https: інші схеми з чужого рядка не мають ставати посиланням.
func sourceURL(_ event: Event) -> URL? {
    guard let raw = event.listing?.canonicalUrl, let url = URL(string: raw), url.scheme == "https" else { return nil }
    return url
}

/// `sheet(item:)` потребує identity, а в `EKEventStore` її нема.
struct CalendarSession: Identifiable {
    let store: EKEventStore
    var id: ObjectIdentifier { ObjectIdentifier(store) }
}

struct ScrimGlyph: View {
    let symbol: String
    var body: some View {
        // Коло завжди біле, бо лежить на довільному фото, тож і гліф завжди темний: `Palette.ink`
        // у темній темі майже білий, і кнопки «назад» та «зберегти» ставали порожніми колами.
        Image(systemName: symbol).font(.system(size: 16, weight: .semibold)).foregroundStyle(Color(light: 0x1D1D1F, dark: 0x1D1D1F))
            .frame(width: 40, height: 40).background(.white.opacity(0.92), in: Circle())
            .overlay(Circle().strokeBorder(.black.opacity(0.06), lineWidth: 1))
    }
}

struct ScrimButton: View {
    let symbol: String
    let label: String
    let action: () -> Void
    var body: some View {
        Button(action: action) { ScrimGlyph(symbol: symbol) }
            .buttonStyle(.plain)
            .accessibilityLabel(label)
    }
}

/// На що скарга: на подію чи на того, хто її опублікував.
enum ReportTarget: String, Identifiable {
    case event, organizer, message, person
    var id: String { rawValue }
    var title: String {
        switch self {
        case .event: Copy.report_event_title
        case .organizer: Copy.report_user_title
        case .message: Copy.chat_report_title
        case .person: Copy.report_person_title
        }
    }
}

/// Скарга: іменована причина для сортування черги модерації плюс необов'язковий текст.
/// Кнопка замість форми: сама оцінка — у `RateSheet`, як у «Моїх подіях».
struct RateEventSection: View {
    let event: Event
    let mine: EventRating?
    @State private var open = false
    var body: some View {
        VStack(alignment: .leading, spacing: Space.md) {
            SectionHeader(title: Copy.rate_title)
            if let mine {
                SecondaryButton(title: "Ваша оцінка ★ \(mine.score) · змінити") { open = true }
            } else {
                PrimaryButton(title: Copy.rate_action) { open = true }
            }
        }
        .sheet(isPresented: $open) { RateSheet(event: event, mine: mine) }
    }
}

/// «Як пройшло?»: бал 1–5, що сподобалось, кілька слів організатору. Повторна відправка
/// замінює попередню. Спільна для деталей і «Моїх подій».
struct RateSheet: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    let event: Event
    let mine: EventRating?
    @State private var score: Int
    @State private var tags: Set<String>
    @State private var comment: String
    /// Перемикач «Стежити за організатором». Nil — не чіпали: тоді початкове значення дає стан підписок.
    @State private var follow: Bool?

    init(event: Event, mine: EventRating?) {
        self.event = event; self.mine = mine
        _score = State(initialValue: mine.map { Int($0.score) } ?? 0)
        _tags = State(initialValue: Set((mine?.tags ?? []).map(\.key)))
        _comment = State(initialValue: mine?.comment ?? "")
    }

    private var mutating: Bool { model.state?.mutating == true }
    /// Теги за категорією події: спершу про суть, далі загальні.
    private var offered: [RatingTag] { RatingRules.shared.tagsFor(category: event.category) }
    /// Організатор, за яким можна стежити: у афіші його нема, а за собою не стежать.
    private var organizerId: String? { event.organizerId.flatMap { $0 == model.state?.session.userId ? nil : $0 } }
    /// Що показує перемикач. Нова оцінка — увімкнено, змінена — як є, щоб не підписати знову того, від кого відписались.
    private var followOrganizer: Bool {
        guard let organizerId else { return false }
        return follow ?? FollowRules.shared.followOnRating(
            alreadyFollowing: model.state?.isFollowing(kind: .organizer, targetId: organizerId) == true, alreadyRated: mine != nil
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: Space.lg) {
                    HStack(spacing: Space.md) {
                        EventThumbnail(event: event, maxDimension: 52).frame(width: 52, height: 52)
                            .clipShape(RoundedRectangle(cornerRadius: Corner.xs, style: .continuous))
                        VStack(alignment: .leading, spacing: 2) {
                            Text(cardOverline(event)).font(PoruchFont.overline).kerning(1.0).foregroundStyle(Palette.inkTertiary)
                            Text(event.displayTitle).font(PoruchFont.serifTitle3).kerning(-0.1).foregroundStyle(Palette.ink).lineLimit(2)
                        }
                    }
                    Text(Copy.rate_title).font(PoruchFont.serifTitle2).kerning(-0.2).foregroundStyle(Palette.ink)
                    VStack(spacing: Space.sm) {
                        HStack(spacing: Space.sm) {
                            ForEach(1...5, id: \.self) { value in
                                Button { score = value } label: {
                                    Text("\(value)").font(PoruchFont.cardName)
                                        .foregroundStyle(value == score ? Palette.onBrand : Palette.ink)
                                        .frame(maxWidth: .infinity).frame(height: 56)
                                        .background {
                                            let shape = RoundedRectangle(cornerRadius: Corner.sm, style: .continuous)
                                            if value == score { shape.fill(brandGradient) } else { shape.fill(Palette.surface) }
                                        }
                                }
                                .buttonStyle(PressableStyle())
                                .accessibilityLabel(Copy.rate_star("\(value)"))
                                .accessibilityAddTraits(value == score ? .isSelected : [])
                            }
                        }
                        HStack {
                            Text(Copy.rate_low)
                            Spacer()
                            Text(Copy.rate_high)
                        }.font(PoruchFont.caption).foregroundStyle(Palette.inkTertiary)
                    }
                    VStack(alignment: .leading, spacing: Space.sm) {
                        Text("ЩО СПОДОБАЛОСЬ").font(PoruchFont.overline).kerning(1.0).foregroundStyle(Palette.inkTertiary)
                        FlexibleChips(
                            items: offered.map { ($0.key, ratingTagTitle($0), nil) },
                            isSelected: { tags.contains($0) },
                            action: { key in if tags.contains(key) { tags.remove(key) } else { tags.insert(key) } }
                        )
                    }
                    LabelledField(label: Copy.rate_comment, text: $comment, placeholder: "Необовʼязково", multiline: true)
                        .onChange(of: comment) { _, value in
                            let limit = Int(RatingRules.shared.COMMENT_MAX)
                            if value.count > limit { comment = String(value.prefix(limit)) }
                        }
                    if organizerId != nil {
                        VStack(alignment: .leading, spacing: Space.sm) {
                            Toggle(isOn: Binding(get: { followOrganizer }, set: { follow = $0 })) {
                                Text(Copy.rate_follow_title).font(PoruchFont.bodyText).foregroundStyle(Palette.ink)
                            }
                            .tint(Palette.brand)
                            Text(Copy.follow_organizer_hint).font(PoruchFont.caption).foregroundStyle(Palette.inkTertiary)
                        }.padding(Space.lg).frame(maxWidth: .infinity, alignment: .leading).cardSurface()
                    }
                }
                .padding(Space.page)
            }
            Divider().overlay(Palette.hairline)
            VStack(spacing: Space.xs) {
                PrimaryButton(title: mine == nil ? Copy.rate_send : Copy.rate_update, loading: mutating,
                              enabled: score > 0 && !mutating) {
                    // Порядок шторки, не порядок тапів.
                    model.app.rateEvent(id: event.id, score: Int32(score), comment: comment,
                                        tags: offered.filter { tags.contains($0.key) },
                                        followOrganizer: organizerId == nil ? nil : KotlinBoolean(bool: followOrganizer))
                    dismiss()
                }
                Button(Copy.rate_skip) { dismiss() }
                    .font(PoruchFont.button).foregroundStyle(Palette.inkSecondary).frame(minHeight: 44)
            }
            .padding(.horizontal, Space.page).padding(.top, Space.lg)
        }
        .background(Palette.canvas)
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }
}

func ratingTagTitle(_ tag: RatingTag) -> String {
    switch tag.key {
    case "atmosphere": Copy.rate_tag_atmosphere
    case "organization": Copy.rate_tag_organization
    case "place": Copy.rate_tag_place
    case "people": Copy.rate_tag_people
    case "on_time": Copy.rate_tag_on_time
    case "music": Copy.music
    case "sound": Copy.rate_tag_sound
    case "humor": Copy.rate_tag_humor
    case "host": Copy.rate_tag_host
    case "program": Copy.rate_tag_program
    case "coach": Copy.rate_tag_coach
    case "workout": Copy.rate_tag_workout
    case "route": Copy.rate_tag_route
    case "views": Copy.rate_tag_views
    case "pace": Copy.rate_tag_pace
    case "guide": Copy.rate_tag_guide
    case "stories": Copy.rate_tag_stories
    case "food": Copy.food
    case "drinks": Copy.rate_tag_drinks
    case "game_choice": Copy.rate_tag_game_choice
    case "rules": Copy.rate_tag_rules
    case "conversation": Copy.rate_tag_conversation
    case "kids_liked": Copy.rate_tag_kids_liked
    case "safety": Copy.rate_tag_safety
    case "speakers": Copy.rate_tag_speakers
    case "useful": Copy.rate_tag_useful
    case "networking": Copy.rate_tag_networking
    default: tag.key
    }
}

/// Відгуки для організатора: середнє, що сподобалось, коментарі — без імен.
struct RatingsSummary: View {
    let ratings: [EventRating]
    var body: some View {
        VStack(alignment: .leading, spacing: Space.md) {
            SectionHeader(title: Copy.ratings_title)
            if let average = RatingRules.shared.average(ratings: ratings)?.doubleValue {
                Text("★ \(String(format: "%.1f", average).replacingOccurrences(of: ".", with: ",")) з 5 · оцінок: \(ratings.count)")
                    .font(PoruchFont.cardName).foregroundStyle(Palette.ink)
                let tags = RatingRules.shared.tagCounts(ratings: ratings)
                if !tags.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: Space.sm) {
                            ForEach(tags, id: \.tag) { StatusBadge(text: "\(ratingTagTitle($0.tag)) · \($0.count)") }
                        }
                    }
                }
                ForEach(Array(ratings.filter { !($0.comment ?? "").isEmpty }.enumerated()), id: \.offset) { _, rating in
                    VStack(alignment: .leading, spacing: Space.xs) {
                        Stars(score: Int(rating.score), size: 14)
                        Text(rating.comment ?? "").font(PoruchFont.bodyText).foregroundStyle(Palette.ink)
                    }.padding(Space.lg).frame(maxWidth: .infinity, alignment: .leading).cardSurface()
                }
            } else {
                Text(Copy.ratings_empty)
                    .font(PoruchFont.subhead).foregroundStyle(Palette.inkSecondary)
            }
        }
    }
}

/// Пʼять зірок у відгуку організатора.
struct Stars: View {
    let score: Int
    var size: CGFloat
    var body: some View {
        HStack(spacing: 2) {
            ForEach(1...5, id: \.self) { value in
                Image(systemName: value <= score ? "star.fill" : "star")
                    .font(.system(size: size)).foregroundStyle(value <= score ? Palette.brand : Palette.inkTertiary)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Copy.rate_star("\(score)"))
    }
}

struct ReportSheet: View {
    let target: ReportTarget
    let send: (ReportReason, String) -> Void
    @Environment(\.dismiss) private var dismiss
    /// Без причини за замовчуванням: інакше поспіх дає хибні скарги найвищого пріоритету.
    @State private var reason: ReportReason?
    @State private var details = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.md) {
                Text(target.title).font(PoruchFont.serifTitle1).kerning(-0.4).foregroundStyle(Palette.ink)
                Text(Copy.report_body)
                    .font(PoruchFont.subhead).foregroundStyle(Palette.inkSecondary)
                ForEach(reportReasons, id: \.value) { option in
                    Button { reason = option.value } label: {
                        HStack(spacing: Space.md) {
                            ZStack {
                                Circle().fill(reason == option.value ? Palette.brand : Palette.surfaceMuted)
                                if reason == option.value {
                                    PoruchIcon(glyph: PoruchIcons.check, size: 14)
                                        .foregroundStyle(Palette.onBrand)
                                }
                            }.frame(width: 20, height: 20)
                            Text(option.title).font(PoruchFont.bodyText).foregroundStyle(Palette.ink)
                            Spacer(minLength: 0)
                        }.padding(.vertical, Space.sm).contentShape(Rectangle())
                    }.buttonStyle(.plain)
                    .accessibilityAddTraits(reason == option.value ? .isSelected : [])
                }
                LabelledField(label: Copy.report_details, text: $details, multiline: true)
                PrimaryButton(title: Copy.report_send, enabled: reason != nil) {
                    if let reason { send(reason, details); dismiss() }
                }
            }
            .padding(Space.page)
        }
        .background(Palette.canvas)
    }
}
