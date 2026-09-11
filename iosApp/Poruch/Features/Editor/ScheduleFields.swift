import SwiftUI
import Shared

/**
 Коли подія починається і коли закінчується.

 Раніше тут стояли два системні `DatePicker` компактного стилю. Три речі в них не працювали.

 По-перше, вони не знали одне про одного: пересунувши початок за кінець, людина отримувала мертву
 кнопку «Опублікувати» без жодного слова про те, чому. Тепер кінець їде за початком, зберігаючи
 тривалість, — саме цього й чекають від пари полів «з» і «до».

 По-друге, тривалість ніде не було видно, хоч це і є те, що обирають: «на дві години», а не «з
 19:00 до 21:00». Тепер вона написана, і її можна поставити одним дотиком.

 По-третє, компактний пікер відкривався системним спливаючим вікном у системному синьому посеред
 паперового застосунку. Тепер це такий самий аркуш знизу, як усі інші питання в застосунку, — і
 такий самий, як на Android.
 */
struct ScheduleFields: View {
    @Binding var starts: Date
    @Binding var ends: Date
    let zone: TimeZone

    @State private var editing: Edge?

    private enum Edge: Identifiable {
        case start, end
        var id: Int { self == .start ? 0 : 1 }
        var title: String { self == .start ? "Коли починається" : "Коли закінчується" }
    }

    var body: some View {
        VStack(spacing: 0) {
            DateTimeRow(label: "ПОЧАТОК", value: starts, zone: zone) { editing = .start }
            Divider().overlay(Palette.hairline).padding(.horizontal, Space.lg)
            DateTimeRow(label: "ЗАКІНЧЕННЯ", value: ends, zone: zone) { editing = .end }
            Divider().overlay(Palette.hairline).padding(.horizontal, Space.lg)
            durationRow
        }
        .cardSurface()
        .sheet(item: $editing) { edge in
            DateTimeSheet(
                title: edge.title,
                initial: edge == .start ? starts : ends,
                // Подія не може закінчитись раніше, ніж почалась; початок не може бути в минулому.
                minimum: edge == .start ? Date() : starts.addingTimeInterval(minimumDuration),
                zone: zone
            ) { picked in
                if edge == .start { moveStart(to: picked) } else { ends = picked }
            }
            .presentationDetents([.height(560), .large])
        }
    }

    /// Тривалість — те, що насправді обирають. Показана словами й змінна одним дотиком.
    private var durationRow: some View {
        HStack(spacing: Space.sm) {
            VStack(alignment: .leading, spacing: 2) {
                Text("ТРИВАЛІСТЬ").font(PoruchFont.overline).kerning(1.2).foregroundStyle(Palette.inkTertiary)
                Text(durationLabel).font(PoruchFont.bodyText).foregroundStyle(Palette.ink)
            }
            Spacer(minLength: Space.sm)
            HStack(spacing: Space.xs) {
                ForEach(commonDurations, id: \.self) { hours in
                    let seconds = TimeInterval(hours) * 3600
                    Chip(label: "\(hours) год", selected: abs(duration - seconds) < 60) {
                        ends = starts.addingTimeInterval(seconds)
                    }
                }
            }
        }
        .padding(Space.lg)
    }

    private var duration: TimeInterval { max(minimumDuration, ends.timeIntervalSince(starts)) }

    private var durationLabel: String {
        let minutes = Int((duration / 60).rounded())
        let hours = minutes / 60
        let rest = minutes % 60
        if hours == 0 { return "\(rest) хв" }
        return rest == 0 ? "\(hours) год" : "\(hours) год \(rest) хв"
    }

    /// Кінець їде за початком: пересунути подію на інший день не означає скоротити її до нуля.
    private func moveStart(to value: Date) {
        let held = duration
        starts = value
        ends = value.addingTimeInterval(held)
    }
}

/// Рядок «мітка — значення — стрілка», такий самий, як поля в решті редактора.
private struct DateTimeRow: View {
    let label: String
    let value: Date
    let zone: TimeZone
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: Space.md) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(label).font(PoruchFont.overline).kerning(1.2).foregroundStyle(Palette.inkTertiary)
                    Text(scheduleLabel(value, in: zone)).font(PoruchFont.bodyText).foregroundStyle(Palette.ink)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right").font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Palette.inkTertiary)
            }
            .padding(Space.lg)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(label.lowercased()): \(scheduleLabel(value, in: zone))")
        .accessibilityAddTraits(.isButton)
    }
}

/**
 Дата й час в одному аркуші.

 Календар і годинник стоять поруч, а не один після одного: дата й час події — це одне рішення, і
 два кроки з переходом між ними змушували б повертатися назад, щоб перевірити перше.
 */
private struct DateTimeSheet: View {
    let title: String
    let initial: Date
    let minimum: Date
    let zone: TimeZone
    let onPick: (Date) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var value: Date

    init(title: String, initial: Date, minimum: Date, zone: TimeZone, onPick: @escaping (Date) -> Void) {
        self.title = title
        self.initial = initial
        self.minimum = minimum
        self.zone = zone
        self.onPick = onPick
        _value = State(initialValue: max(initial, minimum))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.lg) {
            Text(title).font(PoruchFont.title1).titleTracking().foregroundStyle(Palette.ink)
            ScrollView {
                VStack(spacing: Space.lg) {
                    DatePicker("", selection: $value, in: minimum..., displayedComponents: .date)
                        .datePickerStyle(.graphical)
                        .labelsHidden()
                    Divider().overlay(Palette.hairline)
                    HStack {
                        Text("Час").font(PoruchFont.bodyText).foregroundStyle(Palette.inkSecondary)
                        Spacer(minLength: 0)
                        DatePicker("", selection: $value, in: minimum..., displayedComponents: .hourAndMinute)
                            .labelsHidden()
                    }
                }
                .environment(\.timeZone, zone)
                .padding(Space.lg)
                .cardSurface()
            }
            PrimaryButton(title: "Готово") { onPick(value); dismiss() }
                .frame(maxWidth: .infinity)
        }
        .padding(Space.page)
        .tint(Palette.brand)
        .background(Palette.canvas)
    }
}

/// «Сб, 13 вер. · 19:00» — той самий словник, що й на картках, у поясі самої події.
private func scheduleLabel(_ date: Date, in zone: TimeZone) -> String {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "uk_UA")
    formatter.timeZone = zone
    formatter.dateFormat = "EEE, d MMM · HH:mm"
    return formatter.string(from: date)
}

/// Подія коротша за чверть години — це радше помилка вводу, ніж план.
private let minimumDuration: TimeInterval = 900
/// Скільки триває звичайна зустріч. Три дотики покривають майже все, решта — у пікері.
private let commonDurations = [1, 2, 3]

/**
 Пояс не набирають — його визначає місце події.

 Показуємо його все одно: подія зберігає власний пояс, і мовчки підставлений неправильний гірший
 за видимий. Другий рядок каже, звідки він узявся, бо це різні ступені впевненості.
 */
struct TimeZoneNote: View {
    let zone: String
    let fromPlace: Bool

    var body: some View {
        HStack(spacing: Space.md) {
            Image(systemName: "clock").font(.system(size: 17))
                .foregroundStyle(Palette.inkSecondary)
            VStack(alignment: .leading, spacing: 2) {
                Text("ЧАСОВИЙ ПОЯС").font(PoruchFont.overline).kerning(1.2).foregroundStyle(Palette.inkTertiary)
                Text(readableZone).font(PoruchFont.bodyText).foregroundStyle(Palette.ink)
                Text(fromPlace ? "Визначено за місцем події" : "За вашим пристроєм")
                    .font(PoruchFont.caption).foregroundStyle(Palette.inkTertiary)
            }
            Spacer(minLength: 0)
        }
        .padding(Space.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface()
    }

    /// «Europe/Kyiv · GMT+3»: сам ідентифікатор лишається, бо саме він поїде на сервер, а зсув —
    /// те, що людина насправді звіряє.
    private var readableZone: String {
        guard let resolved = TimeZone(identifier: zone) else { return zone }
        let hours = resolved.secondsFromGMT() / 3600
        return "\(zone) · GMT\(hours >= 0 ? "+" : "")\(hours)"
    }
}
