//
//  StampToolbarView.swift
//  QualicoPDFMarkup
//
//  Bottom toolbar for navigation, stamping indicator, and save status
//  Styled with Qualico brand colors
//

import SwiftUI

struct StampToolbarView: View {
    @ObservedObject var viewModel: PDFViewerViewModel

    var body: some View {
        VStack(spacing: 0) {
            Divider()

            HStack {
                // Left: Previous button
                Button(action: {
                    Task {
                        await viewModel.navigateToPrevious()
                    }
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.left")
                            .font(.body.weight(.semibold))
                        Text("Previous")
                            .font(.subheadline)
                    }
                    .foregroundColor(viewModel.canNavigatePrevious ? BrandColors.primaryRed : BrandColors.lightGray)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(Color(UIColor.secondarySystemBackground))
                    .cornerRadius(8)
                }
                .disabled(!viewModel.canNavigatePrevious)

                Spacer()

                // Center: Tap to Stamp indicator
                VStack(spacing: 4) {
                    Image(systemName: "hand.tap.fill")
                        .font(.title2)
                        .foregroundColor(BrandColors.primaryRed)
                    Text("Tap to Stamp")
                        .font(.caption)
                        .foregroundColor(BrandColors.darkGray)
                }
                .frame(minWidth: 100)

                Spacer()

                // Right: Next button and save indicator
                HStack(spacing: 16) {
                    Button(action: {
                        Task {
                            await viewModel.navigateToNext()
                        }
                    }) {
                        HStack(spacing: 4) {
                            Text("Next")
                                .font(.subheadline)
                            Image(systemName: "chevron.right")
                                .font(.body.weight(.semibold))
                        }
                        .foregroundColor(viewModel.canNavigateNext ? BrandColors.primaryRed : BrandColors.lightGray)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(Color(UIColor.secondarySystemBackground))
                        .cornerRadius(8)
                    }
                    .disabled(!viewModel.canNavigateNext)

                    // Save status indicator
                    saveStatusIndicator
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(Color(UIColor.systemBackground))
        }
    }

    @ViewBuilder
    private var saveStatusIndicator: some View {
        if viewModel.hasUnsavedChanges {
            HStack(spacing: 4) {
                Image(systemName: "circle.fill")
                    .font(.caption)
                    .foregroundColor(.orange)
                Text("Unsaved")
                    .font(.caption)
                    .foregroundColor(BrandColors.darkGray)
            }
        } else {
            HStack(spacing: 4) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.body)
                    .foregroundColor(BrandColors.primaryRed)
                Text("Saved")
                    .font(.caption)
                    .foregroundColor(BrandColors.darkGray)
            }
        }
    }
}
