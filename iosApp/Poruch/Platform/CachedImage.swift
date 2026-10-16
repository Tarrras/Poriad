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
    /// `scaledToFill` у велику рамку: `maxDimension` — найкоротша сторона, а не найдовша. Інакше горизонтальне фото
    /// в обкладинці 480 pt заввишки розпаковувалось на 270 pt і розтягувалось у 1.8 раза.
    var fill = false

    @Environment(\.displayScale) private var displayScale
    @State private var image: UIImage?

    init(url: URL, maxDimension: CGFloat, fill: Bool = false) {
        self.url = url
        self.maxDimension = maxDimension
        self.fill = fill
        // Готове зображення беремо до першого кадру, щоб повернення до картки не блимало.
        _image = State(initialValue: ThumbnailCache.shared.image(for: ThumbnailCache.key(url, maxDimension, fill: fill)))
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
        let key = ThumbnailCache.key(url, maxDimension, fill: fill)
        if let cached = ThumbnailCache.shared.image(for: key) {
            if image !== cached { image = cached }
            return
        }
        let pixels = maxDimension * displayScale
        guard let data = try? await URLSession.shared.data(from: url).0, !Task.isCancelled else { return }
        // Розпакування поза головним потоком: воно коштує кадри.
        let fill = fill
        let rendered = await Task.detached(priority: .utility) { ThumbnailCache.downsample(data, to: pixels, fill: fill) }.value
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

    static func key(_ url: URL, _ maxDimension: CGFloat, fill: Bool = false) -> NSString {
        "\(url.absoluteString)|\(Int(maxDimension))\(fill ? "f" : "")" as NSString
    }

    func image(for key: NSString) -> UIImage? { memory.object(forKey: key) }

    func store(_ image: UIImage, for key: NSString) {
        let cost = image.cgImage.map { $0.bytesPerRow * $0.height } ?? 0
        memory.setObject(image, forKey: key, cost: cost)
    }

    /// Читає одразу в потрібний розмір. `kCGImageSourceShouldCache: false` не дає ImageIO тримати повнорозмірну копію.
    /// `fill`: `maxPixel` — найкоротша сторона; найдовшу рахуємо з пропорцій, не більше за оригінал.
    static func downsample(_ data: Data, to maxPixel: CGFloat, fill: Bool = false) -> UIImage? {
        let sourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithData(data as CFData, sourceOptions) else { return nil }
        var maxPixel = maxPixel
        if fill, let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
           let width = props[kCGImagePropertyPixelWidth] as? CGFloat, let height = props[kCGImagePropertyPixelHeight] as? CGFloat,
           min(width, height) > 0 {
            maxPixel = min(max(width, height), maxPixel * max(width, height) / min(width, height))
        }
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
