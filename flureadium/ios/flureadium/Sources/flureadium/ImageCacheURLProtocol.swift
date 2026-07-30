import Foundation

/// Caches HTTP responses from Readium's local server for image-based
/// publications (CBZ, DiViNa). Readium's ResourceResponse disables
/// HTTP caching for DRM safety, but CBZ/DiViNa have no DRM — caching
/// is safe and eliminates redundant ZIP extraction + HTTP round-trips
/// on every page turn.
final class ImageCacheURLProtocol: URLProtocol {
    static let handledKey = "ImageCacheURLProtocol.handled"
    private static let cache: NSCache<NSURL, CachedResponse> = {
        let c = NSCache<NSURL, CachedResponse>()
        c.totalCostLimit = 100 * 1024 * 1024 // 100 MB
        c.countLimit = 30
        return c
    }()

    override class func canInit(with request: URLRequest) -> Bool {
        guard
            let url = request.url,
            let host = url.host,
            (host == "localhost" || host == "127.0.0.1"),
            request.httpMethod == "GET",
            URLProtocol.property(
                forKey: handledKey, in: request
            ) == nil
        else { return false }
        return true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        let url = request.url! as NSURL
        if let cached = Self.cache.object(forKey: url) {
            serveCachedResponse(cached, for: url as URL)
            return
        }

        if let prefetched = Self.promotePrefetchToCache(forPath: request.url?.path ?? "", url: url) {
            serveCachedResponse(prefetched, for: url as URL)
            return
        }

        let mutable = (request as NSURLRequest).mutableCopy()
            as! NSMutableURLRequest
        URLProtocol.setProperty(true, forKey: Self.handledKey, in: mutable)

        let task = URLSession.shared.dataTask(with: mutable as URLRequest) {
            [weak self] data, response, error in
            guard let self else { return }
            if let error {
                self.client?.urlProtocol(self, didFailWithError: error)
                return
            }
            if let data, let response {
                let entry = CachedResponse(
                    data: data,
                    mimeType: response.mimeType
                )
                Self.cache.setObject(entry, forKey: url, cost: data.count)

                self.client?.urlProtocol(self, didReceive: response,
                                         cacheStoragePolicy: .notAllowed)
                self.client?.urlProtocol(self, didLoad: data)
            }
            self.client?.urlProtocolDidFinishLoading(self)
        }
        task.resume()
    }

    private func serveCachedResponse(_ cached: CachedResponse, for url: URL) {
        let response = URLResponse(
            url: url,
            mimeType: cached.mimeType,
            expectedContentLength: cached.data.count,
            textEncodingName: nil
        )
        client?.urlProtocol(self, didReceive: response,
                            cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: cached.data)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}

    // MARK: - Public API

    static func enable() {
        URLProtocol.registerClass(ImageCacheURLProtocol.self)
    }

    static func disable() {
        URLProtocol.unregisterClass(ImageCacheURLProtocol.self)
        cache.removeAllObjects()
        clearPrefetchCache()
    }

    static func clearCache() {
        cache.removeAllObjects()
    }

    // MARK: - Prefetch Store

    private static var prefetchStore: [String: CachedResponse] = [:]
    private static let prefetchLock = NSLock()

    static func seedPrefetch(href: String, data: Data, mimeType: String?) {
        let entry = CachedResponse(data: data, mimeType: mimeType)
        prefetchLock.lock()
        defer { prefetchLock.unlock() }
        prefetchStore[href] = entry
    }

    static func hasPrefetch(href: String) -> Bool {
        prefetchLock.lock()
        defer { prefetchLock.unlock() }
        return prefetchStore[href] != nil
    }

    static func clearPrefetchCache() {
        prefetchLock.lock()
        defer { prefetchLock.unlock() }
        prefetchStore.removeAll()
    }

    /// Finds a prefetch entry matching the given URL path, promotes it to the
    /// primary cache, and removes it from the prefetch store -- all atomically
    /// under a single lock.
    private static func promotePrefetchToCache(forPath decodedPath: String, url: NSURL) -> CachedResponse? {
        prefetchLock.lock()
        defer { prefetchLock.unlock() }
        guard let (href, cached) = prefetchEntry(matchingPath: decodedPath) else { return nil }
        cache.setObject(cached, forKey: url, cost: cached.data.count)
        prefetchStore.removeValue(forKey: href)
        return cached
    }

    /// Caller must hold `prefetchLock`.
    private static func prefetchEntry(matchingPath decodedPath: String) -> (String, CachedResponse)? {
        for (href, cached) in prefetchStore {
            let decodedHref = href.removingPercentEncoding ?? href
            if decodedPath.hasSuffix("/\(decodedHref)") {
                return (href, cached)
            }
        }
        return nil
    }

    // MARK: - Test Helpers

    static func seedCache(url: URL, data: Data, mimeType: String?) {
        let entry = CachedResponse(data: data, mimeType: mimeType)
        cache.setObject(entry, forKey: url as NSURL, cost: data.count)
    }

    static func hasCachedResponse(for url: URL) -> Bool {
        cache.object(forKey: url as NSURL) != nil
    }

    static func findPrefetchMatchData(forPath decodedPath: String) -> Data? {
        prefetchLock.lock()
        defer { prefetchLock.unlock() }
        return prefetchEntry(matchingPath: decodedPath)?.1.data
    }
}

// NSCache requires AnyObject values, so this must be a class.
private final class CachedResponse {
    let data: Data
    let mimeType: String?

    init(data: Data, mimeType: String?) {
        self.data = data
        self.mimeType = mimeType
    }
}
