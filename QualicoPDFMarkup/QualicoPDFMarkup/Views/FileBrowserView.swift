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
    @State private var showSignOutConfirmation = false

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
    @Published var loadingMessage = "Loading..."

    private var graphService: GraphAPIService?
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
