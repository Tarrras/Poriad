import SwiftUI
import Shared

// ---- Навігація

struct TabItem: Identifiable {
    let id: Int
    let label: String
    let glyph: PoruchGlyph
    /// Скільки справ чекає: 0 — без бейджа.
    var badge: Int = 0
    /// Є нове, але не справа, яку треба рахувати: крапка замість числа.
    var dot = false
    /// Підказка першого знайомства, що вказує на цей пункт.
    var tip: CoachTip?
}

/// Таббар плаває поверх застосунку, тож екран із власною нижньою панеллю (деталі) має сам
/// попросити його сховати. Preference, бо треба перетнути `NavigationStack`.

/// Перемкнути на вкладку «Мапа». В оточенні, бо вкладками керує корінь, а просить екран зі стека.
private struct OpenMapKey: EnvironmentKey {
    static let defaultValue: () -> Void = {}
}

extension EnvironmentValues {
    var openMap: () -> Void {
        get { self[OpenMapKey.self] }
        set { self[OpenMapKey.self] = newValue }
    }
}

struct HidesTabBarKey: PreferenceKey {
    static let defaultValue = false
    static func reduce(value: inout Bool, nextValue: () -> Bool) { value = value || nextValue() }
}

extension View {
    /// Екран, над яким таббар не показуємо.
    func hidesTabBar() -> some View { preference(key: HidesTabBarKey.self, value: true) }
}

/// Плаваючий скляний таббар; під активним пунктом тонова пігулка.
struct PoruchTabBar<Trailing: View>: View {
    let items: [TabItem]
    @Binding var selection: Int
    @ViewBuilder var trailing: Trailing
    var body: some View {
        HStack(spacing: Space.sm) {
            HStack(spacing: 0) {
                ForEach(items) { item in
                    Button { selection = item.id } label: {
                        VStack(spacing: 3) {
                            // Активна вкладка заливається, а не товщає: інакше рядок смикається.
                            PoruchIcon(glyph: item.glyph, size: 22)
                                .overlay(alignment: .topTrailing) {
                                    // Бейдж поверх кута гліфа: число справ, не повідомлень.
                                    if item.badge > 0 {
                                        CountBadge(count: item.badge).offset(x: 10, y: -6)
                                    } else if item.dot {
                                        Circle().fill(Palette.accent).frame(width: 8, height: 8).offset(x: 4, y: -2)
                                    }
                                }
                            Text(item.label).font(PoruchFont.overline).lineLimit(1)
                        }
                        .foregroundStyle(selection == item.id ? Palette.ink : Palette.inkTertiary)
                        .frame(maxWidth: .infinity).frame(height: 44)
                        .background {
                            // Тонова пігулка під активним гліфом: стан видно й на відстані руки. Від кольору
                            // тексту, а не brandContainer: той на склі (≈#F2F2F6) майже зливався з тлом.
                            if selection == item.id { Capsule().fill(Palette.ink.opacity(0.1)) }
                        }
                    }
                    .buttonStyle(PressableStyle(pressedScale: 0.94))
                    .accessibilityLabel(
                        item.badge > 0 ? Copy.a11y_unread_chats("\(item.label)", "\(item.badge)")
                            : item.dot ? Copy.a11y_tab_new_follows("\(item.label)") : item.label
                    )
                    .accessibilityAddTraits(selection == item.id ? .isSelected : [])
                    // Підписи не ростуть вище Large, тож із великим текстом довге натискання показує їх збільшено, як у системному таббарі.
                    .accessibilityShowsLargeContentViewer {
                        PoruchIcon(glyph: item.glyph, size: 22)
                        Text(item.label)
                    }
                    .coachTarget(item.tip)
                }
            }
            // Група вкладок для VoiceOver: «вкладка, 1 з 4», як у системного таббара.
            .accessibilityElement(children: .contain)
            .accessibilityAddTraits(.isTabBar)
            .padding(.horizontal, Space.xs).padding(.vertical, Space.sm)
            .glassSurface(radius: 32)
            trailing
        }.padding(.horizontal, Space.lg)
    }
}

struct CreateButton: View {
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            PoruchIcon(glyph: PoruchIcons.plus, size: 24).foregroundStyle(Palette.onBrand)
                .frame(width: 56, height: 56).background(brandGradient, in: Circle())
                .lifted(Elevation.overlay)
        }
        .buttonStyle(PressableStyle(pressedScale: 0.94))
        .accessibilityLabel(Copy.create)
    }
}
