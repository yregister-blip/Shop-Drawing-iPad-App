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

    // Annotation selection state
    @State private var selectedAnnotation: PDFAnnotation? = nil
    @State private var selectedAnnotationPage: PDFPage? = nil
    @State private var showDeleteConfirmation = false

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
                    selectedColor: viewModel.selectedColorBinding,
                    selectedLineWidth: viewModel.selectedLineWidthBinding,
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
                    },
                    showHyperlinks: $viewModel.showHyperlinks,
                    onToggleHyperlinks: {
                        viewModel.toggleHyperlinkVisibility()
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
                        showHyperlinks: viewModel.showHyperlinks,
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
                        },
                        onAnnotationSelected: { annotation, page in
                            withAnimation(.easeInOut(duration: 0.2)) {
                                selectedAnnotation = annotation
                                selectedAnnotationPage = page
                            }
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
                        customStamp: viewModel.selectedTool == .stamp ? viewModel.selectedCustomStamp : nil,
                        color: viewModel.selectedTool == .pen ? viewModel.selectedColor : nil
                    )
                    .padding(.bottom, 30)
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .animation(.easeInOut(duration: 0.2), value: viewModel.selectedTool)
            }

            // Annotation selection indicator (floating at bottom)
            if selectedAnnotation != nil && viewModel.selectedTool == .none {
                VStack {
                    Spacer()
                    AnnotationSelectionBar(
                        onDelete: {
                            showDeleteConfirmation = true
                        },
                        onDeselect: {
                            withAnimation {
                                selectedAnnotation = nil
                                selectedAnnotationPage = nil
                            }
                        }
                    )
                    .padding(.bottom, 30)
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .animation(.easeInOut(duration: 0.2), value: selectedAnnotation != nil)
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
        .alert("Delete Annotation", isPresented: $showDeleteConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Delete", role: .destructive) {
                if let annotation = selectedAnnotation, let page = selectedAnnotationPage {
                    viewModel.deleteAnnotation(annotation, from: page)
                    withAnimation {
                        selectedAnnotation = nil
                        selectedAnnotationPage = nil
                    }
                }
            }
        } message: {
            Text("Are you sure you want to delete this annotation? This action cannot be undone.")
        }
        .task {
            viewModel.setGraphService(authManager: authManager)
            await viewModel.loadPDF()
        }
        .onChange(of: viewModel.selectedTool) { _ in
            // Clear selection when switching tools
            if viewModel.selectedTool != .none {
                selectedAnnotation = nil
                selectedAnnotationPage = nil
            }
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

// MARK: - Annotation Selection Bar

struct AnnotationSelectionBar: View {
    let onDelete: () -> Void
    let onDeselect: () -> Void

    var body: some View {
        HStack(spacing: 16) {
            // Selection indicator
            HStack(spacing: 8) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.white)
                Text("Annotation Selected")
                    .font(.subheadline)
                    .foregroundColor(.white)
            }

            Divider()
                .frame(height: 20)
                .background(Color.white.opacity(0.5))

            // Delete button
            Button(action: onDelete) {
                HStack(spacing: 4) {
                    Image(systemName: "trash")
                        .font(.subheadline)
                    Text("Delete")
                        .font(.subheadline)
                }
                .foregroundColor(.white)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Color.red.opacity(0.8))
                .cornerRadius(8)
            }

            // Deselect button
            Button(action: onDeselect) {
                Image(systemName: "xmark.circle.fill")
                    .font(.title3)
                    .foregroundColor(.white.opacity(0.8))
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(BrandColors.darkGray.opacity(0.9))
        .cornerRadius(20)
        .shadow(radius: 4)
    }
}

struct PDFKitView: UIViewRepresentable {
    let document: PDFDocument
    let selectedTool: AnnotationTool
    let selectedColor: DrawingColor
    let selectedLineWidth: LineWidth
    let showHyperlinks: Bool
    let onTap: (CGPoint, PDFView) -> Void
    let onTextTap: (CGPoint, PDFView) -> Void
    let onDrawingComplete: (DrawingPath, PDFView) -> Void
    var onAnnotationSelected: ((PDFAnnotation?, PDFPage?) -> Void)?

    func makeUIView(context: Context) -> PDFView {
        let pdfView = PDFView()
        pdfView.document = document
        pdfView.delegate = context.coordinator  // Assign delegate for link handling
        pdfView.autoScales = true
        pdfView.displayMode = .singlePageContinuous
        pdfView.displayDirection = .vertical

        // Add tap gesture recognizer
        let tapGesture = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleTap(_:)))
        // Allow touches to pass through to PDFKit for link handling
        tapGesture.cancelsTouchesInView = false
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
        context.coordinator.onAnnotationSelected = onAnnotationSelected

        // Update hyperlink highlighting
        context.coordinator.updateHyperlinkOverlay(show: showHyperlinks, in: pdfView)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(
            onTap: onTap,
            onTextTap: onTextTap,
            onDrawingComplete: onDrawingComplete,
            onAnnotationSelected: onAnnotationSelected,
            selectedTool: selectedTool,
            selectedColor: selectedColor,
            selectedLineWidth: selectedLineWidth
        )
    }

    class Coordinator: NSObject, PDFViewDelegate {
        let onTap: (CGPoint, PDFView) -> Void
        let onTextTap: (CGPoint, PDFView) -> Void
        let onDrawingComplete: (DrawingPath, PDFView) -> Void
        var onAnnotationSelected: ((PDFAnnotation?, PDFPage?) -> Void)?

        weak var pdfView: PDFView?
        var selectedTool: AnnotationTool
        var selectedColor: DrawingColor
        var selectedLineWidth: LineWidth

        // Drawing state
        private var currentPath: DrawingPath?
        private var drawingOverlay: DrawingOverlayView?

        // Hyperlink highlighting state
        private var hyperlinkOverlay: HyperlinkOverlayView?

        init(
            onTap: @escaping (CGPoint, PDFView) -> Void,
            onTextTap: @escaping (CGPoint, PDFView) -> Void,
            onDrawingComplete: @escaping (DrawingPath, PDFView) -> Void,
            onAnnotationSelected: ((PDFAnnotation?, PDFPage?) -> Void)?,
            selectedTool: AnnotationTool,
            selectedColor: DrawingColor,
            selectedLineWidth: LineWidth
        ) {
            self.onTap = onTap
            self.onTextTap = onTextTap
            self.onDrawingComplete = onDrawingComplete
            self.onAnnotationSelected = onAnnotationSelected
            self.selectedTool = selectedTool
            self.selectedColor = selectedColor
            self.selectedLineWidth = selectedLineWidth
        }

        // MARK: - PDFViewDelegate

        /// Called when PDFKit is about to open a link - verify PDFKit sees the link
        func pdfViewWillClick(onLink sender: PDFView, with url: URL) {
            print("🔗 PDFKit is attempting to open URL: \(url.absoluteString)")
        }

        @objc func handleTap(_ gesture: UITapGestureRecognizer) {
            guard let pdfView = pdfView else { return }
            let point = gesture.location(in: pdfView)

            // IMPROVED LINK DETECTION using PDFKit's native hit testing
            if let page = pdfView.page(for: point, nearest: false) {
                let pagePoint = pdfView.convert(point, to: page)

                // Use PDFKit's native hit testing
                if let hitAnnotation = page.annotation(at: pagePoint) {
                    // Debug Log: See exactly what we are tapping
                    print("👇 Tapped Annotation: Type=\(hitAnnotation.type ?? "nil"), Subtype=\(hitAnnotation.subtype?.rawValue ?? "nil")")

                    // Check for Link OR Widget (Bluebeam sometimes uses Widgets for complex links)
                    if hitAnnotation.subtype == .link || hitAnnotation.subtype == .widget {
                        print("🔗 Link/Widget detected - Passing control to PDFKit")
                        return
                    }
                }
            }

            switch selectedTool {
            case .text:
                onTextTap(point, pdfView)
            case .stamp:
                onTap(point, pdfView)
            case .none:
                // In pan/select mode, check for annotation selection
                if let page = pdfView.page(for: point, nearest: true) {
                    let pagePoint = pdfView.convert(point, to: page)

                    // Check for markup annotations (Ink, FreeText, Stamp, Highlight, etc.)
                    // Exclude standard PDF annotations like Link, Widget
                    let markupTypes = ["Ink", "FreeText", "Stamp", "Highlight", "Underline", "StrikeOut", "Square", "Circle", "Line"]

                    for annotation in page.annotations.reversed() { // Reverse to get topmost first
                        if markupTypes.contains(annotation.type ?? "") {
                            // Expand bounds slightly for easier selection
                            let expandedBounds = annotation.bounds.insetBy(dx: -10, dy: -10)
                            if expandedBounds.contains(pagePoint) {
                                onAnnotationSelected?(annotation, page)
                                return
                            }
                        }
                    }

                    // No annotation found - deselect
                    onAnnotationSelected?(nil, nil)
                }
            case .pen, .highlight:
                // For pen/highlight, tap does nothing (drawing is handled by pan)
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

        // MARK: - Hyperlink Overlay

        func updateHyperlinkOverlay(show: Bool, in pdfView: PDFView) {
            if show {
                if hyperlinkOverlay == nil {
                    let overlay = HyperlinkOverlayView(pdfView: pdfView)
                    overlay.frame = pdfView.bounds
                    overlay.autoresizingMask = [.flexibleWidth, .flexibleHeight]
                    overlay.isUserInteractionEnabled = false
                    pdfView.addSubview(overlay)
                    hyperlinkOverlay = overlay

                    // Listen for scroll/zoom changes to update overlay
                    NotificationCenter.default.addObserver(
                        forName: .PDFViewPageChanged,
                        object: pdfView,
                        queue: .main
                    ) { [weak overlay] _ in
                        overlay?.setNeedsDisplay()
                    }

                    NotificationCenter.default.addObserver(
                        forName: .PDFViewScaleChanged,
                        object: pdfView,
                        queue: .main
                    ) { [weak overlay] _ in
                        overlay?.setNeedsDisplay()
                    }
                }
                hyperlinkOverlay?.setNeedsDisplay()
            } else {
                hyperlinkOverlay?.removeFromSuperview()
                hyperlinkOverlay = nil
            }
        }
    }
}

// MARK: - Hyperlink Overlay View

/// Overlay view that highlights all hyperlinks in the PDF
class HyperlinkOverlayView: UIView {
    weak var pdfView: PDFView?

    init(pdfView: PDFView) {
        self.pdfView = pdfView
        super.init(frame: pdfView.bounds)
        backgroundColor = .clear
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func draw(_ rect: CGRect) {
        guard let pdfView = pdfView,
              let document = pdfView.document,
              let context = UIGraphicsGetCurrentContext() else { return }

        // Get visible pages
        let visibleRect = pdfView.bounds

        for pageIndex in 0..<document.pageCount {
            guard let page = document.page(at: pageIndex) else { continue }

            // Check each annotation on the page
            for annotation in page.annotations {
                // Only highlight Link and Widget annotations
                guard annotation.subtype == .link || annotation.subtype == .widget else { continue }

                // Convert annotation bounds to view coordinates
                let pageRect = annotation.bounds
                let viewRect = pdfView.convert(pageRect, from: page)

                // Only draw if visible
                guard viewRect.intersects(visibleRect) else { continue }

                // Determine highlight color based on link status
                let hasDestination = annotation.url != nil ||
                                   annotation.destination != nil ||
                                   annotation.action != nil

                if hasDestination {
                    // Green for working links
                    context.setFillColor(UIColor.systemGreen.withAlphaComponent(0.3).cgColor)
                    context.setStrokeColor(UIColor.systemGreen.cgColor)
                } else {
                    // Red for broken links (no destination)
                    context.setFillColor(UIColor.systemRed.withAlphaComponent(0.3).cgColor)
                    context.setStrokeColor(UIColor.systemRed.cgColor)
                }

                context.setLineWidth(2)

                // Draw filled rectangle with border
                context.fill(viewRect)
                context.stroke(viewRect)

                // Add a small indicator in the corner
                let indicatorSize: CGFloat = 12
                let indicatorRect = CGRect(
                    x: viewRect.maxX - indicatorSize - 2,
                    y: viewRect.minY + 2,
                    width: indicatorSize,
                    height: indicatorSize
                )

                if hasDestination {
                    context.setFillColor(UIColor.systemGreen.cgColor)
                } else {
                    context.setFillColor(UIColor.systemRed.cgColor)
                }
                context.fillEllipse(in: indicatorRect)

                // Draw checkmark or X
                context.setStrokeColor(UIColor.white.cgColor)
                context.setLineWidth(1.5)

                if hasDestination {
                    // Checkmark
                    let checkPath = UIBezierPath()
                    checkPath.move(to: CGPoint(x: indicatorRect.minX + 3, y: indicatorRect.midY))
                    checkPath.addLine(to: CGPoint(x: indicatorRect.midX - 1, y: indicatorRect.maxY - 3))
                    checkPath.addLine(to: CGPoint(x: indicatorRect.maxX - 3, y: indicatorRect.minY + 3))
                    context.addPath(checkPath.cgPath)
                    context.strokePath()
                } else {
                    // X mark
                    context.move(to: CGPoint(x: indicatorRect.minX + 3, y: indicatorRect.minY + 3))
                    context.addLine(to: CGPoint(x: indicatorRect.maxX - 3, y: indicatorRect.maxY - 3))
                    context.move(to: CGPoint(x: indicatorRect.maxX - 3, y: indicatorRect.minY + 3))
                    context.addLine(to: CGPoint(x: indicatorRect.minX + 3, y: indicatorRect.maxY - 3))
                    context.strokePath()
                }
            }
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

// MARK: - Tool Settings

/// Individual settings for each annotation tool
struct ToolSettings {
    var color: DrawingColor
    var width: LineWidth

    static let defaultPen = ToolSettings(color: .black, width: .medium)
    static let defaultHighlight = ToolSettings(color: .yellow, width: .thick)
    static let defaultText = ToolSettings(color: .black, width: .medium)
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
    @Published var customStamps: [CustomStamp] = []

    // Hyperlink debugging
    @Published var showHyperlinks: Bool = false

    // Independent tool settings - each tool remembers its own color and width
    @Published var toolSettings: [AnnotationTool: ToolSettings] = [
        .pen: .defaultPen,
        .highlight: .defaultHighlight,
        .text: .defaultText
    ]

    // Computed properties for current tool's settings (used by UI bindings)
    var selectedColor: DrawingColor {
        get { toolSettings[selectedTool]?.color ?? .black }
        set {
            if toolSettings[selectedTool] != nil {
                toolSettings[selectedTool]?.color = newValue
            } else {
                toolSettings[selectedTool] = ToolSettings(color: newValue, width: .medium)
            }
        }
    }

    var selectedLineWidth: LineWidth {
        get { toolSettings[selectedTool]?.width ?? .medium }
        set {
            if toolSettings[selectedTool] != nil {
                toolSettings[selectedTool]?.width = newValue
            } else {
                toolSettings[selectedTool] = ToolSettings(color: .black, width: newValue)
            }
        }
    }

    // Binding wrappers for SwiftUI
    var selectedColorBinding: Binding<DrawingColor> {
        Binding(
            get: { self.selectedColor },
            set: { self.selectedColor = $0 }
        )
    }

    var selectedLineWidthBinding: Binding<LineWidth> {
        Binding(
            get: { self.selectedLineWidth },
            set: { self.selectedLineWidth = $0 }
        )
    }

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

                // Analyze hyperlinks in the document for debugging
                analyzeHyperlinks(in: document)

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

    // MARK: - Delete Annotation

    /// Deletes a specific annotation from its page
    func deleteAnnotation(_ annotation: PDFAnnotation, from page: PDFPage) {
        page.removeAnnotation(annotation)
        hasUnsavedChanges = true
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
            // Get PDF data - use explicit empty options to ensure all properties are preserved
            guard let pdfData = document.dataRepresentation(options: [:]) else {
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

    // MARK: - Hyperlink Analysis

    /// Analyzes and logs all hyperlinks in the PDF document for debugging
    func analyzeHyperlinks(in document: PDFDocument) {
        var linkCount = 0
        var linksWithDestinations = 0
        var linksWithURLs = 0
        var linksWithActions = 0

        print("📄 ========== HYPERLINK ANALYSIS ==========")
        print("📄 Document: \(currentFile.name)")
        print("📄 Page count: \(document.pageCount)")

        for pageIndex in 0..<document.pageCount {
            guard let page = document.page(at: pageIndex) else { continue }

            for annotation in page.annotations {
                // Check for Link annotations
                if annotation.subtype == .link {
                    linkCount += 1
                    print("")
                    print("🔗 Link #\(linkCount) on Page \(pageIndex + 1)")
                    print("   Bounds: \(annotation.bounds)")
                    print("   Type: \(annotation.type ?? "nil")")
                    print("   Subtype: \(annotation.subtype?.rawValue ?? "nil")")

                    // Check for URL action
                    if let url = annotation.url {
                        linksWithURLs += 1
                        print("   ✅ URL: \(url.absoluteString)")
                    } else {
                        print("   ❌ URL: nil")
                    }

                    // Check for destination (internal link)
                    if let destination = annotation.destination {
                        linksWithDestinations += 1
                        print("   ✅ Destination Page: \(destination.page?.label ?? "unknown")")
                        print("   Destination Point: \(destination.point)")
                    } else {
                        print("   ❌ Destination: nil")
                    }

                    // Check for action
                    if let action = annotation.action {
                        linksWithActions += 1
                        print("   ✅ Action Type: \(type(of: action))")

                        // Try to extract more action details
                        if let urlAction = action as? PDFActionURL {
                            print("   Action URL: \(urlAction.url?.absoluteString ?? "nil")")
                        } else if let goToAction = action as? PDFActionGoTo {
                            print("   GoTo Destination: \(goToAction.destination?.page?.label ?? "nil")")
                        } else if let namedAction = action as? PDFActionNamed {
                            print("   Named Action: \(namedAction.name.rawValue)")
                        }
                    } else {
                        print("   ❌ Action: nil")
                    }

                    // Log all annotation dictionary keys for debugging
                    if let annotDict = annotation.annotationKeyValues as? [PDFAnnotationKey: Any] {
                        print("   Keys: \(annotDict.keys.map { $0.rawValue })")
                    }
                }

                // Also check for Widget annotations (Bluebeam sometimes uses these)
                if annotation.subtype == .widget {
                    print("")
                    print("📦 Widget found on Page \(pageIndex + 1)")
                    print("   Bounds: \(annotation.bounds)")
                    print("   Type: \(annotation.type ?? "nil")")
                    if let action = annotation.action {
                        print("   Action Type: \(type(of: action))")
                    }
                }
            }
        }

        print("")
        print("📊 ========== SUMMARY ==========")
        print("📊 Total Links: \(linkCount)")
        print("📊 Links with URLs: \(linksWithURLs)")
        print("📊 Links with Destinations: \(linksWithDestinations)")
        print("📊 Links with Actions: \(linksWithActions)")
        print("📊 ===============================")
    }

    /// Toggles hyperlink visibility
    func toggleHyperlinkVisibility() {
        showHyperlinks.toggle()
        if showHyperlinks, let document = pdfDocument {
            print("🔍 Hyperlink highlighting enabled")
            analyzeHyperlinks(in: document)
        } else {
            print("🔍 Hyperlink highlighting disabled")
        }
    }
}
