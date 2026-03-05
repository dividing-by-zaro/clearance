import AppKit
import SwiftUI
import WebKit

struct WorkspaceView: View {
    @StateObject private var viewModel: WorkspaceViewModel
    @StateObject private var interactionState = WorkspaceInteractionState()
    @State private var isPopOutDropTargeted = false
    @State private var isOutlineVisible = true
    @State private var renderedFindQuery = ""
    @State private var isRenderedSearchPresented = false
    @State private var headingScrollSequence = 0
    @State private var headingScrollRequest: HeadingScrollRequest?
    private let popoutWindowController: PopoutWindowController

    init(
        appSettings: AppSettings = AppSettings(),
        popoutWindowController: PopoutWindowController = PopoutWindowController()
    ) {
        _viewModel = StateObject(wrappedValue: WorkspaceViewModel(appSettings: appSettings))
        self.popoutWindowController = popoutWindowController
    }

    var body: some View {
        NavigationSplitView {
            RecentFilesSidebar(
                entries: viewModel.recentFilesStore.entries,
                selectedPath: $viewModel.selectedRecentPath,
                onOpenFile: { viewModel.promptAndOpenFile() }
            ) { entry in
                selectRecentEntry(entry)
            } onOpenInNewWindow: { entry in
                popOut(entry: entry)
            }
        } detail: {
            Group {
                if let session = viewModel.activeSession {
                    let parsed = FrontmatterParser().parse(markdown: session.content)
                    HSplitView {
                        DocumentSurfaceView(
                            session: session,
                            parsedDocument: parsed,
                            headingScrollRequest: headingScrollRequest,
                            mode: $viewModel.mode
                        )
                        .frame(maxWidth: .infinity, maxHeight: .infinity)

                        if shouldShowOutline(for: parsed) {
                            MarkdownOutlineView(headings: parsed.headings) { heading in
                                requestScroll(to: heading)
                            }
                            .transition(.move(edge: .trailing).combined(with: .opacity))
                        }
                    }
                    .animation(.snappy(duration: 0.2), value: shouldShowOutline(for: parsed))
                } else {
                    ContentUnavailableView {
                        Label {
                            Text("Open a Markdown File")
                        } icon: {
                            Group {
                                if let appIcon = NSApp.applicationIconImage {
                                    Image(nsImage: appIcon)
                                        .resizable()
                                        .interpolation(.high)
                                        .frame(width: 64, height: 64)
                                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                                } else {
                                    Image(systemName: "doc.text")
                                }
                            }
                        }
                    } description: {
                        Text("Choose a file from the sidebar, or open one directly.")
                    } actions: {
                        Button("Open Markdown…") {
                            viewModel.promptAndOpenFile()
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .overlay(alignment: .topTrailing) {
                if isPopOutDropTargeted {
                    Label("Drop To Pop Out", systemImage: "arrow.up.forward.square")
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                        .background(.thinMaterial, in: Capsule())
                        .padding(12)
                }
            }
            .dropDestination(for: String.self) { items, _ in
                guard let path = items.first else {
                    return false
                }

                return popOutDraggedPath(path)
            } isTargeted: { isTargeted in
                isPopOutDropTargeted = isTargeted
            }
            .navigationTitle(viewModel.windowTitle)
            .alert("File Changed On Disk", isPresented: Binding(
                get: { viewModel.externalChangeDocumentName != nil },
                set: { _ in }
            ), actions: {
                Button("Reload") {
                    viewModel.reloadActiveFromDisk()
                }
                Button("Keep Current", role: .cancel) {
                    viewModel.keepCurrentVersionAfterExternalChange()
                }
            }, message: {
                Text("“\(viewModel.externalChangeDocumentName ?? "This file")” changed outside Clearance.")
            })
        }
        .focusedSceneValue(\.workspaceCommandActions, WorkspaceCommandActions(
            openFile: { viewModel.promptAndOpenFile() },
            toggleOutline: { if canShowOutlineControls { isOutlineVisible.toggle() } },
            showViewMode: { if viewModel.activeSession != nil { viewModel.mode = .view } },
            showEditMode: { if viewModel.activeSession != nil { viewModel.mode = .edit } },
            openInNewWindow: { popOutActiveSession() },
            findInDocument: { performFindInDocument() },
            findPreviousInDocument: { performFindPreviousInDocument() },
            printDocument: { performPrint() },
            hasActiveSession: viewModel.activeSession != nil,
            hasVisibleOutline: isOutlineVisible,
            canShowOutline: canShowOutlineControls
        ))
        .toolbarRole(.editor)
        .toolbar {
            if canShowOutlineControls {
                ToolbarItem(placement: .automatic) {
                    Button {
                        isOutlineVisible.toggle()
                    } label: {
                        Label(
                            isOutlineVisible ? "Hide Outline" : "Show Outline",
                            systemImage: "sidebar.right"
                        )
                    }
                }
            }
            ToolbarItem(placement: .primaryAction) {
                Button {
                    viewModel.mode = viewModel.mode == .view ? .edit : .view
                } label: {
                    Label(
                        viewModel.mode == .edit ? "Done" : "Edit",
                        systemImage: viewModel.mode == .edit ? "checkmark" : "square.and.pencil"
                    )
                }
                .disabled(viewModel.activeSession == nil)
            }
        }
        .searchable(
            text: $renderedFindQuery,
            isPresented: $isRenderedSearchPresented,
            placement: .toolbar,
            prompt: "Find In Document"
        )
        .onSubmit(of: .search) {
            if viewModel.mode == .view {
                performRenderedSearch(for: renderedFindQuery, backwards: false)
            }
        }
        .onChange(of: renderedFindQuery) { _, newValue in
            if viewModel.mode == .view {
                performRenderedSearch(for: newValue, backwards: false)
            }
        }
        .onChange(of: viewModel.mode) { _, mode in
            if mode != .view {
                isRenderedSearchPresented = false
            }
        }
        .onChange(of: viewModel.activeSession?.id) { _, _ in
            headingScrollRequest = nil
        }
        .onReceive(NotificationCenter.default.publisher(for: .clearanceOpenURLs)) { notification in
            guard let urls = notification.object as? [URL],
                  let firstURL = urls.first else {
                return
            }

            viewModel.open(url: firstURL)
        }
        .alert("Could Not Open File", isPresented: Binding(
            get: { viewModel.errorMessage != nil },
            set: { isPresented in
                if !isPresented {
                    viewModel.errorMessage = nil
                }
            }
        ), actions: {
            Button("OK", role: .cancel) {
                viewModel.errorMessage = nil
            }
        }, message: {
            Text(viewModel.errorMessage ?? "")
        })
    }

    private func popOutActiveSession() {
        guard let session = viewModel.activeSession else {
            return
        }

        popoutWindowController.openWindow(for: session, mode: viewModel.mode)
    }

    private func popOut(entry: RecentFileEntry) {
        if let session = viewModel.open(recentEntry: entry) {
            popoutWindowController.openWindow(for: session, mode: viewModel.mode)
        }
    }

    private func selectRecentEntry(_ entry: RecentFileEntry) {
        let activePath = viewModel.activeSession?.url.standardizedFileURL.path
        if activePath == entry.path {
            viewModel.selectedRecentPath = entry.path
            return
        }

        viewModel.open(recentEntry: entry)
    }

    private func popOutDraggedPath(_ path: String) -> Bool {
        if let entry = viewModel.recentFilesStore.entries.first(where: { $0.path == path }) {
            popOut(entry: entry)
            return true
        }

        let url = URL(fileURLWithPath: path)
        guard let session = viewModel.open(url: url) else {
            return false
        }

        popoutWindowController.openWindow(for: session, mode: viewModel.mode)
        return true
    }

    private func requestScroll(to heading: MarkdownHeading) {
        headingScrollSequence += 1
        headingScrollRequest = HeadingScrollRequest(
            headingIndex: heading.index,
            sequence: headingScrollSequence
        )
    }

    private func shouldShowOutline(for parsed: ParsedMarkdownDocument) -> Bool {
        isOutlineVisible && viewModel.mode == .view && !parsed.headings.isEmpty
    }

    private var canShowOutlineControls: Bool {
        guard viewModel.mode == .view,
              let session = viewModel.activeSession else {
            return false
        }

        let parsed = FrontmatterParser().parse(markdown: session.content)
        return !parsed.headings.isEmpty
    }

    private func performFindInDocument() -> Bool {
        if viewModel.mode == .view {
            isRenderedSearchPresented = true
            if !renderedFindQuery.isEmpty {
                performRenderedSearch(for: renderedFindQuery, backwards: false)
            }
            return true
        }

        let findMenuItem = NSMenuItem()
        findMenuItem.tag = NSTextFinder.Action.showFindInterface.rawValue
        if NSApp.sendAction(#selector(NSResponder.performTextFinderAction(_:)), to: nil, from: findMenuItem) {
            return true
        }

        let legacyFindMenuItem = NSMenuItem()
        legacyFindMenuItem.tag = Int(NSFindPanelAction.showFindPanel.rawValue)
        return NSApp.sendAction(#selector(NSTextView.performFindPanelAction(_:)), to: nil, from: legacyFindMenuItem)
    }

    private func performFindPreviousInDocument() -> Bool {
        if viewModel.mode == .view {
            isRenderedSearchPresented = true
            if !renderedFindQuery.isEmpty {
                performRenderedSearch(for: renderedFindQuery, backwards: true)
            }
            return true
        }

        let findMenuItem = NSMenuItem()
        findMenuItem.tag = NSTextFinder.Action.previousMatch.rawValue
        return NSApp.sendAction(#selector(NSResponder.performTextFinderAction(_:)), to: nil, from: findMenuItem)
    }

    private func performPrint() -> Bool {
        guard let session = viewModel.activeSession else {
            return false
        }

        let parsed = FrontmatterParser().parse(markdown: session.content)
        let html = RenderedHTMLBuilder().build(document: parsed)
        let state = interactionState
        state.printJob = RenderedDocumentPrintJob(html: html) { [weak state] in
            state?.printJob = nil
        }
        return true
    }

    private func activeRenderedWebView() -> WKWebView? {
        guard let keyWindow = NSApp.keyWindow,
              let contentView = keyWindow.contentView else {
            return nil
        }

        return contentView.firstDescendant(ofType: WKWebView.self)
    }

    private func performRenderedSearch(for rawQuery: String, backwards: Bool) {
        let query = rawQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty,
              let webView = activeRenderedWebView() else {
            return
        }

        if #available(macOS 12.0, *) {
            let configuration = WKFindConfiguration()
            configuration.backwards = backwards
            configuration.wraps = true
            webView.find(query, configuration: configuration) { _ in }
        } else {
            let escapedQuery = query
                .replacingOccurrences(of: "\\", with: "\\\\")
                .replacingOccurrences(of: "\"", with: "\\\"")
                .replacingOccurrences(of: "\n", with: "\\n")
                .replacingOccurrences(of: "\r", with: "\\r")
            webView.evaluateJavaScript("window.find(\"\(escapedQuery)\", false, \(backwards ? "true" : "false"), true, false, false, false);")
        }
    }
}

struct MarkdownOutlineView: View {
    let headings: [MarkdownHeading]
    let onSelectHeading: (MarkdownHeading) -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Outline")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)

            Divider()

            List(headings) { heading in
                Button {
                    onSelectHeading(heading)
                } label: {
                    Text(heading.title)
                        .lineLimit(1)
                        .padding(.leading, CGFloat(max(0, heading.level - 1)) * 12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.plain)
                .help(heading.title)
            }
            .listStyle(.sidebar)
        }
        .frame(minWidth: 220, idealWidth: 260, maxWidth: 320)
    }
}

private extension NSView {
    func firstDescendant<T: NSView>(ofType type: T.Type) -> T? {
        if let match = self as? T {
            return match
        }

        for subview in subviews {
            if let match = subview.firstDescendant(ofType: type) {
                return match
            }
        }

        return nil
    }
}

@MainActor
private final class WorkspaceInteractionState: ObservableObject {
    var printJob: RenderedDocumentPrintJob?
}

@MainActor
private final class RenderedDocumentPrintJob: NSObject, WKNavigationDelegate {
    private let webView: WKWebView
    private let completion: () -> Void
    private var hasCompleted = false

    init(html: String, completion: @escaping () -> Void) {
        self.webView = WKWebView(frame: NSRect(x: 0, y: 0, width: 960, height: 1200))
        self.completion = completion
        super.init()

        webView.navigationDelegate = self
        webView.loadHTMLString(html, baseURL: Bundle.main.bundleURL)
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        let printOperation = webView.printOperation(with: NSPrintInfo.shared)
        printOperation.showsPrintPanel = true
        printOperation.showsProgressPanel = true
        _ = printOperation.run()
        completeIfNeeded()
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        completeIfNeeded()
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        completeIfNeeded()
    }

    private func completeIfNeeded() {
        guard !hasCompleted else {
            return
        }

        hasCompleted = true
        completion()
    }
}
