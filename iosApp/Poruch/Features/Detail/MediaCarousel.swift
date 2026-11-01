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

    var body: some View {
        ScrollView(.horizontal) {
            LazyHStack(spacing: 0) {
                ForEach(Array(media.enumerated()), id: \.offset) { index, item in
                    page(item)
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
    }

    @ViewBuilder private func page(_ item: EventMedia) -> some View {
        if item.kind == .video, let url = URL(string: item.url) {
            // Постер під відео: перші кадри ще в дорозі, а чорна сторінка виглядала б зламаною.
            ZStack {
                if let poster = item.poster.flatMap(URL.init(string:)) { CachedImage(url: poster, maxDimension: heroHeight, fill: true) }
                LoopingVideo(url: url)
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

/// Відео на весь екран зі звуком: системний плеєр і «закрити». Сесія `playback`, щоб звук був і з вимкненим дзвінком.
private struct FullScreenVideo: View {
    let url: URL
    @Environment(\.dismiss) private var dismiss
    @State private var player: AVPlayer

    init(url: URL) {
        self.url = url
        _player = State(initialValue: AVPlayer(url: url))
    }

    var body: some View {
        VideoPlayer(player: player)
            .ignoresSafeArea()
            .background(Color.black.ignoresSafeArea())
            .overlay(alignment: .topLeading) {
                IconPill(glyph: PoruchIcons.close, label: Copy.close, size: 40) { dismiss() }.padding(Space.page)
            }
            .onAppear {
                try? AVAudioSession.sharedInstance().setCategory(.playback)
                player.play()
            }
            .onDisappear {
                player.pause()
                try? AVAudioSession.sharedInstance().setCategory(.ambient, options: [.mixWithOthers])
            }
    }
}
