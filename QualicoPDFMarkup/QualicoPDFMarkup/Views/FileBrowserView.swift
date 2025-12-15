//
//  FileBrowserView.swift
//  QualicoPDFMarkup
//
//  Paginated file browser with natural sorting and navigation to PDF viewer
//  Styled with Qualico brand colors
//

import SwiftUI
import Combine

struct FileBrowserView: View {
    @EnvironmentObject var authManager: AuthManager
    @StateObject private var viewModel = FileBrowserViewModel()
    @State private var navigationPath = NavigationPath()
    @State private var showSignOutConfirmation = false
    @State private var isGridView = false
    @State private var searchText = ""

    // Grid layout columns
    private let gridColumns = [
        GridItem(.adaptive(minimum: 160, maximum: 200), spacing: 16)
    ]

    // Filtered items based on search text
    private var filteredItems: [DriveItem] {
        if searchText.isEmpty {
            return viewModel.items
        }
        return viewModel.items.filter { item in
            item.name.localizedCaseInsensitiveContains(searchText)
        }
    }

    var body: some View {
        NavigationStack(path: $navigationPath) {
            Group {
                if viewModel.isLoading && viewModel.items.isEmpty {
                    VStack(spacing: 12) {
                        ProgressView()
                        Text(viewModel.loadingMessage)
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
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
                } else if filteredItems.isEmpty && !searchText.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 48))
                            .foregroundColor(.secondary)
                        Text("No results found")
                            .font(.headline)
                        Text("No files match \"\(searchText)\"")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    .padding()
                } else if isGridView {
                    ScrollView {
                        LazyVGrid(columns: gridColumns, spacing: 16) {
                            ForEach(filteredItems) { item in
                                FileGridItemView(item: item, graphService: viewModel.graphService) {
                                    handleItemTap(item)
                                }
                            }
                        }
                        .padding()
                    }
                } else {
                    List {
                        ForEach(filteredItems) { item in
                            FileRowView(item: item, graphService: viewModel.graphService) {
                                handleItemTap(item)
                            }
                        }
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle(viewModel.currentFolderName)
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $searchText, prompt: "Search files")
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
                    HStack(spacing: 8) {
                        // Grid/List toggle button
                        Button(action: {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                isGridView.toggle()
                            }
                        }) {
                            Image(systemName: isGridView ? "list.bullet" : "square.grid.2x2")
                                .foregroundColor(.primary)
                        }
                        .help(isGridView ? "Switch to List View" : "Switch to Grid View")

                        Menu {
                            Button(action: {
                                Task {
                                    await viewModel.loadCurrentFolder()
                                }
                            }) {
                                Label("Refresh", systemImage: "arrow.clockwise")
                            }

                            // Sign Out is hidden in Account submenu to prevent accidental sign-outs
                            Menu {
                                Button(role: .destructive, action: {
                                    showSignOutConfirmation = true
                                }) {
                                    Label("Sign Out", systemImage: "rectangle.portrait.and.arrow.right")
                                }
                            } label: {
                                Label("Account", systemImage: "person.circle")
                            }
                        } label: {
                            Image(systemName: "ellipsis.circle")
                        }
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
        .alert("Sign Out", isPresented: $showSignOutConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Sign Out", role: .destructive) {
                authManager.signOut()
            }
        } message: {
            Text("Are you sure you want to sign out? You will need to sign in again to access files.")
        }
    }

    private func handleItemTap(_ item: DriveItem) {
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
    let graphService: GraphAPIService?
    let onTap: () -> Void

    @State private var thumbnail: UIImage?
    @State private var isLoadingThumbnail = false

    var body: some View {
        Button(action: onTap) {
            HStack {
                // Thumbnail or icon
                thumbnailView
                    .frame(width: 44, height: 56)

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
                        .foregroundColor(BrandColors.primaryRed)
                }

                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(.vertical, 4)
        }
        .buttonStyle(.plain)
        .task {
            await loadThumbnailIfNeeded()
        }
    }

    @ViewBuilder
    private var thumbnailView: some View {
        if item.isFolder {
            // Folder icon - using brand dark gray
            Image(systemName: "folder.fill")
                .font(.system(size: 32))
                .foregroundColor(BrandColors.darkGray)
        } else if let thumbnail = thumbnail {
            // PDF thumbnail
            Image(uiImage: thumbnail)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .cornerRadius(4)
                .overlay(
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(Color.gray.opacity(0.3), lineWidth: 1)
                )
        } else if item.isPDF && isLoadingThumbnail {
            // Loading placeholder
            RoundedRectangle(cornerRadius: 4)
                .fill(Color.gray.opacity(0.1))
                .overlay(
                    ProgressView()
                        .scaleEffect(0.6)
                )
        } else if item.isPDF {
            // PDF icon fallback - using brand red
            Image(systemName: "doc.text.fill")
                .font(.system(size: 32))
                .foregroundColor(BrandColors.primaryRed)
        } else {
            // Generic file icon
            Image(systemName: "doc.fill")
                .font(.system(size: 32))
                .foregroundColor(.gray)
        }
    }

    private func loadThumbnailIfNeeded() async {
        guard item.isPDF, thumbnail == nil, let graphService = graphService else { return }

        // Check cache first
        if let cached = PDFThumbnailService.shared.getCachedThumbnail(for: item.id) {
            thumbnail = cached
            return
        }

        isLoadingThumbnail = true
        thumbnail = await PDFThumbnailService.shared.loadThumbnail(for: item, using: graphService)
        isLoadingThumbnail = false
    }

    private func formatFileSize(_ bytes: Int) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: Int64(bytes))
    }
}

// MARK: - Grid Item View

struct FileGridItemView: View {
    let item: DriveItem
    let graphService: GraphAPIService?
    let onTap: () -> Void

    @State private var thumbnail: UIImage?
    @State private var isLoadingThumbnail = false

    private let thumbnailSize = PDFThumbnailService.gridThumbnailSize

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 8) {
                // Thumbnail area
                thumbnailView
                    .frame(width: thumbnailSize.width, height: thumbnailSize.height)
                    .background(Color(UIColor.secondarySystemBackground))
                    .cornerRadius(8)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.gray.opacity(0.2), lineWidth: 1)
                    )
                    .overlay(alignment: .topTrailing) {
                        if item.localStatus == .stamped {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(BrandColors.primaryRed)
                                .padding(6)
                        }
                    }

                // Filename
                Text(item.name)
                    .font(.caption)
                    .foregroundColor(.primary)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: thumbnailSize.width)

                // File size (for PDFs)
                if let size = item.size, !item.isFolder {
                    Text(formatFileSize(size))
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
            .padding(8)
            .background(Color(UIColor.systemBackground))
            .cornerRadius(12)
            .shadow(color: .black.opacity(0.05), radius: 2, x: 0, y: 1)
        }
        .buttonStyle(.plain)
        .task {
            await loadThumbnailIfNeeded()
        }
    }

    @ViewBuilder
    private var thumbnailView: some View {
        if item.isFolder {
            // Folder icon
            VStack {
                Spacer()
                Image(systemName: "folder.fill")
                    .font(.system(size: 60))
                    .foregroundColor(BrandColors.darkGray)
                Spacer()
            }
        } else if let thumbnail = thumbnail {
            // PDF thumbnail
            Image(uiImage: thumbnail)
                .resizable()
                .aspectRatio(contentMode: .fit)
        } else if item.isPDF && isLoadingThumbnail {
            // Loading placeholder
            VStack {
                Spacer()
                ProgressView()
                    .scaleEffect(1.2)
                Text("Loading...")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .padding(.top, 4)
                Spacer()
            }
        } else if item.isPDF {
            // PDF icon fallback
            VStack {
                Spacer()
                Image(systemName: "doc.text.fill")
                    .font(.system(size: 60))
                    .foregroundColor(BrandColors.primaryRed)
                Spacer()
            }
        } else {
            // Generic file icon
            VStack {
                Spacer()
                Image(systemName: "doc.fill")
                    .font(.system(size: 60))
                    .foregroundColor(.gray)
                Spacer()
            }
        }
    }

    private func loadThumbnailIfNeeded() async {
        guard item.isPDF, thumbnail == nil, let graphService = graphService else { return }

        // Check cache first
        if let cached = PDFThumbnailService.shared.getCachedThumbnail(for: item.id, targetSize: thumbnailSize) {
            thumbnail = cached
            return
        }

        isLoadingThumbnail = true
        thumbnail = await PDFThumbnailService.shared.loadThumbnail(
            for: item,
            using: graphService,
            targetSize: thumbnailSize
        )
        isLoadingThumbnail = false
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
    @Published var loadingMessage = "Loading..."

    private(set) var graphService: GraphAPIService?
    private var navigationStack: [(id: String, name: String)] = []
    private var currentFolderId: String?

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
        loadingMessage = "Loading..."

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
        loadingMessage = "Loading files..."

        do {
            // Load ALL files from ALL pages before sorting
            // This ensures proper natural sorting and Prev/Next navigation for 50+ file folders
            var allItems: [DriveItem] = []
            var pageCount = 0
            var nextLink: String? = nil

            repeat {
                pageCount += 1
                loadingMessage = pageCount == 1 ? "Loading files..." : "Loading files (page \(pageCount))..."

                let skipToken = extractSkipToken(from: nextLink)
                let (fetchedItems, link) = try await service.listFolder(folderId: folderId, skipToken: skipToken)
                allItems.append(contentsOf: fetchedItems)
                nextLink = link
            } while nextLink != nil

            // Now sort the complete list of all files
            items = allItems.naturallySorted()
            isLoading = false
        } catch {
            errorMessage = "Failed to load folder: \(error.localizedDescription)"
            isLoading = false
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

        // Use all loaded PDF files - they're now all loaded and properly sorted
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
