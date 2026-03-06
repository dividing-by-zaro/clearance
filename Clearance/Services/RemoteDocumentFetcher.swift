import Foundation

enum RemoteDocumentFetcher {
    static func resolveForMarkdownRequest(_ requestedURL: URL) -> RemoteDocument {
        RemoteDocument(
            requestedURL: requestedURL,
            renderURL: resolveRenderURL(for: requestedURL)
        )
    }

    private static func resolveRenderURL(for requestedURL: URL) -> URL {
        guard requestedURL.pathExtension.isEmpty else {
            return requestedURL
        }

        return requestedURL.appendingPathComponent("INDEX.md")
    }
}
