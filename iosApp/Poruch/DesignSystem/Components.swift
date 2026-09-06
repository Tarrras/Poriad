import SwiftUI
import Shared

// ---------------------------------------------------------------- search & chips

struct SearchField: View {
    @Binding var text: String
    var placeholder: String
    var activeFilters: Int = 0
    var onFilters: (() -> Void)?
    var body: some View {
        HStack(spacing: Space.sm) {
            HStack(spacing: Space.md) {
                PoruchIcon(glyph: PoruchIcons.search, size: 18).foregroundStyle(Palette.inkSecondary)
                TextField("", text: $text, prompt: Text(placeholder).foregroundStyle(Palette.inkTertiary))
                    .font(PoruchFont.bodyText).foregroundStyle(Palette.ink).tint(Palette.ink)
                    .submitLabel(.search).accessibilityLabel("Пошук подій")
                if !text.isEmpty {
                    Button { text = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(Palette.inkTertiary) }
                        .accessibilityLabel("Очистити пошук")
                }
            }
            .padding(.horizontal, Space.lg).frame(height: 48)
            .background(Palette.surface, in: Capsule())
            .overlay(Capsule().strokeBorder(Palette.hairline, lineWidth: 1))
            if let onFilters {
                IconPill(symbol: "slider.horizontal.3", label: "Фільтри", action: onFilters)
                    .overlay(alignment: .topTrailing) {
                        if activeFilters > 0 {
                            Text("\(activeFilters)").font(PoruchFont.overline).foregroundStyle(Palette.onBrand)
                                .frame(width: 18, height: 18).background(Palette.accent, in: Circle()).offset(x: 2, y: -2)
                        }
                    }
            }
        }
    }
}

struct IconPill: View {
    let symbol: String
    let label: String
    var selected: Bool = false
    var size: CGFloat = 48
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 17, weight: .medium))
                .foregroundStyle(selected ? Palette.onBrand : Palette.ink)
                .frame(width: size, height: size)
                .background(selected ? Palette.brand : Palette.surface, in: Circle())
                .overlay(Circle().strokeBorder(Palette.hairline, lineWidth: selected ? 0 : 1))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}

/// The smallest possible carrier of category colour, straight from Corner.
struct CategoryDot: View {
    let category: String
    var size: CGFloat = 8
    var body: some View { Circle().fill(categoryColor(category)).frame(width: size, height: size) }
}

/// Chip: lowercase label on a white pill; selection fills it with ink, the way Corner marks state.
struct Chip: View {
    let label: String
    var symbol: String?
    var dot: String?
    let selected: Bool
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            HStack(spacing: Space.sm) {
                if let dot {
                    Circle().fill(selected ? Palette.onBrand : categoryColor(dot)).frame(width: 8, height: 8)
                } else if let symbol {
                    Image(systemName: symbol).font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(selected ? Palette.onBrand : Palette.inkSecondary)
                }
                Text(label).font(PoruchFont.label)
            }
            .foregroundStyle(selected ? Palette.onBrand : Palette.ink)
            .padding(.horizontal, Space.lg).frame(height: 38)
            .background(selected ? Palette.brand : Palette.surface, in: Capsule())
            .overlay(Capsule().strokeBorder(Palette.hairline, lineWidth: selected ? 0 : 1))
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// A rounded square washed in the category pastel, as Corner sets its rating tiles.
struct CategoryTile: View {
    let category: String
    let selected: Bool
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            VStack(spacing: Space.sm) {
                PoruchIcon(glyph: categoryGlyph(category), size: 24)
                    .foregroundStyle(categoryColor(category))
                    .frame(width: 60, height: 60)
                    .background(categoryWash(category), in: RoundedRectangle(cornerRadius: Corner.sm, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: Corner.sm, style: .continuous)
                            .strokeBorder(selected ? Palette.ink : Palette.hairline, lineWidth: selected ? 2 : 1)
                    )
                Text(categoryName(category)).font(PoruchFont.label).lineLimit(1)
                    .foregroundStyle(selected ? Palette.ink : Palette.inkSecondary)
            }.frame(width: 76)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(categoryName(category))
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

// ---------------------------------------------------------------- badges & buttons

enum BadgeTone { case brand, success, accent, danger, neutral }

struct StatusBadge: View {
    let text: String
    var tone: BadgeTone = .neutral
    var symbol: String?
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
            if let symbol { Image(systemName: symbol).font(.system(size: 10, weight: .bold)) }
            Text(text.uppercased()).font(PoruchFont.overline).kerning(1.2)
        }
        .foregroundStyle(colors.1)
        .padding(.horizontal, Space.md).padding(.vertical, 5)
        .background(colors.0, in: Capsule())
    }
}

struct PrimaryButton: View {
    let title: String
    var symbol: String?
    var tone: Color?
    var loading: Bool = false
    var enabled: Bool = true
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            HStack(spacing: Space.sm) {
                if loading { ProgressView().tint(Palette.onBrand) }
                else if let symbol { Image(systemName: symbol).font(.system(size: 15, weight: .semibold)) }
                Text(title).font(PoruchFont.button).lineLimit(1)
            }
            .foregroundStyle(enabled ? Palette.onBrand : Palette.inkTertiary)
            .padding(.horizontal, Space.xxl).frame(height: 52).frame(maxWidth: .infinity)
            .background(enabled ? tone ?? Palette.brand : Palette.surfaceMuted, in: Capsule())
        }
        .buttonStyle(.plain)
        .disabled(!enabled || loading)
    }
}

struct SecondaryButton: View {
    let title: String
    var symbol: String?
    var tone: Color?
    var enabled: Bool = true
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            HStack(spacing: Space.sm) {
                if let symbol { Image(systemName: symbol).font(.system(size: 15, weight: .semibold)) }
                Text(title).font(PoruchFont.button).lineLimit(1)
            }
            .foregroundStyle(enabled ? tone ?? Palette.ink : Palette.inkTertiary)
            .padding(.horizontal, Space.xxl).frame(height: 52).frame(maxWidth: .infinity)
            .background(Palette.surfaceMuted, in: Capsule())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
    }
}

// ---------------------------------------------------------------- structure

/// Section headers are small, uppercase and letterspaced — Corner's editorial signature.
struct SectionHeader: View {
    let title: String
    var actionLabel: String?
    var action: (() -> Void)?
    var body: some View {
        HStack {
            Text(title.uppercased()).font(PoruchFont.overline).kerning(1.2).foregroundStyle(Palette.inkSecondary)
            Spacer(minLength: Space.sm)
            if let actionLabel, let action {
                Button(actionLabel, action: action).font(PoruchFont.label).foregroundStyle(Palette.ink)
            }
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
                    Image(systemName: "chevron.left").font(.system(size: 16, weight: .semibold)).foregroundStyle(Palette.ink)
                        .frame(width: 40, height: 40).background(Palette.surface, in: Circle())
                        .overlay(Circle().strokeBorder(Palette.hairline, lineWidth: 1))
                }.accessibilityLabel("Назад")
            }
            Text(title).font(PoruchFont.title1).foregroundStyle(Palette.ink)
            Spacer(minLength: 0)
            trailing
        }.padding(.horizontal, Space.page).padding(.vertical, Space.md)
    }
}

extension PageHeader where Trailing == EmptyView {
    init(title: String, back: (() -> Void)? = nil) { self.init(title: title, back: back) { EmptyView() } }
}

struct EmptyState: View {
    let symbol: String
    let title: String
    let message: String
    var compact: Bool = false
    var actionLabel: String?
    var action: (() -> Void)?
    var body: some View {
        VStack(spacing: compact ? Space.sm : Space.md) {
            Image(systemName: symbol).font(.system(size: compact ? 20 : 26, weight: .medium)).foregroundStyle(Palette.inkSecondary)
                .frame(width: compact ? 52 : 64, height: compact ? 52 : 64)
                .background(Palette.surfaceMuted, in: RoundedRectangle(cornerRadius: Corner.md, style: .continuous))
            Text(title).font(compact ? PoruchFont.title3 : PoruchFont.title2).foregroundStyle(Palette.ink).multilineTextAlignment(.center)
            Text(message).font(PoruchFont.subhead).foregroundStyle(Palette.inkSecondary).multilineTextAlignment(.center)
            if let actionLabel, let action {
                PrimaryButton(title: actionLabel, action: action).fixedSize(horizontal: true, vertical: false).padding(.top, Space.sm)
            }
        }.padding(compact ? Space.md : Space.xxl).frame(maxWidth: .infinity)
    }
}

struct BannerCard: View {
    let title: String
    let subtitle: String
    var symbol: String = "sparkles"
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            HStack(spacing: Space.md) {
                Image(systemName: symbol).font(.system(size: 17, weight: .medium)).foregroundStyle(Palette.ink)
                    .frame(width: 44, height: 44)
                    .background(Palette.brandContainer, in: RoundedRectangle(cornerRadius: Corner.xs, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(PoruchFont.cardName).foregroundStyle(Palette.ink).multilineTextAlignment(.leading)
                    Text(subtitle).font(PoruchFont.caption).foregroundStyle(Palette.inkSecondary).multilineTextAlignment(.leading)
                }
                Spacer(minLength: 0)
                Image(systemName: "arrow.right").font(.system(size: 13, weight: .bold)).foregroundStyle(Palette.onBrand)
                    .frame(width: 32, height: 32).background(Palette.brand, in: Circle())
            }
            .padding(Space.lg)
            .cardSurface()
        }.buttonStyle(.plain)
    }
}

/// Overlapping avatars, the social proof Meetup puts under every event.
struct AvatarStack: View {
    let attendees: [Attendee]
    var total: Int
    var size: CGFloat = 32
    private var shown: [Attendee] { Array(attendees.prefix(5)) }
    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(shown.enumerated()), id: \.element.userId) { index, attendee in
                ZStack {
                    Circle().fill(Palette.surfaceMuted)
                    Text(attendee.name.trimmingCharacters(in: .whitespaces).prefix(1).uppercased())
                        .font(PoruchFont.label).foregroundStyle(Palette.inkSecondary)
                    if let source = attendee.avatarUrl, let url = URL(string: source), url.scheme == "https" {
                        AsyncImage(url: url) { phase in
                            if let image = phase.image { image.resizable().scaledToFill() } else { Color.clear }
                        }.clipShape(Circle())
                    }
                }
                .frame(width: size, height: size)
                .overlay(Circle().strokeBorder(Palette.surface, lineWidth: 2))
                .offset(x: CGFloat(-index * 10))
                .zIndex(Double(shown.count - index))
            }
            if total > shown.count {
                Text("+\(total - shown.count)").font(PoruchFont.label).foregroundStyle(Palette.inkSecondary)
                    .offset(x: CGFloat(-shown.count * 10 + 4))
            }
        }.accessibilityElement(children: .ignore).accessibilityLabel("Учасників: \(total)")
    }
}

struct MetaLine: View {
    let symbol: String
    let text: String
    var tone: Color?
    var body: some View {
        HStack(spacing: Space.sm) {
            Image(systemName: symbol).font(.system(size: 12)).foregroundStyle(tone ?? Palette.inkTertiary).frame(width: 15)
            Text(text).font(PoruchFont.caption).foregroundStyle(tone ?? Palette.inkSecondary).lineLimit(1)
        }
    }
}

struct InfoRow: View {
    let symbol: String
    let label: String
    let value: String
    var body: some View {
        HStack(alignment: .top, spacing: Space.md) {
            Image(systemName: symbol).font(.system(size: 15, weight: .medium)).foregroundStyle(Palette.inkSecondary)
                .frame(width: 34, height: 34)
                .background(Palette.surfaceMuted, in: RoundedRectangle(cornerRadius: Corner.xs, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(label.uppercased()).font(PoruchFont.overline).kerning(1.2).foregroundStyle(Palette.inkTertiary)
                Text(value).font(PoruchFont.bodyText).foregroundStyle(Palette.ink).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }.accessibilityElement(children: .combine)
    }
}

/**
 Field in the Corner idiom: a small uppercase label above the box rather than a floating
 placeholder, so a form reads as a list of named things and every field looks the same.
 */
struct LabelledField<Trailing: View>: View {
    let label: String
    @Binding var text: String
    var placeholder: String = ""
    var hint: String?
    var secure: Bool = false
    /// A description grows with what is typed; every other field stays one line tall.
    var multiline: Bool = false
    @ViewBuilder var trailing: Trailing
    var body: some View {
        VStack(alignment: .leading, spacing: Space.sm) {
            Text(label.uppercased()).font(PoruchFont.overline).kerning(1.2).foregroundStyle(Palette.inkTertiary)
            HStack(spacing: Space.sm) {
                Group {
                    if secure {
                        SecureField("", text: $text, prompt: Text(placeholder).foregroundStyle(Palette.inkTertiary))
                    } else if multiline {
                        TextField("", text: $text, prompt: Text(placeholder).foregroundStyle(Palette.inkTertiary), axis: .vertical)
                            .lineLimit(4...10)
                    } else {
                        TextField("", text: $text, prompt: Text(placeholder).foregroundStyle(Palette.inkTertiary))
                    }
                }
                .font(PoruchFont.bodyText).foregroundStyle(Palette.ink).tint(Palette.ink).textFieldStyle(.plain)
                trailing
            }
            // A trailing control reserves a 44 pt target, so the box is tall enough to hold one
            // without growing past a plain field beside it.
            .padding(.horizontal, Space.lg)
            .padding(.vertical, multiline ? Space.md : 0)
            .frame(minHeight: 56, alignment: multiline ? .top : .center)
            .background(Palette.surface, in: RoundedRectangle(cornerRadius: Corner.sm, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Corner.sm, style: .continuous).strokeBorder(Palette.hairline, lineWidth: 1))
            if let hint {
                Text(hint).font(PoruchFont.caption).foregroundStyle(Palette.inkTertiary)
            }
        }
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

// ---------------------------------------------------------------- event surfaces

struct EventThumbnail: View {
    let event: Event
    var body: some View {
        ZStack {
            categoryWash(event.category)
            PoruchIcon(glyph: categoryGlyph(event.category), size: 24)
                .foregroundStyle(categoryColor(event.category))
            if let source = event.imageUrl, let url = URL(string: source), url.scheme == "https" {
                AsyncImage(url: url) { phase in
                    if let image = phase.image { image.resizable().scaledToFill() } else { Color.clear }
                }
            }
        }.decorative()
    }
}

func eventBadge(_ event: Event, waitlisted: Bool = false) -> (String, BadgeTone, String?)? {
    if event.isCancelled { return ("Скасовано", .danger, nil) }
    if event.joined { return ("Ви йдете", .success, "checkmark") }
    if waitlisted { return ("У черзі", .accent, "hourglass") }
    if event.isFull { return ("Місць немає", .neutral, nil) }
    if eventScarce(event) { return ("Лишилось \(event.seatsLeft)", .accent, nil) }
    return nil
}

/// Category dot plus a lowercase descriptor — the line Corner puts under every place name.
struct EventDescriptor: View {
    let event: Event
    var body: some View {
        HStack(spacing: Space.sm) {
            CategoryDot(category: event.category)
            Text(categoryName(event.category).lowercased() + " · " + (event.address.isEmpty ? event.city : event.address))
                .font(PoruchFont.caption).foregroundStyle(Palette.inkSecondary).lineLimit(1)
        }
    }
}

struct SaveButton: View {
    let saved: Bool
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Image(systemName: saved ? "bookmark.fill" : "bookmark")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(saved ? Palette.ink : Palette.inkSecondary)
                .frame(width: 34, height: 34)
                .background(Palette.surface, in: Circle())
                .overlay(Circle().strokeBorder(Palette.hairline, lineWidth: 1))
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(saved ? "Прибрати зі збережених" : "Зберегти подію")
    }
}

/// Feed card: photo, then the date overline, the name and one descriptor line.
struct EventCard: View {
    let event: Event
    var saved: Bool = false
    var waitlisted: Bool = false
    var onSave: (() -> Void)?
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 0) {
                // Without a photo the placeholder shrinks: an empty 16:9 band would dominate the card.
                EventThumbnail(event: event)
                    .frame(height: event.imageUrl == nil ? 96 : 168).frame(maxWidth: .infinity).clipped()
                    .clipShape(RoundedRectangle(cornerRadius: Corner.sm, style: .continuous))
                    .overlay(alignment: .topLeading) {
                        if let badge = eventBadge(event, waitlisted: waitlisted) {
                            StatusBadge(text: badge.0, tone: badge.1, symbol: badge.2).padding(Space.sm)
                        }
                    }
                    .overlay(alignment: .topTrailing) {
                        if let onSave { SaveButton(saved: saved, action: onSave).padding(Space.sm) }
                    }
                VStack(alignment: .leading, spacing: Space.sm) {
                    Text(eventOverline(event)).font(PoruchFont.overline).kerning(1.2).foregroundStyle(Palette.inkTertiary)
                    Text(event.title.uppercased()).font(PoruchFont.cardName).kerning(0.3).foregroundStyle(Palette.ink)
                        .multilineTextAlignment(.leading).lineLimit(2)
                    EventDescriptor(event: event)
                    MetaLine(symbol: "person.2", text: "\(event.attendeeCount) з \(event.capacity) учасників")
                }.padding(Space.md).frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(Space.sm)
            .cardSurface()
            .opacity(event.isCancelled ? 0.6 : 1)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
    }
}

/// Compact row for lists: square thumbnail, name, descriptor.
struct EventRow: View {
    let event: Event
    var body: some View {
        HStack(spacing: Space.md) {
            EventThumbnail(event: event)
                .frame(width: 60, height: 60)
                .clipShape(RoundedRectangle(cornerRadius: Corner.xs, style: .continuous))
            VStack(alignment: .leading, spacing: Space.xs) {
                Text(eventOverline(event)).font(PoruchFont.overline).kerning(1.2).foregroundStyle(Palette.inkTertiary)
                Text(event.title.uppercased()).font(PoruchFont.cardName).kerning(0.3).foregroundStyle(Palette.ink)
                    .multilineTextAlignment(.leading).lineLimit(2)
                if let badge = eventBadge(event) { StatusBadge(text: badge.0, tone: badge.1, symbol: badge.2) }
                else { EventDescriptor(event: event) }
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right").font(.system(size: 12, weight: .semibold)).foregroundStyle(Palette.inkTertiary)
        }
        .padding(.vertical, Space.md)
        .opacity(event.isCancelled ? 0.6 : 1)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

/// Carousel card above the map: wide enough for the name, short enough to leave the map readable.
struct EventMapCard: View {
    let event: Event
    var focused: Bool = false
    var saved: Bool = false
    var onSave: (() -> Void)?
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            HStack(spacing: Space.md) {
                EventThumbnail(event: event)
                    .frame(width: 84, height: 84)
                    .clipShape(RoundedRectangle(cornerRadius: Corner.xs, style: .continuous))
                VStack(alignment: .leading, spacing: Space.xs) {
                    Text(eventOverline(event)).font(PoruchFont.overline).kerning(1.2).foregroundStyle(Palette.inkTertiary)
                    Text(event.title.uppercased()).font(PoruchFont.cardName).kerning(0.3).foregroundStyle(Palette.ink)
                        .multilineTextAlignment(.leading).lineLimit(2)
                    if let badge = eventBadge(event) { StatusBadge(text: badge.0, tone: badge.1, symbol: badge.2) }
                    else { MetaLine(symbol: "person.2", text: "\(event.attendeeCount) з \(event.capacity)") }
                }
                Spacer(minLength: 0)
                if let onSave { SaveButton(saved: saved, action: onSave) }
            }
            .padding(Space.md)
            .frame(height: 112)
            .cardSurface(radius: Corner.lg, elevation: 10)
            .overlay(
                RoundedRectangle(cornerRadius: Corner.lg, style: .continuous)
                    .strokeBorder(Palette.ink, lineWidth: focused ? 2 : 0)
            )
            .opacity(event.isCancelled ? 0.6 : 1)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(focused ? .isSelected : [])
    }
}

/// Narrow tile for horizontal rails on the home screen.
struct EventTile: View {
    let event: Event
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: Space.sm) {
                EventThumbnail(event: event)
                    .frame(height: 104).frame(maxWidth: .infinity).clipped()
                    .clipShape(RoundedRectangle(cornerRadius: Corner.xs, style: .continuous))
                VStack(alignment: .leading, spacing: Space.xs) {
                    Text(eventOverline(event)).font(PoruchFont.overline).kerning(1.2).foregroundStyle(Palette.inkTertiary)
                    Text(event.title.uppercased()).font(PoruchFont.cardName).kerning(0.3).foregroundStyle(Palette.ink)
                        .multilineTextAlignment(.leading).lineLimit(2, reservesSpace: true)
                    EventDescriptor(event: event)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, Space.sm).padding(.bottom, Space.sm)
            }
            .padding(Space.sm)
            .cardSurface()
            .opacity(event.isCancelled ? 0.6 : 1)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
    }
}

// ---------------------------------------------------------------- navigation

struct TabItem: Identifiable {
    let id: Int
    let label: String
    let glyph: PoruchGlyph
}

/// Floating capsule bar; the active item is inked while the rest stay quiet, as Corner marks tabs.
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
                            // The active tab is inked rather than thickened: the glyphs are one
                            // weight, so swapping stroke widths would make the row jitter.
                            PoruchIcon(glyph: item.glyph, size: 22)
                            Text(item.label).font(PoruchFont.overline).lineLimit(1)
                        }
                        .foregroundStyle(selection == item.id ? Palette.ink : Palette.inkTertiary)
                        .frame(maxWidth: .infinity).frame(height: 42)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(item.label)
                    .accessibilityAddTraits(selection == item.id ? .isSelected : [])
                }
            }
            .padding(.horizontal, Space.xs).padding(.vertical, Space.sm)
            .cardSurface(radius: 32, elevation: 12)
            trailing
        }.padding(.horizontal, Space.lg)
    }
}

struct CreateButton: View {
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            PoruchIcon(glyph: PoruchIcons.plus, size: 24).foregroundStyle(Palette.onBrand)
                .frame(width: 56, height: 56).background(Palette.brand, in: Circle())
                .shadow(color: .black.opacity(0.18), radius: 12, y: 5)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Створити подію")
    }
}
