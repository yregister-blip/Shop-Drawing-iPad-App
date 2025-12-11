//
//  PDFTopToolbarView.swift
//  QualicoPDFMarkup
//
//  Slim top toolbar for full-screen PDF viewer
//

import SwiftUI

struct PDFTopToolbarView: View {
    let filename: String
    let positionDisplay: String
    let onMenuTapped: () -> Void
    let onSettingsTapped: () -> Void
    let onSaveTapped: () -> Void
    let hasUnsavedChanges: Bool
    let isSaving: Bool

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                // Left: Hamburger menu button
                Button(action: onMenuTapped) {
                    HStack(spacing: 6) {
                        Image(systemName: "line.3.horizontal")
                            .font(.title2)
                        Text("Files")
                            .font(.subheadline)
                    }
                    .foregroundColor(.primary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Color(UIColor.secondarySystemBackground))
                    .cornerRadius(8)
                }

                Spacer()

                // Center: Filename
                VStack(spacing: 2) {
                    Text(filename)
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .lineLimit(1)
                        .truncationMode(.middle)

                    // Position counter
                    if !positionDisplay.isEmpty {
                        Text(positionDisplay)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .monospacedDigit()
                    }
                }
                .frame(maxWidth: .infinity)

                Spacer()

                // Right: Save button and settings menu
                HStack(spacing: 12) {
                    // Save button (only shows when there are unsaved changes)
                    if isSaving {
                        ProgressView()
                            .frame(width: 44, height: 44)
                    } else if hasUnsavedChanges {
                        Button(action: onSaveTapped) {
                            Image(systemName: "square.and.arrow.down.fill")
                                .font(.title2)
                                .foregroundColor(.blue)
                                .frame(width: 44, height: 44)
                        }
                    }

                    // Settings menu button
                    Button(action: onSettingsTapped) {
                        Image(systemName: "ellipsis.circle")
                            .font(.title2)
                            .foregroundColor(.primary)
                            .frame(width: 44, height: 44)
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color(UIColor.systemBackground))

            Divider()
        }
    }
}
