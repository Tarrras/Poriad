import SwiftUI
import Shared

// ---- Поля

/// Поле з малим підписом над рамкою замість плаваючого плейсхолдера: форма читається як список названих речей.
struct LabelledField<Trailing: View>: View {
    let label: String
    @Binding var text: String
    var placeholder: String = ""
    var hint: String?
    var secure: Bool = false
    /// Опис росте з текстом; решта полів однорядкові.
    var multiline: Bool = false
    @ViewBuilder var trailing: Trailing
    var body: some View {
        VStack(alignment: .leading, spacing: Space.sm) {
            // Підпис — назва самого поля для VoiceOver, а не окрема зупинка перед ним: з порожньою назвою
            // заповнене поле озвучувало лише значення, без того, що це за поле.
            Text(label.uppercased()).font(PoruchFont.overline).kerning(1.0).foregroundStyle(Palette.inkTertiary)
                .accessibilityHidden(true)
            HStack(spacing: Space.sm) {
                Group {
                    if secure {
                        SecureField(label, text: $text, prompt: Text(placeholder).foregroundStyle(Palette.inkTertiary))
                    } else if multiline {
                        TextField(label, text: $text, prompt: Text(placeholder).foregroundStyle(Palette.inkTertiary), axis: .vertical)
                            .lineLimit(4...10)
                    } else {
                        TextField(label, text: $text, prompt: Text(placeholder).foregroundStyle(Palette.inkTertiary))
                    }
                }
                .font(PoruchFont.bodyText).foregroundStyle(Palette.ink).tint(Palette.ink).textFieldStyle(.plain)
                .accessibilityHint(hint ?? "")
                trailing
            }
            // Висота вміщує 44 pt ціль кінцевого контролу, не переростаючи сусіднє поле.
            .padding(.horizontal, Space.lg)
            .padding(.vertical, multiline ? Space.md : 0)
            .frame(minHeight: 56, alignment: multiline ? .top : .center)
            // Біле поле на сірому полотні: `surfaceMuted` відрізнявся від полотна на два тони і поле зникало.
            .background(Palette.surface, in: RoundedRectangle(cornerRadius: Corner.sm, style: .continuous))
            if let hint {
                // Читається підказкою поля, а не окремою зупинкою.
                Text(hint).font(PoruchFont.caption).foregroundStyle(Palette.inkTertiary).accessibilityHidden(true)
            }
        }
    }
}

/// Дата народження в рамці поля: повна дата словами, тап розгортає барабан. Компактний `DatePicker`
/// без мітки висів з порожнім відступом і писав рік двома цифрами. Без значення, доки людина дату не
/// обере: правило 18+ не проходить саме. Барабан відкривається на найпізнішій дозволеній даті, як календар на Android.
struct BirthDateField: View {
    @Binding var date: Date?
    let range: ClosedRange<Date>
    @State private var open = false

    var body: some View {
        VStack(spacing: 0) {
            Button {
                if date == nil { date = range.upperBound }
                withMotion { open.toggle() }
            } label: {
                HStack(spacing: Space.sm) {
                    Text(date?.formatted(.dateTime.day().month(.wide).year().locale(Locale(identifier: "uk_UA"))) ?? Copy.birth_date_placeholder)
                        .font(PoruchFont.bodyText).foregroundStyle(date == nil ? Palette.inkTertiary : Palette.ink)
                    Spacer(minLength: 0)
                    PoruchIcon(glyph: PoruchIcons.calendar, size: 18)
                        .foregroundStyle(open ? Palette.brand : Palette.inkSecondary)
                }
                .padding(.horizontal, Space.lg).frame(minHeight: 56).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityHint(open ? Copy.a11y_collapse_dates : Copy.a11y_change_date)
            if open {
                DatePicker("", selection: Binding(get: { date ?? range.upperBound }, set: { date = $0 }), in: range, displayedComponents: .date)
                    .datePickerStyle(.wheel).labelsHidden()
                    .environment(\.locale, Locale(identifier: "uk_UA"))
                    .frame(maxWidth: .infinity)
                    .transition(.opacity)
            }
        }
        .background(Palette.surface, in: RoundedRectangle(cornerRadius: Corner.sm, style: .continuous))
        .clipShape(RoundedRectangle(cornerRadius: Corner.sm, style: .continuous))
    }
}

/// «Коли» одним полем: день і година — дві цілі й дві шторки, між ними перфорація, як лінія відриву на квитку. Годину
/// видно й міняють одним дотиком, а не шукають у шторці за календарем. Поле, а не квиток: корінець кольору жанру
/// належить квитку події згори, і поле, вбране так само, з ним зливалось. Частина години сталої ширини, тож поля
/// початку й кінця стоять колонками. Те саме, що `DateTimeField` на Android.
struct DateTimeField: View {
    let label: String
    let date: String
    let time: String
    let onDate: () -> Void
    let onTime: () -> Void

    @ScaledMetric(relativeTo: .body) private var timeWidth: CGFloat = 112

    var body: some View {
        VStack(alignment: .leading, spacing: Space.sm) {
            Text(label.uppercased()).font(PoruchFont.overline).kerning(1.0).foregroundStyle(Palette.inkTertiary)
                .accessibilityHidden(true)
            HStack(spacing: 0) {
                part(PoruchIcons.calendar, date.isEmpty ? Copy.pick_date : date, blank: date.isEmpty,
                     label: "\(label): \(date.isEmpty ? Copy.pick_date : date)", action: onDate)
                part(PoruchIcons.clock, time.isEmpty ? Copy.time : time, blank: time.isEmpty,
                     label: "\(label), \(Copy.time.lowercased()): \(time.isEmpty ? Copy.pick_time : time)", action: onTime)
                    .frame(width: min(timeWidth, 168))
                    // Накладкою, а не в ряду: у `fixedSize` фігура брала свої 10 pt висоти, і лінії не було.
                    .overlay(alignment: .leading) { TearLine() }
            }
            .fixedSize(horizontal: false, vertical: true)
            .background(Palette.surface)
            .clipShape(RoundedRectangle(cornerRadius: Corner.sm, style: .continuous))
        }
    }

    private func part(_ glyph: PoruchGlyph, _ text: String, blank: Bool, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: Space.md) {
                PoruchIcon(glyph: glyph, size: 20).foregroundStyle(Palette.inkSecondary)
                Text(text).font(PoruchFont.bodyText).monospacedDigit().minimumScaleFactor(0.7)
                    .foregroundStyle(blank ? Palette.inkTertiary : Palette.ink)
            }
            .padding(.horizontal, Space.lg)
            .frame(maxWidth: .infinity, minHeight: 56, maxHeight: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(FieldPartStyle())
        .accessibilityLabel(label)
    }
}

/// Натиск на частину поля: частина тьмяніє чорнилом (уночі світлішає папером), а не просідає — просіла б лише
/// половина поля, і перфорація роз'їхалась би.
private struct FieldPartStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.overlay { if configuration.isPressed { Palette.brand.opacity(0.08) } }
    }
}

/// Місяць сіткою в мові «Корінця»: вибраний день — коло чорнилом (уночі папером), як вибраний чип; сьогодні — кільце
/// чорнилом; дні до `minimum` тьмяні й недоступні. Тиждень з понеділка, дні — у поясі події, година обраної дати
/// лишається: сітка міняє лише день. Системний календар вибраний день лише підсвічував блідим колом, а «сьогодні» не
/// позначав. Те саме, що `DatePicker` у кольорах токенів на Android.
struct CalendarGrid: View {
    @Binding var selection: Date
    let minimum: Date
    let zone: String
    /// Перший день показаного місяця.
    @State private var month: Date
    @ScaledMetric(relativeTo: .body) private var dot: CGFloat = 40

    init(selection: Binding<Date>, minimum: Date, zone: String) {
        _selection = selection
        self.minimum = minimum
        self.zone = zone
        _month = State(initialValue: Self.weekCalendar(zone).dateInterval(of: .month, for: selection.wrappedValue)?.start ?? selection.wrappedValue)
    }

    private static func weekCalendar(_ zone: String) -> Calendar {
        var week = calendar(zone: zone)
        week.firstWeekday = 2
        return week
    }
    private var cal: Calendar { Self.weekCalendar(zone) }

    var body: some View {
        VStack(spacing: Space.sm) {
            header
            HStack(spacing: 0) {
                ForEach(weekdays, id: \.self) { name in
                    Text(name).font(PoruchFont.overline).kerning(1.0).foregroundStyle(Palette.inkTertiary).frame(maxWidth: .infinity)
                }
            }
            .accessibilityHidden(true)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 0), count: 7), spacing: Space.xs) {
                ForEach(Array(days.enumerated()), id: \.offset) { _, day in
                    if let day { cell(day) } else { Color.clear.frame(height: 44) }
                }
            }
        }
    }

    private var header: some View {
        HStack(spacing: 0) {
            Text(title(month)).font(PoruchFont.brandTitle3).foregroundStyle(Palette.ink).accessibilityAddTraits(.isHeader)
            Spacer(minLength: Space.sm)
            // Назад — не раніше місяця, з якого вже можна обирати.
            turn(-1, glyph: PoruchIcons.chevronLeft, label: Copy.previous_month,
                 enabled: month > (cal.dateInterval(of: .month, for: minimum)?.start ?? minimum))
            turn(1, glyph: PoruchIcons.chevronRight, label: Copy.next_month, enabled: true)
        }
    }

    private func turn(_ delta: Int, glyph: PoruchGlyph, label: String, enabled: Bool) -> some View {
        Button {
            if let next = cal.date(byAdding: .month, value: delta, to: month) { withMotion { month = next } }
        } label: {
            PoruchIcon(glyph: glyph, size: 20).tapTarget()
        }
        .buttonStyle(PressableStyle(pressedScale: 0.9))
        .foregroundStyle(enabled ? Palette.ink : Palette.inkTertiary.opacity(0.5))
        .disabled(!enabled)
        .accessibilityLabel(label)
    }

    /// Порожні клітинки до першого дня (тиждень з понеділка), далі дні місяця.
    private var days: [Date?] {
        guard let range = cal.range(of: .day, in: .month, for: month) else { return [] }
        let lead = (cal.component(.weekday, from: month) - cal.firstWeekday + 7) % 7
        return Array(repeating: nil, count: lead) + range.map { cal.date(byAdding: .day, value: $0 - 1, to: month) }
    }

    private var weekdays: [String] {
        let names = cal.shortStandaloneWeekdaySymbols
        return (0..<7).map { names[($0 + cal.firstWeekday - 1) % 7].uppercased() }
    }

    private func cell(_ day: Date) -> some View {
        let chosen = cal.isDate(day, inSameDayAs: selection)
        let open = day >= cal.startOfDay(for: minimum)
        let side = min(dot, 44)
        return Button { pick(day) } label: {
            Text("\(cal.component(.day, from: day))")
                .font(PoruchFont.bodyText).fontWeight(chosen ? .semibold : .regular).monospacedDigit()
                .lineLimit(1).minimumScaleFactor(0.7)
                .foregroundStyle(chosen ? Palette.onBrand : open ? Palette.ink : Palette.inkTertiary.opacity(0.5))
                .frame(width: side, height: side)
                .background { if chosen { Circle().fill(Palette.brand) } }
                .overlay { if cal.isDateInToday(day) && !chosen { Circle().strokeBorder(Palette.brand, lineWidth: 1.5) } }
                .frame(maxWidth: .infinity, minHeight: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(PressableStyle(pressedScale: 0.9))
        .disabled(!open)
        .accessibilityLabel(formatter(zone: zone, "d MMMM, EEEE").string(from: day))
        .accessibilityAddTraits(chosen ? .isSelected : [])
    }

    /// Новий день, та сама година; раніше за `minimum` — не можна, як і в системному пікері.
    private func pick(_ day: Date) {
        var parts = cal.dateComponents([.year, .month, .day], from: day)
        let time = cal.dateComponents([.hour, .minute], from: selection)
        parts.hour = time.hour
        parts.minute = time.minute
        guard let date = cal.date(from: parts) else { return }
        withMotion { selection = max(date, minimum) }
    }

    /// «Жовтень 2026».
    private func title(_ date: Date) -> String {
        let text = formatter(zone: zone, "LLLL yyyy").string(from: date)
        return text.prefix(1).uppercased() + text.dropFirst()
    }
}

extension LabelledField where Trailing == EmptyView {
    init(
        label: String, text: Binding<String>, placeholder: String = "",
        hint: String? = nil, secure: Bool = false, multiline: Bool = false
    ) {
        self.init(label: label, text: text, placeholder: placeholder, hint: hint, secure: secure, multiline: multiline) {
            EmptyView()
        }
    }
}
