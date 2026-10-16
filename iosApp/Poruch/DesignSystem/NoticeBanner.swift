import SwiftUI
import Shared

/// Банер під статус-баром, а не над таббаром. Тон несе зміст: червоний для помилки, зелений для
/// успіху. Дотиків не забирає, крім власного хрестика: інакше він накривав поле пошуку під собою.
struct NoticeBanner: View {
    let text: String
    let error: Bool
    let dismiss: () -> Void
    var body: some View {
        content
            .allowsHitTesting(false)
            .overlay(alignment: .trailing) {
                Button(action: dismiss) {
                    PoruchIcon(glyph: PoruchIcons.close, size: 16)
                        .foregroundStyle(Palette.inkTertiary)
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(PressableStyle())
                .accessibilityLabel(Copy.a11y_close_notice)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel(text)
    }

    private var content: some View {
        HStack(spacing: Space.md) {
            PoruchIcon(glyph: error ? PoruchIcons.alert : PoruchIcons.checkCircle, size: 20)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(error ? Palette.danger : Palette.success)
                .frame(width: 36, height: 36)
                .background(
                    toneGradient(error ? Palette.dangerContainer : Palette.successContainer,
                                 error ? Palette.danger : Palette.success),
                    in: RoundedRectangle(cornerRadius: Corner.xs, style: .continuous)
                )
            Text(text).font(PoruchFont.bodyText).foregroundStyle(Palette.ink)
                .frame(maxWidth: .infinity, alignment: .leading)
            // Місце під хрестик-накладку, щоб текст не заходив під нього.
            Color.clear.frame(width: 24, height: 1)
        }
        .padding(Space.md)
        .cardSurface(radius: Corner.md, elevation: Elevation.overlay)
    }
}

/// Дані банера як `Equatable`-значення: спільний `AppNotice` — протокол, а `animation(value:)` і `task(id:)` потребують Equatable.
struct Notice: Equatable {
    let text: String
    let isError: Bool
}

extension AppNotice {
    var presented: Notice { Notice(text: text, isError: isError) }
}

/// Показує банер над будь-яким екраном і сам тримає затримку й згасання.
struct NoticeOverlay: ViewModifier {
    let notice: Notice?
    let dismiss: () -> Void
    @State private var shown: Notice?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    func body(content: Content) -> some View {
        content
            .overlay(alignment: .top) {
                if notice != nil, let shown {
                    NoticeBanner(text: shown.text, error: shown.isError, dismiss: dismiss)
                        .padding(.horizontal, Space.page)
                        .transition(reduceMotion ? .opacity : .move(edge: .top).combined(with: .opacity))
                }
            }
            .motion(Motion.spring, value: notice)
            .task(id: notice) {
                guard let notice else { return }
                shown = notice
                // Банер згори VoiceOver не бачить, поки до нього не дійдуть: відмову чи успіх кажемо вголос.
                AccessibilityNotification.Announcement(notice.text).post()
                try? await Task.sleep(for: .seconds(notice.isError ? errorHold : infoHold))
                dismiss()
            }
    }
}

extension View {
    func notice(_ notice: Notice?, dismiss: @escaping () -> Void) -> some View {
        modifier(NoticeOverlay(notice: notice, dismiss: dismiss))
    }
}

/// Досить, щоб прочитати; помилки висять довше, бо просять рішення.
private let infoHold: TimeInterval = 3
private let errorHold: TimeInterval = 5
