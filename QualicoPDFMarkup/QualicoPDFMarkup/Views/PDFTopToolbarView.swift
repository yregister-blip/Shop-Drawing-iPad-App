//
//  PDFTopToolbarView.swift
//  QualicoPDFMarkup
//
//  Top toolbar with all controls - navigation, annotation tools, save, and menu
//

import SwiftUI

struct PDFTopToolbarView: View {
    let filename: String
    let positionDisplay: String

    // Navigation
    let canNavigatePrevious: Bool
    let canNavigateNext: Bool
    let onPreviousTapped: () -> Void
    let onNextTapped: () -> Void

    // File list
    let onMenuTapped: () -> Void

    // Annotation tools
    @Binding var selectedTool: AnnotationTool
    @Binding var selectedStampType: StampType
    @Binding var selectedColor: DrawingColor
    @Binding var selectedLineWidth: LineWidth

    // Undo
    let canUndo: Bool
    let onUndoTapped: () -> Void

    // Save
    let onSaveTapped: () -> Void
    let hasUnsavedChanges: Bool
    let isSaving: Bool

    // Custom stamps
    @Binding var customStamps: [CustomStamp]
    @Binding var selectedCustomStamp: CustomStamp?
    let onAddCustomStamp: () -> Void

    @State private var showStampPicker = false
    @State private var showColorPicker = false
    @State private var showLineWidthPicker = false

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                // Left side: Back button, Navigation
                leftControls

                Spacer()

                // Center: Annotation tools
                annotationToolbar

                Spacer()

                // Right side: Undo, Save, More menu
                rightControls
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color(UIColor.systemBackground))

            // Secondary toolbar for tool options (when a drawing tool is selected)
            if selectedTool == .pen || selectedTool == .highlight {
                drawingOptionsBar
            }

            Divider()
        }
    }

    // MARK: - Left Controls

    private var leftControls: some View {
        HStack(spacing: 8) {
            // Files/Menu button
            Button(action: onMenuTapped) {
                HStack(spacing: 4) {
                    Image(systemName: "line.3.horizontal")
                        .font(.body)
                    Text("Files")
                        .font(.subheadline)
                }
                .foregroundColor(.primary)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Color(UIColor.secondarySystemBackground))
                .cornerRadius(6)
            }

            // Navigation group
            HStack(spacing: 4) {
                Button(action: onPreviousTapped) {
                    Image(systemName: "chevron.left")
                        .font(.body.weight(.semibold))
                        .foregroundColor(canNavigatePrevious ? .blue : .secondary.opacity(0.5))
                        .frame(width: 36, height: 36)
                }
                .disabled(!canNavigatePrevious)

                Text(positionDisplay)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .monospacedDigit()
                    .frame(minWidth: 50)

                Button(action: onNextTapped) {
                    Image(systemName: "chevron.right")
                        .font(.body.weight(.semibold))
                        .foregroundColor(canNavigateNext ? .blue : .secondary.opacity(0.5))
                        .frame(width: 36, height: 36)
                }
                .disabled(!canNavigateNext)
            }
            .padding(.horizontal, 4)
            .background(Color(UIColor.secondarySystemBackground))
            .cornerRadius(6)
        }
    }

    // MARK: - Annotation Toolbar (Center)

    private var annotationToolbar: some View {
        HStack(spacing: 4) {
            // Pan/Select tool (no annotation)
            toolButton(for: .none)

            Divider()
                .frame(height: 24)

            // Stamp tool
            toolButton(for: .stamp)

            // Pen tool
            toolButton(for: .pen)

            // Highlight tool
            toolButton(for: .highlight)

            // Text tool
            toolButton(for: .text)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color(UIColor.secondarySystemBackground))
        .cornerRadius(8)
    }

    private func toolButton(for tool: AnnotationTool) -> some View {
        Button(action: {
            selectedTool = tool
        }) {
            Image(systemName: selectedTool == tool ? tool.activeIconName : tool.iconName)
                .font(.body)
                .foregroundColor(selectedTool == tool ? .white : .primary)
                .frame(width: 36, height: 36)
                .background(selectedTool == tool ? Color.blue : Color.clear)
                .cornerRadius(6)
        }
        .help(tool.label)
    }

    // MARK: - Drawing Options Bar (Secondary)

    private var drawingOptionsBar: some View {
        HStack(spacing: 16) {
            // Color picker
            Menu {
                ForEach(DrawingColor.allCases) { color in
                    Button(action: {
                        selectedColor = color
                    }) {
                        HStack {
                            Circle()
                                .fill(Color(color.uiColor))
                                .frame(width: 16, height: 16)
                            Text(color.rawValue)
                            if selectedColor == color {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            } label: {
                HStack(spacing: 4) {
                    Circle()
                        .fill(Color(selectedColor.uiColor))
                        .frame(width: 20, height: 20)
                        .overlay(
                            Circle()
                                .stroke(Color.gray, lineWidth: 1)
                        )
                    Text("Color")
                        .font(.caption)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color(UIColor.tertiarySystemBackground))
                .cornerRadius(6)
            }

            // Line width picker
            Menu {
                ForEach(LineWidth.allCases) { width in
                    Button(action: {
                        selectedLineWidth = width
                    }) {
                        HStack {
                            RoundedRectangle(cornerRadius: 2)
                                .fill(Color.primary)
                                .frame(width: 30, height: selectedTool == .highlight ? width.highlightWidth / 2 : width.rawValue * 2)
                            Text(width.displayName)
                            if selectedLineWidth == width {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            } label: {
                HStack(spacing: 4) {
                    RoundedRectangle(cornerRadius: 1)
                        .fill(Color.primary)
                        .frame(width: 20, height: selectedTool == .highlight ? selectedLineWidth.highlightWidth / 3 : selectedLineWidth.rawValue * 1.5)
                    Text("Width")
                        .font(.caption)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color(UIColor.tertiarySystemBackground))
                .cornerRadius(6)
            }

            Spacer()

            // Filename display
            Text(filename)
                .font(.caption)
                .foregroundColor(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: 200)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
        .background(Color(UIColor.secondarySystemBackground).opacity(0.5))
    }

    // MARK: - Right Controls

    private var rightControls: some View {
        HStack(spacing: 8) {
            // Undo button
            undoButton

            // Save button
            saveButton

            // More menu
            moreMenuButton
        }
    }

    private var undoButton: some View {
        Button(action: onUndoTapped) {
            Image(systemName: "arrow.uturn.backward")
                .font(.body)
                .foregroundColor(canUndo ? .blue : .secondary.opacity(0.5))
                .frame(width: 36, height: 36)
        }
        .disabled(!canUndo)
        .help("Undo last annotation")
    }

    @ViewBuilder
    private var saveButton: some View {
        if isSaving {
            ProgressView()
                .frame(width: 40, height: 40)
        } else {
            Button(action: onSaveTapped) {
                Image(systemName: hasUnsavedChanges ? "square.and.arrow.down.fill" : "square.and.arrow.down")
                    .font(.title3)
                    .foregroundColor(hasUnsavedChanges ? .blue : .secondary)
                    .frame(width: 40, height: 40)
            }
            .disabled(!hasUnsavedChanges)
        }
    }

    private var moreMenuButton: some View {
        Menu {
            // Stamp Type Selection submenu
            Menu {
                ForEach(StampType.allCases, id: \.self) { stampType in
                    Button(action: {
                        selectedStampType = stampType
                        selectedCustomStamp = nil  // Clear custom stamp selection
                        selectedTool = .stamp
                    }) {
                        HStack {
                            Text(stampType.rawValue)
                            if selectedStampType == stampType && selectedCustomStamp == nil {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }

                if !customStamps.isEmpty {
                    Divider()

                    ForEach(customStamps) { stamp in
                        Button(action: {
                            selectedCustomStamp = stamp
                            selectedTool = .stamp
                        }) {
                            HStack {
                                Text(stamp.name)
                                if selectedCustomStamp?.id == stamp.id {
                                    Image(systemName: "checkmark")
                                }
                                Image(systemName: "star.fill")
                                    .foregroundColor(.yellow)
                            }
                        }
                    }
                }

                Divider()

                Button(action: onAddCustomStamp) {
                    Label("Create Custom Stamp...", systemImage: "plus.circle")
                }
            } label: {
                Label("Stamp Type", systemImage: "stamp")
            }

            Divider()

            // Position display
            if !positionDisplay.isEmpty {
                Text("Position: \(positionDisplay)")
                    .font(.caption)
            }
        } label: {
            Image(systemName: "ellipsis.circle")
                .font(.title2)
                .foregroundColor(.primary)
                .frame(width: 40, height: 40)
        }
    }
}

// MARK: - Tool Mode Indicator Overlay

struct ToolModeIndicator: View {
    let tool: AnnotationTool
    let stampType: StampType?
    let color: DrawingColor?

    init(tool: AnnotationTool, stampType: StampType? = nil, color: DrawingColor? = nil) {
        self.tool = tool
        self.stampType = stampType
        self.color = color
    }

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: tool.activeIconName)
                .foregroundColor(.white)
            Text(instructionText)
                .font(.subheadline)
                .foregroundColor(.white)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(backgroundColor.opacity(0.9))
        .cornerRadius(20)
        .shadow(radius: 4)
    }

    private var instructionText: String {
        switch tool {
        case .none:
            return "Pan and zoom"
        case .stamp:
            if let stampType = stampType {
                return "Tap to place \(stampType.rawValue)"
            }
            return "Tap to place stamp"
        case .pen:
            return "Draw to annotate"
        case .highlight:
            return "Draw to highlight"
        case .text:
            return "Tap to add text"
        }
    }

    private var backgroundColor: Color {
        switch tool {
        case .none:
            return .gray
        case .stamp:
            return .blue
        case .pen:
            if let color = color {
                return Color(color.uiColor)
            }
            return .black
        case .highlight:
            return .yellow
        case .text:
            return .green
        }
    }
}

// Legacy support - keep StampModeIndicator for backward compatibility
struct StampModeIndicator: View {
    let stampType: StampType

    var body: some View {
        ToolModeIndicator(tool: .stamp, stampType: stampType)
    }
}
