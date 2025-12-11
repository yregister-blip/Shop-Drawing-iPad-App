//
//  PDFTopToolbarView.swift
//  QualicoPDFMarkup
//
//  Top toolbar with all controls - navigation, stamp mode, save, and menu
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

    // Stamp mode
    @Binding var isStampModeEnabled: Bool
    @Binding var selectedStampType: StampType

    // Save
    let onSaveTapped: () -> Void
    let hasUnsavedChanges: Bool
    let isSaving: Bool

    @State private var showStampPicker = false

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                // Left side: Back button, Navigation
                leftControls

                Spacer()

                // Center: Filename
                centerContent

                Spacer()

                // Right side: Stamp mode, Save, More menu
                rightControls
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color(UIColor.systemBackground))

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

    // MARK: - Center Content

    private var centerContent: some View {
        VStack(spacing: 2) {
            Text(filename)
                .font(.subheadline)
                .fontWeight(.medium)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .frame(maxWidth: 300)
    }

    // MARK: - Right Controls

    private var rightControls: some View {
        HStack(spacing: 8) {
            // Stamp Mode Toggle with indicator
            stampModeButton

            // Save button
            saveButton

            // More menu
            moreMenuButton
        }
    }

    private var stampModeButton: some View {
        Button(action: {
            isStampModeEnabled.toggle()
        }) {
            HStack(spacing: 6) {
                Image(systemName: isStampModeEnabled ? "hand.tap.fill" : "hand.tap")
                    .font(.body)
                Text(isStampModeEnabled ? "Stamping" : "Stamp")
                    .font(.subheadline)
            }
            .foregroundColor(isStampModeEnabled ? .white : .primary)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(isStampModeEnabled ? Color.blue : Color(UIColor.secondarySystemBackground))
            .cornerRadius(8)
        }
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
            // Stamp Selection submenu
            Menu {
                ForEach(StampType.allCases, id: \.self) { stampType in
                    Button(action: {
                        selectedStampType = stampType
                    }) {
                        HStack {
                            Text(stampType.rawValue)
                            if selectedStampType == stampType {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            } label: {
                Label("Stamp Type", systemImage: "stamp")
            }

            Divider()

            // Annotations submenu (for future)
            Menu {
                Button(action: {}) {
                    Label("Text (Coming Soon)", systemImage: "textformat")
                }
                .disabled(true)

                Button(action: {}) {
                    Label("Ink (Coming Soon)", systemImage: "pencil.tip")
                }
                .disabled(true)
            } label: {
                Label("Annotations", systemImage: "pencil.and.outline")
            }
        } label: {
            Image(systemName: "ellipsis.circle")
                .font(.title2)
                .foregroundColor(.primary)
                .frame(width: 40, height: 40)
        }
    }
}

// MARK: - Stamp Mode Indicator Overlay

struct StampModeIndicator: View {
    let stampType: StampType

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "hand.tap.fill")
                .foregroundColor(.white)
            Text("Tap to place \(stampType.rawValue)")
                .font(.subheadline)
                .foregroundColor(.white)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color.blue.opacity(0.9))
        .cornerRadius(20)
        .shadow(radius: 4)
    }
}
