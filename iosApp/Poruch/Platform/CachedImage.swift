import SwiftUI
import ImageIO
import UIKit

/**
 Зображення події з пам'яттю й зі зменшенням під розмір показу.

 Системний `AsyncImage` кешу **декодованих** зображень не має. Щойно картка виїхала за край списку
 й повернулась, він читає байти наново і наново розпаковує JPEG — у повний розмір, яким його віддає
 джерело. Афіші приходять розміром 707×1000, тобто ~2.8 МБ пікселів на кожну; у списку їх сотня, і
 кожен прохід туди-назад платить за всі. Coil на Android робить і те, і те сам, тому там цього не
 видно, а тут скрол спотикається.

 Тут два запобіжники. Перший — `NSCache` готових `UIImage`: повернення до вже баченої картки нічого
 не коштує. Другий — розпакування одразу в потрібний розмір через `CGImageSourceCreateThumbnailAtIndex`:
 у рядок 60×60 не потрапляє мільйон пікселів, який усе одно нікуди не помістився б.
 */
struct CachedImage: View {
    let url: URL
    /// Найбільша сторона показу в **точках**. Пікселі рахуються з масштабу екрана під час читання.
    let maxDimension: CGFloat

    @Environment(\.displayScale) private var displayScale
    @State private var image: UIImage?

    init(url: URL, maxDimension: CGFloat) {
        self.url = url
        self.maxDimension = maxDimension
        // Готове зображення підхоплюємо ще до першого кадру: інакше кожне повернення до картки
        // блимало б порожнім місцем, хоча малювати вже є що.
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
        // Розпакування — робота для іншого потоку: воно коштує кадри, а не мілісекунди.
        let rendered = await Task.detached(priority: .utility) { ThumbnailCache.downsample(data, to: pixels) }.value
        guard let rendered, !Task.isCancelled else { return }
        ThumbnailCache.shared.store(rendered, for: key)
        image = rendered
    }
}

/// Готові зображення, спільні для всіх екранів. Обмеження — за пікселями, а не за кількістю:
/// сто мініатюр рядка й сто обкладинок карток коштують геть різного.
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

    /// Читає файл одразу в потрібний розмір. `kCGImageSourceShouldCache: false` на джерелі не дає
    /// ImageIO тримати ще й повнорозмірну копію, яка тут нікому не потрібна.
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
