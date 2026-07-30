import XCTest
@testable import flureadium

final class ImageCacheURLProtocolTests: XCTestCase {

    override func setUp() {
        super.setUp()
        ImageCacheURLProtocol.disable()
    }

    override func tearDown() {
        URLProtocol.unregisterClass(StubForwardURLProtocol.self)
        ImageCacheURLProtocol.disable()
        super.tearDown()
    }

    // MARK: - canInit

    func testCanInitReturnsTrueForLocalhostGET() {
        let request = URLRequest(url: URL(string: "http://localhost:8080/image.jpg")!)
        XCTAssertTrue(ImageCacheURLProtocol.canInit(with: request))
    }

    func testCanInitReturnsTrueFor127001GET() {
        let request = URLRequest(url: URL(string: "http://127.0.0.1:8080/image.jpg")!)
        XCTAssertTrue(ImageCacheURLProtocol.canInit(with: request))
    }

    func testCanInitReturnsFalseForNonLocalhost() {
        let request = URLRequest(url: URL(string: "https://example.com/image.jpg")!)
        XCTAssertFalse(ImageCacheURLProtocol.canInit(with: request))
    }

    func testCanInitReturnsFalseForPOST() {
        var request = URLRequest(url: URL(string: "http://localhost:8080/image.jpg")!)
        request.httpMethod = "POST"
        XCTAssertFalse(ImageCacheURLProtocol.canInit(with: request))
    }

    func testCanInitReturnsFalseForAlreadyHandledRequest() {
        let url = URL(string: "http://localhost:8080/image.jpg")!
        let mutable = NSMutableURLRequest(url: url)
        URLProtocol.setProperty(true, forKey: "ImageCacheURLProtocol.handled", in: mutable)
        XCTAssertFalse(ImageCacheURLProtocol.canInit(with: mutable as URLRequest))
    }

    // MARK: - Cache hit

    func testCacheHitReturnsCachedDataWithoutNetwork() {
        let expectation = self.expectation(description: "Cache hit")
        let url = URL(string: "http://localhost:19876/cached-image.jpg")!

        ImageCacheURLProtocol.seedCache(url: url, data: Data([0xFF, 0xD8, 0xFF, 0xE0]), mimeType: "image/jpeg")

        ImageCacheURLProtocol.enable()

        let task = URLSession.shared.dataTask(with: url) { data, _, error in
            XCTAssertNil(error)
            XCTAssertEqual(data, Data([0xFF, 0xD8, 0xFF, 0xE0]))
            expectation.fulfill()
        }
        task.resume()

        waitForExpectations(timeout: 5)
    }

    // MARK: - clearCache

    func testClearCacheRemovesAllEntries() {
        let url = URL(string: "http://localhost:19876/test-image.jpg")!
        ImageCacheURLProtocol.seedCache(url: url, data: Data([0x01, 0x02]), mimeType: "image/png")
        XCTAssertTrue(ImageCacheURLProtocol.hasCachedResponse(for: url))

        ImageCacheURLProtocol.clearCache()

        XCTAssertFalse(ImageCacheURLProtocol.hasCachedResponse(for: url))
    }

    // MARK: - enable / disable

    func testEnableRegistersProtocol() {
        ImageCacheURLProtocol.enable()
        // After enable, canInit should still work (protocol is registered).
        let request = URLRequest(url: URL(string: "http://localhost:8080/image.jpg")!)
        XCTAssertTrue(ImageCacheURLProtocol.canInit(with: request))
    }

    func testDisableUnregistersAndClearsCache() {
        let url = URL(string: "http://localhost:19876/disable-test.jpg")!
        ImageCacheURLProtocol.seedCache(url: url, data: Data([0x01]), mimeType: "image/jpeg")
        XCTAssertTrue(ImageCacheURLProtocol.hasCachedResponse(for: url))

        ImageCacheURLProtocol.disable()

        XCTAssertFalse(ImageCacheURLProtocol.hasCachedResponse(for: url))
    }

    // MARK: - Cache miss (stubbed downstream)

    func testCacheMissForwardsRequestAndCachesResponse() {
        let expectation = self.expectation(description: "Cache miss forwards and caches")
        let url = StubForwardURLProtocol.stubbedURL

        ImageCacheURLProtocol.enable()
        URLProtocol.registerClass(StubForwardURLProtocol.self)

        // Cache miss: ImageCacheURLProtocol forwards the tagged request to the
        // stub, which returns a canned response. The protocol must deliver that
        // response and cache it for next time -- no real network involved, so
        // the outcome does not depend on connection timing.
        let task = URLSession.shared.dataTask(with: url) { data, _, error in
            XCTAssertNil(error)
            XCTAssertEqual(data, StubForwardURLProtocol.stubbedData)
            expectation.fulfill()
        }
        task.resume()

        waitForExpectations(timeout: 5)
        XCTAssertTrue(ImageCacheURLProtocol.hasCachedResponse(for: url))
    }

    // MARK: - Prefetch store

    func testSeedPrefetchStoresData() {
        ImageCacheURLProtocol.seedPrefetch(href: "page.jpg", data: Data([0x01, 0x02]), mimeType: "image/jpeg")
        XCTAssertTrue(ImageCacheURLProtocol.hasPrefetch(href: "page.jpg"))
    }

    func testHasPrefetchReturnsFalseForUnknown() {
        XCTAssertFalse(ImageCacheURLProtocol.hasPrefetch(href: "unknown.jpg"))
    }

    func testClearPrefetchCacheRemovesAll() {
        ImageCacheURLProtocol.seedPrefetch(href: "a.jpg", data: Data([0x01]), mimeType: "image/jpeg")
        ImageCacheURLProtocol.seedPrefetch(href: "b.jpg", data: Data([0x02]), mimeType: "image/jpeg")
        XCTAssertTrue(ImageCacheURLProtocol.hasPrefetch(href: "a.jpg"))
        XCTAssertTrue(ImageCacheURLProtocol.hasPrefetch(href: "b.jpg"))

        ImageCacheURLProtocol.clearPrefetchCache()

        XCTAssertFalse(ImageCacheURLProtocol.hasPrefetch(href: "a.jpg"))
        XCTAssertFalse(ImageCacheURLProtocol.hasPrefetch(href: "b.jpg"))
    }

    func testFindPrefetchMatchReturnsCachedDataForSuffixMatch() {
        ImageCacheURLProtocol.seedPrefetch(href: "page.jpg", data: Data([0xAA]), mimeType: "image/jpeg")

        let match = ImageCacheURLProtocol.findPrefetchMatchData(forPath: "/some-uuid/page.jpg")

        XCTAssertNotNil(match)
        XCTAssertEqual(match, Data([0xAA]))
    }

    func testFindPrefetchMatchReturnsCachedDataForSubdirectoryHref() {
        ImageCacheURLProtocol.seedPrefetch(href: "images/page.jpg", data: Data([0xBB]), mimeType: "image/jpeg")

        let match = ImageCacheURLProtocol.findPrefetchMatchData(forPath: "/some-uuid/images/page.jpg")

        XCTAssertNotNil(match)
        XCTAssertEqual(match, Data([0xBB]))
    }

    func testFindPrefetchMatchReturnsNilForNoMatch() {
        ImageCacheURLProtocol.seedPrefetch(href: "page1.jpg", data: Data([0x01]), mimeType: "image/jpeg")

        let match = ImageCacheURLProtocol.findPrefetchMatchData(forPath: "/some-uuid/page2.jpg")

        XCTAssertNil(match)
    }

    func testFindPrefetchMatchHandlesPercentEncodedHrefs() {
        ImageCacheURLProtocol.seedPrefetch(href: "My%20Image.jpg", data: Data([0xCC]), mimeType: "image/jpeg")

        let match = ImageCacheURLProtocol.findPrefetchMatchData(forPath: "/some-uuid/My Image.jpg")

        XCTAssertNotNil(match)
        XCTAssertEqual(match, Data([0xCC]))
    }

    func testDisableClearsBothCaches() {
        let url = URL(string: "http://localhost:19876/primary.jpg")!
        ImageCacheURLProtocol.seedCache(url: url, data: Data([0x01]), mimeType: "image/jpeg")
        ImageCacheURLProtocol.seedPrefetch(href: "prefetched.jpg", data: Data([0x02]), mimeType: "image/jpeg")
        XCTAssertTrue(ImageCacheURLProtocol.hasCachedResponse(for: url))
        XCTAssertTrue(ImageCacheURLProtocol.hasPrefetch(href: "prefetched.jpg"))

        ImageCacheURLProtocol.disable()

        XCTAssertFalse(ImageCacheURLProtocol.hasCachedResponse(for: url))
        XCTAssertFalse(ImageCacheURLProtocol.hasPrefetch(href: "prefetched.jpg"))
    }

    func testPrefetchHitPromotesToPrimaryCache() {
        let expectation = self.expectation(description: "Prefetch hit promotes")
        let url = URL(string: "http://localhost:19876/prefetch-promote.jpg")!
        let imageData = Data([0xFF, 0xD8, 0xFF, 0xE0])

        ImageCacheURLProtocol.seedPrefetch(href: "prefetch-promote.jpg", data: imageData, mimeType: "image/jpeg")
        ImageCacheURLProtocol.enable()

        let task = URLSession.shared.dataTask(with: url) { data, _, error in
            XCTAssertNil(error)
            XCTAssertEqual(data, imageData)

            // Promoted to primary cache
            XCTAssertTrue(ImageCacheURLProtocol.hasCachedResponse(for: url))
            // Removed from prefetch store
            XCTAssertFalse(ImageCacheURLProtocol.hasPrefetch(href: "prefetch-promote.jpg"))

            expectation.fulfill()
        }
        task.resume()

        waitForExpectations(timeout: 5)
    }
}

/// Test-only downstream protocol that answers the request
/// `ImageCacheURLProtocol` forwards on a cache miss (the one tagged with
/// `handledKey`). Serving the forwarded request in-process removes the real
/// network connection, so the cache-miss path is exercised deterministically.
private final class StubForwardURLProtocol: URLProtocol {
    static let stubbedURL = URL(string: "http://localhost:19999/nonexistent.jpg")!
    static let stubbedData = Data([0xFF, 0xD8, 0xFF, 0xE1])

    override class func canInit(with request: URLRequest) -> Bool {
        URLProtocol.property(forKey: ImageCacheURLProtocol.handledKey, in: request) != nil
            && request.url == stubbedURL
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        let response = HTTPURLResponse(
            url: Self.stubbedURL,
            statusCode: 200,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "image/jpeg"]
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Self.stubbedData)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
