import SwiftUI
import ImageIO
import UIKit

/// Зображення з кешем декодованих `UIImage` і зменшенням під розмір показу. `AsyncImage` такого
/// кешу не має і розпаковує повнорозмірний JPEG щоразу, коли картка повертається на екран;
/// Coil на Android робить обидва сам.
struct CachedImage: View {
    let url: URL
    /// Найбільша сторона показу в pt. Пікселі рахуються з масштабу екрана.
    let maxDimension: CGFloat

    @Environment(\.displayScale) private var displayScale
    @State private var image: UIImage?

    init(url: URL, maxDimension: CGFloat) {
        self.url = url
        self.maxDimension = maxDimension
        // Готове зображення беремо до першого кадру, щоб повернення до картки не блимало.
        _image = State(initialValue: ThumbnailCache.shared.image(for: ThumbnailCache.key(url, maxDimension)))
    }

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image).resizable().scaledToFill()
            } else {
                Color.clear
            }
        }
        // `.task(id:)` сам скасовує читання, коли картка залишає екран.
        .task(id: url) { await load() }
    }

    private func load() async {
        let key = ThumbnailCache.key(url, maxDimension)
        if let cached = ThumbnailCache.shared.image(for: key) {
            if image !== cached { image = cached }
            return
        }
        let pixels = maxDimension * displayScale
        guard let data = try? await URLSession.shared.data(from: url).0, !Task.isCancelled else { return }
        // Розпакування поза головним потоком: воно коштує кадри.
        let rendered = await Task.detached(priority: .utility) { ThumbnailCache.downsample(data, to: pixels) }.value
        guard let rendered, !Task.isCancelled else { return }
        ThumbnailCache.shared.store(rendered, for: key)
        image = rendered
    }
}

/// Спільний кеш готових зображень. Ліміт за пікселями, а не за кількістю.
final class ThumbnailCache {
    static let shared = ThumbnailCache()

    private let memory = NSCache<NSString, UIImage>()

    private init() {
        memory.totalCostLimit = 64 * 1024 * 1024
    }

    static func key(_ url: URL, _ maxDimension: CGFloat) -> NSString {
        "\(url.absoluteString)|\(Int(maxDimension))" as NSString
    }

    func image(for key: NSString) -> UIImage? { memory.object(forKey: key) }

    func store(_ image: UIImage, for key: NSString) {
        let cost = image.cgImage.map { $0.bytesPerRow * $0.height } ?? 0
        memory.setObject(image, forKey: key, cost: cost)
    }

    /// Читає одразу в потрібний розмір. `kCGImageSourceShouldCache: false` не дає ImageIO тримати повнорозмірну копію.
    static func downsample(_ data: Data, to maxPixel: CGFloat) -> UIImage? {
        let sourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithData(data as CFData, sourceOptions) else { return nil }
        let options = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: max(1, maxPixel)
        ] as CFDictionary
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options) else { return nil }
        return UIImage(cgImage: cgImage)
    }
}
