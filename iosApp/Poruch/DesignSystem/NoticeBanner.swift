import SwiftUI
import Shared

/// Notices land under the status bar, not over the tab bar: the eye is already at the top after a
/// tap, and the bottom edge belongs to navigation. Tone carries the meaning — a red wash for a
/// failure, green for a success — so the two never read the same at a glance.
struct NoticeBanner: View {
    let text: String
    let error: Bool
    let dismiss: () -> Void
    var body: some View {
        Button(action: dismiss) {
            HStack(spacing: Space.md) {
                Image(systemName: error ? "exclamationmark.circle" : "checkmark.circle")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(error ? Palette.danger : Palette.success)
                    .frame(width: 36, height: 36)
                    .background(error ? Palette.dangerContainer : Palette.successContainer,
                                in: RoundedRectangle(cornerRadius: Corner.xs, style: .continuous))
                Text(text).font(PoruchFont.bodyText).foregroundStyle(Palette.ink)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: "xmark").font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Palette.inkTertiary)
            }
            .padding(Space.md)
            .cardSurface(radius: Corner.md, elevation: 12)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(text)
        .accessibilityHint("Торкніться, щоб закрити")
    }
}

/// What the banner needs, in a value SwiftUI can compare. The shared `AppNotice` is a protocol
/// existential, which cannot be `Equatable`, and both `animation(value:)` and `task(id:)` require it.
struct Notice: Equatable {
    let text: String
    let isError: Bool
}

extension AppNotice {
    var presented: Notice { Notice(text: text, isError: isError) }
}

/// Hosts the notice above any screen: it owns the hold-and-fade so each screen does not repeat it.
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
            .animation(reduceMotion ? nil : .spring(response: 0.34, dampingFraction: 0.9), value: notice)
            .task(id: notice) {
                guard let notice else { return }
                shown = notice
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

/// Long enough to read; errors linger because they usually ask for a decision.
private let infoHold: TimeInterval = 3
private let errorHold: TimeInterval = 5
