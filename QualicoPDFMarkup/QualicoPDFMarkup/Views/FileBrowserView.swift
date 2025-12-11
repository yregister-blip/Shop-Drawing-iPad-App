//
//  FileBrowserView.swift
//  QualicoPDFMarkup
//
//  Paginated file browser with natural sorting and navigation to PDF viewer
//

import SwiftUI
import Combine

struct FileBrowserView: View {
    @EnvironmentObject var authManager: AuthManager
    @StateObject private var viewModel = FileBrowserViewModel()
    @State private var navigationPath = NavigationPath()

    var body: some View {
        NavigationStack(path: $navigationPath) {
            Group {
                if viewModel.isLoading && viewModel.items.isEmpty {
                    ProgressView("Loading...")
                } else if let error = viewModel.errorMessage {
                    VStack(spacing: 20) {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.system(size: 60))
                            .foregroundColor(.orange)
                        Text(error)
                            .multilineTextAlignment(.center)
                        Button("Retry") {
                            Task {
                                await viewModel.loadCurrentFolder()
                            }
                        }
                    }
                    .padding()
                } else {
                    List {
                        ForEach(viewModel.items) { item in
                            FileRowView(item: item) {
                                if item.isFolder {
                                    Task {
                                        await viewModel.navigateToFolder(item)
                                    }
                                } else if item.isPDF {
                                    // Navigate to PDF viewer via navigation path
                                    if let context = viewModel.createFolderContext(for: item) {
                                        navigationPath.append(PDFNavigationItem(file: item, context: context))
                                    }
                                }
                            }
                        }

                        if viewModel.hasMorePages {
                            HStack {
                                Spacer()
                                ProgressView()
                                Spacer()
                            }
                            .onAppear {
                                Task {
                                    await viewModel.loadNextPage()
                                }
                            }
                        }
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle(viewModel.currentFolderName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    if viewModel.canGoBack {
                        Button(action: {
                            Task {
                                await viewModel.navigateBack()
                            }
                        }) {
                            HStack {
                                Image(systemName: "chevron.left")
                                Text("Back")
                            }
                        }
                    }
                }

                ToolbarItem(placement: .navigationBarTrailing) {
                    Menu {
                        Button(action: {
                            Task {
                                await viewModel.loadCurrentFolder()
                            }
                        }) {
                            Label("Refresh", systemImage: "arrow.clockwise")
                        }

                        Button(action: {
                            authManager.signOut()
                        }) {
                            Label("Sign Out", systemImage: "rectangle.portrait.and.arrow.right")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
            .navigationDestination(for: PDFNavigationItem.self) { navItem in
                PDFViewerView(
                    file: navItem.file,
                    folderContext: navItem.context
                )
                .environmentObject(authManager)
            }
        }
        .task {
            viewModel.setGraphService(authManager: authManager)
            await viewModel.loadRootFolder()
        }
    }
}

// Navigation item for PDF viewer destination
struct PDFNavigationItem: Hashable {
    let file: DriveItem
    let context: FolderContext

    func hash(into hasher: inout Hasher) {
        hasher.combine(file.id)
    }

    static func == (lhs: PDFNavigationItem, rhs: PDFNavigationItem) -> Bool {
        lhs.file.id == rhs.file.id
    }
}

struct FileRowView: View {
    let item: DriveItem
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack {
                Image(systemName: iconName)
                    .font(.title2)
                    .foregroundColor(iconColor)
                    .frame(width: 40)

                VStack(alignment: .leading, spacing: 4) {
                    Text(item.name)
                        .font(.body)
                        .foregroundColor(.primary)

                    if let size = item.size {
                        Text(formatFileSize(size))
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }

                Spacer()

                if item.localStatus == .stamped {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                }

                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(.vertical, 4)
        }
        .buttonStyle(.plain)
    }

    private var iconName: String {
        if item.isFolder {
            return "folder.fill"
        } else if item.isPDF {
            return "doc.text.fill"
        } else {
            return "doc.fill"
        }
    }

    private var iconColor: Color {
        if item.isFolder {
            return .blue
        } else if item.isPDF {
            return .red
        } else {
            return .gray
        }
    }

    private func formatFileSize(_ bytes: Int) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: Int64(bytes))
    }
}

@MainActor
class FileBrowserViewModel: ObservableObject {
    @Published var items: [DriveItem] = []
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var currentFolderName = "OneDrive"
    @Published var hasMorePages = false

    private var graphService: GraphAPIService?
    private var navigationStack: [(id: String, name: String)] = []
    private var currentFolderId: String?
    private var nextLink: String?

    func setGraphService(authManager: AuthManager) {
        if graphService == nil {
            graphService = GraphAPIService(authManager: authManager)
        }
    }

    var canGoBack: Bool {
        !navigationStack.isEmpty
    }

    func loadRootFolder() async {
        guard let service = graphService else { return }

        isLoading = true
        errorMessage = nil

        do {
            let root = try await service.getRootFolder()
            currentFolderId = root.id
            currentFolderName = "OneDrive"
            await loadCurrentFolder()
        } catch {
            errorMessage = "Failed to load OneDrive: \(error.localizedDescription)"
            isLoading = false
        }
    }

    func loadCurrentFolder() async {
        guard let service = graphService, let folderId = currentFolderId else { return }

        isLoading = true
        errorMessage = nil
        items = []
        nextLink = nil

        do {
            let (fetchedItems, link) = try await service.listFolder(folderId: folderId)
            items = fetchedItems.naturallySorted()
            nextLink = link
            hasMorePages = link != nil
            isLoading = false
        } catch {
            errorMessage = "Failed to load folder: \(error.localizedDescription)"
            isLoading = false
        }
    }

    func loadNextPage() async {
        guard let service = graphService, let folderId = currentFolderId, hasMorePages else { return }

        do {
            let skipToken = extractSkipToken(from: nextLink)
            let (fetchedItems, link) = try await service.listFolder(folderId: folderId, skipToken: skipToken)
            items.append(contentsOf: fetchedItems)
            items = items.naturallySorted()
            nextLink = link
            hasMorePages = link != nil
        } catch {
            errorMessage = "Failed to load more files: \(error.localizedDescription)"
        }
    }

    func navigateToFolder(_ folder: DriveItem) async {
        guard folder.isFolder else { return }

        if let currentId = currentFolderId {
            navigationStack.append((currentId, currentFolderName))
        }

        currentFolderId = folder.id
        currentFolderName = folder.name
        await loadCurrentFolder()
    }

    func navigateBack() async {
        guard let previous = navigationStack.popLast() else { return }

        currentFolderId = previous.id
        currentFolderName = previous.name
        await loadCurrentFolder()
    }

    func createFolderContext(for file: DriveItem) -> FolderContext? {
        guard let folderId = currentFolderId else { return nil }

        let pdfFiles = items.filter { $0.isPDF }
        return FolderContext(folderId: folderId, files: pdfFiles, currentFileId: file.id)
    }

    private func extractSkipToken(from nextLink: String?) -> String? {
        guard let nextLink = nextLink,
              let components = URLComponents(string: nextLink),
              let skipToken = components.queryItems?.first(where: { $0.name == "$skiptoken" })?.value else {
            return nil
        }
        return skipToken
    }
}
