import XCTest
@testable import Clearance

final class RemoteDocumentTests: XCTestCase {
    func testStoresRequestedURLAndRenderURLIndependently() {
        let requestedURL = URL(string: "https://example.com/docs")!
        let renderURL = URL(string: "https://example.com/docs/INDEX.md")!

        let document = RemoteDocument(requestedURL: requestedURL, renderURL: renderURL)

        XCTAssertEqual(document.requestedURL, requestedURL)
        XCTAssertEqual(document.renderURL, renderURL)
    }
}
