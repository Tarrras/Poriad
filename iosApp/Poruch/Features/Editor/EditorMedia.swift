import AVFoundation
import PhotosUI
import SwiftUI
import UniformTypeIdentifiers
import Shared

/// Фото чи відео в чернетці редактора (docs/organizers-1.5.md, «Фото й відео в редакторі»). `Codable`, бо живе в
/// чернетці між запусками: нове лежить файлом на телефоні, доки подію не опублікують — сховище пускає файл лише до
/// наявної події.
struct DraftItem: Codable, Equatable, Identifiable {
    enum Origin: String, Codable {
        /// Файл у `DraftFiles`, уже стиснений.
        case local
        /// Уже в цієї події на сервері: редагування.
        case remote
        /// Іншої події: «Повторити» копіює його в теку нової з публікацією.
        case copied
    }

    var origin: Origin
    var video: Bool
    /// `local` — імʼя файлу в `DraftFiles`; інакше — адреса.
    var url: String
    /// Перший кадр відео JPEG: так само ім'я файлу чи адреса.
    var poster: String?
    /// Відео довше за 30 с обрізане до початку: «Перші 30 секунд».
    var trimmed = false

    var id: String { url }
    var kind: MediaKind { video ? .video : .photo }

    init(origin: Origin, video: Bool, url: String, poster: String?, trimmed: Bool = false) {
        self.origin = origin; self.video = video; self.url = url; self.poster = poster; self.trimmed = trimmed
    }

    init(_ media: EventMedia, origin: Origin) {
        self.init(origin: origin, video: media.kind == .video, url: media.url, poster: media.poster)
    }

    /// Що бачить спільний шар: байти нового читаються з диска лише під час вивантаження.
    var draftMedia: DraftMedia {
        switch origin {
        case .local:
            DraftMediaLocal(key: url, kind: kind, bytes: FileBytes(DraftFiles.url(url)), poster: poster.map { FileBytes(DraftFiles.url($0)) })
        case .remote: DraftMediaRemote(media: EventMedia(kind: kind, url: url, poster: poster))
        case .copied: DraftMediaCopied(media: EventMedia(kind: kind, url: url, poster: poster))
        }
    }

    /// Що показати на плитці: файл чи адреса картинки (у відео — постер).
    var preview: URL? {
        let image = video ? poster : url
        guard let image else { return nil }
        return origin == .local ? DraftFiles.url(image) : URL(string: image)
    }
}

/// Байти файлу чернетки для `DraftMedia.Local`: спільний шар кличе `read` не на головному потоці, коли вантажить.
final class FileBytes: NSObject, MediaBytes {
    private let file: URL
    init(_ file: URL) { self.file = file }
    /// Файлу вже нема (прибрали з диска) — порожньо: вивантаження впаде, і подія лишиться без нього, як без будь-якого збою.
    func read() -> KotlinByteArray { kotlinBytes((try? Data(contentsOf: file)) ?? Data()) }
}

/// Data → ByteArray одним memcpy у спільному шарі (`bytesOf`). Кличуть не з головного потоку.
func kotlinBytes(_ data: Data) -> KotlinByteArray { Bytes_iosKt.bytesOf(data: data) }

/// Тека файлів чернеток. Одна на телефон: чернетки належать людині й зникають з виходом (`EventEditorModel.clearDrafts`).
enum DraftFiles {
    /// Щоразу перевіряємо, що тека є: вихід з акаунта стирає її цілком. Не в Caches — система їх чистить, а чернетка
    /// лишилась би без файлів; і не в бекап iCloud — десятки мегабайт відео, яке ще навіть не опубліковане.
    static var directory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        var directory = base.appendingPathComponent("draft-media", isDirectory: true)
        if !FileManager.default.fileExists(atPath: directory.path) {
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            var values = URLResourceValues()
            values.isExcludedFromBackup = true
            try? directory.setResourceValues(values)
        }
        return directory
    }

    static func url(_ name: String) -> URL { directory.appendingPathComponent(name) }

    static func write(_ data: Data, ext: String) throws -> String {
        let name = "\(UUID().uuidString).\(ext)"
        try data.write(to: url(name), options: .atomic)
        return name
    }

    /// Файли нового з чернетки: подію опубліковано, файл прибрали чи чернетку стерли.
    static func delete(_ items: [DraftItem]) {
        for item in items where item.origin == .local {
            try? FileManager.default.removeItem(at: url(item.url))
            if let poster = item.poster { try? FileManager.default.removeItem(at: url(poster)) }
        }
    }

    static func deleteAll() { try? FileManager.default.removeItem(at: directory) }
}

/// Відео з пікера файлом: `Data` тримало б у памʼяті весь ролик з телефона, а це сотні мегабайт.
private struct PickedMovie: Transferable {
    let url: URL
    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(contentType: .movie) { SentTransferredFile($0.url) } importing: { received in
            let ext = received.file.pathExtension.isEmpty ? "mov" : received.file.pathExtension
            let copy = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).\(ext)")
            try FileManager.default.copyItem(at: received.file, to: copy)
            return PickedMovie(url: copy)
        }
    }
}

enum DraftMediaPicker {
    /// Фото — як обкладинка: JPEG без метаданих, довша сторона до 2048 px (`pickedJPEGData`). Відео — стиснене (`VideoCompressor`).
    static func prepare(_ item: PhotosPickerItem) async -> DraftItem? {
        if item.supportedContentTypes.contains(where: { $0.conforms(to: .movie) }) { return await video(item) }
        guard case .success(let jpeg) = await pickedJPEGData(item, maxPixel: mediaPhotoMaxPixel),
              let name = try? DraftFiles.write(jpeg, ext: "jpg") else { return nil }
        return DraftItem(origin: .local, video: false, url: name, poster: nil)
    }

    private static func video(_ item: PhotosPickerItem) async -> DraftItem? {
        guard let picked = try? await item.loadTransferable(type: PickedMovie.self) else { return nil }
        defer { try? FileManager.default.removeItem(at: picked.url) }
        let name = "\(UUID().uuidString).mp4"
        let output = DraftFiles.url(name)
        // Згорнули застосунок посеред стиснення: дотискаємо у фоні, а вийшов час — зупиняємось, а не висимо.
        let stop = CompressionStop()
        let background = await MainActor.run { BackgroundWork(stop) }
        defer { Task { @MainActor in background.end() } }
        do {
            let trimmed = try await VideoCompressor.compress(picked.url, to: output, stop: stop)
            let poster = try await VideoCompressor.poster(of: output)
            return DraftItem(origin: .local, video: true, url: name, poster: try DraftFiles.write(poster, ext: "jpg"), trimmed: trimmed)
        } catch {
            PoruchLog.shared.w(tag: "media") { "video not prepared: \((error as NSError).domain) \((error as NSError).code)" }
            try? FileManager.default.removeItem(at: output)
            return nil
        }
    }

    /// Зменшене фото для плитки: 2048 px на плитці 96 pt — 16 МБ памʼяті на кожну.
    static func thumbnail(_ file: URL) async -> UIImage? {
        await Task.detached(priority: .userInitiated) {
            (try? Data(contentsOf: file)).flatMap { ThumbnailCache.downsample($0, to: 320, fill: true) }
        }.value
    }
}

/// Стиснення зупиняють ззовні: час фонової задачі вийшов. Перевіряє вартовий у `VideoCompressor`.
final class CompressionStop: @unchecked Sendable {
    private let lock = NSLock()
    private var stopped = false
    var isStopped: Bool { lock.lock(); defer { lock.unlock() }; return stopped }
    func stop() { lock.lock(); stopped = true; lock.unlock() }
}

/// Фонова задача на час стиснення: без неї система зупиняє кодер, щойно застосунок згорнули.
@MainActor private final class BackgroundWork {
    private var id = UIBackgroundTaskIdentifier.invalid
    init(_ stop: CompressionStop) {
        id = UIApplication.shared.beginBackgroundTask(withName: "poruch.video") { [weak self] in
            stop.stop()
            self?.end()
        }
    }
    func end() {
        guard id != .invalid else { return }
        UIApplication.shared.endBackgroundTask(id)
        id = .invalid
    }
}

/// Довша сторона фото події: та сама, що в старої обкладинки.
let mediaPhotoMaxPixel: CGFloat = 2048

/// Відео до H.264 720p, перших 30 с і 8 МБ (`MediaRules`): відтворюють і Safari, і Chrome, а кожен перегляд — наш
/// трафік Storage (docs/organizers-1.5.md, 1.3). Одразу `AVAssetWriter` з бітрейтом: пресет `AVAssetExportPreset1280x720`
/// дає 5–10 Мбіт/с, тож 30 с — 20–35 МБ, і друге кодування після нього було б майже завжди.
enum VideoCompressor {
    private static let audioBitrate = 64_000
    /// ≈ 2 Мбіт/с: стеля навіть для короткого ролика, щоб 10 с не важили 8 МБ.
    private static let maxVideoBitrate = 2_000_000

    struct Failure: Error {}

    /// Повертає, чи обрізали до перших 30 с.
    static func compress(_ source: URL, to output: URL, stop: CompressionStop) async throws -> Bool {
        let asset = AVURLAsset(url: source)
        let duration = try await asset.load(.duration)
        let limit = CMTime(seconds: Double(MediaRules.shared.VIDEO_MAX_SECONDS), preferredTimescale: 600)
        let trimmed = duration > limit
        let range = CMTimeRange(start: .zero, duration: trimmed ? limit : duration)
        let budget = Double(MediaRules.shared.VIDEO_MAX_BYTES)
        // 10 % запасу: кодер тримає середній бітрейт, а не стелю.
        var bitrate = min(Double(maxVideoBitrate), budget * 8 * 0.9 / max(range.duration.seconds, 1) - Double(audioBitrate))
        // ponytail: дві спроби з меншим бітрейтом, далі «Не вдалося додати цей файл». Підбирати точніше — якщо впиратимуться.
        for _ in 0..<2 {
            try await transcode(asset, range: range, to: output, bitrate: Int(bitrate), stop: stop)
            let size = (try? output.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? .max
            if size <= Int(budget) { return trimmed }
            bitrate *= 0.6
        }
        throw Failure()
    }

    /// Перший кадр стисненого відео JPEG — обкладинка, поки відео не грає.
    static func poster(of video: URL) async throws -> Data {
        let generator = AVAssetImageGenerator(asset: AVURLAsset(url: video))
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 1280, height: 1280)
        let (image, _) = try await generator.image(at: .zero)
        guard let jpeg = UIImage(cgImage: image).jpegData(compressionQuality: 0.8) else { throw Failure() }
        return jpeg
    }

    /// SDR Rec.709 і в читанні, і в записі: HDR з iPhone 12+ (HLG, Dolby Vision) інакше на вебі й Android вицвітає.
    private static let rec709: [String: Any] = [
        AVVideoColorPrimariesKey: AVVideoColorPrimaries_ITU_R_709_2,
        AVVideoTransferFunctionKey: AVVideoTransferFunction_ITU_R_709_2,
        AVVideoYCbCrMatrixKey: AVVideoYCbCrMatrix_ITU_R_709_2
    ]

    private static func transcode(_ asset: AVURLAsset, range: CMTimeRange, to output: URL, bitrate: Int, stop: CompressionStop) async throws {
        try? FileManager.default.removeItem(at: output)
        guard let video = try await asset.loadTracks(withMediaType: .video).first else { throw Failure() }
        let audio = try await asset.loadTracks(withMediaType: .audio).first
        let (natural, transform) = try await video.load(.naturalSize, .preferredTransform)
        let reader = try AVAssetReader(asset: asset)
        reader.timeRange = range
        let writer = try AVAssetWriter(outputURL: output, fileType: .mp4)
        // moov на початку: сторінка й застосунок грають, не докачавши весь файл.
        writer.shouldOptimizeForNetworkUse = true

        // 720p: коротша сторона до 720, довша до 1280; розміри парні, як просить H.264. Поворот — у `transform`.
        let scale = min(1, 1280 / max(natural.width, natural.height), 720 / max(min(natural.width, natural.height), 1))
        func even(_ value: CGFloat) -> Int { max(2, Int((value * scale / 2).rounded()) * 2) }
        let videoOut = AVAssetReaderTrackOutput(track: video, outputSettings: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange,
            AVVideoColorPropertiesKey: rec709
        ])
        videoOut.alwaysCopiesSampleData = false
        reader.add(videoOut)
        let videoIn = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: even(natural.width), AVVideoHeightKey: even(natural.height),
            AVVideoScalingModeKey: AVVideoScalingModeResizeAspectFill,
            AVVideoColorPropertiesKey: rec709,
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey: bitrate,
                AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel,
                AVVideoMaxKeyFrameIntervalDurationKey: 2
            ]
        ])
        videoIn.transform = transform
        videoIn.expectsMediaDataInRealTime = false
        writer.add(videoIn)
        var pairs = [(videoOut as AVAssetReaderOutput, videoIn)]

        if let audio {
            let audioOut = AVAssetReaderTrackOutput(track: audio, outputSettings: [
                AVFormatIDKey: kAudioFormatLinearPCM, AVSampleRateKey: 44_100, AVNumberOfChannelsKey: 2,
                AVLinearPCMBitDepthKey: 16, AVLinearPCMIsFloatKey: false, AVLinearPCMIsBigEndianKey: false, AVLinearPCMIsNonInterleaved: false
            ])
            reader.add(audioOut)
            var layout = AudioChannelLayout()
            layout.mChannelLayoutTag = kAudioChannelLayoutTag_Stereo
            let audioIn = AVAssetWriterInput(mediaType: .audio, outputSettings: [
                AVFormatIDKey: kAudioFormatMPEG4AAC, AVSampleRateKey: 44_100, AVNumberOfChannelsKey: 2,
                AVEncoderBitRateKey: audioBitrate,
                AVChannelLayoutKey: Data(bytes: &layout, count: MemoryLayout<AudioChannelLayout>.size)
            ])
            audioIn.expectsMediaDataInRealTime = false
            writer.add(audioIn)
            pairs.append((audioOut, audioIn))
        }

        guard reader.startReading(), writer.startWriting() else { throw reader.error ?? writer.error ?? Failure() }
        writer.startSession(atSourceTime: range.start)
        let pumps = pairs.map { _ in Pump() }
        // Записувач, що впав, може більше не кликати `requestMediaDataWhenReady`: тоді доріжки чекали б вічно. Вартовий
        // бачить збій чи зупинку ззовні й відпускає всі доріжки.
        let watchdog = Task.detached {
            while !pumps.allSatisfy(\.finished) {
                try? await Task.sleep(for: .milliseconds(250))
                if stop.isStopped || reader.status == .failed || writer.status == .failed || writer.status == .cancelled {
                    reader.cancelReading()
                    pumps.forEach { $0.finish() }
                }
            }
        }
        await withTaskGroup(of: Void.self) { group in
            for (index, (output, input)) in pairs.enumerated() {
                let pump = pumps[index]
                let queue = DispatchQueue(label: "poruch.video.\(index)")
                group.addTask {
                    await pump.wait {
                        input.requestMediaDataWhenReady(on: queue) {
                            while input.isReadyForMoreMediaData, !pump.finished {
                                guard writer.status == .writing, reader.status != .failed, !stop.isStopped else { return pump.finish() }
                                guard let sample = output.copyNextSampleBuffer() else {
                                    input.markAsFinished()
                                    return pump.finish()
                                }
                                if !input.append(sample) { return pump.finish() }
                            }
                        }
                    }
                }
            }
        }
        watchdog.cancel()
        guard !stop.isStopped, reader.status != .failed, writer.status == .writing else {
            writer.cancelWriting()
            throw reader.error ?? writer.error ?? Failure()
        }
        await writer.finishWriting()
        guard writer.status == .completed else { throw writer.error ?? Failure() }
    }
}

/// Одна доріжка стиснення: чекання, яке відпускають рівно раз — кінець доріжки, збій чи вартовий.
private final class Pump: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Void, Never>?
    private var done = false

    var finished: Bool { lock.lock(); defer { lock.unlock() }; return done }

    func wait(_ start: () -> Void) async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            lock.lock()
            let already = done
            if !already { self.continuation = continuation }
            lock.unlock()
            if already { continuation.resume() } else { start() }
        }
    }

    func finish() {
        lock.lock()
        let waiting = done ? nil : continuation
        done = true
        continuation = nil
        lock.unlock()
        waiting?.resume()
    }
}

/// «Фото й відео» на першому кроці: плитки в порядку показу, перша — обкладинка. «+» відкриває системний вибір фото
/// й відео, довгий дотик тягне плитку на інше місце, хрестик прибирає. Публікацію не блокує.
struct MediaSection: View {
    @ObservedObject var editor: EventEditorModel
    @State private var picked: [PhotosPickerItem] = []

    private var items: [DraftItem] { editor.form.media ?? [] }
    private var room: Int { Int(MediaRules.shared.MAX_ITEMS) - items.count - editor.preparing }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.sm) {
            Text(Copy.media_title.uppercased()).font(PoruchFont.overline).kerning(1.0).foregroundStyle(Palette.inkTertiary)
                .accessibilityAddTraits(.isHeader)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 96), spacing: Space.sm, alignment: .top)], alignment: .leading, spacing: Space.sm) {
                ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                    MediaTile(item: item, cover: index == 0) { editor.removeMedia(item) }
                        .draggable(item.id) { MediaTile(item: item, cover: false, remove: nil).frame(width: 96) }
                        .dropDestination(for: String.self) { ids, _ in
                            guard let id = ids.first else { return false }
                            editor.moveMedia(id, to: item.id)
                            return true
                        }
                }
                ForEach(0..<editor.preparing, id: \.self) { _ in
                    tileShape.fill(Palette.surface).aspectRatio(1, contentMode: .fit)
                        .overlay { ProgressView() }
                }
                if room > 0 {
                    PhotosPicker(
                        selection: $picked, maxSelectionCount: room, selectionBehavior: .ordered,
                        matching: .any(of: [.images, .videos]), preferredItemEncoding: .current
                    ) {
                        tileShape.strokeBorder(Palette.hairline, style: StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
                            .background(Palette.surface, in: tileShape)
                            .aspectRatio(1, contentMode: .fit)
                            .overlay { PoruchIcon(glyph: PoruchIcons.plus, size: 24).foregroundStyle(Palette.inkSecondary) }
                    }
                    .accessibilityLabel(Copy.media_add_a11y)
                }
            }
            if editor.compressing {
                Text(Copy.media_compressing).font(PoruchFont.caption).foregroundStyle(Palette.inkSecondary)
            }
            if let error = editor.mediaError {
                Text(error).font(PoruchFont.caption).foregroundStyle(Palette.danger)
            }
            Text(Copy.media_hint).font(PoruchFont.caption).foregroundStyle(Palette.inkTertiary)
        }
        .motion(value: items)
        .onChange(of: picked) { _, chosen in
            guard !chosen.isEmpty else { return }
            editor.addMedia(chosen)
            picked = []
        }
    }
}

private let tileShape = RoundedRectangle(cornerRadius: Corner.sm, style: .continuous)

/// Плитка фото чи відео: картинка (у відео — перший кадр і ▶), «Обкладинка» на першій, хрестик у куті.
private struct MediaTile: View {
    let item: DraftItem
    let cover: Bool
    let remove: (() -> Void)?
    @State private var local: UIImage?

    var body: some View {
        VStack(alignment: .leading, spacing: Space.xs) {
            Color.clear.aspectRatio(1, contentMode: .fit)
                .overlay {
                    if item.origin != .local, let url = item.preview {
                        CachedImage(url: url, maxDimension: 96, fill: true)
                    } else if let local {
                        Image(uiImage: local).resizable().scaledToFill()
                    } else {
                        Palette.surfaceMuted
                    }
                }
                .clipShape(tileShape)
                .overlay(alignment: .center) {
                    if item.video {
                        Image(systemName: "play.fill").font(.system(size: 16, weight: .semibold)).foregroundStyle(.white)
                            .frame(width: 36, height: 36).background(.black.opacity(0.45), in: Circle())
                    }
                }
                .overlay(alignment: .bottomLeading) {
                    if cover {
                        Text(Copy.media_cover).font(PoruchFont.overline).foregroundStyle(.white)
                            .padding(.horizontal, Space.sm).padding(.vertical, 3)
                            .background(.black.opacity(0.55), in: Capsule()).padding(Space.xs)
                    }
                }
                .overlay(alignment: .topTrailing) {
                    if let remove {
                        Button(action: remove) {
                            PoruchIcon(glyph: PoruchIcons.close, size: 12).foregroundStyle(.white)
                                .frame(width: 24, height: 24).background(.black.opacity(0.6), in: Circle())
                                .frame(width: 44, height: 44).contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(Copy.media_remove_a11y)
                        .offset(x: 10, y: -10)
                    }
                }
            if item.trimmed {
                Text(Copy.media_video_trimmed).font(PoruchFont.caption).foregroundStyle(Palette.inkSecondary).lineLimit(2)
            }
        }
        .task(id: item.id) {
            guard item.origin == .local, let file = item.preview else { return }
            local = await DraftMediaPicker.thumbnail(file)
        }
    }
}
