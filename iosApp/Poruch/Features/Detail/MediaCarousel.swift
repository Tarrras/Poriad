import AVFoundation
import AVKit
import SwiftUI
import Shared

/// Фото й відео організатора замість обкладинки (docs/organizers-1.5.md, «Показ»): гортаються вбік, відео грає без
/// звуку в циклі, тап по ньому — на весь екран зі звуком. Сторінка заввишки з обкладинку й від краю екрана, як
/// `HeroBackdrop` під нею: на першій сторінці шви не видно, а смугу під годинником малює він же з тією сторінкою, що зараз.
struct MediaCarousel: View {
    let media: [EventMedia]
    let scroll: DetailScroll
    @State private var playing: PlayingVideo?
    /// Зверху відкрили інший екран: відео під ним не грає.
    @State private var onScreen = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Без автозапуску (Reduce Motion чи вимкнений «Автовідтворення відео») — лише постер; тап однаково відкриває відео.
    /// Грає, лише поки обкладинку видно й екран зверху.
    private var autoplay: Bool {
        !reduceMotion && UIAccessibility.isVideoAutoplayEnabled && onScreen && scroll.heroVisible && playing == nil
    }

    var body: some View {
        ScrollView(.horizontal) {
            LazyHStack(spacing: 0) {
                ForEach(Array(media.enumerated()), id: \.offset) { index, item in
                    // Грає й вантажить лише поточна сторінка: сусідні LazyHStack створює наперед, а кожен перегляд — трафік Storage.
                    page(item, playing: autoplay && index == scroll.mediaPage)
                        .containerRelativeFrame(.horizontal)
                        .frame(height: heroHeight).clipped()
                        .id(index)
                }
            }
            .scrollTargetLayout()
        }
        .scrollTargetBehavior(.paging)
        .scrollIndicators(.hidden)
        .scrollPosition(id: Binding(get: { scroll.mediaPage }, set: { scroll.mediaPage = $0 ?? 0 }))
        // Назва лежить на затемненні, як на обкладинці. Дотиків не забирає.
        .overlay(photoScrim.allowsHitTesting(false))
        .fullScreenCover(item: $playing) { FullScreenVideo(url: $0.url) }
        .onAppear { onScreen = true }
        .onDisappear { onScreen = false }
    }

    @ViewBuilder private func page(_ item: EventMedia, playing live: Bool) -> some View {
        if item.kind == .video, let url = URL(string: item.url) {
            // Постер під відео: перші кадри ще в дорозі, а чорна сторінка виглядала б зламаною.
            ZStack {
                if let poster = item.poster.flatMap(URL.init(string:)) { CachedImage(url: poster, maxDimension: heroHeight, fill: true) }
                if live { CachedVideo(remote: url) }
            }
                .contentShape(Rectangle())
                .onTapGesture { playing = PlayingVideo(url: url) }
                .accessibilityElement()
                .accessibilityLabel(Copy.media_play_a11y)
                .accessibilityAddTraits(.isButton)
                .accessibilityAction { playing = PlayingVideo(url: url) }
        } else if let url = URL(string: item.url) {
            CachedImage(url: url, maxDimension: heroHeight, fill: true).decorative()
        }
    }
}

/// Крапки сторінок каруселі: між «назад» і закладкою, де їх не перекриває назва.
struct MediaDots: View {
    let count: Int
    let scroll: DetailScroll
    var body: some View {
        HStack(spacing: 6) {
            ForEach(0..<count, id: \.self) { index in
                Circle().fill(.white.opacity(index == scroll.mediaPage ? 1 : 0.45)).frame(width: 7, height: 7)
            }
        }
        .padding(.horizontal, Space.sm).padding(.vertical, 6)
        .background(.black.opacity(0.25), in: Capsule())
        .decorative()
    }
}

private struct PlayingVideo: Identifiable {
    let url: URL
    var id: URL { url }
}

/// Відео сторінки з кешу на диску: доки файл їде, видно постер під ним.
private struct CachedVideo: View {
    let remote: URL
    @State private var local: URL?
    var body: some View {
        // Основа — прозора, а не порожній Group: на порожньому `.task` не стартує.
        Color.clear
            .overlay { if let local { LoopingVideo(url: local) } }
            .task(id: remote) { local = await VideoCache.file(for: remote) }
    }
}

/// Відео каруселі файлом у Caches: петля, повернення на сторінку й повторне відкриття події грають з диска, а не тягнуть
/// файл зі Storage знову — кожен перегляд там наш трафік, а Spend Cap обмежує весь проєкт (docs/organizers-1.5.md, 1.3).
/// Коли разом понад [limit], геть те, що грало найдавніше.
enum VideoCache {
    /// З запасом на кілька відео з кабінету (до 50 МБ без стиснення) і на десятки з застосунку (до 8 МБ).
    private static let limit = 100 * 1024 * 1024
    private static let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 15
        config.timeoutIntervalForResource = 120
        return URLSession(configuration: config)
    }()

    private static var directory: URL {
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        let directory = base.appendingPathComponent("event-videos", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    /// Локальний файл відео: з кешу або щойно завантажений. Не вийшло — nil, і сторінка лишається постером.
    static func file(for remote: URL) async -> URL? {
        // Подія й імʼя файлу: імена — uuid, тож збігу між подіями нема, а адреса бакета лишається поза іменем.
        let file = directory.appendingPathComponent(remote.pathComponents.suffix(2).joined(separator: "-"))
        if FileManager.default.fileExists(atPath: file.path) {
            try? FileManager.default.setAttributes([.modificationDate: Date()], ofItemAtPath: file.path)
            return file
        }
        guard let (temp, response) = try? await session.download(from: remote),
              (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }
        if (try? FileManager.default.moveItem(at: temp, to: file)) == nil { try? FileManager.default.removeItem(at: temp) }
        prune()
        return FileManager.default.fileExists(atPath: file.path) ? file : nil
    }

    private static func prune() {
        let keys: [URLResourceKey] = [.contentModificationDateKey, .fileSizeKey]
        let files = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: keys)) ?? []
        let sorted = files.compactMap { url -> (URL, Date, Int)? in
            guard let values = try? url.resourceValues(forKeys: Set(keys)) else { return nil }
            return (url, values.contentModificationDate ?? .distantPast, values.fileSize ?? 0)
        }.sorted { $0.1 > $1.1 }
        var total = 0
        for (url, _, size) in sorted {
            total += size
            if total > limit { try? FileManager.default.removeItem(at: url) }
        }
    }
}

/// Відео без звуку в циклі, без елементів керування. Чужої музики не перебиває: сесія `ambient`.
struct LoopingVideo: UIViewRepresentable {
    let url: URL

    func makeUIView(context: Context) -> PlayerView {
        try? AVAudioSession.sharedInstance().setCategory(.ambient, options: [.mixWithOthers])
        let view = PlayerView()
        let player = AVQueuePlayer()
        player.isMuted = true
        // Не тягнути весь файл наперед: кожен перегляд — трафік Storage (1.3).
        player.automaticallyWaitsToMinimizeStalling = true
        context.coordinator.looper = AVPlayerLooper(player: player, templateItem: AVPlayerItem(url: url))
        view.player.player = player
        view.player.videoGravity = .resizeAspectFill
        player.play()
        return view
    }

    func updateUIView(_ view: PlayerView, context: Context) {}

    static func dismantleUIView(_ view: PlayerView, coordinator: Coordinator) {
        view.player.player?.pause()
        coordinator.looper = nil
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator {
        var looper: AVPlayerLooper?
    }

    final class PlayerView: UIView {
        override static var layerClass: AnyClass { AVPlayerLayer.self }
        var player: AVPlayerLayer { layer as! AVPlayerLayer }
    }
}

/// Відео на весь екран зі звуком: системний плеєр і «закрити». Сесія `playback`, щоб звук був і з вимкненим дзвінком;
/// після — сесію віддаємо, і музика людини грає далі. Плеєр — з появою екрана, а не в `init`, який SwiftUI кличе часто.
private struct FullScreenVideo: View {
    let url: URL
    @Environment(\.dismiss) private var dismiss
    @State private var player: AVPlayer?

    var body: some View {
        VideoPlayer(player: player)
            .ignoresSafeArea()
            .background(Color.black.ignoresSafeArea())
            .overlay(alignment: .topLeading) {
                IconPill(glyph: PoruchIcons.close, label: Copy.close, size: 40) { dismiss() }.padding(Space.page)
            }
            .onAppear {
                try? AVAudioSession.sharedInstance().setCategory(.playback)
                let player = AVPlayer(url: url)
                self.player = player
                player.play()
            }
            .onDisappear {
                player?.pause()
                player = nil
                let session = AVAudioSession.sharedInstance()
                try? session.setActive(false, options: .notifyOthersOnDeactivation)
                try? session.setCategory(.ambient, options: [.mixWithOthers])
            }
    }
}
