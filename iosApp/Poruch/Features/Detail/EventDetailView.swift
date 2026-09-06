import SwiftUI
import PhotosUI
import EventKit
import Shared

struct EventDetailView: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @StateObject private var actions: EventActionsModel
    @State private var editing = false
    @State private var auth = false
    @State private var cancelling = false
    @State private var photo: PhotosPickerItem?

    init(app: PoruchApp) {
        _actions = StateObject(wrappedValue: EventActionsModel(app: app))
    }

    var body: some View {
        let view = EventDetailPresentation(state: model.state)
        Group {
            if let event = view.event {
                detail(event, view)
            } else {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity).background(Palette.canvas)
            }
        }
        .task(id: photo) { if let event = view.event { await actions.upload(photo, to: event) } }
        .toolbar(.hidden, for: .navigationBar)
        .sheet(isPresented: $auth) { NavigationStack { AuthView() } }
    }

    @ViewBuilder
    private func detail(_ event: Event, _ view: EventDetailPresentation) -> some View {
        ZStack(alignment: .bottom) {
            ScrollView {
                VStack(alignment: .leading, spacing: Space.xl) {
                    hero(event, view)
                    VStack(alignment: .leading, spacing: Space.lg) {
                        headline(event, view)
                        facts(event)
                        if !view.attendees.isEmpty { roster(event, view) }
                        externalActions(event, view)
                        venue(event)
                        SectionHeader(title: "Опис")
                        Text(event.description_).font(PoruchFont.bodyText).foregroundStyle(Palette.inkSecondary).lineSpacing(5)
                        if view.organizer && !view.cancelled { organizerActions(view) }
                    }.padding(.horizontal, Space.page)
                }.padding(.bottom, 140)
            }.ignoresSafeArea(edges: .top)
            stickyBar(event, view)
        }
        .background(Palette.canvas)
        .sheet(isPresented: $editing) { EventEditor(event: event, app: model.app, home: model.state) }
        .sheet(item: Binding(
            get: { actions.calendarStore.map(CalendarSession.init) },
            set: { if $0 == nil { actions.calendarStore = nil } }
        )) { session in
            CalendarEditor(event: event, store: session.store)
        }
        .alert("Календар", isPresented: $actions.calendarDenied) {
            Button("Добре") { actions.calendarDenied = false }
        } message: { Text("Дозвольте доступ до календаря в налаштуваннях iOS.") }
        .confirmationDialog("Скасувати цю подію? Учасники бачитимуть її скасованою.", isPresented: $cancelling, titleVisibility: .visible) {
            Button("Скасувати подію", role: .destructive) { actions.cancel(event) }
        }
    }

    private func hero(_ event: Event, _ view: EventDetailPresentation) -> some View {
        EventThumbnail(event: event)
            .frame(height: 300).frame(maxWidth: .infinity).clipped()
            .overlay(alignment: .bottom) {
                LinearGradient(colors: [.clear, Palette.canvas], startPoint: .top, endPoint: .bottom).frame(height: 120)
            }
            .overlay(alignment: .top) {
                HStack(spacing: Space.sm) {
                    ScrimButton(symbol: "chevron.left", label: "Назад") { dismiss() }
                    Spacer()
                    ShareLink(item: SystemActions.shareText(for: event)) { ScrimGlyph(symbol: "square.and.arrow.up") }
                        .accessibilityLabel("Поділитися")
                    ScrimButton(
                        symbol: view.saved ? "bookmark.fill" : "bookmark",
                        label: view.saved ? "Прибрати зі збережених" : "Зберегти подію"
                    ) { if !actions.toggleSaved(event, signedIn: view.signedIn) { auth = true } }
                }.padding(Space.page).padding(.top, Space.xxl)
            }
    }

    private func headline(_ event: Event, _ view: EventDetailPresentation) -> some View {
        VStack(alignment: .leading, spacing: Space.lg) {
            HStack(spacing: Space.sm) {
                StatusBadge(text: categoryName(event.category), tone: .brand)
                if view.cancelled { StatusBadge(text: "Скасовано", tone: .danger) }
                else if view.organizer { StatusBadge(text: "Ви організатор", tone: .neutral) }
                else if event.joined { StatusBadge(text: "Ви йдете", tone: .success, symbol: "checkmark") }
                else if view.waitlisted { StatusBadge(text: "У черзі", tone: .accent, symbol: "hourglass") }
                else if eventScarce(event) { StatusBadge(text: "Лишилось \(event.seatsLeft) місць", tone: .accent) }
            }
            Text(event.title).font(PoruchFont.display).foregroundStyle(Palette.ink)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func facts(_ event: Event) -> some View {
        VStack(spacing: Space.lg) {
            InfoRow(symbol: "calendar", label: "КОЛИ", value: eventDate(event))
            InfoRow(symbol: "mappin.and.ellipse", label: "ДЕ", value: "\(event.city) · \(event.address)")
            InfoRow(symbol: "person.crop.circle", label: "ОРГАНІЗАТОР", value: event.organizerName.isEmpty ? "Організатор" : event.organizerName)
            InfoRow(symbol: "person.2", label: "МІСТКІСТЬ", value: "\(event.attendeeCount) з \(event.capacity) учасників")
        }.padding(Space.lg).cardSurface()
    }

    private func roster(_ event: Event, _ view: EventDetailPresentation) -> some View {
        HStack(spacing: Space.md) {
            AvatarStack(attendees: view.attendees, total: Int(event.attendeeCount))
            VStack(alignment: .leading, spacing: 2) {
                Text("ІДУТЬ").font(PoruchFont.overline).kerning(1.2).foregroundStyle(Palette.inkTertiary)
                Text(view.attendees.map(\.name).joined(separator: ", "))
                    .font(PoruchFont.subhead).foregroundStyle(Palette.ink).lineLimit(1)
            }
            Spacer(minLength: 0)
        }.padding(Space.lg).cardSurface()
    }

    private func externalActions(_ event: Event, _ view: EventDetailPresentation) -> some View {
        HStack(spacing: Space.md) {
            SecondaryButton(title: "У календар", symbol: "calendar.badge.plus", enabled: !view.cancelled) {
                actions.requestCalendar()
            }
            SecondaryButton(title: "Маршрут", symbol: "arrow.triangle.turn.up.right") {
                SystemActions.openInMaps(event)
            }
        }
    }

    private func venue(_ event: Event) -> some View {
        VStack(alignment: .leading, spacing: Space.sm) {
            SectionHeader(title: "Місце зустрічі")
            EventMap(
                events: [event], latitude: event.latitude, longitude: event.longitude,
                selectedID: event.id, interactive: false, selected: { _ in }, moved: { _ in }
            )
            .frame(height: 180)
            .clipShape(RoundedRectangle(cornerRadius: Corner.sm, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Corner.sm, style: .continuous).strokeBorder(Palette.hairline, lineWidth: 1)
            )
            .allowsHitTesting(false)
        }
    }

    private func organizerActions(_ view: EventDetailPresentation) -> some View {
        VStack(alignment: .leading, spacing: Space.md) {
            Divider().overlay(Palette.hairline)
            PhotosPicker(selection: $photo, matching: .images) {
                Label("Додати або замінити фото", systemImage: "camera")
                    .font(.system(size: 15, weight: .semibold)).foregroundStyle(Palette.ink)
                    .frame(maxWidth: .infinity).frame(height: 52)
                    .background(Palette.surface, in: Capsule())
                    .overlay(Capsule().strokeBorder(Palette.hairline, lineWidth: 1))
            }.disabled(view.mutating)
            if let error = actions.photoError {
                Text(error).font(PoruchFont.caption).foregroundStyle(Palette.danger)
            }
            HStack(spacing: Space.md) {
                SecondaryButton(title: "Редагувати", symbol: "pencil") { editing = true }
                SecondaryButton(title: "Скасувати", symbol: "xmark", tone: Palette.danger) { cancelling = true }
            }
        }
    }

    private func stickyBar(_ event: Event, _ view: EventDetailPresentation) -> some View {
        HStack(spacing: Space.md) {
            VStack(alignment: .leading, spacing: 2) {
                Text(eventOverline(event)).font(PoruchFont.overline).kerning(1.2)
                    .foregroundStyle(Palette.inkTertiary).lineLimit(1)
                Text(view.seatsSummary).font(PoruchFont.subhead)
                    .foregroundStyle(view.cancelled ? Palette.danger : Palette.inkSecondary).lineLimit(2)
            }
            Spacer(minLength: 0)
            PrimaryButton(
                title: view.action.title,
                tone: view.action == .leave ? Palette.success : view.action == .leaveWaitlist ? Palette.accent : nil,
                loading: view.mutating,
                enabled: view.action.isEnabled && !view.mutating
            ) {
                if !actions.perform(view.action, on: event, signedIn: view.signedIn) { auth = true }
            }.fixedSize(horizontal: true, vertical: false)
        }
        .padding(.horizontal, Space.page).padding(.vertical, Space.md)
        .background(Palette.surface.ignoresSafeArea(edges: .bottom))
        .overlay(alignment: .top) { Rectangle().fill(Palette.hairline).frame(height: 1) }
    }
}

/// `sheet(item:)` needs an identity; an `EKEventStore` has none of its own.
struct CalendarSession: Identifiable {
    let store: EKEventStore
    var id: ObjectIdentifier { ObjectIdentifier(store) }
}

struct ScrimGlyph: View {
    let symbol: String
    var body: some View {
        Image(systemName: symbol).font(.system(size: 16, weight: .semibold)).foregroundStyle(Palette.ink)
            .frame(width: 40, height: 40).background(.white.opacity(0.92), in: Circle())
            .overlay(Circle().strokeBorder(.black.opacity(0.06), lineWidth: 1))
    }
}

struct ScrimButton: View {
    let symbol: String
    let label: String
    let action: () -> Void
    var body: some View {
        Button(action: action) { ScrimGlyph(symbol: symbol) }
            .buttonStyle(.plain)
            .accessibilityLabel(label)
    }
}
