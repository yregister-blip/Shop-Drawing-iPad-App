//
//  StampToolbarView.swift
//  QualicoPDFMarkup
//
//  Toolbar for stamping and navigation controls
//

import SwiftUI

struct StampToolbarView: View {
    @ObservedObject var viewModel: PDFViewerViewModel

    var body: some View {
        VStack(spacing: 0) {
            Divider()

            HStack {
                // Navigation controls
                Button(action: {
                    Task {
                        await viewModel.navigateToPrevious()
                    }
                }) {
                    Image(systemName: "chevron.left")
                        .font(.title2)
                        .frame(width: 44, height: 44)
                }
                .disabled(!viewModel.canNavigatePrevious)

                Text(viewModel.positionDisplay)
                    .font(.subheadline)
                    .monospacedDigit()
                    .frame(minWidth: 80)
                    .foregroundColor(.secondary)

                Button(action: {
                    Task {
                        await viewModel.navigateToNext()
                    }
                }) {
                    Image(systemName: "chevron.right")
                        .font(.title2)
                        .frame(width: 44, height: 44)
                }
                .disabled(!viewModel.canNavigateNext)

                Spacer()

                // Stamp indicator
                VStack(spacing: 2) {
                    Image(systemName: "hand.tap.fill")
                        .font(.title2)
                        .foregroundColor(.blue)
                    Text("Tap to Stamp")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }

                Spacer()

                // Save indicator
                if viewModel.hasUnsavedChanges {
                    VStack(spacing: 2) {
                        Image(systemName: "circle.fill")
                            .font(.caption)
                            .foregroundColor(.orange)
                        Text("Unsaved")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                } else {
                    VStack(spacing: 2) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.title3)
                            .foregroundColor(.green)
                        Text("Saved")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
            .background(Color(UIColor.systemBackground))
        }
    }
}
