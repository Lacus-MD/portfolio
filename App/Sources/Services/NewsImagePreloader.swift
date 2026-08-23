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
    private let stateQueue = DispatchQueue(label: "hu.halasz.portfolio.news-image-state")
    private var waiters: [URL: [(UIImage?) -> Void]] = [:]

    /// Két dekódolásnál több egyszerre nem futhat. Az előző megoldás negyven
    /// `URLSession.shared` feladatot indított el azonnal; ugyan háttérszálon
    /// dolgoztak, de együtt elfoglalták a CPU-t és a memória-sávszélességet,
    /// amitől az előtérben minden fül görgetése megakadt.
    private let session: URLSession = {
        let configuration = URLSessionConfiguration.default
        configuration.requestCachePolicy = .returnCacheDataElseLoad
        configuration.urlCache = .shared
        configuration.httpMaximumConnectionsPerHost = 2
        configuration.timeoutIntervalForRequest = 20

        let delegateQueue = OperationQueue()
        delegateQueue.name = "hu.halasz.portfolio.news-image-decode"
        delegateQueue.qualityOfService = .utility
        delegateQueue.maxConcurrentOperationCount = 2
        return URLSession(configuration: configuration,
                          delegate: nil,
                          delegateQueue: delegateQueue)
    }()

    private init() {
        cache.countLimit = 48
        cache.totalCostLimit = 12 * 1024 * 1024
    }

    func image(for url: URL) -> UIImage? {
        cache.object(forKey: url as NSURL)
    }

    /// Csak a következő néhány képernyőnyi képet készíti elő. A többi majd
    /// akkor jön, amikor tényleg közel kerül a látható tartományhoz.
    func prefetch(_ urls: [URL]) {
        var seen = Set<URL>()
        let nextScreenful = urls.filter { seen.insert($0).inserted }.prefix(16)
        for url in nextScreenful {
            guard image(for: url) == nil else { continue }
            request(url) { _ in }
        }
    }

    /// Used by the visible cell when it arrives before the prefetch finishes.
    func load(_ url: URL) async -> UIImage? {
        if let cached = image(for: url) { return cached }

        return await withCheckedContinuation { continuation in
            request(url) { image in
                continuation.resume(returning: image)
            }
        }
    }

    /// Azonos URL-hez csak egy hálózati/dekódoló feladat fut; az előtöltő és
    /// a látható cella ugyanannak az eredményére vár. Így gyors görgetésnél
    /// sem duplázzuk meg a munkát.
    private func request(_ url: URL, completion: @escaping (UIImage?) -> Void) {
        if let cached = image(for: url) {
            completion(cached)
            return
        }

        stateQueue.async { [weak self] in
            guard let self else { return }
            if let cached = self.image(for: url) {
                completion(cached)
                return
            }
            if self.waiters[url] != nil {
                self.waiters[url]?.append(completion)
                return
            }
            self.waiters[url] = [completion]

            var urlRequest = URLRequest(url: url)
            urlRequest.cachePolicy = .returnCacheDataElseLoad
            self.session.dataTask(with: urlRequest) { [weak self] data, response, _ in
                let status = (response as? HTTPURLResponse)?.statusCode ?? 0
                let image = (200..<300).contains(status) ? data.flatMap(Self.decode) : nil
                if let image { self?.store(image, for: url) }
                self?.finish(url, image: image)
            }.resume()
        }
    }

    private func finish(_ url: URL, image: UIImage?) {
        stateQueue.async { [weak self] in
            guard let self else { return }
            let completions = self.waiters.removeValue(forKey: url) ?? []
            completions.forEach { $0(image) }
        }
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
