import SwiftUI
import Shared

/// Початок і кінець події: день і година в одному полі через перфорацію. Кінець їде за початком, зберігаючи
/// тривалість; тривалість видно й можна поставити одним дотиком.
struct ScheduleFields: View {
    @Binding var starts: Date
    @Binding var ends: Date
    let zone: String

    @State private var picking: Picking?

    /// Яке поле відкрило шторку і що в ньому міняють: день чи годину.
    private struct Picking: Identifiable {
        let start: Bool
        let time: Bool
        var id: Int { (start ? 0 : 2) + (time ? 1 : 0) }
        var title: String {
            switch (start, time) {
            case (true, false): Copy.start_date
            case (true, true): Copy.start_time
            case (false, false): Copy.end_date
            case (false, true): Copy.end_time
            }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.lg) {
            field(Copy.starts, starts, start: true)
            field(Copy.ends, ends, start: false)
            durationRow
        }
        .sheet(item: $picking) { picking in
            // Шторка міняє форму одразу: квиток згори передруковує корінець, поки крутиш барабан.
            PickerSheet(
                title: picking.title,
                time: picking.time,
                value: picking.start ? Binding(get: { starts }, set: moveStart(to:)) : $ends,
                // Початок не в минулому, кінець не раніше початку.
                minimum: picking.start ? Date() : starts.addingTimeInterval(minimumDuration),
                zone: zone
            )
        }
    }

    private func field(_ label: String, _ date: Date, start: Bool) -> some View {
        let parts = fieldDateParts(date, zone: zone)
        return DateTimeField(
            label: label, date: parts.day, time: parts.time,
            onDate: { picking = Picking(start: start, time: false) },
            onTime: { picking = Picking(start: start, time: true) }
        )
    }

    /// Тривалість словами, змінна одним дотиком.
    private var durationRow: some View {
        VStack(alignment: .leading, spacing: Space.sm) {
            Text(Copy.duration.uppercased()).font(PoruchFont.overline).kerning(1.0).foregroundStyle(Palette.inkTertiary)
            HStack(spacing: Space.xs) {
                ForEach(commonDurations, id: \.self) { hours in
                    let seconds = TimeInterval(hours) * 3600
                    Chip(label: Copy.duration_hours("\(hours)"), selected: matches(hours)) {
                        ends = starts.addingTimeInterval(seconds)
                    }
                }
                // Значення лише тоді, коли його не каже вибраний чип: «1 год» двічі поруч — шум.
                if !presetPicked {
                    Text(durationLabel).font(PoruchFont.bodyText).foregroundStyle(Palette.ink).padding(.leading, Space.sm)
                }
            }
        }
    }

    private var duration: TimeInterval { max(minimumDuration, ends.timeIntervalSince(starts)) }
    private func matches(_ hours: Int) -> Bool { abs(duration - TimeInterval(hours) * 3600) < 60 }
    private var presetPicked: Bool { commonDurations.contains(where: matches) }

    private var durationLabel: String {
        let minutes = Int((duration / 60).rounded())
        let hours = minutes / 60
        let rest = minutes % 60
        if hours == 0 { return Copy.duration_minutes("\(rest)") }
        return rest == 0 ? Copy.duration_hours("\(hours)") : Copy.duration_hours("\(hours)") + " " + Copy.duration_minutes("\(rest)")
    }

    /// Кінець їде за початком, зберігаючи тривалість.
    private func moveStart(to value: Date) {
        let held = duration
        starts = value
        ends = value.addingTimeInterval(held)
    }
}

/// День або година в шторці — що саме, вирішує частина поля, яку торкнули; заголовок називає поле, бо шторка його
/// закриває. Один пікер на шторку: удвох із календарем година йшла за згин. День — `CalendarGrid` у мові «Корінця»,
/// година — системний барабан. Висота — за вмістом, як у `PromptSheet`. Те саме, що `DateTimeSheet` на Android.
private struct PickerSheet: View {
    let title: String
    let time: Bool
    @Binding var value: Date
    let minimum: Date
    let zone: String

    @Environment(\.dismiss) private var dismiss
    @State private var height: CGFloat = 480

    var body: some View {
        VStack(alignment: .leading, spacing: Space.lg) {
            Text(title).font(PoruchFont.brandTitle2).kerning(-0.2).foregroundStyle(Palette.ink)
                .accessibilityAddTraits(.isHeader)
            Group {
                if time {
                    DatePicker(title, selection: $value, in: minimum..., displayedComponents: .hourAndMinute)
                        .datePickerStyle(.wheel).labelsHidden()
                        .environment(\.timeZone, TimeZone(identifier: zone) ?? .current)
                        .environment(\.locale, Locale(identifier: "uk_UA"))
                        .frame(maxWidth: .infinity)
                } else {
                    CalendarGrid(selection: $value, minimum: minimum, zone: zone)
                }
            }
            .padding(Space.md)
            .cardSurface()
            PrimaryButton(title: Copy.apply) { dismiss() }
        }
        .padding(.horizontal, Space.page).padding(.top, Space.xl).padding(.bottom, Space.lg)
        .tint(Palette.brand)
        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height = $0 }
        .presentationDetents([.height(height)])
        .presentationDragIndicator(.visible)
        .presentationBackground(Palette.canvas)
    }
}

/// Коротше за чверть години — радше помилка вводу.
private let minimumDuration: TimeInterval = 900
/// Типові тривалості одним дотиком; решта в пікері.
private let commonDurations = [1, 2, 3]

/// Пояс події, коли година на телефоні була б іншою: тоді години вище йдуть за чужим годинником, і це треба сказати.
/// Свій час — норма, про нього мовчимо. Порівнюємо зсув на дату події, а не назви: Kiev і Kyiv — один годинник,
/// а літній і зимовий час різняться.
struct TimeZoneNote: View {
    let zone: String
    let city: String
    let at: Date

    var body: some View {
        if let resolved = TimeZone(identifier: zone), resolved.secondsFromGMT(for: at) != TimeZone.current.secondsFromGMT(for: at) {
            HStack(spacing: Space.md) {
                PoruchIcon(glyph: PoruchIcons.clock, size: 20)
                    .foregroundStyle(Palette.inkSecondary)
                VStack(alignment: .leading, spacing: 2) {
                    Text(Copy.timezone.uppercased()).font(PoruchFont.overline).kerning(1.2).foregroundStyle(Palette.inkTertiary)
                    Text(Copy.timezone_local(city.isEmpty ? zone : city, offset(resolved))).font(PoruchFont.bodyText).foregroundStyle(Palette.ink)
                    Text(Copy.timezone_differs).font(PoruchFont.caption).foregroundStyle(Palette.inkTertiary)
                }
                Spacer(minLength: 0)
            }
            .padding(Space.lg)
            .frame(maxWidth: .infinity, alignment: .leading)
            .cardSurface()
            .accessibilityElement(children: .combine)
        }
    }

    /// «GMT+1», «GMT+5:30» — на дату події.
    private func offset(_ zone: TimeZone) -> String {
        let seconds = zone.secondsFromGMT(for: at)
        let minutes = abs(seconds) % 3600 / 60
        return "GMT\(seconds < 0 ? "−" : "+")\(abs(seconds) / 3600)" + (minutes > 0 ? String(format: ":%02d", minutes) : "")
    }
}
