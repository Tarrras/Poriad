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
