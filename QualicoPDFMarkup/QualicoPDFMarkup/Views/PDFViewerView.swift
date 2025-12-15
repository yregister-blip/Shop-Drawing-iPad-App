//
//  PDFViewerView.swift
//  QualicoPDFMarkup
//
//  Full-screen PDF viewer with annotation tools and slide-out file browser
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
    @State private var showTextInput = false
    @State private var textInputText = ""
    @State private var textInputLocation: CGPoint = .zero
    @State private var textInputPDFView: PDFView? = nil
    @State private var showCustomStampSheet = false

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
                    selectedTool: $viewModel.selectedTool,
                    selectedStampType: $viewModel.selectedStampType,
                    selectedColor: $viewModel.selectedColor,
                    selectedLineWidth: $viewModel.selectedLineWidth,
                    canUndo: viewModel.canUndo,
                    onUndoTapped: {
                        viewModel.undo()
                    },
                    onSaveTapped: {
                        Task {
                            await viewModel.save()
                        }
                    },
                    hasUnsavedChanges: viewModel.hasUnsavedChanges,
                    isSaving: viewModel.isSaving,
                    customStamps: $viewModel.customStamps,
                    selectedCustomStamp: $viewModel.selectedCustomStamp,
                    onAddCustomStamp: {
                        showCustomStampSheet = true
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
                        selectedTool: viewModel.selectedTool,
                        selectedColor: viewModel.selectedColor,
                        selectedLineWidth: viewModel.selectedLineWidth,
                        onTap: { point, pdfView in
                            viewModel.handleTap(at: point, in: pdfView)
                        },
                        onTextTap: { point, pdfView in
                            textInputLocation = point
                            textInputPDFView = pdfView
                            showTextInput = true
                        },
                        onDrawingComplete: { path, pdfView in
                            viewModel.handleDrawingComplete(path: path, in: pdfView)
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
                graphService: viewModel.graphService,
                onFileSelected: { file in
                    Task {
                        await viewModel.navigateToFile(file)
                    }
                },
                onCloseViewer: {
                    dismiss()
                }
            )

            // Tool mode indicator (floating at bottom)
            if viewModel.selectedTool != .none {
                VStack {
                    Spacer()
                    ToolModeIndicator(
                        tool: viewModel.selectedTool,
                        stampType: viewModel.selectedTool == .stamp ? viewModel.selectedStampType : nil,
                        color: viewModel.selectedTool == .pen ? viewModel.selectedColor : nil
                    )
                    .padding(.bottom, 30)
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .animation(.easeInOut(duration: 0.2), value: viewModel.selectedTool)
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
        .alert("Add Text", isPresented: $showTextInput) {
            TextField("Enter text", text: $textInputText)
            Button("Cancel", role: .cancel) {
                textInputText = ""
                textInputPDFView = nil
            }
            Button("Add") {
                if !textInputText.isEmpty, let pdfView = textInputPDFView {
                    viewModel.handleTextInput(text: textInputText, at: textInputLocation, in: pdfView)
                    textInputText = ""
                    textInputPDFView = nil
                }
            }
        } message: {
            Text("Enter text to add to the PDF")
        }
        .sheet(isPresented: $showCustomStampSheet) {
            CustomStampCreatorView(
                onSave: { stamp in
                    viewModel.addCustomStamp(stamp)
                }
            )
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

// MARK: - Custom Stamp Creator View

struct CustomStampCreatorView: View {
    @Environment(\.dismiss) var dismiss
    let onSave: (CustomStamp) -> Void

    @State private var stampName = ""
    @State private var stampText = ""
    @State private var selectedColor: DrawingColor = .red

    var body: some View {
        NavigationView {
            Form {
                Section("Stamp Details") {
                    TextField("Stamp Name", text: $stampName)
                    TextField("Stamp Text", text: $stampText)
                }

                Section("Color") {
                    Picker("Border & Text Color", selection: $selectedColor) {
                        ForEach(DrawingColor.allCases) { color in
                            HStack {
                                Circle()
                                    .fill(Color(color.uiColor))
                                    .frame(width: 20, height: 20)
                                Text(color.rawValue)
                            }
                            .tag(color)
                        }
                    }
                }

                Section("Preview") {
                    HStack {
                        Spacer()
                        stampPreview
                        Spacer()
                    }
                    .padding(.vertical, 8)
                }
            }
            .navigationTitle("Create Custom Stamp")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        let stamp = CustomStamp(
                            name: stampName.isEmpty ? stampText : stampName,
                            text: stampText,
                            borderColor: selectedColor.uiColor,
                            textColor: selectedColor.uiColor
                        )
                        onSave(stamp)
                        dismiss()
                    }
                    .disabled(stampText.isEmpty)
                }
            }
        }
    }

    private var stampPreview: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 2)
                .stroke(Color(selectedColor.uiColor), lineWidth: 3)
                .frame(width: 150, height: 50)

            Text(stampText.isEmpty ? "STAMP" : stampText)
                .font(.system(size: 16, weight: .bold))
                .foregroundColor(Color(selectedColor.uiColor))
        }
    }
}

struct PDFKitView: UIViewRepresentable {
    let document: PDFDocument
    let selectedTool: AnnotationTool
    let selectedColor: DrawingColor
    let selectedLineWidth: LineWidth
    let onTap: (CGPoint, PDFView) -> Void
    let onTextTap: (CGPoint, PDFView) -> Void
    let onDrawingComplete: (DrawingPath, PDFView) -> Void

    func makeUIView(context: Context) -> PDFView {
        let pdfView = PDFView()
        pdfView.document = document
        pdfView.autoScales = true
        pdfView.displayMode = .singlePageContinuous
        pdfView.displayDirection = .vertical

        // Add tap gesture recognizer
        let tapGesture = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleTap(_:)))
        pdfView.addGestureRecognizer(tapGesture)

        // Add pan gesture recognizer for drawing
        let panGesture = UIPanGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handlePan(_:)))
        panGesture.minimumNumberOfTouches = 1
        panGesture.maximumNumberOfTouches = 1
        pdfView.addGestureRecognizer(panGesture)

        context.coordinator.pdfView = pdfView

        return pdfView
    }

    func updateUIView(_ pdfView: PDFView, context: Context) {
        if pdfView.document !== document {
            pdfView.document = document
        }

        // Update coordinator with current tool settings
        context.coordinator.selectedTool = selectedTool
        context.coordinator.selectedColor = selectedColor
        context.coordinator.selectedLineWidth = selectedLineWidth
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(
            onTap: onTap,
            onTextTap: onTextTap,
            onDrawingComplete: onDrawingComplete,
            selectedTool: selectedTool,
            selectedColor: selectedColor,
            selectedLineWidth: selectedLineWidth
        )
    }

    class Coordinator: NSObject {
        let onTap: (CGPoint, PDFView) -> Void
        let onTextTap: (CGPoint, PDFView) -> Void
        let onDrawingComplete: (DrawingPath, PDFView) -> Void

        weak var pdfView: PDFView?
        var selectedTool: AnnotationTool
        var selectedColor: DrawingColor
        var selectedLineWidth: LineWidth

        // Drawing state
        private var currentPath: DrawingPath?
        private var drawingOverlay: DrawingOverlayView?

        init(
            onTap: @escaping (CGPoint, PDFView) -> Void,
            onTextTap: @escaping (CGPoint, PDFView) -> Void,
            onDrawingComplete: @escaping (DrawingPath, PDFView) -> Void,
            selectedTool: AnnotationTool,
            selectedColor: DrawingColor,
            selectedLineWidth: LineWidth
        ) {
            self.onTap = onTap
            self.onTextTap = onTextTap
            self.onDrawingComplete = onDrawingComplete
            self.selectedTool = selectedTool
            self.selectedColor = selectedColor
            self.selectedLineWidth = selectedLineWidth
        }

        @objc func handleTap(_ gesture: UITapGestureRecognizer) {
            guard let pdfView = pdfView else { return }
            let point = gesture.location(in: pdfView)

            switch selectedTool {
            case .text:
                onTextTap(point, pdfView)
            case .stamp:
                onTap(point, pdfView)
            case .none, .pen, .highlight:
                // For none/pen/highlight, tap does nothing or just selects
                break
            }
        }

        @objc func handlePan(_ gesture: UIPanGestureRecognizer) {
            guard let pdfView = pdfView else { return }

            // Only handle pan for drawing tools
            guard selectedTool == .pen || selectedTool == .highlight else { return }

            let point = gesture.location(in: pdfView)

            switch gesture.state {
            case .began:
                startDrawing(at: point, in: pdfView)
            case .changed:
                continueDrawing(at: point)
            case .ended, .cancelled:
                finishDrawing(in: pdfView)
            default:
                break
            }
        }

        private func startDrawing(at point: CGPoint, in pdfView: PDFView) {
            // Determine page index
            let pageIndex: Int
            if let page = pdfView.page(for: point, nearest: true),
               let document = pdfView.document,
               let index = document.index(for: page) as Int? {
                pageIndex = index
            } else {
                pageIndex = 0
            }

            // Create new drawing path
            let isHighlight = selectedTool == .highlight
            let lineWidth = isHighlight ? selectedLineWidth.highlightWidth : selectedLineWidth.rawValue
            let color = isHighlight ? selectedColor.highlightColor : selectedColor.uiColor

            currentPath = DrawingPath(
                points: [point],
                color: color,
                lineWidth: lineWidth,
                isHighlight: isHighlight,
                pageIndex: pageIndex
            )

            // Create and add drawing overlay
            let overlay = DrawingOverlayView(frame: pdfView.bounds)
            overlay.strokeColor = color
            overlay.lineWidth = lineWidth
            overlay.isUserInteractionEnabled = false
            pdfView.addSubview(overlay)
            drawingOverlay = overlay
        }

        private func continueDrawing(at point: CGPoint) {
            currentPath?.points.append(point)
            drawingOverlay?.points = currentPath?.points ?? []
            drawingOverlay?.setNeedsDisplay()
        }

        private func finishDrawing(in pdfView: PDFView) {
            defer {
                // Clean up overlay
                drawingOverlay?.removeFromSuperview()
                drawingOverlay = nil
            }

            guard let path = currentPath, path.points.count >= 2 else {
                currentPath = nil
                return
            }

            onDrawingComplete(path, pdfView)
            currentPath = nil
        }
    }
}

// MARK: - Drawing Overlay View

/// Temporary overlay view for showing drawing in progress
class DrawingOverlayView: UIView {
    var points: [CGPoint] = []
    var strokeColor: UIColor = .black
    var lineWidth: CGFloat = 2.0

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func draw(_ rect: CGRect) {
        guard points.count >= 2 else { return }

        let path = UIBezierPath()
        path.move(to: points[0])

        for point in points.dropFirst() {
            path.addLine(to: point)
        }

        strokeColor.setStroke()
        path.lineWidth = lineWidth
        path.lineCapStyle = .round
        path.lineJoinStyle = .round
        path.stroke()
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

    // Annotation tool controls
    @Published var selectedTool: AnnotationTool = .none
    @Published var selectedStampType: StampType = .fabricated
    @Published var selectedCustomStamp: CustomStamp? = nil
    @Published var selectedColor: DrawingColor = .black
    @Published var selectedLineWidth: LineWidth = .medium
    @Published var customStamps: [CustomStamp] = []

    // Legacy compatibility
    var isStampModeEnabled: Bool {
        get { selectedTool == .stamp }
        set { selectedTool = newValue ? .stamp : .none }
    }

    // Undo support
    private let historyManager = AnnotationHistoryManager()
    @Published var canUndo = false

    // Reference to current PDFView for text input
    private weak var currentPDFView: PDFView?

    private var folderContext: FolderContext?
    private(set) var graphService: GraphAPIService?
    private var syncManager: SyncManager?
    private var preloadManager: FilePreloadManager?
    private var originalETag: String?

    init(file: DriveItem, folderContext: FolderContext?) {
        self.currentFile = file
        self.folderContext = folderContext
        self.originalETag = file.eTag

        // Observe history manager changes
        observeHistoryManager()
    }

    private func observeHistoryManager() {
        // Keep canUndo in sync with history manager
        Task { @MainActor in
            for await _ in historyManager.$canUndo.values {
                self.canUndo = self.historyManager.canUndo
            }
        }
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

        // Clear undo history when loading new document
        historyManager.clearHistory()

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

    // MARK: - Annotation Handling

    /// Handle tap gesture (for stamps)
    func handleTap(at screenPoint: CGPoint, in pdfView: PDFView) {
        currentPDFView = pdfView

        guard selectedTool == .stamp else { return }
        guard let page = pdfView.page(for: screenPoint, nearest: true) else { return }

        let annotation: PDFAnnotation?

        // Check if a custom stamp is selected
        if let customStamp = selectedCustomStamp {
            annotation = PDFAnnotationHelper.addCustomStamp(
                to: page,
                at: screenPoint,
                in: pdfView,
                customStamp: customStamp
            )
        } else {
            annotation = PDFAnnotationHelper.addStamp(
                to: page,
                at: screenPoint,
                in: pdfView,
                stampType: selectedStampType
            )
        }

        if let annotation = annotation {
            historyManager.recordAnnotation(annotation, on: page)
            hasUnsavedChanges = true
            currentFile.localStatus = .stamped
            canUndo = historyManager.canUndo
        }
    }

    /// Handle text input from alert
    func handleTextInput(text: String, at screenPoint: CGPoint, in pdfView: PDFView) {
        currentPDFView = pdfView
        guard let page = pdfView.page(for: screenPoint, nearest: true) else { return }

        if let annotation = PDFAnnotationHelper.addTextAnnotationWithBackground(
            to: page,
            at: screenPoint,
            in: pdfView,
            text: text,
            fontSize: 14,
            textColor: selectedColor.uiColor,
            backgroundColor: UIColor.white.withAlphaComponent(0.9)
        ) {
            historyManager.recordAnnotation(annotation, on: page)
            hasUnsavedChanges = true
            canUndo = historyManager.canUndo
        }
    }

    /// Handle completed drawing path (pen or highlight)
    func handleDrawingComplete(path: DrawingPath, in pdfView: PDFView) {
        currentPDFView = pdfView

        guard let page = pdfView.page(for: path.points.first ?? .zero, nearest: true) else { return }

        let annotation: PDFAnnotation?

        if path.isHighlight {
            annotation = PDFAnnotationHelper.addHighlightAnnotation(
                to: page,
                path: path,
                pdfView: pdfView
            )
        } else {
            annotation = PDFAnnotationHelper.addSmoothInkAnnotation(
                to: page,
                path: path,
                pdfView: pdfView
            )
        }

        if let annotation = annotation {
            historyManager.recordAnnotation(annotation, on: page)
            hasUnsavedChanges = true
            canUndo = historyManager.canUndo
        }
    }

    /// Add custom stamp
    func addCustomStamp(_ stamp: CustomStamp) {
        customStamps.append(stamp)
    }

    // MARK: - Undo

    func undo() {
        if historyManager.undo() {
            hasUnsavedChanges = true
            canUndo = historyManager.canUndo
        }
    }

    // MARK: - Legacy Stamp Mode

    func handleStampTap(at screenPoint: CGPoint, in pdfView: PDFView) {
        handleTap(at: screenPoint, in: pdfView)
    }

    func toggleStampMode() {
        isStampModeEnabled.toggle()
    }

    // MARK: - Save

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

    // MARK: - Navigation

    func navigateToNext() async {
        guard var context = folderContext, context.hasNext else { return }

        if let nextFile = context.goNext() {
            folderContext = context
            currentFile = nextFile
            originalETag = nextFile.eTag
            hasUnsavedChanges = false
            historyManager.clearHistory()
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
            historyManager.clearHistory()
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
        historyManager.clearHistory()
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
