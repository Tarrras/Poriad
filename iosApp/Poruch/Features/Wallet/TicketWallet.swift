import SwiftUI
import Shared
import PDFKit
import Vision
import PhotosUI
import UniformTypeIdentifiers
import CryptoKit

/// Квиток, що прийшов файлом і чекає підтвердження (docs/ticket-wallet.md). Файл уже скопійовано до себе.
struct TicketImport: Identifiable {
    let id: String
    let file: String
    let kind: TicketKind
    let draft: TicketDraft
    let count: Int
    let preview: UIImage?
    /// `share` — прийшов з «Поділитися», `picker` — обрано в «Моїх подіях».
    let source: String
    /// SHA-256 файлу: той самий квиток удруге не додається.
    let fingerprint: String
}

/// Шторка квитка від файлу до «Додати»: відкривається одразу з «Читаємо квиток…», далі — розібраний, дубль чи помилка.
struct TicketIntake: Identifiable {
    enum Stage { case reading, ready(TicketImport), duplicate(String), failed }
    let id = UUID()
    var stage = Stage.reading
}

/// Маршрут до квитка для `sheet(item:)`: у Kotlin-класу нема `Identifiable`.
struct TicketRoute: Identifiable, Hashable { let id: String }

/// Файли квитків — лише на телефоні: копія в Application Support, текст — PDFKit чи Vision. Сервер їх не бачить.
enum TicketFiles {
    static var folder: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("tickets", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base
    }

    static func url(_ file: String) -> URL { folder.appendingPathComponent(file) }

    static func remove(_ file: String) { try? FileManager.default.removeItem(at: url(file)) }

    /**
     * Шторка — одразу, ще до розбору: людина бачить, що файл дійшов. Далі `load` скаже, що це: квиток, той самий
     * квиток удруге чи не квиток.
     */
    @MainActor static func intake(_ model: AppModel, _ load: @escaping () async -> TicketImport?) {
        let intake = TicketIntake()
        model.root.ticketIntake = intake
        Task {
            let ticket = await load()
            // Шторку закрили, поки читали: копія нікому не потрібна.
            guard model.root.ticketIntake?.id == intake.id else { if let ticket { remove(ticket.file) }; return }
            guard let ticket else { model.root.ticketIntake?.stage = .failed; return }
            if let existing = model.app.ticketWithFingerprint(fingerprint: ticket.fingerprint) {
                remove(ticket.file)
                model.root.ticketIntake?.stage = .duplicate(existing.id)
            } else {
                model.root.ticketIntake?.stage = .ready(ticket)
            }
        }
    }

    /// Файл з «Поділитися» чи з вибору: копія до себе, потім читання. Nil — не PDF і не знімок або не відкрився.
    static func load(_ source: URL, app: PoruchApp, origin: String) async -> TicketImport? {
        let scoped = source.startAccessingSecurityScopedResource()
        defer { if scoped { source.stopAccessingSecurityScopedResource() } }
        let ext = source.pathExtension.lowercased()
        let pdf = ext == "pdf"
        let id = UUID().uuidString.lowercased()
        let file = id + "." + (pdf ? "pdf" : (ext.isEmpty ? "jpg" : ext))
        do { try FileManager.default.copyItem(at: source, to: url(file)) } catch { return nil }
        return await read(id: id, file: file, pdf: pdf, app: app, origin: origin)
    }

    /// Знімок квитка з галереї.
    static func load(image data: Data, app: PoruchApp) async -> TicketImport? {
        let id = UUID().uuidString.lowercased()
        let file = id + ".jpg"
        do { try data.write(to: url(file)) } catch { return nil }
        return await read(id: id, file: file, pdf: false, app: app, origin: "picker")
    }

    private static func read(id: String, file: String, pdf: Bool, app: PoruchApp, origin: String) async -> TicketImport? {
        let target = url(file)
        let fingerprint = (try? Data(contentsOf: target)).map { SHA256.hash(data: $0).map { String(format: "%02x", $0) }.joined() } ?? id
        let (text, pages, preview) = await Task.detached(priority: .userInitiated) { () async -> (String, Int, UIImage?) in
            if pdf {
                guard let document = PDFDocument(url: target), document.pageCount > 0 else { return ("", 0, nil) }
                let first = document.page(at: 0).map { trimmed(image($0, width: 900)) }
                var text = document.string ?? ""
                // Скан без текстового шару: читаємо першу сторінку, як знімок.
                if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, let cg = first?.cgImage { text = await recognize(cg) }
                return (text, document.pageCount, first)
            }
            guard let image = UIImage(contentsOfFile: target.path), let cg = image.cgImage else { return ("", 0, nil) }
            return (await recognize(cg), 1, image)
        }.value
        guard pages > 0 else { remove(file); return nil }
        let draft = app.readTicket(text: text)
        // Сторінка на квиток (Multiplex), а на одній сторінці буває кілька місць.
        let count = max(pdf ? pages : 1, draft.seats.count)
        return TicketImport(
            id: id, file: file, kind: pdf ? .pdf : .image, draft: draft, count: count, preview: preview, source: origin,
            fingerprint: fingerprint
        )
    }

    /// Скільки сторінок показати на весь екран: PDF — кожна сторінка, знімок — він сам.
    static func pageCount(_ ticket: WalletTicket) -> Int {
        ticket.kind == .pdf ? PDFDocument(url: url(ticket.file))?.pageCount ?? 0 : 1
    }

    /// Одна сторінка на весь екран — коли до неї догорнули, а не всі десять разом.
    static func page(_ ticket: WalletTicket, _ index: Int) -> UIImage? {
        let target = url(ticket.file)
        if ticket.kind == .pdf { return PDFDocument(url: target)?.page(at: index).map { image($0, width: 1400) } }
        return UIImage(contentsOfFile: target.path)
    }

    /**
     * Одна сторінка як окремий файл (хвиля 2): з PDF на кількох той, з ким ідеш, отримує лише свій квиток. Знімок
     * іде як є.
     */
    static func single(_ ticket: WalletTicket, page: Int) -> URL? {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("send", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let source = url(ticket.file)
        let out = folder.appendingPathComponent("Квиток \(page + 1)." + (ticket.kind == .pdf ? "pdf" : source.pathExtension))
        try? FileManager.default.removeItem(at: out)
        if ticket.kind == .pdf {
            guard let document = PDFDocument(url: source), let copy = document.page(at: page)?.copy() as? PDFPage else { return nil }
            let single = PDFDocument()
            single.insert(copy, at: 0)
            return single.write(to: out) ? out : nil
        }
        return (try? FileManager.default.copyItem(at: source, to: out)) != nil ? out : nil
    }

    private static func image(_ page: PDFPage, width: CGFloat) -> UIImage {
        let box = page.bounds(for: .mediaBox)
        return page.thumbnail(of: CGSize(width: width, height: width * box.height / max(box.width, 1)), for: .mediaBox)
    }

    /// Прев'ю без білих полів: квиток часто — смужка на аркуші A4, і в шторці інакше видно лише папір.
    private static func trimmed(_ image: UIImage) -> UIImage {
        guard let cg = image.cgImage else { return image }
        let width = cg.width, height = cg.height
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        let drawn: Bool = pixels.withUnsafeMutableBytes { buffer in
            guard let context = CGContext(
                data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else { return false }
            context.setFillColor(UIColor.white.cgColor)
            context.fill(CGRect(x: 0, y: 0, width: width, height: height))
            context.draw(cg, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard drawn else { return image }
        var minX = width, minY = height, maxX = -1, maxY = -1
        for y in stride(from: 0, to: height, by: 2) {
            for x in stride(from: 0, to: width, by: 2) {
                let i = (y * width + x) * 4
                if pixels[i] < 235 || pixels[i + 1] < 235 || pixels[i + 2] < 235 {
                    minX = min(minX, x); maxX = max(maxX, x); minY = min(minY, y); maxY = max(maxY, y)
                }
            }
        }
        guard maxX >= 0 else { return image }
        let pad = width / 30
        let x0 = max(minX - pad, 0), y0 = max(minY - pad, 0)
        let rect = CGRect(x: x0, y: y0, width: min(maxX + pad, width) - x0, height: min(maxY + pad, height) - y0)
        return cg.cropping(to: rect).map { UIImage(cgImage: $0, scale: image.scale, orientation: image.imageOrientation) } ?? image
    }

    /// Текст зі знімка: Vision читає українську з iOS 16.
    private static func recognize(_ image: CGImage) async -> String {
        await withCheckedContinuation { continuation in
            let request = VNRecognizeTextRequest { request, _ in
                let lines = (request.results as? [VNRecognizedTextObservation])?.compactMap { $0.topCandidates(1).first?.string } ?? []
                continuation.resume(returning: lines.joined(separator: "\n"))
            }
            request.recognitionLevel = .accurate
            request.recognitionLanguages = ["uk-UA", "en-US"]
            do { try VNImageRequestHandler(cgImage: image).perform([request]) } catch { continuation.resume(returning: "") }
        }
    }
}

/// Що йде разом із файлом: що, коли й де, а для афіші — посилання на подію.
func ticketShareText(_ ticket: WalletTicket) -> String {
    let when = [ticketWhen(ticket), ticket.place].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · ")
    // Кіно без афіші — посилання на сайт: той, кому квиток, дізнається, звідки він.
    let link = "\n" + (ticket.eventId.map { EventLinks.shared.url(eventId: $0) } ?? StoreLinks.shared.SHARE)
    return Copy.wallet_send_text(ticket.title, when) + link
}

/// Аркуш «Поділитися» з файлом квитка: `sheet(item:)` потребує identity.
struct TicketShare: Identifiable {
    let id = UUID()
    let items: [Any]
}

/// «пт 30.10, 19:40» у поясі квитка.
func ticketWhen(_ ticket: WalletTicket) -> String {
    guard let date = parseEventDate(ticket.startsAt) else { return "" }
    return formatter(zone: ticket.timeZone, "EE d.MM, HH:mm").string(from: date)
}

func ticketSeats(_ ticket: WalletTicket) -> String? {
    let seats = ticket.seats.map { seat in seat.row.map { Copy.wallet_seat($0, seat.seat) } ?? Copy.wallet_seat_only(seat.seat) }
    return seats.isEmpty ? nil : seats.joined(separator: " · ")
}

// MARK: - Підтвердження

/// Шторка від файлу до квитка: поки читаємо — так і кажемо; той самий квиток удруге — показуємо той, що вже є.
struct TicketIntakeSheet: View {
    @EnvironmentObject private var model: AppModel
    let intake: TicketIntake

    var body: some View {
        switch intake.stage {
        case .ready(let ticket): TicketImportSheet(ticket: ticket)
        case .reading: note(Copy.wallet_import_title, short: false) { ProgressView(Copy.wallet_reading).tint(Palette.ink).frame(maxWidth: .infinity) }
        case .failed:
            note(Copy.wallet_import_title) {
                Text(Copy.wallet_failed).font(PoruchFont.bodyText).foregroundStyle(Palette.inkSecondary).fixedSize(horizontal: false, vertical: true)
                SecondaryButton(title: Copy.close) { model.root.ticketIntake = nil }
            }
        case .duplicate(let id):
            // Повноекранний квиток — коли шторка вже закрилась: два показу разом SwiftUI не тримає.
            let show = { model.root.ticketNext = TicketRoute(id: id); model.root.ticketIntake = nil }
            note(Copy.wallet_duplicate_title) {
                if let ticket = model.state?.tickets.first(where: { $0.id == id }) {
                    Button(action: show) { WalletTicketCard(ticket: ticket) }.buttonStyle(PressableStyle())
                }
                PrimaryButton(title: Copy.wallet_show, glyph: PoruchIcons.ticket, action: show)
            }
        }
    }

    /// `short` — помилка й дубль: два рядки, пів екрана. Читання — на всю висоту, як шторка, що за ним відкриється.
    private func note(_ title: String, short: Bool = true, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: Space.lg) {
            Text(title).font(PoruchFont.brandTitle1).kerning(-0.4).foregroundStyle(Palette.ink)
            content()
        }
        .padding(.horizontal, Space.page).padding(.top, Space.xl).padding(.bottom, Space.section)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Palette.canvas)
        .presentationDetents(short ? [.medium] : [.large])
        .presentationDragIndicator(.visible)
    }
}

/// Шторка «Квиток»: прев'ю, знайдена подія афіші або поля, заповнені розбором. Одна дія — «Додати квиток».
/// Закрили без «Додати» — файл стирається: квиток не потрапив до людини.
struct TicketImportSheet: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    let ticket: TicketImport
    @State private var title = ""
    @State private var place = ""
    @State private var start = Date()
    @State private var hasStart = false
    @State private var matchID: String?
    @State private var linked = true
    @State private var added = false

    private var matched: Event? { matchID.flatMap { model.cardsByID[$0] } }
    private var onListing: Bool { linked && matched != nil }
    private var canSave: Bool { onListing || (!title.trimmingCharacters(in: .whitespaces).isEmpty && hasStart) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.lg) {
                VStack(alignment: .leading, spacing: Space.xs) {
                    Text(Copy.wallet_import_title).font(PoruchFont.brandTitle1).kerning(-0.4).foregroundStyle(Palette.ink)
                    Text(Copy.wallet_count(ticket.count)).font(PoruchFont.subhead).foregroundStyle(Palette.inkSecondary)
                }
                if let preview = ticket.preview {
                    Image(uiImage: preview).resizable().scaledToFit().frame(maxWidth: .infinity, maxHeight: 220)
                        .clipShape(RoundedRectangle(cornerRadius: Corner.md, style: .continuous))
                        .accessibilityHidden(true)
                }
                if ticket.draft.parsed == "none" {
                    Text(Copy.wallet_unreadable).font(PoruchFont.subhead).foregroundStyle(Palette.inkSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let matched {
                    Toggle(isOn: $linked) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(Copy.wallet_match).font(PoruchFont.caption).foregroundStyle(Palette.inkSecondary)
                            Text(matched.displayTitle).font(PoruchFont.cardName).foregroundStyle(Palette.ink).lineLimit(2)
                            Text(eventDate(matched)).font(PoruchFont.caption).foregroundStyle(Palette.inkSecondary)
                        }
                    }
                    .tint(Palette.ink).padding(Space.lg).cardSurface()
                }
                if !onListing {
                    LabelledField(label: Copy.wallet_name, text: $title, placeholder: Copy.wallet_name_hint)
                    LabelledField(label: Copy.wallet_place, text: $place, placeholder: Copy.wallet_place_hint)
                    VStack(alignment: .leading, spacing: Space.sm) {
                        Text(Copy.wallet_when.uppercased()).font(PoruchFont.overline).kerning(1.0).foregroundStyle(Palette.inkTertiary)
                        DatePicker(Copy.wallet_when, selection: Binding(get: { start }, set: { start = $0; hasStart = true }))
                            .labelsHidden().datePickerStyle(.compact).tint(Palette.ink)
                    }
                }
                PrimaryButton(title: Copy.wallet_save, glyph: PoruchIcons.ticket, enabled: canSave) { add() }
            }
            .padding(.horizontal, Space.page).padding(.top, Space.xl).padding(.bottom, Space.section)
        }
        .background(Palette.canvas)
        .presentationDragIndicator(.visible)
        .onAppear(perform: prefill)
        .onDisappear { if !added { TicketFiles.remove(ticket.file) } }
    }

    private func prefill() {
        title = ticket.draft.title ?? ""
        place = ticket.draft.place ?? ""
        if let millis = model.app.ticketStartMillis(draft: ticket.draft) {
            start = Date(timeIntervalSince1970: TimeInterval(millis.int64Value) / 1000)
            hasStart = true
        }
        matchID = model.app.ticketMatch(draft: ticket.draft)
        // Картку події видача могла ще не завантажити: доїде в `cardsByID`, і рядок «Квиток на цю подію» зʼявиться.
        if let matchID, model.cardsByID[matchID] == nil { model.app.loadCards(ids: [matchID]) }
    }

    private func add() {
        let event = onListing ? matched : nil
        let startDate = event.flatMap { parseEventDate($0.startsAt) } ?? start
        model.app.addTicket(
            id: ticket.id, file: ticket.file, kind: ticket.kind,
            title: event?.displayTitle ?? title, place: event?.placeLabel ?? place,
            startMillis: Int64(startDate.timeIntervalSince1970 * 1000), count: Int32(ticket.count),
            seats: ticket.draft.seats, eventId: event?.id, source: ticket.source, parsed: ticket.draft.parsed,
            fingerprint: ticket.fingerprint
        )
        added = true
        // Квиток — у «Моїх подіях»: туди й ведемо, щоб людина бачила, де він тепер.
        model.root.ticketAdded = true
        dismiss()
    }
}

// MARK: - Показ

/// Квиток на весь екран: сторінки гортаються, яскравість угору, поки на екрані QR.
struct TicketViewer: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    let ticketID: String
    @State private var count = 0
    @State private var pages: [Int: UIImage] = [:]
    @State private var brightness: CGFloat?
    @State private var deleting = false
    @State private var page = 0
    @State private var sharing: TicketShare?

    private var ticket: WalletTicket? { model.state?.tickets.first { $0.id == ticketID } }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.md) {
            HStack(alignment: .top, spacing: Space.md) {
                if let ticket {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(ticket.title).font(PoruchFont.brandTitle2).kerning(-0.2).foregroundStyle(Palette.ink).lineLimit(2)
                        Text([ticketWhen(ticket), ticket.place].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · "))
                            .font(PoruchFont.subhead).foregroundStyle(Palette.inkSecondary)
                        if let seats = ticketSeats(ticket) {
                            Text(seats).font(PoruchFont.caption).foregroundStyle(Palette.inkSecondary)
                        }
                    }
                }
                Spacer(minLength: 0)
                Button { dismiss() } label: {
                    PoruchIcon(glyph: PoruchIcons.close, size: 20).foregroundStyle(Palette.ink)
                        .frame(width: 40, height: 40).background(Palette.surface, in: Circle()).tapTarget()
                }
                .buttonStyle(.plain).accessibilityLabel(Copy.close)
            }
            TabView(selection: $page) {
                ForEach(0..<count, id: \.self) { index in
                    Group {
                        if let image = pages[index] {
                            // Квиток — папір: білий під ним і вночі, інакше QR на темному тлі сканер не бере.
                            Image(uiImage: image).resizable().scaledToFit()
                                .background(Color.white)
                                .clipShape(RoundedRectangle(cornerRadius: Corner.md, style: .continuous))
                        } else {
                            ProgressView().tint(Palette.ink).frame(maxWidth: .infinity, maxHeight: .infinity)
                        }
                    }
                    .padding(.bottom, Space.xl)
                    .tag(index)
                    // Сторінка малюється, коли до неї догорнули: PDF на десять квитків не тримає десять растрів.
                    .task {
                        guard pages[index] == nil, let ticket else { return }
                        pages[index] = await Task.detached { TicketFiles.page(ticket, index) }.value
                    }
                }
            }
            .tabViewStyle(.page(indexDisplayMode: count > 1 ? .always : .never))
            .accessibilityLabel(ticket.map { Copy.wallet_count(Int($0.count)) } ?? "")
            // Квиток тому, з ким ідеш: лише сторінка, яку видно, і що-коли-де з посиланням (docs/ticket-wallet.md, хвиля 2).
            if let ticket {
                SecondaryButton(title: Copy.wallet_send, glyph: PoruchIcons.share) {
                    guard let file = TicketFiles.single(ticket, page: page) else { return }
                    model.app.ticketSent(id: ticket.id)
                    sharing = TicketShare(items: [ticketShareText(ticket), file])
                }
            }
            Button { deleting = true } label: {
                Text(Copy.wallet_delete).font(PoruchFont.button).foregroundStyle(Palette.danger).tapTarget()
            }
            .buttonStyle(.plain).frame(maxWidth: .infinity)
        }
        .padding(.horizontal, Space.page).padding(.top, Space.lg).padding(.bottom, Space.md)
        .background(Palette.canvas.ignoresSafeArea())
        .task {
            guard let ticket else { return }
            count = await Task.detached { TicketFiles.pageCount(ticket) }.value
            model.app.ticketShown(id: ticket.id)
        }
        .onAppear {
            guard let screen = keyScreen() else { return }
            brightness = screen.brightness
            screen.brightness = 1
        }
        .onDisappear { if let brightness { keyScreen()?.brightness = brightness } }
        .sheet(item: $sharing) { ActivitySheet(items: $0.items).presentationDetents([.medium, .large]) }
        .alert(Copy.wallet_delete_title, isPresented: $deleting) {
            Button(Copy.cancel, role: .cancel) {}
            Button(Copy.wallet_delete, role: .destructive) {
                if let ticket {
                    model.app.removeTicket(id: ticket.id)
                    TicketFiles.remove(ticket.file)
                }
                dismiss()
            }
        } message: {
            Text(Copy.wallet_delete_body)
        }
    }

    private func keyScreen() -> UIScreen? {
        UIApplication.shared.connectedScenes.compactMap { ($0 as? UIWindowScene)?.screen }.first
    }
}

// MARK: - Головна

/// День події: квиток першим на головній — його відкривають на вході. І в гостя, і в кіно без афіші.
struct TodayTickets: View {
    @Environment(\.appModel) private var appModel
    let tickets: [WalletTicket]

    var body: some View {
        VStack(alignment: .leading, spacing: Space.md) {
            SectionHeader(title: Copy.wallet_today)
            ForEach(tickets, id: \.id) { ticket in
                Button { appModel?.root.shownTicket = TicketRoute(id: ticket.id) } label: { WalletTicketCard(ticket: ticket) }
                    .buttonStyle(PressableStyle())
            }
        }
        .padding(.horizontal, Space.page)
    }
}

// MARK: - «Мої події»

/// Секція «Квитки» згори «Моїх подій»: що попереду, з датою й місцем. Нема — один рядок, що вчить «Поділитися».
struct TicketsSection: View {
    @Environment(\.appModel) private var appModel
    private var model: AppModel { appModel! }
    let tickets: [WalletTicket]
    /// Минулі — пробиті й згорнуті під рядком: квиток на згадку, а не в черзі з тими, що попереду.
    var past: [WalletTicket] = []
    @State private var choosing = false
    @State private var files = false
    @State private var photos = false
    @State private var photo: PhotosPickerItem?
    @State private var showsPast = false

    var body: some View {
        VStack(alignment: .leading, spacing: Space.md) {
            if tickets.isEmpty {
                LinkRow(glyph: PoruchIcons.ticket, title: Copy.wallet_add_title, subtitle: Copy.wallet_add_hint) { choosing = true }
                    .cardSurface()
            } else {
                SectionHeader(title: Copy.wallet_title, actionLabel: Copy.wallet_add) { choosing = true }
                ForEach(tickets, id: \.id) { ticket in
                    Button { model.root.shownTicket = TicketRoute(id: ticket.id) } label: { WalletTicketCard(ticket: ticket) }
                        .buttonStyle(PressableStyle())
                }
            }
            if !past.isEmpty {
                Button { withMotion { showsPast.toggle() } } label: {
                    HStack(spacing: Space.sm) {
                        Text(Copy.wallet_past("\(past.count)")).font(PoruchFont.subhead).foregroundStyle(Palette.inkSecondary)
                        Spacer(minLength: 0)
                        PoruchIcon(glyph: PoruchIcons.chevronDown, size: 16).foregroundStyle(Palette.inkTertiary)
                            .rotationEffect(.degrees(showsPast ? 180 : 0))
                    }
                    .tapTarget()
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(showsPast ? .isSelected : [])
                if showsPast {
                    ForEach(past, id: \.id) { ticket in
                        Button { model.root.shownTicket = TicketRoute(id: ticket.id) } label: { WalletTicketCard(ticket: ticket, punched: true) }
                            .buttonStyle(PressableStyle())
                    }
                }
            }
        }
        .confirmationDialog(Copy.wallet_add_title, isPresented: $choosing) {
            Button(Copy.wallet_from_files) { files = true }
            Button(Copy.wallet_from_photos) { photos = true }
        }
        .fileImporter(isPresented: $files, allowedContentTypes: [.pdf, .image]) { result in
            guard case .success(let url) = result else { return }
            TicketFiles.intake(model) { await TicketFiles.load(url, app: model.app, origin: "picker") }
        }
        .photosPicker(isPresented: $photos, selection: $photo, matching: .images)
        .onChange(of: photo) { _, item in
            guard let item else { return }
            photo = nil
            TicketFiles.intake(model) {
                guard let data = try? await item.loadTransferable(type: Data.self) else { return nil }
                return await TicketFiles.load(image: data, app: model.app)
            }
        }
    }
}

/// Квиток з телефона квитком «Корінця»: назва, місце й кількість на поверхні, час і день — на чорнильному корінці.
/// Чорнило, а не колір жанру: це вже не афіша, а квиток у руці, і в кіно жанру нема.
struct WalletTicketCard: View {
    let ticket: WalletTicket
    /// Минулий: пробитий, як минулі події афіші.
    var punched = false

    var body: some View {
        let date = parseEventDate(ticket.startsAt)
        Ticket(stubColor: Palette.ink, stubLength: 84, punched: punched) {
            VStack(alignment: .leading, spacing: Space.xs) {
                Text(ticket.title).font(PoruchFont.brandTitle3).foregroundStyle(Palette.ink).lineLimit(2)
                    .multilineTextAlignment(.leading).fixedSize(horizontal: false, vertical: true)
                if let place = ticket.place, !place.isEmpty {
                    Text(place).font(PoruchFont.caption).foregroundStyle(Palette.inkSecondary).lineLimit(2)
                }
                Text(ticketSeats(ticket) ?? Copy.wallet_count(Int(ticket.count)))
                    .font(PoruchFont.caption).foregroundStyle(Palette.inkTertiary).lineLimit(2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(Space.lg)
        } stub: {
            VStack(spacing: 2) {
                if let date {
                    Text(formatter(zone: ticket.timeZone, "HH:mm").string(from: date))
                        .font(PoruchFont.numeral).monospacedDigit().minimumScaleFactor(0.6).lineLimit(1)
                    Text(formatter(zone: ticket.timeZone, "EE d.MM").string(from: date).uppercased())
                        .font(PoruchFont.overline).kerning(0.6).lineLimit(1).minimumScaleFactor(0.7)
                }
            }
            .foregroundStyle(Palette.onBrand).padding(.horizontal, Space.sm)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel([ticket.title, ticketWhen(ticket), ticket.place ?? "", Copy.wallet_count(Int(ticket.count))].filter { !$0.isEmpty }.joined(separator: ", "))
        .accessibilityAddTraits(.isButton)
    }
}
