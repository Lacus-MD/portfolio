import Foundation
import ImageIO
import UIKit

/// Loads and decodes news thumbnails away from SwiftUI's render pass.
///
/// `AsyncImage` starts the request lazily, but the first image decode can still
/// land on the frame that is currently scrolling. Keeping a small decoded
/// cache means cells only perform a cheap lookup while the network and image
/// work happen on a utility queue.
final class NewsImagePreloader: @unchecked Sendable {
    static let shared = NewsImagePreloader()

    private let cache = NSCache<NSURL, UIImage>()
    private let queue = DispatchQueue(
        label: "hu.halasz.portfolio.news-image-preloader",
        qos: .utility,
        attributes: .concurrent
    )

    private init() {
        cache.countLimit = 48
        cache.totalCostLimit = 12 * 1024 * 1024
    }

    func image(for url: URL) -> UIImage? {
        cache.object(forKey: url as NSURL)
    }

    /// Starts background work for the next screenful. Existing/in-flight
    /// requests are harmlessly skipped by the cache check.
    func prefetch(_ urls: [URL]) {
        var seen = Set<URL>()
        for url in urls where seen.insert(url).inserted {
            guard image(for: url) == nil else { continue }
            queue.async { [weak self] in
                self?.loadSynchronously(url)
            }
        }
    }

    /// Used by the visible cell when it arrives before the prefetch finishes.
    func load(_ url: URL) async -> UIImage? {
        if let cached = image(for: url) { return cached }

        return await withCheckedContinuation { continuation in
            var request = URLRequest(url: url)
            request.cachePolicy = .returnCacheDataElseLoad
            URLSession.shared.dataTask(with: request) { [weak self] data, _, _ in
                let image = data.flatMap(Self.decode)
                if let image { self?.store(image, for: url) }
                continuation.resume(returning: image)
            }.resume()
        }
    }

    private func loadSynchronously(_ url: URL) {
        guard image(for: url) == nil else { return }
        var request = URLRequest(url: url)
        request.cachePolicy = .returnCacheDataElseLoad
        URLSession.shared.dataTask(with: request) { [weak self] data, _, _ in
            guard let data, let image = Self.decode(data) else { return }
            self?.store(image, for: url)
        }.resume()
    }

    private func store(_ image: UIImage, for url: URL) {
        cache.setObject(image, forKey: url as NSURL, cost: imageCost(image))
    }

    private static func decode(_ data: Data) -> UIImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let cgImage = CGImageSourceCreateThumbnailAtIndex(
                source,
                0,
                [
                    kCGImageSourceCreateThumbnailFromImageAlways: true,
                    kCGImageSourceCreateThumbnailWithTransform: true,
                    kCGImageSourceThumbnailMaxPixelSize: 256
                ] as CFDictionary
              ) else { return nil }
        return UIImage(cgImage: cgImage)
    }

    private func imageCost(_ image: UIImage) -> Int {
        guard let cgImage = image.cgImage else { return 1 }
        return cgImage.bytesPerRow * cgImage.height
    }
}
