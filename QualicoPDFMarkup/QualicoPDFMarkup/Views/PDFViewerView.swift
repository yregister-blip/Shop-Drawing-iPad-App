//
//  PDFViewerView.swift
//  QualicoPDFMarkup
//
//  Full-screen PDF viewer with tap-to-stamp and slide-out file browser
//

import SwiftUI
import Combine
import PDFKit

struct PDFViewerView: View {
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var authManager: AuthManager
    @StateObject private var viewModel: PDFViewerViewModel

    @State private var showFileList = false
    @State private var edgeSwipeOffset: CGFloat = 0

    private let edgeSwipeThreshold: CGFloat = 50

    init(file: DriveItem, folderContext: FolderContext?) {
        _viewModel = StateObject(wrappedValue: PDFViewerViewModel(file: file, folderContext: folderContext))
    }

    var body: some View {
        ZStack {
            // Main content
            VStack(spacing: 0) {
                // Top toolbar with all controls
                PDFTopToolbarView(
                    filename: viewModel.currentFile.name,
                    positionDisplay: viewModel.positionDisplay,
                    canNavigatePrevious: viewModel.canNavigatePrevious,
                    canNavigateNext: viewModel.canNavigateNext,
                    onPreviousTapped: {
                        Task {
                            await viewModel.navigateToPrevious()
                        }
                    },
                    onNextTapped: {
                        Task {
                            await viewModel.navigateToNext()
                        }
                    },
                    onMenuTapped: {
                        withAnimation(.easeInOut(duration: 0.25)) {
                            showFileList = true
                        }
                    },
                    isStampModeEnabled: $viewModel.isStampModeEnabled,
                    selectedStampType: $viewModel.selectedStampType,
                    onSaveTapped: {
                        Task {
                            await viewModel.save()
                        }
                    },
                    hasUnsavedChanges: viewModel.hasUnsavedChanges,
                    isSaving: viewModel.isSaving,
                    onCloseTapped: {
                        dismiss()
                    }
                )

                // PDF content area
                if viewModel.isLoading {
                    VStack {
                        Spacer()
                        ProgressView("Loading PDF...")
                        Spacer()
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color(UIColor.systemGroupedBackground))
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
                        .buttonStyle(.borderedProminent)
                    }
                    .padding()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color(UIColor.systemGroupedBackground))
                } else if let pdfDocument = viewModel.pdfDocument {
                    PDFKitView(
                        document: pdfDocument,
                        onTap: { point, pdfView in
                            viewModel.handleStampTap(at: point, in: pdfView)
                        }
                    )
                }
            }

            // Edge swipe indicator (visual feedback when swiping from left edge)
            if edgeSwipeOffset > 0 {
                HStack {
                    Rectangle()
                        .fill(Color.blue.opacity(0.3))
                        .frame(width: min(edgeSwipeOffset, 60))
                        .overlay(
                            Image(systemName: "chevron.right")
                                .foregroundColor(.blue)
                                .opacity(edgeSwipeOffset > 30 ? 1 : 0)
                        )
                    Spacer()
                }
                .ignoresSafeArea()
            }

            // Slide-out file list overlay
            SlideOutFileListView(
                isShowing: $showFileList,
                files: viewModel.folderFiles,
                currentFileId: viewModel.currentFile.id,
                onFileSelected: { file in
                    Task {
                        await viewModel.navigateToFile(file)
                    }
                }
            )

            // Stamp mode indicator (floating at bottom)
            if viewModel.isStampModeEnabled {
                VStack {
                    Spacer()
                    StampModeIndicator(stampType: viewModel.selectedStampType)
                        .padding(.bottom, 30)
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .animation(.easeInOut(duration: 0.2), value: viewModel.isStampModeEnabled)
            }
        }
        .navigationBarHidden(true)
        .ignoresSafeArea(.keyboard)
        .gesture(edgeSwipeGesture)
        .alert("Save Result", isPresented: $viewModel.showSaveAlert) {
            Button("OK") {
                viewModel.showSaveAlert = false
            }
        } message: {
            Text(viewModel.saveResultMessage)
        }
        .task {
            viewModel.setGraphService(authManager: authManager)
            await viewModel.loadPDF()
        }
    }

    // Edge swipe gesture to open file list
    private var edgeSwipeGesture: some Gesture {
        DragGesture(minimumDistance: 10)
            .onChanged { value in
                // Only respond to swipes starting from the left edge
                if value.startLocation.x < 30 && value.translation.width > 0 {
                    edgeSwipeOffset = value.translation.width
                }
            }
            .onEnded { value in
                if value.startLocation.x < 30 && value.translation.width > edgeSwipeThreshold {
                    withAnimation(.easeInOut(duration: 0.25)) {
                        showFileList = true
                    }
                }
                withAnimation(.easeOut(duration: 0.15)) {
                    edgeSwipeOffset = 0
                }
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

    // Stamp mode controls
    @Published var isStampModeEnabled = false
    @Published var selectedStampType: StampType = .fabricated

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

    // Expose files for slide-out panel
    var folderFiles: [DriveItem] {
        folderContext?.files ?? []
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
        // Only place stamps when stamp mode is enabled
        guard isStampModeEnabled else { return }
        guard let page = pdfView.page(for: screenPoint, nearest: true) else { return }

        let success = PDFAnnotationHelper.addStamp(
            to: page,
            at: screenPoint,
            in: pdfView,
            stampType: selectedStampType
        )

        if success {
            hasUnsavedChanges = true
            // Immediate UI feedback
            currentFile.localStatus = .stamped
        }
    }

    func toggleStampMode() {
        isStampModeEnabled.toggle()
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

    // Navigate to specific file from slide-out panel
    func navigateToFile(_ file: DriveItem) async {
        guard var context = folderContext,
              let index = context.files.firstIndex(where: { $0.id == file.id }) else { return }

        context.currentIndex = index
        folderContext = context
        currentFile = file
        originalETag = file.eTag
        hasUnsavedChanges = false
        await loadPDF()
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
