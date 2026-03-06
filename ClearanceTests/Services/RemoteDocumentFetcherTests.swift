import XCTest
@testable import Clearance

final class RemoteDocumentFetcherTests: XCTestCase {
    func testResolveForMarkdownRequestAppendsIndexForBareURL() {
        let requestedURL = URL(string: "https://example.com/docs")!

        let document = RemoteDocumentFetcher.resolveForMarkdownRequest(requestedURL)

        XCTAssertEqual(document.requestedURL, requestedURL)
        XCTAssertEqual(document.renderURL, URL(string: "https://example.com/docs/INDEX.md")!)
    }

    func testResolveForMarkdownRequestLeavesMarkdownFileUnchanged() {
        let requestedURL = URL(string: "https://example.com/docs/README.md")!

        let document = RemoteDocumentFetcher.resolveForMarkdownRequest(requestedURL)

        XCTAssertEqual(document.requestedURL, requestedURL)
        XCTAssertEqual(document.renderURL, requestedURL)
    }
}
