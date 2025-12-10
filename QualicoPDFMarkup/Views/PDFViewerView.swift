//
//  PDFViewerView.swift
//  QualicoPDFMarkup
//
//  PDF viewer with tap-to-stamp and in-viewer navigation
//

import SwiftUI
import PDFKit

struct PDFViewerView: View {
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var authManager: AuthManager
    @StateObject private var viewModel: PDFViewerViewModel

    init(file: DriveItem, folderContext: FolderContext?) {
        _viewModel = StateObject(wrappedValue: PDFViewerViewModel(file: file, folderContext: folderContext))
    }

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                if viewModel.isLoading {
                    VStack {
                        Spacer()
                        ProgressView("Loading PDF...")
                        Spacer()
                    }
                } else if let errorMessage = viewModel.errorMessage {
                    VStack(spacing: 20) {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.system(size: 60))
                            .foregroundColor(.orange)
                        Text(errorMessage)
                            .multilineTextAlignment(.center)
                        Button("Retry") {
                            Task {
                                await viewModel.loadPDF()
                            }
                        }
                    }
                    .padding()
                } else if let pdfDocument = viewModel.pdfDocument {
                    PDFKitView(
                        document: pdfDocument,
                        onTap: { point, pdfView in
                            viewModel.handleStampTap(at: point, in: pdfView)
                        }
                    )

                    // Toolbar
                    StampToolbarView(viewModel: viewModel)
                }
            }
            .navigationTitle(viewModel.currentFile.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Close") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .navigationBarTrailing) {
                    if viewModel.isSaving {
                        ProgressView()
                    } else if viewModel.hasUnsavedChanges {
                        Button("Save") {
                            Task {
                                await viewModel.save()
                            }
                        }
                    }
                }
            }
            .alert("Save Result", isPresented: $viewModel.showSaveAlert) {
                Button("OK") {
                    viewModel.showSaveAlert = false
                }
            } message: {
                Text(viewModel.saveResultMessage)
            }
        }
        .navigationViewStyle(.stack)
        .task {
            viewModel.setGraphService(authManager: authManager)
            await viewModel.loadPDF()
        }
    }
}

struct PDFKitView: UIViewRepresentable {
    let document: PDFDocument
    let onTap: (CGPoint, PDFView) -> Void

    func makeUIView(context: Context) -> PDFView {
        let pdfView = PDFView()
        pdfView.document = document
        pdfView.autoScales = true
        pdfView.displayMode = .singlePageContinuous
        pdfView.displayDirection = .vertical

        // Add tap gesture recognizer
        let tapGesture = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleTap(_:)))
        pdfView.addGestureRecognizer(tapGesture)
        context.coordinator.pdfView = pdfView

        return pdfView
    }

    func updateUIView(_ pdfView: PDFView, context: Context) {
        if pdfView.document !== document {
            pdfView.document = document
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(onTap: onTap)
    }

    class Coordinator: NSObject {
        let onTap: (CGPoint, PDFView) -> Void
        weak var pdfView: PDFView?

        init(onTap: @escaping (CGPoint, PDFView) -> Void) {
            self.onTap = onTap
        }

        @objc func handleTap(_ gesture: UITapGestureRecognizer) {
            guard let pdfView = pdfView else { return }
            let point = gesture.location(in: pdfView)
            onTap(point, pdfView)
        }
    }
}

@MainActor
class PDFViewerViewModel: ObservableObject {
    @Published var currentFile: DriveItem
    @Published var pdfDocument: PDFDocument?
    @Published var isLoading = false
    @Published var isSaving = false
    @Published var errorMessage: String?
    @Published var hasUnsavedChanges = false
    @Published var showSaveAlert = false
    @Published var saveResultMessage = ""

    private var folderContext: FolderContext?
    private var graphService: GraphAPIService?
    private var syncManager: SyncManager?
    private var preloadManager: FilePreloadManager?
    private var originalETag: String?

    init(file: DriveItem, folderContext: FolderContext?) {
        self.currentFile = file
        self.folderContext = folderContext
        self.originalETag = file.eTag
    }

    func setGraphService(authManager: AuthManager) {
        if graphService == nil {
            let service = GraphAPIService(authManager: authManager)
            graphService = service
            syncManager = SyncManager(graphService: service)
            preloadManager = FilePreloadManager(graphService: service)
        }
    }

    func loadPDF() async {
        guard let service = graphService else { return }

        isLoading = true
        errorMessage = nil

        do {
            // Check if preloaded
            let data: Data
            if let preloadedData = preloadManager?.getPreloadedData(for: currentFile.id) {
                data = preloadedData
            } else {
                data = try await service.downloadFile(itemId: currentFile.id)
            }

            // Fetch fresh metadata to get current eTag for conflict detection
            let metadata = try await service.getItemMetadata(itemId: currentFile.id)
            originalETag = metadata.eTag

            if let document = PDFDocument(data: data) {
                pdfDocument = document
                hasUnsavedChanges = false

                // Preload next file if available
                if let context = folderContext {
                    preloadManager?.preloadNext(context: context)
                }
            } else {
                errorMessage = "Failed to load PDF document"
            }

            isLoading = false
        } catch {
            errorMessage = "Failed to download PDF: \(error.localizedDescription)"
            isLoading = false
        }
    }

    func handleStampTap(at screenPoint: CGPoint, in pdfView: PDFView) {
        guard let page = pdfView.page(for: screenPoint, nearest: true) else { return }

        let success = PDFAnnotationHelper.addStamp(
            to: page,
            at: screenPoint,
            in: pdfView,
            stampType: .fabricated
        )

        if success {
            hasUnsavedChanges = true
            // Immediate UI feedback
            currentFile.localStatus = .stamped
        }
    }

    func save() async {
        guard let document = pdfDocument,
              let service = graphService,
              let manager = syncManager else { return }

        isSaving = true

        do {
            // Get PDF data
            guard let pdfData = document.dataRepresentation() else {
                errorMessage = "Failed to generate PDF data"
                isSaving = false
                return
            }

            // Use eTag checking to detect concurrent edits
            guard let eTag = originalETag,
                  let folderId = folderContext?.folderId else {
                // Fallback to force save if we don't have eTag or folderId
                try await manager.forceSave(itemId: currentFile.id, pdfData: pdfData)
                hasUnsavedChanges = false
                saveResultMessage = "PDF saved successfully"
                showSaveAlert = true
                isSaving = false
                return
            }

            let result = try await manager.saveWithETagCheck(
                itemId: currentFile.id,
                originalETag: eTag,
                originalName: currentFile.name,
                folderId: folderId,
                pdfData: pdfData
            )

            hasUnsavedChanges = false

            switch result {
            case .overwritten:
                // Update eTag after successful save
                let metadata = try await service.getItemMetadata(itemId: currentFile.id)
                originalETag = metadata.eTag
                saveResultMessage = "PDF saved successfully"
            case .savedAsCopy(let fileName):
                saveResultMessage = "File was modified by another user. Your changes were saved as:\n\n\(fileName)"
            }

            showSaveAlert = true
            isSaving = false
        } catch {
            errorMessage = "Failed to save PDF: \(error.localizedDescription)"
            isSaving = false
        }
    }

    func navigateToNext() async {
        guard var context = folderContext, context.hasNext else { return }

        if let nextFile = context.goNext() {
            folderContext = context
            currentFile = nextFile
            originalETag = nextFile.eTag
            hasUnsavedChanges = false
            await loadPDF()
        }
    }

    func navigateToPrevious() async {
        guard var context = folderContext, context.hasPrevious else { return }

        if let prevFile = context.goPrevious() {
            folderContext = context
            currentFile = prevFile
            originalETag = prevFile.eTag
            hasUnsavedChanges = false
            await loadPDF()
        }
    }

    var canNavigateNext: Bool {
        folderContext?.hasNext ?? false
    }

    var canNavigatePrevious: Bool {
        folderContext?.hasPrevious ?? false
    }

    var positionDisplay: String {
        folderContext?.positionDisplay ?? ""
    }
}
