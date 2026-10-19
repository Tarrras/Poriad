import SwiftUI
import Shared
import Lottie
import AmplitudeSessionReplay

// ---- Структура

/// Заголовок секції читабельного розміру, як написано. Капітель лишається там, де несе дані.
struct SectionHeader: View {
    let title: String
    var actionLabel: String?
    var action: (() -> Void)?
    var body: some View {
        // Заголовок і дія не влазять в один рядок (великий шрифт) — дія стає під заголовком, а не стискає обох у два вузькі стовпці.
        ViewThatFits(in: .horizontal) {
            HStack {
                heading
                Spacer(minLength: Space.sm)
                actionButton(stacked: false)
            }
            VStack(alignment: .leading, spacing: Space.xs) {
                heading
                actionButton(stacked: true)
            }
        }
    }

    private var heading: some View {
        Text(title).font(PoruchFont.brandTitle2).kerning(-0.2).foregroundStyle(Palette.ink).accessibilityAddTraits(.isHeader)
    }

    /// Праворуч дію впізнають за місцем, як «Усі 246»; під заголовком вона читалась би як підзаголовок, тож бере шеврон.
    @ViewBuilder private func actionButton(stacked: Bool) -> some View {
        if let actionLabel, let action {
            Button(action: action) {
                HStack(spacing: Space.xs) {
                    Text(actionLabel)
                    if stacked { PoruchIcon(glyph: PoruchIcons.chevronRight, size: 13) }
                }
            }
            .font(PoruchFont.label).foregroundStyle(Palette.ink)
        }
    }
}

struct PageHeader<Trailing: View>: View {
    let title: String
    var back: (() -> Void)?
    @ViewBuilder var trailing: Trailing
    var body: some View {
        HStack(spacing: Space.md) {
            if let back {
                Button(action: back) {
                    PoruchIcon(glyph: PoruchIcons.chevronLeft, size: 19).foregroundStyle(Palette.ink)
                        .frame(width: 40, height: 40).background(Palette.surface, in: Circle()).tapTarget()
                }.buttonStyle(PressableStyle()).accessibilityLabel(Copy.back)
            }
            Text(title).font(PoruchFont.brandTitle1).kerning(-0.4).foregroundStyle(Palette.ink)
            Spacer(minLength: 0)
            trailing
        }.padding(.horizontal, Space.page).padding(.vertical, Space.md)
    }
}

extension PageHeader where Trailing == EmptyView {
    init(title: String, back: (() -> Void)? = nil) { self.init(title: title, back: back) { EmptyView() } }
}

/// Фірмова Lottie-анімація з Assets: `<name>Light` або `<name>Dark` за темою. Малюнки — tools/generate_lottie.py.
struct BrandAnimation: View {
    let name: String
    var loop = true
    var onFinish: (() -> Void)?
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        LottieView(animation: .asset(name + (scheme == .dark ? "Dark" : "Light")))
            .playing(loopMode: loop ? .loop : .playOnce)
            .animationDidFinish { _ in onFinish?() }
    }
}

/// Лоадер екрана чи секції: шпилька з іконки підстрибує. Кнопки й дрібні підвантаження лишаються з системним.
struct PoruchLoader: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        if reduceMotion { ProgressView() } else { BrandAnimation(name: "Loader").frame(width: 56, height: 56) }
    }
}

struct EmptyState: View {
    let glyph: PoruchGlyph
    let title: String
    let message: String
    var compact: Bool = false
    var actionLabel: String?
    var action: (() -> Void)?
    var body: some View {
        VStack(spacing: compact ? Space.sm : Space.md) {
            BlankTicket(glyph: glyph, compact: compact).padding(.bottom, compact ? 0 : Space.sm)
            Text(title).font(compact ? PoruchFont.brandTitle3 : PoruchFont.brandTitle2).foregroundStyle(Palette.ink).multilineTextAlignment(.center)
            Text(message).font(PoruchFont.subhead).foregroundStyle(Palette.inkSecondary).multilineTextAlignment(.center)
            if let actionLabel, let action {
                PrimaryButton(title: actionLabel, action: action).fixedSize(horizontal: true, vertical: false).padding(.top, Space.sm)
            }
        }.padding(compact ? Space.md : Space.xxl).frame(maxWidth: .infinity)
    }
}

/// Порожній квиток над порожнім станом: пунктирний контур, два незадруковані рядки й гліф на сірому корінці.
private struct BlankTicket: View {
    let glyph: PoruchGlyph
    var compact = false
    var body: some View {
        Ticket(
            stubColor: Palette.surfaceMuted, stubLength: compact ? 44 : 56, radius: Corner.sm,
            outline: (Palette.inkTertiary.opacity(0.6), StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
        ) {
            VStack(alignment: .leading, spacing: 6) {
                Capsule().fill(Palette.hairline).frame(width: compact ? 48 : 72, height: 6)
                Capsule().fill(Palette.hairline).frame(width: compact ? 32 : 44, height: 6)
            }
            .padding(.horizontal, Space.md)
            .frame(maxWidth: .infinity, minHeight: compact ? 52 : 72, alignment: .leading)
        } stub: {
            PoruchIcon(glyph: glyph, size: compact ? 18 : 22).foregroundStyle(Palette.inkSecondary)
        }
        .frame(width: compact ? 132 : 184)
        .decorative()
    }
}

struct BannerCard: View {
    let title: String
    /// Без підпису банер тонкий: гліф, один рядок і стрілка.
    var subtitle: String?
    var glyph: PoruchGlyph = PoruchIcons.sparkle
    let action: () -> Void
    private var slim: Bool { subtitle == nil }
    var body: some View {
        Button(action: action) {
            HStack(spacing: Space.md) {
                PoruchIcon(glyph: glyph, size: 20).foregroundStyle(Palette.ink)
                    .frame(width: slim ? 36 : 44, height: slim ? 36 : 44)
                    .background(Palette.surfaceMuted, in: RoundedRectangle(cornerRadius: Corner.xs, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(PoruchFont.cardName).foregroundStyle(Palette.ink).multilineTextAlignment(.leading)
                    if let subtitle {
                        Text(subtitle).font(PoruchFont.caption).foregroundStyle(Palette.inkSecondary).multilineTextAlignment(.leading)
                    }
                }
                Spacer(minLength: 0)
                PoruchIcon(glyph: PoruchIcons.arrowRight, size: 16).foregroundStyle(Palette.onBrand)
                    .frame(width: slim ? 28 : 32, height: slim ? 28 : 32).background(Palette.brand, in: Circle())
            }
            .padding(.horizontal, Space.lg).padding(.vertical, slim ? Space.md : Space.lg)
            .cardSurface()
        }.buttonStyle(PressableStyle())
    }
}

/// Фото людини або перша літера імені, поки фото нема чи воно ще їде.
struct Avatar: View {
    let name: String
    let url: String?
    var size: CGFloat = 32
    var body: some View {
        ZStack {
            Circle().fill(Palette.surfaceMuted)
            Text(name.trimmingCharacters(in: .whitespaces).prefix(1).uppercased())
                .font(size >= 56 ? PoruchFont.title1 : PoruchFont.label).foregroundStyle(Palette.inkSecondary)
            if let url, let source = URL(string: url), source.scheme == "https" {
                // Той самий кеш, що в картках: `AsyncImage` нічого не пам'ятає.
                CachedImage(url: source, maxDimension: size).clipShape(Circle())
            }
        }
        .frame(width: size, height: size)
        // Обличчя людей не йдуть у Session Replay: маска `conservative` ховає лише текст.
        .amp_setBlocked(true)
    }
}

/// Аватари внапуск.
struct AvatarStack: View {
    let attendees: [Attendee]
    var total: Int
    var size: CGFloat = 32
    private var shown: [Attendee] { Array(attendees.prefix(5)) }
    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(shown.enumerated()), id: \.element.userId) { index, attendee in
                Avatar(name: attendee.name, url: attendee.avatarUrl, size: size)
                .overlay(Circle().strokeBorder(Palette.surface, lineWidth: 2))
                .offset(x: CGFloat(-index * 10))
                .zIndex(Double(shown.count - index))
            }
            if total > shown.count {
                Text("+\(total - shown.count)").font(PoruchFont.label).foregroundStyle(Palette.inkSecondary)
                    .offset(x: CGFloat(-shown.count * 10 + 4))
            }
        }.accessibilityElement(children: .ignore).accessibilityLabel(Copy.a11y_attendees_count("\(total)"))
    }
}

struct MetaLine: View {
    let glyph: PoruchGlyph
    let text: String
    var tone: Color?
    var body: some View {
        HStack(spacing: Space.sm) {
            PoruchIcon(glyph: glyph, size: 15).foregroundStyle(tone ?? Palette.inkTertiary).frame(width: 15)
            Text(text).font(PoruchFont.caption).foregroundStyle(tone ?? Palette.inkSecondary).lineLimit(1)
        }
    }
}

struct InfoRow: View {
    let glyph: PoruchGlyph
    let label: String
    let value: String
    var body: some View {
        HStack(alignment: .top, spacing: Space.md) {
            PoruchIcon(glyph: glyph, size: 18).foregroundStyle(Palette.inkSecondary)
                .frame(width: 34, height: 34)
                .background(Palette.surfaceMuted, in: RoundedRectangle(cornerRadius: Corner.xs, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(label.uppercased()).font(PoruchFont.overline).kerning(1.0).foregroundStyle(Palette.inkTertiary)
                Text(value).font(PoruchFont.bodyText).foregroundStyle(Palette.ink).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }.accessibilityElement(children: .combine)
    }
}
