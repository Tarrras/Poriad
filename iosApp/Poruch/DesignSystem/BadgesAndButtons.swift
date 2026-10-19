import SwiftUI
import Shared

// ---- Бейджі й кнопки

enum BadgeTone { case brand, success, accent, danger, neutral }

struct StatusBadge: View {
    let text: String
    var tone: BadgeTone = .neutral
    var glyph: PoruchGlyph?
    /// Бейдж лежить на фото. Тонована напівпрозора пігулка на випадковому знімку не читалась:
    /// сірий текст на сірому. На фото — майже непрозора поверхня, чорнило й тінь, як у `SaveButton`.
    var onPhoto: Bool = false
    private var colors: (Color, Color) {
        switch tone {
        case .brand: return (Palette.brandContainer, Palette.onBrandContainer)
        case .success: return (Palette.successContainer, Palette.onSuccessContainer)
        case .accent: return (Palette.accentContainer, Palette.onAccentContainer)
        case .danger: return (Palette.dangerContainer, Palette.danger)
        case .neutral: return (Palette.surfaceMuted, Palette.inkSecondary)
        }
    }
    var body: some View {
        HStack(spacing: Space.xs) {
            if let glyph { PoruchIcon(glyph: glyph, size: 13) }
            Text(text.uppercased()).font(PoruchFont.overline).kerning(1.0)
        }
        .foregroundStyle(onPhoto && (tone == .neutral || tone == .brand) ? Palette.ink : colors.1)
        // Росте з текстом, але не вище Accessibility 1: на фото плашка інакше закривала пів постера.
        .dynamicTypeSize(...DynamicTypeSize.accessibility1)
        .padding(.horizontal, Space.md).padding(.vertical, 5)
        .background {
            if onPhoto {
                Capsule().fill(Palette.surface.opacity(0.92))
                    .overlay(Capsule().strokeBorder(.black.opacity(0.06), lineWidth: 1))
                    .shadow(color: .black.opacity(0.22), radius: 6, y: 2)
            } else {
                Capsule().fill(toneGradient(colors.0, colors.1))
            }
        }
    }
}

/// Питання знизу, як `PoruchSheet` на Android: заголовок із засічками, пояснення, головна й другорядна дія.
/// Змах униз — те саме, що другорядна дія: `onDismiss` у `.sheet` викликає її, якщо кнопку не натиснули.
struct PromptSheet: View {
    let title: String
    let message: String
    let primary: String
    var secondary: String?
    let onPrimary: () -> Void
    var onSecondary: () -> Void = {}
    @Environment(\.dismiss) private var dismiss
    @State private var height: CGFloat = 320
    var body: some View {
        VStack(alignment: .leading, spacing: Space.md) {
            Text(title).font(PoruchFont.brandTitle2).kerning(-0.2).foregroundStyle(Palette.ink)
            Text(message).font(PoruchFont.bodyText).foregroundStyle(Palette.inkSecondary).padding(.bottom, Space.sm)
            PrimaryButton(title: primary) { dismiss(); onPrimary() }
            if let secondary { SecondaryButton(title: secondary) { dismiss(); onSecondary() } }
        }
        .padding(.horizontal, Space.page).padding(.top, Space.xl).padding(.bottom, Space.section)
        .frame(maxWidth: .infinity, alignment: .leading)
        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height = $0 }
        .presentationDetents([.height(height)])
        .presentationDragIndicator(.visible)
        .presentationBackground(Palette.canvas)
    }
}

/// Кнопки — зібрані прямокутники з кутом квитка, а не пігулки: пігулками лишились чипи й бейджі.
let buttonShape = RoundedRectangle(cornerRadius: Corner.md, style: .continuous)

struct PrimaryButton: View {
    let title: String
    var glyph: PoruchGlyph?
    /// SF Symbol лише для чужих знаків, яких у наборі бути не може (логотип Apple).
    var symbol: String?
    var tone: Color?
    var loading: Bool = false
    var enabled: Bool = true
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            HStack(spacing: Space.sm) {
                if loading { ProgressView().tint(enabled ? Palette.onBrand : Palette.inkTertiary) }
                else if let glyph { PoruchIcon(glyph: glyph, size: 18) }
                else if let symbol { Image(systemName: symbol).font(.system(size: 15, weight: .semibold)) }
                // Великий шрифт переносить напис, а не обрізає: кнопка росте від 52 pt.
                Text(title).font(PoruchFont.button).lineLimit(2).multilineTextAlignment(.center)
            }
            .foregroundStyle(enabled ? Palette.onBrand : Palette.inkTertiary)
            .padding(.horizontal, Space.xxl).padding(.vertical, Space.sm).frame(minHeight: 52).frame(maxWidth: .infinity)
            .background {
                switch (enabled, tone) {
                // Блідіша за другорядну кнопку поруч: інакше «Назад» і неактивна «Далі» виглядали однаково.
                case (false, _): buttonShape.fill(Palette.brandContainer.opacity(0.55))
                case (true, .some(let tone)): buttonShape.fill(tone)
                case (true, .none): buttonShape.fill(brandGradient)
                }
            }
        }
        .buttonStyle(PressableStyle())
        .disabled(!enabled || loading)
    }
}

struct SecondaryButton: View {
    let title: String
    var glyph: PoruchGlyph?
    /// SF Symbol лише для чужих знаків, яких у наборі бути не може (логотип Apple).
    var symbol: String?
    var tone: Color?
    var enabled: Bool = true
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            HStack(spacing: Space.sm) {
                if let glyph { PoruchIcon(glyph: glyph, size: 18) }
                else if let symbol { Image(systemName: symbol).font(.system(size: 15, weight: .semibold)) }
                Text(title).font(PoruchFont.button).lineLimit(2).multilineTextAlignment(.center)
            }
            .foregroundStyle(enabled ? tone ?? Palette.ink : Palette.inkTertiary)
            .padding(.horizontal, Space.xxl).padding(.vertical, Space.sm).frame(minHeight: 52).frame(maxWidth: .infinity)
            .background(Palette.brandContainer, in: buttonShape)
        }
        .buttonStyle(PressableStyle())
        .disabled(!enabled)
    }
}
